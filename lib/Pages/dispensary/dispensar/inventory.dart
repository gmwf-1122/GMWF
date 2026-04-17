// lib/Pages/dispensary/dispensar/inventory.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import 'dispensar_screen.dart';
import 'inventory_update.dart';
import 'inventory_adjustment.dart';
import '../../request.dart';
import '../../../services/local_storage_service.dart';

class InventoryPage extends StatefulWidget {
  final String branchId;
  final bool isAdmin;
  final bool isDispenser;

  const InventoryPage({
    super.key,
    required this.branchId,
    this.isAdmin = false,
    this.isDispenser = false,
  });

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with TickerProviderStateMixin {
  // ── Palette ───────────────────────────────────────────────────────────────
  static const _teal = Color(0xFF00695C);
  static const _tealDark = Color(0xFF004D40);
  static const _bg = Color(0xFFF1F8F6);
  static const _white = Colors.white;
  static const _green50 = Color(0xFFE8F5E9);
  static const _green100 = Color(0xFFC8E6C9);
  static const _green600 = Color(0xFF2E7D32);
  static const _red = Color(0xFFD32F2F); // More vibrant, premium red
  static const _orange = Color(0xFFE65100);
  static const _amber = Color(0xFFF57F17);
  static const _blue = Color(0xFF1976D2);
  static const _purple = Color(0xFF6A1B9A);
  static const _indigo = Color(0xFF283593);
  static const _brown = Color(0xFF4E342E);
  static const _textDark = Color(0xFF1B2631);
  static const _textMid = Color(0xFF4A5568);
  static const _textLight = Color(0xFF718096);
  static const _border = Color(0xFFB2DFDB);
  static const _shadow = Color(0x1800695C);

  bool get _isManager => !widget.isAdmin && !widget.isDispenser;

  static const _editRequestTypes = {'edit_medicine', 'delete_medicine'};

  static Color _typeColor(String t) => switch (t) {
        'Tablet' => const Color(0xFF1565C0),
        'Capsule' => const Color(0xFF6A1B9A),
        'Syrup' => const Color(0xFFF57F17),
        'Injection' => const Color(0xFFC62828),
        'Drip' => const Color(0xFF00695C),
        'Drip Set' => const Color(0xFF00838F),
        'Syringe' => const Color(0xFFAD1457),
        'Nebulization' => const Color(0xFF283593),
        _ => const Color(0xFF37474F),
      };

  // 4 tabs: Stock | Pending | Log | History
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _filterType = 'All';
  String _filterBatch = 'All Batches';
  String _sortField = 'name';
  bool _isAscending = true;
  int _page = 0;
  final int _perPage = 15;
  List<String> _batchKeys = ['All Batches'];

  // ── Sync & Stream Management ─────────────────────────────────────────────
  StreamSubscription? _fireInvSub;
  StreamSubscription? _logCombinedSub;
  final _logState = BehaviorSubject<List<Map<String, dynamic>>>();

  final List<String> _types = [
    'All', 'Tablet', 'Capsule', 'Syrup', 'Injection',
    'Drip', 'Drip Set', 'Syringe', 'Nebulization', 'Others',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _initSync();
  }

  void _initSync() {
    // 1. Background Sync: Keep Hive updated with any remote changes from Firestore
    _fireInvSub = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          LocalStorageService.deleteLocalStockItem(change.doc.id);
        } else {
          LocalStorageService.saveLocalInventoryItem(
              {...change.doc.data() as Map<String, dynamic>, 'id': change.doc.id, 'branchId': widget.branchId});
        }
      }
    });

    // 2. Merged Log: Combine Cloud Logs + Local Pending Sync items
    final cloudLogStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory_log')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data() as Map<String, dynamic>).toList());

    final localSyncStream = Hive.box(LocalStorageService.syncBox)
        .watch()
        .map((_) => _getPendingLogs());

    _logCombinedSub = Rx.combineLatest2<List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<Map<String, dynamic>>>(
      cloudLogStream,
      localSyncStream.startWith(_getPendingLogs()),
      (cloud, local) {
        final merged = [...local, ...cloud];
        return merged;
      }
    ).listen((list) => _logState.add(list));
  }

  List<Map<String, dynamic>> _getPendingLogs() {
    final box = Hive.box(LocalStorageService.syncBox);
    final pending = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final item = Map<String, dynamic>.from(box.get(key) as Map);
      final type = item['type']?.toString();
      if (type == 'add_inventory_stock' || type == 'register_medicine') {
        final data = Map<String, dynamic>.from(item['data'] ?? item);
        pending.add({
          ...data,
          '_isPending': true,
          'action': type == 'add_inventory_stock' ? 'add_stock' : 'medicine_registered_directly',
          'medicineName': data['medicineName'] ?? data['name'] ?? 'Pending...',
          'timestamp': item['createdAt'] != null ? Timestamp.fromDate(DateTime.parse(item['createdAt'])) : Timestamp.now(),
        });
      }
    }
    return pending;
  }

  @override
  void dispose() {
    _fireInvSub?.cancel();
    _logCombinedSub?.cancel();
    _logState.close();
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  int _asInt(dynamic v) => v is int
      ? v
      : v is double
          ? v.toInt()
          : v is String
              ? (int.tryParse(v) ?? 0)
              : 0;

  double _parsePrice(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String _fmtPrice(double price) =>
      price == price.floorToDouble()
          ? price.toInt().toString()
          : price.toStringAsFixed(2);

  Widget _typeIconWidget(String t, {double size = 14, Color? color}) {
    final c = color ?? _teal;
    final icon = switch (t) {
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
    return Icon(icon, size: size, color: c);
  }

  void _sort(String field) {
    if (field == 'type') return;
    setState(() {
      if (_sortField == field) {
        _isAscending = !_isAscending;
      } else {
        _sortField = field;
        _isAscending = true;
      }
      _page = 0;
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    if (raw.length == 7 && raw[2] == '-') return raw;
    final p = raw.split('-');
    if (p.length != 3) return raw;
    return '${p[0].padLeft(2, '0')}-${p[1].padLeft(2, '0')}-${p[2]}';
  }

  bool _isExpiringSoon(String? exp) {
    if (exp == null || exp.isEmpty) return false;
    try {
      final p = exp.split('-');
      DateTime date;
      if (p.length == 2) {
        date = DateTime(int.parse(p[1]), int.parse(p[0]) + 1, 0);
      } else if (p.length == 3) {
        date = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      } else {
        return false;
      }
      final diff = date.difference(DateTime.now()).inDays;
      return diff <= 30 && diff >= 0;
    } catch (_) {
      return false;
    }
  }

  DateTime _parseExpiry(String? s) {
    if (s == null || s.isEmpty) return DateTime(3000);
    try {
      final p = s.split('-');
      if (p.length == 2) return DateTime(int.parse(p[1]), int.parse(p[0]), 15);
      if (p.length == 3)
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {}
    return DateTime(3000);
  }

  List<Map<String, dynamic>> _groupByBatch(
      Iterable<Map<String, dynamic>> docs) {
    final Map<String, Map<String, dynamic>> map = {};
    for (final data in docs) {
      final name = (data['name'] ?? '').toString().trim();
      final type = data['type'] ?? '';
      final dose = (data['dose'] ?? '').toString().trim();
      final expiry = data['expiryDate']?.toString().trim() ?? '';
      final qty = _asInt(data['quantity']);
      final price = _parsePrice(data['price']);
      final formula = (data['formula'] ?? '').toString().trim();

      String monthYear = '';
      if (expiry.length == 10 && expiry[2] == '-' && expiry[5] == '-') {
        monthYear = expiry.substring(3);
      } else {
        monthYear = expiry;
      }

      String doseDisplay = dose;
      if (type == 'Nebulization' && dose.isEmpty) doseDisplay = 'per session';

      final key = '$name|$type|$dose|$monthYear';
      if (map.containsKey(key)) {
        map[key]!['quantity'] = (map[key]!['quantity'] as int) + qty;
        (map[key]!['_docIds'] as List<String>).add(data['id'] ?? data['medicineId'] ?? 'unknown');
      } else {
        map[key] = {
          'name': name,
          'type': type,
          'dose': doseDisplay,
          'formula': formula,
          'expiryDate': monthYear,
          'quantity': qty,
          'price': price,
          'batchKey': key,
          '_docIds': <String>[data['id'] ?? data['medicineId'] ?? 'unknown'],
        };
      }
    }
    return map.values.toList();
  }

  void _updateBatchKeys(List<Map<String, dynamic>> preFiltered) {
    final set = <String>{};
    for (final b in preFiltered) {
      final e = (b['expiryDate'] as String?) ?? '';
      if (e.isNotEmpty) set.add(e);
    }
    var list = set.toList();
    list.sort((a, b) {
      int n(String s) {
        final p = s.split('-');
        if (p.length != 2) return 0;
        return (int.tryParse(p[1]) ?? 0) * 100 + (int.tryParse(p[0]) ?? 0);
      }
      return n(a).compareTo(n(b));
    });
    final newKeys = ['All Batches', ...list];
    if (_batchKeys.join(',') != newKeys.join(',')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _batchKeys = newKeys;
          if (!_batchKeys.contains(_filterBatch)) _filterBatch = 'All Batches';
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: _buildAppBar(),
        floatingActionButton: widget.isAdmin
            ? null
            : FloatingActionButton.extended(
                backgroundColor: _teal,
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            InventoryUpdatePage(
                              branchId: widget.branchId,
                              isAdmin: widget.isAdmin,
                              isDispenser: widget.isDispenser,
                            ))),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text('Update Stock',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [_stockTab(), _pendingTab(), _logTab(), _historyTab()],
        ),
      );

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: _teal,
        elevation: 4,
        shadowColor: _shadow,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () {
            if (widget.isDispenser) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        DispensarScreen(branchId: widget.branchId)),
              );
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Row(children: [
          const Icon(FontAwesomeIcons.pills,
              color: Colors.white70, size: 16),
          const SizedBox(width: 10),
          const Text('Inventory',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          if (_isManager) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_rounded, size: 10, color: Colors.white70),
                SizedBox(width: 3),
                Text('editable',
                    style: TextStyle(color: Colors.white70, fontSize: 10)),
              ]),
            ),
          ],
        ]),
        actions: widget.isDispenser
            ? []
            : [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => InventoryAdjustmentPage(
                                branchId: widget.branchId))),
                    icon: const Icon(FontAwesomeIcons.sliders,
                        size: 14, color: Colors.white),
                    label: const Text('Adjust',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFBF360C),
                      foregroundColor: Colors.white,
                      elevation: 3,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                    ),
                  ),
                ),
              ],
        // Full-width tab bar with equal spacing
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: TabBar(
            controller: _tabCtrl,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            // Use non-scrollable so tabs fill full width
            isScrollable: false,
            tabs: const [
              Tab(icon: Icon(Icons.inventory_2_rounded, size: 17), text: 'Stock'),
              Tab(
                  icon: Icon(Icons.pending_actions_rounded, size: 17),
                  text: 'Pending'),
              Tab(icon: Icon(Icons.history_edu_rounded, size: 17), text: 'Log'),
              Tab(icon: Icon(Icons.history_rounded, size: 17), text: 'History'),
            ],
          ),
        ),
      );

  // ── Stock Tab ─────────────────────────────────────────────────────────────
  Widget _stockTab() => Column(children: [
        Container(
          color: _white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(children: [
            if (_isManager)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF90CAF9)),
                ),
                child: const Row(children: [
                  Icon(Icons.touch_app_rounded,
                      size: 15, color: Color(0xFF1565C0)),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    'Tap any medicine row to edit it directly.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w500),
                  )),
                ]),
              ),
            TextField(
              controller: _searchCtrl,
              cursorColor: _teal,
              style: const TextStyle(color: _textDark, fontSize: 14),
              decoration: InputDecoration(
                prefixIcon:
                    const Icon(Icons.search_rounded, color: _teal, size: 18),
                hintText: 'Search medicine...',
                hintStyle:
                    const TextStyle(color: _textLight, fontSize: 14),
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
                    horizontal: 14, vertical: 11),
              ),
              onChanged: (_) => setState(() => _page = 0),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _filterDropdown(
                      _filterType,
                      _types,
                      (v) => setState(() {
                            _filterType = v ?? 'All';
                            _page = 0;
                          }))),
              const SizedBox(width: 10),
              Expanded(
                  child: _filterDropdown(
                _filterBatch,
                _batchKeys,
                (v) => setState(() {
                  _filterBatch = v ?? 'All Batches';
                  _page = 0;
                }),
                display: (k) => k == 'All Batches' ? k : 'Batch: $k',
              )),
            ]),
          ]),
        ),
        Expanded(
          child: ValueListenableBuilder<Box>(
            valueListenable: Hive.box(LocalStorageService.stockBox).listenable(),
            builder: (context, box, _) {
              final rawItems = box.values
                  .whereType<Map>()
                  .map((v) => Map<String, dynamic>.from(v))
                  .where((v) => v['branchId'] == widget.branchId)
                  .toList();

              if (rawItems.isEmpty) {
                return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 72, color: Colors.grey[300]),
                      const SizedBox(height: 14),
                      Text(
                          widget.isAdmin
                              ? 'No medicines in local stock.'
                              : 'No medicines in local stock.\nChecking cloud...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: _textLight, fontSize: 15)),
                    ]));
              }

              final batches = _groupByBatch(rawItems);
              var preFiltered = batches.where((b) {
                final name = b['name'].toString().toLowerCase();
                final formula =
                    (b['formula'] ?? '').toString().toLowerCase();
                final type = b['type'];
                final query = _searchCtrl.text.toLowerCase();
                return (name.contains(query) ||
                        formula.contains(query)) &&
                    (_filterType == 'All' || type == _filterType);
              }).toList();

              _updateBatchKeys(preFiltered);

              var filtered = _filterBatch == 'All Batches'
                  ? preFiltered
                  : preFiltered
                      .where((b) => b['expiryDate'] == _filterBatch)
                      .toList();

              filtered.sort((a, b) {
                int cmp = switch (_sortField) {
                  'name' => a['name']
                      .toString()
                      .toLowerCase()
                      .compareTo(b['name'].toString().toLowerCase()),
                  'formula' => (a['formula'] ?? '')
                      .toString()
                      .toLowerCase()
                      .compareTo(
                          (b['formula'] ?? '').toString().toLowerCase()),
                  'dose' => (a['dose'] ?? '')
                      .toString()
                      .compareTo((b['dose'] ?? '').toString()),
                  'quantity' =>
                    (a['quantity'] as int).compareTo(b['quantity'] as int),
                  'price' =>
                    (a['price'] as double).compareTo(b['price'] as double),
                  'expiry' => _parseExpiry(a['expiryDate'])
                      .compareTo(_parseExpiry(b['expiryDate'])),
                  _ => 0,
                };
                return _isAscending ? cmp : -cmp;
              });

              final totalPages =
                  (filtered.length / _perPage).ceil().clamp(1, 9999);
              final safePage = _page.clamp(0, totalPages - 1);
              final start = safePage * _perPage;
              final end = (start + _perPage).clamp(0, filtered.length);
              final pageData = start < end
                  ? filtered.sublist(start, end)
                  : <Map<String, dynamic>>[];

              return Column(children: [
                Expanded(
                    child: LayoutBuilder(builder: (ctx, constraints) {
                  return constraints.maxWidth > 640
                      ? _stockTable(pageData, start, constraints.maxWidth)
                      : _stockCards(pageData, start);
                })),
                _pagination(safePage, totalPages),
              ]);
            },
          ),
        ),
      ]);

  Widget _filterDropdown(
      String value, List<String> items, ValueChanged<String?> onChange,
      {String Function(String)? display}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _green50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: _white,
        style: const TextStyle(color: _textDark, fontSize: 13),
        icon:
            const Icon(Icons.expand_more_rounded, color: _teal, size: 18),
        items: items
            .map((t) => DropdownMenuItem<String>(
                value: t,
                child: Text(display != null ? display(t) : t,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _textDark, fontSize: 13))))
            .toList(),
        onChanged: onChange,
      ),
    );
  }

  // ── Stock Table (wide screens) ─────────────────────────────────────────────
  Widget _stockTable(
      List<Map<String, dynamic>> data, int start, double w) {
    final cols = [
      _Col('#', w * 0.04, null),
      // "Formula" label instead of "Name"
      _Col('Formula', w * 0.18, 'name'),
      _Col('Type', w * 0.11, null),
      _Col('Dose', w * 0.14, 'dose'),
      _Col('Qty', w * 0.08, 'quantity'),
      _Col('Price', w * 0.11, 'price'),
      _Col('Expiry', w * 0.19, 'expiry'),
    ];
    return Column(children: [
      Container(
        decoration: const BoxDecoration(
          color: Color(0xFF004D40),
          border:
              Border(bottom: BorderSide(color: Color(0xFF00695C), width: 2)),
        ),
        child: Row(
            children: cols.map((c) => _hCell(c.w, c.label, c.sort)).toList()),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: data.length,
        itemBuilder: (ctx, i) {
          final b = data[i];
          final qty = b['quantity'] as int;
          final type = b['type'] as String;
          final price = b['price'] as double;
          final lowStock = qty < 10;
          final expSoon = _isExpiringSoon(b['expiryDate'] as String?);
          final expText = _formatDate(b['expiryDate'] as String?);
          final isWarning = lowStock || expSoon;
          // Strong color: expired = deep red, low stock = deep red
          final rowColor = isWarning
              ? const Color(0xFFFFEBEE) // strong red tint
              : (i % 2 == 0 ? _white : const Color(0xFFF0FAF4));

          final rowContent = Container(
            decoration: BoxDecoration(
              color: rowColor,
              border: Border(
                  bottom: BorderSide(
                      color: isWarning
                          ? _red.withOpacity(0.4)
                          : const Color(0xFFDCEDDE),
                      width: isWarning ? 1.2 : 0.8),
                  left: isWarning
                      ? const BorderSide(color: _red, width: 5)
                      : BorderSide.none),
            ),
            child: Row(children: [
              _dCell(
                  cols[0].w,
                  Text('${start + i + 1}',
                      style:
                          const TextStyle(color: _textLight, fontSize: 12))),
              _dCell(
                  cols[1].w,
                  Row(children: [
                    Expanded(
                        child: Text(b['name'],
                            style: TextStyle(
                                color: isWarning ? _red : _textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis)),
                    if (_isManager)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.edit_rounded,
                            size: 12, color: _teal),
                      ),
                  ])),
              _dCell(cols[2].w, _typePill(type)),
              _dCell(
                  cols[3].w,
                  Text(b['dose'] ?? '—',
                      style: const TextStyle(color: _textMid, fontSize: 12))),
              _dCell(cols[4].w, _qtyBadge(qty, lowStock)),
              _dCell(cols[5].w, _priceBadge(price)),
              _dCell(cols[6].w, _expBadge(expText, expSoon)),
              if (lowStock || expSoon)
                _dCell(
                    120,
                    _statusLabel(
                        lowStock: lowStock, expSoon: expSoon, isTable: true)),
            ]),
          );

          if (_isManager) {
            return InkWell(
              onTap: () => _showEditSheet(b),
              hoverColor: _teal.withOpacity(0.05),
              child: rowContent,
            );
          }
          return rowContent;
        },
      )),
    ]);
  }

  // ── Stock Cards (narrow screens) ──────────────────────────────────────────
  Widget _stockCards(List<Map<String, dynamic>> data, int start) =>
      ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: data.length,
        itemBuilder: (ctx, i) {
          final b = data[i];
          final qty = _asInt(b['quantity']);
          final type = b['type']?.toString() ?? '';
          final price = _parsePrice(b['price']);
          final lowStock = qty < 10;
          final expSoon = _isExpiringSoon(b['expiryDate']?.toString());
          final expText = _formatDate(b['expiryDate']?.toString());

          final isWarning = lowStock || expSoon;

          final card = Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              // Strong red background for warning items
              color: isWarning ? const Color(0xFFFFEBEE) : _white,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                top: isWarning ? const BorderSide(color: _red, width: 3) : const BorderSide(color: Color(0xFFE0E0E0), width: 0.8),
                left: isWarning ? const BorderSide(color: _red, width: 5) : const BorderSide(color: Color(0xFFE0E0E0), width: 0.8),
                right: isWarning ? const BorderSide(color: _red, width: 1) : const BorderSide(color: Color(0xFFE0E0E0), width: 0.8),
                bottom: isWarning ? const BorderSide(color: _red, width: 1) : const BorderSide(color: Color(0xFFE0E0E0), width: 0.8),
              ),
              boxShadow: [
                BoxShadow(
                    color: isWarning
                        ? _red.withOpacity(0.18)
                        : _shadow,
                    blurRadius: isWarning ? 10 : 6,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: isWarning
                              ? _red.withOpacity(0.1)
                              : _green50,
                          borderRadius: BorderRadius.circular(8)),
                      child: _typeIconWidget(type,
                          size: 13,
                          color: isWarning ? _red : null),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${start + i + 1}. ${b['name']}',
                            style: TextStyle(
                                color: isWarning ? _red : _textDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5)),
                      ],
                    )),
                    if (_isManager)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 14, color: _teal),
                      )
                    else
                      _qtyBadge(qty, lowStock),
                  ]),
                  if (_isManager) ...[
                    const SizedBox(height: 6),
                    _qtyBadge(qty, lowStock),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _typePill(type),
                    if ((b['dose'] ?? '').toString().isNotEmpty)
                      _infoBadge(b['dose'].toString(), _textMid),
                    _priceBadge(price),
                    _expBadge(expText, expSoon),
                    if (lowStock || expSoon)
                      _statusLabel(lowStock: lowStock, expSoon: expSoon),
                  ]),
                ]),
          );

          if (_isManager) {
            return GestureDetector(
                onTap: () => _showEditSheet(b), child: card);
          }
          return card;
        },
      );


  void _showEditSheet(Map<String, dynamic> batchData) {
    final docIds =
        List<String>.from(batchData['_docIds'] as List? ?? []);
    if (docIds.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditMedicineSheet(
        branchId: widget.branchId,
        docIds: docIds,
        initial: batchData,
        medicineTypes: _types.where((t) => t != 'All').toList(),
        formatDate: _formatDate,
      ),
    );
  }

  // ── Pagination ─────────────────────────────────────────────────────────────
  Widget _pagination(int page, int total) => Container(
        color: _white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _pgBtn(Icons.first_page_rounded, page > 0,
              () => setState(() => _page = 0)),
          _pgBtn(Icons.chevron_left_rounded, page > 0,
              () => setState(() => _page--)),
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _green50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _green100),
            ),
            child: Text('${page + 1} / $total',
                style: const TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          _pgBtn(Icons.chevron_right_rounded, page + 1 < total,
              () => setState(() => _page++)),
          _pgBtn(Icons.last_page_rounded, page + 1 < total,
              () => setState(() => _page = total - 1)),
        ]),
      );

  Widget _pgBtn(IconData icon, bool enabled, VoidCallback fn) =>
      IconButton(
        icon: Icon(icon,
            size: 20, color: enabled ? _teal : Colors.grey[300]),
        onPressed: enabled ? fn : null,
      );

  // ── Pending Tab ───────────────────────────────────────────────────────────
  Widget _pendingTab() => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('edit_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _teal));
          }
          var docs = snap.data?.docs ?? [];

          docs = docs.where((d) {
            final t =
                (d.data() as Map<String, dynamic>)['requestType']?.toString() ??
                    '';
            return _editRequestTypes.contains(t);
          }).toList();

          if (docs.isEmpty) {
            return _emptyState(Icons.pending_actions_rounded,
                'No pending edit requests');
          }

          docs.sort((a, b) {
            final ta = (a.data() as Map<String, dynamic>)['requestedAt']
                as Timestamp?;
            final tb = (b.data() as Map<String, dynamic>)['requestedAt']
                as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _requestCard(
                docs[i].id,
                docs[i].data() as Map<String, dynamic>,
                'pending'),
          );
        },
      );

  // ── Log Tab ───────────────────────────────────────────────────────────────
  // ── Log Tab (Merged Cloud + Local Pending) ──────────────────────────────
  Widget _logTab() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _logState.stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _teal));
          }
          
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return _emptyState(Icons.history_edu_rounded,
                'No activity yet.\nStock updates will appear here.');
          }

          // Ensure strict temporal sort
          final sorted = list..sort((a, b) {
            final tsA = a['timestamp'] as Timestamp;
            final tsB = b['timestamp'] as Timestamp;
            return tsB.compareTo(tsA);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: sorted.length,
            itemBuilder: (ctx, i) {
              return _logCard(sorted[i]);
            },
          );
        },
      );

  Widget _logCard(Map<String, dynamic> data) {
    final action = data['action']?.toString() ?? '';
    final medicineName = data['medicineName']?.toString() ?? '—';
    final medicineType = data['medicineType']?.toString() ?? '';
    final dose = data['dose']?.toString() ?? '';
    final qtyAdded = data['quantityAdded'] ?? 0;
    final performedBy = data['performedByName']?.toString() ?? 'Unknown';
    final ts = data['timestamp'] as Timestamp?;
    final price = data['price']?.toString() ?? '';
    final expiry = data['expiryDate']?.toString() ?? '';

    final isRegistration = action == 'medicine_registered' ||
        action == 'medicine_registered_directly';
    final isEdited = action == 'medicine_edited';
    final Color accentColor = isEdited ? _purple : (isRegistration ? _blue : _green600);
    final IconData actionIcon = isEdited
        ? Icons.edit_rounded
        : (isRegistration ? Icons.medication_liquid_rounded : Icons.add_box_rounded);
    final String actionLabel = isEdited
        ? 'MEDICINE EDITED'
        : (isRegistration ? 'NEW MEDICINE' : 'STOCK ADDED');
    final Color labelBg = isEdited
        ? const Color(0xFFF3E5F5)
        : (isRegistration ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9));
    final Color labelFg = isEdited ? _purple : (isRegistration ? _blue : _green600);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: _shadow, blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(actionIcon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: labelBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(actionLabel,
                    style: TextStyle(
                        color: labelFg,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              if (data['_isPending'] == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _orange.withOpacity(0.3)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_rounded, size: 9, color: _orange),
                    SizedBox(width: 3),
                    Text('PENDING SYNC',
                        style: TextStyle(
                            color: _orange,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5)),
                  ]),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Text(medicineName,
                style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 5, children: [
              if (medicineType.isNotEmpty)
                _miniChip(medicineType, _teal),
              if (dose.isNotEmpty) _miniChip(dose, _textMid),
              _miniChip('+$qtyAdded units', accentColor),
              if (isRegistration && price.isNotEmpty)
                _miniChip('PKR $price', _orange),
              if (isRegistration && expiry.isNotEmpty)
                _miniChip('Exp: ${_formatDate(expiry)}', _textMid),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.person_outline_rounded,
                  size: 13, color: _textLight),
              const SizedBox(width: 5),
              Text(performedBy,
                  style: const TextStyle(
                      color: _textMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (ts != null) ...[
                const SizedBox(width: 10),
                const Icon(Icons.access_time_rounded,
                    size: 12, color: _textLight),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()),
                  style: const TextStyle(
                      color: _textLight, fontSize: 11),
                ),
              ]
            ]),
          ])),
        ]),
      ),
    );
  }

  // ── History Tab ───────────────────────────────────────────────────────────
  // Uses a nested DefaultTabController so inner tabs fill full width
  Widget _historyTab() {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: _white,
          // Full-width inner tabs
          child: const TabBar(
            indicatorColor: _teal,
            labelColor: _teal,
            unselectedLabelColor: _textLight,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            isScrollable: false,
            tabs: [
              Tab(
                  icon: Icon(Icons.check_circle_rounded, size: 16),
                  text: 'Approved'),
              Tab(
                  icon: Icon(Icons.cancel_rounded, size: 16),
                  text: 'Rejected'),
            ],
          ),
        ),
        Expanded(
            child: TabBarView(children: [
          _historyList('approved'),
          _historyList('rejected')
        ])),
      ]),
    );
  }

  Widget _historyList(String status) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('edit_requests')
            .where('status', isEqualTo: status)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _teal));
          }
          var docs = snap.data?.docs ?? [];

          docs = docs.where((d) {
            final t =
                (d.data() as Map<String, dynamic>)['requestType']?.toString() ??
                    '';
            return _editRequestTypes.contains(t);
          }).toList();

          if (docs.isEmpty) {
            return _emptyState(
                status == 'approved'
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                'No $status edit requests');
          }

          docs.sort((a, b) {
            final ta = (a.data() as Map<String, dynamic>)['requestedAt']
                as Timestamp?;
            final tb = (b.data() as Map<String, dynamic>)['requestedAt']
                as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _requestCard(
                docs[i].id,
                docs[i].data() as Map<String, dynamic>,
                status),
          );
        },
      );

  Widget _requestCard(
      String docId, Map<String, dynamic> data, String status) {
    final requestType = data['requestType']?.toString() ?? '';
    final reason = data['reason']?.toString() ?? '';
    final ts = data['requestedAt'] as Timestamp?;
    final cachedName =
        (data['requesterName']?.toString() ?? '').trim();
    final requesterId =
        (data['requestedBy']?.toString() ??
                data['requester']?.toString() ??
                '')
            .trim();

    final Future<String> nameFuture = cachedName.isNotEmpty
        ? Future.value(cachedName)
        : requesterId.isEmpty
            ? Future.value('Unknown')
            : FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('users')
                .doc(requesterId)
                .get()
                .then((s) =>
                    s.data()?['username']?.toString() ?? 'User')
                .timeout(const Duration(seconds: 5),
                    onTimeout: () => 'User')
                .catchError((_) => 'User');

    Color badgeBg = switch (requestType) {
      'edit_medicine' => const Color(0xFFF3E5F5),
      'delete_medicine' => const Color(0xFFFFEBEE),
      _ => Colors.grey.shade100,
    };
    Color badgeFg = switch (requestType) {
      'edit_medicine' => _purple,
      'delete_medicine' => _red,
      _ => _textMid,
    };
    String typeLabel = switch (requestType) {
      'edit_medicine' => 'EDIT MEDICINE',
      'delete_medicine' => 'DELETE MEDICINE',
      _ => requestType.replaceAll('_', ' ').toUpperCase(),
    };

    Color statusColor = switch (status) {
      'approved' => _green600,
      'rejected' => _red,
      _ => _orange,
    };
    IconData statusIcon = switch (status) {
      'approved' => Icons.check_circle_rounded,
      'rejected' => Icons.cancel_rounded,
      _ => Icons.pending_rounded,
    };

    final rawItems = status == 'pending'
        ? (data['draftItems'] as List?) ?? (data['items'] as List?) ?? []
        : (data['items'] as List?) ?? [];
    final items = rawItems.cast<Map<String, dynamic>>();

    return Card(
      color: _green50,
      elevation: status == 'pending' ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                switch (requestType) {
                  'edit_medicine' => 'Edit Medicine Request',
                  'delete_medicine' => 'Delete Medicine Request',
                  _ => 'Inventory Request',
                },
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _tealDark),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(typeLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeFg)),
            ),
          ]),
          const SizedBox(height: 10),
          FutureBuilder<String>(
            future: nameFuture,
            builder: (_, snap) => Row(children: [
              const Icon(Icons.person_rounded, size: 15, color: _teal),
              const SizedBox(width: 6),
              Text('By: ${snap.data ?? '…'}',
                  style:
                      const TextStyle(fontSize: 13, color: _textDark)),
            ]),
          ),
          const SizedBox(height: 4),
          if (ts != null)
            Row(children: [
              const Icon(Icons.access_time_rounded,
                  size: 14, color: _textLight),
              const SizedBox(width: 6),
              Text(
                DateFormat('dd MMM yyyy, hh:mm a')
                    .format(ts.toDate()),
                style:
                    const TextStyle(fontSize: 12, color: _textLight),
              ),
            ]),
          const SizedBox(height: 12),
          if (requestType == 'edit_medicine')
            _buildMedicineEditComparison(data)
          else if (items.isNotEmpty)
            _buildItemsList(items),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.comment_rounded,
                      size: 14, color: _textLight),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Reason: $reason',
                          style: const TextStyle(
                              fontSize: 13, color: _textDark))),
                ],
              ),
            ),
          ],

          // ── Approver info (shown for approved/rejected cards in History) ──
          if (status != 'pending') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: status == 'approved'
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: status == 'approved'
                      ? _green600.withOpacity(0.35)
                      : _red.withOpacity(0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      status == 'approved'
                          ? Icons.verified_user_rounded
                          : Icons.gavel_rounded,
                      size: 14,
                      color: status == 'approved' ? _green600 : _red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status == 'approved' ? 'Approved by:' : 'Rejected by:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: status == 'approved' ? _green600 : _red,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        data['reviewedByName']?.toString() ?? '—',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: status == 'approved' ? _green600 : _red,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  if (data['reviewedAt'] != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.access_time_rounded,
                          size: 12, color: _textLight),
                      const SizedBox(width: 5),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a').format(
                            (data['reviewedAt'] as Timestamp).toDate()),
                        style: const TextStyle(
                            fontSize: 11, color: _textLight),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Approve / Reject buttons for pending; status chip otherwise
          if (status == 'pending' && !widget.isDispenser)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      _handleApproval(docId, data, 'rejected'),
                  child: const Text('Reject',
                      style: TextStyle(color: _red)),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _teal),
                  onPressed: () =>
                      _handleApproval(docId, data, 'approved'),
                  child: const Text('Approve',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            )
          else if (status == 'pending')
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _orange.withOpacity(0.45)),
                ),
                child: const Text('PENDING APPROVAL',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _orange)),
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  // ── Approve / Reject handler with inventory update ─────────────────────────
  Future<void> _handleApproval(
      String docId, Map<String, dynamic> data, String newStatus) async {
    final db = FirebaseFirestore.instance;
    final branchRef = db.collection('branches').doc(widget.branchId);
    final reqRef =
        branchRef.collection('edit_requests').doc(docId);

    try {
      String? reviewerName;
      final reviewerUid = FirebaseAuth.instance.currentUser?.uid;
      if (reviewerUid != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('users')
            .doc(reviewerUid)
            .get();
        reviewerName = userDoc.data()?['username']?.toString();
      }

      await reqRef.update({
        'status': newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': reviewerUid,
        if (reviewerName != null) 'reviewedByName': reviewerName,
      });

      if (newStatus == 'approved') {
        final requestType = data['requestType']?.toString() ?? '';

        if (requestType == 'edit_medicine') {
          // Apply the edits to inventory
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);

          if (itemsToUse.isNotEmpty) {
            await _applyEditMedicine(
                branchRef, data, itemsToUse, reviewerUid, reviewerName);
          }
        } else if (requestType == 'delete_medicine') {
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);
          await _applyDeleteMedicine(branchRef, itemsToUse);
        } else if (requestType == 'register_medicine') {
          final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
              ? _safeItemList(data['draftItems'])
              : _safeItemList(data['items']);
          if (itemsToUse.isNotEmpty) {
            for (final item in itemsToUse) {
              final name = item['name']?.toString() ?? '';
              final type = item['type'] ?? '';
              final dose = item['dose'] ?? '';
              final exp  = item['expiryDate'] ?? '';
              final id = RequestUtils.generateDocId(name, type, dose, exp);
              
              await branchRef.collection('inventory').doc(id).set({
                ...item,
                'addedAt': FieldValue.serverTimestamp(),
                'createdBy': data['requestedBy'],
                'createdByName': data['requesterName'],
                'approvedBy': reviewerUid,
                'approvedByName': reviewerName ?? 'Supervisor',
              });
            }
          }
        }
      }

      // Add to log for edits (if it was an edit)
      if (newStatus == 'approved' &&
          (data['requestType']?.toString() ?? '') == 'edit_medicine') {
        final itemsToUse = _safeItemList(data['draftItems']).isNotEmpty
            ? _safeItemList(data['draftItems'])
            : _safeItemList(data['items']);
        final originalDocId = data['docId']?.toString();

        for (final item in itemsToUse) {
          final name = item['name']?.toString() ?? '';
          final type = item['type'] ?? '';
          final dose = item['dose'] ?? '';
          final oldId = originalDocId ?? item['oldId']?.toString();
          
          await branchRef.collection('inventory_log').add({
            'action': 'medicine_edited',
            'medicineName': name,
            'medicineType': type,
            'dose': dose,
            'oldId': oldId,
            'performedBy': reviewerUid,
            'performedByName': reviewerName ?? 'Supervisor',
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request ${newStatus.toUpperCase()}'),
          backgroundColor: newStatus == 'approved' ? _teal : _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _red,
        ));
      }
    }
  }

  /// Applies edit_medicine approved request to inventory.
  /// Uses the docId stored in the request to update the right document.
  Future<void> _applyEditMedicine(
      DocumentReference branchRef,
      Map<String, dynamic> requestData,
      List<Map<String, dynamic>> items,
      String? reviewerUid,
      String? reviewerName) async {
    final inventory = branchRef.collection('inventory');
    final batch = FirebaseFirestore.instance.batch();

    // The original docId is stored at top-level in the request
    final originalDocId = requestData['docId']?.toString();

    for (final item in items) {
      final name = (item['name'] ?? '').toString().trim();
      final type = (item['type'] ?? '').toString().trim();
      final dose = (item['dose'] ?? '').toString().trim();
      final price = item['price']?.toString() ?? '0';
      final expiry = (item['expiryDate'] ?? '').toString().trim();

      final updateData = <String, dynamic>{
        'name': name,
        'name_lower': name.toLowerCase(),
        'type': type,
        'dose': dose,
        'price': price,
        'expiryDate': expiry,
        'updatedAt': FieldValue.serverTimestamp(),
        'approvedBy': reviewerUid,
        'approvedByName': reviewerName ?? 'Supervisor',
      };

      // Use original docId if available, else fall back to item's oldId
      final targetDocId =
          originalDocId ?? item['oldId']?.toString();

      if (targetDocId != null && targetDocId.isNotEmpty) {
        batch.update(inventory.doc(targetDocId), updateData);
      }
    }

    await batch.commit();
  }

  Future<void> _applyDeleteMedicine(
      DocumentReference branchRef,
      List<Map<String, dynamic>> items) async {
    final inventory = branchRef.collection('inventory');
    final batch = FirebaseFirestore.instance.batch();

    for (final item in items) {
      final name = item['name']?.toString();
      final type = item['type']?.toString();
      if (name == null || type == null) continue;
      final dose = item['dose']?.toString() ?? '';
      final expiry = item['expiryDate']?.toString() ?? '';

      // Try to find document by query
      final q = await inventory
          .where('name_lower', isEqualTo: name.toLowerCase())
          .where('type', isEqualTo: type)
          .get();
      for (final doc in q.docs) {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }

  Widget _buildMedicineEditComparison(Map<String, dynamic> data) {
    final originalData = data['originalData'] as Map<String, dynamic>? ?? {};
    final rawItems = data['draftItems'] ?? data['items'] ?? [];
    final items = _safeItemList(rawItems);
    
    final proposedData = items.isNotEmpty ? items.first : <String, dynamic>{};
    
    final fields = [
      {'key': 'name', 'label': 'Formula'},
      {'key': 'type', 'label': 'Type'},
      {'key': 'dose', 'label': 'Dose'},
      {'key': 'quantity', 'label': 'Qty'},
      {'key': 'price', 'label': 'Price'},
      {'key': 'expiryDate', 'label': 'Expiry'},
    ];

    String getValue(Map<String, dynamic> m, String key) {
      final v = m[key];
      if (key == 'price' && v != null && v.toString().isNotEmpty) {
        return 'PKR ${v.toString()}';
      }
      return v?.toString() ?? '—';
    }

    final isWide = MediaQuery.of(context).size.width > 600;

    if (isWide) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border.withOpacity(0.5)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_teal.withOpacity(0.05)),
            columnSpacing: 20,
            horizontalMargin: 16,
            columns: const [
              DataColumn(label: Text('Field', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              DataColumn(label: Text('Original', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              DataColumn(label: Text('Proposed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
            rows: fields.map((f) {
              final key = f['key'] as String;
              final oldVal = getValue(originalData, key);
              final newVal = getValue(proposedData, key);
              final isChanged = oldVal != newVal && newVal != '—';

              return DataRow(cells: [
                DataCell(Text(f['label']!, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                DataCell(Text(oldVal, style: TextStyle(
                  color: isChanged ? Colors.grey : _textDark,
                  decoration: isChanged ? TextDecoration.lineThrough : null,
                  fontSize: 12,
                ))),
                DataCell(Text(newVal, style: TextStyle(
                  color: isChanged ? Colors.blue.shade700 : _textDark,
                  fontWeight: isChanged ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ))),
              ]);
            }).toList(),
          ),
        ),
      );
    }

    // Mobile View
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, top: 4),
          child: Text('Proposed Changes:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _tealDark)),
        ),
        ...fields.map((f) {
          final key = f['key'] as String;
          final label = f['label'] as String;
          final oldVal = getValue(originalData, key);
          final newVal = getValue(proposedData, key);
          
          if (oldVal == newVal || newVal == '—') return const SizedBox.shrink();

          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(label, style: const TextStyle(fontSize: 11, color: _textLight, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(oldVal, style: const TextStyle(fontSize: 11, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward, size: 10, color: Colors.grey),
                      ),
                      Text(newVal, style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  List<Map<String, dynamic>> _safeItemList(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Widget _buildItemsList(List<Map<String, dynamic>> items) {
    final isWide = MediaQuery.of(context).size.width > 600;
    return isWide ? _itemsTable(items) : _itemsCompact(items);
  }

  Widget _itemsTable(List<Map<String, dynamic>> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor:
            WidgetStateProperty.all(_tealDark.withOpacity(0.07)),
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columnSpacing: 16,
        columns: const [
          // "Formula" label
          DataColumn(
              label: Text('Formula',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('Type',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('Dose',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('Qty',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('Price',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(
              label: Text('Expiry',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12))),
        ],
        rows: items.map((m) {
          final p = _parsePrice(m['price']);
          return DataRow(cells: [
            DataCell(Text(m['name']?.toString() ?? '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12))),
            DataCell(Row(children: [
              _typeIconWidget(m['type'] ?? '',
                  size: 12, color: _teal),
              const SizedBox(width: 5),
              Text(m['type']?.toString() ?? '—',
                  style: const TextStyle(fontSize: 12)),
            ])),
            DataCell(Text(m['dose']?.toString() ?? '—',
                style: const TextStyle(fontSize: 12))),
            DataCell(Text('${m['quantity'] ?? 0}',
                style: const TextStyle(fontSize: 12))),
            DataCell(Text('PKR ${_fmtPrice(p)}',
                style: const TextStyle(
                    fontSize: 12,
                    color: _green600,
                    fontWeight: FontWeight.w600))),
            DataCell(Text(
                _formatDate(m['expiryDate']?.toString()),
                style: const TextStyle(fontSize: 12))),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _itemsCompact(List<Map<String, dynamic>> items) {
    return Column(
      children: items.map((m) {
        final name = m['name']?.toString() ?? '—';
        final type = m['type']?.toString() ?? '';
        final dose = (m['dose']?.toString().isNotEmpty == true)
            ? ' · ${m['dose']}'
            : '';
        final qty = m['quantity'] ?? 0;
        final price = _parsePrice(m['price']);
        final expiry = _formatDate(m['expiryDate']?.toString());

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border)),
              child: _typeIconWidget(type, size: 13),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text('$name ($type$dose) × $qty',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _textDark)),
              const SizedBox(height: 2),
              Row(children: [
                _miniChip('PKR ${_fmtPrice(price)}', _green600),
                const SizedBox(width: 6),
                _miniChip(expiry, _textMid),
              ]),
            ])),
          ]),
        );
      }).toList(),
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────
  Widget _hCell(double w, String label, String? sort) {
    final active = _sortField == sort;
    return InkWell(
      onTap: sort != null ? () => _sort(sort) : null,
      child: Container(
        width: w,
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(children: [
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.3)),
          if (active) ...[
            const SizedBox(width: 3),
            Icon(
                _isAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
                color: Colors.white),
          ],
        ]),
      ),
    );
  }

  Widget _typePill(String type) {
    final color = _typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _typeIconWidget(type, size: 11, color: color),
        const SizedBox(width: 5),
        Flexible(
            child: Text(type,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _priceBadge(double price) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3FCF4),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: const Color(0xFF81C784).withOpacity(0.6)),
        ),
        child: Text('PKR ${_fmtPrice(price)}',
            style: const TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w800,
                fontSize: 12)),
      );

  Widget _dCell(double w, Widget child) => Container(
      width: w,
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: child);

  Widget _qtyBadge(int qty, bool low) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (low ? _red : _green600).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (low ? _red : _green600).withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (low) ...[
            const Icon(Icons.warning_rounded, size: 11, color: _red),
            const SizedBox(width: 3)
          ],
          Text(qty.toString(),
              style: TextStyle(
                  color: low ? _red : _green600,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ]),
      );

  Widget _expBadge(String text, bool soon) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (soon) ...[
          const Icon(Icons.access_time_rounded,
              size: 12, color: _red),
          const SizedBox(width: 4)
        ],
        Text(text,
            style: TextStyle(
                color: soon ? _red : _textMid,
                fontWeight:
                    soon ? FontWeight.bold : FontWeight.normal,
                fontSize: 12)),
      ]);

  Widget _statusLabel(
      {required bool lowStock, required bool expSoon, bool isTable = false}) {
    String label = '';
    IconData icon = Icons.warning_rounded;
    if (lowStock && expSoon) {
      label = 'CRITICAL: LOW STOCK & NEAR EXPIRY';
    } else if (lowStock) {
      label = 'WARNING: LOW STOCK';
      icon = Icons.inventory_2_rounded;
    } else if (expSoon) {
      label = 'ALERT: NEAR EXPIRY';
      icon = Icons.access_time_rounded;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isTable ? 8 : 12, vertical: isTable ? 3 : 5),
      decoration: BoxDecoration(
        color: _red, // Solid vibrant red
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: _red.withOpacity(0.35),
            blurRadius: 5,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: isTable ? 10 : 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: isTable ? 8 : 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(String text, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );

  Widget _miniChip(String text, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _emptyState(IconData icon, String msg) => Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 14),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textLight, fontSize: 15)),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Edit Medicine Bottom Sheet (manager direct edit)
// ═══════════════════════════════════════════════════════════════════════════════
class _EditMedicineSheet extends StatefulWidget {
  final String branchId;
  final List<String> docIds;
  final Map<String, dynamic> initial;
  final List<String> medicineTypes;
  final String Function(String?) formatDate;

  const _EditMedicineSheet({
    required this.branchId,
    required this.docIds,
    required this.initial,
    required this.medicineTypes,
    required this.formatDate,
  });

  @override
  State<_EditMedicineSheet> createState() => _EditMedicineSheetState();
}

class _EditMedicineSheetState extends State<_EditMedicineSheet> {
  static const _teal = Color(0xFF00695C);
  static const _tealDark = Color(0xFF004D40);
  static const _green50 = Color(0xFFE8F5E9);
  static const _green600 = Color(0xFF2E7D32);
  static const _red = Color(0xFFC62828);
  static const _border = Color(0xFFB2DFDB);
  static const _textDark = Color(0xFF1B2631);
  static const _textLight = Color(0xFF718096);

  late final TextEditingController _nameCtrl;
  late final TextEditingController _doseCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _expiryCtrl;
  late String _selectedType;

  bool _saving = false;
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

  @override
  void initState() {
    super.initState();
    final initialPrice = _parsePrice(widget.initial['price']);
    // Label says "Formula" but field holds name
    _nameCtrl =
        TextEditingController(text: widget.initial['name']?.toString() ?? '');
    _doseCtrl =
        TextEditingController(text: widget.initial['dose']?.toString() ?? '');
    _qtyCtrl = TextEditingController(
        text: '${widget.initial['quantity'] ?? 0}');
    _priceCtrl =
        TextEditingController(text: _fmtPrice(initialPrice));
    _expiryCtrl = TextEditingController(
        text: widget.initial['expiryDate']?.toString() ?? '');
    _selectedType = widget.medicineTypes
            .contains(widget.initial['type'])
        ? widget.initial['type'].toString()
        : widget.medicineTypes.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final col = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory');

      final batch = FirebaseFirestore.instance.batch();
      final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
      final price = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
      final perDoc = (qty / widget.docIds.length).floor();
      final remainder = qty - perDoc * widget.docIds.length;

      for (int i = 0; i < widget.docIds.length; i++) {
        final ref = col.doc(widget.docIds[i]);
        batch.update(ref, {
          'formula': '',
          'name': _nameCtrl.text.trim(),
          'name_lower': _nameCtrl.text.trim().toLowerCase(),
          'type': _selectedType,
          'dose': _doseCtrl.text.trim(),
          'quantity': perDoc + (i == 0 ? remainder : 0),
          'price': price,
          'expiryDate': _expiryCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Medicine updated successfully'),
          ]),
          backgroundColor: _green600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child:
          Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_rounded,
                color: _teal, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Edit Medicine',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _tealDark)),
              Text('${widget.docIds.length} batch doc(s) will be updated',
                  style: const TextStyle(
                      fontSize: 11, color: _textLight)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _textLight),
            onPressed: () => Navigator.pop(context),
          ),
        ]),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(children: [
              // "Formula" label
              _field(
                controller: _nameCtrl,
                label: 'Formula',
                icon: Icons.medication_rounded,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Type',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textLight)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _green50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedType,
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: Colors.white,
                    style: const TextStyle(
                        color: _textDark, fontSize: 14),
                    icon: const Icon(Icons.expand_more_rounded,
                        color: _teal),
                    items: widget.medicineTypes
                        .map((t) => DropdownMenuItem(
                            value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(
                        () => _selectedType = v ?? _selectedType),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _field(
                controller: _doseCtrl,
                label: 'Dose (e.g. 500mg, 5ml)',
                icon: Icons.vaccines_rounded,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _field(
                  controller: _qtyCtrl,
                  label: 'Total Quantity',
                  icon: Icons.numbers_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _field(
                  controller: _priceCtrl,
                  label: 'Price (PKR)',
                  icon: Icons.payments_rounded,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v.trim()) == null)
                      return 'Invalid price';
                    return null;
                  },
                )),
              ]),
              const SizedBox(height: 12),
              _field(
                controller: _expiryCtrl,
                label: 'Expiry (MM-YYYY or DD-MM-YYYY)',
                icon: Icons.calendar_today_rounded,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded,
                          color: Colors.white, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save Changes',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    disabledBackgroundColor:
                        _teal.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                ),
              ),
            ]),
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
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
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
          inputFormatters: inputFormatters,
          validator: validator,
          cursorColor: _teal,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 17, color: _teal),
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
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _red)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 13),
          ),
        ),
      ]);
}

class _Col {
  final String label;
  final double w;
  final String? sort;
  const _Col(this.label, this.w, this.sort);
}