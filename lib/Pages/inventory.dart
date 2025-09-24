// lib/pages/inventory.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class InventoryPage extends StatefulWidget {
  final String branchId;
  final String receptionistId;

  const InventoryPage({
    super.key,
    required this.branchId,
    required this.receptionistId,
  });

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _firestore = FirebaseFirestore.instance;

  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();

  String? _editingDocId;
  String? _selectedType;
  String _searchQuery = "";
  String _filterType = "All";

  final List<String> _medicineTypes = [
    "Tablet",
    "Capsule",
    "Syrup",
    "Injection",
    "Other"
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  List<String> _generateKeywords(String input) {
    input = input.toLowerCase();
    List<String> keywords = [];
    for (int i = 1; i <= input.length; i++) {
      keywords.add(input.substring(0, i));
    }
    return keywords;
  }

  Future<void> _saveMedicine() async {
    if (_nameController.text.isEmpty ||
        _codeController.text.isEmpty ||
        _quantityController.text.isEmpty ||
        _priceController.text.isEmpty ||
        _selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please fill all fields")),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Save"),
        content: Text(_editingDocId == null
            ? "Do you want to add this medicine?"
            : "Do you want to update this medicine?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Confirm")),
        ],
      ),
    );

    if (confirm != true) return;

    final data = {
      "name": _nameController.text.trim(),
      "code": _codeController.text.trim(),
      "quantity": int.tryParse(_quantityController.text.trim()) ?? 0,
      "price": double.tryParse(_priceController.text.trim()) ?? 0.0,
      "type": _selectedType,
      "branchId": widget.branchId,
      "addedBy": widget.receptionistId,
      "updatedAt": FieldValue.serverTimestamp(),
      "searchKeywords": [
        ..._generateKeywords(_nameController.text),
        ..._generateKeywords(_codeController.text),
      ],
    };

    final colRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory");

    if (_editingDocId == null) {
      await colRef.add(data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Medicine added!")),
      );
    } else {
      await colRef.doc(_editingDocId).update(data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Medicine updated!")),
      );
    }

    _clearForm();
  }

  Future<void> _deleteMedicine(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Medicine"),
        content: const Text("Are you sure you want to delete this medicine?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );

    if (confirm == true) {
      await _firestore
          .collection("branches")
          .doc(widget.branchId)
          .collection("inventory")
          .doc(docId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🗑️ Medicine deleted")),
      );
    }
  }

  void _clearForm() {
    setState(() {
      _nameController.clear();
      _codeController.clear();
      _quantityController.clear();
      _priceController.clear();
      _editingDocId = null;
      _selectedType = null;
    });
  }

  void _editMedicine(DocumentSnapshot doc) {
    setState(() {
      _editingDocId = doc.id;
      _nameController.text = doc["name"] ?? "";
      _codeController.text = doc["code"] ?? "";
      _quantityController.text = (doc["quantity"] ?? "").toString();
      _priceController.text = (doc["price"] ?? "").toString();
      _selectedType = doc["type"];
    });
  }

  @override
  Widget build(BuildContext context) {
    final colRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory");

    return Scaffold(
      backgroundColor: Colors.green.shade700,
      appBar: AppBar(
        backgroundColor: Colors.green.shade900,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "📦 Inventory",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Medicine Form
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Medicine Name",
                          prefixIcon: Icon(Icons.medical_services),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: "Medicine Code",
                          prefixIcon: Icon(Icons.numbers),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedType,
                        decoration: const InputDecoration(
                          labelText: "Medicine Type",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: _medicineTypes
                            .map((type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedType = v),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: "Quantity",
                          prefixIcon: Icon(Icons.confirmation_number),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}'))
                        ],
                        decoration: const InputDecoration(
                          labelText: "Price",
                          prefixIcon: Text(
                            "PKR",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _saveMedicine,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.save),
                            label: Text(
                              _editingDocId == null
                                  ? "Add Medicine"
                                  : "Update Medicine",
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_editingDocId != null)
                            ElevatedButton.icon(
                              onPressed: _clearForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.cancel),
                              label: const Text("Cancel"),
                            ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Inventory Card with Search + Filter
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Container(
                  height: 500,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // 🔍 Search + Filter Row inside Card
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: "Search medicine",
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(
                                  () => _searchQuery = v.trim().toLowerCase()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _filterType,
                            items: ["All", ..._medicineTypes]
                                .map((type) => DropdownMenuItem(
                                    value: type, child: Text(type)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _filterType = v ?? "All"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Medicine List
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: colRef
                              .orderBy("updatedAt", descending: true)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            var docs = snapshot.data!.docs;

                            // Apply search + filter
                            docs = docs.where((doc) {
                              final name =
                                  (doc["name"] ?? "").toString().toLowerCase();
                              final code =
                                  (doc["code"] ?? "").toString().toLowerCase();
                              final type = (doc["type"] ?? "").toString();
                              final matchesSearch =
                                  name.contains(_searchQuery) ||
                                      code.contains(_searchQuery);
                              final matchesFilter =
                                  _filterType == "All" || type == _filterType;
                              return matchesSearch && matchesFilter;
                            }).toList();

                            if (docs.isEmpty) {
                              return const Center(
                                  child: Text("❌ No medicines found."));
                            }

                            return ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (_, index) {
                                final doc = docs[index];
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: ListTile(
                                    leading: const Icon(Icons.medication,
                                        color: Colors.green),
                                    title: Text(
                                      doc["name"] ?? "Unnamed",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      "Code: ${doc["code"] ?? "-"} | "
                                      "Type: ${doc["type"] ?? "-"} | "
                                      "Qty: ${doc["quantity"] ?? 0} | "
                                      "Price: PKR ${doc["price"] ?? 0}",
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.blue),
                                          onPressed: () => _editMedicine(doc),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () =>
                                              _deleteMedicine(doc.id),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
