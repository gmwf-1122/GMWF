// lib/pages/dasterkhwaan/kitchen.dart
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

class _DasterkhwaanKitchenState extends State<DasterkhwaanKitchen>
    with SingleTickerProviderStateMixin {
  int _currentNav = 0;
  String _username = "Kitchen Staff";
  String? _branchId;
  final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat displayFormat = DateFormat('dd MMM yyyy');
  late final String today = dateFormat.format(DateTime.now());
  List<StockItem> _allStockItems = [];
  bool _stockLoaded = false;
  // Menu tracking
  String _currentMenu = "";
  Map<String, double> _menuIngredients = {};
  // Modern Color Palette - Professional Kitchen Theme
  static const Color _primary = Color(0xFF2C3E50);
  static const Color _primaryLight = Color(0xFF34495E);
  static const Color _accent = Color(0xFFE74C3C);
  static const Color _success = Color(0xFF27AE60);
  static const Color _warning = Color(0xFFF39C12);
  static const Color _info = Color(0xFF3498DB);
  static const Color _surface = Color(0xFFF8F9FA);
  static const Color _cardBg = Colors.white;
  static const Color _textDark = Color(0xFF2C3E50);
  static const Color _textLight = Color(0xFF95A5A6);
  // Default required ingredients per token (kg)
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
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;
  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeInOut,
    );
    _fabController.forward();
    _loadUserAndBranch();
  }
  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
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
              data['username'] ?? user.email?.split('@').first ?? "Kitchen Staff";
          _branchId = branch.id;
        });
        await _loadAllStockItems();
        await _loadTodayMenu();
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
        'Piyaz', 'Tamatar', 'Aloo', 'Ghee', 'Oil', 'Bara Gosht', 'Chota Gosht',
        'Chawal', 'Daal Masoor', 'Daal Chana', 'Masala', 'Namak', 'Hari Mirch',
        'Adrak', 'Lehsan', 'Dhania', 'Pudina', 'Limu', 'Gobi', 'Matar', 'Palak',
        'Shaljam', 'Band Gobi', 'Phool Gobi', 'Kheera', 'Dahi', 'Doodh'
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
  Future<void> _loadTodayMenu() async {
    if (_branchId == null) return;
    final doc = await dayDoc(today).get();
    final data = doc.data();
    if (data != null && data.containsKey('menu')) {
      setState(() {
        _currentMenu = data['menu'] as String;
      });
    }
    if (data != null && data.containsKey('menuIngredients')) {
      setState(() {
        _menuIngredients = Map<String, double>.from(
            data['menuIngredients'] as Map<dynamic, dynamic>);
      });
    }
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
  DocumentReference<Map<String, dynamic>> dayDoc(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date);
  CollectionReference<Map<String, dynamic>> tokensCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('tokens');
  CollectionReference<Map<String, dynamic>> wasteCol(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date)
          .collection('waste');
  Future<void> _serveToken(String tokenId, int tokenNumber) async {
    // Check if there's enough stock
    bool canServe = true;
    List<String> insufficientItems = [];
    for (final entry in requiredPerToken.entries) {
      final item = _allStockItems.firstWhere(
        (i) => i.name == entry.key,
        orElse: () => StockItem(
          id: '',
          name: entry.key,
          unit: 'kg',
          lastUpdated: Timestamp.now(),
        ),
      );
      if (item.quantity < entry.value) {
        canServe = false;
        insufficientItems.add(entry.key);
      }
    }
    if (!canServe) {
      _showSnack(
        "Cannot serve: Insufficient stock for ${insufficientItems.join(', ')}",
        isError: true,
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.restaurant_rounded, color: _success, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              "Serve Token #$tokenNumber",
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Required ingredients will be deducted:",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...requiredPerToken.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: TextStyle(color: _textLight)),
                    Text(
                      "-${e.value} kg",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              HapticFeedback.mediumImpact();
              final batch = FirebaseFirestore.instance.batch();
             
              // Mark token as served
              batch.update(tokensCol(today).doc(tokenId), {
                'served': true,
                'servedTime': FieldValue.serverTimestamp(),
              });
             
              // Update served count
              batch.update(dayDoc(today), {
                'servedTokens': FieldValue.increment(1),
              });
             
              // Deduct stock
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
              await _loadAllStockItems();
              _showSnack("Token #$tokenNumber served successfully ✓");
            },
            child: const Text(
              "Confirm Serve",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
  void _showMenuDialog() {
    final menuController = TextEditingController(text: _currentMenu);
    final ingredientsControllers = <String, TextEditingController>{};
    for (final key in requiredPerToken.keys) {
      ingredientsControllers[key] = TextEditingController(
        text: (_menuIngredients[key] ?? requiredPerToken[key]).toString(),
      );
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.restaurant_menu_rounded,
                                color: _warning,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Text(
                              "Today's Menu Setup",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Menu name
                        const Text(
                          "MENU NAME",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _textLight,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: menuController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: "e.g., Beef Karahi, Daal, Chawal, Salad",
                            filled: true,
                            fillColor: _surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: _warning, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          "INGREDIENTS PER TOKEN (kg)",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _textLight,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...ingredientsControllers.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: entry.value,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: _surface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _warning,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              final menu = menuController.text.trim();
                              final ingredients = <String, double>{};
                             
                              for (final entry in ingredientsControllers.entries) {
                                final value = double.tryParse(entry.value.text) ??
                                    requiredPerToken[entry.key]!;
                                ingredients[entry.key] = value;
                              }
                              dayDoc(today).set({
                                'menu': menu,
                                'menuIngredients': ingredients,
                              }, SetOptions(merge: true));
                              setState(() {
                                _currentMenu = menu;
                                _menuIngredients = ingredients;
                              });
                              Navigator.pop(context);
                              _showSnack("Menu updated successfully");
                            },
                            child: const Text(
                              "Save Menu",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  void _showAddWasteDialog({Map<String, dynamic>? existing, String? docId}) {
    final formKey = GlobalKey<FormState>();
    final itemController = TextEditingController(text: existing?['item'] ?? '');
    double qty = (existing?['quantity'] as double?) ?? 1.0;
    String unit = existing?['unit'] ?? 'kg';
    String type = existing?['type'] ?? 'rotten';
    String reason = existing?['reason'] ?? '';
    const units = ['kg', 'gram', 'liter', 'piece', 'packet', 'handi', 'plate'];
    const types = ['rotten', 'unused', 'overcooked', 'burnt', 'expired'];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: _accent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        existing == null ? "Record Waste" : "Edit Waste",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Item selector
                  if (!_stockLoaded)
                    const LinearProgressIndicator(color: _primary)
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
                      fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                        ctrl.text = itemController.text;
                        return TextFormField(
                          controller: ctrl,
                          focusNode: focus,
                          decoration: _inputDecoration(
                            label: "Item Name *",
                            icon: Icons.inventory_2_outlined,
                          ),
                          validator: (v) =>
                              v?.trim().isEmpty ?? true ? "Required" : null,
                          onChanged: (v) => itemController.text = v,
                        );
                      },
                      onSelected: (s) => itemController.text = s,
                    ),
                  const SizedBox(height: 16),
                  // Quantity and Unit
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: qty.toString(),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(
                            label: "Quantity",
                            icon: Icons.scale_rounded,
                          ),
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
                            label: "Unit",
                            icon: Icons.straighten,
                          ),
                          items: units
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setModalState(() => unit = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Type
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: _inputDecoration(
                      label: "Waste Type",
                      icon: Icons.category_rounded,
                    ),
                    items: types
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setModalState(() => type = v!),
                  ),
                  const SizedBox(height: 16),
                  // Reason
                  TextFormField(
                    initialValue: reason,
                    maxLines: 2,
                    decoration: _inputDecoration(
                      label: "Reason (optional)",
                      icon: Icons.notes_rounded,
                    ),
                    onSaved: (v) => reason = v ?? '',
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              fontSize: 15,
                              color: _textLight,
                            ),
                          ),
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
                            final data = {
                              'item': itemName,
                              'quantity': qty,
                              'unit': unit,
                              'type': type,
                              'reason': reason,
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
                            if (context.mounted) Navigator.pop(context);
                            _showSnack(
                              existing == null
                                  ? "Waste recorded: $qty $unit $itemName"
                                  : "Waste updated",
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            existing == null ? "Record Waste" : "Update",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  void _showDeleteWasteDialog(String docId, String itemName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: _accent),
            SizedBox(width: 8),
            Text(
              "Delete Waste?",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Text("Remove \"$itemName\" from waste records?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final doc = await wasteCol(today).doc(docId).get();
              final data = doc.data() as Map<String, dynamic>;
              final qty = data['quantity'] as double;
              await _updateStock(data['item'], qty);
              await wasteCol(today).doc(docId).delete();
              if (context.mounted) Navigator.pop(context);
              _showSnack("$itemName deleted", isError: true);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? _accent : _success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _primary, size: 20),
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 16,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (_branchId == null) {
      return const Scaffold(
        backgroundColor: _primary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
              SizedBox(height: 20),
              Text(
                "Loading Kitchen Panel...",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _surface,
      body: IndexedStack(
        index: _currentNav,
        children: [
          _TokensTab(
            branchId: _branchId!,
            today: today,
            tokensCol: tokensCol(today),
            serveToken: _serveToken,
            username: _username,
            onLogout: _logout,
          ),
          _InventoryTab(
            branchId: _branchId!,
            allStockItems: _allStockItems,
            stockLoaded: _stockLoaded,
            onRefresh: _loadAllStockItems,
            username: _username,
            onLogout: _logout,
          ),
          _WasteTab(
            wasteCol: wasteCol(today),
            onAddWaste: _showAddWasteDialog,
            onDeleteWaste: _showDeleteWasteDialog,
            username: _username,
            onLogout: _logout,
          ),
          _MenuTab(
            currentMenu: _currentMenu,
            menuIngredients: _menuIngredients,
            requiredPerToken: requiredPerToken,
            onEditMenu: _showMenuDialog,
            username: _username,
            onLogout: _logout,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }
  Widget _buildBottomNav() {
    final items = [
      _NavItem(
        icon: Icons.confirmation_number_rounded,
        label: "Tokens",
        color: _success,
      ),
      _NavItem(
        icon: Icons.inventory_2_rounded,
        label: "Inventory",
        color: _info,
      ),
      _NavItem(
        icon: Icons.delete_outline_rounded,
        label: "Waste",
        color: _accent,
      ),
      _NavItem(
        icon: Icons.restaurant_menu_rounded,
        label: "Menu",
        color: _warning,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (idx) {
              final item = items[idx];
              final selected = _currentNav == idx;
              return GestureDetector(
                onTap: () {
                  setState(() => _currentNav = idx);
                  HapticFeedback.selectionClick();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? item.color.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: selected ? item.color : _textLight,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected ? item.color : _textLight,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.color,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// TOKENS TAB
// ═════════════════════════════════════════════════════════════════════════════
class _TokensTab extends StatelessWidget {
  final String branchId;
  final String today;
  final CollectionReference<Map<String, dynamic>> tokensCol;
  final Function(String, int) serveToken;
  final String username;
  final VoidCallback onLogout;
  const _TokensTab({
    required this.branchId,
    required this.today,
    required this.tokensCol,
    required this.serveToken,
    required this.username,
    required this.onLogout,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        _buildHeader(context),
        // Content
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: tokensCol
                .where('served', isEqualTo: false)
                .orderBy('number')
                .snapshots(),
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF27AE60),
                    strokeWidth: 2,
                  ),
                );
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
                      Icon(
                        Icons.check_circle_outline,
                        size: 80,
                        color: const Color(0xFF27AE60).withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "All tokens served!",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF95A5A6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "No pending tokens",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF95A5A6),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final e = docs[i].data() as Map<String, dynamic>;
                  final time = (e['time'] as Timestamp?)?.toDate() ?? DateTime.now();
                  final number = e['number'] as int;
                  return _TokenCard(
                    number: number,
                    time: time,
                    onServe: () => serveToken(docs[i].id, number),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF27AE60), Color(0xFF229954)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Active Tokens",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        username,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: onLogout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE74C3C),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            "Logout",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .doc(branchId)
                    .collection('dasterkhwaan')
                    .doc(today)
                    .collection('tokens')
                    .snapshots(),
                builder: (_, snap) {
                  final allTokens = snap.data?.docs ?? [];
                  final pending = allTokens
                      .where((d) => (d.data() as Map)['served'] == false)
                      .length;
                  final served = allTokens.length - pending;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatBadge(
                          icon: Icons.hourglass_top_rounded,
                          label: "Pending",
                          value: "$pending",
                          color: const Color(0xFFFFD54F),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        _StatBadge(
                          icon: Icons.check_circle_rounded,
                          label: "Served",
                          value: "$served",
                          color: const Color(0xFF81C784),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TokenCard extends StatelessWidget {
  final int number;
  final DateTime time;
  final VoidCallback onServe;
  const _TokenCard({
    required this.number,
    required this.time,
    required this.onServe,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF27AE60).withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Token number badge
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF27AE60), Color(0xFF229954)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  "#$number",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Token Ready",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: const Color(0xFF95A5A6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('hh:mm a').format(time),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF95A5A6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Serve button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: onServe,
              child: const Text(
                "Serve",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// INVENTORY TAB
// ═════════════════════════════════════════════════════════════════════════════
class _InventoryTab extends StatefulWidget {
  final String branchId;
  final List<StockItem> allStockItems;
  final bool stockLoaded;
  final VoidCallback onRefresh;
  final String username;
  final VoidCallback onLogout;
  const _InventoryTab({
    required this.branchId,
    required this.allStockItems,
    required this.stockLoaded,
    required this.onRefresh,
    required this.username,
    required this.onLogout,
  });
  @override
  State<_InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<_InventoryTab> {
  final TextEditingController _searchController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final filtered = _searchController.text.isEmpty
        ? widget.allStockItems
        : widget.allStockItems
            .where((i) => i.name
                .toLowerCase()
                .contains(_searchController.text.toLowerCase()))
            .toList();
    final lowStock = widget.allStockItems.where((i) => i.quantity <= 2).length;
    final criticalStock = widget.allStockItems.where((i) => i.quantity == 0).length;
    return Column(
      children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3498DB), Color(0xFF2980B9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Inventory",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            "${widget.allStockItems.length} items in stock",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: widget.onLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE74C3C),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.logout_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                "Logout",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.warning_rounded,
                                color: const Color(0xFFFFD54F),
                                size: 20,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "$lowStock",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                "Low Stock",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.error_rounded,
                                color: const Color(0xFFEF5350),
                                size: 20,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "$criticalStock",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                "Out of Stock",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Search inventory...",
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF95A5A6),
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
            ),
          ),
        ),
        // Content
        Expanded(
          child: widget.stockLoaded
              ? (filtered.isEmpty
                  ? const Center(
                      child: Text(
                        "No items found",
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF95A5A6),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => widget.onRefresh(),
                      color: const Color(0xFF3498DB),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          final isLow = item.quantity <= 2;
                          final isCritical = item.quantity == 0;
                          return _InventoryCard(
                            item: item,
                            isLow: isLow,
                            isCritical: isCritical,
                          );
                        },
                      ),
                    ))
              : const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF3498DB),
                    strokeWidth: 2,
                  ),
                ),
        ),
      ],
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final StockItem item;
  final bool isLow;
  final bool isCritical;
  const _InventoryCard({
    required this.item,
    required this.isLow,
    required this.isCritical,
  });
  @override
  Widget build(BuildContext context) {
    Color statusColor = const Color(0xFF27AE60);
    IconData statusIcon = Icons.check_circle_rounded;
    String statusText = "Good";
    if (isCritical) {
      statusColor = const Color(0xFFE74C3C);
      statusIcon = Icons.error_rounded;
      statusText = "Out";
    } else if (isLow) {
      statusColor = const Color(0xFFF39C12);
      statusIcon = Icons.warning_rounded;
      statusText = "Low";
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCritical || isLow
              ? statusColor.withOpacity(0.3)
              : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                statusIcon,
                color: statusColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Updated ${DateFormat('dd MMM, hh:mm a').format(item.lastUpdated.toDate())}",
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF95A5A6),
                    ),
                  ),
                ],
              ),
            ),
            // Quantity and status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    "${item.quantity} ${item.unit}",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WASTE TAB
// ═════════════════════════════════════════════════════════════════════════════
class _WasteTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> wasteCol;
  final void Function({Map<String, dynamic>? existing, String? docId})
      onAddWaste;
  final Function(String, String) onDeleteWaste;
  final String username;
  final VoidCallback onLogout;
  const _WasteTab({
    required this.wasteCol,
    required this.onAddWaste,
    required this.onDeleteWaste,
    required this.username,
    required this.onLogout,
  });
  @override
  State<_WasteTab> createState() => _WasteTabState();
}

class _WasteTabState extends State<_WasteTab> {
  final TextEditingController _searchController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Waste Tracking",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            "Monitor & reduce waste",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: widget.onLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C3E50),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.logout_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                "Logout",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "Search waste records...",
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF95A5A6),
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
            ),
          ),
        ),
        // Content
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: widget.wasteCol.orderBy('addedAt', descending: true).snapshots(),
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFE74C3C),
                    strokeWidth: 2,
                  ),
                );
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
                      Icon(
                        Icons.recycling_rounded,
                        size: 80,
                        color: const Color(0xFFE74C3C).withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "No waste recorded",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF95A5A6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Keep up the good work!",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF95A5A6),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final e = docs[i].data() as Map<String, dynamic>;
                  final time =
                      (e['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                  return _WasteCard(
                    item: e['item'],
                    quantity: e['quantity'] as double,
                    unit: e['unit'],
                    type: e['type'],
                    reason: e['reason'] ?? '',
                    time: time,
                    onEdit: () => widget.onAddWaste(
                      existing: e,
                      docId: docs[i].id,
                    ),
                    onDelete: () => widget.onDeleteWaste(docs[i].id, e['item']),
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

class _WasteCard extends StatelessWidget {
  final String item;
  final double quantity;
  final String unit;
  final String type;
  final String reason;
  final DateTime time;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _WasteCard({
    required this.item,
    required this.quantity,
    required this.unit,
    required this.type,
    required this.reason,
    required this.time,
    required this.onEdit,
    required this.onDelete,
  });
  String _fmt(double qty) =>
      qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
  @override
  Widget build(BuildContext context) {
    Color typeColor = const Color(0xFFE74C3C);
    IconData typeIcon = Icons.dangerous_rounded;
    if (type == 'unused') {
      typeColor = const Color(0xFFF39C12);
      typeIcon = Icons.remove_circle_outline_rounded;
    } else if (type == 'expired') {
      typeColor = const Color(0xFF9B59B6);
      typeIcon = Icons.event_busy_rounded;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: typeColor.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: typeColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${_fmt(quantity)} $unit • $type",
                        style: TextStyle(
                          fontSize: 12,
                          color: typeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: Color(0xFF3498DB),
                      ),
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_rounded,
                        size: 18,
                        color: Color(0xFFE74C3C),
                      ),
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: Color(0xFF95A5A6),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF95A5A6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              DateFormat('hh:mm a · dd MMM').format(time),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF95A5A6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MENU TAB
// ═════════════════════════════════════════════════════════════════════════════
class _MenuTab extends StatelessWidget {
  final String currentMenu;
  final Map<String, double> menuIngredients;
  final Map<String, double> requiredPerToken;
  final VoidCallback onEditMenu;
  final String username;
  final VoidCallback onLogout;
  const _MenuTab({
    required this.currentMenu,
    required this.menuIngredients,
    required this.requiredPerToken,
    required this.onEditMenu,
    required this.username,
    required this.onLogout,
  });
  @override
  Widget build(BuildContext context) {
    final activeIngredients = menuIngredients.isNotEmpty
        ? menuIngredients
        : requiredPerToken;
    return Column(
      children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF39C12), Color(0xFFE67E22)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Today's Menu",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            DateFormat('EEE, dd MMM').format(DateTime.now()),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: onLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE74C3C),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.logout_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                "Logout",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Menu card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF39C12).withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF39C12).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.restaurant_menu_rounded,
                                  color: Color(0xFFF39C12),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                "Menu",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF2C3E50),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: onEditMenu,
                            icon: const Icon(
                              Icons.edit_rounded,
                              color: Color(0xFFF39C12),
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        currentMenu.isEmpty
                            ? "No menu set for today"
                            : currentMenu,
                        style: TextStyle(
                          fontSize: 15,
                          color: currentMenu.isEmpty
                              ? const Color(0xFF95A5A6)
                              : const Color(0xFF2C3E50),
                          fontWeight: currentMenu.isEmpty
                              ? FontWeight.w500
                              : FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Ingredients section
                const Text(
                  "INGREDIENTS PER TOKEN",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF95A5A6),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                ...activeIngredients.entries.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF39C12),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "${entry.value} kg",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF39C12),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 20),
                // Info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9E6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFF39C12).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFF39C12),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "These quantities are automatically deducted when a token is served",
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFFF39C12).withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}