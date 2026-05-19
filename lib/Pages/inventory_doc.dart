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
      color: const Color(0xFFE8F5E9), // Match the Scaffold background seamlessly
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        final searchWidget = Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _teal.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _searchCtrl,
            cursorColor: _teal,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search medicines...',
              prefixIcon: const Icon(Icons.search_rounded, color: _teal, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(() => _searchCtrl.clear()),
                    )
                  : null,
              filled: true,
              fillColor: Colors.transparent,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _teal, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
          ),
        );

        final sortWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200, width: 1),
            boxShadow: [
              BoxShadow(
                color: _teal.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const FaIcon(FontAwesomeIcons.arrowDownAZ, color: _teal, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  value: _sortBy,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey, size: 20),
                  style: const TextStyle(color: Colors.black87, fontSize: 13.5, fontWeight: FontWeight.w500),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Sort by Name')),
                    DropdownMenuItem(value: 'quantity_asc', child: Text('Qty (Low to High)')),
                    DropdownMenuItem(value: 'quantity_desc', child: Text('Qty (High to Low)')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sortBy = value);
                  },
                ),
              ),
            ],
          ),
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 3, child: searchWidget),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: sortWidget),
            ],
          );
        } else {
          return Column(
            children: [
              searchWidget,
              const SizedBox(height: 12),
              sortWidget,
            ],
          );
        }
      }),
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

    return Column(
      children: [
        _buildMetricsRow(filtered),
        Expanded(
          child: LayoutBuilder(
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
    ),
  ),
],
);
}

  Widget _buildMetricsRow(List<Map<String, dynamic>> batches) {
    final totalMedicines = batches.length;
    final lowStockCount = batches.where((b) => (b['quantity'] as int) < 10).length;
    final totalStockQty = batches.fold<int>(0, (sum, b) => sum + (b['quantity'] as int));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildMetricCard('TOTAL FORMULAS', '$totalMedicines', FontAwesomeIcons.pills, _teal),
                  const SizedBox(width: 12),
                  _buildMetricCard('TOTAL QTY', '$totalStockQty', Icons.inventory_2_rounded, const Color(0xFF1976D2)),
                  const SizedBox(width: 12),
                  _buildMetricCard('LOW STOCK', '$lowStockCount', Icons.warning_amber_rounded, _lowStockRed),
                ],
              ),
            );
          } else {
            return Row(
              children: [
                Expanded(child: _buildMetricCard('TOTAL FORMULAS', '$totalMedicines', FontAwesomeIcons.pills, _teal)),
                const SizedBox(width: 16),
                Expanded(child: _buildMetricCard('TOTAL QTY', '$totalStockQty', Icons.inventory_2_rounded, const Color(0xFF1976D2))),
                const SizedBox(width: 16),
                Expanded(child: _buildMetricCard('LOW STOCK', '$lowStockCount', Icons.warning_amber_rounded, _lowStockRed)),
              ],
            );
          }
        }
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1B2631),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(
    String section,
    List<Map<String, dynamic>> items, {
    bool isFullHeight = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00695C), Color(0xFF004D40)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _teal.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: FaIcon(
                      section == 'All Medicines'
                          ? FontAwesomeIcons.pills
                          : FontAwesomeIcons.circleDot,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section,
                    style: const TextStyle(
                      color: Color(0xFF1B2631),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      color: _teal,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (_, i) => _buildItemRow(items[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item) {
    final qty = _asInt(item['quantity']);
    final bool lowStock = qty < 10;

    final abbrev = _getAbbrev(item['type']);
    final dose = (item['dose'] ?? '').toString().trim();
    final formula = (item['formula'] ?? '').toString().trim();
    final classification = (item['classification'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      color: lowStock ? _lowStockRed.withValues(alpha: 0.03) : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Type icon bubble
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: FaIcon(
                _typeIcon(item['type']),
                color: _teal,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),

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
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                Text(
                  abbrev.isNotEmpty
                      ? '$abbrev ${item['name']}'.trim()
                      : item['name'].toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: lowStock ? _lowStockRed : const Color(0xFF2D3748),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (classification.isNotEmpty)
                  Text(
                    classification,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Dose pill badge
          if (dose.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                dose,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A5568),
                ),
              ),
            ),
          const SizedBox(width: 16),

          // Quantity + LOW badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                qty.toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: lowStock ? _lowStockRed : _teal,
                ),
              ),
              if (lowStock)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _lowStockRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LOW',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
