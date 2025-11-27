// lib/pages/inventory.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dispensar_screen.dart';
import 'inventory_update.dart';

class InventoryPage extends StatefulWidget {
  final String branchId;
  const InventoryPage({super.key, required this.branchId});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterType = "All";
  String _filterBatch = "All Batches";
  String _sortField = "name";
  bool _isAscending = true;
  int _page = 0;
  final int _perPage = 10;

  final List<String> _types = [
    "All",
    "Tablet",
    "Capsule",
    "Syrup",
    "Injection",
    "Drip",
    "Drip Set",
    "Syringe",
    "Big Bottle",
    "Others",
  ];

  List<String> _batchKeys = ['All Batches'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  int _asInt(dynamic v) => v is int
      ? v
      : v is double
          ? v.toInt()
          : v is String
              ? int.tryParse(v) ?? 0
              : 0;

  Widget _typeIcon(String t, {double size = 16, Color color = Colors.white}) {
    return switch (t) {
      'Tablet' => Icon(FontAwesomeIcons.tablets, size: size, color: color),
      'Capsule' => Icon(FontAwesomeIcons.capsules, size: size, color: color),
      'Syrup' => Icon(FontAwesomeIcons.bottleDroplet, size: size, color: color),
      'Injection' => Icon(FontAwesomeIcons.syringe, size: size, color: color),
      'Drip' => Icon(FontAwesomeIcons.bottleDroplet, size: size, color: color),
      'Drip Set' => Icon(FontAwesomeIcons.kitMedical, size: size, color: color),
      'Syringe' => Icon(FontAwesomeIcons.syringe, size: size, color: color),
      'Big Bottle' =>
        Icon(FontAwesomeIcons.prescriptionBottleAlt, size: size, color: color),
      'Others' => Icon(FontAwesomeIcons.pills, size: size, color: color),
      _ => Icon(FontAwesomeIcons.circleQuestion, size: size, color: color),
    };
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

  void _openAddForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => InventoryUpdatePage(branchId: widget.branchId)),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}-${parts[2]}';
  }

  // SAFE EXPIRY CHECK – NO CRASH
  bool _isExpiringSoon(String? expiry) {
    if (expiry == null || expiry.isEmpty) return false;
    try {
      final parts = expiry.split('-');
      if (parts.length != 3) return false;
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day == null || month == null || year == null) return false;
      final date = DateTime(year, month, day);
      final diff = date.difference(DateTime.now()).inDays;
      return diff <= 30 && diff >= 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final tableW = w - 32;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(FontAwesomeIcons.pills, color: Colors.orange),
            SizedBox(width: 10),
            Text('Inventory',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => DispensarScreen(branchId: widget.branchId)),
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.orange,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Stock', icon: Icon(Icons.inventory)),
            Tab(text: 'Pending', icon: Icon(Icons.pending_actions)),
            Tab(text: 'History', icon: Icon(Icons.history)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        onPressed: _openAddForm,
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'Request New Medicine',
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _stockTab(tableW),
          _pendingTab(),
          _historyTab(),
        ],
      ),
    );
  }

  // GROUP BY BATCH
  List<Map<String, dynamic>> _groupByBatch(List<QueryDocumentSnapshot> docs) {
    final Map<String, Map<String, dynamic>> map = {};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().trim();
      final type = data['type'] ?? '';
      final dose = (data['dose'] ?? '').toString().trim();
      final expiry = data['expiryDate']?.toString().trim() ?? '';
      final qty = _asInt(data['quantity']);
      final price = _asInt(data['price']);
      final key = '$name|$type|$dose|$expiry';

      if (map.containsKey(key)) {
        map[key]!['quantity'] += qty;
      } else {
        map[key] = {
          'name': name,
          'type': type,
          'dose': dose,
          'expiryDate': expiry,
          'quantity': qty,
          'price': price,
          'batchKey': key,
        };
      }
    }
    return map.values.toList();
  }

  // STOCK TAB – NO CRASH
  Widget _stockTab(double tableW) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              bool isWide = constraints.maxWidth > 600;
              return Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
                      hintText: 'Search medicine...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF2D2D2D),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) => setState(() => _page = 0),
                  ),
                  const SizedBox(height: 8),
                  if (isWide)
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                                color: const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(12)),
                            child: DropdownButton<String>(
                              value: _filterType,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: const Color(0xFF2D2D2D),
                              style: const TextStyle(color: Colors.white),
                              items: _types
                                  .map((t) => DropdownMenuItem<String>(
                                      value: t, child: Text(t)))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _filterType = v ?? 'All';
                                _page = 0;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                                color: const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(12)),
                            child: DropdownButton<String>(
                              value: _filterBatch,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: const Color(0xFF2D2D2D),
                              style: const TextStyle(color: Colors.white),
                              items: _batchKeys
                                  .map((k) => DropdownMenuItem<String>(
                                      value: k,
                                      child: Text(
                                          k == 'All Batches'
                                              ? k
                                              : 'Batch: ${k.split('|').last}',
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _filterBatch = v ?? 'All Batches';
                                _page = 0;
                              }),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(12)),
                          child: DropdownButton<String>(
                            value: _filterType,
                            isExpanded: true,
                            underline: const SizedBox(),
                            dropdownColor: const Color(0xFF2D2D2D),
                            style: const TextStyle(color: Colors.white),
                            items: _types
                                .map((t) => DropdownMenuItem<String>(
                                    value: t, child: Text(t)))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _filterType = v ?? 'All';
                              _page = 0;
                            }),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(12)),
                          child: DropdownButton<String>(
                            value: _filterBatch,
                            isExpanded: true,
                            underline: const SizedBox(),
                            dropdownColor: const Color(0xFF2D2D2D),
                            style: const TextStyle(color: Colors.white),
                            items: _batchKeys
                                .map((k) => DropdownMenuItem<String>(
                                    value: k,
                                    child: Text(
                                        k == 'All Batches'
                                            ? k
                                            : 'Batch: ${k.split('|').last}',
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => setState(() {
                              _filterBatch = v ?? 'All Batches';
                              _page = 0;
                            }),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('inventory')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.orange));
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red)));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No medicines in stock.\nTap + to request.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                );
              }

              final batches = _groupByBatch(docs);

              // Update batch keys
              final newBatchKeys = <String>{'All Batches'}
                ..addAll(batches.map((b) => b['batchKey'] as String));
              final newList = newBatchKeys.toList();

              if (_batchKeys.toSet().difference(newBatchKeys).isNotEmpty ||
                  newBatchKeys.difference(_batchKeys.toSet()).isNotEmpty) {
                setState(() {
                  _batchKeys = newList;
                  if (!_batchKeys.contains(_filterBatch))
                    _filterBatch = 'All Batches';
                });
              }

              var filtered = batches.where((b) {
                final name = b['name'].toString().toLowerCase();
                final type = b['type'];
                return name.contains(_searchCtrl.text.toLowerCase()) &&
                    (_filterType == 'All' || type == _filterType);
              }).toList();

              if (_filterBatch != 'All Batches') {
                filtered = filtered
                    .where((b) => b['batchKey'] == _filterBatch)
                    .toList();
              }

              filtered.sort((a, b) {
                int cmp = 0;
                switch (_sortField) {
                  case 'name':
                    cmp = a['name']
                        .toString()
                        .toLowerCase()
                        .compareTo(b['name'].toString().toLowerCase());
                    break;
                  case 'dose':
                    cmp = (a['dose'] ?? '')
                        .toString()
                        .compareTo((b['dose'] ?? '').toString());
                    break;
                  case 'quantity':
                    cmp =
                        (a['quantity'] as int).compareTo(b['quantity'] as int);
                    break;
                  case 'price':
                    cmp = (a['price'] as int).compareTo(b['price'] as int);
                    break;
                  case 'expiry':
                    DateTime parse(String? s) {
                      if (s == null) return DateTime(3000);
                      try {
                        final p = s.split('-');
                        if (p.length == 3)
                          return DateTime(int.parse(p[2]), int.parse(p[1]),
                              int.parse(p[0]));
                      } catch (_) {}
                      return DateTime(3000);
                    }
                    cmp = parse(a['expiryDate'])
                        .compareTo(parse(b['expiryDate']));
                    break;
                }
                return _isAscending ? cmp : -cmp;
              });

              final totalPages = (filtered.length / _perPage).ceil();
              if (_page >= totalPages)
                _page = totalPages > 0 ? totalPages - 1 : 0;
              final start = _page * _perPage;
              final end = (start + _perPage).clamp(0, filtered.length);
              final pageData = start < end ? filtered.sublist(start, end) : [];

              return LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 600;

                  Widget content;
                  if (isWide) {
                    content = SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: tableW),
                        child: DataTable(
                          headingRowColor: MaterialStateProperty.all(
                              const Color(0xFF2D2D2D)),
                          dataRowColor: MaterialStateProperty.all(
                              const Color(0xFF1E1E1E)),
                          columns: [
                            _sortableHeader('Name', 'name'),
                            const DataColumn(
                                label: Text('Type',
                                    style: TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold))),
                            _sortableHeader('Dose', 'dose'),
                            _sortableHeader('Qty', 'quantity'),
                            _sortableHeader('Price', 'price'),
                            _sortableHeader('Expiry', 'expiry'),
                          ],
                          rows: pageData.map((b) {
                            final qty = b['quantity'] as int;
                            final lowStock = qty < 10;
                            final expiringSoon =
                                _isExpiringSoon(b['expiryDate'] as String?);
                            final expiryText =
                                _formatDate(b['expiryDate'] as String?);

                            return DataRow(cells: [
                              DataCell(Text(b['name'],
                                  style: const TextStyle(color: Colors.white))),
                              DataCell(Row(children: [
                                _typeIcon(b['type']),
                                const SizedBox(width: 6),
                                Text(b['type'],
                                    style:
                                        const TextStyle(color: Colors.white)),
                              ])),
                              DataCell(Text(b['dose'],
                                  style:
                                      const TextStyle(color: Colors.white70))),
                              DataCell(Row(
                                children: [
                                  if (lowStock)
                                    const Icon(Icons.warning,
                                        color: Colors.red, size: 16),
                                  Text(qty.toString(),
                                      style: TextStyle(
                                          color: lowStock
                                              ? Colors.red
                                              : Colors.orange,
                                          fontWeight: lowStock
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
                                ],
                              )),
                              DataCell(Text('PKR ${b['price']}',
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold))),
                              DataCell(Row(
                                children: [
                                  if (expiringSoon)
                                    const Icon(Icons.access_time,
                                        color: Colors.red, size: 16),
                                  Text(expiryText,
                                      style: TextStyle(
                                          color: expiringSoon
                                              ? Colors.red
                                              : Colors.white70,
                                          fontWeight: expiringSoon
                                              ? FontWeight.bold
                                              : FontWeight.normal)),
                                ],
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
                    );
                  } else {
                    content = ListView.builder(
                      itemCount: pageData.length,
                      itemBuilder: (context, index) {
                        final b = pageData[index];
                        final qty = b['quantity'] as int;
                        final lowStock = qty < 10;
                        final expiringSoon =
                            _isExpiringSoon(b['expiryDate'] as String?);
                        final expiryText =
                            _formatDate(b['expiryDate'] as String?);

                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      b['name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (lowStock)
                                      const Icon(Icons.warning,
                                          color: Colors.red, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Qty: $qty',
                                      style: TextStyle(
                                        color: lowStock
                                            ? Colors.red
                                            : Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _typeIcon(b['type']),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Type: ${b['type']}',
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Dose: ${b['dose']}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Price: PKR ${b['price']}',
                                  style: const TextStyle(color: Colors.green),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (expiringSoon)
                                      const Icon(Icons.access_time,
                                          color: Colors.red, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Expiry: $expiryText',
                                      style: TextStyle(
                                        color: expiringSoon
                                            ? Colors.red
                                            : Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }

                  return Column(
                    children: [
                      Expanded(child: content),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                                icon: const Icon(Icons.chevron_left,
                                    color: Colors.white),
                                onPressed: _page > 0
                                    ? () => setState(() => _page--)
                                    : null),
                            const SizedBox(width: 8),
                            Text(
                                'Page ${_page + 1} of ${totalPages.clamp(1, 999)}',
                                style: const TextStyle(color: Colors.white)),
                            const SizedBox(width: 8),
                            IconButton(
                                icon: const Icon(Icons.chevron_right,
                                    color: Colors.white),
                                onPressed: (_page + 1 < totalPages)
                                    ? () => setState(() => _page++)
                                    : null),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // PENDING TAB – NO INDEX NEEDED
  Widget _pendingTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.orange));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
              child: Text('No pending requests',
                  style: TextStyle(color: Colors.white70)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final items =
                (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final time = (data['requestedAt'] as Timestamp?)?.toDate();
            final timeStr = time != null
                ? '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                : '';

            return Card(
              color: const Color(0xFF1E1E1E),
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Request #${i + 1}',
                            style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold)),
                        Text(timeStr,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${item['name']} × ${item['quantity']}',
                              style: const TextStyle(color: Colors.white)),
                        )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // HISTORY TAB – NO INDEX NEEDED
  Widget _historyTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: 'Approved'), Tab(text: 'Rejected')],
          ),
          Expanded(
            child: TabBarView(children: [
              _historyList('approved'),
              _historyList('rejected'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _historyList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.orange));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
              child: Text('No $status requests',
                  style: const TextStyle(color: Colors.white70)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final items =
                (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final time = (data['requestedAt'] as Timestamp?)?.toDate();
            final timeStr = time != null
                ? '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}'
                : '';

            return Card(
              color: const Color(0xFF1E1E1E),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Batch #${i + 1}',
                            style: TextStyle(
                                color: status == 'approved'
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold)),
                        Text(timeStr,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${item['name']} × ${item['quantity']}',
                              style: const TextStyle(color: Colors.white)),
                        )),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            (status == 'approved' ? Colors.green : Colors.red)
                                .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(status.toUpperCase(),
                          style: TextStyle(
                              color: status == 'approved'
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  DataColumn _sortableHeader(String title, String field) {
    final active = _sortField == field;
    return DataColumn(
      label: InkWell(
        onTap: () => _sort(field),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.orange, fontWeight: FontWeight.bold)),
            if (active)
              Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14, color: Colors.orange),
          ],
        ),
      ),
    );
  }
}
