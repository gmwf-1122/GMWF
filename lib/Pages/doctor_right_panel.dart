import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:another_flushbar/flushbar.dart';

class DoctorRightPanel extends StatefulWidget {
  final String branchId;
  final Map? selectedPatientData;
  final TextEditingController complaintController;
  final TextEditingController diagnosisController;
  final List<Map<String, dynamic>> prescriptions;
  final List<Map<String, dynamic>> labResults;
  final bool isSaving;
  final VoidCallback onAddLabResult;
  final Function(int index) onRemoveLabResult;
  final Function(Map<String, dynamic>) onEditMedicine;
  final Function(int index) onRemoveMedicine;
  final Future Function()? onSavePrescription;
  final String serialId;

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
    required this.onEditMedicine,
    required this.onRemoveMedicine,
    this.onSavePrescription,
    required this.serialId,
  });

  @override
  State<DoctorRightPanel> createState() => _DoctorRightPanelState();
}

class _DoctorRightPanelState extends State<DoctorRightPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _complaintFocus = FocusNode();
  final FocusNode _diagnosisFocus = FocusNode();
  final FocusNode _saveButtonFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Vitals
  final TextEditingController _bpCtrl = TextEditingController();
  final TextEditingController _tempCtrl = TextEditingController();
  String _tempUnit = 'C';
  final TextEditingController _sugarCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  String _gender = 'Male';

  // Search & Inventory
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _allInventory = [];
  bool _inventoryLoaded = false;
  StreamSubscription? _inventorySubscription;
  List<Map<String, dynamic>> _inventoryMeds = [];
  List<Map<String, dynamic>> _injectableMeds = [];
  List<Map<String, dynamic>> _customMeds = [];
  bool _isLoadingSearch = false;
  int _selectedSearchIndex = -1;
  static const Color _green = Color(0xFF2E7D32);

  final List<String> _quickLabTests = [
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

  final Set<String> _selectedQuickTests = {};
  final Map<String, FocusNode> _quickLabFocusNodes = {};
  late final List<FocusNode> _tabOrder;

  @override
  void initState() {
    super.initState();
    _setupQuickLabFocusNodes();
    _initializeFocusOrder();
    _initializeFromExisting();
    _loadVitalsFromSelectedPatient();
    _loadAllInventory();
    _listenToInventoryChanges();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.selectedPatientData != null) {
        _complaintFocus.requestFocus();
      }
    });
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        setState(() => _selectedSearchIndex = -1);
      }
    });
  }

  void _setupQuickLabFocusNodes() {
    for (var test in _quickLabTests) {
      final node = FocusNode();
      node.addListener(() {
        setState(() {});
      });
      _quickLabFocusNodes[test] = node;
    }
  }

  void _initializeFocusOrder() {
    _tabOrder = [
      _complaintFocus,
      _diagnosisFocus,
      _searchFocusNode,
      ..._quickLabTests.map((t) => _quickLabFocusNodes[t]!).toList(),
      _saveButtonFocus,
    ];
  }

  @override
  void didUpdateWidget(covariant DoctorRightPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPatientData == null &&
        widget.selectedPatientData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _complaintFocus.requestFocus();
      });
    }
    if (!identical(oldWidget.prescriptions, widget.prescriptions) ||
        oldWidget.prescriptions.length != widget.prescriptions.length) {
      _initializeFromExisting();
      _loadVitalsFromPrescriptionDoc();
    }
    if (!identical(oldWidget.labResults, widget.labResults) ||
        oldWidget.labResults.length != widget.labResults.length) {
      _updateSelectedQuickTestsFromLabResults();
    }
  }

  void _updateSelectedQuickTestsFromLabResults() {
    _selectedQuickTests.clear();
    for (var t in widget.labResults) {
      final name = (t['name'] ?? '').toString().trim();
      if (name.isNotEmpty && _quickLabTests.contains(name)) {
        _selectedQuickTests.add(name);
      }
    }
  }

  Future<void> _loadAllInventory() async {
    if (_inventoryLoaded) return;
    setState(() => _isLoadingSearch = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .get();
      _allInventory = snap.docs.map((d) {
        final data = d.data();
        data['id'] = data['id'] ?? d.id;
        return data;
      }).toList();
      setState(() => _inventoryLoaded = true);
    } catch (e) {
      debugPrint('Inventory load error: $e');
    } finally {
      setState(() => _isLoadingSearch = false);
    }
  }

  void _listenToInventoryChanges() {
    _inventorySubscription = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory')
        .snapshots()
        .listen((snap) {
      _allInventory = snap.docs.map((d) {
        final data = d.data();
        data['id'] = data['id'] ?? d.id;
        return data;
      }).toList();
    });
  }

  void _onSearchChanged(String q) {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
        _selectedSearchIndex = -1;
      });
      return;
    }
    if (!_inventoryLoaded) {
      _loadAllInventory().then((_) => _performSearch(query));
    } else {
      _performSearch(query);
    }
  }

  void _performSearch(String query) {
    final lowerQuery = query.toLowerCase();
    final filtered = _allInventory
        .where((m) =>
            (m['name'] ?? '').toString().toLowerCase().startsWith(lowerQuery))
        .take(25)
        .toList();
    setState(() {
      _searchResults = filtered;
      _selectedSearchIndex = filtered.isEmpty ? -1 : 0;
    });
  }

  IconData _getMedicineIcon(Map<String, dynamic> med) {
    final typeName = (med['type'] ?? '').toString().trim().toLowerCase();
    return switch (typeName) {
      'pills' => FontAwesomeIcons.pills,
      'capsule' => FontAwesomeIcons.capsules,
      'syringe' || 'injection' => FontAwesomeIcons.syringe,
      'drip' => FontAwesomeIcons.tint,
      'tablets' || 'tablet' => FontAwesomeIcons.tablets,
      'bandage' => FontAwesomeIcons.bandage,
      'prescription' => FontAwesomeIcons.prescription,
      _ => FontAwesomeIcons.pills,
    };
  }

  void _initializeFromExisting() {
    _inventoryMeds = [];
    _injectableMeds = [];
    _customMeds = [];
    for (var m in widget.prescriptions) {
      if (m['inventoryId'] != null && m['inventoryId'].toString().isNotEmpty) {
        if (_isInjectionOrDrip(m)) {
          _injectableMeds.add(m);
        } else {
          _inventoryMeds.add(m);
        }
      } else {
        _customMeds.add(m);
      }
    }
    setState(() {});
  }

  void _loadVitalsFromSelectedPatient() {
    final p = widget.selectedPatientData;
    if (p == null) return;
    final vit = (p['vitals'] as Map?)?.cast<String, dynamic>() ?? {};
    if (vit.isNotEmpty) _applyVitals(vit);
  }

  Future<void> _loadVitalsFromPrescriptionDoc() async {
    try {
      final patient = widget.selectedPatientData;
      if (patient == null) return;
      final cnic = (patient['patientCNIC'] ?? patient['cnic'] ?? '').toString();
      final serial = (patient['serial'] ?? widget.serialId ?? '').toString();
      if (cnic.isEmpty || serial.isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(cnic)
          .collection('prescriptions')
          .doc(serial)
          .get();
      if (doc.exists) {
        final vit =
            (doc.data()?['vitals'] as Map?)?.cast<String, dynamic>() ?? {};
        if (vit.isNotEmpty) _applyVitals(vit);
      } else {
        _loadVitalsFromSelectedPatient();
      }
    } catch (e) {
      debugPrint('Vitals load error: $e');
    }
  }

  void _applyVitals(Map<String, dynamic> vit) {
    _bpCtrl.text = (vit['bp'] ?? '').toString();
    _tempCtrl.text = (vit['temp'] ?? '').toString();
    _tempUnit = (vit['tempUnit'] ?? _tempUnit).toString();
    _sugarCtrl.text = (vit['sugar'] ?? '').toString();
    _weightCtrl.text = (vit['weight'] ?? '').toString();
    _gender = (vit['gender'] ?? _gender).toString();
    setState(() {});
  }

  Future<Map<String, dynamic>> _fetchVitalsFromSerials() async {
    try {
      final now = DateTime.now();
      final dateKey =
          "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year}";
      final zakatRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey)
          .collection('zakat')
          .doc(widget.serialId);
      final nonZakatRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey)
          .collection('non-zakat')
          .doc(widget.serialId);
      final zakatSnap = await zakatRef.get();
      if (zakatSnap.exists) {
        final data = zakatSnap.data() ?? {};
        return (data['vitals'] as Map?)?.cast<String, dynamic>() ?? {};
      }
      final nonSnap = await nonZakatRef.get();
      if (nonSnap.exists) {
        final data = nonSnap.data() ?? {};
        return (data['vitals'] as Map?)?.cast<String, dynamic>() ?? {};
      }
    } catch (e) {
      debugPrint('Serial vitals error: $e');
    }
    return {};
  }

  Map<String, dynamic> _collectVitalsFromInputs() => {
        'bp': _bpCtrl.text.trim(),
        'temp': _tempCtrl.text.trim(),
        'tempUnit': _tempUnit,
        'sugar': _sugarCtrl.text.trim(),
        'weight': _weightCtrl.text.trim(),
        'gender': _gender,
      };

  Widget _buildTimingField(TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: 'e.g. 102',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
      style: const TextStyle(fontSize: 16, letterSpacing: 2),
      onChanged: (value) {
        final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length > 3) return;
        final formatted = digits.isEmpty ? '' : digits.split('').join('+');
        if (controller.text != formatted) {
          final oldOffset = controller.selection.baseOffset;
          controller.text = formatted;
          final newDigitCount = digits.length;
          int newOffset = newDigitCount * 2 - 1;
          if (newDigitCount < 3 && newOffset >= formatted.length)
            newOffset = formatted.length;
          controller.selection = TextSelection.collapsed(
              offset: newOffset.clamp(0, formatted.length));
        }
      },
    );
  }

  bool _isInjectionOrDrip(Map<String, dynamic> med) {
    final type = (med['type'] ?? '').toString().trim().toLowerCase();
    return type == 'injection' || type == 'drip';
  }

  Future<void> _addCustomMedicineDialog(String prefillName) async {
    final nameCtrl = TextEditingController(text: prefillName);
    final timingCtrl = TextEditingController();
    String mealTiming = 'After Meal';
    final options = ['Before Meal', 'After Meal', 'Before Sleep'];
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Medicine'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Medicine name',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              const Text('Timing (M+E+N):',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              _buildTimingField(timingCtrl),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: mealTiming,
                decoration: const InputDecoration(
                    labelText: 'Timing Instruction',
                    border: OutlineInputBorder()),
                items: options
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setStateDialog(() => mealTiming = v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return _showError('Enter medicine name.');
              if (_medicineExists(name)) return _showError('Already added.');
              final digits = timingCtrl.text.replaceAll('+', '');
              final m = int.tryParse(digits.isNotEmpty ? digits[0] : '0') ?? 0;
              final e = digits.length > 1 ? int.tryParse(digits[1]) ?? 0 : 0;
              final n = digits.length > 2 ? int.tryParse(digits[2]) ?? 0 : 0;
              if (m + e + n == 0 && mealTiming != 'Before Sleep')
                return _showError('Please select a timing or Before Sleep.');
              final timing = '$m+$e+$n';
              final newMed = {
                'name': name,
                'quantity': 1,
                'timing': timing,
                'meal': mealTiming,
                'inventoryId': null,
              };
              setState(() {
                widget.prescriptions.add(newMed);
                _customMeds.add(newMed);
                _searchResults.clear();
                _searchController.clear();
                _selectedSearchIndex = -1;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _addInventoryMedicineDialog(Map<String, dynamic> med) async {
    if (_isInjectionOrDrip(med)) {
      final qtyCtrl = TextEditingController(text: '1');
      final type = (med['type'] ?? '').toString().toLowerCase() == 'drip'
          ? 'Drip'
          : 'Injection';
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Add ${med['name']} ($type)'),
          content: TextField(
            controller: qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              onPressed: () {
                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                if (qty <= 0) return _showError('Enter valid quantity.');
                final newMed = {
                  'name': med['name'],
                  'quantity': qty,
                  'inventoryId': med['id'] ?? med['inventoryId'],
                  'injectable': true,
                };
                setState(() {
                  widget.prescriptions.add(newMed);
                  _injectableMeds.add(newMed);
                  _searchResults.clear();
                  _searchController.clear();
                  _selectedSearchIndex = -1;
                });
                _addAccessory('Syringe', qty);
                if (type == 'Drip') {
                  _addAccessory('IV Set', qty);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      final timingCtrl = TextEditingController();
      String mealTiming = 'After Meal';
      final options = ['Before Meal', 'After Meal', 'Before Sleep'];
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Add ${med['name']}'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateDialog) =>
                Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Timing (M+E+N):',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                _buildTimingField(timingCtrl),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: mealTiming,
                  decoration: const InputDecoration(
                      labelText: 'Timing Instruction',
                      border: OutlineInputBorder()),
                  items: options
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => mealTiming = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              onPressed: () {
                final digits = timingCtrl.text.replaceAll('+', '');
                final m =
                    int.tryParse(digits.isNotEmpty ? digits[0] : '0') ?? 0;
                final e = digits.length > 1 ? int.tryParse(digits[1]) ?? 0 : 0;
                final n = digits.length > 2 ? int.tryParse(digits[2]) ?? 0 : 0;
                if (m + e + n == 0 && mealTiming != 'Before Sleep')
                  return _showError('Please select a timing or Before Sleep.');
                final timing = '$m+$e+$n';
                final newMed = {
                  'name': med['name'],
                  'quantity': 1,
                  'timing': timing,
                  'meal': mealTiming,
                  'inventoryId': med['id'] ?? med['inventoryId'],
                };
                setState(() {
                  widget.prescriptions.add(newMed);
                  _inventoryMeds.add(newMed);
                  _searchResults.clear();
                  _searchController.clear();
                  _selectedSearchIndex = -1;
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  void _addAccessory(String accessoryName, int qty) {
    final lowerName = accessoryName.toLowerCase();
    final accessoryMed = _allInventory.firstWhere(
      (m) => (m['name'] ?? '').toString().toLowerCase() == lowerName,
      orElse: () => {},
    );
    if (accessoryMed.isEmpty) {
      return;
    }
    final inventoryId = accessoryMed['id'];
    final existing = _injectableMeds.firstWhere(
      (m) => (m['inventoryId'] ?? '') == inventoryId,
      orElse: () => {},
    );
    if (existing.isNotEmpty) {
      existing['quantity'] = (existing['quantity'] ?? 1) + qty;
    } else {
      final newAccessory = {
        'name': accessoryMed['name'],
        'quantity': qty,
        'inventoryId': inventoryId,
        'injectable': true,
      };
      setState(() {
        widget.prescriptions.add(newAccessory);
        _injectableMeds.add(newAccessory);
      });
    }
  }

  Future<void> _addCustomLabTest() async {
    final ctrl = TextEditingController();
    final focusNode = FocusNode();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Custom Lab Test'),
        content: RawKeyboardListener(
          focusNode: FocusNode(),
          onKey: (event) {
            if (event is RawKeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              final name = ctrl.text.trim();
              if (name.isNotEmpty &&
                  !_quickLabTests
                      .any((q) => q.toLowerCase() == name.toLowerCase()) &&
                  !widget.labResults.any((l) =>
                      (l['name'] ?? '').toString().trim().toLowerCase() ==
                      name.toLowerCase())) {
                setState(
                    () => widget.labResults.add({'name': name, 'result': ''}));
                Navigator.pop(context);
              }
            }
          },
          child: TextField(
            controller: ctrl,
            focusNode: focusNode,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Test name', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              if (_quickLabTests
                  .any((q) => q.toLowerCase() == name.toLowerCase()))
                return _showError('Already in quick list.');
              if (widget.labResults.any((l) =>
                  (l['name'] ?? '').toString().trim().toLowerCase() ==
                  name.toLowerCase())) return _showError('Lab already added.');
              setState(
                  () => widget.labResults.add({'name': name, 'result': ''}));
              Navigator.pop(context);
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  bool _medicineExists(String name) {
    final lower = name.trim().toLowerCase();
    return widget.prescriptions
        .any((m) => (m['name'] ?? '').toString().trim().toLowerCase() == lower);
  }

  Future<void> _savePrescription() async {
    final diagnosis = widget.diagnosisController.text.trim();
    if (diagnosis.isEmpty) return _showError('Please fill in all fields.');
    final patient = widget.selectedPatientData;
    if (patient == null) return _showError('Select a patient.');
    final cnic = patient['patientCNIC'] ?? patient['cnic'] ?? '';
    if (cnic.toString().isEmpty) return _showError('CNIC missing.');
    final serial = widget.serialId.trim();
    if (serial.isEmpty) return _showError('Serial missing.');
    try {
      Map<String, dynamic> vitals = await _fetchVitalsFromSerials();
      final allEmpty =
          vitals.values.every((v) => v == null || v.toString().isEmpty);
      if (allEmpty) {
        final inputs = _collectVitalsFromInputs();
        final inputsEmpty =
            inputs.values.every((v) => v == null || v.toString().isEmpty);
        if (!inputsEmpty) vitals = inputs;
      }
      final quickLabTests = _selectedQuickTests
          .map((t) => {'name': t.trim(), 'result': ''})
          .toList();
      final customLabResults = widget.labResults
          .where((t) => (t['name'] ?? '').toString().trim().isNotEmpty)
          .map((t) => {'name': t['name'], 'result': t['result'] ?? ''})
          .toList();
      final Set<String> seenNames = {};
      final List<Map<String, dynamic>> allLabResults = [];
      for (var lab in quickLabTests) {
        final String name = lab['name'] as String;
        if (seenNames.add(name)) allLabResults.add(lab);
      }
      for (var lab in customLabResults) {
        final String name = lab['name'] as String;
        allLabResults.removeWhere((l) => l['name'] == name);
        allLabResults.add(lab);
      }
      final docData = {
        'serial': serial,
        'cnic': cnic,
        'patientName': patient['patientName'] ?? patient['name'] ?? '',
        'complaint': widget.complaintController.text.trim(),
        'diagnosis': diagnosis,
        'prescriptions': widget.prescriptions.map((m) {
          if (m['injectable'] == true) {
            return {
              'name': m['name'],
              'quantity': m['quantity'] ?? 1,
              'inventoryId': m['inventoryId'],
              'injectable': true,
            };
          } else {
            return {
              'name': m['name'],
              'quantity': m['quantity'] ?? 1,
              'timing': m['timing'] ?? '0+0+0',
              'meal': m['meal'] ?? '',
              'inventoryId': m['inventoryId'],
            };
          }
        }).toList(),
        'labTests': quickLabTests,
        'labResults': allLabResults,
        'vitals': vitals,
        'doctorId': patient['doctorId'] ?? '',
        'doctorName': patient['doctorName'] ?? '',
        'status': 'prescribed',
        'createdAt': FieldValue.serverTimestamp(),
      };
      final presRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(cnic)
          .collection('prescriptions')
          .doc(serial);
      await presRef.set(docData);
      final now = DateTime.now();
      final dateKey =
          "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year}";
      final zakatRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey)
          .collection('zakat')
          .doc(widget.serialId);
      final nonZakatRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey)
          .collection('non-zakat')
          .doc(widget.serialId);
      final zakatSnap = await zakatRef.get();
      final nonZakatSnap = await nonZakatRef.get();
      DocumentReference serialRef = zakatSnap.exists
          ? zakatRef
          : (nonZakatSnap.exists ? nonZakatRef : zakatRef);
      await serialRef.set({'status': 'prescribed'}, SetOptions(merge: true));
      _showSuccess('Prescription saved!');
      setState(() {
        widget.complaintController.clear();
        widget.diagnosisController.clear();
        widget.prescriptions.clear();
        widget.labResults.clear();
        _inventoryMeds.clear();
        _injectableMeds.clear();
        _customMeds.clear();
        _selectedQuickTests.clear();
        _bpCtrl.clear();
        _tempCtrl.clear();
        _sugarCtrl.clear();
        _weightCtrl.clear();
        _tempUnit = 'C';
        _gender = 'Male';
        _searchResults.clear();
        _selectedSearchIndex = -1;
      });
    } catch (e) {
      _showError('Save error: $e');
    }
  }

  void _showError(String msg) {
    Flushbar(
            message: msg,
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.redAccent)
        .show(context);
  }

  void _showSuccess(String msg) {
    Flushbar(
            message: msg,
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700)
        .show(context);
  }

  Widget _sectionHeader(String title, IconData icon, {Widget? action}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            FaIcon(icon, color: _green, size: 18),
            const SizedBox(width: 6),
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          if (action != null) action,
        ],
      );

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _complaintFocus.dispose();
    _diagnosisFocus.dispose();
    _saveButtonFocus.dispose();
    _scrollController.dispose();
    _quickLabFocusNodes.values.forEach((node) => node.dispose());
    _inventorySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.tab) {
          final currentIndex = _tabOrder.indexWhere((n) => n.hasFocus);
          final isShift = HardwareKeyboard.instance.physicalKeysPressed
              .contains(PhysicalKeyboardKey.shiftLeft);
          int nextIndex;
          if (currentIndex == -1) {
            nextIndex = 0;
          } else {
            nextIndex = isShift
                ? (currentIndex <= 0 ? _tabOrder.length - 1 : currentIndex - 1)
                : (currentIndex + 1) % _tabOrder.length;
          }
          final nextNode = _tabOrder[nextIndex];
          if (nextNode.canRequestFocus) {
            nextNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            _saveButtonFocus.hasFocus &&
            !widget.isSaving) {
          if (widget.diagnosisController.text.trim().isEmpty) {
            _showError('Please fill in all fields.');
          } else {
            widget.onSavePrescription?.call() ?? _savePrescription();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Patient Condition', FontAwesomeIcons.userInjured),
            const SizedBox(height: 4),
            TextField(
              focusNode: _complaintFocus,
              controller: widget.complaintController,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Enter condition', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            _sectionHeader('Diagnosis', FontAwesomeIcons.stethoscope),
            const SizedBox(height: 4),
            TextField(
              focusNode: _diagnosisFocus,
              controller: widget.diagnosisController,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Enter diagnosis', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            _sectionHeader('Medicines', FontAwesomeIcons.pills),
            const SizedBox(height: 6),
            RawKeyboardListener(
              focusNode: FocusNode(canRequestFocus: false),
              onKey: (event) {
                if (event is RawKeyDownEvent && _searchFocusNode.hasFocus) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                      _searchResults.isNotEmpty) {
                    setState(() => _selectedSearchIndex =
                        (_selectedSearchIndex + 1) % _searchResults.length);
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                      _searchResults.isNotEmpty) {
                    setState(() => _selectedSearchIndex =
                        (_selectedSearchIndex - 1)
                            .clamp(-1, _searchResults.length - 1));
                  } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                    final query = _searchController.text.trim();
                    if (query.isEmpty) return;
                    if (_selectedSearchIndex >= 0 &&
                        _searchResults.isNotEmpty) {
                      final med = _searchResults[_selectedSearchIndex];
                      _addInventoryMedicineDialog(med);
                    } else {
                      _addCustomMedicineDialog(query);
                    }
                    _searchController.clear();
                    setState(() {
                      _searchResults.clear();
                      _selectedSearchIndex = -1;
                    });
                  }
                }
              },
              child: TextField(
                focusNode: _searchFocusNode,
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search medicines...',
                  prefixIcon: Icon(Icons.search, color: _green),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchResults.clear();
                              _selectedSearchIndex = -1;
                            });
                          })
                      : null,
                ),
              ),
            ),
            if (_isLoadingSearch) const LinearProgressIndicator(),
            if (_searchResults.isNotEmpty)
              SizedBox(
                height: 150,
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (_, i) {
                    final m = _searchResults[i];
                    final qty = (m['quantity'] ?? m['stock'] ?? 0);
                    final zero = qty == 0;
                    return ListTile(
                      dense: true,
                      selected: i == _selectedSearchIndex,
                      selectedTileColor: _green.withOpacity(0.1),
                      leading:
                          FaIcon(_getMedicineIcon(m), color: _green, size: 20),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(m['name'] ?? '')),
                          Text('Qty: $qty',
                              style: TextStyle(
                                  color: zero ? Colors.red : Colors.black87,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      onTap: () {
                        _addInventoryMedicineDialog(m);
                        _searchController.clear();
                        setState(() {
                          _searchResults.clear();
                          _selectedSearchIndex = -1;
                        });
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _addCustomMedicineDialog(''),
                icon: Icon(Icons.add, color: _green),
                label: Text('Add Custom', style: TextStyle(color: _green)),
              ),
            ),
            if (_inventoryMeds.isNotEmpty ||
                _injectableMeds.isNotEmpty ||
                _customMeds.isNotEmpty) ...[
              const SizedBox(height: 10),
              if (_inventoryMeds.isNotEmpty) ...[
                const Text('Inventory Medicines',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 6,
                  children: _inventoryMeds.map((m) {
                    final tooltip = '${m['timing']} • ${m['meal']}';
                    return Tooltip(
                      message: tooltip,
                      child: Chip(
                        label: Text(m['name'],
                            style: const TextStyle(color: Colors.white)),
                        onDeleted: () => setState(() {
                          _inventoryMeds.remove(m);
                          widget.prescriptions.remove(m);
                        }),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (_injectableMeds.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Injectables',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 6,
                  children: _injectableMeds.map((m) {
                    final tooltip = 'Qty: ${m['quantity']}';
                    return Tooltip(
                      message: tooltip,
                      child: Chip(
                        label: Text(m['name'],
                            style: const TextStyle(color: Colors.white)),
                        onDeleted: () => setState(() {
                          _injectableMeds.remove(m);
                          widget.prescriptions.remove(m);
                        }),
                        backgroundColor: Colors.orange.shade700,
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (_customMeds.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Custom Medicines',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 6,
                  children: _customMeds.map((m) {
                    return Tooltip(
                      message: '${m['timing']} • ${m['meal']}',
                      child: Chip(
                        label: Text(m['name'],
                            style: const TextStyle(color: Colors.white)),
                        onDeleted: () => setState(() {
                          _customMeds.remove(m);
                          widget.prescriptions.remove(m);
                        }),
                        backgroundColor: Colors.blueGrey.shade400,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
            const Divider(height: 24),
            _sectionHeader('Lab Tests', FontAwesomeIcons.flask,
                action: IconButton(
                  icon: Icon(Icons.add, color: _green, size: 22),
                  onPressed: _addCustomLabTest,
                  tooltip: 'Add Custom Test',
                )),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickLabTests.map((t) {
                final sel = _selectedQuickTests.contains(t);
                final focusNode = _quickLabFocusNodes[t]!;
                return Focus(
                  focusNode: focusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      setState(() {
                        if (sel) {
                          _selectedQuickTests.remove(t);
                          widget.labResults.removeWhere((l) => l['name'] == t);
                        } else {
                          _selectedQuickTests.add(t);
                          if (!widget.labResults.any((l) => l['name'] == t)) {
                            widget.labResults.add({'name': t, 'result': ''});
                          }
                        }
                      });
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Container(
                    decoration: focusNode.hasFocus
                        ? BoxDecoration(
                            border: Border.all(color: Colors.blue, width: 2),
                            borderRadius: BorderRadius.circular(20),
                          )
                        : null,
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (sel)
                            const Icon(Icons.check,
                                color: Colors.white, size: 16),
                          if (sel) const SizedBox(width: 4),
                          Text(t,
                              style: TextStyle(
                                  color: sel ? Colors.white : Colors.black87)),
                        ],
                      ),
                      selected: sel,
                      selectedColor: _green,
                      backgroundColor: Colors.white,
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() {
                          if (sel) {
                            _selectedQuickTests.remove(t);
                            widget.labResults
                                .removeWhere((l) => l['name'] == t);
                          } else {
                            _selectedQuickTests.add(t);
                            if (!widget.labResults.any((l) => l['name'] == t)) {
                              widget.labResults.add({'name': t, 'result': ''});
                            }
                          }
                        });
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            if (widget.labResults
                .any((l) => !_quickLabTests.contains(l['name']))) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.labResults
                    .where((l) => !_quickLabTests.contains(l['name']))
                    .map((l) {
                  final name = l['name'].toString().trim();
                  return Chip(
                    label:
                        Text(name, style: const TextStyle(color: Colors.white)),
                    backgroundColor: Colors.orange,
                    deleteIcon:
                        const Icon(Icons.close, size: 18, color: Colors.white),
                    onDeleted: () =>
                        setState(() => widget.labResults.remove(l)),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Center(
              child: ElevatedButton.icon(
                focusNode: _saveButtonFocus,
                onPressed: widget.isSaving
                    ? null
                    : () {
                        if (widget.diagnosisController.text.trim().isEmpty) {
                          _showError('Please fill in all fields.');
                          return;
                        }
                        widget.onSavePrescription?.call() ??
                            _savePrescription();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                icon: const Icon(Icons.save, color: Colors.white),
                label: Text(
                  widget.isSaving ? 'Saving...' : 'Save Prescription',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
