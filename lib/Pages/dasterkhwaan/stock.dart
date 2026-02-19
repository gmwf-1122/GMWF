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

  @override
  void initState() {
    super.initState();
    _loadBranchAndStock();
  }

  Future<void> _loadBranchAndStock() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final branches = await FirebaseFirestore.instance.collection('branches').get();
    for (final branch in branches.docs) {
      final doc = await branch.reference.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          _branchId = branch.id;
        });
        _loadStockItems();
        return;
      }
    }
  }

  Future<void> _loadStockItems() async {
    if (_branchId == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan_stock')
        .orderBy('name')
        .get();

    setState(() {
      _allStockItems = snapshot.docs.map((e) => StockItem.fromMap(e.data(), e.id)).toList();
    });
  }

  Future<void> _addCustomStockItem() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    String unit = 'kg';
    const units = ['kg', 'gram', 'liter', 'piece', 'packet', 'bundle', 'bunch', 'handi', 'plate'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Add Custom Stock Item", style: TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: "Item Name",
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  validator: (v) => v?.trim().isEmpty ?? true ? "Required" : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: unit,
                  decoration: InputDecoration(
                    labelText: "Unit",
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: units.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => unit = v!,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final name = nameController.text.trim();
                if (_allStockItems.any((item) => item.name == name)) return;

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

                if (mounted) Navigator.pop(context);
                _loadStockItems();
              }
            },
            child: const Text("Add Item"),
          ),
        ],
      ),
    );
  }

  void _adjustStock(StockItem item, double delta) {
    final formKey = GlobalKey<FormState>();
    final qtyController = TextEditingController(text: "1.0");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(delta > 0 ? "Increment ${item.name}" : "Decrement ${item.name}", style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: qtyController,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: "Quantity",
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            validator: (v) => (double.tryParse(v!) ?? 0) <= 0 ? "Positive number required" : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final qty = double.parse(qtyController.text);
                final effectiveDelta = delta > 0 ? qty : -qty;
                await _updateStock(item.name, effectiveDelta);
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Apply"),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    if (_branchId == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Stock Management", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green.shade700,
        onPressed: _addCustomStockItem,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search stock items...",
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      })
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _allStockItems.length,
              itemBuilder: (_, i) {
                final item = _allStockItems[i];
                if (_searchController.text.isNotEmpty && !item.name.toLowerCase().contains(_searchController.text.toLowerCase())) return const SizedBox.shrink();
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text("${item.quantity} ${item.unit} - Last updated: ${DateFormat('dd MMM hh:mm a').format(item.lastUpdated.toDate())}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                          onPressed: () => _adjustStock(item, 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: () => _adjustStock(item, -1),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}