// lib/pages/warehouse.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class WarehouseScreen extends StatefulWidget {
  final String branchId;
  const WarehouseScreen({super.key, required this.branchId});

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filterType = "All";
  String _filterBatch = "All Batches";
  String _sortField = "name";
  bool _isAscending = true;
  int _page = 0;
  final int _perPage = 10;

  final List<String> _types = [
    "All",
    "Big Bottle",
    "Syrup",
    "Drip",
    "Injection",
    "Powder",
    "Other"
  ];

  List<String> _batchKeys = ['All Batches'];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
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

  Widget _typeIcon(String t,
      {double size = 16, Color color = Colors.blueGrey}) {
    return switch (t) {
      'Big Bottle' =>
        Icon(FontAwesomeIcons.bottleDroplet, size: size, color: color),
      'Syrup' =>
        Icon(FontAwesomeIcons.prescriptionBottle, size: size, color: color),
      'Drip' => Icon(FontAwesomeIcons.vial, size: size, color: color),
      'Injection' => Icon(FontAwesomeIcons.syringe, size: size, color: color),
      'Powder' => Icon(FontAwesomeIcons.flask, size: size, color: color),
      'Other' => Icon(FontAwesomeIcons.box, size: size, color: color),
      _ => Icon(FontAwesomeIcons.circleQuestion, size: size, color: color),
    };
  }

  void _sort(String field) {
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
    if (raw == null || raw.isEmpty) return '';
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}-${parts[2]}';
  }

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

  List<Map<String, dynamic>> _groupByBatch(List<QueryDocumentSnapshot> docs) {
    final Map<String, Map<String, dynamic>> map = {};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().trim();
      final type = data['type'] ?? '';
      final dose = (data['dose'] ?? '').toString().trim();
      final expiry = data['expiryDate']?.toString().trim() ?? '';
      final qty = _asInt(data['quantity']);
      final price = _asInt(data['price'] ?? 0);

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

  void _openAddForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WarehouseUpdatePage(branchId: widget.branchId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final tableW = w - 32;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        title: const Row(
          children: [
            Icon(FontAwesomeIcons.warehouse, color: Colors.white),
            SizedBox(width: 10),
            Text('Warehouse',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [], // No back button
      ),
      body: Column(
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
                            const Icon(Icons.search, color: Colors.blueGrey),
                        hintText: 'Search warehouse...',
                        hintStyle: const TextStyle(color: Colors.blueGrey),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                      style: const TextStyle(color: Colors.black87),
                      onChanged: (_) => setState(() => _page = 0),
                    ),
                    const SizedBox(height: 8),
                    if (isWide)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12)),
                              child: DropdownButton<String>(
                                value: _filterType,
                                isExpanded: true,
                                underline: const SizedBox(),
                                dropdownColor: Colors.white,
                                style: const TextStyle(color: Colors.black87),
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12)),
                              child: DropdownButton<String>(
                                value: _filterBatch,
                                isExpanded: true,
                                underline: const SizedBox(),
                                dropdownColor: Colors.white,
                                style: const TextStyle(color: Colors.black87),
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
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12)),
                            child: DropdownButton<String>(
                              value: _filterType,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: Colors.white,
                              style: const TextStyle(color: Colors.black87),
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
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12)),
                            child: DropdownButton<String>(
                              value: _filterBatch,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: Colors.white,
                              style: const TextStyle(color: Colors.black87),
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
                  .collection('warehouse')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.blueGrey));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No items in warehouse.\nTap + to add.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blueGrey, fontSize: 16),
                    ),
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
                      cmp = (a['quantity'] as int)
                          .compareTo(b['quantity'] as int);
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

                int lowCount =
                    filtered.where((b) => (b['quantity'] as int) < 10).length;
                int expCount = filtered
                    .where((b) => _isExpiringSoon(b['expiryDate']))
                    .length;

                if (lowCount > 0 || expCount > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Low stock: $lowCount, Expiring soon: $expCount. Notify admin and supervisor.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  });
                }

                final totalPages = (filtered.length / _perPage).ceil();
                if (_page >= totalPages)
                  _page = totalPages > 0 ? totalPages - 1 : 0;
                final start = _page * _perPage;
                final end = (start + _perPage).clamp(0, filtered.length);
                final pageData =
                    start < end ? filtered.sublist(start, end) : [];

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
                            headingRowColor:
                                MaterialStateProperty.all(Colors.blueGrey),
                            dataRowColor:
                                MaterialStateProperty.all(Colors.white),
                            columns: [
                              _sortableHeader('Name', 'name'),
                              const DataColumn(
                                  label: Text('Type',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold))),
                              _sortableHeader('Size', 'dose'),
                              _sortableHeader('Qty', 'quantity'),
                              _sortableHeader('Price', 'price'),
                              _sortableHeader('Expiry', 'expiry'),
                            ],
                            rows: pageData.map((b) {
                              final qty = b['quantity'] as int;
                              final lowStock = qty < 10;
                              final expiringSoon =
                                  _isExpiringSoon(b['expiryDate']);
                              final expiryText = _formatDate(b['expiryDate']);

                              return DataRow(cells: [
                                DataCell(Text(b['name'],
                                    style: const TextStyle(
                                        color: Colors.black87))),
                                DataCell(Row(children: [
                                  _typeIcon(b['type']),
                                  const SizedBox(width: 6),
                                  Text(b['type'],
                                      style: const TextStyle(
                                          color: Colors.black87)),
                                ])),
                                DataCell(Text(b['dose'],
                                    style: const TextStyle(
                                        color: Colors.blueGrey))),
                                DataCell(Row(
                                  children: [
                                    if (lowStock)
                                      const Icon(Icons.warning,
                                          color: Colors.red, size: 16),
                                    Text(qty.toString(),
                                        style: TextStyle(
                                            color: lowStock
                                                ? Colors.red
                                                : Colors.green,
                                            fontWeight: lowStock
                                                ? FontWeight.bold
                                                : FontWeight.normal)),
                                    if (lowStock) const SizedBox(width: 4),
                                    if (lowStock)
                                      const Text('Low Stock',
                                          style: TextStyle(color: Colors.red)),
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
                                                : Colors.blueGrey,
                                            fontWeight: expiringSoon
                                                ? FontWeight.bold
                                                : FontWeight.normal)),
                                    if (expiringSoon) const SizedBox(width: 4),
                                    if (expiringSoon)
                                      const Text('Short Expiry',
                                          style: TextStyle(color: Colors.red)),
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
                          final expiringSoon = _isExpiringSoon(b['expiryDate']);
                          final expiryText = _formatDate(b['expiryDate']);

                          return Card(
                            color: Colors.white,
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
                                          color: Colors.black87,
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
                                              : Colors.green,
                                        ),
                                      ),
                                      if (lowStock) const SizedBox(width: 4),
                                      if (lowStock)
                                        const Text('Low Stock',
                                            style:
                                                TextStyle(color: Colors.red)),
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
                                            color: Colors.blueGrey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Size: ${b['dose']}',
                                    style:
                                        const TextStyle(color: Colors.blueGrey),
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
                                              : Colors.blueGrey,
                                        ),
                                      ),
                                      if (expiringSoon)
                                        const SizedBox(width: 4),
                                      if (expiringSoon)
                                        const Text('Short Expiry',
                                            style:
                                                TextStyle(color: Colors.red)),
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
                                      color: Colors.blueGrey),
                                  onPressed: _page > 0
                                      ? () => setState(() => _page--)
                                      : null),
                              const SizedBox(width: 8),
                              Text(
                                  'Page ${_page + 1} of ${totalPages.clamp(1, 999)}',
                                  style:
                                      const TextStyle(color: Colors.blueGrey)),
                              const SizedBox(width: 8),
                              IconButton(
                                  icon: const Icon(Icons.chevron_right,
                                      color: Colors.blueGrey),
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
      ),
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
                    color: Colors.white, fontWeight: FontWeight.bold)),
            if (active)
              Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class WarehouseUpdatePage extends StatefulWidget {
  final String branchId;
  const WarehouseUpdatePage({super.key, required this.branchId});

  @override
  State<WarehouseUpdatePage> createState() => _WarehouseUpdatePageState();
}

class _WarehouseUpdatePageState extends State<WarehouseUpdatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _expiryCtrl = TextEditingController();
  final _customDoseCtrl = TextEditingController();

  String _type = 'Big Bottle';
  String _dose = '1 L';

  final List<String> _bigBottleDoses = [
    "1 L",
    "500 ml",
    "250 ml",
    "100 ml",
    "50 ml",
    "Custom"
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        title: const Text('Add Warehouse Item',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Name', filled: true, fillColor: Colors.white),
                style: const TextStyle(color: Colors.black87),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                items: [
                  "Big Bottle",
                  "Syrup",
                  "Drip",
                  "Injection",
                  "Powder",
                  "Other"
                ]
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v!),
                decoration: const InputDecoration(
                    labelText: 'Type', filled: true, fillColor: Colors.white),
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 16),
              if (_type == 'Big Bottle') ...[
                DropdownButtonFormField<String>(
                  value: _dose,
                  items: _bigBottleDoses
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setState(() => _dose = v!),
                  decoration: const InputDecoration(
                      labelText: 'Size', filled: true, fillColor: Colors.white),
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Colors.black87),
                ),
                if (_dose == 'Custom')
                  TextFormField(
                    controller: _customDoseCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Custom Size',
                        filled: true,
                        fillColor: Colors.white),
                    style: const TextStyle(color: Colors.black87),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Required' : null,
                  ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Quantity',
                    filled: true,
                    fillColor: Colors.white),
                style: const TextStyle(color: Colors.black87),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 1
                      ? 'Enter greater than or equal to 1'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _expiryCtrl,
                decoration: const InputDecoration(
                    labelText: 'Expiry (dd-mm-yyyy)',
                    filled: true,
                    fillColor: Colors.white),
                style: const TextStyle(color: Colors.black87),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                  TextInputFormatter.withFunction((old, newVal) {
                    var text = newVal.text;
                    if (text.length > 2 && text[2] != '-')
                      text = '${text.substring(0, 2)}-${text.substring(2)}';
                    if (text.length > 5 && text[5] != '-')
                      text = '${text.substring(0, 5)}-${text.substring(5)}';
                    return newVal.copyWith(
                        text: text,
                        selection:
                            TextSelection.collapsed(offset: text.length));
                  }),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;

                  final name = _nameCtrl.text.trim();
                  final qty = int.parse(_qtyCtrl.text);
                  final expiry = _expiryCtrl.text.trim();
                  final dose = _type == 'Big Bottle'
                      ? (_dose == 'Custom'
                          ? _customDoseCtrl.text.trim()
                          : _dose)
                      : '';

                  try {
                    final docRef = FirebaseFirestore.instance
                        .collection('branches')
                        .doc(widget.branchId)
                        .collection('warehouse')
                        .doc();

                    await docRef.set({
                      'name': name,
                      'name_lower': name.toLowerCase(),
                      'type': _type,
                      'dose': dose,
                      'quantity': qty,
                      'expiryDate': expiry,
                      'price': 0,
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Item added to warehouse')));
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: const Text('Save to Warehouse',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
