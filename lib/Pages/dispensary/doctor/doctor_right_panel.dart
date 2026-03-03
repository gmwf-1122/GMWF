// lib/pages/doctor_right_panel.dart
// FIXES:
//   1. DOCTOR NAME: Added required `doctorId` + `doctorName` props.
//      These are now used directly in prescriptionData instead of reading
//      from selectedPatientData (which never had them → "Unknown Doctor").
//   2. QUEUE TYPE: Added required `queueType` prop (already normalised by
//      DoctorScreen.resolveQueueType). Used for both Firestore paths so
//      non-zakat/gmwf prescriptions are never saved under 'zakat'.
//   3. Firestore now writes to BOTH:
//      • prescriptions/{cnic}/prescriptions/{serial}  (medical fields only — no duplicates)
//      • serials/{dateKey}/{queueType}/{serial}        (status + nested medical map)
//   4. DEDUPLICATION: fullPrescriptionData is a single flat document.
//      The nested prescription sub-doc (Path A) stores ONLY medical fields.
//      The serial doc (Path B) stores status/meta + a 'prescription' map
//      with medical fields — no field appears twice at the same level.
//   5. STOCK VALIDATION: Prevents adding medicines with 0 stock or exceeding available quantity.
// MOBILE: Compact form fields, responsive medicine chips, single-column scroll.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:another_flushbar/flushbar.dart';

import '../../../services/local_storage_service.dart';
import '../../../services/sync_service.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';

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

  /// The logged-in doctor's UID
  final String doctorId;

  /// The logged-in doctor's display name — resolved upstream, never blank
  final String doctorName;

  /// Already-normalised queue type: 'zakat' | 'non-zakat' | 'gmwf'
  final String queueType;

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
    required this.doctorId,
    required this.doctorName,
    required this.queueType,
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
    "CBC", "LFT", "RFT", "HbA1C", "BMP",
    "Urine R/E", "Lipid Profile", "ECG", "X-ray", "Ultrasound Abdomen",
  ];

  final Set<String> _selectedQuickTests = {};

  late final List<FocusNode> _tabOrder = [
    _complaintFocus,
    _diagnosisFocus,
    _searchFocusNode,
    _saveButtonFocus,
  ];

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _loadInventory();

    for (final lab in widget.labResults) {
      final name = lab['name']?.toString() ?? '';
      if (_quickLabTests.contains(name)) _selectedQuickTests.add(name);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _complaintFocus.requestFocus();
    });

    _searchController.addListener(
        () => _onSearchChanged(_searchController.text));
    _realtimeSub =
        RealtimeManager().messageStream.listen(_handleRealtimeUpdate);
  }

  void _handleRealtimeUpdate(Map<String, dynamic> event) {
    final type = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? event;
    if (type == null || data.isEmpty) return;

    final serial = data['serial'] as String?;
    if (serial == null || serial != widget.serialId) return;

    final msgBranch = data['branchId']?.toString().toLowerCase().trim();
    if (msgBranch != null &&
        msgBranch != widget.branchId.toLowerCase().trim()) return;

    if (type == RealtimeEvents.saveEntry) {
      if (mounted) setState(() {});
    }

    if (type == RealtimeEvents.savePrescription) {
      setState(() {
        widget.complaintController.text =
            data['complaint'] ?? data['condition'] ?? '';
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
    }
  }

  void _loadInventory() async {
    final items = LocalStorageService.getAllLocalStockItems(
        branchId: widget.branchId);
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

  void _onSearchChanged(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _searchResults.clear());
      return;
    }
    final filtered = _allInventory.where((m) {
      return (m['name'] ?? '').toString().toLowerCase().contains(query) ||
          (m['type'] ?? '').toString().toLowerCase().contains(query) ||
          (m['dose'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
    setState(() => _searchResults = filtered);
  }

  String _getFormattedMedicine(Map<String, dynamic> m) {
    final name = (m['name'] ?? '').toString().trim();
    final dose = m['dose'] != null && m['dose'].toString().isNotEmpty
        ? ' ${m['dose']}'
        : '';
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
      'tablet'    => FontAwesomeIcons.tablets,
      'capsule'   => FontAwesomeIcons.capsules,
      'syrup'     => FontAwesomeIcons.bottleDroplet,
      'injection' => FontAwesomeIcons.syringe,
      _           => FontAwesomeIcons.pills,
    };
  }

  bool _isInjectionOrDrip(Map<String, dynamic> med) {
    final t = (med['type'] ?? '').toString().trim().toLowerCase();
    return t.contains('injection') || t.contains('inj') ||
        t.contains('drip') || t.contains('syringe') ||
        t.contains('nebulization');
  }

  bool _medicineExists(String name, {String? inventoryId}) {
    final lower = name.trim().toLowerCase();
    return widget.prescriptions.any((m) =>
        (m['name'] ?? '').toString().trim().toLowerCase() == lower &&
        (inventoryId == null || m['inventoryId'] == inventoryId));
  }

  // Get available stock for an inventory item
  int _getAvailableStock(Map<String, dynamic>? inventoryMed) {
    if (inventoryMed == null) return 999999; // Custom medicine, no limit

    final totalStock = ((inventoryMed['quantity'] ?? 0) as num).toInt();
    final inventoryId = inventoryMed['id'];

    // Calculate already prescribed quantity for this inventory item
    int alreadyPrescribed = 0;
    for (final med in widget.prescriptions) {
      if (med['inventoryId'] == inventoryId) {
        alreadyPrescribed += ((med['quantity'] ?? 0) as num).toInt();
      }
    }

    return totalStock - alreadyPrescribed;
  }

  Future<void> _addMedicineDialog({Map<String, dynamic>? inventoryMed}) async {
    final isInventory = inventoryMed != null;

    // Check stock availability for inventory items
    if (isInventory) {
      final availableStock = _getAvailableStock(inventoryMed);
      if (availableStock <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                availableStock == 0
                  ? '⚠️ Out of Stock!'
                  : '⚠️ Stock Limit Exceeded! Available: $availableStock'
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    final nameCtrl =
        TextEditingController(text: isInventory ? inventoryMed['name'] : '');
    final timingCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    String mealTiming = 'After Meal';
    String dosage = '1 spoon';
    bool isSyrup = false;
    bool isInjection = false;

    void updateFields() {
      if (isInventory) {
        final type = (inventoryMed['type'] ?? '').toString().toLowerCase();
        isInjection = type.contains('injection') || type.contains('inj');
        isSyrup = type.contains('syrup') || type.contains('syp');
      } else {
        final text = nameCtrl.text.toLowerCase();
        isInjection = text.contains('inj.');
        isSyrup = text.contains('syp.');
      }
    }

    updateFields();
    if (!isInventory) {
      nameCtrl.addListener(() => setState(() => updateFields()));
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isInventory ? 'Add Inventory Medicine' : 'Add Custom Medicine',
          style: const TextStyle(fontSize: 16),
        ),
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
                    border: const OutlineInputBorder(),
                    filled: isInventory,
                    fillColor: isInventory ? Colors.grey[200] : null,
                    isDense: true,
                  ),
                  onChanged: isInventory
                      ? null
                      : (v) => setStateDialog(() => updateFields()),
                ),
                if (isInventory) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.inventory_2, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Available: ${_getAvailableStock(inventoryMed)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _getAvailableStock(inventoryMed) < 10
                            ? Colors.red
                            : Colors.grey[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (!isInjection) ...[
                  const Text('Timing (M+E+N):',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: timingCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'e.g. 1+1+1',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final digits = v.replaceAll('+', '');
                      if (digits.length > 3) return;
                      final formatted = digits.split('').join('+');
                      if (timingCtrl.text != formatted) {
                        timingCtrl.text = formatted;
                        timingCtrl.selection = TextSelection.collapsed(
                            offset: formatted.length);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: mealTiming,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Timing Instruction',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      'Empty Stomach', 'Before Meal', 'During Meal',
                      'After Meal', 'Before Sleep',
                    ]
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setStateDialog(() => mealTiming = v!),
                  ),
                  if (isSyrup) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: dosage,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Dosage',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        '1 spoon', '1/2 spoon', '1/3 spoon', '1/4 spoon',
                      ]
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(d,
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setStateDialog(() => dosage = v!),
                    ),
                  ],
                ] else
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Enter medicine name'),
                    backgroundColor: Colors.redAccent));
                return;
              }
              if (_medicineExists(name, inventoryId: inventoryMed?['id'])) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Medicine already added'),
                    backgroundColor: Colors.orange));
                return;
              }

              Map<String, dynamic> newMed;
              if (isInjection) {
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                if (qty <= 0) return;

                // Validate stock for inventory items
                if (isInventory) {
                  final availableStock = _getAvailableStock(inventoryMed);
                  if (qty > availableStock) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('⚠️ Stock Limit Exceeded! Available: $availableStock'),
                      backgroundColor: Colors.red));
                    return;
                  }
                }

                newMed = {
                  'name': name, 'quantity': qty,
                  'type': 'Injection',
                  'inventoryId': inventoryMed?['id'],
                };
              } else {
                final digits = timingCtrl.text.replaceAll('+', '');
                final m = int.tryParse(
                        digits.isNotEmpty ? digits[0] : '0') ??
                    0;
                final e =
                    digits.length > 1 ? int.tryParse(digits[1]) ?? 0 : 0;
                final n =
                    digits.length > 2 ? int.tryParse(digits[2]) ?? 0 : 0;
                final sum = m + e + n;
                final qty =
                    (mealTiming == 'Before Sleep' && sum == 0) ? 1 : sum;
                if (qty == 0) return;

                // Validate stock for inventory items
                if (isInventory) {
                  final availableStock = _getAvailableStock(inventoryMed);
                  if (qty > availableStock) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('⚠️ Stock Limit Exceeded! Available: $availableStock'),
                      backgroundColor: Colors.red));
                    return;
                  }
                }

                newMed = {
                  'name': name, 'quantity': qty,
                  'timing': '$m+$e+$n', 'meal': mealTiming,
                  'dosage': isSyrup ? dosage : '',
                  'type': isSyrup ? 'Syrup' : 'Tablet',
                  'inventoryId': inventoryMed?['id'],
                };
              }

              setState(() => widget.prescriptions.add(newMed));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Added $name'),
                  backgroundColor: Colors.green));
              _searchController.clear();
              _searchResults.clear();
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _addCustomLabTest() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Custom Lab Test',
            style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Test name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty ||
                  widget.labResults.any((l) =>
                      (l['name'] ?? '').toString().trim() == name)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Invalid or duplicate test'),
                    backgroundColor: Colors.redAccent));
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

  Widget _sectionHeader(
    String title,
    IconData icon, {
    Widget? action,
    bool compact = false,
  }) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              FaIcon(icon, color: _teal, size: compact ? 16 : 20),
              SizedBox(width: compact ? 6 : 10),
              Text(title,
                  style: TextStyle(
                      fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.bold,
                      color: _teal)),
            ]),
            if (action != null) action,
          ],
        ),
      );

  Widget _buildMedicineSection(
    String title,
    IconData icon,
    List<Map<String, dynamic>> meds,
    Color chipColor, {
    bool compact = false,
  }) {
    if (meds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title, icon, compact: compact),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: meds.map((m) {
            final abbrev = _getMedAbbrev(m);
            final namePart = _getFormattedMedicine(m);
            final label = abbrev.isNotEmpty &&
                    !namePart
                        .toLowerCase()
                        .startsWith(abbrev.toLowerCase())
                ? '$abbrev $namePart ×${m['quantity']}'
                : '$namePart ×${m['quantity']}';
            return Chip(
              label: Text(label,
                  style: TextStyle(
                      fontSize: compact ? 11 : 13,
                      color: Colors.white)),
              backgroundColor: chipColor,
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 10),
              onDeleted: () =>
                  setState(() => widget.prescriptions.remove(m)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  // ── Main save ──────────────────────────────────────────────────────────

  Future<void> _savePrescriptionHiveFirst() async {
    final complaint = widget.complaintController.text.trim();
    final diagnosis = widget.diagnosisController.text.trim();

    if (complaint.isEmpty || diagnosis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Both Patient Condition and Diagnosis are required!'),
          backgroundColor: Colors.red));
      return;
    }
    if (widget.prescriptions.isEmpty && widget.labResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Please add at least one medicine or lab test!'),
          backgroundColor: Colors.orange));
      return;
    }

    try {
      final patientData =
          Map<String, dynamic>.from(widget.selectedPatientData ?? {});

      // Resolve CNIC
      String patientCnic = (patientData['cnic']?.toString() ??
              patientData['guardianCnic']?.toString() ??
              patientData['patientCnic']?.toString() ??
              '')
          .trim()
          .replaceAll(RegExp(r'[-\s]'), '');
      if (patientCnic.isEmpty || patientCnic == '0000000000000') {
        patientCnic =
            'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }

      // Use widget props directly — never read from patientData
      final doctorId   = widget.doctorId;
      final doctorName = widget.doctorName;
      final queueType  = widget.queueType;

      debugPrint('[DoctorPanel] saving — doctor="$doctorName" '
          'queue="$queueType" serial="${widget.serialId}"');

      final now         = DateTime.now();
      final nowIso      = now.toIso8601String();
      final serialClean = widget.serialId.trim().toLowerCase();
      final dateKey     = serialClean.split('-')[0];

      // ── Shared medicine + lab lists (built once, reused everywhere) ────────
      final medicineList = widget.prescriptions
          .map((m) => {
                'name':        m['name'],
                'quantity':    m['quantity'],
                'type':        m['type'] ?? 'Tablet',
                'timing':      m['timing'] ?? '',
                'meal':        m['meal'] ?? '',
                'dosage':      m['dosage'] ?? '',
                'inventoryId': m['inventoryId'],
              })
          .toList();

      final labList = widget.labResults
          .map((l) => {'name': l['name']})
          .toList();

      // ── Medical-only map — stored NESTED inside entry/serial docs ──────────
      // Contains ONLY what the dispenser/pharmacist needs; no patient meta.
      final medicalData = <String, dynamic>{
        'complaint':     complaint,
        'condition':     complaint,
        'diagnosis':     diagnosis,
        'prescriptions': medicineList,
        'labResults':    labList,
        'completedAt':   nowIso,
        'updatedAt':     nowIso,
      };

      // ── Full flat document — written to Hive prescriptions box and
      //    to Firestore prescriptions/{cnic}/prescriptions/{serial}.
      //    Every field appears exactly ONCE at the top level; there is no
      //    nested 'prescription' map here to avoid duplication.
      final fullPrescriptionData = <String, dynamic>{
        'id':            serialClean,
        'serial':        serialClean,
        'patientCnic':   patientCnic,
        'cnic':          patientCnic,
        'patientId':     patientData['patientId']?.toString() ??
            patientData['id']?.toString(),
        'guardianCnic':  patientData['guardianCnic']?.toString(),
        'patientName':   patientData['patientName'] ??
            patientData['name'] ?? 'Unknown',
        'patientAge':    patientData['age']?.toString() ?? 'N/A',
        'patientGender': patientData['gender']?.toString() ?? 'N/A',
        'complaint':     complaint,
        'condition':     complaint,
        'diagnosis':     diagnosis,
        'prescriptions': medicineList,
        'labResults':    labList,
        'completedAt':   nowIso,
        'updatedAt':     nowIso,
        'status':        'completed',
        'queueType':     queueType,
        'createdAt':     nowIso,
        'branchId':      widget.branchId,
        'dateKey':       dateKey,
        'doctorId':      doctorId,
        'doctorName':    doctorName,
        'prescribedBy':  doctorName,
        'updatedBy':     doctorName,
      };

      // 1. Save to Hive prescriptions box (full flat data for standalone access)
      await LocalStorageService.saveLocalPrescription(fullPrescriptionData);

      // 2. Embed ONLY medicalData into the Hive entry — patient/meta fields
      //    already live at the entry's top level, so we don't repeat them.
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      final entryKey = '${widget.branchId}-${widget.serialId}';
      final current = entriesBox.get(entryKey);
      if (current != null) {
        final updated = Map<String, dynamic>.from(current);
        updated['status']         = 'completed';
        updated['completedAt']    = nowIso;
        updated['prescription']   = medicalData; // medical details only — no duplication
        updated['prescriptionId'] = serialClean;
        updated['queueType']      = queueType;
        updated['doctorName']     = doctorName;
        updated['doctorId']       = doctorId;
        await entriesBox.put(entryKey, updated);
      }

      // 3. LAN broadcast — send the full flat doc so other screens have
      //    everything they need without unwrapping a nested map.
      try {
        RealtimeManager().sendMessage(RealtimeEvents.payload(
          type: RealtimeEvents.savePrescription,
          branchId: widget.branchId,
          data: fullPrescriptionData,
        ));
        final full = entriesBox.get(entryKey);
        if (full != null) {
          RealtimeManager().sendMessage(RealtimeEvents.payload(
            type: RealtimeEvents.saveEntry,
            branchId: widget.branchId,
            data: Map<String, dynamic>.from(full),
          ));
        }
      } catch (e) {
        debugPrint('[DoctorPanel] Broadcast failed: $e');
      }

      // 4. Clear UI & parent callbacks
      widget.complaintController.clear();
      widget.diagnosisController.clear();
      widget.prescriptions.clear();
      widget.labResults.clear();
      _selectedQuickTests.clear();
      widget.onEntryCompleted?.call();
      if (widget.onSavePrescription != null) {
        await widget.onSavePrescription!();
      }

      if (mounted) {
        Flushbar(
          message: '✅ Prescription saved & broadcast successfully',
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }

      // 5. Firestore sync in background
      _syncToFirestoreInBackground(
          dateKey, queueType, serialClean, patientCnic,
          fullPrescriptionData, medicalData);
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
    String dateKey,
    String queueType,
    String serial,
    String patientCnic,
    Map<String, dynamic> fullData,    // flat — for prescriptions/{cnic}/...
    Map<String, dynamic> medicalData, // medical only — nested in serial doc
  ) async {
    try {
      final result = await Connectivity().checkConnectivity();
      final isOnline = !result.contains(ConnectivityResult.none);

      if (isOnline) {
        final branchRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId);

        // Path A: prescriptions/{cnic}/prescriptions/{serial}
        // Stores the full flat document — one place, all fields, no nesting.
        if (patientCnic.isNotEmpty &&
            !patientCnic.startsWith('unknown_')) {
          await branchRef
              .collection('prescriptions')
              .doc(patientCnic)
              .collection('prescriptions')
              .doc(serial)
              .set(fullData, SetOptions(merge: true));
          debugPrint(
              '[DoctorPanel] ✅ Firestore prescriptions/$patientCnic/$serial');
        }

        // Path B: serials/{dateKey}/{queueType}/{serial}
        // Stores status/meta at top level + medicalData under 'prescription'
        // key so the dispenser has both queue info and Rx in one doc without
        // any field appearing twice.
        await branchRef
            .collection('serials')
            .doc(dateKey)
            .collection(queueType)
            .doc(serial)
            .set(
              {
                'status':       'completed',
                'completedAt':  fullData['completedAt'],
                'doctorName':   fullData['doctorName'],
                'doctorId':     fullData['doctorId'],
                'prescription': medicalData, // only medical details nested here
              },
              SetOptions(merge: true),
            );
        debugPrint(
            '[DoctorPanel] ✅ Firestore serials/$dateKey/$queueType/$serial');
      } else {
        await _enqueueSync(
            dateKey, queueType, serial, patientCnic, fullData, medicalData);
      }
    } catch (e) {
      debugPrint('[DoctorPanel] Firestore sync failed: $e');
      await _enqueueSync(
          dateKey, queueType, serial, patientCnic, fullData, medicalData);
    }
  }

  Future<void> _enqueueSync(
    String dateKey,
    String queueType,
    String serial,
    String patientCnic,
    Map<String, dynamic> fullData,
    Map<String, dynamic> medicalData,
  ) async {
    try {
      await LocalStorageService.enqueueSync({
        'type':        'save_prescription',
        'branchId':    widget.branchId,
        'dateKey':     dateKey,
        'queueType':   queueType,
        'serial':      serial,
        'patientCnic': patientCnic,
        'data':        fullData,
      });
      await LocalStorageService.enqueueSync({
        'type':      'update_serial_status',
        'branchId':  widget.branchId,
        'dateKey':   dateKey,
        'queueType': queueType,
        'serial':    serial,
        'data': {
          'status':       'completed',
          'completedAt':  fullData['completedAt'],
          'doctorName':   fullData['doctorName'],
          'doctorId':     fullData['doctorId'],
          'prescription': medicalData,
        },
      });
      SyncService().triggerUpload();
    } catch (e) {
      debugPrint('[DoctorPanel] Enqueue failed: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.isSaving) {
      return const Center(
          child: CircularProgressIndicator(color: _teal));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 500;

      return Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            final cur = _tabOrder.indexWhere((n) => n.hasFocus);
            final isShift = HardwareKeyboard.instance.physicalKeysPressed
                .contains(PhysicalKeyboardKey.shiftLeft);
            final next = isShift
                ? (cur <= 0 ? _tabOrder.length - 1 : cur - 1)
                : (cur + 1) % _tabOrder.length;
            _tabOrder[next].requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.all(compact ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Patient condition ───────────────────────────────────
              Row(children: [
                Icon(Icons.description,
                    color: _teal, size: compact ? 18 : 22),
                SizedBox(width: compact ? 6 : 10),
                Text('Patient Condition',
                    style: TextStyle(
                        fontSize: compact ? 15 : 18,
                        fontWeight: FontWeight.bold,
                        color: _teal)),
              ]),
              const SizedBox(height: 8),
              TextField(
                focusNode: _complaintFocus,
                controller: widget.complaintController,
                maxLines: 2,
                style: TextStyle(fontSize: compact ? 13 : 15),
                decoration: InputDecoration(
                  hintText: "Describe patient's condition...",
                  filled: true,
                  fillColor: Colors.green[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                  isDense: compact,
                ),
              ),
              SizedBox(height: compact ? 12 : 16),

              // ── Diagnosis ───────────────────────────────────────────
              Row(children: [
                Icon(Icons.medical_services,
                    color: _teal, size: compact ? 18 : 22),
                SizedBox(width: compact ? 6 : 10),
                Text('Diagnosis',
                    style: TextStyle(
                        fontSize: compact ? 15 : 18,
                        fontWeight: FontWeight.bold,
                        color: _teal)),
              ]),
              const SizedBox(height: 8),
              TextField(
                focusNode: _diagnosisFocus,
                controller: widget.diagnosisController,
                maxLines: 2,
                style: TextStyle(fontSize: compact ? 13 : 15),
                decoration: InputDecoration(
                  hintText: 'Enter diagnosis...',
                  filled: true,
                  fillColor: Colors.green[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                  isDense: compact,
                ),
              ),
              SizedBox(height: compact ? 12 : 20),

              // ── Medicine search ─────────────────────────────────────
              _sectionHeader('Medicines', FontAwesomeIcons.pills,
                  compact: compact),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 3))
                  ],
                ),
                child: TextField(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  style: TextStyle(fontSize: compact ? 13 : 15),
                  decoration: InputDecoration(
                    hintText: 'Search medicines...',
                    prefixIcon: const Icon(Icons.search, color: _teal),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchResults.clear());
                            },
                          ),
                        IconButton(
                          icon: const FaIcon(
                              FontAwesomeIcons.arrowsRotate,
                              size: 16),
                          onPressed: () async {
                            await LocalStorageService
                                .downloadInventory(widget.branchId);
                            _loadInventory();
                          },
                        ),
                      ],
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: compact ? 12 : 16),
                    isDense: compact,
                  ),
                ),
              ),

              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 6)
                    ],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _searchResults.length,
                    itemBuilder: (_, i) {
                      final m = _searchResults[i];
                      final availableStock = _getAvailableStock(m);
                      final label = _getFormattedMedicine(m);
                      final bool isOutOfStock = availableStock <= 0;

                      return ListTile(
                        dense: compact,
                        leading: FaIcon(_getMedicineIcon(m),
                            color: isOutOfStock ? Colors.grey : _teal,
                            size: 16),
                        title: Text(label,
                            style: TextStyle(
                                fontSize: compact ? 13 : 14,
                                color: isOutOfStock ? Colors.grey : Colors.black)),
                        trailing: Text(
                          isOutOfStock
                            ? 'Out of Stock'
                            : 'Stock: $availableStock',
                          style: TextStyle(
                            color: isOutOfStock
                                ? Colors.red
                                : availableStock < 10
                                  ? Colors.orange
                                  : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        enabled: !isOutOfStock,
                        onTap: isOutOfStock
                          ? null
                          : () => _addMedicineDialog(inventoryMed: m),
                      );
                    },
                  ),
                ),
              ] else if (_searchController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('No medicines found',
                      style: TextStyle(
                          color: Colors.grey[700], fontSize: 13)),
                ),
              ],

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _addMedicineDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('Add Custom',
                      style: TextStyle(
                          fontSize: compact ? 12 : 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                ),
              ),

              // ── Medicine chips ──────────────────────────────────────
              _buildMedicineSection(
                'Inventory Medicines', FontAwesomeIcons.pills,
                widget.prescriptions
                    .where((m) =>
                        m['inventoryId'] != null &&
                        !_isInjectionOrDrip(m))
                    .toList(),
                _teal, compact: compact,
              ),
              _buildMedicineSection(
                'Inventory Injectables', FontAwesomeIcons.syringe,
                widget.prescriptions
                    .where((m) =>
                        m['inventoryId'] != null &&
                        _isInjectionOrDrip(m))
                    .toList(),
                _orange, compact: compact,
              ),
              _buildMedicineSection(
                'Custom Medicines',
                FontAwesomeIcons.prescriptionBottle,
                widget.prescriptions
                    .where((m) =>
                        m['inventoryId'] == null &&
                        !_isInjectionOrDrip(m))
                    .toList(),
                _blueGrey, compact: compact,
              ),
              _buildMedicineSection(
                'Custom Injectables', FontAwesomeIcons.syringe,
                widget.prescriptions
                    .where((m) =>
                        m['inventoryId'] == null &&
                        _isInjectionOrDrip(m))
                    .toList(),
                _orange, compact: compact,
              ),

              const Divider(height: 1),
              SizedBox(height: compact ? 12 : 20),

              // ── Lab tests ───────────────────────────────────────────
              _sectionHeader(
                'Lab Tests', FontAwesomeIcons.flask,
                compact: compact,
                action: IconButton(
                  icon: Icon(Icons.add_circle_outline,
                      color: _teal, size: compact ? 20 : 24),
                  onPressed: _addCustomLabTest,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),

              Wrap(
                spacing: compact ? 6 : 10,
                runSpacing: compact ? 6 : 10,
                children: _quickLabTests.map((t) {
                  final selected = _selectedQuickTests.contains(t);
                  return FilterChip(
                    label: Text(t,
                        style: TextStyle(
                            fontSize: compact ? 11 : 13)),
                    selected: selected,
                    selectedColor: _teal,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.black87),
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) {
                      setState(() {
                        if (selected) {
                          _selectedQuickTests.remove(t);
                          widget.labResults
                              .removeWhere((l) => l['name'] == t);
                        } else {
                          _selectedQuickTests.add(t);
                          if (!widget.labResults
                              .any((l) => l['name'] == t)) {
                            widget.labResults.add({'name': t});
                          }
                        }
                      });
                    },
                  );
                }).toList(),
              ),

              if (widget.labResults
                  .any((l) => !_quickLabTests.contains(l['name']))) ...[
                const SizedBox(height: 12),
                Text('Custom Tests',
                    style: TextStyle(
                        fontSize: compact ? 13 : 16,
                        fontWeight: FontWeight.bold,
                        color: _teal)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.labResults
                      .where((l) =>
                          !_quickLabTests.contains(l['name']))
                      .map((l) => Chip(
                            label: Text(l['name'],
                                style: TextStyle(
                                    fontSize: compact ? 11 : 13)),
                            backgroundColor: Colors.orange.shade600,
                            labelStyle: const TextStyle(
                                color: Colors.white),
                            onDeleted: () => setState(
                                () => widget.labResults.remove(l)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ],

              SizedBox(height: compact ? 16 : 30),
              const Divider(height: 1),
              SizedBox(height: compact ? 16 : 30),

              // ── Save button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  focusNode: _saveButtonFocus,
                  onPressed: widget.isSaving
                      ? null
                      : _savePrescriptionHiveFirst,
                  icon: widget.isSaving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.save,
                          color: Colors.white),
                  label: Text(
                    widget.isSaving
                        ? 'Saving...'
                        : 'Save Prescription',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: compact ? 14 : 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    elevation: 6,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    });
  }
}