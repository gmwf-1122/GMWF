import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class InventoryUpdatePage extends StatefulWidget {
  final String branchId;
  const InventoryUpdatePage({super.key, required this.branchId});

  @override
  State<InventoryUpdatePage> createState() => _InventoryUpdatePageState();
}

class _InventoryUpdatePageState extends State<InventoryUpdatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _expCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _distWaterCtrl = TextEditingController();
  final _dropsCtrl = TextEditingController();

  String _type = 'Tablet';
  String? _selectedDose;
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _itemsToAdd = [];

  final List<String> _allTypes = [
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

  final Map<String, List<String>> _doseOptions = {
    'Capsule': [
      '5 mg',
      '10 mg',
      '20 mg',
      '50 mg',
      '100 mg',
      '250 mg',
      '500 mg',
    ],
    'Syrup': [
      '5 ml',
      '10 ml',
      '15 ml',
      '20 ml',
      '30 ml',
      '60 ml',
      '90 ml',
      '120 ml',
      '250 ml',
    ],
    'Injection': ['1cc', '2cc', '3cc', '5cc', '10cc'],
    'Drip': ['100 ml', '250 ml', '450 ml', '500 ml', '1000 ml'],
  };

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _expCtrl.dispose();
    _priceCtrl.dispose();
    _distWaterCtrl.dispose();
    _dropsCtrl.dispose();
    super.dispose();
  }

  void _searchMedicine(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .where('name_lower', isGreaterThanOrEqualTo: query.toLowerCase())
          .where(
            'name_lower',
            isLessThanOrEqualTo: '${query.toLowerCase()}\uf8ff',
          )
          .limit(6)
          .get();

      setState(() {
        _searchResults = snap.docs.map((d) => d.data()).toList();
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  void _selectMedicine(Map<String, dynamic> med) {
    _nameCtrl.text = med['name'] ?? '';
    final newType = med['type'] ?? 'Tablet';
    if (newType != _type) {
      setState(() {
        _type = newType;
        _selectedDose = null;
      });
    }
    if (_type == 'Nebulization') {
      _distWaterCtrl.text = med['distilledWater']?.toString() ?? '';
      _dropsCtrl.text = med['drops']?.toString() ?? '';
    } else {
      final incomingDose = med['dose']?.toString().trim();
      final doseList = _doseOptions[_type] ?? [];
      _selectedDose = (incomingDose != null && doseList.contains(incomingDose))
          ? incomingDose
          : null;
    }
    _priceCtrl.text = (med['price'] ?? '').toString();
    setState(() => _searchResults = []);
  }

  void _addItem() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final price = int.tryParse(_priceCtrl.text) ?? 0;
    final exp = _expCtrl.text.trim();

    Map<String, dynamic> newItem;
    bool isDuplicate = false;
    if (_type == 'Nebulization') {
      final water = int.tryParse(_distWaterCtrl.text) ?? 0;
      final drops = int.tryParse(_dropsCtrl.text) ?? 0;
      if (water <= 0 || drops <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid distilled water or drops quantity'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      newItem = {
        'name': name,
        'type': _type,
        'distilledWater': water,
        'drops': drops,
        'quantity': qty,
        'price': price,
        'expiryDate': exp,
      };
      isDuplicate = _itemsToAdd.any(
        (i) =>
            i['name'] == name &&
            i['type'] == _type &&
            i['distilledWater'] == water &&
            i['drops'] == drops &&
            i['expiryDate'] == exp,
      );
    } else {
      final dose = _selectedDose ?? '';
      newItem = {
        'name': name,
        'type': _type,
        'dose': dose,
        'quantity': qty,
        'price': price,
        'expiryDate': exp,
      };
      isDuplicate = _itemsToAdd.any(
        (i) =>
            i['name'] == name &&
            i['type'] == _type &&
            i['dose'] == dose &&
            i['expiryDate'] == exp,
      );
    }

    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already added!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _itemsToAdd.add(newItem);
      _resetForm();
    });
  }

  void _resetForm() {
    _nameCtrl.clear();
    _qtyCtrl.text = '1';
    _expCtrl.clear();
    _priceCtrl.clear();
    _distWaterCtrl.clear();
    _dropsCtrl.clear();
    _type = 'Tablet';
    _selectedDose = null;
    _searchResults = [];
  }

  void _removeItem(int index) => setState(() => _itemsToAdd.removeAt(index));

  void _editItem(int index) {
    final item = Map<String, dynamic>.from(_itemsToAdd[index]);
    showDialog(
      context: context,
      builder: (ctx) {
        final editNameCtrl = TextEditingController(text: item['name']);
        final editQtyCtrl = TextEditingController(
          text: item['quantity'].toString(),
        );
        final editPriceCtrl = TextEditingController(
          text: item['price'].toString(),
        );
        final editExpCtrl = TextEditingController(text: item['expiryDate']);
        final editDistWaterCtrl = TextEditingController(
          text: item['distilledWater']?.toString() ?? '',
        );
        final editDropsCtrl = TextEditingController(
          text: item['drops']?.toString() ?? '',
        );
        String editType = item['type'];
        String? editDose = item['dose'];

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text(
                'Edit Item',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: editNameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: editType,
                      dropdownColor: const Color(0xFF2D2D2D),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      items: _allTypes
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                t,
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            editType = v;
                            editDose = null;
                            editDistWaterCtrl.clear();
                            editDropsCtrl.clear();
                          });
                        }
                      },
                    ),
                    if (editType != 'Nebulization' &&
                        _doseOptions[editType] != null &&
                        _doseOptions[editType]!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: DropdownButtonFormField<String>(
                          value: editDose,
                          hint: const Text(
                            'Select dose',
                            style: TextStyle(color: Colors.white70),
                          ),
                          dropdownColor: const Color(0xFF2D2D2D),
                          style: const TextStyle(color: Colors.white),
                          items: _doseOptions[editType]!
                              .map(
                                (d) =>
                                    DropdownMenuItem(value: d, child: Text(d)),
                              )
                              .toList(),
                          onChanged: (v) => setDialogState(() => editDose = v),
                        ),
                      ),
                    if (editType == 'Nebulization')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: editDistWaterCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Distilled Water (ml)',
                            labelStyle: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    if (editType == 'Nebulization')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: editDropsCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Drops',
                            labelStyle: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: editQtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: editPriceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Price (PKR)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: editExpCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ExpiryDateFormatter(),
                      ],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Expiry',
                        hintText: 'dd-MM-yyyy',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintStyle: const TextStyle(color: Colors.white38),
                        errorText: ExpiryDateFormatter.validate(
                          editExpCtrl.text,
                        ),
                        errorStyle: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () {
                    final error = ExpiryDateFormatter.validate(
                      editExpCtrl.text,
                    );
                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(error),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Map<String, dynamic> updatedItem = {
                      'name': editNameCtrl.text.trim(),
                      'type': editType,
                      'quantity': int.tryParse(editQtyCtrl.text) ?? 1,
                      'price': int.tryParse(editPriceCtrl.text) ?? 0,
                      'expiryDate': editExpCtrl.text,
                    };
                    if (editType == 'Nebulization') {
                      final water = int.tryParse(editDistWaterCtrl.text) ?? 0;
                      final drops = int.tryParse(editDropsCtrl.text) ?? 0;
                      if (water <= 0 || drops <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Invalid distilled water or drops quantity',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      updatedItem['distilledWater'] = water;
                      updatedItem['drops'] = drops;
                    } else {
                      updatedItem['dose'] = editDose ?? '';
                    }
                    setState(() {
                      _itemsToAdd[index] = updatedItem;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addToInventory() async {
    if (_itemsToAdd.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not authenticated'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Map<String, dynamic> requestData = {
        'requestType': 'add_stock',
        'requester': user.uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'items': _itemsToAdd.map((item) {
          var data = Map<String, dynamic>.from(item);
          data['name_lower'] = item['name'].toLowerCase();
          return data;
        }).toList(),
      };

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .add(requestData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Update request sent for approval!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _itemsToAdd.clear();
      });
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Helper to determine expiry color
  Color _getExpiryColor(String expiry) {
    final error = ExpiryDateFormatter.validate(expiry);
    if (error != null) return Colors.red;

    try {
      final parts = expiry.split('-');
      final date = DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
      final now = DateTime.now();
      final diff = date.difference(now).inDays;
      if (diff <= 30) return Colors.red; // 1 month or less
      if (diff <= 90) return Colors.orange; // 3 months
      return Colors.green;
    } catch (_) {
      return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final doseList = _doseOptions[_type] ?? [];

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
            Icon(FontAwesomeIcons.boxesStacked, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Text(
              'Request Inventory Update',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // FORM CARD
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Medicine Name',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Search medicine...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(
                            Icons.medication,
                            color: Colors.orange,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF2D2D2D),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: _isSearching
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.orange,
                                  ),
                                )
                              : null,
                        ),
                        onChanged: _searchMedicine,
                        validator: (v) =>
                            v?.trim().isEmpty ?? true ? 'Required' : null,
                      ),
                      if (_searchResults.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF252525),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _searchResults.length,
                            itemBuilder: (ctx, i) {
                              final med = _searchResults[i];
                              return ListTile(
                                leading: const Icon(
                                  Icons.touch_app,
                                  color: Colors.orange,
                                ),
                                title: Text(
                                  med['name'],
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  '${med['type']} ${med['dose'] ?? ''}'.trim(),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                onTap: () => _selectMedicine(med),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _type,
                              dropdownColor: const Color(0xFF2D2D2D),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Type',
                                labelStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                prefixIcon: _typeIcon(_type),
                                filled: true,
                                fillColor: const Color(0xFF2D2D2D),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: _allTypes
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(
                                        t,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _type = v;
                                    _selectedDose = null;
                                    _distWaterCtrl.clear();
                                    _dropsCtrl.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Price (PKR)',
                                labelStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                prefixIcon: const Icon(
                                  Icons.price_change,
                                  color: Colors.green,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2D2D2D),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (v) {
                                if (v?.trim().isEmpty ?? true) {
                                  return 'Required';
                                }
                                if (int.tryParse(v!) == null ||
                                    int.parse(v) <= 0) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_type != 'Nebulization' && doseList.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _selectedDose,
                          hint: const Text(
                            'Select dose',
                            style: TextStyle(color: Colors.white70),
                          ),
                          dropdownColor: const Color(0xFF2D2D2D),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Dose',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF2D2D2D),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: doseList
                              .map(
                                (d) =>
                                    DropdownMenuItem(value: d, child: Text(d)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _selectedDose = v),
                          validator: (v) => v == null ? 'Select dose' : null,
                        ),
                      if (_type == 'Nebulization')
                        TextFormField(
                          controller: _distWaterCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Distilled Water (ml)',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF2D2D2D),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) {
                            if (v?.trim().isEmpty ?? true) return 'Required';
                            final num = int.tryParse(v!);
                            if (num == null || num <= 0) return 'Invalid';
                            return null;
                          },
                        ),
                      if (_type == 'Nebulization') const SizedBox(height: 16),
                      if (_type == 'Nebulization')
                        TextFormField(
                          controller: _dropsCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Drops',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF2D2D2D),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) {
                            if (v?.trim().isEmpty ?? true) return 'Required';
                            final num = int.tryParse(v!);
                            if (num == null || num <= 0) return 'Invalid';
                            return null;
                          },
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _qtyCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                labelStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                prefixIcon: const Icon(
                                  Icons.numbers,
                                  color: Colors.orange,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2D2D2D),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (v) =>
                                  int.tryParse(v ?? '') == null ||
                                      int.parse(v!) < 1
                                  ? '≥1'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _expCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                ExpiryDateFormatter(),
                              ],
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Expiry',
                                labelStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                hintText: 'dd-MM-yyyy',
                                hintStyle: const TextStyle(
                                  color: Colors.white38,
                                ),
                                prefixIcon: const Icon(
                                  Icons.calendar_today,
                                  color: Colors.orange,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF2D2D2D),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                errorText: ExpiryDateFormatter.validate(
                                  _expCtrl.text,
                                ),
                                errorStyle: const TextStyle(color: Colors.red),
                              ),
                              validator: ExpiryDateFormatter.validate,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _addItem,
                          icon: const Icon(Icons.add_box, color: Colors.white),
                          label: const Text(
                            'Add to List',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // FULL WIDTH TABLE – ORANGE HEADER + EXPIRY COLOR LOGIC
            if (_itemsToAdd.isNotEmpty)
              Card(
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Items to Add (${_itemsToAdd.length})',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const Icon(Icons.list_alt, color: Colors.orange),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 32,
                        ),
                        child: DataTable(
                          columnSpacing: 16,
                          headingRowColor: WidgetStateProperty.all(
                            const Color(0xFF252525),
                          ),
                          columns: const [
                            DataColumn(
                              label: Text(
                                'Name',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Type',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Dose',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Qty',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Price',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Expiry',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Actions',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          rows: _itemsToAdd.asMap().entries.map((entry) {
                            int idx = entry.key;
                            Map<String, dynamic> item = entry.value;
                            final color = _getExpiryColor(item['expiryDate']);
                            String doseDisplay = '';
                            if (item['type'] == 'Nebulization') {
                              doseDisplay =
                                  '${item['distilledWater']} ml water, ${item['drops']} drops';
                            } else {
                              doseDisplay = item['dose'] ?? '';
                            }
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    item['name'],
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    item['type'],
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    doseDisplay,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    item['quantity'].toString(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    'PKR ${item['price']}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    item['expiryDate'],
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.orange,
                                        ),
                                        onPressed: () => _editItem(idx),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_forever,
                                          color: Colors.red,
                                        ),
                                        onPressed: () => _removeItem(idx),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _itemsToAdd.isEmpty ? null : _addToInventory,
                icon: const Icon(Icons.send, color: Colors.white),
                label: Text(
                  'Submit Request (${_itemsToAdd.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _itemsToAdd.isEmpty
                      ? Colors.grey[700]
                      : Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _typeIcon(String type, {double size = 20}) {
    return Icon(
      switch (type) {
        'Tablet' => FontAwesomeIcons.tablets,
        'Capsule' => FontAwesomeIcons.capsules,
        'Syrup' => FontAwesomeIcons.bottleDroplet,
        'Injection' => FontAwesomeIcons.syringe,
        'Drip' => FontAwesomeIcons.bottleDroplet,
        'Drip Set' => FontAwesomeIcons.kitMedical,
        'Syringe' => FontAwesomeIcons.syringe,
        'Nebulization' => FontAwesomeIcons.cloud,
        _ => FontAwesomeIcons.pills,
      },
      size: size,
      color: Colors.orange,
    );
  }
}

// YOUR EXACT EXPIRY FORMATTER
class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    String result = '';
    if (digits.length >= 2) {
      result += digits.substring(0, 2);
      if (digits.length > 2) result += '-';
    } else {
      result = digits;
    }
    if (digits.length >= 4) {
      result += digits.substring(2, 4);
      if (digits.length > 4) result += '-';
    } else if (digits.length > 2) {
      result += digits.substring(2);
    }
    if (digits.length > 4) {
      result += digits.substring(4);
    }
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }

  static String? validate(String? value) {
    if (value == null || value.isEmpty) return 'Enter expiry date';
    if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(value)) {
      return 'Use dd-MM-yyyy format';
    }
    try {
      final parts = value.split('-');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      if (month < 1 || month > 12) return 'Invalid month';
      if (day < 1 || day > 31) return 'Invalid day';
      final date = DateTime(year, month, day);
      final now = DateTime.now();
      if (date.isBefore(DateTime(now.year, now.month, now.day))) {
        return 'Date not permitted';
      }
      if (year < 2025) return 'Year too early';
      if (year > 2100) return 'Year too far ahead';
    } catch (_) {
      return 'Invalid date';
    }
    return null;
  }
}