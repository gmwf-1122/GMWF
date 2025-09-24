// lib/pages/receptionist_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import 'inventory.dart';

class ReceptionistScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;

  const ReceptionistScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
  });

  @override
  State<ReceptionistScreen> createState() => _ReceptionistScreenState();
}

class _ReceptionistScreenState extends State<ReceptionistScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _tempController = TextEditingController();
  final _sugarController = TextEditingController();
  final _searchController = TextEditingController();

  String? _selectedGender;
  String? _selectedBloodGroup;
  String? _serialNumber;

  @override
  void initState() {
    super.initState();
    _generateSerialNumber();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cnicController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _tempController.dispose();
    _sugarController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 🔢 Generate ddMMyy-001 style serial per branch/day
  Future<void> _generateSerialNumber() async {
    final today = DateTime.now();
    final datePart =
        "${today.day.toString().padLeft(2, '0')}${today.month.toString().padLeft(2, '0')}${today.year.toString().substring(2)}";

    final snapshot = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('patients')
        .where('serialDate', isEqualTo: datePart)
        .orderBy('serial', descending: true)
        .limit(1)
        .get();

    int nextNumber = 1;
    if (snapshot.docs.isNotEmpty) {
      final lastSerial = snapshot.docs.first['serial'] as String?;
      if (lastSerial != null && lastSerial.contains('-')) {
        final lastNum = int.tryParse(lastSerial.split('-').last);
        if (lastNum != null) {
          nextNumber = lastNum + 1;
        }
      }
    }

    setState(() {
      _serialNumber = "$datePart-${nextNumber.toString().padLeft(3, '0')}";
    });
  }

  /// ✅ Validate & save patient
  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;
    if (_serialNumber == null) {
      await _generateSerialNumber();
    }

    final data = {
      'serial': _serialNumber,
      'serialDate': _serialNumber!.split('-')[0],
      'name': _nameController.text.trim(),
      'cnic': _cnicController.text.trim(),
      'age': _ageController.text.trim(),
      'weight': _weightController.text.trim(),
      'temperature': _tempController.text.trim(),
      'sugar': _sugarController.text.trim(),
      'gender': _selectedGender,
      'bloodGroup': _selectedBloodGroup,
      'branchId': widget.branchId,
      'receptionistId': widget.receptionistId,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('patients')
        .doc(_serialNumber) // save with serial as docId
        .set(data);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Patient saved successfully')),
    );

    _resetFormAndNextSerial();
  }

  void _resetFormAndNextSerial() {
    _formKey.currentState?.reset();
    _nameController.clear();
    _cnicController.clear();
    _ageController.clear();
    _weightController.clear();
    _tempController.clear();
    _sugarController.clear();
    setState(() {
      _selectedGender = null;
      _selectedBloodGroup = null;
    });
    _generateSerialNumber();
  }

  /// 🔒 CNIC formatter (XXXXX-XXXXXXX-X)
  TextInputFormatter get _cnicFormatter => TextInputFormatter.withFunction(
        (oldValue, newValue) {
          final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
          final capped = digits.length <= 13 ? digits : digits.substring(0, 13);
          String formatted = capped;
          if (capped.length > 5 && capped.length <= 12) {
            formatted = "${capped.substring(0, 5)}-${capped.substring(5)}";
          } else if (capped.length > 12) {
            formatted =
                "${capped.substring(0, 5)}-${capped.substring(5, 12)}-${capped.substring(12)}";
          }
          return TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        },
      );

  Widget _buildTextFormField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    IconData? icon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.green.shade700,
        title: Row(
          children: [
            Image.asset('assets/logo/gmwf.png', height: 36),
            const SizedBox(width: 10),
            const Text(
              'Receptionist',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InventoryPage(
                    branchId: widget.branchId,
                    receptionistId: widget.receptionistId,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.inventory, color: Colors.white),
            label: const Text(
              "Inventory",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text(
              "Logout",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Patient Form Card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Patient Details',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      _buildTextFormField(
                        label: 'Name',
                        controller: _nameController,
                        icon: Icons.person,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Enter name' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextFormField(
                        label: 'CNIC (00000-0000000-0)',
                        controller: _cnicController,
                        icon: Icons.credit_card,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                          LengthLimitingTextInputFormatter(15),
                          _cnicFormatter,
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter CNIC';
                          }
                          if (!RegExp(r'^\d{5}-\d{7}-\d{1}$')
                              .hasMatch(v.trim())) {
                            return 'CNIC must be 00000-0000000-0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextFormField(
                              label: 'Age',
                              controller: _ageController,
                              icon: Icons.cake,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextFormField(
                              label: 'Weight (kg)',
                              controller: _weightController,
                              icon: Icons.monitor_weight,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextFormField(
                              label: 'Temp (°C)',
                              controller: _tempController,
                              icon: Icons.thermostat,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.]')),
                                LengthLimitingTextInputFormatter(3),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextFormField(
                              label: 'Sugar',
                              controller: _sugarController,
                              icon: Icons.bloodtype,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(3),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedGender,
                              hint: const Text('Select Gender'),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.wc),
                              ),
                              items: ['Male', 'Female', 'Other']
                                  .map((g) => DropdownMenuItem(
                                        value: g,
                                        child: Text(g),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedGender = v),
                              validator: (v) =>
                                  v == null ? 'Please select gender' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedBloodGroup,
                              hint: const Text('Select Blood Group'),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.bloodtype),
                              ),
                              items: [
                                'A+',
                                'A-',
                                'B+',
                                'B-',
                                'O+',
                                'O-',
                                'AB+',
                                'AB-'
                              ]
                                  .map((bg) => DropdownMenuItem(
                                        value: bg,
                                        child: Text(bg),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedBloodGroup = v),
                              validator: (v) => v == null
                                  ? 'Please select blood group'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Confirm'),
                          onPressed: () async {
                            if (_selectedGender == null ||
                                _selectedBloodGroup == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Please select gender and blood group')),
                              );
                              return;
                            }
                            if (_formKey.currentState!.validate()) {
                              await _savePatient();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🔹 Unified bottom card for Serial + Search
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_serialNumber != null)
                      Text('Current Serial: $_serialNumber',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by Serial or CNIC',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                      ),
                      onChanged: (v) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Patients list
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('patients')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();

                final query = _searchController.text.trim().toLowerCase();
                final docs = snapshot.data!.docs.where((doc) {
                  final serial = (doc['serial'] ?? '').toString().toLowerCase();
                  final cnic = (doc['cnic'] ?? '').toString().toLowerCase();
                  if (query.isEmpty) return true;
                  return serial.contains(query) || cnic.contains(query);
                }).toList();

                if (_searchController.text.isNotEmpty && docs.isEmpty) {
                  return const Text('❌ No patient found');
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final d = docs[index].data() as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        title: Text(d['name'] ?? 'Unnamed'),
                        subtitle: Text('Serial: ${d['serial'] ?? '-'}'),
                        trailing: Text('CNIC: ${d['cnic'] ?? '-'}'),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
