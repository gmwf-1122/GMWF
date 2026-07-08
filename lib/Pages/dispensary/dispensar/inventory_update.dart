// lib/pages/dispensary/dispensar/inventory_update.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/pages/request.dart';

class InventoryUpdatePage extends StatefulWidget {
  final String branchId;
  final bool isAdmin;
  final bool isDispenser;
  final bool isEmbedded;
  final int showMode; // 0: both, 1: Add Stock, 2: Register New

  const InventoryUpdatePage({
    super.key,
    required this.branchId,
    this.isAdmin = false,
    this.isDispenser = false,
    this.isEmbedded = false,
    this.showMode = 0,
  });

  @override
  State<InventoryUpdatePage> createState() => _InventoryUpdatePageState();
}

class _InventoryUpdatePageState extends State<InventoryUpdatePage>
    with TickerProviderStateMixin {
  // ── Palette ───────────────────────────────────────────────────────────────
  static const _teal = Color(0xFF00695C);
  static const _tealDark = Color(0xFF004D40);
  static const _bg = Color(0xFFF1F8F6);
  static const _white = Colors.white;
  static const _green50 = Color(0xFFE8F5E9);
  static const _green100 = Color(0xFFC8E6C9);
   static const _green600 = Color(0xFF2E7D32);
  static const _red = Color(0xFFD32F2F); // Vibrant red
  static const _orange = Color(0xFFE65100);
  static const _blue = Color(0xFF1976D2);
  static const _purple = Color(0xFF6A1B9A);
  static const _textDark = Color(0xFF1B2631);
  static const _textMid = Color(0xFF4A5568);
  static const _textLight = Color(0xFF718096);
  static const _border = Color(0xFFB2DFDB);
  static const _shadow = Color(0x1800695C);

  late TabController _tabCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── Add Stock state ───────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _hasSearched = false;
  Map<String, dynamic>? _selectedMed;
  String? _selectedDocId;
  final _addQtyCtrl = TextEditingController(text: '1');
  bool _isSubmittingStock = false;

  // ── Register New Medicine state ───────────────────────────────────────────
  final _regFormKey = GlobalKey<FormState>();
  final _regNameCtrl = TextEditingController();
  final _regQtyCtrl = TextEditingController(text: '1');
  final _regExpCtrl = TextEditingController();
  final _regPriceCtrl = TextEditingController();
  final _regDoseCtrl = TextEditingController();
  String _regType = 'Tablet';
  String? _regSelectedDose;
  bool _isSubmittingReg = false;

  final List<String> _allTypes = [
    'Tablet', 'Capsule', 'Syrup', 'Injection',
    'Drip', 'Drip Set', 'Syringe', 'Nebulization', 'Others',
  ];

  final Map<String, List<String>> _doseOptions = {
    'Tablet': [
      '2 mg',
      '5 mg',
      '20 mg',
      '40 mg',
      '50 mg',
      '100 mg',
      '250 mg',
      '300 mg',
      '400 mg',
      '500 mg',
      '650 mg',
      '1 g'
    ],
    'Capsule': [
      '2 mg',
      '5 mg',
      '10 mg',
      '20 mg',
      '25 mg',
      '40 mg',
      '50 mg',
      '100 mg',
      '250 mg',
      '500 mg'
    ],
    'Syrup': ['5 ml', '10 ml', '15 ml', '20 ml', '30 ml', '60 ml', '90 ml', '120 ml', '250 ml'],
    'Injection': ['1cc', '2cc', '3cc', '5cc', '10cc'],
    'Drip': ['100 ml', '250 ml', '450 ml', '500 ml', '1000 ml'],
  };

  bool get _hasDoseDropdown => _doseOptions.containsKey(_regType);
  bool get _usesFreeTextDose =>
      !_doseOptions.containsKey(_regType) &&
      _regType != 'Drip Set' &&
      _regType != 'Syringe';

  // ── INIT & LIFECYCLE ────────────────────────────────═══════════════════════
  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();

    _loadAllMedicines();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    _addQtyCtrl.dispose();
    _regNameCtrl.dispose();
    _regQtyCtrl.dispose();
    _regExpCtrl.dispose();
    _regPriceCtrl.dispose();
    _regDoseCtrl.dispose();
    super.dispose();
  }

  // ── Helper methods ────────────────────────────────────────────────────────
  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(err ? Icons.error_rounded : Icons.check_circle_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg,
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
        ]),
        backgroundColor: err ? _red : _green600,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Submit: Edit Request (needs approval or direct update for admin) ─────
  Future<void> _submitEditRequest(
      Map<String, dynamic> originalMed, Map<String, dynamic> updatedFields) async {
    try {
      final userInfo = await _getUserInfo();
      final db = FirebaseFirestore.instance;

      if (widget.isAdmin) {
        final docId = originalMed['_docId'] ?? originalMed['id'] ?? originalMed['medicineId'];
        if (docId != null) {
          await db
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory')
              .doc(docId)
              .update(Map<String, dynamic>.from(updatedFields)..addAll({
                'updatedAt': FieldValue.serverTimestamp(),
              }));

          // Log the direct edit
          await db
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory_log')
              .add({
            'action': 'edit_medicine_directly',
            'medicineName': originalMed['name'],
            'medicineId': docId,
            'updatedFields': updatedFields,
            'performedBy': userInfo['uid'],
            'performedByName': userInfo['username'],
            'timestamp': FieldValue.serverTimestamp(),
          });

          _snack('Medicine updated successfully!');
          _loadAllMedicines();
          return;
        }
      }

      await db
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .add({
        'requestType': 'edit_medicine',
        'requestedBy': userInfo['uid'],
        'requestedByName': userInfo['username'],
        'requesterName': userInfo['username'],
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'reason': updatedFields['reason'] ?? '',
        'docId': originalMed['_docId'] ?? originalMed['id'],
        'originalData': {
          'name': originalMed['name'],
          'type': originalMed['type'],
          'dose': originalMed['dose'],
          'price': originalMed['price'],
          'expiryDate': originalMed['expiryDate'],
          'quantity': originalMed['quantity'],
        },
        'draftItems': [{
          ...updatedFields,
          'oldId': originalMed['_docId'] ?? originalMed['id'],
        }],
        'items': [{
          ...updatedFields,
          'oldId': originalMed['_docId'] ?? originalMed['id'],
        }],
      });

      _snack('Edit request submitted for supervisor approval');
    } catch (e) {
      _snack('Error submitting request: $e', err: true);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return Container(
        color: _bg,
        child: widget.showMode == 1 ? _addStockTab() : _registerTab(),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: TabBarView(
          controller: _tabCtrl,
          children: [_addStockTab(), _registerTab()],
        ),
      ),
    );
  }

  IconData _typeIcon(String t) => switch (t) {
        'Tablet' => FontAwesomeIcons.tablets,
        'Capsule' => FontAwesomeIcons.capsules,
        'Syrup' => FontAwesomeIcons.bottleDroplet,
        'Injection' => FontAwesomeIcons.syringe,
        'Drip' => FontAwesomeIcons.bottleDroplet,
        'Drip Set' => FontAwesomeIcons.kitMedical,
        'Syringe' => FontAwesomeIcons.syringe,
        'Nebulization' => FontAwesomeIcons.wind,
        _ => FontAwesomeIcons.pills,
      };

  InputDecoration _inputDec(String label,
      {IconData? icon, Widget? prefix, String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _textLight, fontSize: 13),
        hintStyle: const TextStyle(color: _textLight, fontSize: 13),
        prefixIcon: prefix ??
            (icon != null ? Icon(icon, color: _teal, size: 18) : null),
        filled: true,
        fillColor: _green50,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _teal, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _red)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _red)),
        errorStyle: const TextStyle(color: _red, fontSize: 11),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      );

  bool _isExpiringSoon(String? exp) {
    if (exp == null || exp.isEmpty) return false;
    try {
      final parts = exp.split('-');
      if (parts.length != 3) return false;
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final date = DateTime(year, month, day);
      final diff = date.difference(DateTime.now()).inDays;
      return diff <= 30 && diff >= 0;
    } catch (_) {
      return false;
    }
  }

  Widget _statusLabel({required bool lowStock, required bool expSoon}) {
    String label = '';
    if (lowStock && expSoon) {
      label = 'CRITICAL: LOW STOCK & NEAR EXPIRY';
    } else if (lowStock) {
      label = 'WARNING: LOW STOCK';
    } else if (expSoon) {
      label = 'ALERT: NEAR EXPIRY';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: _red, // Solid red background
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: _red.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white, // High contrast white text
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }



  Future<Map<String, String>> _getUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'uid': '', 'username': 'Unknown'};
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(user.uid)
          .get();
      final username =
          doc.data()?['username']?.toString() ?? user.email ?? 'Unknown';
      return {'uid': user.uid, 'username': username};
    } catch (_) {
      return {'uid': user.uid, 'username': user.email ?? 'Unknown'};
    }
  }

  // ── Load all medicines on start (Hive-first for instant offline updates) ───
  Future<void> _loadAllMedicines() async {
    setState(() => _isSearching = true);
    try {
      final localItems = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId);
      final Map<String, Map<String, dynamic>> consolidated = {};
      final Set<String> processedDocIds = {};

      void processItem(Map<String, dynamic> d) {
        final docId = d['_docId'] ?? d['id'] ?? d['docId'];
        if (docId != null) {
          if (processedDocIds.contains(docId)) return;
          processedDocIds.add(docId);
        }

        final key = '${d['name']}|${d['type']}|${d['dose']}';
        if (!consolidated.containsKey(key)) {
          consolidated[key] = {...d, '_docId': docId};
        } else {
          consolidated[key]!['quantity'] =
              (consolidated[key]!['quantity'] ?? 0) + (d['quantity'] ?? 0);
        }
      }

      for (final item in localItems) {
        processItem(item);
      }

      try {
        final snap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory')
            .orderBy('name_lower')
            .limit(200)
            .get(const GetOptions(source: Source.serverAndCache));

        for (final doc in snap.docs) {
          processItem({...doc.data(), '_docId': doc.id});
        }
      } catch (e) {
        debugPrint('InventoryUpdate: Firestore background fetch failed (offline mode): $e');
      }

      if (mounted) {
        setState(() {
          _searchResults = consolidated.values.toList()
            ..sort((a, b) => (a['name'] ?? '').toString()
                .toLowerCase()
                .compareTo((b['name'] ?? '').toString().toLowerCase()));
          _isSearching = false;
          _hasSearched = true;
        });
      }
    } catch (e) {
      debugPrint('InventoryUpdate: _loadAllMedicines Error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ── Search (filters the persistent list) ─────────────────────────────────
  void _searchMedicine(String query) async {
    if (_selectedMed != null) {
      setState(() {
        _selectedMed = null;
        _selectedDocId = null;
      });
    }

    if (query.trim().isEmpty) {
      _loadAllMedicines();
      return;
    }

    setState(() => _isSearching = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .where('name_lower',
              isGreaterThanOrEqualTo: query.toLowerCase())
          .where('name_lower',
              isLessThanOrEqualTo: '${query.toLowerCase()}\uf8ff')
          .limit(50)
          .get();

      final Map<String, Map<String, dynamic>> seen = {};
      for (final doc in snap.docs) {
        final d = doc.data();
        final key = '${d['name']}|${d['type']}|${d['dose']}';
        if (!seen.containsKey(key)) {
          seen[key] = {...d, '_docId': doc.id};
        } else {
          seen[key]!['quantity'] =
              (seen[key]!['quantity'] ?? 0) + (d['quantity'] ?? 0);
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = seen.values.toList();
          _isSearching = false;
          _hasSearched = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectMedForStock(Map<String, dynamic> med) {
    setState(() {
      _selectedMed = med;
      _selectedDocId = med['_docId']?.toString();
      _addQtyCtrl.text = '1';
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMed = null;
      _selectedDocId = null;
      _addQtyCtrl.text = '1';
    });
  }

  // ── Submit: Add Stock ─────────────────────────────────────────────────────
  Future<void> _submitAddStock() async {
    if (_selectedMed == null || _selectedDocId == null) {
      _snack('Select a medicine from the list first', err: true);
      return;
    }
    final qty = int.tryParse(_addQtyCtrl.text.trim()) ?? 0;
    if (qty < 1) {
      _snack('Enter a valid quantity (min 1)', err: true);
      return;
    }

    setState(() => _isSubmittingStock = true);
    try {
      final userInfo = await _getUserInfo();
      final medId = _selectedDocId!;

      // STEP 1: Update local Hive instantly — local UI reflects immediately
      await LocalStorageService.updateLocalStockQuantity(medId, qty.toDouble());

      // STEP 2: LAN broadcast — all LAN devices (doctor, server) see it instantly
      final updatedMed = LocalStorageService.getLocalInventoryItem(medId);
      if (updatedMed != null) {
        RealtimeManager().sendMessage({
          'event_type': RealtimeEvents.saveStockItem,
          'data': {
            ...updatedMed,
            '_quantityDelta':   qty,        // tells receiving device to increment
            'performedBy':      userInfo['uid'],
            'performedByName':  userInfo['username'],
          },
        });
      }

      // STEP 3: Try Firestore directly (online devices see it via StreamBuilder).
      //         If offline, catch and enqueue — SyncService will apply when back online.
      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory')
            .doc(medId)
            .update({'quantity': FieldValue.increment(qty)});

        // Log the action
        FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory_log')
            .add({
          'action': 'add_stock',
          'medicineName': _selectedMed!['name'],
          'medicineId': medId,
          'quantityAdded': qty,
          'performedBy': userInfo['uid'],
          'performedByName': userInfo['username'],
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Offline — queue for Firestore sync when connectivity is restored
        await LocalStorageService.enqueueSync({
          'type': 'add_inventory_stock',
          'branchId': widget.branchId,
          'medicineId': medId,
          'medicineName': _selectedMed!['name'],
          'quantity': qty,
          'performedBy': userInfo['uid'],
          'performedByName': userInfo['username'],
        });
      }

      _snack('+$qty added to ${_selectedMed!['name']} successfully!');
      _clearSelection();
      _loadAllMedicines();
    } catch (e) {
      _snack('Error: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSubmittingStock = false);
    }
  }



  // ── Submit: Register New Medicine ─────────────────────────────────────────
  Future<void> _submitRegister() async {
    if (!_regFormKey.currentState!.validate()) return;

    final name = _regNameCtrl.text.trim();
    final qty = int.tryParse(_regQtyCtrl.text.trim()) ?? 0;
    final price = _regPriceCtrl.text.trim();
    final exp = _regExpCtrl.text.trim();
    final dose = _hasDoseDropdown
        ? (_regSelectedDose ?? '')
        : (_usesFreeTextDose ? _regDoseCtrl.text.trim() : '');

    setState(() => _isSubmittingReg = true);
    try {
      final userInfo = await _getUserInfo();

      final medData = {
        'name': name,
        'name_lower': name.toLowerCase(),
        'formula': '',
        'formula_lower': '',
        'type': _regType,
        'dose': dose,
        'quantity': qty,
        'price': price,
        'expiryDate': exp,
        'branchId': widget.branchId,
        'createdAt': DateTime.now().toIso8601String(),
        'createdBy': userInfo['uid'] ?? '',
        'createdByName': userInfo['username'] ?? '',
      };

      final docId = RequestUtils.generateDocId(name, _regType, dose, exp);
      medData['id'] = docId;

      // STEP 1: Save to local Hive instantly — local UI reflects immediately
      LocalStorageService.saveLocalInventoryItem(medData);

      // STEP 2: LAN broadcast — all LAN devices (doctor, server) see it instantly
      RealtimeManager().sendMessage({
        'event_type': RealtimeEvents.saveStockItem,
        'data': medData,
      });

      // STEP 3: Try Firestore directly (online devices see it via StreamBuilder).
      //         If offline, catch and enqueue — SyncService will apply when back online.
      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory')
            .doc(docId)
            .set(medData);

        // Log the registration
        FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory_log')
            .add({
          'action': 'medicine_registered_directly',
          'medicineName': name,
          'medicineType': _regType,
          'dose': dose,
          'quantityAdded': qty,
          'price': price,
          'expiryDate': exp,
          'performedBy': userInfo['uid'],
          'performedByName': userInfo['username'],
          'timestamp': FieldValue.serverTimestamp(),
          'docId': docId,
        });
      } catch (_) {
        // Offline — queue for Firestore sync when connectivity is restored
        await LocalStorageService.enqueueSync({
          'type': 'register_medicine',
          'branchId': widget.branchId,
          'data': medData,
        });
      }

      _snack('$name registered successfully!');
      _resetRegForm();
      _loadAllMedicines();
    } catch (e) {
      _snack('Error: $e', err: true);
    } finally {
      if (mounted) setState(() => _isSubmittingReg = false);
    }
  }

  void _resetRegForm() {
    _regNameCtrl.clear();
    _regQtyCtrl.text = '1';
    _regExpCtrl.clear();
    _regPriceCtrl.clear();
    _regDoseCtrl.clear();
    setState(() {
      _regType = 'Tablet';
      _regSelectedDose = null;
    });
  }



  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: _teal,
        elevation: 4,
        shadowColor: _shadow,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Inventory Update',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(
                icon: Icon(Icons.add_box_rounded, size: 18),
                text: 'Add Stock'),
            Tab(
                icon: Icon(Icons.medication_liquid_rounded, size: 18),
                text: 'Register New'),
          ],
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — Add Stock
  // ══════════════════════════════════════════════════════════════════════════
  Widget _addStockTab() => Column(children: [
        // ── Search bar ──────────────────────────────────────────────────────
        Container(
          color: _white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            cursorColor: _teal,
            style: const TextStyle(color: _textDark, fontSize: 15),
            onChanged: _searchMedicine,
            decoration: InputDecoration(
              prefixIcon: _isSearching
                  ? Container(
                      margin: const EdgeInsets.all(12),
                      width: 18,
                      height: 18,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: _teal))
                  : const Icon(Icons.search_rounded,
                      color: _teal, size: 20),
              hintText: 'Search medicines...',
              hintStyle:
                  const TextStyle(color: _textLight, fontSize: 14),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: _textLight, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _selectedMed = null;
                          _selectedDocId = null;
                        });
                        _loadAllMedicines();
                      },
                    )
                  : null,
              filled: true,
              fillColor: _green50,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
            ),
          ),
        ),

        // ── Selected medicine + qty panel ────────────────────────────────────
        if (_selectedMed != null)
          Container(
            margin:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _teal.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: _shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: _green50,
                      borderRadius: BorderRadius.circular(9)),
                  child: Icon(_typeIcon(_selectedMed!['type'] ?? ''),
                      color: _teal, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Text(_selectedMed!['name'] ?? '',
                      style: const TextStyle(
                          color: _tealDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  Wrap(spacing: 6, children: [
                    _miniChip(_selectedMed!['type'] ?? '', _teal),
                    if ((_selectedMed!['dose'] ?? '')
                        .toString()
                        .isNotEmpty)
                      _miniChip(_selectedMed!['dose'], _textMid),
                    _miniChip(
                        'In stock: ${_selectedMed!['quantity'] ?? 0}',
                        _green600),
                  ]),
                ])),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: _textLight, size: 20),
                  onPressed: _clearSelection,
                  tooltip: 'Cancel',
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _qtyBtn(Icons.remove_rounded, () {
                  final v = int.tryParse(_addQtyCtrl.text) ?? 1;
                  if (v > 1) setState(() => _addQtyCtrl.text = '${v - 1}');
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _addQtyCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    cursorColor: _teal,
                    style: const TextStyle(
                        color: _teal,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _green50,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: _teal, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _qtyBtn(Icons.add_rounded, () {
                  final v = int.tryParse(_addQtyCtrl.text) ?? 0;
                  setState(() => _addQtyCtrl.text = '${v + 1}');
                }),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      _isSubmittingStock ? null : _submitAddStock,
                  icon: _isSubmittingStock
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_rounded,
                          color: Colors.white),
                  label: Text(
                      _isSubmittingStock ? 'Adding...' : 'Add Stock',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green600,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                ),
              ),
            ]),
          ),

        // ── Section header ───────────────────────────────────────────────────
        if (_hasSearched && _searchResults.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFF8FFFE),
            child: Row(children: [
              Text(
                _searchCtrl.text.isEmpty
                    ? 'All Medicines (${_searchResults.length})'
                    : 'Results (${_searchResults.length})',
                style: const TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              const Spacer(),
            ]),
          ),

        // ── Persistent medicine list ─────────────────────────────────────────
        Expanded(
          child: _isSearching && !_hasSearched
              ? const Center(
                  child: CircularProgressIndicator(color: _teal))
              : _searchResults.isEmpty && _hasSearched
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.search_off_rounded,
                            size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        const Text('No medicines found',
                            style: TextStyle(
                                color: _textLight, fontSize: 15)),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      itemCount: _searchResults.length,
                      itemBuilder: (ctx, i) {
                        final med = _searchResults[i];
                        final isSelected = _selectedMed != null &&
                            _selectedMed!['_docId'] == med['_docId'];
                        return _searchResultRow(med, isSelected);
                      },
                    ),
        ),
      ]);

  Widget _searchResultRow(Map<String, dynamic> med, bool isSelected) {
    final qty = _safeInt(med['quantity']);
    final type = med['type']?.toString() ?? '';
    final lowStock = qty < 50;
    final expSoon = _isExpiringSoon(med['expiryDate']?.toString());
    final isWarning = lowStock || expSoon;

    final rowBg = isSelected 
        ? _green50 
        : (isWarning ? _red.withValues(alpha: 0.12) : _white);
    final borderColor = isSelected
        ? _teal
        : (isWarning ? _red : _green100);

    return GestureDetector(
      onTap: () => _selectMedForStock(med),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            top:    BorderSide(color: borderColor, width: isSelected ? 2.0 : 1.0),
            right:  BorderSide(color: borderColor, width: isSelected ? 2.0 : 1.0),
            bottom: BorderSide(color: borderColor, width: isSelected ? 2.0 : 1.0),
            left:   BorderSide(color: isWarning ? _red : borderColor, width: isWarning ? 6.0 : (isSelected ? 2.0 : 1.0)),
          ),
          boxShadow: [
            BoxShadow(
              color: _shadow,
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: isSelected
                    ? _teal.withValues(alpha: 0.12)
                    : _green50,
                borderRadius: BorderRadius.circular(9)),
            child: Icon(_typeIcon(type), color: _teal, size: 15),
          ),
          const SizedBox(width: 12),

          // Name, type, dose
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(med['name'] ?? '',
                style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _miniChip(type, _teal),
              if ((med['dose'] ?? '').toString().isNotEmpty)
                _miniChip(med['dose'].toString(), _textMid),
            ]),
            if (isWarning)
              _statusLabel(lowStock: lowStock, expSoon: expSoon),
          ])),

          // Right side: stock badge + edit button
          Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (lowStock ? _red : _green600)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (lowStock ? _red : _green600)
                        .withValues(alpha: 0.3)),
              ),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                if (lowStock) ...[
                  const Icon(Icons.warning_rounded,
                      size: 11, color: _red),
                  const SizedBox(width: 3),
                ],
                Text('$qty',
                    style: TextStyle(
                        color: lowStock ? _red : _green600,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _showEditRequestSheet(med),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _purple.withValues(alpha: 0.3)),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                  Icon(Icons.edit_rounded,
                      size: 12, color: _purple),
                  SizedBox(width: 4),
                  Text('Edit',
                      style: TextStyle(
                          color: _purple,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Edit Request Sheet ─────────────────────────────────────────────────────
  void _showEditRequestSheet(Map<String, dynamic> med) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditRequestSheet(
        branchId: widget.branchId,
        medicine: med,
        allTypes: _allTypes,
        doseOptions: _doseOptions,
        onSubmit: (updatedFields) =>
            _submitEditRequest(med, updatedFields),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback fn) => InkWell(
        onTap: fn,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _teal.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: _teal, size: 22),
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — Register New Medicine
  // ══════════════════════════════════════════════════════════════════════════
  Widget _registerTab() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(children: [
          _card(
            child: Form(
              key: _regFormKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _sectionLabel('Register New Medicine'),
                const SizedBox(height: 18),

                // Name (Formula)
                TextFormField(
                  controller: _regNameCtrl,
                  style:
                      const TextStyle(color: _textDark, fontSize: 15),
                  cursorColor: _teal,
                  decoration: _inputDec('Formula',
                      icon: Icons.medication_rounded,
                      hint: 'e.g. Amoxicillin, Panadol Extra'),
                  validator: (v) => v?.trim().isEmpty ?? true
                      ? 'Formula is required'
                      : null,
                ),
                const SizedBox(height: 14),

                // Type + Price
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _regType,
                      dropdownColor: _white,
                      style: const TextStyle(
                          color: _textDark, fontSize: 14),
                      decoration: _inputDec('Type',
                          icon: FontAwesomeIcons.capsules),
                      items: _allTypes
                          .map((t) => DropdownMenuItem(
                              value: t,
                              child: Row(children: [
                                Icon(_typeIcon(t),
                                    size: 13, color: _teal),
                                const SizedBox(width: 8),
                                Text(t),
                              ])))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _regType = v;
                            _regSelectedDose = null;
                            _regDoseCtrl.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _regPriceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.]'))
                      ],
                      style: const TextStyle(
                          color: _textDark, fontSize: 15),
                      cursorColor: _teal,
                      decoration: _inputDec('Price',
                          prefix: const Padding(
                            padding:
                                EdgeInsets.only(left: 12, top: 14),
                            child: Text('PKR',
                                style: TextStyle(
                                    color: _teal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          )),
                      validator: (v) {
                        if (v?.trim().isEmpty ?? true) {
                          return 'Required';
                        }
                        final t = v!.trim().toLowerCase();
                        if (t == 'free') return null;
                        if (double.tryParse(t) == null) {
                          return 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Dose dropdown
                if (_hasDoseDropdown) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _regSelectedDose,
                    dropdownColor: _white,
                    style: const TextStyle(
                        color: _textDark, fontSize: 14),
                    decoration: _inputDec('Dose',
                        icon: Icons.science_rounded),
                    hint: const Text('Select dose',
                        style: TextStyle(color: _textLight)),
                    items: (_doseOptions[_regType] ?? [])
                        .map((d) => DropdownMenuItem(
                            value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _regSelectedDose = v),
                    validator: (v) => (_regType == 'Tablet')
                          ? null
                          : (v == null ? 'Select a dose' : null),
                  ),
                  const SizedBox(height: 14),
                ],

                // Dose free text
                if (_usesFreeTextDose) ...[
                  TextFormField(
                    controller: _regDoseCtrl,
                    style: const TextStyle(
                        color: _textDark, fontSize: 15),
                    cursorColor: _teal,
                    decoration: _inputDec(
                      _regType == 'Nebulization'
                          ? 'Dose per session'
                          : 'Dose / Variant (e.g. 500mg)',
                      icon: Icons.science_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Qty + Expiry
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _regQtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      style: const TextStyle(
                          color: _textDark, fontSize: 15),
                      cursorColor: _teal,
                      decoration: _inputDec(
                          _regType == 'Nebulization'
                              ? 'Sessions'
                              : 'Quantity',
                          icon: Icons.inventory_2_rounded),
                      validator: (v) =>
                          (int.tryParse(v ?? '') ?? 0) < 1
                              ? 'Min 1'
                              : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _regExpCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ExpiryDateFormatter(),
                      ],
                      style: const TextStyle(
                          color: _textDark, fontSize: 15),
                      cursorColor: _teal,
                      decoration: _inputDec(
                          'Expiry (dd-MM-yyyy)',
                          icon: Icons.calendar_today_rounded,
                          hint: 'dd-MM-yyyy'),
                      validator: ExpiryDateFormatter.validate,
                    ),
                  ),
                ]),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isSubmittingReg ? null : _submitRegister,
                    icon: _isSubmittingReg
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(
                            Icons.medication_liquid_rounded,
                            color: Colors.white),
                    label: Text(
                        _isSubmittingReg
                            ? 'Registering...'
                            : 'Register Medicine',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      padding: const EdgeInsets.symmetric(
                          vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );

  // ── Shared widgets ─────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _green100),
          boxShadow: [
            BoxShadow(
                color: _shadow,
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: child,
      );

  Widget _sectionLabel(String text) => Row(children: [
        Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
                color: _teal,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(text,
            style: const TextStyle(
                color: _teal,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      ]);

  Widget _miniChip(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  int _safeInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Edit Request Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════════════
class _EditRequestSheet extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic> medicine;
  final List<String> allTypes;
  final Map<String, List<String>> doseOptions;
  final Future<void> Function(Map<String, dynamic> updatedFields) onSubmit;

  const _EditRequestSheet({
    required this.branchId,
    required this.medicine,
    required this.allTypes,
    required this.doseOptions,
    required this.onSubmit,
  });

  @override
  State<_EditRequestSheet> createState() => _EditRequestSheetState();
}

class _EditRequestSheetState extends State<_EditRequestSheet> {
  static const _teal = Color(0xFF00695C);
  static const _tealDark = Color(0xFF004D40);
  static const _green50 = Color(0xFFE8F5E9);
  static const _red = Color(0xFFC62828);
  static const _purple = Color(0xFF6A1B9A);
  static const _border = Color(0xFFB2DFDB);
  static const _textDark = Color(0xFF1B2631);
  static const _textLight = Color(0xFF718096);

  late TextEditingController _nameCtrl;
  late TextEditingController _doseCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _expiryCtrl;
  late TextEditingController _reasonCtrl;
  late String _selectedType;
  String? _selectedDoseDropdown;

  bool _submitting = false;
  final _formKey = GlobalKey<FormState>();

  double _parsePrice(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String _fmtPrice(double p) =>
      p == p.floorToDouble()
          ? p.toInt().toString()
          : p.toStringAsFixed(2);

  bool _hasDd(String t) => widget.doseOptions.containsKey(t);
  bool _hasFree(String t) =>
      !widget.doseOptions.containsKey(t) &&
      t != 'Drip Set' &&
      t != 'Syringe';

  @override
  void initState() {
    super.initState();
    final med = widget.medicine;
    final price = _parsePrice(med['price']);
    _nameCtrl =
        TextEditingController(text: med['name']?.toString() ?? '');
    _doseCtrl =
        TextEditingController(text: med['dose']?.toString() ?? '');
    _qtyCtrl =
        TextEditingController(text: med['quantity']?.toString() ?? '0');
    _priceCtrl = TextEditingController(text: _fmtPrice(price));
    _expiryCtrl =
        TextEditingController(text: med['expiryDate']?.toString() ?? '');
    _reasonCtrl = TextEditingController();
    _selectedType = widget.allTypes.contains(med['type'])
        ? med['type'].toString()
        : widget.allTypes.first;

    final dose = (med['dose'] ?? '').toString().trim();
    if (_hasDd(_selectedType)) {
      final list = widget.doseOptions[_selectedType] ?? [];
      _selectedDoseDropdown = list.contains(dose) ? dose : null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _expiryCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final dose = _hasDd(_selectedType)
        ? (_selectedDoseDropdown ?? '')
        : _hasFree(_selectedType)
            ? _doseCtrl.text.trim()
            : '';

    final updatedFields = {
      'name': _nameCtrl.text.trim(),
      'type': _selectedType,
      'dose': dose,
      'quantity': int.tryParse(_qtyCtrl.text.trim()) ?? 0,
      'price': _priceCtrl.text.trim(),
      'expiryDate': _expiryCtrl.text.trim(),
      'reason': _reasonCtrl.text.trim(),
    };

    try {
      await widget.onSubmit(updatedFields);
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final hasDd = _hasDd(_selectedType);
    final hasFree = _hasFree(_selectedType);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
        ),

        // Title row
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_rounded,
                color: _purple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Request Edit',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _tealDark)),
              const Text(
                  'Changes will be sent for supervisor approval',
                  style:
                      TextStyle(fontSize: 11, color: _textLight)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: _textLight),
            onPressed: () => Navigator.pop(context),
          ),
        ]),

        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF3E5F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _purple.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded,
                size: 14, color: _purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Editing: ${widget.medicine['name'] ?? ''} '
                '(${widget.medicine['type'] ?? ''})',
                style: const TextStyle(
                    fontSize: 12,
                    color: _purple,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),

        Flexible(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(children: [
                // Formula (was Name)
                _field(
                  controller: _nameCtrl,
                  label: 'Formula',
                  icon: Icons.medication_rounded,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Required'
                          : null,
                ),
                const SizedBox(height: 12),

                // Type dropdown
                Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                  const Text('Type',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textLight)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14),
                    decoration: BoxDecoration(
                      color: _green50,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: _border),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedType,
                      isExpanded: true,
                      underline: const SizedBox(),
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                          color: _textDark, fontSize: 14),
                      icon: const Icon(
                          Icons.expand_more_rounded,
                          color: _teal),
                      items: widget.allTypes
                          .map((t) => DropdownMenuItem(
                              value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedType =
                            v ?? _selectedType;
                        _selectedDoseDropdown = null;
                        _doseCtrl.clear();
                      }),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // Dose dropdown
                if (hasDd) ...[
                  Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                    const Text('Dose',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _textLight)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14),
                      decoration: BoxDecoration(
                        color: _green50,
                        borderRadius:
                            BorderRadius.circular(10),
                        border:
                            Border.all(color: _border),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedDoseDropdown,
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: const Text('Select dose',
                            style: TextStyle(
                                color: _textLight)),
                        dropdownColor: Colors.white,
                        style: const TextStyle(
                            color: _textDark, fontSize: 14),
                        icon: const Icon(
                            Icons.expand_more_rounded,
                            color: _teal),
                        items: (widget.doseOptions[
                                        _selectedType] ??
                                    [])
                            .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(d)))
                            .toList(),
                        onChanged: (v) => setState(
                            () => _selectedDoseDropdown = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                ],

                // Dose free text
                if (hasFree) ...[
                  _field(
                    controller: _doseCtrl,
                    label: 'Dose / Variant',
                    icon: Icons.science_rounded,
                  ),
                  const SizedBox(height: 12),
                ],

                // Quantity Adjustment Field
                _field(
                  controller: _qtyCtrl,
                  label: 'Total Quantity',
                  icon: Icons.inventory_2_rounded,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (int.tryParse(v.trim()) == null) return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Price + Expiry
                Row(children: [
                  Expanded(
                      child: _field(
                    controller: _priceCtrl,
                    label: 'Price (PKR)',
                    icon: Icons.payments_rounded,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Required';
                      }
                      if (double.tryParse(v.trim()) == null) {
                        return 'Invalid';
                      }
                      return null;
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _field(
                    controller: _expiryCtrl,
                    label: 'Expiry',
                    icon: Icons.calendar_today_rounded,
                  )),
                ]),
                const SizedBox(height: 12),

                // Reason — mandatory
                _field(
                  controller: _reasonCtrl,
                  label: 'Reason for edit',
                  icon: Icons.comment_rounded,
                  maxLines: 2,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Reason is required'
                          : null,
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 18),
                    label: Text(
                        _submitting
                            ? 'Submitting…'
                            : 'Submit for Approval',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      disabledBackgroundColor:
                          _purple.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textLight)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          cursorColor: _teal,
          style:
              const TextStyle(color: _textDark, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon:
                Icon(icon, size: 17, color: _teal),
            filled: true,
            fillColor: _green50,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: _teal, width: 1.5)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _red)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _red, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 13),
          ),
        ),
      ]);
}

// ── Expiry Date Formatter ──────────────────────────────────────────────────────
class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String text =
        newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.length > 8) text = text.substring(0, 8);

    String formatted = '';
    if (text.length >= 2) {
      formatted += text.substring(0, 2);
      if (text.length > 2) formatted += '-';
    } else {
      formatted = text;
    }
    if (text.length >= 4) {
      formatted += text.substring(2, 4);
      if (text.length > 4) formatted += '-';
    } else if (text.length > 2) {
      formatted += text.substring(2);
    }
    if (text.length > 4) {
      formatted += text.substring(4);
    }

    return TextEditingValue(
      text: formatted,
      selection:
          TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String? validate(String? v) {
    if (v == null || v.isEmpty) return 'Enter expiry date';
    if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(v)) {
      return 'Use dd-MM-yyyy format';
    }
    try {
      final p = v.split('-');
      final day = int.parse(p[0]);
      final month = int.parse(p[1]);
      final year = int.parse(p[2]);
      if (month < 1 || month > 12) return 'Invalid month';
      if (day < 1 || day > 31) return 'Invalid day';
      final date = DateTime(year, month, day);
      final now = DateTime.now();
      if (date.isBefore(
          DateTime(now.year, now.month, now.day))) {
        return 'Past date not allowed';
      }
      if (year < 2025) return 'Year too early';
      if (year > 2100) return 'Year too far';
    } catch (_) {
      return 'Invalid date';
    }
    return null;
  }
}
