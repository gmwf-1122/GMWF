// lib/pages/inventory.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'receptionist_screen.dart'; // for back navigation

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
  final TextEditingController _searchController = TextEditingController();
  String _sortOption = "Name";
  String _filterType = "All";

  final List<String> _types = [
    "All",
    "Tablet",
    "Capsule",
    "Syrup",
    "Injection"
  ];

  void _showAddMedicineForm() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController codeController = TextEditingController();
    final TextEditingController qtyController = TextEditingController();
    final TextEditingController priceController = TextEditingController();
    final TextEditingController expiryController = TextEditingController();
    String selectedType = "Tablet";

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Medicine"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Medicine Code
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: "Medicine Code",
                    prefixIcon: Icon(Icons.code, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 10),
                // Medicine Name
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Medicine Name",
                    prefixIcon:
                        Icon(Icons.medical_services, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 10),
                // Medicine Type
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: "Type",
                    prefixIcon: Icon(Icons.category, color: Colors.green),
                  ),
                  items:
                      ["Tablet", "Capsule", "Syrup", "Injection"].map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) selectedType = val;
                  },
                ),
                const SizedBox(height: 10),
                // Quantity
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Quantity",
                    prefixIcon: Icon(Icons.inventory_2, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 10),
                // Price
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Price (PKR)",
                    prefixIcon: Text(
                      "PKR ",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Expiry Date (strict dd-mm-yyyy)
                TextField(
                  controller: expiryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'\d|-')),
                    LengthLimitingTextInputFormatter(10),
                    ExpiryDateFormatter(), // custom formatter below
                  ],
                  decoration: const InputDecoration(
                    labelText: "Expiry Date (dd-mm-yyyy)",
                    prefixIcon: Icon(Icons.date_range, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, color: Colors.white),
              label:
                  const Text("Confirm", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                final code = codeController.text.trim();
                final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                final price = double.tryParse(priceController.text.trim()) ?? 0;
                final expiryText = expiryController.text.trim();

                if (name.isEmpty ||
                    code.isEmpty ||
                    qty <= 0 ||
                    price <= 0 ||
                    expiryText.length != 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "🚩 Fill all fields correctly (expiry dd-mm-yyyy)")),
                  );
                  return;
                }

                // Duplicate check
                final existing = await FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('inventory')
                    .where('code', isEqualTo: code)
                    .get();

                if (existing.docs.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("❌ Medicine code already exists")),
                  );
                  return;
                }

                await FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('inventory')
                    .add({
                  'code': code,
                  'name': name,
                  'type': selectedType,
                  'quantity': qty,
                  'price': price,
                  'expiryDate': expiryText,
                  'createdBy': widget.receptionistId,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ReceptionistScreen(
                  branchId: widget.branchId,
                  receptionistId: widget.receptionistId,
                ),
              ),
            );
          },
        ),
        title: const Text("Inventory", style: TextStyle(color: Colors.white)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: _showAddMedicineForm,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          // Red gradient strip
          Container(
            height: 15,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.redAccent, Colors.red],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search medicine...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _sortOption,
                  items: ["Name", "Quantity", "Expiry"].map((opt) {
                    return DropdownMenuItem(
                        value: opt, child: Text("Sort: $opt"));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _sortOption = val);
                  },
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _filterType,
                  items: _types.map((opt) {
                    return DropdownMenuItem(
                        value: opt, child: Text("Type: $opt"));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _filterType = val);
                  },
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('inventory')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No medicines found."));
                }

                var meds = snapshot.data!.docs;
                var filteredMeds = meds.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final name = (d['name'] ?? '').toString().toLowerCase();
                  final type = (d['type'] ?? '').toString();
                  final code = (d['code'] ?? '').toString().toLowerCase();
                  final matchesSearch =
                      name.contains(_searchController.text.toLowerCase()) ||
                          code.contains(_searchController.text.toLowerCase());
                  final matchesType =
                      _filterType == "All" || type == _filterType;
                  return matchesSearch && matchesType;
                }).toList();

                filteredMeds.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  if (_sortOption == "Name") {
                    return (aData['name'] ?? "").compareTo(bData['name'] ?? "");
                  } else if (_sortOption == "Quantity") {
                    return (aData['quantity'] ?? 0)
                        .compareTo(bData['quantity'] ?? 0);
                  } else if (_sortOption == "Expiry") {
                    final aDate = aData['expiryDate'] ?? '';
                    final bDate = bData['expiryDate'] ?? '';
                    return aDate.toString().compareTo(bDate.toString());
                  }
                  return 0;
                });

                return ListView.builder(
                  itemCount: filteredMeds.length,
                  itemBuilder: (context, index) {
                    final d =
                        filteredMeds[index].data() as Map<String, dynamic>;
                    final code = d['code'] ?? '';
                    final name = d['name'] ?? '';
                    final type = d['type'] ?? '';
                    final qty = d['quantity'] ?? 0;
                    final price = d['price'] ?? 0;
                    final expiry = d['expiryDate'] ?? '';

                    IconData iconData;
                    switch (type.toLowerCase()) {
                      case "tablet":
                        iconData = FontAwesomeIcons.tablets;
                        break;
                      case "capsule":
                        iconData = FontAwesomeIcons.capsules;
                        break;
                      case "syrup":
                        iconData = FontAwesomeIcons.prescriptionBottleMedical;
                        break;
                      case "injection":
                        iconData = FontAwesomeIcons.syringe;
                        break;
                      default:
                        iconData = FontAwesomeIcons.pills;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading:
                            FaIcon(iconData, size: 28, color: Colors.green),
                        title: Text("$name ($code)"),
                        subtitle: Text(
                            "Type: $type | Qty: $qty | PKR $price | Expiry: $expiry"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                // TODO: implement edit
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                await filteredMeds[index].reference.delete();
                              },
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

/// Formatter to enforce dd-mm-yyyy input
class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      buffer.write(digits[i]);
      if (i == 1 || i == 3) buffer.write('-');
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
