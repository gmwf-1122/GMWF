// lib/pages/inventory.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'dispensar_screen.dart';
import 'inventory_update.dart';
import 'inventory_adjustment.dart';

class InventoryPage extends StatefulWidget {
  final String branchId;
  final bool   isAdmin;
  final bool   isDispenser;

  const InventoryPage({
    super.key,
    required this.branchId,
    this.isAdmin = false,
    this.isDispenser = false,
  });

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> with TickerProviderStateMixin {
  // ── Palette ───────────────────────────────────────────────────────────────
  static const _teal      = Color(0xFF00695C);
  static const _tealDark  = Color(0xFF004D40);
  static const _bg        = Color(0xFFF1F8F6);
  static const _white     = Colors.white;
  static const _green50   = Color(0xFFE8F5E9);
  static const _green100  = Color(0xFFC8E6C9);
  static const _green600  = Color(0xFF2E7D32);
  static const _red       = Color(0xFFC62828);
  static const _orange    = Color(0xFFBF360C);
  static const _amber     = Color(0xFFF57F17);
  static const _blue      = Color(0xFF1565C0);
  static const _purple    = Color(0xFF6A1B9A);
  static const _indigo    = Color(0xFF283593);
  static const _brown     = Color(0xFF4E342E);
  static const _textDark  = Color(0xFF1B2631);
  static const _textMid   = Color(0xFF4A5568);
  static const _textLight = Color(0xFF718096);
  static const _border    = Color(0xFFB2DFDB);
  static const _shadow    = Color(0x1800695C);

  // Inventory-only request types — anything outside this set is irrelevant to
  // the inventory screen and is hidden from both Pending and History tabs.
  static const _inventoryTypes = {'add_stock', 'edit_medicine', 'delete_medicine'};

  // Per-type badge color
  static Color _typeColor(String t) => switch (t) {
    'Tablet'       => const Color(0xFF1565C0),
    'Capsule'      => const Color(0xFF6A1B9A),
    'Syrup'        => const Color(0xFFF57F17),
    'Injection'    => const Color(0xFFC62828),
    'Drip'         => const Color(0xFF00695C),
    'Drip Set'     => const Color(0xFF00838F),
    'Syringe'      => const Color(0xFFAD1457),
    'Big Bottle'   => const Color(0xFF4E342E),
    'Nebulization' => const Color(0xFF283593),
    _              => const Color(0xFF37474F),
  };

  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _filterType  = 'All';
  String _filterBatch = 'All Batches';
  String _sortField   = 'name';
  bool   _isAscending = true;
  int    _page        = 0;
  final  int _perPage = 15;

  List<String> _batchKeys = ['All Batches'];

  final List<String> _types = [
    'All','Tablet','Capsule','Syrup','Injection',
    'Drip','Drip Set','Syringe','Big Bottle','Nebulization','Others',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tabCtrl.dispose(); _searchCtrl.dispose(); super.dispose(); }

  int _asInt(dynamic v) => v is int ? v
      : v is double ? v.toInt()
      : v is String ? (int.tryParse(v) ?? 0) : 0;

  Widget _typeIconWidget(String t, {double size = 14, Color? color}) {
    final c = color ?? _teal;
    final icon = switch (t) {
      'Tablet'       => FontAwesomeIcons.tablets,
      'Capsule'      => FontAwesomeIcons.capsules,
      'Syrup'        => FontAwesomeIcons.bottleDroplet,
      'Injection'    => FontAwesomeIcons.syringe,
      'Drip'         => FontAwesomeIcons.bottleDroplet,
      'Drip Set'     => FontAwesomeIcons.kitMedical,
      'Syringe'      => FontAwesomeIcons.syringe,
      'Big Bottle'   => FontAwesomeIcons.prescriptionBottleAlt,
      'Nebulization' => FontAwesomeIcons.wind,
      _              => FontAwesomeIcons.pills,
    };
    return Icon(icon, size: size, color: c);
  }

  void _sort(String field) {
    if (field == 'type') return;
    setState(() {
      if (_sortField == field) _isAscending = !_isAscending;
      else { _sortField = field; _isAscending = true; }
      _page = 0;
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    if (raw.length == 7 && raw[2] == '-') return raw;
    final p = raw.split('-');
    if (p.length != 3) return raw;
    return '${p[0].padLeft(2,'0')}-${p[1].padLeft(2,'0')}-${p[2]}';
  }

  bool _isExpiringSoon(String? exp) {
    if (exp == null || exp.isEmpty) return false;
    try {
      final p = exp.split('-');
      DateTime date;
      if (p.length == 2) date = DateTime(int.parse(p[1]), int.parse(p[0]) + 1, 0);
      else if (p.length == 3) date = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      else return false;
      final diff = date.difference(DateTime.now()).inDays;
      return diff <= 30 && diff >= 0;
    } catch (_) { return false; }
  }

  DateTime _parseExpiry(String? s) {
    if (s == null || s.isEmpty) return DateTime(3000);
    try {
      final p = s.split('-');
      if (p.length == 2) return DateTime(int.parse(p[1]), int.parse(p[0]), 15);
      if (p.length == 3) return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {}
    return DateTime(3000);
  }

  List<Map<String, dynamic>> _groupByBatch(List<QueryDocumentSnapshot> docs) {
    final Map<String, Map<String, dynamic>> map = {};
    for (final doc in docs) {
      final data   = doc.data() as Map<String, dynamic>;
      final name   = (data['name'] ?? '').toString().trim();
      final type   = data['type'] ?? '';
      final dose   = (data['dose'] ?? '').toString().trim();
      final expiry = data['expiryDate']?.toString().trim() ?? '';
      final qty    = _asInt(data['quantity']);
      final price  = _asInt(data['price']);

      String monthYear = '';
      if (expiry.length == 10 && expiry[2] == '-' && expiry[5] == '-') {
        monthYear = expiry.substring(3);
      } else monthYear = expiry;

      String doseDisplay = dose;
      if (type == 'Nebulization' && dose.isEmpty) doseDisplay = 'per session';

      final key = '$name|$type|$dose|$monthYear';
      if (map.containsKey(key)) {
        map[key]!['quantity'] += qty;
      } else {
        map[key] = {
          'name': name, 'type': type, 'dose': doseDisplay,
          'expiryDate': monthYear, 'quantity': qty, 'price': price, 'batchKey': key,
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

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: _buildAppBar(),
    floatingActionButton: widget.isAdmin ? null : FloatingActionButton.extended(
      backgroundColor: _teal,
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => InventoryUpdatePage(branchId: widget.branchId))),
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: const Text('Request Stock',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ),
    body: TabBarView(
      controller: _tabCtrl,
      children: [_stockTab(), _pendingTab(), _historyTab()],
    ),
  );

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: _teal,
    elevation: 4,
    shadowColor: _shadow,
    // ── Back button: shown for ALL roles ─────────────────────────────────
    // Dispenser   → pushReplacement to DispensarScreen
    // All others  → Navigator.pop() (returns to their sidebar/parent screen)
    automaticallyImplyLeading: false,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
      onPressed: () {
        if (widget.isDispenser) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => DispensarScreen(branchId: widget.branchId)),
          );
        } else {
          Navigator.pop(context);
        }
      },
    ),
    title: Row(children: [
      const Icon(FontAwesomeIcons.pills, color: Colors.white70, size: 16),
      const SizedBox(width: 10),
      const Text('Inventory',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
    ]),
    // ── Adjust button: hidden for dispensers, shown for all other roles ───
    actions: widget.isDispenser ? [] : [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: ElevatedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => InventoryAdjustmentPage(branchId: widget.branchId))),
          icon: const Icon(FontAwesomeIcons.sliders, size: 14, color: Colors.white),
          label: const Text('Adjust', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFBF360C),
            foregroundColor: Colors.white,
            elevation: 3,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          ),
        ),
      ),
    ],
    bottom: TabBar(
      controller: _tabCtrl,
      indicatorColor: Colors.white,
      indicatorWeight: 3,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      tabs: const [
        Tab(icon: Icon(Icons.inventory_2_rounded, size: 18), text: 'Stock'),
        Tab(icon: Icon(Icons.pending_actions_rounded, size: 18), text: 'Pending'),
        Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'History'),
      ],
    ),
  );

  // ── Stock Tab ─────────────────────────────────────────────────────────────
  Widget _stockTab() => Column(children: [
    Container(
      color: _white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(children: [
        TextField(
          controller: _searchCtrl, cursorColor: _teal,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: _teal, size: 18),
            hintText: 'Search medicine...',
            hintStyle: const TextStyle(color: _textLight, fontSize: 14),
            filled: true, fillColor: _green50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          ),
          onChanged: (_) => setState(() => _page = 0),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _filterDropdown(_filterType, _types,
              (v) => setState(() { _filterType = v ?? 'All'; _page = 0; }))),
          const SizedBox(width: 10),
          Expanded(child: _filterDropdown(_filterBatch, _batchKeys,
              (v) => setState(() { _filterBatch = v ?? 'All Batches'; _page = 0; }),
              display: (k) => k == 'All Batches' ? k : 'Batch: $k')),
        ]),
      ]),
    ),
    Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('branches').doc(widget.branchId).collection('inventory').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _teal));
          }
          if (snap.hasError) return Center(
              child: Text('Error: ${snap.error}', style: const TextStyle(color: _red)));

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.inventory_2_outlined, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 14),
            Text(widget.isAdmin ? 'No medicines in stock.' : 'No medicines in stock.\nTap + to request.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textLight, fontSize: 15)),
          ]));

          final batches     = _groupByBatch(docs);
          var   preFiltered = batches.where((b) {
            final name = b['name'].toString().toLowerCase();
            final type = b['type'];
            return name.contains(_searchCtrl.text.toLowerCase()) &&
                (_filterType == 'All' || type == _filterType);
          }).toList();

          _updateBatchKeys(preFiltered);

          var filtered = _filterBatch == 'All Batches'
              ? preFiltered
              : preFiltered.where((b) => b['expiryDate'] == _filterBatch).toList();

          filtered.sort((a, b) {
            int cmp = switch (_sortField) {
              'name'     => a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase()),
              'dose'     => (a['dose'] ?? '').toString().compareTo((b['dose'] ?? '').toString()),
              'quantity' => (a['quantity'] as int).compareTo(b['quantity'] as int),
              'price'    => (a['price'] as int).compareTo(b['price'] as int),
              'expiry'   => _parseExpiry(a['expiryDate']).compareTo(_parseExpiry(b['expiryDate'])),
              _          => 0,
            };
            return _isAscending ? cmp : -cmp;
          });

          final totalPages = (filtered.length / _perPage).ceil().clamp(1, 9999);
          final safePage   = _page.clamp(0, totalPages - 1);
          final start      = safePage * _perPage;
          final end        = (start + _perPage).clamp(0, filtered.length);
          final pageData   = start < end ? filtered.sublist(start, end) : <Map<String, dynamic>>[];

          return Column(children: [
            Expanded(child: LayoutBuilder(builder: (ctx, constraints) {
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

  Widget _filterDropdown(String value, List<String> items, ValueChanged<String?> onChange,
      {String Function(String)? display}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _green50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: DropdownButton<String>(
          value: value, isExpanded: true, underline: const SizedBox(),
          dropdownColor: _white,
          style: const TextStyle(color: _textDark, fontSize: 13),
          icon: const Icon(Icons.expand_more_rounded, color: _teal, size: 18),
          items: items.map((t) => DropdownMenuItem<String>(value: t,
              child: Text(display != null ? display(t) : t,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textDark, fontSize: 13)))).toList(),
          onChanged: onChange,
        ),
      );

  Widget _stockTable(List<Map<String, dynamic>> data, int start, double w) {
    final cols = [
      _Col('#',      w * 0.05, null),
      _Col('Name',   w * 0.22, 'name'),
      _Col('Type',   w * 0.14, null),
      _Col('Dose',   w * 0.17, 'dose'),
      _Col('Qty',    w * 0.09, 'quantity'),
      _Col('Price',  w * 0.13, 'price'),
      _Col('Expiry', w * 0.20, 'expiry'),
    ];
    return Column(children: [
      Container(
        decoration: const BoxDecoration(
          color: Color(0xFF004D40),
          border: Border(bottom: BorderSide(color: Color(0xFF00695C), width: 2)),
        ),
        child: Row(children: cols.map((c) => _hCell(c.w, c.label, c.sort)).toList()),
      ),
      Expanded(child: ListView.builder(
        itemCount: data.length,
        itemBuilder: (ctx, i) {
          final b        = data[i];
          final qty      = b['quantity'] as int;
          final type     = b['type'] as String;
          final lowStock = type == 'Big Bottle' ? qty < 3 : qty < 10;
          final expSoon  = _isExpiringSoon(b['expiryDate'] as String?);
          final expText  = _formatDate(b['expiryDate'] as String?);
          final rowColor = i % 2 == 0 ? _white : const Color(0xFFF0FAF4);
          return Container(
            decoration: BoxDecoration(
              color: rowColor,
              border: const Border(bottom: BorderSide(color: Color(0xFFDCEDDE), width: 0.8)),
            ),
            child: Row(children: [
              _dCell(cols[0].w, Text('${start+i+1}',
                  style: const TextStyle(color: _textLight, fontSize: 12))),
              _dCell(cols[1].w, Text(b['name'],
                  style: const TextStyle(color: _textDark, fontWeight: FontWeight.w700, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              _dCell(cols[2].w, _typePill(type)),
              _dCell(cols[3].w, Text(b['dose'] ?? '—',
                  style: const TextStyle(color: _textMid, fontSize: 12), overflow: TextOverflow.ellipsis)),
              _dCell(cols[4].w, _qtyBadge(qty, lowStock)),
              _dCell(cols[5].w, _priceBadge(b['price'] as int)),
              _dCell(cols[6].w, _expBadge(expText, expSoon)),
            ]),
          );
        },
      )),
    ]);
  }

  Widget _stockCards(List<Map<String, dynamic>> data, int start) =>
      ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: data.length,
        itemBuilder: (ctx, i) {
          final b        = data[i];
          final qty      = b['quantity'] as int;
          final type     = b['type'] as String;
          final lowStock = type == 'Big Bottle' ? qty < 3 : qty < 10;
          final expSoon  = _isExpiringSoon(b['expiryDate'] as String?);
          final expText  = _formatDate(b['expiryDate'] as String?);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: lowStock ? _red.withOpacity(0.25) : _green100),
              boxShadow: [BoxShadow(color: _shadow, blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _green50, borderRadius: BorderRadius.circular(8)),
                  child: _typeIconWidget(type, size: 13),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('${start+i+1}. ${b['name']}',
                    style: const TextStyle(color: _textDark, fontWeight: FontWeight.bold, fontSize: 14))),
                _qtyBadge(qty, lowStock),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _typePill(type),
                if ((b['dose'] ?? '').toString().isNotEmpty) _infoBadge(b['dose'].toString(), _textMid),
                _priceBadge(b['price'] as int),
                _expBadge(expText, expSoon),
              ]),
            ]),
          );
        },
      );

  Widget _pagination(int page, int total) => Container(
    color: _white,
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _pgBtn(Icons.first_page_rounded, page > 0, () => setState(() => _page = 0)),
      _pgBtn(Icons.chevron_left_rounded, page > 0, () => setState(() => _page--)),
      const SizedBox(width: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: _green50, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _green100),
        ),
        child: Text('${page+1} / $total',
            style: const TextStyle(color: _teal, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
      const SizedBox(width: 12),
      _pgBtn(Icons.chevron_right_rounded, page+1 < total, () => setState(() => _page++)),
      _pgBtn(Icons.last_page_rounded, page+1 < total, () => setState(() => _page = total-1)),
    ]),
  );

  Widget _pgBtn(IconData icon, bool enabled, VoidCallback fn) => IconButton(
    icon: Icon(icon, size: 20, color: enabled ? _teal : Colors.grey[300]),
    onPressed: enabled ? fn : null,
  );

  // ── Pending Tab ───────────────────────────────────────────────────────────
  // Shows only inventory-related requests (add_stock, edit_medicine, delete_medicine).
  // Latest first.
  Widget _pendingTab() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('branches').doc(widget.branchId)
        .collection('edit_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots(),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: _teal));
      }
      var docs = snap.data?.docs ?? [];

      // Keep only inventory-related request types
      docs = docs.where((d) {
        final t = (d.data() as Map<String, dynamic>)['requestType']?.toString() ?? '';
        return _inventoryTypes.contains(t);
      }).toList();

      if (docs.isEmpty) return _emptyState(Icons.pending_actions_rounded, 'No pending requests');

      // Latest first
      docs.sort((a, b) {
        final ta = (a.data() as Map<String,dynamic>)['requestedAt'] as Timestamp?;
        final tb = (b.data() as Map<String,dynamic>)['requestedAt'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) =>
            _requestCard(docs[i].data() as Map<String, dynamic>, 'pending'),
      );
    },
  );

  // ── History Tab ───────────────────────────────────────────────────────────
  Widget _historyTab() => DefaultTabController(
    length: 2,
    child: Column(children: [
      Container(
        color: _white,
        child: const TabBar(
          indicatorColor: _teal,
          labelColor: _teal,
          unselectedLabelColor: _textLight,
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
          tabs: [
            Tab(icon: Icon(Icons.check_circle_rounded, size: 16), text: 'Approved'),
            Tab(icon: Icon(Icons.cancel_rounded, size: 16), text: 'Rejected'),
          ],
        ),
      ),
      Expanded(child: TabBarView(
          children: [_historyList('approved'), _historyList('rejected')])),
    ]),
  );

  // Shows only inventory-related requests. Latest first.
  Widget _historyList(String status) => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('branches').doc(widget.branchId)
        .collection('edit_requests')
        .where('status', isEqualTo: status)
        .snapshots(),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: _teal));
      }
      var docs = snap.data?.docs ?? [];

      // Keep only inventory-related request types
      docs = docs.where((d) {
        final t = (d.data() as Map<String, dynamic>)['requestType']?.toString() ?? '';
        return _inventoryTypes.contains(t);
      }).toList();

      if (docs.isEmpty) return _emptyState(
          status == 'approved' ? Icons.check_circle_outline : Icons.cancel_outlined,
          'No $status requests');

      // Latest first
      docs.sort((a, b) {
        final ta = (a.data() as Map<String,dynamic>)['requestedAt'] as Timestamp?;
        final tb = (b.data() as Map<String,dynamic>)['requestedAt'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) =>
            _requestCard(docs[i].data() as Map<String, dynamic>, status),
      );
    },
  );

  // ── Rich request card (mirrors request.dart layout) ───────────────────────
  Widget _requestCard(Map<String, dynamic> data, String status) {
    final requestType   = data['requestType']?.toString() ?? '';
    final reason        = data['reason']?.toString() ?? '';
    final ts            = data['requestedAt'] as Timestamp?;
    final cachedName    = (data['requesterName']?.toString() ?? '').trim();
    final requesterId   = (data['requestedBy']?.toString() ??
                           data['requester']?.toString() ?? '').trim();

    // Resolve requester name: use cached value or look up from Firestore
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
                .then((s) => s.data()?['username']?.toString() ?? 'User')
                .timeout(const Duration(seconds: 5), onTimeout: () => 'User')
                .catchError((_) => 'User');

    // Badge colours per request type
    Color badgeBg = switch (requestType) {
      'add_stock'       => _green50,
      'edit_medicine'   => const Color(0xFFF3E5F5),
      'delete_medicine' => const Color(0xFFFFEBEE),
      _                 => Colors.grey.shade100,
    };
    Color badgeFg = switch (requestType) {
      'add_stock'       => _green600,
      'edit_medicine'   => _purple,
      'delete_medicine' => _red,
      _                 => _textMid,
    };
    String typeLabel = switch (requestType) {
      'add_stock'       => 'ADD STOCK',
      'edit_medicine'   => 'EDIT MEDICINE',
      'delete_medicine' => 'DELETE MEDICINE',
      _                 => requestType.replaceAll('_', ' ').toUpperCase(),
    };

    Color statusColor = switch (status) {
      'approved' => _green600,
      'rejected' => _red,
      _          => _orange,
    };
    IconData statusIcon = switch (status) {
      'approved' => Icons.check_circle_rounded,
      'rejected' => Icons.cancel_rounded,
      _          => Icons.pending_rounded,
    };

    // Items: prefer draftItems for pending, otherwise items
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header row ─────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Text(
                switch (requestType) {
                  'add_stock'       => 'Stock Request',
                  'edit_medicine'   => 'Edit Medicine Request',
                  'delete_medicine' => 'Delete Medicine Request',
                  _                 => 'Inventory Request',
                },
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _tealDark),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeBg, borderRadius: BorderRadius.circular(20)),
              child: Text(typeLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeFg)),
            ),
          ]),
          const SizedBox(height: 10),

          // ── Requester name ──────────────────────────────────────────────
          FutureBuilder<String>(
            future: nameFuture,
            builder: (_, snap) => Row(children: [
              Icon(Icons.person_rounded, size: 15, color: _teal),
              const SizedBox(width: 6),
              Text('By: ${snap.data ?? '…'}',
                  style: const TextStyle(fontSize: 13, color: _textDark)),
            ]),
          ),
          const SizedBox(height: 4),

          // ── Timestamp ───────────────────────────────────────────────────
          if (ts != null)
            Row(children: [
              Icon(Icons.access_time_rounded, size: 14, color: _textLight),
              const SizedBox(width: 6),
              Text(
                DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()),
                style: const TextStyle(fontSize: 12, color: _textLight),
              ),
            ]),
          const SizedBox(height: 12),

          // ── Items list ──────────────────────────────────────────────────
          if (items.isNotEmpty) _buildItemsList(items),

          // ── Reason ─────────────────────────────────────────────────────
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
                  Icon(Icons.comment_rounded, size: 14, color: _textLight),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Reason: $reason',
                      style: const TextStyle(fontSize: 13, color: _textDark))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Status chip (approved / rejected) ──────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Items list inside request card ────────────────────────────────────────
  Widget _buildItemsList(List<Map<String, dynamic>> items) {
    final isWide = MediaQuery.of(context).size.width > 600;
    return isWide ? _itemsTable(items) : _itemsCompact(items);
  }

  Widget _itemsTable(List<Map<String, dynamic>> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(_tealDark.withOpacity(0.07)),
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('Name',   style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Type',   style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Dose',   style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Qty',    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Price',  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Expiry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        ],
        rows: items.map((m) => DataRow(cells: [
          DataCell(Text(m['name']?.toString() ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
          DataCell(Row(children: [
            _typeIconWidget(m['type'] ?? '', size: 12, color: _teal),
            const SizedBox(width: 5),
            Text(m['type']?.toString() ?? '—',
                style: const TextStyle(fontSize: 12)),
          ])),
          DataCell(Text(m['dose']?.toString() ?? '—',
              style: const TextStyle(fontSize: 12))),
          DataCell(Text('${m['quantity'] ?? 0}',
              style: const TextStyle(fontSize: 12))),
          DataCell(Text('PKR ${m['price'] ?? 0}',
              style: const TextStyle(fontSize: 12, color: _green600, fontWeight: FontWeight.w600))),
          DataCell(Text(_formatDate(m['expiryDate']?.toString()),
              style: const TextStyle(fontSize: 12))),
        ])).toList(),
      ),
    );
  }

  Widget _itemsCompact(List<Map<String, dynamic>> items) {
    return Column(
      children: items.map((m) {
        final name   = m['name']?.toString() ?? '—';
        final type   = m['type']?.toString() ?? '';
        final dose   = (m['dose']?.toString().isNotEmpty == true) ? ' · ${m['dose']}' : '';
        final qty    = m['quantity'] ?? 0;
        final price  = m['price'] ?? 0;
        final expiry = _formatDate(m['expiryDate']?.toString());
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _white, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border)),
              child: _typeIconWidget(type, size: 13),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$name ($type$dose) × $qty',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _textDark)),
              const SizedBox(height: 2),
              Row(children: [
                _miniChip('PKR $price', _green600),
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
        width: w, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(children: [
          Text(label, style: TextStyle(
              color: active ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.3)),
          if (active) ...[
            const SizedBox(width: 3),
            Icon(_isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 12, color: Colors.white),
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
        Flexible(child: Text(type,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _priceBadge(int price) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF3FCF4),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xFF81C784).withOpacity(0.6)),
    ),
    child: Text('PKR $price', style: const TextStyle(
        color: Color(0xFF2E7D32), fontWeight: FontWeight.w800, fontSize: 12)),
  );

  Widget _dCell(double w, Widget child) => Container(
    width: w, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: child);

  Widget _qtyBadge(int qty, bool low) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: (low ? _red : _green600).withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: (low ? _red : _green600).withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (low) ...[const Icon(Icons.warning_rounded, size: 11, color: _red), const SizedBox(width: 3)],
      Text(qty.toString(), style: TextStyle(
          color: low ? _red : _green600, fontWeight: FontWeight.bold, fontSize: 12)),
    ]),
  );

  Widget _expBadge(String text, bool soon) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (soon) ...[const Icon(Icons.access_time_rounded, size: 12, color: _red), const SizedBox(width: 4)],
    Text(text, style: TextStyle(
        color: soon ? _red : _textMid,
        fontWeight: soon ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
  ]);

  Widget _infoBadge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _miniChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _emptyState(IconData icon, String msg) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 72, color: Colors.grey[300]),
      const SizedBox(height: 14),
      Text(msg, style: const TextStyle(color: _textLight, fontSize: 15)),
    ]),
  );
}

class _Col {
  final String label; final double w; final String? sort;
  const _Col(this.label, this.w, this.sort);
}