// lib/pages/dispensary/doctor/patient_queue.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';

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
  StreamSubscription<QuerySnapshot>? _exceptionSub;
  List<DocumentSnapshot> _exceptionRequests = [];
  List<Map<String, dynamic>> _localExceptionRequests = [];

  List<Map<String, dynamic>> _loadLocalExceptionRequests() {
    final box = Hive.box('app_settings');
    return box.keys
        .where((k) => k.toString().startsWith('pending_exception_'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .where((r) =>
            r['branchId']?.toString() == widget.branchId &&
            r['status']?.toString() == 'pending')
        .toList();
  }

  bool _isOnline = true;

  // ── Pricing: base PKR per day per queue type ───────────────────────────────
  static const Map<String, int> _baseDayPrice = {
    'zakat':     20,
    'non-zakat': 100,
    'gmwf':      0,
  };

  // ─── Queue-type normaliser ─────────────────────────────────────────────────
  static String _normaliseQueueType(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) {
      return 'non-zakat';
    }
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') {
      return 'gmwf';
    }
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
      final data = event['data'] as Map<String, dynamic>? ?? event;
      if (!mounted || type == null) return;

      final msgBranch = (data['branchId'] ?? event['branchId'])?.toString().toLowerCase().trim();
      final myBranch  = widget.branchId.toLowerCase().trim();
      if (msgBranch != null && msgBranch.isNotEmpty && msgBranch != myBranch) return;

      if (type == RealtimeEvents.saveEntry ||
          type == 'token_created' ||
          type == 'save_entry') {
        final serial = (data['serial'] ?? data['id'])?.toString();
        if (serial != null && serial.isNotEmpty) {
          LocalStorageService.saveEntryLocal(widget.branchId, serial, data);
        }
        if (mounted) {
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryAutoSelectSmallestWaiting();
          });
        }
      } else if (type == 'dispense_completed') {
        final serial = (data['serial'] ?? data['id'])?.toString();
        if (serial != null && serial.isNotEmpty) {
          final entryKey = '${widget.branchId}-$serial';
          final existing = Hive.box(LocalStorageService.entriesBox).get(entryKey);
          if (existing is Map) {
            final updated = Map<String, dynamic>.from(existing)
              ..['dispenseStatus'] = 'dispensed'
              ..['status'] = 'completed';
            Hive.box(LocalStorageService.entriesBox).put(entryKey, updated);
          }
        }
        if (mounted) {
          setState(() {});
        }
      } else if (type == RealtimeEvents.savePrescription || type == 'prescription_created') {
        if (mounted) {
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryAutoSelectSmallestWaiting();
          });
        }
      } else if (type == RealtimeEvents.tokenExceptionRequest) {
        final requestId = data?['requestId']?.toString() ??
            'local_${DateTime.now().millisecondsSinceEpoch}';
        final localReq = <String, dynamic>{
          'id':          requestId,
          'requestType': 'token_exception',
          'status':      'pending',
          'patientId':   data?['patientId'] ?? '',
          'patientName': data?['patientName'] ?? 'Unknown',
          'restriction': data?['restriction'],
          'branchId':    widget.branchId,
        };
        Hive.box('app_settings').put(
            'pending_exception_$requestId',
            LocalStorageService.sanitize(localReq));
        if (mounted) {
          setState(() {
            _localExceptionRequests = _loadLocalExceptionRequests();
          });
        }
      }
    });

    _startExceptionListener();

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
    _exceptionSub?.cancel();
    super.dispose();
  }

  void _startExceptionListener() {
    _exceptionSub?.cancel();
    _exceptionSub = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('edit_requests')
        .where('requestType', isEqualTo: 'token_exception')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _exceptionRequests = snap.docs;
        });
      }
    });
  }

  Future<void> _approveException(Map<String, dynamic> data) async {
    final patientId = data['patientId'] as String;
    final requestId = data['id'] as String;

    final reasonCtrl = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Exception'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Why are you allowing this patient (${data['patientName']}) to get a token again today?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                hintText: 'Enter reason (e.g. emergency, correction)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (approved != true) return;
    final doctorReason = reasonCtrl.text.trim();
    if (doctorReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a reason for the exception'),
      ));
      return;
    }

    try {
      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('edit_requests')
            .doc(requestId)
            .update({
          'status': 'approved',
          'doctorReason': doctorReason,
          'approvedBy': RealtimeManager().role ?? 'Doctor',
          'approvedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[PatientQueue] Firestore offline update failed: $e');
      }

      await LocalStorageService.enqueueSync({
        'type':      'approve_token_exception',
        'branchId':  widget.branchId,
        'requestId': requestId,
        'patientId': patientId,
        'data': {
          'doctorReason': doctorReason,
          'approvedBy':   RealtimeManager().role ?? 'Doctor',
          'approvedAt':   DateTime.now().toIso8601String(),
        },
      });

      await LocalStorageService.clearMedicineRestriction(widget.branchId, patientId);
      Hive.box('app_settings').delete('pending_exception_$requestId');

      RealtimeManager().sendMessage({
        ...RealtimeEvents.payload(
          type: RealtimeEvents.tokenExceptionApproved,
          branchId: widget.branchId,
          data: {
            'requestId': requestId,
            'patientId': patientId,
            'reason':    doctorReason,
          },
        ),
      });

      if (mounted) {
        setState(() {
          _localExceptionRequests = _loadLocalExceptionRequests();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Exception approved. Restriction cleared.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _rejectException(Map<String, dynamic> data) async {
    final requestId  = data['id'] as String;
    final reasonCtrl = TextEditingController();

    final rejected = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Exception'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(hintText: 'Reason for rejection'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (rejected != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .doc(requestId)
          .update({
        'status': 'rejected',
        'doctorReason': reasonCtrl.text.trim(),
        'rejectedBy': RealtimeManager().role ?? 'Doctor',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      Hive.box('app_settings').delete('pending_exception_$requestId');

      if (mounted) {
        setState(() {
          _localExceptionRequests = _loadLocalExceptionRequests();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Exception request rejected.'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
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

  // ─── Injection / drip check ───────────────────────────────────────────────
  bool _isInjectionOrDrip(Map<String, dynamic> med) {
    final type = (med['type'] ?? '').toString().toLowerCase();
    final name = (med['name'] ?? '').toString().toLowerCase();
    return type.contains('injection') || type.contains('inj') ||
        type.contains('drip') ||
        name.contains('inj.') || name.contains('drip');
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

  int _getAvailableStock(
    Map<String, dynamic>? inventoryMed, {
    required String branchId,
    required List<Map<String, dynamic>> currentMeds,
    String? excludeSerial,
  }) {
    if (inventoryMed == null) return 999999;

    final invQty = inventoryMed['quantity'];
    final totalStock = (invQty is num ? invQty.toInt() : int.tryParse(invQty?.toString() ?? '') ?? 0);
    final inventoryId = inventoryMed['id']?.toString() ?? '';

    // Quantity reserved by OTHER pending patients (from Hive scan)
    final prescBox   = Hive.box(LocalStorageService.prescriptionsBox);
    final entriesBox = Hive.box(LocalStorageService.entriesBox);
    final mySerial   = excludeSerial?.trim().toLowerCase();

    int reservedByOthers = 0;
    for (final key in prescBox.keys) {
      final raw = prescBox.get(key);
      if (raw is! Map) continue;
      final presc = Map<String, dynamic>.from(raw);

      final prescSerial = (presc['serial'] ?? presc['id'] ?? '')
          .toString().trim().toLowerCase();
      if (prescSerial == mySerial) continue;

      final entryKey = '$branchId-$prescSerial';
      final entry    = entriesBox.get(entryKey);
      if (entry is Map) {
        final dispenseStatus =
            (entry['dispenseStatus'] ?? '').toString().toLowerCase();
        if (dispenseStatus == 'dispensed') continue;
      }

      final dispenseStatusOnPresc =
          (presc['dispenseStatus'] ?? '').toString().toLowerCase();
      if (dispenseStatusOnPresc == 'dispensed') continue;

      final meds = presc['prescriptions'];
      if (meds is! List) continue;

      for (final med in meds) {
        if (med is! Map) continue;
        if (med['inventoryId']?.toString() == inventoryId) {
          final medQty = med['quantity'];
          final qty = (medQty is num ? medQty.toInt() : int.tryParse(medQty?.toString() ?? '') ?? 0);
          final days = (presc['daysOfMedicine'] as int?) ?? 1;
          final type = (med['type'] ?? '').toString().toLowerCase();
          final isInj = type.contains('injection') || type.contains('inj') ||
              type.contains('drip') || type.contains('syringe') ||
              type.contains('nebulization');
          reservedByOthers += isInj ? qty : qty * days;
        }
      }
    }

    // Quantity already added in THIS dialog/edit session for this patient
    int sessionQty = 0;
    for (final med in currentMeds) {
      if (med['inventoryId']?.toString() == inventoryId) {
        final medQty = med['quantity'];
        sessionQty += (medQty is num ? medQty.toInt() : int.tryParse(medQty?.toString() ?? '') ?? 0);
      }
    }

    final available = totalStock - reservedByOthers - sessionQty;
    return available < 0 ? 0 : available;
  }

  // ─── Add medicine sub-dialog ───────────────────────────────────────────────
  Future<Map<String, dynamic>?> _showAddMedicineSubDialog({
    required String branchId,
    required List<Map<String, dynamic>> currentMeds,
    required int daysOfMedicine,
    String? excludeSerial,
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
                initialValue: mealTiming,
                decoration: const InputDecoration(
                    labelText: 'Timing Instruction', border: OutlineInputBorder()),
                items: ['Empty Stomach', 'Before Meal', 'During Meal', 'After Meal', 'Before Sleep']
                    .map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) => mealTiming = v!,
              ),
              if (isSyrup) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: dosage,
                  decoration: const InputDecoration(
                      labelText: 'Dosage', border: OutlineInputBorder()),
                  items: ['1 spoon', '1/2 spoon', '1/3 spoon', '1/4 spoon']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => dosage = v!,
                ),
              ],
            ] else
              TextField(
                controller: qtyCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Quantity', border: OutlineInputBorder()),
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _teal)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Map<String, dynamic> newMed;
              if (isInjection) {
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                if (qty <= 0) return;
                if (isInventory) {
                  final availableStock = _getAvailableStock(
                    inventoryMed,
                    branchId: branchId,
                    currentMeds: currentMeds,
                    excludeSerial: excludeSerial,
                  );
                  if (qty > availableStock) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('⚠️ Stock Limit Exceeded! Available: $availableStock'),
                        backgroundColor: Colors.red));
                    return;
                  }
                }
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
                if (isInventory) {
                  final availableStock = _getAvailableStock(
                    inventoryMed,
                    branchId: branchId,
                    currentMeds: currentMeds,
                    excludeSerial: excludeSerial,
                  );
                  final totalRequired = qty * daysOfMedicine;
                  if (totalRequired > availableStock) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('⚠️ Stock Limit Exceeded! Need $totalRequired but only $availableStock available.'),
                        backgroundColor: Colors.red));
                    return;
                  }
                }
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

    nameCtrl.dispose(); timingCtrl.dispose(); qtyCtrl.dispose();
    return result;
  }

  // ─── Days selector widget ──────────────────────────────────────────────────
  Widget _buildDaysSelectorDialog({
    required int selectedDays,
    required String queueType,
    required void Function(int) onChanged,
    bool hasInjection = false,
    int? suggestedDays,
  }) {
    final pricePerDay = _baseDayPrice[queueType] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.calendar_month_rounded, color: _teal, size: 18),
          const SizedBox(width: 8),
          const Text('Days of Medicine',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: _teal)),
          if (!hasInjection && pricePerDay > 0 && selectedDays > 1) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Text(
                'Extra: PKR ${(selectedDays - 1) * pricePerDay}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Row(
          children: [1, 2, 3].map((day) {
            final isSelected = selectedDays == day;
            final isDisabled = hasInjection && day > 1;
            final effectiveColor = isDisabled
                ? Colors.grey.shade200
                : isSelected
                    ? _teal
                    : Colors.white;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: day < 3 ? 8 : 0),
                child: Tooltip(
                  message: isDisabled ? 'Injection prescribed — only 1 day allowed' : '',
                  child: GestureDetector(
                    onTap: isDisabled
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  '💉 Injection prescribed — only 1 day of medicine is allowed'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 2),
                            ));
                          }
                        : () => onChanged(day),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: effectiveColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isDisabled
                                ? Colors.grey.shade300
                                : isSelected
                                    ? _teal
                                    : Colors.grey.shade300,
                            width: isSelected && !isDisabled ? 2 : 1),
                        boxShadow: isSelected && !isDisabled
                            ? [BoxShadow(
                                color: _teal.withValues(alpha: 0.22),
                                blurRadius: 6,
                                offset: const Offset(0, 2))]
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDisabled
                                    ? Colors.grey.shade400
                                    : isSelected
                                        ? Colors.white
                                        : Colors.grey.shade700),
                          ),
                          Text(
                            day == 1 ? 'day' : 'days',
                            style: TextStyle(
                                fontSize: 11,
                                color: isDisabled
                                    ? Colors.grey.shade400
                                    : isSelected
                                        ? Colors.white70
                                        : Colors.grey.shade500),
                          ),
                          if (!isDisabled && pricePerDay > 0 && day > 1)
                            Text(
                              '+PKR ${(day - 1) * pricePerDay}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.orange.shade600,
                                  fontWeight: FontWeight.w600),
                            ),
                          if (isDisabled)
                            Icon(Icons.vaccines_rounded,
                                size: 11, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        if (hasInjection)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(children: [
              Icon(Icons.vaccines_rounded, size: 13, color: Colors.orange.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Injection prescribed — only 1 day of medicine is allowed. '
                  'Multi-day selection is disabled.',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          )
        else
          Text(
            pricePerDay > 0
                ? 'Day-1 fee (PKR $pricePerDay) collected at token desk.'
                    '${selectedDays > 1 ? ' Extra PKR ${(selectedDays - 1) * pricePerDay} will be charged.' : ''}'
                : 'No charge for $queueType patients.',
            style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic),
          ),
      ],
    );
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
            final snap = await FirebaseFirestore.instance
                .collection('branches').doc(branchId)
                .collection('serials').doc(ddmmyy)
                .collection(type).doc(serial).get();
            if (snap.exists) {
              final d = snap.data() ?? {};
              entryData = Map<String, dynamic>.from(d);
              entryData['queueType'] = type;
              final embeddedPresc = d['prescription'] as Map<String, dynamic>?;
              if (embeddedPresc != null) {
                prescData = Map<String, dynamic>.from(embeddedPresc);
              }
              break;
            }
          }
        } catch (e) {
          debugPrint('[PrescEdit] Firestore fetch failed: $e');
        }
      }
    }

    if (prescData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No prescription found for $serial'),
          backgroundColor: Colors.orange));
      }
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

    final String queueType = _normaliseQueueType(
      entryData['queueType']?.toString() ??
      prescData['queueType']?.toString() ??
      patient['queueType']?.toString(),
    );

    debugPrint('[PrescEdit] resolved queueType=$queueType for serial=$serial');

    int editDays = (() {
      final d = prescData['daysOfMedicine'] ??
          entryData['daysOfMedicine'] ??
          (entryData['prescription'] is Map
              ? entryData['prescription']['daysOfMedicine']
              : null) ??
          entryData['suggestedDays'] ??
          patient['suggestedDays'];
      if (d is int && d >= 1 && d <= 3) return d;
      return 1;
    })();

    final complaintCtrl = TextEditingController(
        text: prescData['condition'] ?? prescData['complaint'] ?? '');
    final diagnosisCtrl = TextEditingController(
        text: prescData['diagnosis'] ?? '');

    List<Map<String, dynamic>> currentMeds = List<Map<String, dynamic>>.from(
        (prescData['prescriptions'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? []);
    List<Map<String, dynamic>> currentLabs = List<Map<String, dynamic>>.from(
        (prescData['labResults'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? []);

    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];

    void searchInventory(String q) {
      final query    = q.trim().toLowerCase();
      final allStock = LocalStorageService.getAllLocalStockItems(branchId: branchId);
      searchResults  = query.isEmpty ? []
          : allStock
              .where((m) => (m['name'] ?? '').toString().toLowerCase().contains(query))
              .toList();
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          searchCtrl.addListener(() {
            searchInventory(searchCtrl.text);
            setDialogState(() {});
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(children: [
              const Icon(Icons.edit_note, color: _teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Edit Prescription – $patientName ($serial)',
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            content: SizedBox(
              width: 700,
              height: 640,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Complaint ───────────────────────────────────────────
                    TextField(
                      controller: complaintCtrl,
                      decoration: InputDecoration(
                        labelText: 'Patient Complaint',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Colors.green[50],
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // ── Diagnosis ───────────────────────────────────────────
                    TextField(
                      controller: diagnosisCtrl,
                      decoration: InputDecoration(
                        labelText: 'Diagnosis',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        filled: true,
                        fillColor: Colors.green[50],
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // ── Days selector ───────────────────────────────────────
                    _buildDaysSelectorDialog(
                      selectedDays:  editDays,
                      queueType:     queueType,
                      hasInjection:  currentMeds.any(_isInjectionOrDrip),
                      suggestedDays: (patient['suggestedDays'] as int?) ?? (entryData['suggestedDays'] as int?),
                      onChanged:     (d) => setDialogState(() => editDays = d),
                    ),
                    const SizedBox(height: 20),

                    // ── Medicines ───────────────────────────────────────────
                    const Text('Medicines',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search inventory & add medicine...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30)),
                        filled: true,
                      ),
                      onChanged: (q) {
                        searchInventory(q);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    if (searchResults.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(12)),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (ctx, i) {
                            final med      = searchResults[i];
                            final abbrev   = _getMedAbbrev(med);
                            final namePart = (med['name'] ?? '').trim();
                            final label    = abbrev.isNotEmpty &&
                                    !namePart.toLowerCase().startsWith(
                                        abbrev.toLowerCase())
                                ? '$abbrev $namePart'
                                : namePart;
                            return ListTile(
                              title: Text(label),
                              subtitle: Text('Stock: ${med['quantity'] ?? 0}'),
                              onTap: () async {
                                final newMed =
                                    await _showAddMedicineSubDialog(
                                  branchId: branchId,
                                  currentMeds: currentMeds,
                                  daysOfMedicine: editDays,
                                  excludeSerial: serial,
                                  inventoryMed: med,
                                );
                                if (newMed != null) {
                                  setDialogState(() {
                                    currentMeds.add(newMed);
                                    final isInj = _isInjectionOrDrip(newMed);
                                    if (isInj && editDays > 1) editDays = 1;
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
                        child: Text('No matching medicines in local inventory',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    const SizedBox(height: 12),
                    if (currentMeds.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('No medicines added yet',
                            style: TextStyle(color: Colors.grey)))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: currentMeds.map((med) {
                          final abbrev   = _getMedAbbrev(med);
                          final namePart = (med['name'] ?? '').trim();
                          final qty      = med['quantity'] ?? 1;
                          final label    = abbrev.isNotEmpty &&
                                  !namePart
                                      .toLowerCase()
                                      .startsWith(abbrev.toLowerCase())
                              ? '$abbrev $namePart ×$qty'
                              : '$namePart ×$qty';
                          return Chip(
                            label: Text(label),
                            backgroundColor: _teal,
                            labelStyle: const TextStyle(color: Colors.white),
                            onDeleted: () =>
                                setDialogState(() => currentMeds.remove(med)),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),

                    // ── Lab tests ───────────────────────────────────────────
                    const Text('Lab Tests',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: currentLabs.map((l) => l['name']).join(', '),
                      decoration: InputDecoration(
                        hintText: 'Lab tests (comma separated)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
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
                    const SizedBox(height: 8),

                    // ── Source indicator ────────────────────────────────────
                    if (localPresc != null)
                      Text('Source: local prescriptions',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                    else if (entryData.isNotEmpty)
                      Text('Source: local entry cache',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                    else
                      Text('Source: Firestore (cloud)',
                          style: TextStyle(fontSize: 11, color: Colors.orange[700])),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              // FIX: confirmation dialog "Update" button — teal background so white text is readable
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _teal.withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white70,
                ),
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('Update'),
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
                    daysOfMedicine: editDays,
                  );
                },
              ),
            ],
          );
        },
      ),
    );

    complaintCtrl.dispose();
    diagnosisCtrl.dispose();
    searchCtrl.dispose();
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
    required int daysOfMedicine,
  }) async {
    // --- Stock Check Validation at Save Time ---
    try {
      final allStock   = LocalStorageService.getAllLocalStockItems(branchId: branchId);
      final prescBox   = Hive.box(LocalStorageService.prescriptionsBox);
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      final mySerial   = serial.trim().toLowerCase();

      // 1. Build reserved quantities from other pending patients
      final Map<String, int> reserved = {};
      for (final key in prescBox.keys) {
        final raw = prescBox.get(key);
        if (raw is! Map) continue;
        final presc = Map<String, dynamic>.from(raw);

        final prescSerial = (presc['serial'] ?? presc['id'] ?? '')
            .toString().trim().toLowerCase();
        if (prescSerial == mySerial) continue;

        final entryKey = '$branchId-$prescSerial';
        final entry    = entriesBox.get(entryKey);
        if (entry is Map) {
          final dispenseStatus =
              (entry['dispenseStatus'] ?? '').toString().toLowerCase();
          if (dispenseStatus == 'dispensed') continue;
        }

        final dispenseStatusOnPresc =
            (presc['dispenseStatus'] ?? '').toString().toLowerCase();
        if (dispenseStatusOnPresc == 'dispensed') continue;

        final meds = presc['prescriptions'];
        if (meds is! List) continue;

        for (final med in meds) {
          if (med is! Map) continue;
          final inventoryId = (med['inventoryId'] ?? '').toString().trim();
          if (inventoryId.isEmpty) continue;

          final medQty = med['quantity'];
          final qty = (medQty is num ? medQty.toInt() : int.tryParse(medQty?.toString() ?? '') ?? 0);
          final days = (presc['daysOfMedicine'] as int?) ?? 1;
          final type = (med['type'] ?? '').toString().toLowerCase();
          final isInj = type.contains('injection') || type.contains('inj') ||
              type.contains('drip') || type.contains('syringe') ||
              type.contains('nebulization');
          final effectiveQty = isInj ? qty : qty * days;

          reserved[inventoryId] = (reserved[inventoryId] ?? 0) + effectiveQty;
        }
      }

      // 2. Validate each medicine in the updated prescription
      for (final med in medicines) {
        final inventoryId = (med['inventoryId'] ?? '').toString().trim();
        if (inventoryId.isEmpty) continue;

        final inventoryMed = allStock.firstWhere(
          (m) => m['id']?.toString() == inventoryId,
          orElse: () => {},
        );
        if (inventoryMed.isEmpty) continue;

        final invQty = inventoryMed['quantity'];
        final totalStock = (invQty is num ? invQty.toInt() : int.tryParse(invQty?.toString() ?? '') ?? 0);
        final reservedByOthers = reserved[inventoryId] ?? 0;
        final available = totalStock - reservedByOthers;
        final availableClamped = available < 0 ? 0 : available;

        final medQty = med['quantity'];
        final perDayQty = (medQty is num ? medQty.toInt() : int.tryParse(medQty?.toString() ?? '') ?? 0);
        final isInj = _isInjectionOrDrip(med);
        final required = isInj ? perDayQty : perDayQty * daysOfMedicine;

        if (required > availableClamped) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                '⚠️ "${med['name']}" stock insufficient! '
                'Need $required but only $availableClamped available after reservations.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ));
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('[PrescEdit] Stock validation error: $e');
    }

    final now         = DateTime.now().toIso8601String();
    final pricePerDay = _baseDayPrice[queueType] ?? 0;
    final extraCharge = (daysOfMedicine - 1) * pricePerDay;

    final updatedPresc = <String, dynamic>{
      ...originalPresc,
      'serial':          serial,
      'branchId':        branchId,
      'queueType':       queueType,
      'condition':       complaint,
      'complaint':       complaint,
      'diagnosis':       diagnosis,
      'prescriptions':   medicines,
      'labResults':      labTests,
      'daysOfMedicine':  daysOfMedicine,
      'updatedAt':       now,
      'updatedBy':       RealtimeManager().role ?? 'Doctor',
    };

    // 1. Hive prescriptions box
    await LocalStorageService.saveLocalPrescription(updatedPresc);
    debugPrint('[PrescEdit] ✅ Saved to local prescriptions box: $serial');

    // 2. Hive entries box — also update top-level daysOfMedicine
    final entryKey = '$branchId-$serial';
    final entryBox  = Hive.box(LocalStorageService.entriesBox);
    final existing  = entryBox.get(entryKey);
    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing);
      updated['prescription']   = updatedPresc;
      updated['prescriptionId'] = serial;
      updated['status']         = 'completed';
      updated['completedAt']    = updatedPresc['completedAt'] ?? now;
      updated['daysOfMedicine'] = daysOfMedicine;
      await entryBox.put(entryKey, updated);
      debugPrint('[PrescEdit] ✅ Updated entry in Hive: $entryKey');
    }

    // 3. LAN broadcast
    RealtimeManager().sendMessage(RealtimeEvents.payload(
      type:     RealtimeEvents.savePrescription,
      branchId: branchId,
      data:     updatedPresc,
    ));
    debugPrint('[PrescEdit] ✅ Broadcasted save_prescription (days=$daysOfMedicine)');

    // 4. Firestore fire-and-forget
    if (_isOnline) {
      _updateFirestore(
        serial:         serial,
        branchId:       branchId,
        patientCnic:    patientCnic,
        queueType:      queueType,
        updatedPresc:   updatedPresc,
        daysOfMedicine: daysOfMedicine,
        now:            now,
      );
    }

    if (mounted) {
      final daysTxt   = daysOfMedicine > 1 ? ' ($daysOfMedicine days)' : '';
      final chargeTxt = extraCharge > 0 ? ' | Extra: PKR $extraCharge' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 8),
          Text('Prescription updated$daysTxt$chargeTxt'),
        ]),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ));
      setState(() {});
    }
  }

  // ─── Firestore write ───────────────────────────────────────────────────────
  Future<void> _updateFirestore({
    required String serial,
    required String branchId,
    required String patientCnic,
    required String queueType,
    required Map<String, dynamic> updatedPresc,
    required int daysOfMedicine,
    required String now,
  }) async {
    try {
      final ddmmyy    = serial.split('-')[0];
      final db        = FirebaseFirestore.instance;
      final cleanCnic = patientCnic.isNotEmpty ? patientCnic : 'unknown_$serial';

      // Path A: prescriptions/{cnic}/prescriptions/{serial}
      await db
          .collection('branches').doc(branchId)
          .collection('prescriptions').doc(cleanCnic)
          .collection('prescriptions').doc(serial)
          .set(updatedPresc, SetOptions(merge: true));
      debugPrint('[PrescEdit] ✅ Firestore prescriptions updated: $serial');

      // Path B: serials/{dateKey}/{queueType}/{serial}
      await db
          .collection('branches').doc(branchId)
          .collection('serials').doc(ddmmyy)
          .collection(queueType)
          .doc(serial)
          .update({
        'prescription':   updatedPresc,
        'status':         'completed',
        'daysOfMedicine': daysOfMedicine,
        'updatedAt':      FieldValue.serverTimestamp(),
      });
      debugPrint('[PrescEdit] ✅ Firestore serials/$ddmmyy/$queueType/$serial updated '
          '(days=$daysOfMedicine)');
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
          return const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text("No patients in today's queue",
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
            ],
          ));
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
          case 'waiting':   list = waiting;    break;
          case 'completed': list = completed;  break;
          default:          list = allPatients;
        }

        final mergedExceptions = [
          ..._exceptionRequests.map((doc) => {
                ...doc.data() as Map<String, dynamic>,
                'id': doc.id
              }),
          ..._localExceptionRequests,
        ];

        // deduplicate by ID
        final uniqueExceptions = <String, Map<String, dynamic>>{};
        for (var e in mergedExceptions) {
          uniqueExceptions[e['id'].toString()] = e;
        }
        final finalExceptions = uniqueExceptions.values.toList();

        return Column(children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: _teal,
            child: Row(children: [
              const Icon(Icons.people_alt, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              const Text("Today's Queue",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold)),
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

          // ── Filter tabs ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _filter = 'waiting'),
                  child: _buildFilterTab(
                      'Waiting', waitingCount, _amber, _filter == 'waiting')),
                GestureDetector(
                  onTap: () => setState(() => _filter = 'completed'),
                  child: _buildFilterTab('Done', completedCount,
                      Colors.green[700]!, _filter == 'completed')),
                GestureDetector(
                  onTap: () => setState(() => _filter = 'all'),
                  child: _buildFilterTab(
                      'Total', total, _purple, _filter == 'all')),
              ],
            ),
          ),

          // ── Exception requests ───────────────────────────────────────────
          if (finalExceptions.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.emergency_share_outlined, color: Colors.orange.shade900, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'EXCEPTION REQUESTS (${finalExceptions.length})',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                          letterSpacing: 1.1),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  ...finalExceptions.map((d) {
                    return Card(
                      elevation: 0,
                      color: Colors.orange.shade100,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.orange.shade800,
                          child: const Icon(Icons.person, color: Colors.white, size: 16),
                        ),
                        title: Text(d['patientName'] ?? 'Unknown',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                        subtitle: Text('Restricted: ${d['restriction']?['remainingDays'] ?? '?'} days left'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green, size: 24),
                              onPressed: () => _approveException(d),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red, size: 24),
                              onPressed: () => _rejectException(d),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          // ── Patient list ─────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final patient = list[index];
                final serial  = patient['serial']?.toString() ??
                    patient['id']?.toString() ?? 'N/A';
                final name = patient['patientName'] ?? 'Unknown Patient';

                final isSelected =
                    widget.selectedPatient?['serial']?.toString() == serial ||
                    widget.selectedPatient?['id']?.toString() == serial;

                final status    = (patient['status'] ?? '').toString().toLowerCase();
                final dispenseStatus = (patient['dispenseStatus'] ?? '').toString().toLowerCase();
                final isWaiting = status == 'waiting';

                // FIX: edit button must only appear for status == 'completed',
                // and MUST hide immediately once status becomes 'dispensed'
                // (or dispenseStatus is 'dispensed' even if status is 'completed' for sync reasons).
                final isCompleted = status == 'completed' && dispenseStatus != 'dispensed';

                final smallestWaitingSerial = waiting.isNotEmpty
                    ? (waiting.first['serial']?.toString() ??
                        waiting.first['id']?.toString() ?? '')
                    : '';
                final isSmallestWaiting =
                    isWaiting && serial == smallestWaitingSerial;
                final isSelectable = isSmallestWaiting && !widget.isSaving;
                final hasPrescription = patient['prescription'] != null ||
                    LocalStorageService.getLocalPrescription(serial) != null;

                // Days badge for prescriptions with > 1 day
                final prescDays = (() {
                  final d = patient['daysOfMedicine'];
                  if (d is int && d > 1) return d;
                  final presc = patient['prescription'];
                  if (presc is Map) {
                    final pd = presc['daysOfMedicine'];
                    if (pd is int && pd > 1) return pd;
                  }
                  return 1;
                })();

                final Color dotColor = isWaiting ? _amber : Colors.green[700]!;

                Widget dot = Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: dotColor, shape: BoxShape.circle));
                if (isWaiting) dot = ScaleTransition(scale: _pulseAnimation, child: dot);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? _amber.withValues(alpha: 0.15) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: isSelected ? _amber : dotColor.withValues(alpha: 0.4),
                        width: isSelected ? 2.0 : 1.2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black12.withValues(alpha: 0.08),
                          blurRadius: 3,
                          offset: const Offset(0, 1))
                    ],
                  ),
                  child: InkWell(
                    onTap: isSelectable
                        ? () => widget.onPatientSelected(
                            {...patient, 'serial': serial, 'id': serial})
                        : null,
                    child: Row(children: [
                      Icon(isWaiting ? Icons.person : Icons.check_circle,
                          color: dotColor, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: (!isWaiting)
                                        ? Colors.grey
                                        : Colors.black87)),
                            const SizedBox(height: 3),
                            Row(children: [
                              Text('Serial: $serial',
                                  style: TextStyle(
                                      color: isSelected
                                          ? _teal
                                          : (!isWaiting
                                              ? Colors.grey
                                              : Colors.black54),
                                      fontSize: 12)),
                              // ×2 / ×3 days badge
                              if (prescDays > 1) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('×$prescDays',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ]),
                          ],
                        ),
                      ),
                      // FIX: show edit button only when status is exactly 'completed'
                      // (prescription written by doctor but not yet dispensed).
                      // Hidden immediately once status becomes 'dispensed'.
                      if (isCompleted && hasPrescription)
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: Colors.orange, size: 20),
                          tooltip: 'Edit Prescription',
                          onPressed: () => _showPrescriptionDialog(patient),
                        ),
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

  Widget _buildFilterTab(
      String label, int count, Color color, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? color : color.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(30),
        boxShadow: isActive
            ? [BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 4))]
            : null,
      ),
      child: Column(children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
        const SizedBox(height: 2),
        Text('$count',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
