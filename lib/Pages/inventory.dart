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
  int _currentPage = 0;
  final int _itemsPerPage = 20;

  final List<String> _types = [
    "All",
    "Tablet",
    "Capsule",
    "Syrup",
    "Injection",
    "Drip",
  ];

  bool _isValidDate = true;

  /// Utility: Date input field formatter
  List<TextInputFormatter> _expiryInputFormatters() {
    return [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(8), // ddmmyyyy -> 8 digits
      TextInputFormatter.withFunction((oldValue, newValue) {
        var text = newValue.text;

        // Auto-insert "-" after dd and mm
        if (text.length > 2 && text[2] != '-') {
          text = '${text.substring(0, 2)}-${text.substring(2)}';
        }
        if (text.length > 5 && text[5] != '-') {
          text = '${text.substring(0, 5)}-${text.substring(5)}';
        }

        return newValue.copyWith(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }),
    ];
  }

  void _validateDate(String val) {
    final parts = val.split('-');
    bool valid = true;

    if (parts.length >= 2) {
      final day = int.tryParse(parts[0]) ?? 0;
      final month = int.tryParse(parts[1]) ?? 0;
      if (day < 1 || day > 31 || month < 1 || month > 12) {
        valid = false;
      }
    }

    if (_isValidDate != valid) {
      setState(() {
        _isValidDate = valid;
      });
    }
  }

  /// Add Medicine Form
  void _showAddMedicineForm() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController qtyController = TextEditingController();
    final TextEditingController expiryController = TextEditingController();
    String selectedType = "Tablet";

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("➕ Add Medicine"),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "Medicine Name",
                      prefixIcon: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: FaIcon(FontAwesomeIcons.pills,
                            size: 18, color: Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: "Type",
                      prefixIcon: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: FaIcon(FontAwesomeIcons.tags,
                            size: 18, color: Colors.green),
                      ),
                    ),
                    items: ["Tablet", "Capsule", "Syrup", "Injection", "Drip"]
                        .map((type) =>
                            DropdownMenuItem(value: type, child: Text(type)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) selectedType = val;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: "Quantity",
                      prefixIcon: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: FaIcon(FontAwesomeIcons.boxesStacked,
                            size: 18, color: Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: expiryController,
                    keyboardType: TextInputType.number,
                    inputFormatters: _expiryInputFormatters(),
                    decoration: InputDecoration(
                      labelText: "Expiry Date (dd-mm-yyyy)",
                      hintText: "dd-mm-yyyy",
                      errorText: _isValidDate ? null : "Invalid date",
                      prefixIcon: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: FaIcon(FontAwesomeIcons.calendar,
                            size: 18, color: Colors.green),
                      ),
                    ),
                    onChanged: _validateDate,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton.icon(
              icon: const FaIcon(FontAwesomeIcons.check, color: Colors.white),
              label:
                  const Text("Confirm", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                final expiryText = expiryController.text.trim();

                if (name.isEmpty ||
                    qty <= 0 ||
                    expiryText.isEmpty ||
                    !_isValidDate) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("🚩 Fill all fields correctly.")),
                  );
                  return;
                }

                await FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('inventory')
                    .add({
                  'name': name,
                  'type': selectedType,
                  'quantity': qty,
                  'expiryDate': expiryText,
                  'createdBy': widget.receptionistId,
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  /// Edit Medicine Form
  void _showEditMedicineForm(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final TextEditingController nameController =
        TextEditingController(text: data['name']);
    final TextEditingController qtyController =
        TextEditingController(text: data['quantity'].toString());
    final TextEditingController expiryController =
        TextEditingController(text: data['expiryDate']);
    String selectedType = data['type'] ?? "Tablet";

    _validateDate(expiryController.text); // validate initial value

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("✏️ Edit Medicine"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Medicine Name"),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: ["Tablet", "Capsule", "Syrup", "Injection", "Drip"]
                      .map((type) =>
                          DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) selectedType = val;
                  },
                  decoration: const InputDecoration(labelText: "Type"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: "Quantity"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: expiryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: _expiryInputFormatters(),
                  decoration: InputDecoration(
                    labelText: "Expiry Date (dd-mm-yyyy)",
                    hintText: "dd-mm-yyyy",
                    errorText: _isValidDate ? null : "Invalid date",
                  ),
                  onChanged: _validateDate,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                if (!_isValidDate) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("🚩 Enter a valid date.")),
                  );
                  return;
                }

                await doc.reference.update({
                  'name': nameController.text.trim(),
                  'type': selectedType,
                  'quantity': int.tryParse(qtyController.text.trim()) ?? 0,
                  'expiryDate': expiryController.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              },
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// Build UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.arrowLeft, color: Colors.white),
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
        child: const FaIcon(FontAwesomeIcons.plus, color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 144, 201, 74),
              Color.fromARGB(255, 39, 92, 15),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            // Search & Filters
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: "Search medicine...",
                        prefixIcon: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: FaIcon(FontAwesomeIcons.magnifyingGlass,
                              size: 18, color: Colors.grey),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (_) => setState(() {
                        _currentPage = 0;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildDropdown(
                    value: _sortOption,
                    items: ["Name", "Quantity", "Expiry"],
                    prefix: "Sort: ",
                    onChanged: (val) {
                      if (val != null) setState(() => _sortOption = val);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildDropdown(
                    value: _filterType,
                    items: _types,
                    prefix: "Type: ",
                    onChanged: (val) {
                      if (val != null) setState(() => _filterType = val);
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            // Medicine List
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
                    return const Center(
                        child: Text("📦 No medicines found.",
                            style: TextStyle(fontSize: 16)));
                  }

                  var meds = snapshot.data!.docs;
                  var filteredMeds = meds.where((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final name = (d['name'] ?? '').toString().toLowerCase();
                    final type = (d['type'] ?? '').toString();
                    final matchesSearch =
                        name.contains(_searchController.text.toLowerCase());
                    final matchesType =
                        _filterType == "All" || type == _filterType;
                    return matchesSearch && matchesType;
                  }).toList();

                  // Sorting
                  filteredMeds.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    if (_sortOption == "Name") {
                      return (aData['name'] ?? "")
                          .compareTo(bData['name'] ?? "");
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

                  // Pagination
                  final totalPages =
                      (filteredMeds.length / _itemsPerPage).ceil();
                  final startIndex = _currentPage * _itemsPerPage;
                  final endIndex = (startIndex + _itemsPerPage)
                      .clamp(0, filteredMeds.length);
                  final pageMeds = filteredMeds.sublist(startIndex, endIndex);

                  return Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: pageMeds.length,
                          itemBuilder: (context, index) {
                            final d =
                                pageMeds[index].data() as Map<String, dynamic>;
                            final name = d['name'] ?? '';
                            final type = d['type'] ?? '';
                            final qty = d['quantity'] ?? 0;
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
                                iconData =
                                    FontAwesomeIcons.prescriptionBottleMedical;
                                break;
                              case "injection":
                                iconData = FontAwesomeIcons.syringe;
                                break;
                              case "drip":
                                iconData = FontAwesomeIcons.prescriptionBottle;
                                break;
                              default:
                                iconData = FontAwesomeIcons.pills;
                            }

                            return Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              color: Colors.white,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              elevation: 3,
                              child: ListTile(
                                leading: FaIcon(iconData,
                                    size: 28, color: Colors.green),
                                title: Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    "$type | Qty: $qty | $expiry"), // ✅ no emojis
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const FaIcon(
                                          FontAwesomeIcons.penToSquare,
                                          color: Colors.amber),
                                      onPressed: () {
                                        _showEditMedicineForm(pageMeds[index]);
                                      },
                                    ),
                                    IconButton(
                                      icon: const FaIcon(FontAwesomeIcons.trash,
                                          color: Colors.red),
                                      onPressed: () async {
                                        await pageMeds[index]
                                            .reference
                                            .delete();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (totalPages > 1)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: _currentPage > 0
                                    ? () {
                                        setState(() => _currentPage--);
                                      }
                                    : null,
                              ),
                              Text("Page ${_currentPage + 1} of $totalPages"),
                              IconButton(
                                icon: const Icon(Icons.arrow_forward),
                                onPressed: _currentPage < totalPages - 1
                                    ? () {
                                        setState(() => _currentPage++);
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required String prefix,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox(),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
        dropdownColor: Colors.white,
        style: const TextStyle(color: Colors.black, fontSize: 14),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
