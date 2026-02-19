// lib/pages/inventory.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dispensar_screen.dart';
import 'branches.dart';
import 'inventory_update.dart';
import 'inventory_adjustment.dart';

class InventoryPage extends StatefulWidget {
  final String branchId;
  final bool isAdmin;
  const InventoryPage({super.key, required this.branchId, this.isAdmin = false});

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
  final int _perPage = 15;

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
      'Big Bottle' => Icon(
          FontAwesomeIcons.prescriptionBottleAlt,
          size: size,
          color: color,
        ),
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
    // Kept for dispenser (non-admin) – you can uncomment the navigation if needed
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryUpdatePage(branchId: widget.branchId),
      ),
    );
  }

  void _openAdjustmentForm() {
    // Kept for dispenser (non-admin)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryAdjustmentPage(branchId: widget.branchId),
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.length == 7 && raw[2] == '-') return raw; // MM-yyyy
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}-${parts[2]}';
  }

  bool _isExpiringSoon(String? expiry) {
    if (expiry == null || expiry.isEmpty) return false;
    try {
      DateTime date;
      if (expiry.length == 7 && expiry[2] == '-') {
        final parts = expiry.split('-');
        final month = int.tryParse(parts[0]);
        final year = int.tryParse(parts[1]);
        if (month == null || year == null) return false;
        date = DateTime(year, month + 1, 0);
      } else {
        final parts = expiry.split('-');
        if (parts.length != 3) return false;
        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);
        if (day == null || month == null || year == null) return false;
        date = DateTime(year, month, day);
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
      var p = s.split('-');
      if (p.length == 2) {
        return DateTime(int.parse(p[1]), int.parse(p[0]), 15);
      } else if (p.length == 3) {
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    return DateTime(3000);
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
            Text(
              'Inventory',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Admin → always go back to Branches
            // Dispenser → go to DispensarScreen
            if (widget.isAdmin) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const Branches()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => DispensarScreen(branchId: widget.branchId),
                ),
              );
            }
          },
        ),
        actions: widget.isAdmin
            ? [] // No gear icon or any actions for admin
            : [
                IconButton(
                  icon: const Icon(FontAwesomeIcons.gear, color: Colors.white),
                  tooltip: 'Adjust Inventory',
                  onPressed: _openAdjustmentForm,
                ),
              ],
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
      floatingActionButton: widget.isAdmin
          ? null // No + button for admin
          : FloatingActionButton(
              backgroundColor: Colors.orange,
              onPressed: _openAddForm,
              tooltip: 'Request New Medicine',
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_stockTab(tableW), _pendingTab(), _historyTab()],
      ),
    );
  }

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
      String monthYear = '';
      if (expiry.length == 10 && expiry[2] == '-' && expiry[5] == '-') {
        monthYear = expiry.substring(3); // MM-yyyy
      }
      final key = '$name|$type|$dose|$monthYear';

      if (map.containsKey(key)) {
        map[key]!['quantity'] += qty;
      } else {
        map[key] = {
          'name': name,
          'type': type,
          'dose': dose,
          'expiryDate': monthYear,
          'quantity': qty,
          'price': price,
          'batchKey': key,
        };
      }
    }
    return map.values.toList();
  }

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
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      hintText: 'Search medicine...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF2D2D2D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButton<String>(
                              value: _filterType,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: const Color(0xFF2D2D2D),
                              style: const TextStyle(color: Colors.white),
                              items: _types.map((t) => DropdownMenuItem<String>(value: t, child: Text(t))).toList(),
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButton<String>(
                              value: _filterBatch,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: const Color(0xFF2D2D2D),
                              style: const TextStyle(color: Colors.white),
                              items: _batchKeys.map((k) => DropdownMenuItem<String>(value: k, child: Text(k == 'All Batches' ? k : 'Batch: $k', overflow: TextOverflow.ellipsis))).toList(),
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButton<String>(
                            value: _filterType,
                            isExpanded: true,
                            underline: const SizedBox(),
                            dropdownColor: const Color(0xFF2D2D2D),
                            style: const TextStyle(color: Colors.white),
                            items: _types.map((t) => DropdownMenuItem<String>(value: t, child: Text(t))).toList(),
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButton<String>(
                            value: _filterBatch,
                            isExpanded: true,
                            underline: const SizedBox(),
                            dropdownColor: const Color(0xFF2D2D2D),
                            style: const TextStyle(color: Colors.white),
                            items: _batchKeys.map((k) => DropdownMenuItem<String>(value: k, child: Text(k == 'All Batches' ? k : 'Batch: $k', overflow: TextOverflow.ellipsis))).toList(),
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
                return const Center(child: CircularProgressIndicator(color: Colors.orange));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                final noStockMessage = widget.isAdmin
                    ? 'No medicines in stock.'
                    : 'No medicines in stock.\nTap + to request.';
                return Center(
                  child: Text(noStockMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                );
              }

              final batches = _groupByBatch(docs);

              var preFiltered = batches.where((b) {
                final name = b['name'].toString().toLowerCase();
                final type = b['type'];
                return name.contains(_searchCtrl.text.toLowerCase()) && (_filterType == 'All' || type == _filterType);
              }).toList();

              final currentBatchSet = <String>{};
              for (var b in preFiltered) {
                final exp = b['expiryDate'] as String;
                if (exp.isNotEmpty) currentBatchSet.add(exp);
              }
              var batchList = currentBatchSet.toList();
              batchList.sort((a, b) {
                int toNum(String exp) {
                  var p = exp.split('-');
                  if (p.length != 2) return 0;
                  final month = int.tryParse(p[0]) ?? 0;
                  final year = int.tryParse(p[1]) ?? 0;
                  return year * 100 + month;
                }
                return toNum(a).compareTo(toNum(b));
              });
              final newBatchKeys = ['All Batches'] + batchList;

              if (_batchKeys.join(',') != newBatchKeys.join(',')) {
                setState(() {
                  _batchKeys = newBatchKeys;
                  if (!_batchKeys.contains(_filterBatch)) {
                    _filterBatch = 'All Batches';
                  }
                });
              }

              var filtered = preFiltered;
              if (_filterBatch != 'All Batches') {
                filtered = preFiltered.where((b) => b['expiryDate'] == _filterBatch).toList();
              }

              filtered.sort((a, b) {
                int cmp = 0;
                switch (_sortField) {
                  case 'name':
                    cmp = a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase());
                    break;
                  case 'dose':
                    cmp = (a['dose'] ?? '').toString().compareTo((b['dose'] ?? '').toString());
                    break;
                  case 'quantity':
                    cmp = (a['quantity'] as int).compareTo(b['quantity'] as int);
                    break;
                  case 'price':
                    cmp = (a['price'] as int).compareTo(b['price'] as int);
                    break;
                  case 'expiry':
                    cmp = _parseExpiry(a['expiryDate']).compareTo(_parseExpiry(b['expiryDate']));
                    break;
                }
                return _isAscending ? cmp : -cmp;
              });

              final totalPages = (filtered.length / _perPage).ceil();
              if (_page >= totalPages) {
                _page = totalPages > 0 ? totalPages - 1 : 0;
              }
              final start = _page * _perPage;
              final end = (start + _perPage).clamp(0, filtered.length);
              final pageData = start < end ? filtered.sublist(start, end) : [];

              return LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 600;

                  Widget content;
                  if (isWide) {
                    final numW = tableW * 0.05;
                    final nameW = tableW * 0.25;
                    final typeW = tableW * 0.15;
                    final doseW = tableW * 0.15;
                    final qtyW = tableW * 0.1;
                    final priceW = tableW * 0.15;
                    final expiryW = tableW * 0.15;

                    content = Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D),
                            border: const Border(bottom: BorderSide(color: Colors.orange, width: 1)),
                          ),
                          child: Row(
                            children: [
                              _headerCell(numW, const Text('#', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                              _headerCell(nameW, _sortableHeaderContent('Name', 'name', Colors.orange)),
                              _headerCell(typeW, const Text('Type', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                              _headerCell(doseW, _sortableHeaderContent('Dose', 'dose', Colors.orange)),
                              _headerCell(qtyW, _sortableHeaderContent('Qty', 'quantity', Colors.orange)),
                              _headerCell(priceW, _sortableHeaderContent('Price', 'price', Colors.orange)),
                              _headerCell(expiryW, _sortableHeaderContent('Expiry', 'expiry', Colors.orange)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: pageData.length,
                            itemBuilder: (context, index) {
                              final b = pageData[index];
                              final qty = b['quantity'] as int;
                              final type = b['type'] as String;
                              final lowStock = type == 'Big Bottle' ? qty < 3 : qty < 10;
                              final expiringSoon = _isExpiringSoon(b['expiryDate'] as String?);
                              final expiryText = _formatDate(b['expiryDate'] as String?);

                              return Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  border: Border(bottom: BorderSide(color: Colors.grey[800]!, width: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    _cell(numW, Text('${start + index + 1}', style: const TextStyle(color: Colors.white70))),
                                    _cell(nameW, Padding(padding: const EdgeInsets.only(left: 8.0), child: Text(b['name'], style: const TextStyle(color: Colors.white)))),
                                    _cell(typeW, Row(children: [_typeIcon(b['type']), const SizedBox(width: 6), Text(b['type'], style: const TextStyle(color: Colors.white))])),
                                    _cell(doseW, Text(b['dose'], style: const TextStyle(color: Colors.white70))),
                                    _cell(qtyW, Row(children: [if (lowStock) const Icon(Icons.warning, color: Colors.red, size: 16), Text(qty.toString(), style: TextStyle(color: lowStock ? Colors.red : Colors.orange, fontWeight: lowStock ? FontWeight.bold : FontWeight.normal))])),
                                    _cell(priceW, Text('PKR ${b['price']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                                    _cell(expiryW, Row(children: [if (expiringSoon) const Icon(Icons.access_time, color: Colors.red, size: 16), Text(expiryText, style: TextStyle(color: expiringSoon ? Colors.red : Colors.white70, fontWeight: expiringSoon ? FontWeight.bold : FontWeight.normal))])),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  } else {
                    content = ListView.builder(
                      itemCount: pageData.length,
                      itemBuilder: (context, index) {
                        final b = pageData[index];
                        final qty = b['quantity'] as int;
                        final type = b['type'] as String;
                        final lowStock = type == 'Big Bottle' ? qty < 3 : qty < 10;
                        final expiringSoon = _isExpiringSoon(b['expiryDate'] as String?);
                        final expiryText = _formatDate(b['expiryDate'] as String?);

                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('${start + index + 1}. ${b['name']}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    if (lowStock) const Icon(Icons.warning, color: Colors.red, size: 16),
                                    const SizedBox(width: 4),
                                    Text('Qty: $qty', style: TextStyle(color: lowStock ? Colors.red : Colors.orange)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(children: [_typeIcon(b['type']), const SizedBox(width: 8), Text('Type: ${b['type']}', style: const TextStyle(color: Colors.white70))]),
                                const SizedBox(height: 4),
                                Text('Dose: ${b['dose']}', style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 4),
                                Text('Price: PKR ${b['price']}', style: const TextStyle(color: Colors.green)),
                                const SizedBox(height: 4),
                                Row(children: [if (expiringSoon) const Icon(Icons.access_time, color: Colors.red, size: 16), const SizedBox(width: 4), Text('Expiry: $expiryText', style: TextStyle(color: expiringSoon ? Colors.red : Colors.white70))]),
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
                            IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: _page > 0 ? () => setState(() => _page--) : null),
                            const SizedBox(width: 8),
                            Text('Page ${_page + 1} of ${totalPages.clamp(1, 999)}', style: const TextStyle(color: Colors.white)),
                            const SizedBox(width: 8),
                            IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white), onPressed: (_page + 1 < totalPages) ? () => setState(() => _page++) : null),
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

  Widget _headerCell(double width, Widget child) {
    return Container(width: width, padding: const EdgeInsets.all(8), alignment: Alignment.centerLeft, child: child);
  }

  Widget _cell(double width, Widget child) {
    return Container(width: width, padding: const EdgeInsets.all(8), alignment: Alignment.centerLeft, child: child);
  }

  Widget _sortableHeaderContent(String title, String field, Color color) {
    final active = _sortField == field;
    return InkWell(
      onTap: () => _sort(field),
      child: Row(
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          if (active) Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: color),
        ],
      ),
    );
  }

  Widget _pendingTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('branches').doc(widget.branchId).collection('edit_requests').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.orange));
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        var docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No pending requests', style: TextStyle(color: Colors.white70)));
        docs.sort((a, b) {
          final ta = (a.data() as Map<String, dynamic>)['requestedAt'] as Timestamp?;
          final tb = (b.data() as Map<String, dynamic>)['requestedAt'] as Timestamp?;
          if (ta == null || tb == null) return 0;
          return ta.compareTo(tb);
        });
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final time = (data['requestedAt'] as Timestamp?)?.toDate();
            final timeStr = time != null ? '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : '';
            return Card(
              color: const Color(0xFF1E1E1E),
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Request #${i + 1}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        Text(timeStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
                        child: DataTable(
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(label: Text('Name', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Type', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Dose', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Qty', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Price', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Expiry', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                          ],
                          rows: items.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item['name'] ?? '', style: const TextStyle(color: Colors.white))),
                              DataCell(Text(item['type'] ?? '', style: const TextStyle(color: Colors.white))),
                              DataCell(Text(item['dose'] ?? '', style: const TextStyle(color: Colors.white))),
                              DataCell(Text('${item['quantity'] ?? 0}', style: const TextStyle(color: Colors.white))),
                              DataCell(Text('PKR ${item['price'] ?? 0}', style: const TextStyle(color: Colors.white))),
                              DataCell(Text(_formatDate(item['expiryDate']), style: const TextStyle(color: Colors.white))),
                            ]);
                          }).toList(),
                        ),
                      ),
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
          Expanded(child: TabBarView(children: [_historyList('approved'), _historyList('rejected')])),
        ],
      ),
    );
  }

  Widget _historyList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('branches').doc(widget.branchId).collection('edit_requests').where('status', isEqualTo: status).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.orange));
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        var docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return Center(child: Text('No $status requests', style: TextStyle(color: Colors.white70)));
        docs.sort((a, b) {
          final ta = (a.data() as Map<String, dynamic>)['requestedAt'] as Timestamp?;
          final tb = (b.data() as Map<String, dynamic>)['requestedAt'] as Timestamp?;
          if (ta == null || tb == null) return 0;
          return ta.compareTo(tb);
        });
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final time = (data['requestedAt'] as Timestamp?)?.toDate();
            final timeStr = time != null ? '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}' : '';
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
                        Text('Batch #${i + 1}', style: TextStyle(color: status == 'approved' ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                        Text(timeStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
                        child: DataTable(
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(label: Text('Name', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Type', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Dose', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Qty', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Price', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Expiry', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                          ],
                          rows: items.map((item) {
                            return DataRow(cells: [
                              DataCell(Text(item['name'] ?? '', style: const TextStyle(color: Colors.white))),
                              DataCell(Text(item['type'] ?? '', style: const TextStyle(color: Colors.white))),
                              DataCell(Text(item['dose'] ?? '', style: const TextStyle(color: Colors.white))),
                              DataCell(Text('${item['quantity'] ?? 0}', style: const TextStyle(color: Colors.white))),
                              DataCell(Text('PKR ${item['price'] ?? 0}', style: const TextStyle(color: Colors.white))),
                              DataCell(Text(_formatDate(item['expiryDate']), style: const TextStyle(color: Colors.white))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: (status == 'approved' ? Colors.green : Colors.red).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text(status.toUpperCase(), style: TextStyle(color: status == 'approved' ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
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
}