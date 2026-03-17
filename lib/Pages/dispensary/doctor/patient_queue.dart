// lib/pages/patient_queue.dart
// FIXES:
//   1. _showPrescriptionDialog now reads from local Hive prescriptions first,
//      falls back to Firestore, and on save writes to BOTH Hive AND Firestore.
//   2. RealtimeManager broadcast uses correct RealtimeEvents.payload() structure
//      with branchId at top level (not nested inside data).
//   3. Removed FieldValue.serverTimestamp() from realtime payload — not serialisable.
//   4. Entry status updated in local Hive after prescription edit.
//
// QUEUE TYPE FIX (Bug 3):
//   • _updateFirestore no longer has a hardcoded 'zakat' fallback.
//   • _normaliseQueueType() is the single resolver — mirrors all other files.
//   • queueType is resolved from entryData → prescData → patient map, in order,
//     then normalised before being used in any Firestore write path.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../services/local_storage_service.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';

class PatientQueue extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? selectedPatient;
  final Function(Map<String, dynamic>) onPatientSelected;
  final bool isSaving;

  const PatientQueue({
    super.key,
    required this.branchId,
    this.selectedPatient,
    required this.onPatientSelected,
    this.isSaving = false,
  });

  @override
  State<PatientQueue> createState() => _PatientQueueState();
}

class _PatientQueueState extends State<PatientQueue>
    with SingleTickerProviderStateMixin {
  static const Color _teal   = Color(0xFF00695C);
  static const Color _amber  = Color(0xFFFFA000);
  static const Color _purple = Color(0xFF6A1B9A);

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  String _filter = 'all';
  final String _todayKey = DateFormat('ddMMyy').format(DateTime.now());

  late StreamSubscription<Map<String, dynamic>> _realtimeSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  bool _isOnline = true;

  // ─── Queue-type normaliser (FIX: single source of truth) ─────────────────
  /// Mirrors _resolveQueueType in token_screen / sync_service / server_sync_manager.
  static String _normaliseQueueType(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) return 'non-zakat';
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf')
      return 'gmwf';
    return 'zakat';
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _realtimeSub = RealtimeManager().messageStream.listen((event) {
      final type = event['event_type'] as String?;
      final data = event['data'] as Map<String, dynamic>?;
      if (!mounted || type == null) return;

      final msgBranch = data?['branchId']?.toString().toLowerCase().trim();
      final myBranch  = widget.branchId.toLowerCase().trim();
      if (msgBranch != null && msgBranch != myBranch) return;

      if (type == RealtimeEvents.saveEntry ||
          type == RealtimeEvents.savePrescription ||
          type == 'dispense_completed') {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryAutoSelectSmallestWaiting();
        });
      }
    });

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (_isOnline != online && mounted) {
        setState(() => _isOnline = online);
        if (online) {
          Future.microtask(() async {
            await _syncQueueFromFirestore();
            if (mounted) {
              setState(() {});
              _tryAutoSelectSmallestWaiting();
            }
          });
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoSelectSmallestWaiting();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _realtimeSub.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  // ─── Serial number extraction ──────────────────────────────────────────────
  int _extractSerialNumber(Map<String, dynamic> p) {
    final s = (p['serial'] ?? p['id'] ?? 'Z-999999').toString();
    final parts = s.split('-');
    return parts.length > 1 ? int.tryParse(parts.last) ?? 999999 : 999999;
  }

  // ─── Strict two-group sort ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _getSortedQueue() {
    final all = LocalStorageService.getLocalEntries(widget.branchId)
        .where((e) => e['dateKey'] == _todayKey)
        .toList();

    final waiting = <Map<String, dynamic>>[];
    final others  = <Map<String, dynamic>>[];

    for (final e in all) {
      final status = (e['status'] ?? '').toString().toLowerCase();
      if (status == 'waiting') waiting.add(e);
      else others.add(e);
    }

    waiting.sort((a, b) => _extractSerialNumber(a).compareTo(_extractSerialNumber(b)));
    others.sort((a, b)  => _extractSerialNumber(a).compareTo(_extractSerialNumber(b)));

    return [...waiting, ...others];
  }

  // ─── Auto-select smallest waiting ─────────────────────────────────────────
  void _tryAutoSelectSmallestWaiting() {
    if (!mounted) return;
    final queue   = _getSortedQueue();
    final waiting = queue
        .where((p) => (p['status'] ?? '').toString().toLowerCase() == 'waiting')
        .toList();
    if (waiting.isEmpty) return;

    final smallest       = waiting.first;
    final smallestSerial = smallest['serial']?.toString() ?? smallest['id']?.toString() ?? '';
    final currentSerial  = widget.selectedPatient?['serial']?.toString() ??
        widget.selectedPatient?['id']?.toString() ?? '';

    final currentIsWaiting = waiting.any((p) =>
        (p['serial']?.toString() ?? p['id']?.toString() ?? '') == currentSerial);

    if (!currentIsWaiting || currentSerial != smallestSerial) {
      debugPrint('[PatientQueue] Auto-selecting smallest waiting: $smallestSerial');
      widget.onPatientSelected({...smallest, 'serial': smallestSerial, 'id': smallestSerial});
    }
  }

  // ─── Firestore sync ────────────────────────────────────────────────────────
  Future<void> _syncQueueFromFirestore() async {
    try {
      final serialsRef = FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId)
          .collection('serials').doc(_todayKey);

      for (final type in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await serialsRef.collection(type).get();
        for (final doc in snap.docs) {
          final data   = doc.data();
          final serial = doc.id;
          Hive.box(LocalStorageService.entriesBox).put('${widget.branchId}-$serial', {
            ...data,
            'serial':    serial,
            'queueType': type,
            'dateKey':   _todayKey,
          });
        }
      }
    } catch (e) {
      debugPrint('[PatientQueue] Firestore sync failed: $e');
    }
  }

  // ─── Medicine abbreviation helper ─────────────────────────────────────────
  String _getMedAbbrev(Map<String, dynamic> med) {
    final rawName = (med['name'] ?? '').toString().trim().toLowerCase();
    final rawType = (med['type'] ?? '').toString().trim().toLowerCase();
    final prefixes = {
      'syrup': 'syp.', 'syp': 'syp.',
      'capsule': 'cap.', 'cap': 'cap.',
      'tablet': 'tab.', 'tab': 'tab.',
      'injection': 'inj.', 'inj': 'inj.',
      'drip': 'drip.', 'syringe': 'syr.', 'syr': 'syr.',
    };
    String? abbrev;
    for (var entry in prefixes.entries) {
      if (rawType.contains(entry.key) || rawName.contains(entry.key)) {
        abbrev = entry.value;
        break;
      }
    }
    if (abbrev == null) return '';
    if (rawName.startsWith(abbrev.toLowerCase())) return '';
    return abbrev;
  }

  // ─── Add medicine sub-dialog ───────────────────────────────────────────────
  Future<Map<String, dynamic>?> _showAddMedicineSubDialog({
    Map<String, dynamic>? inventoryMed,
  }) async {
    final isInventory = inventoryMed != null;
    final nameCtrl    = TextEditingController(text: isInventory ? inventoryMed['name'] : '');
    final timingCtrl  = TextEditingController();
    final qtyCtrl     = TextEditingController(text: '1');
    String mealTiming = 'After Meal';
    String dosage     = '1 spoon';
    bool isSyrup      = false;
    bool isInjection  = false;

    void updateFields() {
      if (isInventory) {
        final type  = (inventoryMed['type'] ?? '').toString().toLowerCase();
        isInjection = type.contains('injection') || type.contains('inj');
        isSyrup     = type.contains('syrup')     || type.contains('syp');
      } else {
        final text  = nameCtrl.text.toLowerCase();
        isInjection = text.contains('inj.');
        isSyrup     = text.contains('syp.');
      }
    }

    updateFields();
    if (!isInventory) nameCtrl.addListener(updateFields);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isInventory ? 'Add Inventory Medicine' : 'Add Custom Medicine'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl, readOnly: isInventory,
              decoration: InputDecoration(
                labelText: 'Medicine name', border: const OutlineInputBorder(),
                filled: isInventory, fillColor: isInventory ? Colors.grey[200] : null),
            ),
            const SizedBox(height: 12),
            if (!isInjection) ...[
              const Text('Timing (M+E+N):'),
              const SizedBox(height: 6),
              TextField(
                controller: timingCtrl, keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(hintText: 'e.g. 1+0+2', border: OutlineInputBorder()),
                onChanged: (value) {
                  final digits    = value.replaceAll('+', '');
                  if (digits.length > 3) return;
                  final formatted = digits.split('').join('+');
                  if (timingCtrl.text != formatted) {
                    timingCtrl.text = formatted;
                    timingCtrl.selection = TextSelection.collapsed(offset: formatted.length);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: mealTiming,
                decoration: const InputDecoration(
                    labelText: 'Timing Instruction', border: OutlineInputBorder()),
                items: ['Empty Stomach', 'Before Meal', 'During Meal', 'After Meal', 'Before Sleep']
                    .map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) => mealTiming = v!,
              ),
              if (isSyrup) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: dosage,
                  decoration: const InputDecoration(labelText: 'Dosage', border: OutlineInputBorder()),
                  items: ['1 spoon', '1/2 spoon', '1/3 spoon', '1/4 spoon']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => dosage = v!,
                ),
              ],
            ] else
              TextField(
                controller: qtyCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Map<String, dynamic> newMed;
              if (isInjection) {
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                if (qty <= 0) return;
                newMed = {'name': name, 'quantity': qty, 'type': 'Injection',
                    'inventoryId': inventoryMed?['id']};
              } else {
                final digits = timingCtrl.text.replaceAll('+', '');
                final m      = int.tryParse(digits.isNotEmpty ? digits[0] : '0') ?? 0;
                final e      = digits.length > 1 ? int.tryParse(digits[1]) ?? 0 : 0;
                final n      = digits.length > 2 ? int.tryParse(digits[2]) ?? 0 : 0;
                final sum    = m + e + n;
                final qty    = (mealTiming == 'Before Sleep' && sum == 0) ? 1 : sum;
                if (qty == 0) return;
                newMed = {'name': name, 'quantity': qty, 'timing': '$m+$e+$n',
                    'meal': mealTiming, 'dosage': isSyrup ? dosage : '',
                    'type': isSyrup ? 'Syrup' : 'Tablet', 'inventoryId': inventoryMed?['id']};
              }
              Navigator.pop(ctx, newMed);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    nameCtrl.dispose(); timingCtrl.dispose(); qtyCtrl.dispose();
    return result;
  }

  // ─── Prescription edit dialog ──────────────────────────────────────────────
  Future<void> _showPrescriptionDialog(Map<String, dynamic> patient) async {
    final serial   = (patient['serial'] ?? patient['id'] ?? '').toString().trim();
    final branchId = widget.branchId;

    if (serial.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid serial number')));
      return;
    }

    Map<String, dynamic> prescData = {};
    Map<String, dynamic> entryData = {};

    final localPresc = LocalStorageService.getLocalPrescription(serial);
    if (localPresc != null && localPresc.isNotEmpty) {
      prescData = Map<String, dynamic>.from(localPresc);
      debugPrint('[PrescEdit] Loaded from local prescriptions box: $serial');
    } else {
      final entryKey = '$branchId-$serial';
      final entryRaw = Hive.box(LocalStorageService.entriesBox).get(entryKey);
      if (entryRaw != null) {
        entryData = Map<String, dynamic>.from(entryRaw);
        final embeddedPresc = entryData['prescription'] as Map<String, dynamic>?;
        if (embeddedPresc != null && embeddedPresc.isNotEmpty) {
          prescData = Map<String, dynamic>.from(embeddedPresc);
          debugPrint('[PrescEdit] Loaded from embedded entry prescription: $serial');
        }
      }

      if (prescData.isEmpty && _isOnline) {
        debugPrint('[PrescEdit] Falling back to Firestore for: $serial');
        try {
          final ddmmyy = serial.split('-')[0];
          for (final type in ['zakat', 'non-zakat', 'gmwf']) {
            final candidate = FirebaseFirestore.instance
                .collection('branches').doc(branchId)
                .collection('serials').doc(ddmmyy)
                .collection(type).doc(serial);
            final snap = await candidate.get();
            if (snap.exists) {
              final d = snap.data() ?? {};
              entryData = Map<String, dynamic>.from(d);
              // Preserve collection name so queueType resolver works
              entryData['queueType'] = type;
              final embeddedPresc = d['prescription'] as Map<String, dynamic>?;
              if (embeddedPresc != null) prescData = Map<String, dynamic>.from(embeddedPresc);
              break;
            }
          }
          debugPrint('[PrescEdit] Firestore fetch complete. prescData empty: ${prescData.isEmpty}');
        } catch (e) {
          debugPrint('[PrescEdit] Firestore fetch failed: $e');
        }
      }
    }

    if (prescData.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No prescription found for $serial'),
          backgroundColor: Colors.orange));
      return;
    }

    final String patientCnic = (
      prescData['patientCnic']?.toString() ??
      prescData['cnic']?.toString() ??
      entryData['patientCnic']?.toString() ??
      entryData['cnic']?.toString() ??
      patient['patientCnic']?.toString() ??
      ''
    ).replaceAll(RegExp(r'[-\s]'), '').toLowerCase();

    final String patientName = (
      prescData['patientName']?.toString() ??
      entryData['patientName']?.toString() ??
      patient['patientName']?.toString() ??
      'Unknown Patient'
    );

    // FIX (Bug 3): resolve through normaliser, not a hardcoded 'zakat' default
    final String queueType = _normaliseQueueType(
      entryData['queueType']?.toString() ??
      prescData['queueType']?.toString() ??
      patient['queueType']?.toString(),
    );

    debugPrint('[PrescEdit] resolved queueType=$queueType for serial=$serial');

    final complaintCtrl = TextEditingController(
        text: prescData['condition'] ?? prescData['complaint'] ?? '');
    final diagnosisCtrl = TextEditingController(text: prescData['diagnosis'] ?? '');

    List<Map<String, dynamic>> currentMeds = List<Map<String, dynamic>>.from(
        (prescData['prescriptions'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []);
    List<Map<String, dynamic>> currentLabs = List<Map<String, dynamic>>.from(
        (prescData['labResults'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []);

    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];

    void searchInventory(String q) {
      final query    = q.trim().toLowerCase();
      final allStock = LocalStorageService.getAllLocalStockItems(branchId: branchId);
      searchResults  = query.isEmpty ? []
          : allStock.where((m) => (m['name'] ?? '').toString().toLowerCase().contains(query)).toList();
    }

    searchCtrl.addListener(() { searchInventory(searchCtrl.text); if (mounted) setState(() {}); });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(children: [
            const Icon(Icons.edit_note, color: _teal),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Edit Prescription – $patientName ($serial)',
              style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
          ]),
          content: SizedBox(
            width: 700, height: 600,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: complaintCtrl,
                  decoration: InputDecoration(
                    labelText: 'Patient Complaint',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    filled: true, fillColor: Colors.green[50]),
                  maxLines: 2),
                const SizedBox(height: 16),
                TextField(
                  controller: diagnosisCtrl,
                  decoration: InputDecoration(
                    labelText: 'Diagnosis',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    filled: true, fillColor: Colors.green[50]),
                  maxLines: 3),
                const SizedBox(height: 24),
                const Text('Medicines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                TextField(
                  controller: searchCtrl, autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search inventory & add medicine...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                    filled: true),
                  onChanged: (q) { searchInventory(q); setDialogState(() {}); }),
                const SizedBox(height: 8),
                if (searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12)),
                    child: ListView.builder(
                      shrinkWrap: true, itemCount: searchResults.length,
                      itemBuilder: (ctx, i) {
                        final med    = searchResults[i];
                        final abbrev = _getMedAbbrev(med);
                        final namePart = (med['name'] ?? '').trim();
                        final label = abbrev.isNotEmpty &&
                                !namePart.toLowerCase().startsWith(abbrev.toLowerCase())
                            ? '$abbrev $namePart' : namePart;
                        return ListTile(
                          title: Text(label),
                          subtitle: Text('Stock: ${med['quantity'] ?? 0}'),
                          onTap: () async {
                            final newMed = await _showAddMedicineSubDialog(inventoryMed: med);
                            if (newMed != null) {
                              setDialogState(() {
                                currentMeds.add(newMed);
                                searchCtrl.clear(); searchResults = [];
                              });
                            }
                          },
                        );
                      },
                    ),
                  )
                else if (searchCtrl.text.isNotEmpty)
                  const Padding(padding: EdgeInsets.all(16),
                      child: Text('No matching medicines in local inventory',
                          style: TextStyle(color: Colors.grey))),
                const SizedBox(height: 12),
                if (currentMeds.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('No medicines added yet', style: TextStyle(color: Colors.grey)))
                else
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: currentMeds.map((med) {
                      final abbrev   = _getMedAbbrev(med);
                      final namePart = (med['name'] ?? '').trim();
                      final qty      = med['quantity'] ?? 1;
                      final label    = abbrev.isNotEmpty &&
                              !namePart.toLowerCase().startsWith(abbrev.toLowerCase())
                          ? '$abbrev $namePart ×$qty' : '$namePart ×$qty';
                      return Chip(
                        label: Text(label),
                        backgroundColor: _teal,
                        labelStyle: const TextStyle(color: Colors.white),
                        onDeleted: () => setDialogState(() => currentMeds.remove(med)));
                    }).toList()),
                const SizedBox(height: 16),
                const Text('Lab Tests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: currentLabs.map((l) => l['name']).join(', '),
                  decoration: InputDecoration(
                    hintText: 'Lab tests (comma separated)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    filled: true),
                  onChanged: (value) {
                    currentLabs = value.split(',').map((e) => e.trim())
                        .where((e) => e.isNotEmpty).map((e) => {'name': e}).toList();
                    setDialogState(() {});
                  }),
                const SizedBox(height: 8),
                if (localPresc != null)
                  Text('Source: local prescriptions', style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                else if (entryData.isNotEmpty)
                  Text('Source: local entry cache', style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                else
                  Text('Source: Firestore (cloud)', style: TextStyle(fontSize: 11, color: Colors.orange[700])),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _teal),
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text('Update', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _savePrescriptionUpdate(
                  serial:        serial,
                  branchId:      branchId,
                  patientCnic:   patientCnic,
                  queueType:     queueType,
                  originalPresc: prescData,
                  complaint:     complaintCtrl.text.trim(),
                  diagnosis:     diagnosisCtrl.text.trim(),
                  medicines:     currentMeds,
                  labTests:      currentLabs,
                );
              },
            ),
          ],
        ),
      ),
    );

    complaintCtrl.dispose(); diagnosisCtrl.dispose(); searchCtrl.dispose();
  }

  // ─── Save prescription update ──────────────────────────────────────────────
  Future<void> _savePrescriptionUpdate({
    required String serial,
    required String branchId,
    required String patientCnic,
    required String queueType,
    required Map<String, dynamic> originalPresc,
    required String complaint,
    required String diagnosis,
    required List<Map<String, dynamic>> medicines,
    required List<Map<String, dynamic>> labTests,
  }) async {
    final now = DateTime.now().toIso8601String();

    final updatedPresc = <String, dynamic>{
      ...originalPresc,
      'serial':        serial,
      'branchId':      branchId,
      'queueType':     queueType,   // explicit — not just from originalPresc spread
      'condition':     complaint,
      'complaint':     complaint,
      'diagnosis':     diagnosis,
      'prescriptions': medicines,
      'labResults':    labTests,
      'updatedAt':     now,
      'updatedBy':     RealtimeManager().role ?? 'Doctor',
    };

    // 1. Local Hive prescriptions box
    await LocalStorageService.saveLocalPrescription(updatedPresc);
    debugPrint('[PrescEdit] ✅ Saved to local prescriptions box: $serial');

    // 2. Hive entries box
    final entryKey = '$branchId-$serial';
    final entryBox  = Hive.box(LocalStorageService.entriesBox);
    final existing  = entryBox.get(entryKey);
    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing);
      updated['prescription']   = updatedPresc;
      updated['prescriptionId'] = serial;
      updated['status']         = 'completed';
      updated['completedAt']    = updatedPresc['completedAt'] ?? now;
      await entryBox.put(entryKey, updated);
      debugPrint('[PrescEdit] ✅ Updated entry in Hive entries box: $entryKey');
    }

    // 3. LAN broadcast
    RealtimeManager().sendMessage(RealtimeEvents.payload(
      type:     RealtimeEvents.savePrescription,
      branchId: branchId,
      data:     updatedPresc,
    ));
    debugPrint('[PrescEdit] ✅ Broadcasted save_prescription');

    // 4. Firestore fire-and-forget
    if (_isOnline) {
      _updateFirestore(
        serial:       serial,
        branchId:     branchId,
        patientCnic:  patientCnic,
        queueType:    queueType,
        updatedPresc: updatedPresc,
        now:          now,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle, color: Colors.white), SizedBox(width: 8),
          Text('Prescription updated successfully'),
        ]),
        backgroundColor: Colors.green, duration: Duration(seconds: 3),
      ));
      setState(() {});
    }
  }

  // ─── Firestore write (FIX Bug 3) ─────────────────────────────────────────
  Future<void> _updateFirestore({
    required String serial,
    required String branchId,
    required String patientCnic,
    required String queueType,   // FIX: always normalised before reaching here
    required Map<String, dynamic> updatedPresc,
    required String now,
  }) async {
    try {
      final ddmmyy = serial.split('-')[0];
      final db     = FirebaseFirestore.instance;

      final cleanCnic = patientCnic.isNotEmpty ? patientCnic : 'unknown_$serial';
      await db
          .collection('branches').doc(branchId)
          .collection('prescriptions').doc(cleanCnic)
          .collection('prescriptions').doc(serial)
          .set(updatedPresc, SetOptions(merge: true));
      debugPrint('[PrescEdit] ✅ Firestore prescriptions updated: $serial');

      // FIX (Bug 3): queueType is now always correctly resolved via
      // _normaliseQueueType before reaching this method — no hardcoded fallback.
      await db
          .collection('branches').doc(branchId)
          .collection('serials').doc(ddmmyy)
          .collection(queueType)   // ← correct collection, not always 'zakat'
          .doc(serial)
          .update({
        'prescription': updatedPresc,
        'status':       'completed',
        'updatedAt':    FieldValue.serverTimestamp(),
      });
      debugPrint('[PrescEdit] ✅ Firestore serials/$ddmmyy/$queueType/$serial updated');
    } catch (e) {
      debugPrint('[PrescEdit] ❌ Firestore update failed (will retry on next sync): $e');
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(LocalStorageService.entriesBox).listenable(),
      builder: (context, box, _) {
        final allPatients = _getSortedQueue();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryAutoSelectSmallestWaiting();
        });

        if (allPatients.isEmpty) {
          return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text("No patients in today's queue", style: TextStyle(fontSize: 18, color: Colors.grey)),
          ]));
        }

        final waiting   = allPatients.where((p) => (p['status'] ?? '').toString().toLowerCase() == 'waiting').toList();
        final completed = allPatients.where((p) => (p['status'] ?? '').toString().toLowerCase() != 'waiting').toList();
        final waitingCount   = waiting.length;
        final completedCount = completed.length;
        final total          = allPatients.length;

        List<Map<String, dynamic>> list;
        switch (_filter) {
          case 'waiting':   list = waiting;    break;
          case 'completed': list = completed;  break;
          default:          list = allPatients;
        }

        return Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: _teal,
            child: Row(children: [
              const Icon(Icons.people_alt, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              const Text("Today's Queue", style: TextStyle(
                  color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 24),
                onPressed: () {
                  setState(() {});
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _tryAutoSelectSmallestWaiting());
                }),
            ]),
          ),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              GestureDetector(onTap: () => setState(() => _filter = 'waiting'),
                  child: _buildFilterTab('Waiting', waitingCount, _amber, _filter == 'waiting')),
              GestureDetector(onTap: () => setState(() => _filter = 'completed'),
                  child: _buildFilterTab('Done', completedCount, Colors.green[700]!, _filter == 'completed')),
              GestureDetector(onTap: () => setState(() => _filter = 'all'),
                  child: _buildFilterTab('Total', total, _purple, _filter == 'all')),
            ]),
          ),

          // Patient list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final patient = list[index];
                final serial  = patient['serial']?.toString() ?? patient['id']?.toString() ?? 'N/A';
                final name    = patient['patientName'] ?? 'Unknown Patient';

                final isSelected = widget.selectedPatient?['serial']?.toString() == serial ||
                    widget.selectedPatient?['id']?.toString() == serial;

                final status    = (patient['status'] ?? '').toString().toLowerCase();
                final isWaiting = status == 'waiting';

                final smallestWaitingSerial = waiting.isNotEmpty
                    ? (waiting.first['serial']?.toString() ?? waiting.first['id']?.toString() ?? '') : '';
                final isSmallestWaiting = isWaiting && serial == smallestWaitingSerial;
                final isSelectable      = isSmallestWaiting && !widget.isSaving;
                final hasPrescription   = patient['prescription'] != null ||
                    LocalStorageService.getLocalPrescription(serial) != null;

                final Color dotColor = isWaiting ? _amber : Colors.green[700]!;

                Widget dot = Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle));
                if (isWaiting) dot = ScaleTransition(scale: _pulseAnimation, child: dot);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? _amber.withOpacity(0.15) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: isSelected ? _amber : dotColor.withOpacity(0.4),
                        width: isSelected ? 2.0 : 1.2),
                    boxShadow: [BoxShadow(
                        color: Colors.black12.withOpacity(0.08), blurRadius: 3,
                        offset: const Offset(0, 1))]),
                  child: InkWell(
                    onTap: isSelectable ? () => widget.onPatientSelected(
                        {...patient, 'serial': serial, 'id': serial}) : null,
                    child: Row(children: [
                      Icon(isWaiting ? Icons.person : Icons.check_circle,
                          color: dotColor, size: 26),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15,
                            color: (!isWaiting) ? Colors.grey : Colors.black87)),
                        const SizedBox(height: 3),
                        Text('Serial: $serial', style: TextStyle(
                            color: isSelected ? _teal : (!isWaiting ? Colors.grey : Colors.black54),
                            fontSize: 12)),
                      ])),
                      if (!isWaiting && hasPrescription)
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.orange, size: 20),
                          tooltip: 'Edit Prescription',
                          onPressed: () => _showPrescriptionDialog(patient)),
                      dot,
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildFilterTab(String label, int count, Color color, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? color : color.withOpacity(0.6),
        borderRadius: BorderRadius.circular(30),
        boxShadow: isActive
            ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]
            : null),
      child: Column(children: [
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 2),
        Text('$count', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}