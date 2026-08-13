// lib/pages/dispensary/dispensar/universal_proforma_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/master_proforma_service.dart';
import 'package:gmwf/utils/string_similarity_helper.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/pages/request.dart';
import 'package:gmwf/widgets/app_back_button.dart';

class UniversalProformaSheetPage extends StatefulWidget {
  final String branchId;
  final bool isDispenser;
  final bool isAdmin;
  final bool isEmbedded;

  const UniversalProformaSheetPage({
    super.key,
    required this.branchId,
    this.isDispenser = true,
    this.isAdmin = false,
    this.isEmbedded = false,
  });

  @override
  State<UniversalProformaSheetPage> createState() => _UniversalProformaSheetPageState();
}

class _UniversalProformaSheetPageState extends State<UniversalProformaSheetPage> {
  // ── Palette ───────────────────────────────────────────────────────────────
  static const _teal = Color(0xFF00695C);
  static const _tealDark = Color(0xFF004D40);
  static const _bg = Color(0xFFF4F7F6);
  static const _white = Colors.white;
  static const _headerBg = Color(0xFFE0F2F1);
  static const _gridBorder = Color(0xFFB2DFDB);
  static const _textDark = Color(0xFF1B2631);
  static const _textMid = Color(0xFF4A5568);
  static const _textLight = Color(0xFF718096);
  static const _green600 = Color(0xFF2E7D32);
  static const _red = Color(0xFFD32F2F);

  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedTypeFilter = 'All';
  List<Map<String, dynamic>> _proformaMasterList = [];
  List<Map<String, dynamic>> _filteredList = [];

  // Item state maps (keyed by item code/id)
  final Map<String, bool> _selectedItems = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, DateTime> _expiryDates = {};

  bool _isSavingBatch = false;
  bool _selectAllChecked = false;

  final List<String> _typeCategories = [
    'All', 'Tablet', 'Capsule', 'Syrup', 'Injection', 'Drip', 'Drip Set', 'Syringe', 'Cannula', 'Nebulization', 'Dressing Item', 'Consumables', 'Others'
  ];

  @override
  void initState() {
    super.initState();
    _loadProformaData();
    _searchCtrl.addListener(_filterData);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_filterData);
    _searchCtrl.dispose();
    for (final ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _priceControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _loadProformaData() {
    final list = MasterProformaService.getAllProformaItems();
    final defaultExp = DateTime.now().add(const Duration(days: 365));

    setState(() {
      _proformaMasterList = list;
      for (final item in list) {
        final code = item['code'] as String? ?? 'MED-GEN';
        _selectedItems[code] = false;

        if (!_qtyControllers.containsKey(code)) {
          _qtyControllers[code] = TextEditingController(text: '0');
        }

        final defaultPrice = (item['defaultPrice'] as num?)?.toDouble() ?? 0.0;
        if (!_priceControllers.containsKey(code)) {
          _priceControllers[code] = TextEditingController(
            text: defaultPrice > 0 ? defaultPrice.toStringAsFixed(0) : '0',
          );
        }

        if (!_expiryDates.containsKey(code)) {
          _expiryDates[code] = defaultExp;
        }
      }
      _filterData();
    });
  }

  void _filterData() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      var directMatches = _proformaMasterList.where((item) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        final formula = (item['formula'] as String? ?? '').toLowerCase();
        final code = (item['code'] as String? ?? '').toLowerCase();
        final type = item['type'] as String? ?? 'Tablet';

        final matchesQuery = query.isEmpty ||
            name.contains(query) ||
            formula.contains(query) ||
            code.contains(query);

        final matchesType = _selectedTypeFilter == 'All' || type == _selectedTypeFilter;

        return matchesQuery && matchesType;
      }).toList();

      if (directMatches.isEmpty && query.length >= 3) {
        directMatches = _proformaMasterList.where((item) {
          final name = (item['name'] as String? ?? '').toLowerCase();
          final formula = (item['formula'] as String? ?? '').toLowerCase();
          final type = item['type'] as String? ?? 'Tablet';
          final matchesType = _selectedTypeFilter == 'All' || type == _selectedTypeFilter;
          if (!matchesType) return false;

          final simName = StringSimilarityHelper.calculateSimilarity(query, name);
          final simForm = StringSimilarityHelper.calculateSimilarity(query, formula);
          return simName >= 0.55 || simForm >= 0.55;
        }).toList();
      }

      _filteredList = directMatches;

      // Check if all filtered are selected
      if (_filteredList.isEmpty) {
        _selectAllChecked = false;
      } else {
        _selectAllChecked = _filteredList.every((item) {
          final code = item['code'] as String? ?? '';
          return _selectedItems[code] == true;
        });
      }
    });
  }

  void _toggleSelectAll(bool? val) {
    final flag = val ?? false;
    setState(() {
      _selectAllChecked = flag;
      for (final item in _filteredList) {
        final code = item['code'] as String? ?? '';
        _selectedItems[code] = flag;
      }
    });
  }

  void _selectItemsWithQty() {
    setState(() {
      int count = 0;
      for (final item in _proformaMasterList) {
        final code = item['code'] as String? ?? '';
        final qtyText = _qtyControllers[code]?.text.trim() ?? '0';
        final qty = int.tryParse(qtyText) ?? 0;
        if (qty > 0) {
          _selectedItems[code] = true;
          count++;
        }
      }

      _filterData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected $count items with Quantity > 0'),
          backgroundColor: _teal,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  int get _selectedCount => _selectedItems.values.where((v) => v).length;

  Future<void> _pickExpiryDate(String code) async {
    final current = _expiryDates[code] ?? DateTime.now().add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _teal,
              onPrimary: Colors.white,
              onSurface: _textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _expiryDates[code] = picked;
      });
    }
  }

  Future<void> _saveBatchToInventory() async {
    final itemsToSave = <Map<String, dynamic>>[];

    for (final item in _proformaMasterList) {
      final code = item['code'] as String? ?? '';
      if (_selectedItems[code] == true) {
        final qtyText = _qtyControllers[code]?.text.trim() ?? '0';
        final qty = int.tryParse(qtyText) ?? 0;
        final priceText = _priceControllers[code]?.text.trim() ?? '0';
        final price = double.tryParse(priceText) ?? 0.0;
        final expDate = _expiryDates[code] ?? DateTime.now().add(const Duration(days: 365));

        if (qty < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please enter a valid non-negative quantity for "${item['name']}"'),
              backgroundColor: _red,
            ),
          );
          return;
        }

        itemsToSave.add({
          'proforma': item,
          'qty': qty,
          'price': price,
          'expiryDate': DateFormat('yyyy-MM-dd').format(expDate),
        });
      }
    }

    if (itemsToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No items selected! Check at least one medicine to add to inventory.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    setState(() => _isSavingBatch = true);

    try {
      final String activeBranch = widget.branchId.isEmpty ? 'default' : widget.branchId;
      final stockBox = Hive.box(LocalStorageService.stockBox);
      final user = FirebaseAuth.instance.currentUser;
      final addedBy = user?.email ?? user?.displayName ?? 'Dispenser';
      int totalAdded = 0;

      for (final entry in itemsToSave) {
        final prof = entry['proforma'] as Map<String, dynamic>;
        final String name = prof['name'] as String? ?? 'Unknown';
        final String formula = prof['formula'] as String? ?? '';
        final String type = prof['type'] as String? ?? 'Tablet';
        final String dose = prof['dose'] as String? ?? '';
        final String code = prof['code'] as String? ?? '';
        final int qty = entry['qty'] as int;
        final double price = entry['price'] as double;
        final String exp = entry['expiryDate'] as String;

        final String activeCamp = CampSessionService.getActiveCamp() ?? '';

        // Search stockBox for an existing item in this active camp matching Barcode or Name+Dose+Type
        final cleanCode = code.trim().toLowerCase();
        final cleanN = (formula.isNotEmpty ? formula : name).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final cleanT = type.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
        final cleanD = dose.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

        Map<String, dynamic>? existingStockData;

        for (final k in stockBox.keys) {
          final val = stockBox.get(k);
          if (val is Map) {
            final map = Map<String, dynamic>.from(val);

            // Camp filter check
            final itemCamp = (map['dispensaryId'] ?? map['campId'])?.toString().trim().toLowerCase() ?? '';
            if (activeCamp.isNotEmpty && itemCamp.isNotEmpty && itemCamp != 'all' && itemCamp != activeCamp.toLowerCase()) {
              continue;
            }

            final itemCode = (map['code'] ?? map['barcode'] ?? '').toString().trim().toLowerCase();
            final itemN = (map['name'] ?? map['formula'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
            final itemT = (map['type'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
            final itemD = (map['dose'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

            bool isMatch = false;
            if (cleanCode.isNotEmpty && itemCode.isNotEmpty && itemCode == cleanCode) {
              isMatch = true;
            } else if (itemN == cleanN && itemT == cleanT && (cleanD.isEmpty || itemD == cleanD || itemD == 'standard')) {
              isMatch = true;
            }

            if (isMatch) {
              existingStockData = map;
              break;
            }
          }
        }

        String docId;
        Map<String, dynamic> stockData;

        if (existingStockData != null) {
          docId = existingStockData['_docId'] ?? existingStockData['docId'] ?? existingStockData['id'] ?? RequestUtils.generateDocId(name, type, dose, exp, campId: activeCamp);
          stockData = Map<String, dynamic>.from(existingStockData);
          final currentQty = (stockData['quantity'] as num?)?.toInt() ?? 0;
          stockData['quantity'] = currentQty + qty;
          stockData['price'] = price > 0 ? price : (stockData['price'] ?? 0.0);
          stockData['dispensaryId'] = activeCamp.isNotEmpty ? activeCamp : (stockData['dispensaryId'] ?? 'all');
          stockData['campId'] = activeCamp.isNotEmpty ? activeCamp : (stockData['campId'] ?? 'all');
          stockData['lastUpdated'] = DateTime.now().toIso8601String();
        } else {
          docId = RequestUtils.generateDocId(name, type, dose, exp, campId: activeCamp);
          stockData = {
            'docId': docId,
            'id': docId,
            'medicineId': docId,
            'code': code,
            'barcode': code,
            'name': name,
            'formula': formula,
            'type': type,
            'dose': dose,
            'quantity': qty,
            'price': price,
            'expiryDate': exp,
            'branchId': activeBranch,
            'dispensaryId': activeCamp.isNotEmpty ? activeCamp : 'all',
            'campId': activeCamp.isNotEmpty ? activeCamp : 'all',
            'isProforma': true,
            'addedBy': addedBy,
            'createdAt': DateTime.now().toIso8601String(),
            'lastUpdated': DateTime.now().toIso8601String(),
          };
        }

        LocalStorageService.saveLocalInventoryItem(stockData);
        totalAdded += qty;

        // LAN Broadcast
        RealtimeManager().sendMessage({
          'event_type': RealtimeEvents.saveStockItem,
          'data': stockData,
        });

        // Try direct Firestore update or enqueue offline sync
        try {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(activeBranch)
              .collection('inventory')
              .doc(docId)
              .set(stockData, SetOptions(merge: true));
        } catch (_) {
          await LocalStorageService.enqueueSync({
            'type': 'add_stock',
            'branchId': activeBranch,
            'data': stockData,
          });
        }
      }

      if (!mounted) return;

      setState(() {
        _isSavingBatch = false;
        // Reset selections & quantities
        for (final item in _proformaMasterList) {
          final code = item['code'] as String? ?? '';
          _selectedItems[code] = false;
          _qtyControllers[code]?.text = '0';
        }
        _selectAllChecked = false;
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(FontAwesomeIcons.circleCheck, color: _green600, size: 28),
              SizedBox(width: 12),
              Text('Inventory Added!'),
            ],
          ),
          content: Text(
            'Successfully added ${itemsToSave.length} proforma medicine batches ($totalAdded total items) to Branch Stock!',
            style: const TextStyle(fontSize: 14, color: _textDark),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(true); // Return success to caller
              },
              child: const Text('Back to Inventory', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingBatch = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save batch: $e'), backgroundColor: _red),
      );
    }
  }

  bool get _isDark {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        return Hive.box('app_settings').get('is_dark_mode', defaultValue: false) == true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : _bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F172A) : _tealDark,
        elevation: 2,
        automaticallyImplyLeading: false,
        leading: (!widget.isEmbedded && Navigator.canPop(context))
            ? AppBackButton(color: Colors.white)
            : null,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            const Icon(FontAwesomeIcons.fileExcel, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Universal Proforma Sheet',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Text(
                    'Master Generic Formula Catalog (Universal)',
                    style: TextStyle(color: Color(0xFF80CBC4), fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Auto-Select Items with Qty > 0',
            icon: const Icon(FontAwesomeIcons.listCheck, color: Colors.white, size: 18),
            onPressed: _selectItemsWithQty,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Top Search & Filter Bar ───────────────────────────────────────
          _buildFilterHeader(),

          // ── Excel Grid Sheet Data ──────────────────────────────────────────
          Expanded(
            child: _filteredList.isEmpty
                ? _buildEmptyState()
                : _buildExcelGridSheet(),
          ),

          // ── Bottom Action Sticky Toolbar ──────────────────────────────────
          _buildBottomToolbar(),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    final isDark = _isDark;
    return Container(
      color: isDark ? const Color(0xFF1E293B) : _white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: isDark ? Colors.white : _textDark),
                  decoration: InputDecoration(
                    hintText: 'Search Proforma by Name, Formula, Barcode...',
                    hintStyle: TextStyle(color: isDark ? const Color(0xFF94A3B8) : _textLight),
                    prefixIcon: Icon(Icons.search, color: isDark ? const Color(0xFF38BDF8) : _teal),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: 18, color: isDark ? const Color(0xFF94A3B8) : Colors.grey),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : _bg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : _gridBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? const Color(0xFF38BDF8) : _teal, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFF38BDF8) : _teal,
                  side: BorderSide(color: isDark ? const Color(0xFF38BDF8) : _teal),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _selectItemsWithQty,
                icon: const Icon(FontAwesomeIcons.checkDouble, size: 14),
                label: const Text('Auto Select Qty > 0'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Medicine Count Badges ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F766E).withValues(alpha: 0.2) : _teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? const Color(0xFF0F766E) : _teal.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Total Master Catalog: ${_proformaMasterList.length} Medicines',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF38BDF8) : _tealDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E3A3A) : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isDark ? const Color(0xFF0284C7) : Colors.blue.shade200),
                ),
                child: Text(
                  'Showing: ${_filteredList.length} Matching',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF7DD3FC) : Colors.blue.shade900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _selectedCount > 0
                      ? (isDark ? const Color(0xFF065F46) : Colors.green.shade50)
                      : (isDark ? const Color(0xFF334155) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _selectedCount > 0
                        ? (isDark ? const Color(0xFF10B981) : Colors.green.shade300)
                        : (isDark ? const Color(0xFF475569) : Colors.grey.shade300),
                  ),
                ),
                child: Text(
                  'Selected: $_selectedCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _selectedCount > 0
                        ? (isDark ? const Color(0xFF34D399) : Colors.green.shade800)
                        : (isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Category filter pills
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _typeCategories.length,
              separatorBuilder: (_, index) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final cat = _typeCategories[idx];
                final isSelected = _selectedTypeFilter == cat;
                return ChoiceChip(
                  label: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : (isDark ? const Color(0xFFCBD5E1) : _textMid),
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: isDark ? const Color(0xFF0F766E) : _teal,
                  backgroundColor: isDark ? const Color(0xFF334155) : _bg,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedTypeFilter = cat;
                        _filterData();
                      });
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExcelGridSheet() {
    final isDark = _isDark;
    const double tableWidth = 1240;

    final headerBg = isDark ? const Color(0xFF0F766E) : _headerBg;
    final headerTextColor = isDark ? Colors.white : _tealDark;
    final rowBgNormal = isDark ? const Color(0xFF1E293B) : Colors.white;
    final rowBgAlt = isDark ? const Color(0xFF0F172A) : const Color(0xFFFAFAFA);
    final rowBgSelected = isDark ? const Color(0xFF1E3A3A) : _teal.withValues(alpha: 0.08);
    final borderColor = isDark ? const Color(0xFF334155) : _gridBorder.withValues(alpha: 0.6);
    final textColor = isDark ? Colors.white : _textDark;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rowBgNormal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF334155) : _gridBorder),
        boxShadow: const [
          BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                // ── Header Row ──
                Container(
                  height: 48,
                  color: headerBg,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Row(
                          children: [
                            Checkbox(
                              value: _selectAllChecked,
                              activeColor: _teal,
                              onChanged: _toggleSelectAll,
                            ),
                            Text('Select', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)),
                          ],
                        ),
                      ),
                      _vDivider(borderColor),
                      SizedBox(width: 155, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('Code / Barcode', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)))),
                      _vDivider(borderColor),
                      Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('Medicine Formula (Generic)', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)))),
                      _vDivider(borderColor),
                      SizedBox(width: 125, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)))),
                      _vDivider(borderColor),
                      SizedBox(width: 115, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('Dose', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)))),
                      _vDivider(borderColor),
                      SizedBox(width: 125, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('Price (PKR) *', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)))),
                      _vDivider(borderColor),
                      SizedBox(width: 150, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('Expiry Date *', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)))),
                      _vDivider(borderColor),
                      SizedBox(width: 185, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('Quantity to Add *', style: TextStyle(fontWeight: FontWeight.bold, color: headerTextColor, fontSize: 13.5)))),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),
                // ── Rows (Virtualised ListView.builder for instant 60 FPS performance) ──
                Expanded(
                  child: ListView.separated(
                    itemCount: _filteredList.length,
                    separatorBuilder: (_, index) => Divider(height: 1, color: borderColor),
                    itemBuilder: (context, index) {
                      final item = _filteredList[index];
                      final code = item['code'] as String? ?? 'MED-GEN';
                      final isChecked = _selectedItems[code] ?? false;
                      final expDate = _expiryDates[code] ?? DateTime.now().add(const Duration(days: 365));
                      final bg = isChecked ? rowBgSelected : (index % 2 == 0 ? rowBgNormal : rowBgAlt);

                      return Container(
                        height: 58,
                        color: bg,
                        child: Row(
                          children: [
                            // Select Checkbox
                            SizedBox(
                              width: 110,
                              child: Center(
                                child: Checkbox(
                                  value: isChecked,
                                  activeColor: _teal,
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedItems[code] = val ?? false;
                                    });
                                  },
                                ),
                              ),
                            ),
                            _vDivider(borderColor),

                            // Code / Barcode
                            SizedBox(
                              width: 155,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0C4A6E) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isDark ? const Color(0xFF0284C7) : Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    code,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? const Color(0xFF7DD3FC) : _textDark,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _vDivider(borderColor),

                            // Formula Name
                            Expanded(
                              flex: 4,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  item['formula'] as String? ?? item['name'] as String? ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13.5),
                                ),
                              ),
                            ),
                            _vDivider(borderColor),

                            // Type
                            SizedBox(
                              width: 125,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Chip(
                                  label: Text(
                                    item['type'] as String? ?? 'Tablet',
                                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  backgroundColor: _getTypeBadgeColor(item['type'] as String? ?? 'Tablet'),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            _vDivider(borderColor),

                            // Dose
                            SizedBox(
                              width: 115,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  item['dose'] as String? ?? '-',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: isDark ? const Color(0xFFCBD5E1) : _textDark, fontSize: 13),
                                ),
                              ),
                            ),
                            _vDivider(borderColor),

                            // Price
                            SizedBox(
                              width: 125,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: SizedBox(
                                  height: 38,
                                  child: TextField(
                                    controller: _priceControllers[code],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                                    style: TextStyle(fontSize: 12.5, color: textColor),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      filled: isDark,
                                      fillColor: isDark ? const Color(0xFF334155) : null,
                                      prefixText: 'Rs ',
                                      prefixStyle: TextStyle(color: isDark ? const Color(0xFF38BDF8) : _teal, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _vDivider(borderColor),

                            // Expiry Date
                            SizedBox(
                              width: 150,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: InkWell(
                                  onTap: () => _pickExpiryDate(code),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: isDark ? const Color(0xFF38BDF8) : _teal.withValues(alpha: 0.5)),
                                      borderRadius: BorderRadius.circular(6),
                                      color: isDark ? const Color(0xFF334155) : _white,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.calendar_today, size: 13, color: isDark ? const Color(0xFF38BDF8) : _teal),
                                        const SizedBox(width: 6),
                                        Text(
                                          DateFormat('yyyy-MM-dd').format(expDate),
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _tealDark),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _vDivider(borderColor),

                            // Quantity Stepper
                            SizedBox(
                              width: 185,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: _red, size: 20),
                                    onPressed: () {
                                      final current = int.tryParse(_qtyControllers[code]?.text ?? '0') ?? 0;
                                      if (current > 0) {
                                        _qtyControllers[code]?.text = (current - 1).toString();
                                      }
                                    },
                                  ),
                                  SizedBox(
                                    width: 64,
                                    height: 38,
                                    child: TextField(
                                      controller: _qtyControllers[code],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: textColor),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                        filled: isDark,
                                        fillColor: isDark ? const Color(0xFF334155) : null,
                                      ),
                                      onChanged: (val) {
                                        final qty = int.tryParse(val) ?? 0;
                                        if (qty > 0 && _selectedItems[code] != true) {
                                          setState(() => _selectedItems[code] = true);
                                        }
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, color: _green600, size: 20),
                                    onPressed: () {
                                      final current = int.tryParse(_qtyControllers[code]?.text ?? '0') ?? 0;
                                      _qtyControllers[code]?.text = (current + 1).toString();
                                      if (_selectedItems[code] != true) {
                                        setState(() => _selectedItems[code] = true);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vDivider(Color color) {
    return Container(width: 1, height: double.infinity, color: color);
  }

  Widget _buildEmptyState() {
    final isDark = _isDark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(FontAwesomeIcons.magnifyingGlass, size: 48, color: isDark ? const Color(0xFF64748B) : Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No master proforma items matching "${_searchCtrl.text}"',
            style: TextStyle(fontSize: 16, color: isDark ? const Color(0xFFCBD5E1) : _textMid),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final count = _selectedCount;
    final isDark = _isDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey.shade200)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, -4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count of ${_proformaMasterList.length} Medicines Selected',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : _tealDark),
                ),
                const SizedBox(height: 2),
                Text(
                  'Showing ${_filteredList.length} of ${_proformaMasterList.length} total catalog medicines • Specifications protected.',
                  style: TextStyle(fontSize: 11.5, color: isDark ? const Color(0xFF94A3B8) : _textMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: count > 0 ? (isDark ? const Color(0xFF0F766E) : _teal) : Colors.grey,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 4,
            ),
            onPressed: count > 0 && !_isSavingBatch ? _saveBatchToInventory : null,
            icon: _isSavingBatch
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(FontAwesomeIcons.floppyDisk, color: Colors.white, size: 16),
            label: Text(
              _isSavingBatch ? 'Adding to Inventory...' : 'Add Selected to Stock',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeBadgeColor(String type) {
    if (_isDark) {
      switch (type.trim().toLowerCase()) {
        case 'tablet':
          return const Color(0xFF1D4ED8);
        case 'capsule':
          return const Color(0xFF7E22CE);
        case 'syrup':
          return const Color(0xFFC2410C);
        case 'injection':
          return const Color(0xFFB91C1C);
        case 'drip':
          return const Color(0xFF0F766E);
        case 'drip set':
          return const Color(0xFF0E7490);
        case 'syringe':
          return const Color(0xFFBE185D);
        case 'cannula':
        case 'needle':
        case 'cannula & needle':
        case 'cannula / needle':
          return const Color(0xFF9D174D);
        case 'nebulization':
          return const Color(0xFF4338CA);
        case 'dressing item':
          return const Color(0xFF334155);
        case 'consumables':
          return const Color(0xFF0F766E);
        default:
          return const Color(0xFF334155);
      }
    }
    switch (type.trim().toLowerCase()) {
      case 'tablet':
        return const Color(0xFF1565C0);
      case 'capsule':
        return const Color(0xFF6A1B9A);
      case 'syrup':
        return const Color(0xFFE65100);
      case 'injection':
        return const Color(0xFFC62828);
      case 'drip':
        return const Color(0xFF00695C);
      case 'drip set':
        return const Color(0xFF00838F);
      case 'syringe':
        return const Color(0xFFAD1457);
      case 'cannula':
      case 'needle':
      case 'cannula & needle':
      case 'cannula / needle':
        return const Color(0xFF7B1FA2);
      case 'nebulization':
        return const Color(0xFF283593);
      case 'dressing item':
        return const Color(0xFF455A64);
      case 'consumables':
        return const Color(0xFF00796B);
      default:
        return const Color(0xFF455A64);
    }
  }
}
