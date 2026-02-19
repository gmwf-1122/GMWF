// lib/pages/patient_queue.dart
// FIXED: Removed BorderRadius.vertical(top: Radius.circular(36)) from the
// internal teal header — the parent Card now clips it cleanly via
// clipBehavior: Clip.antiAlias. Also removed the matching
// BorderRadius.vertical(top: Radius.circular(36)) from the Column wrapper.
// The queue list padding is tightened from 16→12 since there's no outer Padding.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../services/local_storage_service.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

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
      if (status == 'waiting') {
        waiting.add(e);
      } else {
        others.add(e);
      }
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
      widget.onPatientSelected({
        ...smallest,
        'serial': smallestSerial,
        'id': smallestSerial,
      });
    }
  }

  // ─── Firestore sync ────────────────────────────────────────────────────────
  Future<void> _syncQueueFromFirestore() async {
    try {
      final branchRef  = FirebaseFirestore.instance.collection('branches').doc(widget.branchId);
      final serialsRef = branchRef.collection('serials').doc(_todayKey);

      for (final type in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await serialsRef.collection(type).get();
        for (final doc in snap.docs) {
          final data     = doc.data();
          final serial   = doc.id;
          final entryKey = '${widget.branchId}-$serial';
          Hive.box(LocalStorageService.entriesBox).put(entryKey, {
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
    final nameCtrl    = TextEditingController(text: isInventory ? inventoryMed!['name'] : '');
    final timingCtrl  = TextEditingController();
    final qtyCtrl     = TextEditingController(text: '1');
    String mealTiming = 'After Meal';
    String dosage     = '1 spoon';
    bool isSyrup      = false;
    bool isInjection  = false;

    void updateFields() {
      if (isInventory) {
        final type  = (inventoryMed!['type'] ?? '').toString().toLowerCase();
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                readOnly: isInventory,
                decoration: InputDecoration(
                  labelText: 'Medicine name',
                  border: const OutlineInputBorder(),
                  filled: isInventory,
                  fillColor: isInventory ? Colors.grey[200] : null,
                ),
              ),
              const SizedBox(height: 12),
              if (!isInjection) ...[
                const Text('Timing (M+E+N):'),
                const SizedBox(height: 6),
                TextField(
                  controller: timingCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                      hintText: 'e.g. 1+0+2', border: OutlineInputBorder()),
                  onChanged: (value) {
                    final digits    = value.replaceAll('+', '');
                    if (digits.length > 3) return;
                    final formatted = digits.split('').join('+');
                    if (timingCtrl.text != formatted) {
                      timingCtrl.text = formatted;
                      timingCtrl.selection =
                          TextSelection.collapsed(offset: formatted.length);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: mealTiming,
                  decoration: const InputDecoration(
                      labelText: 'Timing Instruction', border: OutlineInputBorder()),
                  items: ['Empty Stomach', 'Before Meal', 'During Meal', 'After Meal', 'Before Sleep']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => mealTiming = v!,
                ),
                if (isSyrup) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: dosage,
                    decoration: const InputDecoration(
                        labelText: 'Dosage', border: OutlineInputBorder()),
                    items: ['1 spoon', '1/2 spoon', '1/3 spoon', '1/4 spoon']
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) => dosage = v!,
                  ),
                ],
              ] else
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Quantity', border: OutlineInputBorder()),
                ),
            ],
          ),
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
                newMed = {
                  'name': name, 'quantity': qty, 'type': 'Injection',
                  'inventoryId': inventoryMed?['id'],
                };
              } else {
                final digits = timingCtrl.text.replaceAll('+', '');
                final m      = int.tryParse(digits.isNotEmpty ? digits[0] : '0') ?? 0;
                final e      = digits.length > 1 ? int.tryParse(digits[1]) ?? 0 : 0;
                final n      = digits.length > 2 ? int.tryParse(digits[2]) ?? 0 : 0;
                final sum    = m + e + n;
                final qty    = (mealTiming == 'Before Sleep' && sum == 0) ? 1 : sum;
                if (qty == 0) return;
                newMed = {
                  'name': name, 'quantity': qty, 'timing': '$m+$e+$n',
                  'meal': mealTiming, 'dosage': isSyrup ? dosage : '',
                  'type': isSyrup ? 'Syrup' : 'Tablet',
                  'inventoryId': inventoryMed?['id'],
                };
              }
              Navigator.pop(ctx, newMed);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    timingCtrl.dispose();
    qtyCtrl.dispose();
    return result;
  }

  // ─── Prescription edit dialog ──────────────────────────────────────────────
  Future<void> _showPrescriptionDialog(Map<String, dynamic> patient) async {
    final serial  = patient['serial'] ?? patient['id'] ?? '';
    if (serial.isEmpty) return;

    final branchId = widget.branchId;
    final ddmmyy   = serial.split('-')[0];
    DocumentReference? serialRef;

    for (final type in ['zakat', 'non-zakat', 'gmwf']) {
      final candidate = FirebaseFirestore.instance
          .collection('branches').doc(branchId)
          .collection('serials').doc(ddmmyy)
          .collection(type).doc(serial);
      final snap = await candidate.get();
      if (snap.exists) { serialRef = candidate; break; }
    }

    if (serialRef == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Serial not found')));
      return;
    }

    final serialData = (await serialRef.get()).data() as Map<String, dynamic>? ?? {};
    final prescData  = serialData['prescription'] as Map<String, dynamic>? ?? {};

    final complaintCtrl = TextEditingController(
        text: prescData['condition'] ?? prescData['complaint'] ?? '');
    final diagnosisCtrl = TextEditingController(text: prescData['diagnosis'] ?? '');

    List<Map<String, dynamic>> currentMeds =
        List.from(prescData['prescriptions'] ?? []);
    List<Map<String, dynamic>> currentLabs =
        List.from(prescData['labResults'] ?? []);

    final searchCtrl         = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];

    void searchInventory(String q) {
      final query    = q.trim().toLowerCase();
      final allStock = LocalStorageService.getAllLocalStockItems(branchId: branchId);
      searchResults  = query.isEmpty
          ? []
          : allStock
              .where((m) => (m['name'] ?? '').toString().toLowerCase().contains(query))
              .toList();
      if (mounted) setState(() {});
    }

    searchCtrl.addListener(() => searchInventory(searchCtrl.text));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
              "Edit Prescription – ${patient['patientName'] ?? 'Patient'} ($serial)"),
          content: SizedBox(
            width: 700,
            height: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: complaintCtrl,
                    decoration: InputDecoration(
                      labelText: "Patient Complaint",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true, fillColor: Colors.green[50],
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: diagnosisCtrl,
                    decoration: InputDecoration(
                      labelText: "Diagnosis",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true, fillColor: Colors.green[50],
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  const Text("Medicines",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search inventory & add medicine...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        itemBuilder: (ctx, i) {
                          final med    = searchResults[i];
                          final abbrev = _getMedAbbrev(med);
                          final namePart = (med['name'] ?? '').trim();
                          final label  = abbrev.isNotEmpty &&
                                  !namePart.toLowerCase().startsWith(abbrev.toLowerCase())
                              ? '$abbrev $namePart'
                              : namePart;
                          return ListTile(
                            title: Text(label),
                            subtitle: Text('Stock: ${med['quantity'] ?? 0}'),
                            onTap: () async {
                              final newMed = await _showAddMedicineSubDialog(inventoryMed: med);
                              if (newMed != null) {
                                setDialogState(() {
                                  currentMeds.add(newMed);
                                  searchCtrl.clear();
                                  searchResults = [];
                                });
                              }
                            },
                          );
                        },
                      ),
                    )
                  else if (searchCtrl.text.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text("No matching medicines in local inventory",
                          style: TextStyle(color: Colors.grey)),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: currentMeds.map((med) {
                      final abbrev   = _getMedAbbrev(med);
                      final namePart = (med['name'] ?? '').trim();
                      final qty      = med['quantity'] ?? 1;
                      final label    = abbrev.isNotEmpty &&
                              !namePart.toLowerCase().startsWith(abbrev.toLowerCase())
                          ? '$abbrev $namePart ×$qty'
                          : '$namePart ×$qty';
                      return Chip(
                        label: Text(label),
                        backgroundColor: _teal,
                        labelStyle: const TextStyle(color: Colors.white),
                        onDeleted: () => setDialogState(() => currentMeds.remove(med)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text("Lab Tests",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(
                        text: currentLabs.map((l) => l['name']).join(', ')),
                    decoration: InputDecoration(
                      hintText: 'Lab tests (comma separated)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true,
                    ),
                    onChanged: (value) {
                      currentLabs = value
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .map((e) => {'name': e})
                          .toList();
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _teal),
              onPressed: () async {
                final updatedPrescription = {
                  ...prescData,
                  'condition':   complaintCtrl.text.trim(),
                  'diagnosis':   diagnosisCtrl.text.trim(),
                  'prescriptions': currentMeds,
                  'labResults':  currentLabs,
                  'updatedAt':   FieldValue.serverTimestamp(),
                  'updatedBy':   'Doctor',
                };
                try {
                  await serialRef!.update({'prescription': updatedPrescription});
                  RealtimeManager().sendMessage(
                    RealtimeEvents.payload(
                      type: RealtimeEvents.savePrescription,
                      data: {
                        'serial': serial, 'branchId': branchId,
                        ...updatedPrescription,
                      },
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Prescription updated live!"),
                        backgroundColor: Colors.green),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("Update failed: $e"),
                        backgroundColor: Colors.red),
                  );
                }
                Navigator.pop(dialogContext);
              },
              child: const Text("Update", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
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
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 80, color: Colors.grey),
                SizedBox(height: 16),
                Text("No patients in today's queue",
                    style: TextStyle(fontSize: 18, color: Colors.grey)),
              ],
            ),
          );
        }

        final waiting   = allPatients
            .where((p) => (p['status'] ?? '').toString().toLowerCase() == 'waiting')
            .toList();
        final completed = allPatients
            .where((p) => (p['status'] ?? '').toString().toLowerCase() != 'waiting')
            .toList();

        final waitingCount   = waiting.length;
        final completedCount = completed.length;
        final total          = allPatients.length;

        List<Map<String, dynamic>> list;
        switch (_filter) {
          case 'waiting':   list = waiting;   break;
          case 'completed': list = completed; break;
          default:          list = allPatients;
        }

        return Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            // FIX: Removed BorderRadius.vertical so the Card's own clip
            // handles the rounded-corner shaping. No more double border.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: _teal,
              child: Row(
                children: [
                  const Icon(Icons.people_alt, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  const Text("Today's Queue",
                      style: TextStyle(
                          color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white, size: 24),
                    onPressed: () {
                      setState(() {});
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _tryAutoSelectSmallestWaiting());
                    },
                  ),
                ],
              ),
            ),

            // ── Filter tabs ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _filter = 'waiting'),
                    child: _buildFilterTab("Waiting", waitingCount, _amber, _filter == 'waiting'),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _filter = 'completed'),
                    child: _buildFilterTab("Done", completedCount, Colors.green[700]!, _filter == 'completed'),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _filter = 'all'),
                    child: _buildFilterTab("Total", total, _purple, _filter == 'all'),
                  ),
                ],
              ),
            ),

            // ── Patient list ─────────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final patient = list[index];
                  final serial  = patient['serial']?.toString() ??
                      patient['id']?.toString() ?? 'N/A';
                  final name    = patient['patientName'] ?? 'Unknown Patient';

                  final isSelected = widget.selectedPatient?['serial']?.toString() == serial ||
                      widget.selectedPatient?['id']?.toString() == serial;

                  final status    = (patient['status'] ?? '').toString().toLowerCase();
                  final isWaiting = status == 'waiting';

                  final smallestWaitingSerial = waiting.isNotEmpty
                      ? (waiting.first['serial']?.toString() ??
                          waiting.first['id']?.toString() ?? '')
                      : '';
                  final isSmallestWaiting = isWaiting && serial == smallestWaitingSerial;
                  final isSelectable      = isSmallestWaiting && !widget.isSaving;
                  final hasPrescription   = patient['prescription'] != null;

                  final Color dotColor = isWaiting ? _amber : Colors.green[700]!;

                  Widget dot = Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  );
                  if (isWaiting) {
                    dot = ScaleTransition(scale: _pulseAnimation, child: dot);
                  }

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? _amber.withOpacity(0.15) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? _amber : dotColor.withOpacity(0.4),
                        width: isSelected ? 2.0 : 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12.withOpacity(0.08),
                            blurRadius: 3,
                            offset: const Offset(0, 1)),
                      ],
                    ),
                    child: InkWell(
                      onTap: isSelectable
                          ? () => widget.onPatientSelected({
                                ...patient,
                                'serial': serial,
                                'id': serial,
                              })
                          : null,
                      child: Row(
                        children: [
                          Icon(
                            isWaiting ? Icons.person : Icons.check_circle,
                            color: dotColor, size: 26,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15,
                                    color: (!isWaiting) ? Colors.grey : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Serial: $serial',
                                  style: TextStyle(
                                    color: isSelected ? _teal : (!isWaiting ? Colors.grey : Colors.black54),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isWaiting && hasPrescription)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.orange, size: 20),
                              tooltip: "Edit Prescription",
                              onPressed: () => _showPrescriptionDialog(patient),
                            ),
                          dot,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
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
            : null,
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 2),
          Text('$count',
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}