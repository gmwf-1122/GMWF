// lib/pages/dispensary/dispensar/inventory_update.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/services/master_proforma_service.dart';
import 'package:gmwf/utils/string_similarity_helper.dart';
import 'package:gmwf/pages/dispensary/dispensar/universal_proforma_sheet.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/pages/request.dart';
import 'package:gmwf/widgets/app_back_button.dart';
import 'package:gmwf/widgets/camp_selector_chip.dart';

class InventoryUpdatePage extends StatefulWidget {
  final String branchId;
  final bool isAdmin;
  final bool isDispenser;
  final bool isDoctor;
  final bool isEmbedded;
  final int showMode; // 0: both, 1: Add Stock, 2: Register New

  const InventoryUpdatePage({
    super.key,
    required this.branchId,
    this.isAdmin = false,
    this.isDispenser = false,
    this.isDoctor = false,
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
  String _selectedCampFilter = 'all';
  bool get _hasMultiCamps => CampSessionService.hasCampsForBranch(widget.branchId);

  // ── Register New Medicine state ───────────────────────────────────────────
  final _regFormKey = GlobalKey<FormState>();
  final _regNameCtrl = TextEditingController();
  final _regQtyCtrl = TextEditingController(text: '1');
  final _regExpCtrl = TextEditingController();
  final _regPriceCtrl = TextEditingController();
  final _regDoseCtrl = TextEditingController();
  final _regCodeCtrl = TextEditingController();
  final _regReasonCtrl = TextEditingController();
  String _regType = 'Tablet';
  String? _regSelectedDose;
  bool _isSubmittingReg = false;
  Map<String, dynamic>? _liveSpellingSuggestion;

  bool get _canRegisterMedicine {
    if (widget.isDispenser || widget.isDoctor) return false;
    String r = '';
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final uData = Hive.box('app_settings').get('user_data') ?? Hive.box('app_settings').get('currentUser');
        if (uData is Map) {
          r = (uData['role'] ?? uData['userRole'] ?? '').toString().trim().toLowerCase();
        }
      }
    } catch (_) {}

    if (r.contains('doctor') || r.contains('dispens') || r.contains('hybrid') || r.contains('reception')) {
      return false;
    }

    if (widget.isAdmin || r.contains('chairman') || r.contains('hqmanager') || r.contains('hq_manager') || r.contains('manager') || r.contains('admin') || r.contains('supervisor') || r.contains('president')) {
      return true;
    }
    return false;
  }

  void _onRegNameChanged() {
    final text = _regNameCtrl.text.trim();
    if (text.length < 3) {
      if (_liveSpellingSuggestion != null) setState(() => _liveSpellingSuggestion = null);
      return;
    }
    final candidates = <Map<String, dynamic>>[
      ...MasterProformaService.getAllItems(),
      ..._searchResults,
    ];
    final matches = StringSimilarityHelper.findSimilarMedicines(text, candidates, threshold: 0.60);
    if (matches.isNotEmpty) {
      final best = matches.first;
      final bestName = (best['name'] as String? ?? '').trim();
      if (bestName.toLowerCase() != text.toLowerCase()) {
        if (_liveSpellingSuggestion != best) {
          setState(() => _liveSpellingSuggestion = best);
        }
        return;
      }
    }
    if (_liveSpellingSuggestion != null) setState(() => _liveSpellingSuggestion = null);
  }

  final List<String> _allTypes = [
    'Tablet', 'Capsule', 'Syrup', 'Injection', 'Infusion',
    'Drip Set', 'Syringe', 'Cannula', 'Nebulization', 'Dressing Item', 'Consumables', 'Others',
  ];

  final Map<String, List<String>> _doseOptions = {
    'Tablet': [
      '2 mg',
      '5 mg',
      '8 mg',
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
    'Infusion': ['100 ml', '250 ml', '450 ml', '500 ml', '1000 ml'],
    'Drip': ['100 ml', '250 ml', '450 ml', '500 ml', '1000 ml'],
    'Syringe': ['1cc', '3cc', '5cc', '10cc', '20cc', '50cc'],
    'Cannula': ['18"', '20"', '21"', '22"', '23"', '24"', '25"', '26"', '27"', '30"'],
  };

  bool get _hasDoseDropdown => _doseOptions.containsKey(_regType);
  bool get _usesFreeTextDose =>
      !_doseOptions.containsKey(_regType) &&
      _regType != 'Drip Set' &&
      _regType != 'Syringe' &&
      _regType != 'Cannula';

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

    _regNameCtrl.addListener(_onRegNameChanged);
    _loadAllMedicines();
  }

  @override
  void dispose() {
    _regNameCtrl.removeListener(_onRegNameChanged);
    _tabCtrl.dispose();
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    _addQtyCtrl.dispose();
    _regNameCtrl.dispose();
    _regQtyCtrl.dispose();
    _regExpCtrl.dispose();
    _regPriceCtrl.dispose();
    _regDoseCtrl.dispose();
    _regCodeCtrl.dispose();
    _regReasonCtrl.dispose();
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

  // ── Barcode uniqueness check ────────────────────────────────────────────
  Future<bool> _isBarcodeTaken(String code, {String? excludeDocId}) async {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    // 1. Check Master Proforma catalog
    final profMatch = MasterProformaService.findExactBarcodeMatch(code);
    if (profMatch != null) return true;

    // 2. Check local stock items in active camp
    final localItems =
        LocalStorageService.getAllLocalStockItems(branchId: widget.branchId, filterByCamp: true);
    final localMatch = localItems.any((item) {
      final itemCode = (item['code']?.toString().trim().toLowerCase() ?? item['barcode']?.toString().trim().toLowerCase() ?? '');
      if (itemCode.isEmpty || itemCode != normalized) return false;
      final itemDocId = item['_docId'] ?? item['id'] ?? item['docId'];
      if (excludeDocId != null && itemDocId == excludeDocId) return false;
      return true;
    });
    if (localMatch) return true;

    // 3. Check Firestore
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .where('code', isEqualTo: code.trim())
          .limit(5)
          .get();
      for (final doc in snap.docs) {
        if (excludeDocId != null && doc.id == excludeDocId) continue;
        return true;
      }
    } catch (_) {}

    try {
      final snapBarcode = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .where('barcode', isEqualTo: code.trim())
          .limit(5)
          .get();
      for (final doc in snapBarcode.docs) {
        if (excludeDocId != null && doc.id == excludeDocId) continue;
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Returns existing medicine matching barcode if found
  Future<Map<String, dynamic>?> _findExistingByBarcode(String code) async {
    final cleanCode = code.trim().toLowerCase();
    if (cleanCode.isEmpty) return null;

    final profMatch = MasterProformaService.findExactBarcodeMatch(code);
    if (profMatch != null) return profMatch;

    final localItems = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId, filterByCamp: true);
    for (final item in localItems) {
      final itemCode = (item['code']?.toString().trim().toLowerCase() ?? item['barcode']?.toString().trim().toLowerCase() ?? '');
      if (itemCode.isNotEmpty && itemCode == cleanCode) {
        return item;
      }
    }
    return null;
  }

  /// Checks if a medicine with exact Name + Dose + Type already exists in catalog or local stock
  Future<Map<String, dynamic>?> _findExistingNameDoseTypeMatch(String name, String type, String dose, {String? excludeDocId}) async {
    final cleanN = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final cleanT = type.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final cleanD = dose.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (cleanN.isEmpty) return null;

    final profMatch = MasterProformaService.findExactNameDoseTypeMatch(name, type, dose);
    if (profMatch != null) return profMatch;

    final localItems = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId, filterByCamp: true);
    for (final item in localItems) {
      final itemDocId = item['_docId'] ?? item['id'] ?? item['docId'];
      if (excludeDocId != null && itemDocId == excludeDocId) continue;

      final itemN = (item['name'] as String? ?? item['formula'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final itemT = (item['type'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
      final itemD = (item['dose'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

      final matchesName = (itemN == cleanN);
      final matchesType = (itemT == cleanT);
      final matchesDose = (cleanD.isEmpty || itemD == cleanD || itemD == 'standard');

      if (matchesName && matchesType && matchesDose) {
        return item;
      }
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .where('name_lower', isEqualTo: cleanN)
          .limit(10)
          .get();
      for (final doc in snap.docs) {
        if (excludeDocId != null && doc.id == excludeDocId) continue;
        final data = doc.data();
        final itemT = (data['type'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
        final itemD = (data['dose'] as String? ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

        if (itemT == cleanT && (cleanD.isEmpty || itemD == cleanD || itemD == 'standard')) {
          return {...data, '_docId': doc.id};
        }
      }
    } catch (_) {}

    return null;
  }

  // ── Submit: Edit Request (needs approval or direct update for admin) ─────
  Future<void> _submitEditRequest(
      Map<String, dynamic> originalMed, Map<String, dynamic> updatedFields) async {
    try {
      final userInfo = await _getUserInfo();
      final db = FirebaseFirestore.instance;

      if (widget.isAdmin || widget.isDoctor) {
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

      final requestId = 'req_edit_${userInfo['uid'] ?? 'dispenser'}_${DateTime.now().millisecondsSinceEpoch}';
      await db
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .doc(requestId)
          .set({
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
        'Cannula' => FontAwesomeIcons.kitMedical,
        'Needle' => FontAwesomeIcons.syringe,
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
        fillColor: _isDark ? const Color(0xFF0F172A) : _green50,
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

  bool _isLowStock(int qty, String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('inj') || t.contains('drip') || t.contains('iv') || t.contains('infusion')) {
      return qty <= 10;
    }
    if (t.contains('syp') || t.contains('syrup') || t.contains('drop') || t.contains('susp') || t.contains('ointment') || t.contains('cream') || t.contains('inhaler') || t.contains('spray')) {
      return qty <= 15;
    }
    return qty <= 30;
  }

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
      final activeCamp = CampSessionService.getActiveCamp()?.toLowerCase().trim();
      final localItems = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId, filterByCamp: true);
      final Map<String, Map<String, dynamic>> consolidated = {};
      final Set<String> processedDocIds = {};

      void processItem(Map<String, dynamic> d) {
        final docId = d['_docId'] ?? d['id'] ?? d['docId'];
        if (docId != null) {
          if (processedDocIds.contains(docId)) return;
          processedDocIds.add(docId);
        }

        final filterCamp = _selectedCampFilter != 'all' ? _selectedCampFilter.toLowerCase() : activeCamp;
        if (filterCamp != null && filterCamp.isNotEmpty && filterCamp != 'all') {
          final itemCamp = (d['dispensaryId'] ?? d['campId'])?.toString().toLowerCase().trim();
          if (itemCamp != null && itemCamp.isNotEmpty && itemCamp != 'all' && itemCamp != filterCamp) {
            return;
          }
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
      final activeCamp = CampSessionService.getActiveCamp()?.toLowerCase().trim();
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
        final filterCamp = _selectedCampFilter != 'all' ? _selectedCampFilter.toLowerCase() : activeCamp;
        if (filterCamp != null && filterCamp.isNotEmpty && filterCamp != 'all') {
          final itemCamp = (d['dispensaryId'] ?? d['campId'])?.toString().toLowerCase().trim();
          if (itemCamp != null && itemCamp.isNotEmpty && itemCamp != 'all' && itemCamp != filterCamp) {
            continue;
          }
        }
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
          'dispensaryId': CampSessionService.getActiveCamp(),
          'performedBy': userInfo['uid'],
          'performedByName': userInfo['username'],
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Offline — queue for Firestore sync when connectivity is restored
        await LocalStorageService.enqueueSync({
          'type': 'add_inventory_stock',
          'branchId': widget.branchId,
          'dispensaryId': CampSessionService.getActiveCamp(),
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



  /// Checks for exact or fuzzy matches in  and stock catalog to avoid duplicate & spelling mistakes
  Future<bool> _verifySpellingAndDuplicates(String name, String type) async {
    // 1. Check exact match in Master Proforma
    final exact = MasterProformaService.findExactMatch(name, type);
    if (exact != null) {
      final String profName = exact['name'] ?? name;
      final String profCode = exact['code'] ?? '';
      final String profFormula = exact['formula'] ?? '';

      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(FontAwesomeIcons.circleExclamation, color: Color(0xFFE65100), size: 26),
              SizedBox(width: 10),
              Text('Medicine Exists in Catalog'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The medicine formula "${profFormula.isNotEmpty ? profFormula : profName}" ($type) is already registered in our Universal  Catalog!',
                style: const TextStyle(fontWeight: FontWeight.bold, color: _textDark),
              ),
              const SizedBox(height: 8),
              if (profCode.isNotEmpty)
                Text('Catalog Code: $profCode', style: const TextStyle(fontSize: 13, color: _textMid)),
              const SizedBox(height: 12),
              const Text(
                'Duplicate registration is blocked. Please select this medicine from the Universal  Sheet instead.',
                style: TextStyle(fontSize: 13, color: _red, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: _textMid)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(context).pop(false);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UniversalProformaSheetPage(
                      branchId: widget.branchId,
                      isDispenser: widget.isDispenser,
                      isAdmin: widget.isAdmin,
                    ),
                  ),
                );
              },
              icon: const Icon(FontAwesomeIcons.fileExcel, size: 14, color: Colors.white),
              label: const Text('Open  Sheet', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return false; // Stop custom registration
    }

    // 2. Collect all candidates for fuzzy spelling match
    final List<Map<String, dynamic>> candidates = [];
    final items = MasterProformaService.getAllItems();
    candidates.addAll(items);

    if (Hive.isBoxOpen(LocalStorageService.stockBox)) {
      final stockBox = Hive.box(LocalStorageService.stockBox);
      for (final key in stockBox.keys) {
        final val = stockBox.get(key);
        if (val is Map) {
          candidates.add(Map<String, dynamic>.from(val));
        }
      }
    }

    final matches = StringSimilarityHelper.findSimilarMedicines(name, candidates, threshold: 0.65);
    if (matches.isNotEmpty) {
      final bestMatch = matches.first;
      final String bestName = bestMatch['name'] ?? '';
      final double score = (bestMatch['_similarityScore'] as double? ?? 0.0);

      if (bestName.toLowerCase() != name.toLowerCase() && score < 1.0) {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(FontAwesomeIcons.lightbulb, color: Color(0xFF1976D2), size: 24),
                SizedBox(width: 10),
                Text('Did You Mean...?'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: _textDark),
                    children: [
                      const TextSpan(text: 'You entered '),
                      TextSpan(
                        text: '"$name"',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: _red),
                      ),
                      const TextSpan(text: ', which is very similar to our standard catalog medicine:'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(FontAwesomeIcons.pills, size: 16, color: _green600),
                          const SizedBox(width: 8),
                          Text(
                            bestName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _green600),
                          ),
                        ],
                      ),
                      if (bestMatch['formula'] != null && bestMatch['formula'].toString().isNotEmpty)
                        Text('Formula: ${bestMatch['formula']}', style: const TextStyle(fontSize: 12, color: _textMid)),
                      if (bestMatch['type'] != null)
                        Text('Type: ${bestMatch['type']} | Dose: ${bestMatch['dose'] ?? 'Standard'}', style: const TextStyle(fontSize: 12, color: _textMid)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Would you like to use the suggested standard medicine or register your new custom spelling?',
                  style: TextStyle(fontSize: 13, color: _textMid),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('custom'),
                child: Text('Keep Custom "$name"', style: const TextStyle(color: _textMid)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.of(context).pop('suggested'),
                child: Text('Use "$bestName"', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (choice == 'suggested') {
          _regNameCtrl.text = bestName;
          if (bestMatch['type'] != null && _allTypes.contains(bestMatch['type'])) {
            setState(() {
              _regType = bestMatch['type'];
            });
          }
          return true;
        } else if (choice == 'custom') {
          return true;
        } else {
          return false;
        }
      }
    }

    return true;
  }

  // ── Submit: Register New Medicine into Master Proforma ─────────────────────
  Future<void> _submitRegister() async {
    if (!_regFormKey.currentState!.validate()) return;

    final name = _regNameCtrl.text.trim();
    final reason = _regReasonCtrl.text.trim();
    if (reason.isEmpty) {
      _snack('A mandatory reason is required to register a medicine into Master Proforma!', err: true);
      return;
    }

    String code = _regCodeCtrl.text.trim();
    final dose = _hasDoseDropdown
        ? (_regSelectedDose ?? '')
        : (_usesFreeTextDose ? _regDoseCtrl.text.trim() : '');

    final allowed = await _verifySpellingAndDuplicates(name, _regType);
    if (!allowed) return;

    final finalName = _regNameCtrl.text.trim();
    final cleanFormula = MasterProformaService.cleanBrandToFormula(finalName);

    if (code.isEmpty) {
      final initials = cleanFormula.split(RegExp(r'\s+')).take(3).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
      code = 'MED-$initials-${DateTime.now().millisecondsSinceEpoch % 10000}';
    }

    setState(() => _isSubmittingReg = true);
    try {
      final userInfo = await _getUserInfo();

      final proformaItem = {
        'code': code,
        'name': cleanFormula,
        'formula': cleanFormula,
        'type': _regType,
        'dose': dose,
        'defaultPrice': 0.0,
        'expiryDate': '2099-12-31',
        'isProformaMaster': true,
        'createdAt': DateTime.now().toIso8601String(),
        'createdBy': userInfo['uid'] ?? '',
        'createdByName': userInfo['username'] ?? '',
      };

      final auditLog = {
        'id': 'audit_${DateTime.now().millisecondsSinceEpoch}',
        'action': 'register_proforma_medicine',
        'medicineCode': code,
        'medicineName': cleanFormula,
        'medicineType': _regType,
        'medicineDose': dose,
        'reason': reason,
        'performedBy': userInfo['uid'],
        'performedByName': userInfo['username'],
        'performedByRole': userInfo['role'] ?? 'HQ Manager / Chairman',
        'timestamp': DateTime.now().toIso8601String(),
        'branchId': widget.branchId,
      };

      await MasterProformaService.saveProformaItem(proformaItem, auditLog: auditLog);

      RealtimeManager().sendMessage({
        'event_type': RealtimeEvents.saveStockItem,
        'data': proformaItem,
        'logData': auditLog,
      });

      _snack('"$cleanFormula" registered permanently into Master Proforma Catalog with Audit Trail!');
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
    _regCodeCtrl.clear();
    _regReasonCtrl.clear();
    setState(() {
      _regType = 'Tablet';
      _regSelectedDose = null;
      _liveSpellingSuggestion = null;
    });
  }



  bool get _isDark {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        return Hive.box('app_settings').get('is_dark_mode', defaultValue: false) == true;
      }
    } catch (_) {}
    return false;
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: _isDark ? const Color(0xFF0F172A) : _teal,
        elevation: 4,
        shadowColor: _shadow,
        automaticallyImplyLeading: false,
        leading: (!widget.isEmbedded && Navigator.canPop(context))
            ? AppBackButton(color: Colors.white)
            : null,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Inventory Update',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        actions: [
          CampSelectorChip(
            branchId: widget.branchId,
            onCampChanged: (newCamp) {
              setState(() {
                _loadAllMedicines();
              });
            },
          ),
          const SizedBox(width: 8),
        ],
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
          color: _isDark ? const Color(0xFF1E293B) : _white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            cursorColor: _teal,
            style: TextStyle(color: _isDark ? Colors.white : _textDark, fontSize: 15),
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
              fillColor: _isDark ? const Color(0xFF1E293B) : _green50,
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
              color: _isDark ? const Color(0xFF1E293B) : _white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _isDark ? const Color(0xFF0F766E) : _teal.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: _isDark ? Colors.black26 : _shadow,
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
                      color: _isDark ? const Color(0xFF0F766E).withValues(alpha: 0.25) : _green50,
                      borderRadius: BorderRadius.circular(9)),
                  child: Icon(_typeIcon(_selectedMed!['type'] ?? ''),
                      color: _isDark ? const Color(0xFF2DD4BF) : _teal, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Text(_selectedMed!['name'] ?? '',
                      style: TextStyle(
                          color: _isDark ? Colors.white : _tealDark,
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
                    cursorColor: _isDark ? const Color(0xFF2DD4BF) : _teal,
                    style: TextStyle(
                        color: _isDark ? const Color(0xFF2DD4BF) : _teal,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _isDark ? const Color(0xFF0F172A) : _green50,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: _isDark ? const Color(0xFF334155) : _border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: _isDark ? const Color(0xFF334155) : _border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: _isDark ? const Color(0xFF2DD4BF) : _teal, width: 1.5)),
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
            color: _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FFFE),
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
              if (_hasMultiCamps) ...[
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCampFilter,
                      isDense: true,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textDark),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('🏥 All Camps')),
                        DropdownMenuItem(value: 'haji', child: Text('📍 Haji Camp')),
                        DropdownMenuItem(value: 'saddar', child: Text('📍 Saddar')),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedCampFilter = v ?? 'all');
                        _loadAllMedicines();
                      },
                    ),
                  ),
                ),
              ],
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
    final isDark = _isDark;
    final qty = _safeInt(med['quantity']);
    final type = med['type']?.toString() ?? '';
    final lowStock = _isLowStock(qty, type);
    final expSoon = _isExpiringSoon(med['expiryDate']?.toString());
    final isWarning = lowStock || expSoon;

    final rowBg = isDark 
        ? (isSelected ? const Color(0xFF1E3A3A) : (isWarning ? const Color(0xFF2D1214) : const Color(0xFF1E293B)))
        : (isSelected ? _green50 : (isWarning ? _red.withValues(alpha: 0.12) : _white));
    final borderColor = isDark
        ? (isSelected ? const Color(0xFF0F766E) : (isWarning ? const Color(0xFFFF6B6B) : const Color(0xFF334155)))
        : (isSelected ? _teal : (isWarning ? _red : _green100));

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
            left:   BorderSide(color: isWarning ? (isDark ? const Color(0xFFFF6B6B) : _red) : borderColor, width: isWarning ? 6.0 : (isSelected ? 2.0 : 1.0)),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : _shadow,
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
                    ? (isDark ? const Color(0xFF0F766E).withValues(alpha: 0.3) : _teal.withValues(alpha: 0.12))
                    : (isDark ? const Color(0xFF334155) : _green50),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(_typeIcon(type), color: isDark ? const Color(0xFF38BDF8) : _teal, size: 15),
          ),
          const SizedBox(width: 12),

          // Name, type, dose
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(med['name'] ?? '',
                style: TextStyle(
                    color: isDark ? (isWarning ? const Color(0xFFFF6B6B) : Colors.white) : (isWarning ? _red : _textDark),
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _miniChip(type, isDark ? const Color(0xFF38BDF8) : _teal),
              if ((med['dose'] ?? '').toString().isNotEmpty)
                _miniChip(med['dose'].toString(), isDark ? const Color(0xFF94A3B8) : _textMid),
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
                color: (lowStock ? (isDark ? const Color(0xFFFF6B6B) : _red) : (isDark ? const Color(0xFF22C55E) : _green600))
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (lowStock ? (isDark ? const Color(0xFFFF6B6B) : _red) : (isDark ? const Color(0xFF22C55E) : _green600))
                        .withValues(alpha: 0.3)),
              ),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                if (lowStock) ...[
                  Icon(Icons.warning_rounded,
                      size: 11, color: isDark ? const Color(0xFFFF6B6B) : _red),
                  const SizedBox(width: 3),
                ],
                Text('$qty',
                    style: TextStyle(
                        color: lowStock ? (isDark ? const Color(0xFFFF6B6B) : _red) : (isDark ? const Color(0xFF22C55E) : _green600),
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
        isAdmin: widget.isAdmin,
        isDoctor: widget.isDoctor,
        isDispenser: widget.isDispenser,
        isBarcodeTaken: _isBarcodeTaken,
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
            color: _isDark ? const Color(0xFF1E293B) : _teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _isDark ? const Color(0xFF334155) : _teal.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: _isDark ? const Color(0xFF38BDF8) : _teal, size: 22),
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — Register New Medicine
  // ══════════════════════════════════════════════════════════════════════════
  Widget _registerTab() {
    if (!_canRegisterMedicine) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Access Restricted',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _tealDark),
              ),
              const SizedBox(height: 8),
              const Text(
                'Registering permanent medicines into the Master Proforma is restricted to Chairman, HQ Managers, and Admins.\nDispensary staff and doctors can restock and add branch inventory from the Universal Proforma Sheet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _textMid),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(children: [
          _card(
            child: Form(
              key: _regFormKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _sectionLabel('Register Medicine to Master Proforma'),
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
                if (_liveSpellingSuggestion != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF90CAF9)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF1976D2)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: const TextStyle(fontSize: 12, color: _textDark),
                              children: [
                                const TextSpan(text: 'Did you mean '),
                                TextSpan(
                                  text: '${_liveSpellingSuggestion!['name']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: _blue),
                                ),
                                if (_liveSpellingSuggestion!['formula'] != null)
                                  TextSpan(text: ' (${_liveSpellingSuggestion!['formula']})'),
                                const TextSpan(text: '?'),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _regNameCtrl.text = _liveSpellingSuggestion!['name'] ?? '';
                              _liveSpellingSuggestion = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Apply Fix', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Barcode — required and must be unique across the branch
                TextFormField(
                  controller: _regCodeCtrl,
                  style:
                      const TextStyle(color: _textDark, fontSize: 15),
                  cursorColor: _teal,
                  decoration: _inputDec('Barcode',
                      icon: Icons.qr_code_rounded,
                      hint: 'e.g. 8964000123456'),
                  validator: (v) => v?.trim().isEmpty ?? true
                      ? 'Barcode is required'
                      : null,
                ),
                const SizedBox(height: 14),

                // Type Dropdown
                DropdownButtonFormField<String>(
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

                // Reason for Registration (MANDATORY AUDIT)
                TextFormField(
                  controller: _regReasonCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: _textDark, fontSize: 14),
                  cursorColor: _teal,
                  decoration: _inputDec(
                    'Reason for Registration (Mandatory Audit) *',
                    icon: Icons.history_edu_rounded,
                    hint: 'e.g. Approved generic formula per Chairman / HQ decision',
                  ),
                  validator: (v) => v?.trim().isEmpty ?? true
                      ? 'Reason is required for Master Proforma audit logging'
                      : null,
                ),
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
                            Icons.save_rounded,
                            color: Colors.white),
                    label: Text(
                        _isSubmittingReg
                            ? 'Registering...'
                            : 'Save Permanently to Master Proforma',
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
  }

  // ── Shared widgets ─────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isDark ? const Color(0xFF1E293B) : _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _isDark ? const Color(0xFF334155) : _green100),
          boxShadow: [
            BoxShadow(
                color: _isDark ? Colors.black26 : _shadow,
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
  final bool isAdmin;
  final bool isDoctor;
  final bool isDispenser;
  final Future<bool> Function(String code, {String? excludeDocId}) isBarcodeTaken;
  final Future<void> Function(Map<String, dynamic> updatedFields) onSubmit;

  const _EditRequestSheet({
    required this.branchId,
    required this.medicine,
    required this.allTypes,
    required this.doseOptions,
    this.isAdmin = false,
    this.isDoctor = false,
    this.isDispenser = false,
    required this.isBarcodeTaken,
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
  late TextEditingController _codeCtrl;
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
    _codeCtrl =
        TextEditingController(text: med['code']?.toString() ?? '');
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
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    // Barcode must remain unique across the branch's inventory. Only check
    // when it actually changed, excluding this medicine's own record.
    final newCode = _codeCtrl.text.trim();
    final originalCode = (widget.medicine['code'] ?? '').toString().trim();
    if (newCode.toLowerCase() != originalCode.toLowerCase()) {
      final excludeDocId =
          widget.medicine['_docId'] ?? widget.medicine['id'];
      final taken = await widget.isBarcodeTaken(newCode,
          excludeDocId: excludeDocId?.toString());
      if (taken) {
        if (mounted) {
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'This barcode is already registered to another medicine'),
              backgroundColor: _red,
            ),
          );
        }
        return;
      }
    }

    final dose = _hasDd(_selectedType)
        ? (_selectedDoseDropdown ?? '')
        : _hasFree(_selectedType)
            ? _doseCtrl.text.trim()
            : '';

    final updatedFields = {
      'name': _nameCtrl.text.trim(),
      'type': _selectedType,
      'dose': dose,
      'code': newCode,
      'barcode': newCode,
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

                // Barcode — required and must be unique across the branch
                Builder(builder: (context) {
                  return _field(
                    controller: _codeCtrl,
                    label: 'Barcode',
                    icon: Icons.qr_code_rounded,
                    enabled: true,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Barcode is required'
                        : null,
                  );
                }),
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

                // Expiry
                _field(
                  controller: _expiryCtrl,
                  label: 'Expiry',
                  icon: Icons.calendar_today_rounded,
                ),
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
    bool enabled = true,
    String? helperText,
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
          enabled: enabled,
          readOnly: !enabled,
          cursorColor: _teal,
          style: TextStyle(color: enabled ? _textDark : Colors.grey.shade700, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 17, color: enabled ? _teal : Colors.grey),
            suffixIcon: !enabled ? const Icon(Icons.lock_rounded, size: 16, color: Colors.grey) : null,
            helperText: helperText,
            helperStyle: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold),
            filled: true,
            fillColor: enabled ? _green50 : Colors.grey.shade100,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal, width: 1.5)),
            disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _red)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _red, width: 1.5)),
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