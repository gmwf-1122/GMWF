import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class InventoryAdjustmentPage extends StatefulWidget {
  final String branchId;

  const InventoryAdjustmentPage({super.key, required this.branchId});

  @override
  State<InventoryAdjustmentPage> createState() => _InventoryAdjustmentPageState();
}

class _InventoryAdjustmentPageState extends State<InventoryAdjustmentPage> {
  List<Map<String, dynamic>> inventoryItems = [];
  List<Map<String, dynamic>> searchResults = [];

  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController doseCtrl = TextEditingController();
  final TextEditingController quantityCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController expiryCtrl = TextEditingController();
  final TextEditingController classificationCtrl = TextEditingController();
  final TextEditingController distilledWaterCtrl = TextEditingController();
  final TextEditingController dropsCtrl = TextEditingController();
  final TextEditingController reasonCtrl = TextEditingController();

  Map<String, dynamic>? selectedItem;
  String? selectedType;
  bool hasDoseOriginally = false;
  String? _branchName;

  final List<String> medicineTypes = [
    'Tablet',
    'Capsule',
    'Syrup',
    'Injection',
    'Drip',
    'Drip Set',
    'Syringe',
    'Nebulization',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    _loadBranchName();
    loadInventory();
  }

  Future<void> _loadBranchName() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('branches').doc(widget.branchId).get();
      if (doc.exists) {
        setState(() {
          _branchName = doc['name'] ?? 'Unknown Branch';
        });
      }
    } catch (e) {
      debugPrint('Error loading branch name: $e');
    }
  }

  Future<void> loadInventory() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .get();

      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        inventoryItems = items;
        searchResults = List.from(items);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load inventory')));
      }
    }
  }

  void filterSearch(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        searchResults = List.from(inventoryItems);
      } else {
        searchResults = inventoryItems.where((item) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    nameCtrl.dispose();
    doseCtrl.dispose();
    quantityCtrl.dispose();
    priceCtrl.dispose();
    expiryCtrl.dispose();
    classificationCtrl.dispose();
    distilledWaterCtrl.dispose();
    dropsCtrl.dispose();
    reasonCtrl.dispose();
    super.dispose();
  }

  String _generateDocId(Map<String, dynamic> item) {
    String clean(String? s) {
      if (s == null || s.isEmpty) return '';
      return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
    }

    final name = clean(item['name']);
    final type = item['type'] ?? 'Others';
    final expiry = clean(item['expiryDate'] ?? 'no-expiry');

    if (type == 'Nebulization') {
      final water = item['distilledWater'] ?? 0;
      final drops = item['drops'] ?? 0;
      return '$name--$type--water${water}ml-drops$drops--$expiry';
    }

    final dose = clean(item['dose'] ?? '');
    return '$name--$type--$dose--$expiry';
  }

  void _selectItem(Map<String, dynamic> item) {
    setState(() {
      selectedItem = Map.from(item);
      selectedType = item['type'] ?? 'Others';

      final originalDose = (item['dose']?.toString() ?? '').trim();
      hasDoseOriginally = originalDose.isNotEmpty && selectedType != 'Nebulization';

      nameCtrl.text = item['name'] ?? '';
      doseCtrl.text = hasDoseOriginally ? originalDose : '';
      quantityCtrl.text = (item['quantity'] ?? 0).toString();
      priceCtrl.text = (item['price'] ?? 0).toString();
      expiryCtrl.text = item['expiryDate'] ?? '';
      classificationCtrl.text = item['classification'] ?? '';
      distilledWaterCtrl.text = (item['distilledWater'] ?? 0).toString();
      dropsCtrl.text = (item['drops'] ?? 0).toString();
      reasonCtrl.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      selectedItem = null;
      selectedType = null;
      hasDoseOriginally = false;
      nameCtrl.clear();
      doseCtrl.clear();
      quantityCtrl.clear();
      priceCtrl.clear();
      expiryCtrl.clear();
      classificationCtrl.clear();
      distilledWaterCtrl.clear();
      dropsCtrl.clear();
      reasonCtrl.clear();
    });
  }

  Future<void> _submitAdjustment() async {
    if (selectedItem == null) return;

    final newName = nameCtrl.text.trim();
    final newType = selectedType!;
    final newQty = int.tryParse(quantityCtrl.text.trim());
    final newPrice = int.tryParse(priceCtrl.text.trim());
    final newDose = doseCtrl.text.trim();
    final newExpiry = expiryCtrl.text.trim();
    final newClassification = classificationCtrl.text.trim();
    final reason = reasonCtrl.text.trim();

    if (newName.isEmpty || newQty == null || newPrice == null || reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
      return;
    }

    if (newType != 'Nebulization' && hasDoseOriginally && newDose.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dose is required')));
      return;
    }

    if (newType == 'Nebulization') {
      final water = int.tryParse(distilledWaterCtrl.text.trim());
      final drops = int.tryParse(dropsCtrl.text.trim());
      if (water == null || drops == null || water <= 0 || drops <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid water & drops required')));
        return;
      }
    }

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(user.uid)
          .get();
      final username = userDoc.data()?['username'] ?? user.email ?? 'Unknown';

      final oldId = _generateDocId(selectedItem!);

      final itemData = {
        'oldId': oldId,
        'name': newName,
        'name_lower': newName.toLowerCase(),
        'type': newType,
        'dose': newType == 'Nebulization' ? '' : (hasDoseOriginally ? newDose : ''),
        'quantity': newQty,
        'price': newPrice,
        'expiryDate': newExpiry,
        'classification': newClassification,
        if (newType == 'Nebulization') ...{
          'distilledWater': int.parse(distilledWaterCtrl.text.trim()),
          'drops': int.parse(dropsCtrl.text.trim()),
        },
      };

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .add({
        'requestType': 'edit_medicine',
        'requester': user.uid,
        'requesterName': username,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'reason': reason,
        'items': [itemData],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent for approval!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitDelete() async {
    if (selectedItem == null) return;

    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reason is required for deletion')));
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(user.uid)
          .get();
      final username = userDoc.data()?['username'] ?? user.email ?? 'Unknown';

      final docId = _generateDocId(selectedItem!);

      final itemData = {
        'id': docId,
        'name': selectedItem!['name'],
        'name_lower': (selectedItem!['name'] as String).toLowerCase(),
        'type': selectedItem!['type'],
        'dose': selectedItem!['dose'] ?? '',
        'quantity': selectedItem!['quantity'] ?? 0,
        'price': selectedItem!['price'] ?? 0,
        'expiryDate': selectedItem!['expiryDate'] ?? '',
        'classification': selectedItem!['classification'] ?? '',
        'distilledWater': selectedItem!['distilledWater'],
        'drops': selectedItem!['drops'],
      };

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .add({
        'requestType': 'delete_medicine',
        'requester': user.uid,
        'requesterName': username,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'reason': reason,
        'items': [itemData],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delete request sent!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Medicine?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This medicine will be permanently removed after supervisor approval.\n\nAre you sure?',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitDelete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF2D2D2D),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _getTypeIcon(String? type) {
    final icon = switch (type) {
      'Tablet' => FontAwesomeIcons.tablets,
      'Capsule' => FontAwesomeIcons.capsules,
      'Syrup' => FontAwesomeIcons.bottleDroplet,
      'Injection' => FontAwesomeIcons.syringe,
      'Drip' => FontAwesomeIcons.tint,
      'Drip Set' => FontAwesomeIcons.kitMedical,
      'Syringe' => FontAwesomeIcons.syringe,
      'Nebulization' => FontAwesomeIcons.cloud,
      _ => FontAwesomeIcons.pills,
    };
    return Icon(icon, color: Colors.orange, size: 24);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(FontAwesomeIcons.edit, color: Colors.orange, size: 20),
            SizedBox(width: 10),
            Text('Adjust Inventory', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
      ),
      body: selectedItem == null ? _buildSearchView() : _buildAdjustmentForm(),
    );
  }

  Widget _buildSearchView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dispensary: ${_branchName ?? 'Loading...'}',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchCtrl,
                onChanged: filterSearch,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search medicine...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.orange),
                  filled: true,
                  fillColor: const Color(0xFF2D2D2D),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: searchResults.isEmpty
              ? const Center(child: Text('No items found', style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  itemCount: searchResults.length,
                  itemBuilder: (ctx, i) {
                    final item = searchResults[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      color: const Color(0xFF1E1E1E),
                      child: ListTile(
                        leading: _getTypeIcon(item['type']),
                        title: Text(
                          item['name'] ?? 'Unknown',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${item['type'] ?? ''} • Qty: ${item['quantity'] ?? 0} • ${item['expiryDate'] ?? '—'}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.orange),
                        onTap: () => _selectItem(item),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _clearSelection,
              ),
              const Text('Adjust Stock', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Dispensary: ${_branchName ?? 'Loading...'}', style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 24),
          TextField(
            controller: nameCtrl,
            decoration: _inputDecoration('Name *'),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: selectedType,
            items: medicineTypes.map((type) {
              return DropdownMenuItem<String>(
                value: type,
                child: Text(type, style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                selectedType = value;
              });
            },
            decoration: _inputDecoration('Type *'),
            dropdownColor: const Color(0xFF2D2D2D),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          if (selectedType != 'Nebulization' && hasDoseOriginally) ...[
            TextField(
              controller: doseCtrl,
              decoration: _inputDecoration('Dose/Variant *'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
          ],
          if (selectedType == 'Nebulization') ...[
            TextField(
              controller: distilledWaterCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('Distilled Water (ml) *'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dropsCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('Drops *'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: quantityCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration('New Quantity *'),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: priceCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration('Price (PKR) *'),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: expiryCtrl,
            decoration: _inputDecoration('Expiry Date'),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: classificationCtrl,
            decoration: _inputDecoration('Classification'),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: reasonCtrl,
            maxLines: 4,
            decoration: _inputDecoration('Reason for Adjustment *'),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitAdjustment,
              icon: const Icon(Icons.send, color: Colors.white),
              label: const Text('Submit Request', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showDeleteConfirmation,
              icon: const Icon(Icons.delete, color: Colors.white),
              label: const Text('Delete Medicine', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}