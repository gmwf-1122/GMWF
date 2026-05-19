// lib/pages/dispensary/doctor/doctor_right_panel.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:another_flushbar/flushbar.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';

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

  final String doctorId;
  final String doctorName;
  final bool isPhysiotherapist;

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
    required this.isPhysiotherapist,
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

  /// Number of days of medicine to dispense (1 = default, 2, 3)
  int _daysOfMedicine = 1;

  // ── FIX: Cross-patient reserved quantities ─────────────────────────────
  // Maps inventoryId → total quantity already prescribed across ALL
  // pending (not-yet-dispensed) patients in Hive.
  // Rebuilt by _buildReservedQuantities() on load and before each add.
  Map<String, int> _reservedQuantities = {};

  static const Color _teal     = Color(0xFF00695C);
  static const Color _orange   = Color(0xFFFF6D00);
  static const Color _blueGrey = Color(0xFF455A64);

  // Dose pill colours (teal ramp)
  static const Color _dosePillBg     = Color(0xFFE1F5EE);
  static const Color _dosePillBorder = Color(0xFF5DCAA5);
  static const Color _dosePillText   = Color(0xFF0F6E56);

  // Base price per day per queue type
  static const Map<String, int> _baseDayPrice = {
    'zakat':     20,
    'non-zakat': 100,
    'gmwf':      0,
  };

  final List<String> _quickLabTests = const [
    "CBC", "LFT", "RFT", "HbA1C", "BMP",
    "Urine R/E", "Lipid Profile", "ECG", "X-ray", "Ultrasound Abdomen",
  ];

  final List<String> _quickPhysiotherapies = const [
    "SWD (Shortwave Diathermy)", "Ultrasound Therapy", "TENS Therapy", "Cervical Traction", "Lumbar Traction",
    "Manual Therapy", "Therapeutic Exercises", "Hot Pack / Cold Pack", "Infrared Therapy (IRR)", "Laser Therapy",
  ];

  List<String> get _currentQuickList => widget.isPhysiotherapist ? _quickPhysiotherapies : _quickLabTests;

  final Set<String> _selectedQuickTests = {};

  late final List<FocusNode> _tabOrder = [
    _complaintFocus,
    _diagnosisFocus,
    _searchFocusNode,
    _saveButtonFocus,
  ];

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  // ── Derived: extra charge (PKR) ────────────────────────────────────────────
  int get _extraCharge {
    final pricePerDay = _baseDayPrice[widget.queueType] ?? 0;
    if (pricePerDay == 0) return 0;
    return (_daysOfMedicine - 1) * pricePerDay;
  }

  // ── Rule: if any injection is prescribed, only 1 day is allowed ───────────
  bool get _hasInjection => widget.prescriptions.any(_isInjectionOrDrip);

  @override
  void initState() {
    super.initState();
    _loadInventory();

    final quickList = _currentQuickList;
    for (final lab in widget.labResults) {
      final name = lab['name']?.toString() ?? '';
      if (quickList.contains(name)) _selectedQuickTests.add(name);
    }

    // Restore days if re-opening a partially-saved entry, or use receptionist suggestion
    final existing = widget.selectedPatientData?['prescription'];
    if (existing is Map) {
      final d = existing['daysOfMedicine'];
      if (d is int && d >= 1 && d <= 3) _daysOfMedicine = d;
    } else {
      // Receptionist suggestion (1, 2, or 3)
      final suggested = widget.selectedPatientData?['suggestedDays'];
      if (suggested is int && suggested >= 1 && suggested <= 3) {
        _daysOfMedicine = suggested;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _complaintFocus.requestFocus();
    });

    _searchController.addListener(() => _onSearchChanged(_searchController.text));
    _realtimeSub = RealtimeManager().messageStream.listen(_handleRealtimeUpdate);
  }

  void _handleRealtimeUpdate(Map<String, dynamic> event) {
    final type = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? event;
    if (type == null || data.isEmpty) return;

    final serial = data['serial'] as String?;
    if (serial == null || serial != widget.serialId) return;

    final msgBranch = data['branchId']?.toString().toLowerCase().trim();
    if (msgBranch != null && msgBranch != widget.branchId.toLowerCase().trim()) return;

    if (type == RealtimeEvents.saveEntry) {
      if (mounted) setState(() {});
    }

    // ── FIX: Rebuild reserved quantities when any dispense or prescription
    //         save happens on the LAN, so stock counts stay accurate.
    if (type == 'dispense_completed' || type == RealtimeEvents.savePrescription) {
      _buildReservedQuantities();
    }

    if (type == RealtimeEvents.savePrescription) {
      setState(() {
        widget.complaintController.text = data['complaint'] ?? data['condition'] ?? '';
        widget.diagnosisController.text = data['diagnosis'] ?? '';
        widget.prescriptions
          ..clear()
          ..addAll(
            (data['prescriptions'] as List<dynamic>?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ?? [],
          );
        widget.labResults
          ..clear()
          ..addAll(
            (data['labResults'] as List<dynamic>?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ?? [],
          );
        _selectedQuickTests
          ..clear()
          ..addAll(
            widget.labResults
                .map((l) => l['name']?.toString() ?? '')
                .where(_currentQuickList.contains),
          );
        final d = data['daysOfMedicine'];
        if (d is int && d >= 1 && d <= 3) _daysOfMedicine = d;
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
    final items = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId);
    if (mounted) {
      setState(() => _allInventory = items);
    }
    // Build reserved map after inventory is loaded
    await _buildReservedQuantities();
  }

  // ── FIX: Scan ALL pending prescriptions in Hive and sum up reserved qty ──
  // A prescription is "pending" (reserved) when:
  //   • it exists in the prescriptions box (doctor has saved it), AND
  //   • the corresponding entry in entriesBox does NOT have
  //     dispenseStatus == 'dispensed'.
  // We skip the current patient's serial so their own session counts
  // are handled separately by _getAvailableStock().
  Future<void> _buildReservedQuantities() async {
    final Map<String, int> reserved = {};

    try {
      final prescBox   = Hive.box(LocalStorageService.prescriptionsBox);
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      final mySerial   = widget.serialId.trim().toLowerCase();

      for (final key in prescBox.keys) {
        final raw = prescBox.get(key);
        if (raw is! Map) continue;
        final presc = Map<String, dynamic>.from(raw);

        // Skip the current patient — their session is handled in _getAvailableStock
        final prescSerial = (presc['serial'] ?? presc['id'] ?? '')
            .toString().trim().toLowerCase();
        if (prescSerial == mySerial) continue;

        // Check if already dispensed — look up in entriesBox
        final entryKey = '${widget.branchId}-$prescSerial';
        final entry    = entriesBox.get(entryKey);
        if (entry is Map) {
          final dispenseStatus =
              (entry['dispenseStatus'] ?? '').toString().toLowerCase();
          if (dispenseStatus == 'dispensed') continue;
        }

        // Also check dispenseStatus on the prescription itself
        final dispenseStatusOnPresc =
            (presc['dispenseStatus'] ?? '').toString().toLowerCase();
        if (dispenseStatusOnPresc == 'dispensed') continue;

        // Sum up quantities for each inventory medicine
        final meds = presc['prescriptions'];
        if (meds is! List) continue;

        for (final med in meds) {
          if (med is! Map) continue;
          final inventoryId = (med['inventoryId'] ?? '').toString().trim();
          if (inventoryId.isEmpty) continue;

          final qty = ((med['quantity'] ?? 0) as num).toInt();
          // For multi-day prescriptions, account for the multiplier
          // (injections/drips are always × 1)
          final days = (presc['daysOfMedicine'] as int?) ?? 1;
          final type = (med['type'] ?? '').toString().toLowerCase();
          final isInj = type.contains('injection') || type.contains('inj') ||
              type.contains('drip') || type.contains('syringe') ||
              type.contains('nebulization');
          final effectiveQty = isInj ? qty : qty * days;

          reserved[inventoryId] = (reserved[inventoryId] ?? 0) + effectiveQty;
        }
      }
    } catch (e) {
      debugPrint('[DoctorPanel] _buildReservedQuantities error: $e');
    }

    if (mounted) {
      setState(() => _reservedQuantities = reserved);
    }
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
    if (query.isEmpty) { setState(() => _searchResults.clear()); return; }
    final filtered = _allInventory.where((m) {
      return (m['name'] ?? '').toString().toLowerCase().contains(query) ||
          (m['type'] ?? '').toString().toLowerCase().contains(query) ||
          (m['dose'] ?? '').toString().toLowerCase().contains(query) ||
          (m['formula'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
    setState(() => _searchResults = filtered);
  }

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
        abbrev = entry.value; break;
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
        t.contains('drip') || t.contains('syringe') || t.contains('nebulization');
  }

  bool _medicineExists(String name, {String? inventoryId}) {
    final lower = name.trim().toLowerCase();
    return widget.prescriptions.any((m) =>
        (m['name'] ?? '').toString().trim().toLowerCase() == lower &&
        (inventoryId == null || m['inventoryId'] == inventoryId));
  }

  // ── FIX: Available stock = total stock − reserved by other patients
  //         − already added in this session
  int _getAvailableStock(Map<String, dynamic>? inventoryMed) {
    if (inventoryMed == null) return 999999;

    final totalStock  = ((inventoryMed['quantity'] ?? 0) as num).toInt();
    final inventoryId = inventoryMed['id']?.toString() ?? '';

    // Quantity reserved by OTHER pending patients (from Hive scan)
    final reservedByOthers = _reservedQuantities[inventoryId] ?? 0;

    // Quantity already added in THIS doctor session for this patient
    int sessionQty = 0;
    for (final med in widget.prescriptions) {
      if (med['inventoryId']?.toString() == inventoryId) {
        sessionQty += ((med['quantity'] ?? 0) as num).toInt();
      }
    }

    final available = totalStock - reservedByOthers - sessionQty;
    return available < 0 ? 0 : available;
  }

  Future<void> _addMedicineDialog({Map<String, dynamic>? inventoryMed}) async {
    // ── FIX: Refresh reserved quantities right before showing the dialog
    //         so we have the freshest picture of stock even if another
    //         patient was just saved while this doctor was typing.
    await _buildReservedQuantities();

    final isInventory = inventoryMed != null;

    if (isInventory) {
      final availableStock = _getAvailableStock(inventoryMed);
      if (availableStock <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(availableStock == 0
                ? '⚠️ Out of Stock! (reserved by pending patients)'
                : '⚠️ Stock Limit Exceeded! Available: $availableStock'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ));
        }
        return;
      }
    }

    final nameCtrl   = TextEditingController(text: isInventory ? inventoryMed['name'] : '');
    final timingCtrl = TextEditingController();
    final qtyCtrl    = TextEditingController(text: '1');
    String mealTiming = 'After Meal';
    String dosage     = '1 spoon';
    bool isSyrup      = false;
    bool isInjection  = false;

    final formula = isInventory
        ? (inventoryMed['formula'] ?? '').toString().trim()
        : '';

    void updateFields() {
      if (isInventory) {
        final type  = (inventoryMed['type'] ?? '').toString().toLowerCase();
        isInjection = type.contains('injection') || type.contains('inj');
        isSyrup     = type.contains('syrup') || type.contains('syp');
      } else {
        final text  = nameCtrl.text.toLowerCase();
        isInjection = text.contains('inj.');
        isSyrup     = text.contains('syp.');
      }
    }

    updateFields();
    if (!isInventory) nameCtrl.addListener(() => setState(() => updateFields()));

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
                    labelText: 'Formula',
                    border: const OutlineInputBorder(),
                    filled: isInventory,
                    fillColor: isInventory ? Colors.grey[200] : null,
                    isDense: true,
                  ),
                  onChanged: isInventory ? null : (v) => setStateDialog(() => updateFields()),
                ),
                if (isInventory) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.inventory_2, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Available: ${_getAvailableStock(inventoryMed)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: _getAvailableStock(inventoryMed) < 10 ? Colors.red : Colors.grey[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // ── FIX: Show how many are reserved by other patients
                    if ((_reservedQuantities[inventoryMed['id']?.toString() ?? ''] ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${_reservedQuantities[inventoryMed['id']?.toString() ?? '']} reserved)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ]),
                  if (formula.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.biotech_rounded, size: 15, color: Color(0xFF00695C)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            formula,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF00695C),
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                if (!isInjection) ...[
                  const Text('Timing (M+E+N):', style: TextStyle(fontSize: 13)),
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
                      final digits    = v.replaceAll('+', '');
                      if (digits.length > 3) return;
                      final formatted = digits.split('').join('+');
                      if (timingCtrl.text != formatted) {
                        timingCtrl.text      = formatted;
                        timingCtrl.selection = TextSelection.collapsed(offset: formatted.length);
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
                    items: ['Empty Stomach', 'Before Meal', 'During Meal', 'After Meal', 'Before Sleep']
                        .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setStateDialog(() => mealTiming = v!),
                  ),
                  if (isSyrup) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: dosage,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Dosage', border: OutlineInputBorder(), isDense: true,
                      ),
                      items: ['1 spoon', '1/2 spoon', '1/3 spoon', '1/4 spoon']
                          .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => dosage = v!),
                    ),
                  ],
                ] else
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity', border: OutlineInputBorder(), isDense: true,
                    ),
                  ),
              ],
            ),
          ),
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
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Enter medicine name'), backgroundColor: Colors.redAccent));
                return;
              }
              if (_medicineExists(name, inventoryId: inventoryMed?['id'])) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Medicine already added'), backgroundColor: Colors.orange));
                return;
              }

              Map<String, dynamic> newMed;
              if (isInjection) {
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                if (qty <= 0) return;
                if (isInventory) {
                  final availableStock = _getAvailableStock(inventoryMed);
                  if (qty > availableStock) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('⚠️ Stock Limit Exceeded! Available: $availableStock'),
                        backgroundColor: Colors.red));
                    return;
                  }
                }
                newMed = {'name': name, 'quantity': qty, 'type': 'Injection', 'inventoryId': inventoryMed?['id']};
              } else {
                final digits = timingCtrl.text.replaceAll('+', '');
                final m      = int.tryParse(digits.isNotEmpty ? digits[0] : '0') ?? 0;
                final e      = digits.length > 1 ? int.tryParse(digits[1]) ?? 0 : 0;
                final n      = digits.length > 2 ? int.tryParse(digits[2]) ?? 0 : 0;
                final sum    = m + e + n;
                final qty    = (mealTiming == 'Before Sleep' && sum == 0) ? 1 : sum;
                if (qty == 0) return;
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

              bool wasReset = false;
              setState(() {
                widget.prescriptions.add(newMed);
                // ── Rule: injection prescribed → force 1 day ───────────────
                if (_isInjectionOrDrip(newMed) && _daysOfMedicine > 1) {
                  _daysOfMedicine = 1;
                  wasReset = true;
                }
              });
              Navigator.pop(ctx);
              
              if (wasReset) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                      content: Text('Added $name. 💉 Duration reset to 1 day due to injection.'),
                      backgroundColor: Colors.orange.shade800,
                      duration: const Duration(seconds: 4)));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added $name'), backgroundColor: Colors.green));
              }
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
    final titleText = widget.isPhysiotherapist ? 'Add Custom Physiotherapy' : 'Add Custom Lab Test';
    final hintText = widget.isPhysiotherapist ? 'Therapy name' : 'Test name';
    final errorText = widget.isPhysiotherapist ? 'Invalid or duplicate therapy' : 'Invalid or duplicate test';
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titleText, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl, autofocus: true,
          decoration: InputDecoration(hintText: hintText, border: const OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _teal)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty || widget.labResults.any((l) => (l['name'] ?? '').toString().trim() == name)) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(errorText), backgroundColor: Colors.redAccent));
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

  Widget _sectionHeader(String title, IconData icon, {Widget? action, bool compact = false}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              FaIcon(icon, color: _teal, size: compact ? 16 : 20),
              SizedBox(width: compact ? 6 : 10),
              Text(title, style: TextStyle(
                  fontSize: compact ? 14 : 18, fontWeight: FontWeight.bold, color: _teal)),
            ]),
            if (action != null) action,
          ],
        ),
      );

  Widget _buildMedicineSection(
    String title, IconData icon,
    List<Map<String, dynamic>> meds,
    Color chipColor, {bool compact = false}) {
    if (meds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title, icon, compact: compact),
        Wrap(
          spacing: 6, runSpacing: 6,
          children: meds.map((m) {
            final abbrev   = _getMedAbbrev(m);
            final namePart = _getFormattedMedicine(m);
            final label = abbrev.isNotEmpty &&
                    !namePart.toLowerCase().startsWith(abbrev.toLowerCase())
                ? '$abbrev $namePart ×${m['quantity']}'
                : '$namePart ×${m['quantity']}';
            return Chip(
              label: Text(label,
                  style: TextStyle(fontSize: compact ? 11 : 13, color: Colors.white)),
              backgroundColor: chipColor,
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
              onDeleted: () => setState(() => widget.prescriptions.remove(m)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  // ── Days-of-medicine selector ──────────────────────────────────────────────
  Widget _buildDaysSelector(bool compact) {
    final pricePerDay = _baseDayPrice[widget.queueType] ?? 0;
    final isPaying    = pricePerDay > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          FaIcon(FontAwesomeIcons.calendarDays, color: _teal, size: compact ? 16 : 18),
          SizedBox(width: compact ? 6 : 10),
          Text('Days of Medicine',
              style: TextStyle(
                  fontSize: compact ? 14 : 16, fontWeight: FontWeight.bold, color: _teal)),
          if (isPaying && _extraCharge > 0) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Text(
                'Extra: PKR $_extraCharge',
                style: TextStyle(
                    fontSize: compact ? 11 : 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),

        Row(
          children: [1, 2, 3].map((day) {
            final isSelected  = _daysOfMedicine == day;
            // Disable multi-day buttons when injection is prescribed
            final isDisabled  = _hasInjection && day > 1;
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
                        : () => setState(() => _daysOfMedicine = day),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 13),
                      decoration: BoxDecoration(
                        color: effectiveColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isDisabled
                                ? Colors.grey.shade300
                                : isSelected
                                    ? _teal
                                    : Colors.grey.shade300,
                            width: isSelected && !isDisabled ? 2 : 1),
                        boxShadow: isSelected && !isDisabled
                            ? [BoxShadow(color: _teal.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))]
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                                fontSize: compact ? 18 : 22,
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
                                fontSize: compact ? 10 : 12,
                                color: isDisabled
                                    ? Colors.grey.shade400
                                    : isSelected
                                        ? Colors.white70
                                        : Colors.grey.shade500),
                          ),
                          if (!isDisabled && (_baseDayPrice[widget.queueType] ?? 0) > 0 && day > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                '+PKR ${(day - 1) * (_baseDayPrice[widget.queueType] ?? 0)}',
                                style: TextStyle(
                                    fontSize: compact ? 9 : 10,
                                    color: isSelected ? Colors.white70 : Colors.orange.shade600,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (isDisabled)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: FaIcon(FontAwesomeIcons.syringe,
                                  size: compact ? 9 : 10,
                                  color: Colors.grey.shade400),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),

        Text(
          () {
            final pricePerDay = _baseDayPrice[widget.queueType] ?? 0;
            if (pricePerDay == 0) return 'No charge for ${widget.queueType} patients.';
            final base = 'Day 1 fee (PKR $pricePerDay) collected at token desk.';
            return _extraCharge > 0
                ? '$base  Extra PKR $_extraCharge will be charged.'
                : base;
          }(),
          style: TextStyle(
              fontSize: compact ? 10 : 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic),
        ),

        if (_hasInjection) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(children: [
              FaIcon(FontAwesomeIcons.syringe, size: 13, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Injection prescribed — only 1 day of medicine is allowed. '
                  'Multi-day selection is disabled.',
                  style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ] else if (_daysOfMedicine > 1) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _teal.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: _teal.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Prescription is per-day (e.g. 1+1+1 stays 1+1+1). '
                  'Dispenser gives $_daysOfMedicine days\' worth of each '
                  'tablet/capsule/syrup in one go.',
                  style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      color: _teal.withValues(alpha: 0.8)),
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  // ── Main save ──────────────────────────────────────────────────────────────
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

    // ── FIX: Final stock check at save time to catch any race conditions
    for (final med in widget.prescriptions) {
      final inventoryId = med['inventoryId']?.toString() ?? '';
      if (inventoryId.isEmpty) continue;

      // Refresh reserved quantities one more time before saving
      await _buildReservedQuantities();

      final inventoryMed = _allInventory.firstWhere(
        (m) => m['id']?.toString() == inventoryId,
        orElse: () => {},
      );
      if (inventoryMed.isEmpty) continue;

      final available = _getAvailableStock(inventoryMed);
      // At save time we include THIS session's qty in available (since
      // _getAvailableStock subtracts session qty already), so compare
      // against the raw per-day qty.
      final perDayQty = ((med['quantity'] ?? 0) as num).toInt();
      // Re-add session qty to get "others only" available
      final othersOnly = available + perDayQty;

      final isInj = _isInjectionOrDrip(med);
      final required = isInj ? perDayQty : perDayQty * _daysOfMedicine;

      if (required > othersOnly) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              '⚠️ "${med['name']}" stock insufficient! '
              'Need $required but only $othersOnly available after reservations.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ));
        }
        return;
      }
    }

    try {
      final patientData = Map<String, dynamic>.from(widget.selectedPatientData ?? {});

      String patientCnic = (patientData['cnic']?.toString() ??
              patientData['guardianCnic']?.toString() ??
              patientData['patientCnic']?.toString() ?? '')
          .trim()
          .replaceAll(RegExp(r'[-\s]'), '');
      if (patientCnic.isEmpty || patientCnic == '0000000000000') {
        patientCnic = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }

      final doctorId    = widget.doctorId;
      final doctorName  = widget.doctorName;
      final queueType   = widget.queueType;
      final days        = _daysOfMedicine;
      final extraCharge = _extraCharge;

      debugPrint('[DoctorPanel] saving — doctor="$doctorName" '
          'queue="$queueType" serial="${widget.serialId}" '
          'days=$days extraCharge=$extraCharge');

      final now         = DateTime.now();
      final nowIso      = now.toIso8601String();
      final serialClean = widget.serialId.trim().toLowerCase();
      final dateKey     = serialClean.split('-')[0];

      final medicineList = widget.prescriptions.map((m) {
        return {
          'name':        m['name'],
          'quantity':    m['quantity'],   // per-day, unchanged
          'type':        m['type'] ?? 'Tablet',
          'timing':      m['timing'] ?? '',
          'meal':        m['meal'] ?? '',
          'dosage':      m['dosage'] ?? '',
          'inventoryId': m['inventoryId'],
        };
      }).toList();

      final labList = widget.labResults.map((l) => {'name': l['name']}).toList();

      final medicalData = <String, dynamic>{
        'complaint':       complaint,
        'condition':       complaint,
        'diagnosis':       diagnosis,
        'prescriptions':   medicineList,
        'labResults':      labList,
        'daysOfMedicine':  days,
        'extraCharge':     extraCharge,
        'completedAt':     nowIso,
        'updatedAt':       nowIso,
        'isPhysiotherapist': widget.isPhysiotherapist,
      };

      final fullPrescriptionData = <String, dynamic>{
        'id':              serialClean,
        'serial':          serialClean,
        'patientCnic':     patientCnic,
        'cnic':            patientCnic,
        'patientId':       patientData['patientId']?.toString() ?? patientData['id']?.toString(),
        'guardianCnic':    patientData['guardianCnic']?.toString(),
        'patientName':     patientData['patientName'] ?? patientData['name'] ?? 'Unknown',
        'patientAge':      patientData['age']?.toString() ?? 'N/A',
        'patientGender':   patientData['gender']?.toString() ?? 'N/A',
        'complaint':       complaint,
        'condition':       complaint,
        'diagnosis':       diagnosis,
        'prescriptions':   medicineList,
        'labResults':      labList,
        'daysOfMedicine':  days,
        'extraCharge':     extraCharge,
        'completedAt':     nowIso,
        'updatedAt':       nowIso,
        'status':          'completed',
        'queueType':       queueType,
        'createdAt':       nowIso,
        'branchId':        widget.branchId,
        'dateKey':         dateKey,
        'doctorId':        doctorId,
        'doctorName':      doctorName,
        'prescribedBy':    doctorName,
        'updatedBy':       doctorName,
        // ── FIX: Mark as not yet dispensed so _buildReservedQuantities
        //         picks it up correctly for subsequent patients
        'dispenseStatus':  'pending',
        'isPhysiotherapist': widget.isPhysiotherapist,
      };

      // 1. Hive prescriptions box
      await LocalStorageService.saveLocalPrescription(fullPrescriptionData);

      // Save medicine restriction for multi-day prescriptions
      if (days > 1) {
        // Use the unique patientId (Individual identifier) instead of just CNIC.
        // This ensures children (who share guardian CNIC) are restricted individually.
        final pId = patientData['patientId']?.toString().trim() ?? 
                    patientData['id']?.toString().trim() ?? '';
        
        if (pId.isNotEmpty) {
          await LocalStorageService.saveMedicineRestriction(
            branchId:    widget.branchId,
            patientId:   pId,
            daysCovered: days,
          );
          debugPrint('[DoctorPanel] ✅ Individual restriction saved for: $pId ($days days)');
        } else {
          debugPrint('[DoctorPanel] ⚠️ Cannot save restriction: No patientId found.');
        }
      }

      // 2. Embed into Hive entry
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      final entryKey   = '${widget.branchId}-${widget.serialId}';
      final current    = entriesBox.get(entryKey);
      if (current != null) {
        final updated = Map<String, dynamic>.from(current);
        updated['status']         = 'completed';
        updated['completedAt']    = nowIso;
        updated['prescription']   = medicalData;
        updated['prescriptionId'] = serialClean;
        updated['queueType']      = queueType;
        updated['doctorName']     = doctorName;
        updated['doctorId']       = doctorId;
        updated['daysOfMedicine'] = days;
        updated['extraCharge']    = extraCharge;
        // ── FIX: Explicitly NOT 'dispensed' yet so reserved qty is counted
        updated['dispenseStatus'] = 'pending';
        await entriesBox.put(entryKey, updated);
      }

      // 3. LAN broadcast
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

      // 4. Clear UI
      widget.complaintController.clear();
      widget.diagnosisController.clear();
      widget.prescriptions.clear();
      widget.labResults.clear();
      _selectedQuickTests.clear();
      setState(() => _daysOfMedicine = 1);
      widget.onEntryCompleted?.call();
      if (widget.onSavePrescription != null) await widget.onSavePrescription!();

      if (mounted) {
        final chargeMsg = extraCharge > 0 ? ' | Extra: PKR $extraCharge' : '';
        Flushbar(
          message: '✅ Prescription saved ($days day${days > 1 ? 's' : ''})$chargeMsg',
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }

      // 5. Firestore background sync
      _syncToFirestoreInBackground(
          dateKey, queueType, serialClean, patientCnic,
          fullPrescriptionData, medicalData);

      // 6. Enqueue extra-charge sync op
      if (extraCharge > 0) {
        _enqueueExtraChargeSync(
          branchId:    widget.branchId,
          serial:      serialClean,
          dateKey:     dateKey,
          queueType:   queueType,
          patientCnic: patientCnic,
          patientName: fullPrescriptionData['patientName'] as String,
          amount:      extraCharge,
          days:        days,
          doctorName:  doctorName,
          nowIso:      nowIso,
        );
      }

      // 7. ── FIX: Rebuild reserved quantities so the NEXT patient the
      //           doctor opens immediately sees accurate stock numbers
      await _buildReservedQuantities();

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

  void _enqueueExtraChargeSync({
    required String branchId,
    required String serial,
    required String dateKey,
    required String queueType,
    required String patientCnic,
    required String patientName,
    required int amount,
    required int days,
    required String doctorName,
    required String nowIso,
  }) {
    try {
      LocalStorageService.enqueueSync({
        'type':      'save_dispensary_charge',
        'branchId':  branchId,
        'serial':    serial,
        'dateKey':   dateKey,
        'queueType': queueType,
        'data': {
          'serial':          serial,
          'branchId':        branchId,
          'dateKey':         dateKey,
          'queueType':       queueType,
          'patientCnic':     patientCnic,
          'patientName':     patientName,
          'amount':          amount,
          'daysOfMedicine':  days,
          'chargeType':      'extra_days',
          'prescribedBy':    doctorName,
          'createdAt':       nowIso,
        },
      });
      SyncService().triggerUpload();
    } catch (e) {
      debugPrint('[DoctorPanel] Extra-charge enqueue failed: $e');
    }
  }

  Future<void> _syncToFirestoreInBackground(
    String dateKey, String queueType, String serial, String patientCnic,
    Map<String, dynamic> fullData, Map<String, dynamic> medicalData,
  ) async {
    try {
      final result   = await Connectivity().checkConnectivity();
      final isOnline = !result.contains(ConnectivityResult.none);

      if (isOnline) {
        final branchRef = FirebaseFirestore.instance.collection('branches').doc(widget.branchId);

        if (patientCnic.isNotEmpty && !patientCnic.startsWith('unknown_')) {
          await branchRef
              .collection('prescriptions').doc(patientCnic)
              .collection('prescriptions').doc(serial)
              .set(fullData, SetOptions(merge: true));
        }

        await branchRef
            .collection('serials').doc(dateKey)
            .collection(queueType).doc(serial)
            .set({
              'status':          'completed',
              'completedAt':     fullData['completedAt'],
              'doctorName':      fullData['doctorName'],
              'doctorId':        fullData['doctorId'],
              'daysOfMedicine':  fullData['daysOfMedicine'],
              'extraCharge':     fullData['extraCharge'],
              'prescription':    medicalData,
              'dispenseStatus':  'pending',
            }, SetOptions(merge: true));
      } else {
        await _enqueueSync(dateKey, queueType, serial, patientCnic, fullData, medicalData);
      }
    } catch (e) {
      debugPrint('[DoctorPanel] Firestore sync failed: $e');
      await _enqueueSync(dateKey, queueType, serial, patientCnic, fullData, medicalData);
    }
  }

  Future<void> _enqueueSync(
    String dateKey, String queueType, String serial, String patientCnic,
    Map<String, dynamic> fullData, Map<String, dynamic> medicalData,
  ) async {
    try {
      await LocalStorageService.enqueueSync({
        'type': 'save_prescription', 'branchId': widget.branchId,
        'dateKey': dateKey, 'queueType': queueType,
        'serial': serial, 'patientCnic': patientCnic, 'data': fullData,
      });
      await LocalStorageService.enqueueSync({
        'type': 'update_serial_status', 'branchId': widget.branchId,
        'dateKey': dateKey, 'queueType': queueType, 'serial': serial,
        'data': {
          'status':          'completed',
          'completedAt':     fullData['completedAt'],
          'doctorName':      fullData['doctorName'],
          'doctorId':        fullData['doctorId'],
          'daysOfMedicine':  fullData['daysOfMedicine'],
          'extraCharge':     fullData['extraCharge'],
          'prescription':    medicalData,
          'dispenseStatus':  'pending',
        },
      });
      SyncService().triggerUpload();
    } catch (e) {
      debugPrint('[DoctorPanel] Enqueue failed: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.isSaving) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 500;

      return Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
            final cur     = _tabOrder.indexWhere((n) => n.hasFocus);
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
              // ── Patient condition ─────────────────────────────────────
              Row(children: [
                Icon(Icons.description, color: _teal, size: compact ? 18 : 22),
                SizedBox(width: compact ? 6 : 10),
                Text('Patient Condition',
                    style: TextStyle(
                        fontSize: compact ? 15 : 18, fontWeight: FontWeight.bold, color: _teal)),
              ]),
              const SizedBox(height: 8),
              TextField(
                focusNode: _complaintFocus,
                controller: widget.complaintController,
                maxLines: 2,
                style: TextStyle(fontSize: compact ? 13 : 15),
                decoration: InputDecoration(
                  hintText: "Describe patient's condition...",
                  filled: true, fillColor: Colors.green[50],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(12), isDense: compact,
                ),
              ),
              SizedBox(height: compact ? 12 : 16),

              // ── Diagnosis ─────────────────────────────────────────────
              Row(children: [
                Icon(Icons.medical_services, color: _teal, size: compact ? 18 : 22),
                SizedBox(width: compact ? 6 : 10),
                Text('Diagnosis',
                    style: TextStyle(
                        fontSize: compact ? 15 : 18, fontWeight: FontWeight.bold, color: _teal)),
              ]),
              const SizedBox(height: 8),
              TextField(
                focusNode: _diagnosisFocus,
                controller: widget.diagnosisController,
                maxLines: 2,
                style: TextStyle(fontSize: compact ? 13 : 15),
                decoration: InputDecoration(
                  hintText: 'Enter diagnosis...',
                  filled: true, fillColor: Colors.green[50],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(12), isDense: compact,
                ),
              ),
              SizedBox(height: compact ? 12 : 20),

              // ── Days selector ─────────────────────────────────────────
              _buildDaysSelector(compact),
              SizedBox(height: compact ? 12 : 20),
              const Divider(height: 1),
              SizedBox(height: compact ? 12 : 20),

              // ── Medicine search ───────────────────────────────────────
              _sectionHeader('Medicines', FontAwesomeIcons.pills, compact: compact),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
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
                          icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 16),
                          onPressed: () async {
                            await LocalStorageService.downloadInventory(widget.branchId);
                            _loadInventory();
                          },
                        ),
                      ],
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 12 : 16),
                    isDense: compact,
                  ),
                ),
              ),

              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _searchResults.length,
                    itemBuilder: (_, i) {
                      final m              = _searchResults[i];
                      final availableStock = _getAvailableStock(m);
                      final isOutOfStock   = availableStock <= 0;
                      final formula        = (m['formula'] ?? '').toString().trim();
                      final dose           = (m['dose'] ?? '').toString().trim();
                      final medicineName   = (m['name'] ?? '').toString().trim();
                      // ── FIX: Show reserved count in trailing label
                      final reservedCount  = _reservedQuantities[m['id']?.toString() ?? ''] ?? 0;

                      return ListTile(
                        dense: compact,
                        leading: FaIcon(
                          _getMedicineIcon(m),
                          color: isOutOfStock ? Colors.grey : _teal,
                          size: 16,
                        ),
                        // ── NEW: Name + dose pill badge side by side ──────────
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                medicineName,
                                style: TextStyle(
                                  fontSize: compact ? 13 : 14,
                                  color: isOutOfStock ? Colors.grey : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (dose.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOutOfStock
                                      ? Colors.grey.shade200
                                      : _dosePillBg,
                                  border: Border.all(
                                    color: isOutOfStock
                                        ? Colors.grey.shade400
                                        : _dosePillBorder,
                                    width: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  dose,
                                  style: TextStyle(
                                    fontSize: compact ? 10 : 11,
                                    fontWeight: FontWeight.w500,
                                    color: isOutOfStock
                                        ? Colors.grey.shade600
                                        : _dosePillText,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: formula.isNotEmpty
                            ? Text(
                                formula,
                                style: TextStyle(
                                  fontSize: compact ? 10 : 12,
                                  color: isOutOfStock
                                      ? Colors.grey.shade400
                                      : _teal.withValues(alpha: 0.75),
                                  fontStyle: FontStyle.italic,
                                ),
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isOutOfStock ? 'Out of Stock' : 'Avail: $availableStock',
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
                            // ── FIX: Show reserved count if any
                            if (reservedCount > 0)
                              Text(
                                '$reservedCount reserved',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                        enabled: !isOutOfStock,
                        onTap: isOutOfStock ? null : () => _addMedicineDialog(inventoryMed: m),
                      );
                    },
                  ),
                ),
              ] else if (_searchController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                  child: Text('No medicines found', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                ),
              ],

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _addMedicineDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('Add Custom', style: TextStyle(fontSize: compact ? 12 : 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),

              // ── Medicine chips ────────────────────────────────────────
              _buildMedicineSection(
                  'Inventory Medicines', FontAwesomeIcons.pills,
                  widget.prescriptions.where((m) => m['inventoryId'] != null && !_isInjectionOrDrip(m)).toList(),
                  _teal, compact: compact),
              _buildMedicineSection(
                  'Inventory Injectables', FontAwesomeIcons.syringe,
                  widget.prescriptions.where((m) => m['inventoryId'] != null && _isInjectionOrDrip(m)).toList(),
                  _orange, compact: compact),
              _buildMedicineSection(
                  'Custom Medicines', FontAwesomeIcons.prescriptionBottle,
                  widget.prescriptions.where((m) => m['inventoryId'] == null && !_isInjectionOrDrip(m)).toList(),
                  _blueGrey, compact: compact),
              _buildMedicineSection(
                  'Custom Injectables', FontAwesomeIcons.syringe,
                  widget.prescriptions.where((m) => m['inventoryId'] == null && _isInjectionOrDrip(m)).toList(),
                  _orange, compact: compact),

              const Divider(height: 1),
              SizedBox(height: compact ? 12 : 20),

              // ── Lab tests ─────────────────────────────────────────────
              _sectionHeader(widget.isPhysiotherapist ? 'Physiotherapies' : 'Lab Tests', widget.isPhysiotherapist ? FontAwesomeIcons.personWalking : FontAwesomeIcons.flask,
                  compact: compact,
                  action: IconButton(
                    icon: Icon(Icons.add_circle_outline, color: _teal, size: compact ? 20 : 24),
                    onPressed: _addCustomLabTest,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )),

              Wrap(
                spacing: compact ? 6 : 10, runSpacing: compact ? 6 : 10,
                children: _currentQuickList.map((t) {
                  final selected = _selectedQuickTests.contains(t);
                  return FilterChip(
                    label: Text(t, style: TextStyle(fontSize: compact ? 11 : 13)),
                    selected: selected,
                    selectedColor: _teal,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

              if (widget.labResults.any((l) => !_currentQuickList.contains(l['name']))) ...[
                const SizedBox(height: 12),
                Text(widget.isPhysiotherapist ? 'Custom Physiotherapies' : 'Custom Tests',
                    style: TextStyle(
                        fontSize: compact ? 13 : 16, fontWeight: FontWeight.bold, color: _teal)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: widget.labResults
                      .where((l) => !_currentQuickList.contains(l['name']))
                      .map((l) => Chip(
                            label: Text(l['name'], style: TextStyle(fontSize: compact ? 11 : 13)),
                            backgroundColor: Colors.orange.shade600,
                            labelStyle: const TextStyle(color: Colors.white),
                            onDeleted: () => setState(() => widget.labResults.remove(l)),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ],

              SizedBox(height: compact ? 16 : 30),
              const Divider(height: 1),
              SizedBox(height: compact ? 16 : 30),

              // ── Save button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  focusNode: _saveButtonFocus,
                  onPressed: widget.isSaving ? null : _savePrescriptionHiveFirst,
                  icon: widget.isSaving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, color: Colors.white),
                  label: Text(
                    widget.isSaving
                        ? 'Saving...'
                        : _extraCharge > 0
                            ? 'Save Prescription  (+PKR $_extraCharge)'
                            : 'Save Prescription',
                    style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: 24, vertical: compact ? 14 : 18),
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
