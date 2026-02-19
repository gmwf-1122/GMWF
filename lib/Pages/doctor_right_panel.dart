// lib/pages/doctor_right_panel.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:another_flushbar/flushbar.dart';

import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

class DoctorRightPanel extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? selectedPatientData;
  final TextEditingController complaintController;
  final TextEditingController diagnosisController;
  final List<Map<String, dynamic>> prescriptions;
  final List<Map<String, dynamic>> labResults;
  final bool isSaving;
  final VoidCallback onAddLabResult;
  final Function(int) onRemoveLabResult;
  final Function(Map<String, dynamic>) onEditMedicine;
  final Function(int) onRemoveMedicine;
  final Future Function()? onSavePrescription;
  final VoidCallback? onEntryCompleted;
  final String serialId;
  final Function(Map<String, dynamic> repeatData)? onRepeatData;

  const DoctorRightPanel({
    super.key,
    required this.branchId,
    required this.selectedPatientData,
    required this.complaintController,
    required this.diagnosisController,
    required this.prescriptions,
    required this.labResults,
    required this.isSaving,
    required this.onAddLabResult,
    required this.onRemoveLabResult,
    required this.onRemoveMedicine,
    required this.onEditMedicine,
    this.onSavePrescription,
    this.onEntryCompleted,
    required this.serialId,
    this.onRepeatData,
  });

  @override
  State<DoctorRightPanel> createState() => _DoctorRightPanelState();
}

class _DoctorRightPanelState extends State<DoctorRightPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _complaintFocus  = FocusNode();
  final FocusNode _diagnosisFocus  = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _saveButtonFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _allInventory  = [];

  static const Color _teal     = Color(0xFF00695C);
  static const Color _orange   = Color(0xFFFF6D00);
  static const Color _blueGrey = Color(0xFF455A64);

  final List<String> _quickLabTests = const [
    "CBC",
    "LFT",
    "RFT",
    "HbA1C",
    "BMP",
    "Urine R/E",
    "Lipid Profile",
    "ECG",
    "X-ray",
    "Ultrasound Abdomen",
  ];

  // Tracks which quick-test chips are toggled ON.
  final Set<String> _selectedQuickTests = {};

  late final List<FocusNode> _tabOrder = [
    _complaintFocus,
    _diagnosisFocus,
    _searchFocusNode,
    _saveButtonFocus,
  ];

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  // ── Init ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadInventory();

    // ── FIXED: seed _selectedQuickTests from whatever labs are already present
    // This is critical for the Repeat Last flow: the parent calls
    // _applyRepeatData(), clears+fills widget.labResults, then increments
    // _rightPanelKey which causes this widget to be fully reconstructed.
    // By the time initState runs, widget.labResults already contains the
    // repeated labs, so we mirror them into _selectedQuickTests here so the
    // filter chips render as pre-selected.
    for (final lab in widget.labResults) {
      final name = lab['name']?.toString() ?? '';
      if (_quickLabTests.contains(name)) {
        _selectedQuickTests.add(name);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _complaintFocus.requestFocus();
    });

    _searchController.addListener(() => _onSearchChanged(_searchController.text));
    _realtimeSub = RealtimeManager().messageStream.listen(_handleRealtimeUpdate);
  }

  // ── Realtime ──────────────────────────────────────────────────────────────
  void _handleRealtimeUpdate(Map<String, dynamic> event) {
    final type = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? event;

    if (type == null || data.isEmpty) return;

    final serial = data['serial'] as String?;
    if (serial == null) return;

    if (type == RealtimeEvents.saveEntry) {
      debugPrint('[DoctorPanel] received save_entry → refreshing queue');
      setState(() {});
    }

    final msgBranch = data['branchId']?.toString().toLowerCase().trim();
    if (msgBranch != null && msgBranch != widget.branchId.toLowerCase().trim()) return;

    if (serial != widget.serialId) return;

    if (type == RealtimeEvents.savePrescription) {
      setState(() {
        widget.complaintController.text = data['complaint'] ?? data['condition'] ?? '';
        widget.diagnosisController.text = data['diagnosis'] ?? '';
        widget.prescriptions
          ..clear()
          ..addAll(
            (data['prescriptions'] as List<dynamic>?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [],
          );
        widget.labResults
          ..clear()
          ..addAll(
            (data['labResults'] as List<dynamic>?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [],
          );
        // Re-sync quick-test chips after realtime update too
        _selectedQuickTests
          ..clear()
          ..addAll(
            widget.labResults
                .map((l) => l['name']?.toString() ?? '')
                .where(_quickLabTests.contains),
          );
      });

      if (mounted) {
        Flushbar(
          message: 'Prescription updated in realtime',
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 4),
        ).show(context);
      }
    } else if (type == RealtimeEvents.saveEntry && data['status'] == 'completed') {
      if (mounted) {
        Flushbar(
          message: 'Patient #$serial marked completed',
          backgroundColor: Colors.purple.shade700,
          duration: const Duration(seconds: 4),
        ).show(context);
      }
    }
  }

  // ── Inventory ─────────────────────────────────────────────────────────────
  void _loadInventory() async {
    final items = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId);
    if (mounted) setState(() => _allInventory = items);
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _complaintFocus.dispose();
    _diagnosisFocus.dispose();
    _saveButtonFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────────
  void _onSearchChanged(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _searchResults.clear());
      return;
    }
    final filtered = _allInventory.where((m) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      final type = (m['type'] ?? '').toString().toLowerCase();
      final dose = (m['dose'] ?? '').toString().toLowerCase();
      return name.contains(query) || type.contains(query) || dose.contains(query);
    }).toList();
    setState(() => _searchResults = filtered);
  }

  // ── Medicine helpers ──────────────────────────────────────────────────────
  String _getFormattedMedicine(Map<String, dynamic> m) {
    final name = (m['name'] ?? '').toString().trim();
    final dose = m['dose'] != null && m['dose'].toString().isNotEmpty ? ' ${m['dose']}' : '';
    return '$name$dose'.trim();
  }

  String _getMedAbbrev(Map<String, dynamic> med) {
    final rawName = (med['name'] ?? '').toString().trim().toLowerCase();
    final rawType = (med['type'] ?? '').toString().trim().toLowerCase();
    final prefixes = {
      'syrup': 'syp.', 'syp': 'syp.',
      'capsule': 'cap.', 'cap': 'cap.',
      'tablet': 'tab.', 'tab': 'tab.',
      'injection': 'inj.', 'inj': 'inj.',
      'drip': 'drip.',
      'syringe': 'syr.', 'syr': 'syr.',
    };
    String? abbrev;
    for (final entry in prefixes.entries) {
      if (rawType.contains(entry.key) || rawName.contains(entry.key)) {
        abbrev = entry.value;
        break;
      }
    }
    if (abbrev == null) return '';
    if (rawName.startsWith(abbrev.toLowerCase())) return '';
    return abbrev;
  }

  IconData _getMedicineIcon(Map<String, dynamic> med) {
    return switch ((med['type'] ?? '').toString().trim().toLowerCase()) {
      'tablet'   => FontAwesomeIcons.tablets,
      'capsule'  => FontAwesomeIcons.capsules,
      'syrup'    => FontAwesomeIcons.bottleDroplet,
      'injection' => FontAwesomeIcons.syringe,
      _          => FontAwesomeIcons.pills,
    };
  }

  bool _isInjectionOrDrip(Map<String, dynamic> med) {
    final t = (med['type'] ?? '').toString().trim().toLowerCase();
    return t.contains('injection') || t.contains('inj') ||
           t.contains('drip') || t.contains('syringe') || t.contains('nebulization');
  }

  bool _medicineExists(String name, {String? inventoryId}) {
    final lower = name.trim().toLowerCase();
    return widget.prescriptions.any((m) =>
        (m['name'] ?? '').toString().trim().toLowerCase() == lower &&
        (inventoryId == null || m['inventoryId'] == inventoryId));
  }

  // ── Add medicine dialog ───────────────────────────────────────────────────
  Future<void> _addMedicineDialog({Map<String, dynamic>? inventoryMed}) async {
    final isInventory = inventoryMed != null;
    final nameCtrl   = TextEditingController(text: isInventory ? inventoryMed['name'] : '');
    final timingCtrl = TextEditingController();
    final qtyCtrl    = TextEditingController(text: '1');
    String mealTiming = 'After Meal';
    String dosage     = '1 spoon';
    bool isSyrup      = false;
    bool isInjection  = false;

    void updateFields() {
      if (isInventory) {
        final type = (inventoryMed['type'] ?? '').toString().toLowerCase();
        isInjection = type.contains('injection') || type.contains('inj');
        isSyrup     = type.contains('syrup')     || type.contains('syp');
      } else {
        final text = nameCtrl.text.toLowerCase();
        isInjection = text.contains('inj.');
        isSyrup     = text.contains('syp.');
      }
    }

    updateFields();
    if (!isInventory) nameCtrl.addListener(() => setState(() => updateFields()));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isInventory ? 'Add Inventory Medicine' : 'Add Custom Medicine'),
        content: StatefulBuilder(
          builder: (context, setStateDialog) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  readOnly: isInventory,
                  decoration: InputDecoration(
                    labelText: 'Medicine name',
                    hintText: isInventory ? '' : 'e.g. Paracetamol, Dicloran',
                    border: const OutlineInputBorder(),
                    filled: isInventory,
                    fillColor: isInventory ? Colors.grey[200] : null,
                  ),
                  onChanged: isInventory ? null : (v) => setStateDialog(() => updateFields()),
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
                    decoration: const InputDecoration(hintText: 'e.g. 1+1+1', border: OutlineInputBorder()),
                    onChanged: (v) {
                      final digits    = v.replaceAll('+', '');
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
                    decoration: const InputDecoration(labelText: 'Timing Instruction', border: OutlineInputBorder()),
                    items: ['Empty Stomach', 'Before Meal', 'During Meal', 'After Meal', 'Before Sleep']
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => mealTiming = v!),
                  ),
                  if (isSyrup) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: dosage,
                      decoration: const InputDecoration(labelText: 'Dosage', border: OutlineInputBorder()),
                      items: ['1 spoon', '1/2 spoon', '1/3 spoon', '1/4 spoon']
                          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => dosage = v!),
                    ),
                  ],
                ] else
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter medicine name'), backgroundColor: Colors.redAccent));
                return;
              }
              if (_medicineExists(name, inventoryId: inventoryMed?['id'])) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Medicine already added'), backgroundColor: Colors.orange));
                return;
              }

              Map<String, dynamic> newMed;
              if (isInjection) {
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                if (qty <= 0) return;
                newMed = {'name': name, 'quantity': qty, 'type': 'Injection', 'inventoryId': inventoryMed?['id']};
              } else {
                final digits = timingCtrl.text.replaceAll('+', '');
                final m = int.tryParse(digits.isNotEmpty           ? digits[0] : '0') ?? 0;
                final e = digits.length > 1 ? int.tryParse(digits[1]) ?? 0 : 0;
                final n = digits.length > 2 ? int.tryParse(digits[2]) ?? 0 : 0;
                final sum = m + e + n;
                final qty = (mealTiming == 'Before Sleep' && sum == 0) ? 1 : sum;
                if (qty == 0) return;
                newMed = {
                  'name': name, 'quantity': qty, 'timing': '$m+$e+$n',
                  'meal': mealTiming, 'dosage': isSyrup ? dosage : '',
                  'type': isSyrup ? 'Syrup' : 'Tablet',
                  'inventoryId': inventoryMed?['id'],
                };
              }

              setState(() => widget.prescriptions.add(newMed));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added $name'), backgroundColor: Colors.green));
              _searchController.clear();
              _searchResults.clear();
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Add custom lab test ───────────────────────────────────────────────────
  Future<void> _addCustomLabTest() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Custom Lab Test'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Test name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty || widget.labResults.any((l) => (l['name'] ?? '').toString().trim() == name)) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid or duplicate test'), backgroundColor: Colors.redAccent));
                return;
              }
              setState(() => widget.labResults.add({'name': name}));
              Navigator.pop(context);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, IconData icon, {Widget? action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              FaIcon(icon, color: _teal, size: 20),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _teal)),
            ]),
            if (action != null) action,
          ],
        ),
      );

  Widget _buildMedicineSection(
      String title, IconData icon, List<Map<String, dynamic>> meds, Color chipColor) {
    if (meds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title, icon),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: meds.map((m) {
            final abbrev   = _getMedAbbrev(m);
            final namePart = _getFormattedMedicine(m);
            final label    = abbrev.isNotEmpty && !namePart.toLowerCase().startsWith(abbrev.toLowerCase())
                ? '$abbrev $namePart ×${m['quantity']}'
                : '$namePart ×${m['quantity']}';
            return Chip(
              label: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white)),
              backgroundColor: chipColor,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onDeleted: () => setState(() => widget.prescriptions.remove(m)),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Save prescription ─────────────────────────────────────────────────────
  Future<void> _savePrescriptionHiveFirst() async {
    final complaint = widget.complaintController.text.trim();
    final diagnosis = widget.diagnosisController.text.trim();

    if (complaint.isEmpty || diagnosis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Both Patient Condition and Diagnosis are required!'),
          backgroundColor: Colors.red));
      return;
    }
    if (widget.prescriptions.isEmpty && widget.labResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please add at least one medicine or lab test!'),
          backgroundColor: Colors.orange));
      return;
    }

    try {
      final patientData = Map<String, dynamic>.from(widget.selectedPatientData ?? {});

      String patientCnic = (patientData['cnic']?.toString() ??
          patientData['guardianCnic']?.toString() ??
          patientData['patientCnic']?.toString() ?? '').trim().replaceAll(RegExp(r'[-\s]'), '');

      if (patientCnic.isEmpty || patientCnic == '0000000000000') {
        patientCnic = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }

      final vitals    = patientData['vitals']    as Map<String, dynamic>? ?? {};
      final queueType = patientData['queueType'] as String? ?? 'zakat';
      final doctorId  = patientData['doctorId']  as String? ?? 'unknown_doctor';
      final doctorName = patientData['doctorName'] as String? ?? 'Dr. Unknown';

      final now      = DateTime.now();
      final nowIso   = now.toIso8601String();
      final serialClean = widget.serialId.trim().toLowerCase();
      final dateKey  = serialClean.split('-')[0];

      final prescriptionData = <String, dynamic>{
        'id': serialClean,
        'serial': serialClean,
        'patientCnic': patientCnic,
        'cnic': patientCnic,
        'patientName':   patientData['patientName'] ?? patientData['name'] ?? 'Unknown',
        'patientAge':    patientData['age']?.toString() ?? vitals['age']?.toString() ?? 'N/A',
        'patientGender': patientData['gender']?.toString() ?? vitals['gender']?.toString() ?? 'N/A',
        'vitals': vitals,
        'complaint': complaint,
        'condition': complaint,
        'diagnosis': diagnosis,
        'prescriptions': widget.prescriptions.map((m) => {
          'name': m['name'], 'quantity': m['quantity'], 'type': m['type'] ?? 'Tablet',
          'timing': m['timing'] ?? '', 'meal': m['meal'] ?? '',
          'dosage': m['dosage'] ?? '', 'inventoryId': m['inventoryId'],
        }).toList(),
        'labResults': widget.labResults.map((l) => {'name': l['name']}).toList(),
        'status': 'completed',
        'queueType': queueType,
        'createdAt': nowIso,
        'branchId': widget.branchId,
        'dateKey': dateKey,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'completedAt': nowIso,
        'updatedAt': nowIso,
        'updatedBy': doctorName,
      };

      debugPrint('[DoctorPanel] Saving → serial=$serialClean '
          'meds=${widget.prescriptions.length} labs=${widget.labResults.length}');

      await LocalStorageService.saveLocalPrescription(prescriptionData);

      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      final entryKey   = '${widget.branchId}-${widget.serialId}';
      final current    = entriesBox.get(entryKey);
      if (current != null) {
        final updated = Map<String, dynamic>.from(current);
        updated['status']         = 'completed';
        updated['completedAt']    = nowIso;
        updated['prescription']   = prescriptionData;
        updated['prescriptionId'] = serialClean;
        await entriesBox.put(entryKey, updated);
      }

      // Broadcast to dispenser
      try {
        RealtimeManager().sendMessage(RealtimeEvents.payload(
            type: RealtimeEvents.savePrescription,
            branchId: widget.branchId,
            data: prescriptionData));
        final full = entriesBox.get(entryKey);
        if (full != null) {
          RealtimeManager().sendMessage(RealtimeEvents.payload(
              type: RealtimeEvents.saveEntry,
              branchId: widget.branchId,
              data: Map<String, dynamic>.from(full)));
        }
      } catch (e) {
        debugPrint('[DoctorPanel] Broadcast failed (non-fatal): $e');
      }

      // Clear state
      widget.complaintController.clear();
      widget.diagnosisController.clear();
      widget.prescriptions.clear();
      widget.labResults.clear();
      _selectedQuickTests.clear();
      widget.onEntryCompleted?.call();
      if (widget.onSavePrescription != null) await widget.onSavePrescription!();

      if (mounted) {
        Flushbar(
          message: '✅ Prescription saved & broadcast successfully',
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }

      _syncToFirestoreInBackground(dateKey, queueType, serialClean, prescriptionData);
    } catch (e, stack) {
      debugPrint('[DoctorPanel] Save failed: $e\n$stack');
      if (mounted) {
        Flushbar(
          message: 'Failed to save: $e',
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ).show(context);
      }
    }
  }

  Future<void> _syncToFirestoreInBackground(
    String dateKey, String queueType, String serial,
    Map<String, dynamic> prescriptionData,
  ) async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (!result.contains(ConnectivityResult.none)) {
        await FirebaseFirestore.instance
            .collection('branches').doc(widget.branchId)
            .collection('serials').doc(dateKey)
            .collection(queueType).doc(serial)
            .update({
          'status': 'completed',
          'completedAt': prescriptionData['completedAt'],
          'prescription': prescriptionData,
        });
        debugPrint('[DoctorPanel] Synced to Firestore → $serial');
      } else {
        await _enqueueSync(dateKey, queueType, serial, prescriptionData);
      }
    } catch (e) {
      debugPrint('[DoctorPanel] Firestore sync failed: $e — queuing');
      await _enqueueSync(dateKey, queueType, serial, prescriptionData);
    }
  }

  Future<void> _enqueueSync(String dateKey, String queueType, String serial,
      Map<String, dynamic> prescriptionData) async {
    try {
      await LocalStorageService.enqueueSync({
        'type': 'save_prescription', 'branchId': widget.branchId,
        'dateKey': dateKey, 'queueType': queueType, 'serial': serial,
        'data': prescriptionData,
      });
      await LocalStorageService.enqueueSync({
        'type': 'update_serial_status', 'branchId': widget.branchId,
        'dateKey': dateKey, 'queueType': queueType, 'serial': serial,
        'data': {
          'status': 'completed',
          'completedAt': prescriptionData['completedAt'],
          'doctorName': prescriptionData['doctorName'],
        },
      });
      SyncService().triggerUpload();
    } catch (e) {
      debugPrint('[DoctorPanel] Enqueue failed: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.isSaving) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
          final cur     = _tabOrder.indexWhere((n) => n.hasFocus);
          final isShift = HardwareKeyboard.instance.physicalKeysPressed
              .contains(PhysicalKeyboardKey.shiftLeft);
          final next    = isShift
              ? (cur <= 0 ? _tabOrder.length - 1 : cur - 1)
              : (cur + 1) % _tabOrder.length;
          _tabOrder[next].requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Patient condition ────────────────────────────────────────────
            Row(children: [
              Icon(Icons.description, color: _teal, size: 22),
              const SizedBox(width: 10),
              const Text('Patient Condition',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _teal)),
            ]),
            const SizedBox(height: 12),
            TextField(
              focusNode: _complaintFocus,
              controller: widget.complaintController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "Describe patient's condition...",
                filled: true,
                fillColor: Colors.green[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),

            // ── Diagnosis ────────────────────────────────────────────────────
            Row(children: [
              Icon(Icons.medical_services, color: _teal, size: 22),
              const SizedBox(width: 10),
              const Text('Diagnosis',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _teal)),
            ]),
            const SizedBox(height: 12),
            TextField(
              focusNode: _diagnosisFocus,
              controller: widget.diagnosisController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter diagnosis...',
                filled: true,
                fillColor: Colors.green[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),

            // ── Medicine search ──────────────────────────────────────────────
            _sectionHeader('Medicines', FontAwesomeIcons.pills),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: TextField(
                focusNode: _searchFocusNode,
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search medicines...',
                  prefixIcon: const Icon(Icons.search, color: _teal),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchResults.clear());
                          },
                        ),
                      IconButton(
                        icon: const FaIcon(FontAwesomeIcons.arrowsRotate),
                        tooltip: 'Reload Inventory',
                        onPressed: () async {
                          await LocalStorageService.downloadInventory(widget.branchId);
                          _loadInventory();
                        },
                      ),
                    ],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),

            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _searchResults.length,
                  itemBuilder: (_, i) {
                    final m   = _searchResults[i];
                    final qty = ((m['quantity'] ?? 0) as num).toInt();
                    final abbrev   = _getMedAbbrev(m);
                    final namePart = _getFormattedMedicine(m);
                    final label    = abbrev.isNotEmpty &&
                            !namePart.toLowerCase().startsWith(abbrev.toLowerCase())
                        ? '$abbrev $namePart'
                        : namePart;
                    return ListTile(
                      leading: FaIcon(_getMedicineIcon(m), color: _teal),
                      title: Text(label),
                      trailing: Text('Stock: $qty',
                          style: TextStyle(
                              color: qty == 0 ? Colors.red : Colors.black87,
                              fontWeight: FontWeight.bold)),
                      onTap: () => _addMedicineDialog(inventoryMed: m),
                    );
                  },
                ),
              ),
            ] else if (_searchController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                child: Text('No medicines found matching "${_searchController.text}"',
                    style: TextStyle(color: Colors.grey[700])),
              ),
            ],

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _addMedicineDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add Custom'),
                style: OutlinedButton.styleFrom(foregroundColor: _teal),
              ),
            ),

            // ── Medicine chips (four groups) ─────────────────────────────────
            _buildMedicineSection(
                'Inventory Medicines', FontAwesomeIcons.pills,
                widget.prescriptions.where((m) => m['inventoryId'] != null && !_isInjectionOrDrip(m)).toList(),
                _teal),
            _buildMedicineSection(
                'Inventory Injectables', FontAwesomeIcons.syringe,
                widget.prescriptions.where((m) => m['inventoryId'] != null && _isInjectionOrDrip(m)).toList(),
                _orange),
            _buildMedicineSection(
                'Custom Medicines', FontAwesomeIcons.prescriptionBottle,
                widget.prescriptions.where((m) => m['inventoryId'] == null && !_isInjectionOrDrip(m)).toList(),
                _blueGrey),
            _buildMedicineSection(
                'Custom Injectables', FontAwesomeIcons.syringe,
                widget.prescriptions.where((m) => m['inventoryId'] == null && _isInjectionOrDrip(m)).toList(),
                _orange),

            const Divider(height: 1, thickness: 1, color: Colors.grey),
            const SizedBox(height: 20),

            // ── Lab tests ────────────────────────────────────────────────────
            _sectionHeader('Lab Tests', FontAwesomeIcons.flask,
                action: IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: _teal),
                  onPressed: _addCustomLabTest,
                )),

            // Quick-test filter chips
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _quickLabTests.map((t) {
                final selected = _selectedQuickTests.contains(t);
                return FilterChip(
                  label: Text(t),
                  selected: selected,
                  selectedColor: _teal,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                  onSelected: (_) {
                    setState(() {
                      if (selected) {
                        _selectedQuickTests.remove(t);
                        widget.labResults.removeWhere((l) => l['name'] == t);
                      } else {
                        _selectedQuickTests.add(t);
                        if (!widget.labResults.any((l) => l['name'] == t)) {
                          widget.labResults.add({'name': t});
                        }
                      }
                    });
                  },
                );
              }).toList(),
            ),

            // Custom (non-quick) lab test chips
            if (widget.labResults.any((l) => !_quickLabTests.contains(l['name']))) ...[
              const SizedBox(height: 16),
              const Text('Custom Tests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _teal)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.labResults
                    .where((l) => !_quickLabTests.contains(l['name']))
                    .map((l) => Chip(
                          label: Text(l['name'], style: const TextStyle(fontSize: 13)),
                          backgroundColor: Colors.orange.shade600,
                          labelStyle: const TextStyle(color: Colors.white),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          onDeleted: () => setState(() => widget.labResults.remove(l)),
                        ))
                    .toList(),
              ),
            ],

            const SizedBox(height: 30),
            const Divider(height: 1, thickness: 1, color: Colors.grey),
            const SizedBox(height: 30),

            // ── Save button ──────────────────────────────────────────────────
            Center(
              child: ElevatedButton.icon(
                focusNode: _saveButtonFocus,
                onPressed: widget.isSaving ? null : _savePrescriptionHiveFirst,
                icon: widget.isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, color: Colors.white),
                label: Text(
                  widget.isSaving ? 'Saving...' : 'Save Prescription',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 10,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}