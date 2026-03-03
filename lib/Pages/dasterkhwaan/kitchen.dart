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

  // Palette
  static const Color _primary = Color(0xFF1B5E20);
  static const Color _primaryLight = Color(0xFF2E7D32);
  static const Color _accent = Color(0xFFF9A825);
  static const Color _surface = Color(0xFFF1F8E9);

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
    final branches =
        await FirebaseFirestore.instance.collection('branches').get();
    for (final branch in branches.docs) {
      final doc =
          await branch.reference.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _username =
              data['username'] ?? user.email?.split('@').first ?? "User";
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

    List<StockItem> items =
        snapshot.docs.map((e) => StockItem.fromMap(e.data(), e.id)).toList();

    if (items.isEmpty) {
      const defaults = [
        'Piyaz','Tamatar','Aloo','Ghee','Oil','Bara Gosht','Chota Gosht',
        'Chawal','Daal Masoor','Daal Chana','Masala','Namak','Hari Mirch',
        'Adrak','Lehsan','Dhania','Pudina','Limu','Gobi','Matar','Palak',
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
      items =
          newSnap.docs.map((e) => StockItem.fromMap(e.data(), e.id)).toList();
    }

    setState(() {
      _allStockItems = items..sort((a, b) => a.name.compareTo(b.name));
      _stockLoaded = true;
    });
  }

  Future<void> _saveCustomStockItem(String name, String unit) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _allStockItems.any((item) => item.name == trimmed))
      return;
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
      _allStockItems
          .add(StockItem(id: trimmed, name: trimmed, unit: unit, lastUpdated: Timestamp.now()));
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
          .withConverter(
              fromFirestore: (s, _) => s.data() ?? {},
              toFirestore: (m, _) => m);

  CollectionReference<Map<String, dynamic>> servedCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('served')
          .withConverter(
              fromFirestore: (s, _) => s.data() ?? {},
              toFirestore: (m, _) => m);

  CollectionReference<Map<String, dynamic>> wasteCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('waste')
          .withConverter(
              fromFirestore: (s, _) => s.data() ?? {},
              toFirestore: (m, _) => m);

  CollectionReference<Map<String, dynamic>> tokensCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('tokens')
          .withConverter(
              fromFirestore: (s, _) => s.data() ?? {},
              toFirestore: (m, _) => m);

  DocumentReference<Map<String, dynamic>> dayDoc(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .withConverter(
              fromFirestore: (s, _) => s.data() ?? {},
              toFirestore: (m, _) => m);

  // ── Dialogs ──────────────────────────────────────────────────────────────

  void _showAddPurchaseDialog(
      {Map<String, dynamic>? existing, String? docId}) {
    _showItemDialog(
      title: existing == null ? "Add Purchase" : "Edit Purchase",
      icon: Icons.shopping_cart_rounded,
      iconColor: const Color(0xFF1565C0),
      existing: existing,
      docId: docId,
      withType: false,
      onSave: (itemName, qty, unit, _) async {
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
        if (mounted) {
          _showSnack(existing == null
              ? "$qty $unit $itemName added"
              : "$itemName updated");
        }
      },
    );
  }

  void _showAddServedDialog({Map<String, dynamic>? existing, String? docId}) {
    _showItemDialog(
      title: existing == null ? "Add Served" : "Edit Served",
      icon: Icons.restaurant_rounded,
      iconColor: const Color(0xFF2E7D32),
      existing: existing,
      docId: docId,
      withType: false,
      stockOnly: true,
      onSave: (itemName, qty, unit, _) async {
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
        if (mounted) {
          _showSnack(existing == null
              ? "$qty $unit $itemName served"
              : "$itemName updated");
        }
      },
    );
  }

  void _showAddWasteDialog({Map<String, dynamic>? existing, String? docId}) {
    _showItemDialog(
      title: existing == null ? "Add Waste" : "Edit Waste",
      icon: Icons.delete_rounded,
      iconColor: const Color(0xFFB71C1C),
      existing: existing,
      docId: docId,
      withType: true,
      stockOnly: true,
      onSave: (itemName, qty, unit, type) async {
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
        if (mounted) {
          _showSnack(existing == null
              ? "$qty $unit $itemName ($type)"
              : "$itemName updated");
        }
      },
    );
  }

  void _showItemDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    Map<String, dynamic>? existing,
    String? docId,
    required bool withType,
    bool stockOnly = false,
    required Future<void> Function(
            String itemName, double qty, String unit, String type)
        onSave,
  }) {
    final formKey = GlobalKey<FormState>();
    final itemController =
        TextEditingController(text: existing?['item'] ?? '');
    double qty = (existing?['quantity'] as double?) ?? 1.0;
    String unit = existing?['unit'] ?? 'kg';
    String type = existing?['type'] ?? 'rotten';

    const units = [
      'kg','gram','liter','piece','packet','bundle','bunch','handi','plate'
    ];
    const types = ['rotten', 'unused'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  // Title
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: iconColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 20),

                  if (!_stockLoaded)
                    LinearProgressIndicator(color: _primary)
                  else
                    Autocomplete<String>(
                      optionsBuilder: (v) {
                        if (v.text.isEmpty) return const [];
                        return _allStockItems
                            .where((i) => i.name
                                .toLowerCase()
                                .contains(v.text.toLowerCase()))
                            .map((e) => e.name)
                            .take(8);
                      },
                      fieldViewBuilder:
                          (context, ctrl, focus, onSubmit) {
                        ctrl.text = itemController.text;
                        return TextFormField(
                          controller: ctrl,
                          focusNode: focus,
                          decoration: _inputDecoration(
                              label: stockOnly
                                  ? "Select Item *"
                                  : "Item Name *",
                              icon: Icons.search),
                          validator: (v) =>
                              v?.trim().isEmpty ?? true ? "Required" : null,
                          onChanged: (v) => itemController.text = v,
                        );
                      },
                      onSelected: (s) => itemController.text = s,
                    ),

                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: qty.toString(),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            _inputDecoration(label: "Quantity", icon: Icons.scale),
                        validator: (v) =>
                            v?.trim().isEmpty ?? true ? "Required" : null,
                        onSaved: (v) => qty = double.tryParse(v!) ?? 1.0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: unit,
                        decoration: _inputDecoration(
                            label: "Unit", icon: Icons.straighten),
                        items: units
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) => setModalState(() => unit = v!),
                      ),
                    ),
                  ]),

                  if (withType) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration:
                          _inputDecoration(label: "Type", icon: Icons.category),
                      items: types
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setModalState(() => type = v!),
                    ),
                  ],

                  const SizedBox(height: 20),

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
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          formKey.currentState!.save();
                          final itemName = itemController.text.trim();
                          if (itemName.isEmpty) return;
                          if (!stockOnly &&
                              !_allStockItems
                                  .any((i) => i.name == itemName)) {
                            await _saveCustomStockItem(itemName, unit);
                          }
                          await onSave(itemName, qty, unit, type);
                          if (context.mounted) Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: iconColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          existing == null ? "Add" : "Update",
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
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

  InputDecoration _inputDecoration(
      {required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _primary, size: 20),
      filled: true,
      fillColor: const Color(0xFFF1F8E9),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );
  }

  void _showDeleteConfirmDialog(
      String docId, String itemName, String colType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: Color(0xFFB71C1C)),
          SizedBox(width: 8),
          Text("Delete?",
              style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        content: Text("Remove \"$itemName\" from $colType?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              CollectionReference col = colType == 'purchase'
                  ? purchasesCol(today)
                  : colType == 'served'
                      ? servedCol(today)
                      : wasteCol(today);
              final doc = await col.doc(docId).get();
              final data = doc.data() as Map<String, dynamic>;
              final qty = data['quantity'] as double;
              final delta = colType == 'purchase' ? -qty : qty;
              await _updateStock(data['item'], delta);
              await col.doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
              _showSnack("$itemName deleted", isError: true);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showMenuDialog(String current) {
    _menuController.text = current == "No menu set" ? "" : current;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white38,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Icon(Icons.restaurant_menu_rounded,
                    color: Color(0xFFF9A825), size: 26),
                const SizedBox(width: 10),
                const Text("Today's Menu",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: _menuController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: "e.g. Beef Karahi, Daal, Chawal, Salad...",
                  hintStyle:
                      const TextStyle(color: Colors.white54, fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: Color(0xFFF9A825), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF9A825),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    final text = _menuController.text.trim();
                    if (text.isEmpty) return;
                    dayDoc(today)
                        .set({'menu': text}, SetOptions(merge: true));
                    Navigator.pop(context);
                  },
                  child: const Text("Save Menu",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _serveToken(String tokenId, int tokenNumber) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Serve Ticket #$tokenNumber",
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
            "Confirm serving? Required stock will be deducted automatically."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _primaryLight,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              Navigator.pop(context);
              final batch = FirebaseFirestore.instance.batch();
              batch.update(tokensCol(today).doc(tokenId), {
                'served': true,
                'servedTime': FieldValue.serverTimestamp(),
              });
              batch.update(dayDoc(today), {
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
              _showSnack("Ticket #$tokenNumber served ✓");
            },
            child: const Text("Confirm Serve"),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
      backgroundColor: isError ? const Color(0xFFB71C1C) : _primaryLight,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_branchId == null) {
      return Scaffold(
        backgroundColor: _primary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                  color: Color(0xFFF9A825), strokeWidth: 3),
              const SizedBox(height: 20),
              Text("Loading Kitchen...",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.9), fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // ── 6 tabs (Donations removed) ─────────────────────────────────────────
    final tabs = [
      _KitchenTab(label: "Purchases", icon: Icons.shopping_cart_rounded,       color: const Color(0xFF1565C0)),
      _KitchenTab(label: "Served",    icon: Icons.restaurant_rounded,          color: const Color(0xFF2E7D32)),
      _KitchenTab(label: "Waste",     icon: Icons.delete_outline_rounded,      color: const Color(0xFFB71C1C)),
      _KitchenTab(label: "Tickets",   icon: Icons.confirmation_number_rounded, color: const Color(0xFFE65100)),
      _KitchenTab(label: "Inventory", icon: Icons.inventory_2_rounded,         color: const Color(0xFF6A1B9A)),
      _KitchenTab(label: "History",   icon: Icons.history_rounded,             color: const Color(0xFF37474F)),
    ];

    return Scaffold(
      backgroundColor: _surface,
      body: Column(
        children: [
          // Top bar
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Row(
                      children: [
                        Image.asset('assets/logo/gmwf.png',
                            height: 40,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.restaurant,
                                color: Colors.white70,
                                size: 36)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Kitchen Panel",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              Text(_username,
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        // Menu button
                        StreamBuilder<DocumentSnapshot>(
                          stream: dayDoc(today).snapshots(),
                          builder: (_, snap) {
                            final menu = (snap.data?.data()
                                    as Map<String, dynamic>?)?['menu'] as String? ??
                                "No menu set";
                            return TextButton.icon(
                              onPressed: () => _showMenuDialog(menu),
                              icon: const Icon(Icons.restaurant_menu,
                                  color: Color(0xFFF9A825), size: 18),
                              label: const Text("Menu",
                                  style: TextStyle(
                                      color: Color(0xFFF9A825),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout_rounded,
                              color: Color(0xFFFF8A65)),
                          onPressed: () =>
                              FirebaseAuth.instance.signOut().then((_) =>
                                  Navigator.pushNamedAndRemoveUntil(
                                      context, '/login', (_) => false)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tab bar
                  SizedBox(
                    height: 72,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: tabs.length,
                      itemBuilder: (_, i) {
                        final t = tabs[i];
                        final sel = _selectedIndex == i;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8, bottom: 12),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: sel
                                      ? t.color
                                      : Colors.transparent,
                                  width: 1.5),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(t.icon,
                                    color: sel ? t.color : Colors.white70,
                                    size: 20),
                                const SizedBox(height: 4),
                                Text(t.label,
                                    style: TextStyle(
                                        color:
                                            sel ? t.color : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: sel
                                            ? FontWeight.w800
                                            : FontWeight.w500)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _DataTab(
                  col: purchasesCol(today),
                  title: 'Purchases',
                  accentColor: const Color(0xFF1565C0),
                  showAddDialog: _showAddPurchaseDialog,
                  showDeleteDialog: (id, name) =>
                      _showDeleteConfirmDialog(id, name, 'purchase'),
                  isWaste: false,
                ),
                _DataTab(
                  col: servedCol(today),
                  title: 'Served Items',
                  accentColor: const Color(0xFF2E7D32),
                  showAddDialog: _showAddServedDialog,
                  showDeleteDialog: (id, name) =>
                      _showDeleteConfirmDialog(id, name, 'served'),
                  isWaste: false,
                ),
                _DataTab(
                  col: wasteCol(today),
                  title: 'Waste',
                  accentColor: const Color(0xFFB71C1C),
                  showAddDialog: _showAddWasteDialog,
                  showDeleteDialog: (id, name) =>
                      _showDeleteConfirmDialog(id, name, 'waste'),
                  isWaste: true,
                ),
                _TokensTab(
                  tokensCol: tokensCol(today),
                  serveToken: _serveToken,
                ),
                _InventoryTab(branchId: _branchId!),
                _HistoryTab(
                  branchId: _branchId!,
                  dateFormat: dateFormat,
                  displayFormat: displayFormat,
                ),
              ],
            ),
          ),
        ],
      ),

      floatingActionButton: _selectedIndex < 3
          ? FloatingActionButton.extended(
              backgroundColor: _accent,
              foregroundColor: Colors.black87,
              onPressed: () {
                if (_selectedIndex == 0) _showAddPurchaseDialog();
                if (_selectedIndex == 1) _showAddServedDialog();
                if (_selectedIndex == 2) _showAddWasteDialog();
              },
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text("Add Entry",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              elevation: 4,
            )
          : null,
    );
  }
}

class _KitchenTab {
  final String label;
  final IconData icon;
  final Color color;
  const _KitchenTab(
      {required this.label, required this.icon, required this.color});
}

// ── Data Tab ──────────────────────────────────────────────────────────────────

class _DataTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final String title;
  final Color accentColor;
  final void Function({Map<String, dynamic>? existing, String? docId})
      showAddDialog;
  final Function(String, String) showDeleteDialog;
  final bool isWaste;

  const _DataTab({
    required this.col,
    required this.title,
    required this.accentColor,
    required this.showAddDialog,
    required this.showDeleteDialog,
    this.isWaste = false,
  });

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  final TextEditingController _searchController = TextEditingController();

  String _fmt(double qty) =>
      qty == qty.toInt() ? qty.toInt().toString() : qty.toString();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Search ${widget.title.toLowerCase()}...",
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
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: widget.col.orderBy('addedAt', descending: true).snapshots(),
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF1B5E20), strokeWidth: 2));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              var docs = snapshot.data!.docs;
              if (_searchController.text.isNotEmpty) {
                final q = _searchController.text.toLowerCase();
                docs = docs
                    .where((d) =>
                        (d['item'] as String).toLowerCase().contains(q))
                    .toList();
              }
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 64,
                          color:
                              widget.accentColor.withOpacity(0.25)),
                      const SizedBox(height: 12),
                      Text("No ${widget.title.toLowerCase()} yet",
                          style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final e = docs[i].data() as Map<String, dynamic>;
                  final time =
                      (e['addedAt'] as Timestamp?)?.toDate() ??
                          DateTime.now();
                  final qty = e['quantity'] as double;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.fromLTRB(14, 6, 8, 6),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: widget.accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.local_dining_rounded,
                            color: widget.accentColor, size: 20),
                      ),
                      title: Text(e['item'],
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      subtitle: Text(
                        widget.isWaste
                            ? "${_fmt(qty)} ${e['unit']} • ${e['type']}"
                            : "${_fmt(qty)} ${e['unit']}",
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateFormat('hh:mm a').format(time),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500])),
                          IconButton(
                            icon: Icon(Icons.edit_rounded,
                                color: const Color(0xFF1565C0),
                                size: 18),
                            onPressed: () => widget.showAddDialog(
                                existing: e, docId: docs[i].id),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_rounded,
                                color: Colors.red.shade400, size: 18),
                            onPressed: () =>
                                widget.showDeleteDialog(docs[i].id, e['item']),
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

// ── Tokens Tab ────────────────────────────────────────────────────────────────

class _TokensTab extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> tokensCol;
  final Function(String, int) serveToken;

  const _TokensTab({required this.tokensCol, required this.serveToken});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          tokensCol.where('served', isEqualTo: false).orderBy('number').snapshots(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF1B5E20), strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.confirmation_number_outlined,
                    size: 72, color: Colors.orange.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text("No active tickets",
                    style: TextStyle(color: Colors.grey[500], fontSize: 16)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final e = docs[i].data() as Map<String, dynamic>;
            final time =
                (e['time'] as Timestamp?)?.toDate() ?? DateTime.now();
            final number = e['number'] as int;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.orange.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
                border: Border.all(
                    color: Colors.orange.withOpacity(0.2), width: 1),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.fromLTRB(16, 8, 12, 8),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFE65100), Color(0xFFF57C00)]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text("#$number",
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14)),
                  ),
                ),
                title: Text("Ticket #$number",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                subtitle: Text(DateFormat('hh:mm a').format(time),
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 12)),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    elevation: 0,
                  ),
                  onPressed: () => serveToken(docs[i].id, number),
                  child: const Text("Serve",
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Inventory Tab ─────────────────────────────────────────────────────────────

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
          return const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF1B5E20), strokeWidth: 2));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text("No inventory items"));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final stock = data['quantity'] as double? ?? 0.0;
            final unit = data['unit'] as String? ?? 'kg';
            final isLow = stock <= 2;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isLow
                        ? Colors.red.withOpacity(0.3)
                        : Colors.transparent),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isLow
                        ? Colors.red.withOpacity(0.1)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      isLow
                          ? Icons.warning_rounded
                          : Icons.inventory_2_outlined,
                      color: isLow
                          ? Colors.red.shade400
                          : const Color(0xFF2E7D32),
                      size: 20),
                ),
                title: Text(data['name'],
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLow
                        ? Colors.red.withOpacity(0.1)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "$stock $unit",
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isLow
                            ? Colors.red.shade600
                            : const Color(0xFF2E7D32),
                        fontSize: 13),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── History Tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final String branchId;
  final DateFormat dateFormat;
  final DateFormat displayFormat;

  const _HistoryTab({
    required this.branchId,
    required this.dateFormat,
    required this.displayFormat,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('dasterkhwaan')
          .snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF1B5E20), strokeWidth: 2));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text("No history available"));
        }
        var docs = snap.data!.docs
          ..sort((a, b) => b.id.compareTo(a.id));
        docs = docs.take(30).toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final total = data['totalTokens'] as int? ?? 0;
            final served = data['servedTokens'] as int? ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.fromLTRB(16, 10, 12, 10),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calendar_today_rounded,
                      color: Color(0xFF2E7D32), size: 20),
                ),
                title: Text(displayFormat.format(dateFormat.parse(doc.id)),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                subtitle: Text(
                  "$total tickets • $served served",
                  style:
                      TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Colors.grey),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyDetailScreen(
                        date: doc.id, branchId: branchId),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Daily Detail Screen ───────────────────────────────────────────────────────

class DailyDetailScreen extends StatelessWidget {
  final String date;
  final String branchId;
  const DailyDetailScreen(
      {required this.date, required this.branchId, super.key});

  String _fmt(double qty) =>
      qty == qty.toInt() ? qty.toInt().toString() : qty.toString();

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
    final base = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('dasterkhwaan')
        .doc(date);

    final tabs = [
      {'label': 'Purchases', 'col': base.collection('purchases'), 'icon': Icons.shopping_cart_rounded, 'color': const Color(0xFF1565C0)},
      {'label': 'Served', 'col': base.collection('served'), 'icon': Icons.restaurant_rounded, 'color': const Color(0xFF2E7D32)},
      {'label': 'Waste', 'col': base.collection('waste'), 'icon': Icons.delete_rounded, 'color': const Color(0xFFB71C1C)},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          DateFormat('dd MMM yyyy').format(parsedDate),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Container(
              color: const Color(0xFF2E7D32),
              child: TabBar(
                indicatorColor: const Color(0xFFF9A825),
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12),
                tabs: tabs
                    .map((t) => Tab(
                          icon: Icon(t['icon'] as IconData, size: 18),
                          text: t['label'] as String,
                        ))
                    .toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: tabs.map((t) {
                  final col = t['col'] as CollectionReference;
                  final color = t['color'] as Color;
                  return StreamBuilder<QuerySnapshot>(
                    stream: col
                        .orderBy('addedAt', descending: true)
                        .snapshots(),
                    builder: (_, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF1B5E20), strokeWidth: 2));
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text("No ${t['label'].toString().toLowerCase()} recorded",
                              style: TextStyle(color: Colors.grey[500])),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final e = docs[i].data() as Map;
                          final qty = e['quantity'] as double;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                                child: Icon(t['icon'] as IconData,
                                    color: color, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(e['item'],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14)),
                                    Text(
                                      e.containsKey('type')
                                          ? "${_fmt(qty)} ${e['unit']} • ${e['type']}"
                                          : "${_fmt(qty)} ${e['unit']}",
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ]),
                          );
                        },
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}