// lib/pages/inventory_doc.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/local_storage_service.dart';

class InventoryDocPage extends StatefulWidget {
  final String branchId;
  final bool isStandalone;
  final String role; // e.g. 'doctor' or 'supervisor'
  const InventoryDocPage({
    super.key,
    required this.branchId,
    this.isStandalone = true,
    this.role = 'doctor',
  });

  @override
  State<InventoryDocPage> createState() => _InventoryDocPageState();
}

class _InventoryDocPageState extends State<InventoryDocPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _sortBy = 'name';
  static const Color _teal = Color(0xFF00695C);
  static const Color _lowStockRed = Color(0xFFE53935);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  IconData _typeIcon(String type) {
    final trimmed = type.trim();
    return switch (trimmed) {
      'Tablet' => FontAwesomeIcons.tablets,
      'Capsule' => FontAwesomeIcons.capsules,
      'Syrup' => FontAwesomeIcons.bottleWater,
      'Injection' => FontAwesomeIcons.syringe,
      'Drip' => FontAwesomeIcons.bottleDroplet,
      'Drip Set' => FontAwesomeIcons.kitMedical,
      'Syringe' => FontAwesomeIcons.syringe,
      'Nebulization' => FontAwesomeIcons.wind,
      _ => FontAwesomeIcons.pills,
    };
  }

  List<Map<String, dynamic>> _groupByBatch(List<Map<String, dynamic>> items) {
    final Map<String, Map<String, dynamic>> map = {};
    for (final item in items) {
      final name = (item['name'] ?? '').toString().trim();
      final type = item['type'] ?? '';
      final dose = (item['dose'] ?? '').toString().trim();
      final classification = item['classification']?.toString().trim() ?? '';
      final qty = _asInt(item['quantity']);
      final key = '$name|$type|$dose|$classification';
      if (map.containsKey(key)) {
        map[key]!['quantity'] += qty;
      } else {
        map[key] = {
          'name': name,
          'type': type,
          'dose': dose,
          'quantity': qty,
          'classification': classification,
          'formula': item['formula'] ?? '',
          'formula_lower': item['formula_lower'] ?? '',
        };
      }
    }
    return map.values.toList();
  }

  String _getAbbrev(String type) {
    return switch (type.trim()) {
      'Tablet' => 'tab.',
      'Capsule' => 'cap.',
      'Syrup' => 'syp.',
      'Injection' => 'inj.',
      'Drip' => 'drip',
      'Drip Set' => 'drip set',
      'Syringe' => 'syr.',
      'Nebulization' => 'neb.',
      _ => '',
    };
  }

  String _getTypeGroup(String type) {
    final trimmed = type.trim();
    if (trimmed == 'Capsule') return 'Capsule';
    if (trimmed == 'Tablet') return 'Tablet';
    if (trimmed == 'Syrup' || trimmed == 'Nebulization') return 'Syrup';
    if (['Injection', 'Drip', 'Drip Set', 'Syringe'].contains(trimmed)) return 'Injection';
    return 'Others';
  }

  void _sortItems(List<Map<String, dynamic>> items) {
    if (_sortBy == 'name') {
      items.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    } else if (_sortBy == 'quantity_asc') {
      items.sort((a, b) => _asInt(a['quantity']).compareTo(_asInt(b['quantity'])));
    } else if (_sortBy == 'quantity_desc') {
      items.sort((a, b) => _asInt(b['quantity']).compareTo(_asInt(a['quantity'])));
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildSearchAndSortBar(),
        Expanded(child: _buildStockView()),
      ],
    );

    if (!widget.isStandalone) return content;

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      appBar: AppBar(
        backgroundColor: _teal,
        elevation: 8,
        leading: widget.role == 'doctor'
            ? IconButton(
                icon: const FaIcon(FontAwesomeIcons.arrowLeft, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(
          children: [
            const FaIcon(FontAwesomeIcons.pills, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            const Text(
              'Inventory',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () async {
              await LocalStorageService.downloadInventory(widget.branchId);
              setState(() {});
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: content,
    );
  }

  Widget _buildSearchAndSortBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search medicines...',
                  prefixIcon: const Icon(Icons.search, color: _teal),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _searchCtrl.clear()),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.arrowDownAZ, color: _teal, size: 18),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _sortBy,
                underline: const SizedBox(),
                icon: const Icon(Icons.keyboard_arrow_down, color: _teal),
                items: const [
                  DropdownMenuItem(value: 'name', child: Text('Name')),
                  DropdownMenuItem(value: 'quantity_asc', child: Text('Qty ↑')),
                  DropdownMenuItem(value: 'quantity_desc', child: Text('Qty ↓')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _sortBy = value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockView() {
    final allItems = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId);

    if (allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(FontAwesomeIcons.boxOpen, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No inventory items found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await LocalStorageService.downloadInventory(widget.branchId);
                setState(() {});
              },
              icon: const FaIcon(FontAwesomeIcons.arrowsRotate),
              label: const Text('Reload Inventory'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final batches = _groupByBatch(allItems);
    final searchText = _searchCtrl.text.trim().toLowerCase();
    final List<Map<String, dynamic>> filtered = batches.where((b) {
      final name = (b['name'] ?? '').toString().toLowerCase();
      final type = (b['type'] ?? '').toString().toLowerCase();
      final dose = (b['dose'] ?? '').toString().toLowerCase();
      final formula = (b['formula'] ?? '').toString().toLowerCase();
      return name.contains(searchText) ||
          type.contains(searchText) ||
          dose.contains(searchText) ||
          formula.contains(searchText);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No items match your search',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      );
    }

    final Map<String, List<Map<String, dynamic>>> groupedByType = {};
    for (var item in filtered) {
      final group = _getTypeGroup(item['type']);
      groupedByType.putIfAbsent(group, () => []).add(item);
    }

    final List<String> sections = [
      'All Medicines',
      'Capsule',
      'Tablet',
      'Syrup',
      'Injection',
      'Others'
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;

        int crossAxisCount = 1;
        double childAspectRatio = 1.4;

        if (width > 1600) {
          crossAxisCount = 4;
          childAspectRatio = 1.35;
        } else if (width > 1300) {
          crossAxisCount = 3;
          childAspectRatio = 1.4;
        } else if (width > 1000) {
          crossAxisCount = 2;
          childAspectRatio = 1.45;
        } else if (width > 700) {
          crossAxisCount = 2;
          childAspectRatio = 1.5;
        }

        final allMedicinesItems = List<Map<String, dynamic>>.from(filtered);
        _sortItems(allMedicinesItems);

        final otherSections = sections.sublist(1);
        final List<Map<String, dynamic>> sectionData = [];

        for (final section in otherSections) {
          final items = groupedByType[section] ?? [];
          if (items.isNotEmpty) {
            _sortItems(items);
            sectionData.add({'section': section, 'items': items});
          }
        }

        if (width <= 700) {
          const double cardHeight = 380;
          final List<Widget> cards = [
            SizedBox(
              height: cardHeight,
              child: _buildCategoryCard('All Medicines', allMedicinesItems,
                  isFullHeight: true),
            ),
            ...sectionData.map(
              (d) => SizedBox(
                height: cardHeight,
                child: _buildCategoryCard(
                  d['section'] as String,
                  d['items'] as List<Map<String, dynamic>>,
                ),
              ),
            ),
          ];

          return Padding(
            padding: const EdgeInsets.all(12),
            child: ListView.separated(
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) => cards[i],
            ),
          );
        }

        final List<Widget> gridItems = sectionData
            .map((d) => _buildCategoryCard(
                  d['section'] as String,
                  d['items'] as List<Map<String, dynamic>>,
                ))
            .toList();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _buildCategoryCard('All Medicines', allMedicinesItems,
                    isFullHeight: true),
              ),
              if (gridItems.isNotEmpty) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 18,
                    childAspectRatio: childAspectRatio,
                    children: gridItems,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryCard(
    String section,
    List<Map<String, dynamic>> items, {
    bool isFullHeight = false,
  }) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: FaIcon(
                      section == 'All Medicines'
                          ? FontAwesomeIcons.pills
                          : FontAwesomeIcons.circleDot,
                      color: _teal,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section,
                    style: const TextStyle(
                      color: _teal,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      color: _teal,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 0.8),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5),
                itemBuilder: (_, i) => _buildItemRow(items[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final qty = _asInt(item['quantity']);
    final bool lowStock = qty < 10;
    final Color textColor = lowStock ? _lowStockRed : Colors.black87;

    final abbrev = _getAbbrev(item['type']);
    final dose = (item['dose'] ?? '').toString().trim();
    final formula = (item['formula'] ?? '').toString().trim();
    final classification = (item['classification'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      decoration: BoxDecoration(
        color: lowStock
            ? _lowStockRed.withValues(alpha: 0.06)
            : Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: lowStock
            ? Border.all(color: _lowStockRed.withValues(alpha: 0.35), width: 1)
            : Border.all(color: Colors.grey.withValues(alpha: 0.12), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Type icon bubble
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: lowStock
                  ? _lowStockRed.withValues(alpha: 0.12)
                  : _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: FaIcon(
                _typeIcon(item['type']),
                color: lowStock ? _lowStockRed : _teal,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name + formula + classification
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (formula.isNotEmpty)
                  Text(
                    formula,
                    style: TextStyle(
                      fontSize: 10,
                      color: _teal.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  abbrev.isNotEmpty
                      ? '$abbrev ${item['name']}'.trim()
                      : item['name'].toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (classification.isNotEmpty)
                  Text(
                    classification,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Dose pill badge
          if (dose.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: lowStock
                    ? _lowStockRed.withValues(alpha: 0.12)
                    : _teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: lowStock
                      ? _lowStockRed.withValues(alpha: 0.3)
                      : _teal.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Text(
                dose,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: lowStock ? _lowStockRed : _teal,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          const SizedBox(width: 8),

          // Quantity + LOW badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                qty.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              if (lowStock)
                Text(
                  'LOW',
                  style: TextStyle(
                    fontSize: 8.5,
                    color: _lowStockRed,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
