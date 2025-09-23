// lib/pages/inventory.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inventory.dart';

class InventoryPage extends StatefulWidget {
  final String branchId;

  const InventoryPage({super.key, required this.branchId});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _serialController = TextEditingController();
  final _batchController = TextEditingController();
  final _strengthController = TextEditingController();
  final _typeController = TextEditingController();
  final _expiryController = TextEditingController();
  final _stockController = TextEditingController();
  final _priceController = TextEditingController();

  final _firestore = FirebaseFirestore.instance;

  /// Add or update medicine permanently (serial ID = permanent key)
  Future<void> _addMedicine() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;

    final docRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory")
        .doc(_serialController.text.trim()); // permanent serial ID

    final medicineData = {
      "serial": _serialController.text.trim(),
      "name": _nameController.text.trim(),
      "batchNo": _batchController.text.trim(),
      "strength": _strengthController.text.trim(),
      "type": _typeController.text.trim(),
      "expiry": _expiryController.text.trim(),
      "stock": int.tryParse(_stockController.text.trim()) ?? 0,
      "price": num.tryParse(_priceController.text.trim()) ?? 0,
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    };

    await docRef.set(medicineData, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Medicine saved")),
    );

    _formKey.currentState!.reset();
    _nameController.clear();
    _serialController.clear();
    _batchController.clear();
    _strengthController.clear();
    _typeController.clear();
    _expiryController.clear();
    _stockController.clear();
    _priceController.clear();
  }

  Future<void> _updateStock(String id, int change) async {
    final docRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory")
        .doc(id);

    await docRef.update({
      "stock": FieldValue.increment(change),
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteMedicine(String id) async {
    await _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory")
        .doc(id)
        .delete();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🗑 Medicine deleted")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inventory"),
        backgroundColor: Colors.green,
      ),
      body: Column(
        children: [
          // Add medicine form
          Padding(
            padding: const EdgeInsets.all(12),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: "Name"),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Required" : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _serialController,
                          decoration:
                              const InputDecoration(labelText: "Serial ID"),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Required" : null,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _batchController,
                          decoration:
                              const InputDecoration(labelText: "Batch No."),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _strengthController,
                          decoration:
                              const InputDecoration(labelText: "Strength"),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _typeController,
                          decoration: const InputDecoration(
                              labelText: "Type (Tablet/Syrup)"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _expiryController,
                          decoration: const InputDecoration(
                              labelText: "Expiry (YYYY-MM-DD)"),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockController,
                          decoration: const InputDecoration(labelText: "Stock"),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          decoration: const InputDecoration(labelText: "Price"),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      minimumSize: const Size(120, 50),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InventoryPage(
                              branchId: widget.branchId), // ✅ Pass branchId
                        ),
                      );
                    },
                    child: const Text("Inventory"),
                  ),
                ],
              ),
            ),
          ),

          const Divider(),

          // Medicine list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection("branches")
                  .doc(widget.branchId)
                  .collection("inventory")
                  .orderBy("name")
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final meds = snapshot.data!.docs;

                if (meds.isEmpty) {
                  return const Center(child: Text("No medicines found"));
                }

                return ListView.builder(
                  itemCount: meds.length,
                  itemBuilder: (context, index) {
                    final med = meds[index].data() as Map<String, dynamic>;
                    final id = meds[index].id;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text("${med["name"]} (${med["strength"]})"),
                        subtitle: Text(
                            "Serial: ${med["serial"]}, Batch: ${med["batchNo"]}, Expiry: ${med["expiry"]}, Price: ${med["price"]}\nStock: ${med["stock"] ?? 0}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, color: Colors.red),
                              onPressed: () => _updateStock(id, -1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: Colors.green),
                              onPressed: () => _updateStock(id, 1),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.delete, color: Colors.grey),
                              onPressed: () => _deleteMedicine(id),
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
      ),
    );
  }
}
