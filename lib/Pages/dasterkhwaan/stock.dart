import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/stock_item.dart';

class DasterkhwaanStock extends StatefulWidget {
  static const String routeName = '/dasterkhwaan-stock';
  const DasterkhwaanStock({super.key});

  @override
  State<DasterkhwaanStock> createState() => _DasterkhwaanStockState();
}

class _DasterkhwaanStockState extends State<DasterkhwaanStock> {
  String? _branchId;
  List<StockItem> _allStockItems = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;

  static const Color _primary = Color(0xFF1B5E20);
  static const Color _primaryLight = Color(0xFF2E7D32);
  static const Color _accent = Color(0xFFF9A825);
  static const Color _surface = Color(0xFFF1F8E9);

  @override
  void initState() {
    super.initState();
    _loadBranchAndStock();
  }

  Future<void> _loadBranchAndStock() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final branches =
        await FirebaseFirestore.instance.collection('branches').get();
    for (final branch in branches.docs) {
      final doc =
          await branch.reference.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() => _branchId = branch.id);
        await _loadStockItems();
        return;
      }
    }
  }

  Future<void> _loadStockItems() async {
    if (_branchId == null) return;
    setState(() => _loading = true);
    final snapshot = await FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan_stock')
        .orderBy('name')
        .get();
    setState(() {
      _allStockItems =
          snapshot.docs.map((e) => StockItem.fromMap(e.data(), e.id)).toList();
      _loading = false;
    });
  }

  void _showAddItemDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    String unit = 'kg';
    const units = [
      'kg','gram','liter','piece','packet','bundle','bunch','handi','plate'
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: _primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.add_box_rounded,
                          color: _primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text("Add Stock Item",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: nameController,
                    decoration: _inputDeco(
                        label: "Item Name *",
                        icon: Icons.inventory_2_outlined),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? "Required" : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: unit,
                    decoration:
                        _inputDeco(label: "Unit", icon: Icons.straighten),
                    items: units
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setModal(() => unit = v!),
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text("Cancel",
                            style: TextStyle(color: Colors.grey, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final name = nameController.text.trim();
                          if (_allStockItems.any((i) => i.name == name)) {
                            _showSnack("Item already exists", isError: true);
                            return;
                          }
                          final ref = FirebaseFirestore.instance
                              .collection('branches')
                              .doc(_branchId)
                              .collection('dasterkhwaan_stock')
                              .doc(name);
                          await ref.set({
                            'name': name,
                            'quantity': 0.0,
                            'unit': unit,
                            'lastUpdated': FieldValue.serverTimestamp(),
                          });
                          if (context.mounted) Navigator.pop(context);
                          await _loadStockItems();
                          _showSnack("$name added to stock");
                        },
                        child: const Text("Add Item",
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAdjustDialog(StockItem item, {required bool isIncrement}) {
    final formKey = GlobalKey<FormState>();
    final qtyController = TextEditingController(text: "1.0");

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2))),
                ),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isIncrement
                          ? const Color(0xFF1565C0).withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isIncrement
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      color: isIncrement
                          ? const Color(0xFF1565C0)
                          : Colors.red.shade600,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isIncrement ? "Add Stock" : "Remove Stock",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      Text(item.name,
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ]),
                const SizedBox(height: 12),

                // Current stock indicator
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Current Stock",
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                      Text(
                        "${item.quantity} ${item.unit}",
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B5E20),
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: qtyController,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: true),
                  decoration: _inputDeco(
                      label: "Quantity (${item.unit})",
                      icon: Icons.scale_rounded),
                  validator: (v) =>
                      (double.tryParse(v!) ?? 0) <= 0
                          ? "Must be positive"
                          : null,
                ),
                const SizedBox(height: 24),

                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text("Cancel",
                          style: TextStyle(color: Colors.grey, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isIncrement
                            ? const Color(0xFF1565C0)
                            : Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final qty = double.parse(qtyController.text);
                        final delta = isIncrement ? qty : -qty;
                        await _updateStock(item.name, delta);
                        if (context.mounted) Navigator.pop(context);
                        _showSnack(isIncrement
                            ? "Added $qty ${item.unit} of ${item.name}"
                            : "Removed $qty ${item.unit} of ${item.name}");
                      },
                      child: Text(
                        isIncrement ? "Add Stock" : "Remove Stock",
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateStock(String itemName, double delta) async {
    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan_stock')
        .doc(itemName);
    await ref.update({
      'quantity': FieldValue.increment(delta),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
    await _loadStockItems();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(msg,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: isError ? const Color(0xFFB71C1C) : _primaryLight,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  InputDecoration _inputDeco(
      {required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _primary, size: 20),
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filter items
    final filtered = _searchController.text.isEmpty
        ? _allStockItems
        : _allStockItems
            .where((i) => i.name
                .toLowerCase()
                .contains(_searchController.text.toLowerCase()))
            .toList();

    final lowStock =
        _allStockItems.where((i) => i.quantity <= 2).length;

    return Scaffold(
      backgroundColor: _surface,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1B5E20), Color(0xFF33691E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text("Stock Management",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        Row(children: [
                          Text(
                            "${_allStockItems.length} items",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 13),
                          ),
                          if (lowStock > 0) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.red.withOpacity(0.5)),
                              ),
                              child: Text(
                                "$lowStock low stock",
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: "Search stock items...",
                  prefixIcon:
                      Icon(Icons.search, color: Colors.grey[500], size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          })
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                ),
              ),
            ),
          ),

          // Content
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF1B5E20), strokeWidth: 2)),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 72,
                        color: _primary.withOpacity(0.2)),
                    const SizedBox(height: 12),
                    Text("No items found",
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 15)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final item = filtered[i];
                    final isLow = item.quantity <= 2;
                    final updated = item.lastUpdated.toDate();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isLow
                              ? Colors.red.withOpacity(0.3)
                              : Colors.transparent,
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            // Stock icon
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isLow
                                    ? Colors.red.withOpacity(0.08)
                                    : _primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                isLow
                                    ? Icons.warning_rounded
                                    : Icons.kitchen_rounded,
                                color: isLow
                                    ? Colors.red.shade500
                                    : _primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Updated ${DateFormat('dd MMM, hh:mm a').format(updated)}",
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            // Qty badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isLow
                                    ? Colors.red.withOpacity(0.1)
                                    : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isLow
                                      ? Colors.red.withOpacity(0.3)
                                      : _primary.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                "${item.quantity} ${item.unit}",
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: isLow
                                        ? Colors.red.shade600
                                        : _primary,
                                    fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Actions
                            Column(
                              children: [
                                _ActionBtn(
                                  icon: Icons.add_rounded,
                                  color: const Color(0xFF1565C0),
                                  onTap: () => _showAdjustDialog(item,
                                      isIncrement: true),
                                ),
                                const SizedBox(height: 4),
                                _ActionBtn(
                                  icon: Icons.remove_rounded,
                                  color: Colors.red.shade500,
                                  onTap: () => _showAdjustDialog(item,
                                      isIncrement: false),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        foregroundColor: Colors.black87,
        onPressed: _showAddItemDialog,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text("Add Item",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        elevation: 4,
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}