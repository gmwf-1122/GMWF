import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/stock_item.dart';

class DasterkhwaanKitchen extends StatefulWidget {
  static const String routeName = '/dasterkhwaan-kitchen';
  const DasterkhwaanKitchen({super.key});

  @override
  State<DasterkhwaanKitchen> createState() => _DasterkhwaanKitchenState();
}

class _DasterkhwaanKitchenState extends State<DasterkhwaanKitchen> {
  int _selectedIndex = 0;
  String _username = "User";
  String? _branchId;

  final TextEditingController _menuController = TextEditingController();

  final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat displayFormat = DateFormat('dd MMM yyyy');
  late final String today = dateFormat.format(DateTime.now());

  List<StockItem> _allStockItems = [];
  bool _stockLoaded = false;

  static const Map<String, double> requiredPerToken = {
    'Piyaz': 0.05,
    'Tamatar': 0.1,
    'Aloo': 0.15,
    'Ghee': 0.05,
    'Oil': 0.05,
    'Bara Gosht': 0.25,
    'Chota Gosht': 0.2,
    'Chawal': 0.2,
    'Daal Masoor': 0.15,
    'Daal Chana': 0.15,
  };

  @override
  void initState() {
    super.initState();
    _loadUserAndBranch();
  }

  Future<void> _loadUserAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final branches = await FirebaseFirestore.instance.collection('branches').get();
    for (final branch in branches.docs) {
      final doc = await branch.reference.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _username = data['username'] ?? user.email?.split('@').first ?? "User";
          _branchId = branch.id;
        });
        _loadAllStockItems();
        return;
      }
    }
  }

  Future<void> _loadAllStockItems() async {
    if (_branchId == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan_stock')
        .orderBy('name')
        .get();

    List<StockItem> items = snapshot.docs.map((e) => StockItem.fromMap(e.data(), e.id)).toList();

    if (items.isEmpty) {
      const defaults = [
        'Piyaz','Tamatar','Aloo','Ghee','Oil','Bara Gosht','Chota Gosht','Chawal','Daal Masoor','Daal Chana',
        'Masala','Namak','Hari Mirch','Adrak','Lehsan','Dhania','Pudina','Limu','Gobi','Matar','Palak',
        'Shaljam','Band Gobi','Phool Gobi','Kheera','Dahi','Doodh'
      ];
      final batch = FirebaseFirestore.instance.batch();
      for (var item in defaults) {
        final ref = FirebaseFirestore.instance
            .collection('branches')
            .doc(_branchId)
            .collection('dasterkhwaan_stock')
            .doc(item);
        batch.set(ref, {
          'name': item,
          'quantity': 0.0,
          'unit': 'kg',
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      final newSnap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId)
          .collection('dasterkhwaan_stock')
          .orderBy('name')
          .get();
      items = newSnap.docs.map((e) => StockItem.fromMap(e.data(), e.id)).toList();
    }

    setState(() {
      _allStockItems = items..sort((a, b) => a.name.compareTo(b.name));
      _stockLoaded = true;
    });
  }

  Future<void> _saveCustomStockItem(String name, String unit) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _allStockItems.any((item) => item.name == trimmed)) return;

    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan_stock')
        .doc(trimmed);
    await ref.set({
      'name': trimmed,
      'quantity': 0.0,
      'unit': unit,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    setState(() {
      _allStockItems.add(StockItem(id: trimmed, name: trimmed, unit: unit, lastUpdated: Timestamp.now()));
      _allStockItems.sort((a, b) => a.name.compareTo(b.name));
    });
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
    final index = _allStockItems.indexWhere((item) => item.name == itemName);
    if (index != -1) {
      setState(() {
        _allStockItems[index].quantity += delta;
        _allStockItems[index].lastUpdated = Timestamp.now();
      });
    }
  }

  CollectionReference<Map<String, dynamic>> purchasesCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('purchases')
          .withConverter(fromFirestore: (s, _) => s.data() ?? {}, toFirestore: (m, _) => m);

  CollectionReference<Map<String, dynamic>> servedCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('served')
          .withConverter(fromFirestore: (s, _) => s.data() ?? {}, toFirestore: (m, _) => m);

  CollectionReference<Map<String, dynamic>> wasteCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('waste')
          .withConverter(fromFirestore: (s, _) => s.data() ?? {}, toFirestore: (m, _) => m);

  CollectionReference<Map<String, dynamic>> tokensCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('tokens')
          .withConverter(fromFirestore: (s, _) => s.data() ?? {}, toFirestore: (m, _) => m);

  DocumentReference<Map<String, dynamic>> dayDoc(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .withConverter(fromFirestore: (s, _) => s.data() ?? {}, toFirestore: (m, _) => m);

  void _showAddPurchaseDialog({Map<String, dynamic>? existing, String? docId}) {
    final formKey = GlobalKey<FormState>();
    final itemController = TextEditingController(text: existing?['item'] ?? '');
    double qty = existing?['quantity'] ?? 1.0;
    String unit = existing?['unit'] ?? 'kg';

    const units = ['kg', 'gram', 'liter', 'piece', 'packet', 'bundle', 'bunch', 'handi', 'plate'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.kitchen, color: Colors.green.shade700),
            const SizedBox(width: 12),
            Text(existing == null ? "Add Purchase" : "Edit Purchase", style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_stockLoaded) LinearProgressIndicator(color: Colors.green.shade700),
              if (_stockLoaded)
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    return _allStockItems.where((StockItem option) {
                      return option.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    }).map((e) => e.name).take(10);
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    textEditingController.text = itemController.text;
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: "Select or Enter Item",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v?.trim().isEmpty ?? true ? "Required" : null,
                      onChanged: (v) => itemController.text = v,
                    );
                  },
                  onSelected: (String selection) {
                    itemController.text = selection;
                  },
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: qty.toString(),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()),
                      validator: (v) => v?.trim().isEmpty ?? true ? "Required" : null,
                      onSaved: (v) => qty = double.tryParse(v!) ?? 1.0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: "Unit", border: OutlineInputBorder()),
                      items: units.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => unit = v!,
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                String itemName = itemController.text.trim();
                if (itemName.isEmpty) return;

                if (!_allStockItems.any((item) => item.name == itemName)) {
                  await _saveCustomStockItem(itemName, unit);
                }

                final data = {
                  'item': itemName,
                  'quantity': qty,
                  'unit': unit,
                  'addedAt': FieldValue.serverTimestamp(),
                };

                if (existing != null && docId != null) {
                  final oldQty = existing['quantity'] as double;
                  await _updateStock(itemName, qty - oldQty);
                  await purchasesCol(today).doc(docId).update(data);
                } else {
                  await _updateStock(itemName, qty);
                  await purchasesCol(today).add(data);
                }

                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(existing == null ? "$qty $unit $itemName added" : "$itemName updated"), backgroundColor: Colors.green),
                );
              }
            },
            child: Text(existing == null ? "Add Item" : "Update Item"),
          ),
        ],
      ),
    );
  }

  void _showAddServedDialog({Map<String, dynamic>? existing, String? docId}) {
    final formKey = GlobalKey<FormState>();
    final itemController = TextEditingController(text: existing?['item'] ?? '');
    double qty = existing?['quantity'] ?? 1.0;
    String unit = existing?['unit'] ?? 'kg';

    const units = ['kg', 'gram', 'liter', 'piece', 'packet', 'bundle', 'bunch', 'handi', 'plate'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.restaurant, color: Colors.green.shade700),
            const SizedBox(width: 12),
            Text(existing == null ? "Add Served" : "Edit Served", style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_stockLoaded) LinearProgressIndicator(color: Colors.green.shade700),
              if (_stockLoaded)
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    return _allStockItems.where((StockItem option) {
                      return option.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    }).map((e) => e.name).take(10);
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    textEditingController.text = itemController.text;
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: "Select Item",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v?.trim().isEmpty ?? true ? "Required" : null,
                      onChanged: (v) => itemController.text = v,
                    );
                  },
                  onSelected: (String selection) {
                    itemController.text = selection;
                  },
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: qty.toString(),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()),
                      validator: (v) => v?.trim().isEmpty ?? true ? "Required" : null,
                      onSaved: (v) => qty = double.tryParse(v!) ?? 1.0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: "Unit", border: OutlineInputBorder()),
                      items: units.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => unit = v!,
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                String itemName = itemController.text.trim();
                if (itemName.isEmpty || !_allStockItems.any((item) => item.name == itemName)) return;

                final data = {
                  'item': itemName,
                  'quantity': qty,
                  'unit': unit,
                  'addedAt': FieldValue.serverTimestamp(),
                };

                if (existing != null && docId != null) {
                  final oldQty = existing['quantity'] as double;
                  await _updateStock(itemName, oldQty - qty);
                  await servedCol(today).doc(docId).update(data);
                } else {
                  await _updateStock(itemName, -qty);
                  await servedCol(today).add(data);
                }

                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(existing == null ? "$qty $unit $itemName served" : "$itemName updated"), backgroundColor: Colors.green),
                );
              }
            },
            child: Text(existing == null ? "Add Served" : "Update Served"),
          ),
        ],
      ),
    );
  }

  void _showAddWasteDialog({Map<String, dynamic>? existing, String? docId}) {
    final formKey = GlobalKey<FormState>();
    final itemController = TextEditingController(text: existing?['item'] ?? '');
    double qty = existing?['quantity'] ?? 1.0;
    String unit = existing?['unit'] ?? 'kg';
    String type = existing?['type'] ?? 'rotten';

    const units = ['kg', 'gram', 'liter', 'piece', 'packet', 'bundle', 'bunch', 'handi', 'plate'];
    const types = ['rotten', 'unused'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete, color: Colors.green.shade700),
            const SizedBox(width: 12),
            Text(existing == null ? "Add Waste" : "Edit Waste", style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_stockLoaded) LinearProgressIndicator(color: Colors.green.shade700),
              if (_stockLoaded)
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    return _allStockItems.where((StockItem option) {
                      return option.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    }).map((e) => e.name).take(10);
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    textEditingController.text = itemController.text;
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: "Select Item",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v?.trim().isEmpty ?? true ? "Required" : null,
                      onChanged: (v) => itemController.text = v,
                    );
                  },
                  onSelected: (String selection) {
                    itemController.text = selection;
                  },
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: qty.toString(),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()),
                      validator: (v) => v?.trim().isEmpty ?? true ? "Required" : null,
                      onSaved: (v) => qty = double.tryParse(v!) ?? 1.0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: "Unit", border: OutlineInputBorder()),
                      items: units.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => unit = v!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: "Type", border: OutlineInputBorder()),
                items: types.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => type = v!,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                String itemName = itemController.text.trim();
                if (itemName.isEmpty || !_allStockItems.any((item) => item.name == itemName)) return;

                final data = {
                  'item': itemName,
                  'quantity': qty,
                  'unit': unit,
                  'type': type,
                  'addedAt': FieldValue.serverTimestamp(),
                };

                if (existing != null && docId != null) {
                  final oldQty = existing['quantity'] as double;
                  await _updateStock(itemName, oldQty - qty);
                  await wasteCol(today).doc(docId).update(data);
                } else {
                  await _updateStock(itemName, -qty);
                  await wasteCol(today).add(data);
                }

                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(existing == null ? "$qty $unit $itemName $type" : "$itemName updated"), backgroundColor: Colors.green),
                );
              }
            },
            child: Text(existing == null ? "Add Waste" : "Update Waste"),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(String docId, String itemName, String colType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text("Are you sure you want to delete $itemName?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              CollectionReference col;
              if (colType == 'purchase') {
                col = purchasesCol(today);
              } else if (colType == 'served') {
                col = servedCol(today);
              } else {
                col = wasteCol(today);
              }
              final doc = await col.doc(docId).get();
              final data = doc.data() as Map<String, dynamic>;
              final qty = data['quantity'] as double;
              final delta = colType == 'purchase' ? -qty : qty;
              await _updateStock(data['item'], delta);
              await col.doc(docId).delete();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$itemName deleted"), backgroundColor: Colors.red),
              );
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showMenuDialog(String current) {
    _menuController.text = current == "No menu set" ? "" : current;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.green.shade700,
        title: const Text("Set Today's Menu", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _menuController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Beef Karahi, Daal, Chawal, Salad...",
            hintStyle: TextStyle(color: Colors.white70),
            border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              final text = _menuController.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Menu is required!"), backgroundColor: Colors.red),
                );
                return;
              }
              dayDoc(today).set({'menu': text}, SetOptions(merge: true));
              Navigator.pop(context);
            },
            child: const Text("Save Menu", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _serveToken(String tokenId, int tokenNumber) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Serve Token #$tokenNumber"),
        content: const Text("Confirm serving this token? This will deduct required stock."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final batch = FirebaseFirestore.instance.batch();
              final tokenRef = tokensCol(today).doc(tokenId);
              batch.update(tokenRef, {
                'served': true,
                'servedTime': FieldValue.serverTimestamp(),
              });
              final dayRef = dayDoc(today);
              batch.update(dayRef, {
                'servedTokens': FieldValue.increment(1),
              });
              for (final entry in requiredPerToken.entries) {
                final stockRef = FirebaseFirestore.instance
                    .collection('branches')
                    .doc(_branchId)
                    .collection('dasterkhwaan_stock')
                    .doc(entry.key);
                batch.update(stockRef, {
                  'quantity': FieldValue.increment(-entry.value),
                  'lastUpdated': FieldValue.serverTimestamp(),
                });
              }
              await batch.commit();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Token #$tokenNumber served and stock deducted"), backgroundColor: Colors.green),
              );
            },
            child: const Text("Serve"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_branchId == null) {
      return Scaffold(
        backgroundColor: Colors.green.shade700,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white, strokeWidth: 5),
              SizedBox(height: 20),
              Text("Loading Kitchen...", style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        elevation: 8,
        title: Row(
          children: [
            Image.asset('assets/logo/gmwf.png', height: 46),
            const SizedBox(width: 14),
            Text("Kitchen - $_username", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.red.shade700),
            onPressed: () => FirebaseAuth.instance.signOut().then((_) =>
                Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false)),
          ),
        ],
      ),

      floatingActionButton: _selectedIndex < 3
          ? FloatingActionButton.extended(
              backgroundColor: Colors.amber,
              onPressed: () {
                if (_selectedIndex == 0) _showAddPurchaseDialog();
                if (_selectedIndex == 1) _showAddServedDialog();
                if (_selectedIndex == 2) _showAddWasteDialog();
              },
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text("Add Entry", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          : null,

      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _DataTab(
            col: purchasesCol(today),
            title: 'Purchases',
            showAddDialog: _showAddPurchaseDialog,
            showDeleteConfirmDialog: (id, name) => _showDeleteConfirmDialog(id, name, 'purchase'),
            isWaste: false,
          ),
          _DataTab(
            col: servedCol(today),
            title: 'Served',
            showAddDialog: _showAddServedDialog,
            showDeleteConfirmDialog: (id, name) => _showDeleteConfirmDialog(id, name, 'served'),
            isWaste: false,
          ),
          _DataTab(
            col: wasteCol(today),
            title: 'Waste',
            showAddDialog: _showAddWasteDialog,
            showDeleteConfirmDialog: (id, name) => _showDeleteConfirmDialog(id, name, 'waste'),
            isWaste: true,
          ),
          _TokensTab(
            tokensCol: tokensCol(today),
            serveToken: _serveToken,
          ),
          _InventoryTab(
            branchId: _branchId!,
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('branches')
                .doc(_branchId)
                .collection('dasterkhwaan')
                .snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error loading history: ${snap.error}'));
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Center(child: Text("No history available"));
              }
              var docs = snap.data!.docs;
              docs.sort((a, b) => b.id.compareTo(a.id));
              docs = docs.take(30).toList();
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  return Card(
                    margin: const EdgeInsets.all(12),
                    child: ListTile(
                      leading: Icon(Icons.calendar_today, color: Colors.blue.shade700),
                      title: Text(displayFormat.format(dateFormat.parse(doc.id)), style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DailyDetailScreen(date: doc.id, branchId: _branchId!)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.white70,
        backgroundColor: Colors.green.shade700,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Purchases"),
          BottomNavigationBarItem(icon: Icon(Icons.restaurant), label: "Served"),
          BottomNavigationBarItem(icon: Icon(Icons.delete), label: "Waste"),
          BottomNavigationBarItem(icon: Icon(Icons.confirmation_number), label: "Tokens"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "Inventory"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "History"),
        ],
      ),
    );
  }
}

class _DataTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final String title;
  final void Function({Map<String, dynamic>? existing, String? docId}) showAddDialog;
  final Function(String, String) showDeleteConfirmDialog;
  final bool isWaste;

  const _DataTab({
    required this.col,
    required this.title,
    required this.showAddDialog,
    required this.showDeleteConfirmDialog,
    this.isWaste = false,
  });

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  final TextEditingController _searchController = TextEditingController();

  String _formatQuantity(double qty) {
    return qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Search items...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: widget.col.orderBy('addedAt', descending: true).snapshots(),
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              var docs = snapshot.data!.docs;

              if (_searchController.text.isNotEmpty) {
                final q = _searchController.text.toLowerCase();
                docs = docs.where((d) => (d['item'] as String).toLowerCase().contains(q)).toList();
              }

              if (docs.isEmpty) {
                return Center(child: Text("No ${widget.title.toLowerCase()} added", style: const TextStyle(fontSize: 18)));
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final e = docs[i].data() as Map<String, dynamic>;
                  final time = (e['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final qty = e['quantity'] as double;
                  final qtyStr = _formatQuantity(qty);
                  final subtitle = widget.isWaste ? "$qtyStr ${e['unit']} (${e['type']})" : "$qtyStr ${e['unit']}";
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber.shade100,
                        child: Icon(Icons.local_dining, color: Colors.brown),
                      ),
                      title: Text(e['item'], style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(subtitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateFormat('hh:mm a').format(time)),
                          IconButton(
                            icon: Icon(Icons.edit, color: Colors.blue.shade700),
                            onPressed: () => widget.showAddDialog(existing: e, docId: docs[i].id),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red.shade700),
                            onPressed: () => widget.showDeleteConfirmDialog(docs[i].id, e['item']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TokensTab extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> tokensCol;
  final Function(String, int) serveToken;

  const _TokensTab({required this.tokensCol, required this.serveToken});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: tokensCol.where('served', isEqualTo: false).orderBy('number').snapshots(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text("No active tokens", style: TextStyle(fontSize: 18)));
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final e = docs[i].data() as Map<String, dynamic>;
            final time = (e['time'] as Timestamp?)?.toDate() ?? DateTime.now();
            final number = e['number'] as int;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.confirmation_number, color: Colors.blue),
                ),
                title: Text('Token #$number', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(DateFormat('hh:mm a').format(time)),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () => serveToken(docs[i].id, number),
                  child: const Text('Serve'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _InventoryTab extends StatelessWidget {
  final String branchId;

  const _InventoryTab({required this.branchId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('dasterkhwaan_stock')
          .orderBy('name')
          .snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text("No inventory items"));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final stock = data['stock'] as double? ?? 0.0;
            final unit = data['unit'] as String? ?? 'kg';
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                title: Text(data['name']),
                subtitle: Text("$stock $unit"),
              ),
            );
          },
        );
      },
    );
  }
}

class DailyDetailScreen extends StatelessWidget {
  final String date;
  final String branchId;
  const DailyDetailScreen({required this.date, required this.branchId, super.key});

  String _formatQuantity(double qty) {
    return qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
  }

  @override
  Widget build(BuildContext context) {
    final displayFormat = DateFormat('dd MMM yyyy');
    final parsedDate = DateFormat('yyyy-MM-dd').parse(date);

    final purchasesCol = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('dasterkhwaan')
        .doc(date)
        .collection('purchases');

    final servedCol = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('dasterkhwaan')
        .doc(date)
        .collection('served');

    final wasteCol = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('dasterkhwaan')
        .doc(date)
        .collection('waste');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        title: Text("Details - ${displayFormat.format(parsedDate)}"),
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            TabBar(
              labelColor: Colors.green,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.green,
              tabs: const [Tab(text: "Purchases"), Tab(text: "Served"), Tab(text: "Waste")],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: purchasesCol.orderBy('addedAt', descending: true).snapshots(),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text("No purchases for this day"));
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final e = docs[i].data() as Map;
                          final qty = e['quantity'] as double;
                          final qtyStr = _formatQuantity(qty);
                          return ListTile(
                            leading: Icon(Icons.shopping_cart, color: Colors.orange.shade700),
                            title: Text(e['item'], style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text("$qtyStr ${e['unit']}"),
                          );
                        },
                      );
                    },
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: servedCol.orderBy('addedAt', descending: true).snapshots(),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text("No served for this day"));
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final e = docs[i].data() as Map;
                          final qty = e['quantity'] as double;
                          final qtyStr = _formatQuantity(qty);
                          return ListTile(
                            leading: Icon(Icons.restaurant, color: Colors.green),
                            title: Text(e['item'], style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text("$qtyStr ${e['unit']}"),
                          );
                        },
                      );
                    },
                  ),
                  StreamBuilder<QuerySnapshot>(
                    stream: wasteCol.orderBy('addedAt', descending: true).snapshots(),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text("No waste for this day"));
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final e = docs[i].data() as Map;
                          final qty = e['quantity'] as double;
                          final qtyStr = _formatQuantity(qty);
                          return ListTile(
                            leading: Icon(Icons.delete, color: Colors.red),
                            title: Text(e['item'], style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text("$qtyStr ${e['unit']} (${e['type']})"),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}