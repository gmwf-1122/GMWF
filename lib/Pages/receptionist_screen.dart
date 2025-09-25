import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/patient.dart';
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
  final _bpController = TextEditingController();
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
    _bpController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 🔢 Generate next serial safely
  Future<void> _generateSerialNumber() async {
    try {
      final today = DateTime.now();
      final datePart = DateFormat("ddMMyy").format(today);
      final serialsRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(datePart);

      final serialSnap = await serialsRef.get();

      int lastNum = 0;
      if (serialSnap.exists) {
        lastNum = serialSnap.data()?['lastNumber'] ?? 0;
      } else {
        await serialsRef.set({'lastNumber': 0});
      }

      final nextNum = lastNum + 1;
      if (mounted) {
        setState(() {
          _serialNumber = "$datePart-${nextNum.toString().padLeft(3, '0')}";
        });
      }
    } catch (e) {
      debugPrint('❌ Error generating serial: $e');
      if (mounted) setState(() => _serialNumber = null);
    }
  }

  /// ✅ Save patient using Patient model
  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;
    if (_serialNumber == null) await _generateSerialNumber();
    if (_serialNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Could not generate serial.')));
      return;
    }

    final today = DateTime.now();
    final datePart = DateFormat("ddMMyy").format(today);
    final cnic = _cnicController.text.trim();
    final branchPatientRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('patients')
        .doc(cnic);

    try {
      // Increment serial safely
      final serialsRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(datePart);
      final serialSnap = await serialsRef.get();
      int lastNum = serialSnap.exists ? serialSnap['lastNumber'] ?? 0 : 0;
      final nextNum = lastNum + 1;
      final newSerial = "$datePart-${nextNum.toString().padLeft(3, '0')}";
      await serialsRef.set({'lastNumber': nextNum});

      // Create Patient object
      final patient = Patient(
        id: cnic,
        name: _nameController.text.trim(),
        branchId: widget.branchId,
        createdBy: widget.receptionistId,
        status: 'New',
        visitDetails: {
          'serial': newSerial,
          'serialDate': datePart,
          'age': _ageController.text.trim(),
          'weight': _weightController.text.trim(),
          'temperature': _tempController.text.trim(),
          'sugar': _sugarController.text.trim(),
          'bloodPressure': _bpController.text.trim(),
          'gender': _selectedGender,
          'bloodGroup': _selectedBloodGroup,
        },
      );

      await branchPatientRef.set(patient.toMap(), SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Patient saved with serial $newSerial')));
      _resetFormAndNextSerial();
    } catch (e) {
      debugPrint('❌ Error saving patient: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Failed to save patient')));
    }
  }

  void _resetFormAndNextSerial() {
    _formKey.currentState?.reset();
    _nameController.clear();
    _cnicController.clear();
    _ageController.clear();
    _weightController.clear();
    _tempController.clear();
    _sugarController.clear();
    _bpController.clear();
    setState(() {
      _selectedGender = null;
      _selectedBloodGroup = null;
    });
    _generateSerialNumber();
  }

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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF43A047), Color.fromARGB(255, 173, 250, 177)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            // AppBar replacement
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              height: 70,
              color: Colors.transparent,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Image.asset('assets/logo/gmwf.png', height: 50),
                    const SizedBox(width: 10),
                    const Text('Receptionist',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20)),
                  ]),
                  Row(children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InventoryPage(
                              branchId: widget.branchId,
                              receptionistId: widget.receptionistId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.inventory, color: Colors.green),
                      label: const Text("Inventory",
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacementNamed('/login');
                        }
                      },
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text("Logout",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            // Gradient Red Strip 20px
            Container(
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.redAccent, Colors.red],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Body: patient form + list
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 1, child: _buildPatientForm()),
                    const SizedBox(width: 16),
                    Expanded(flex: 1, child: _buildPatientsList()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientForm() {
    return SingleChildScrollView(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Patient Details',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text('Serial no:  ${_serialNumber ?? "--"}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
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
                  if (v == null || v.trim().isEmpty) return 'Enter CNIC';
                  if (!RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(v.trim())) {
                    return 'CNIC must be 00000-0000000-0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _buildTextFormField(
                    label: 'Age',
                    controller: _ageController,
                    icon: Icons.cake,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3)
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
                      LengthLimitingTextInputFormatter(3)
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _buildTextFormField(
                    label: 'Temp (°C)',
                    controller: _tempController,
                    icon: Icons.thermostat,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      LengthLimitingTextInputFormatter(3)
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextFormField(
                    label: 'Sugar',
                    controller: _sugarController,
                    icon: Icons.bubble_chart,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3)
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextFormField(
                    label: 'Blood Pressure (e.g. 120/80)',
                    controller: _bpController,
                    icon: Icons.favorite,
                    keyboardType: TextInputType.text,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
                      LengthLimitingTextInputFormatter(7)
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedGender,
                    hint: const Text('Select Gender'),
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.wc)),
                    items: ['Male', 'Female', 'Other']
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedGender = v),
                    validator: (v) => v == null ? 'Please select gender' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedBloodGroup,
                    hint: const Text('Select Blood Group'),
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.bloodtype)),
                    items: ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-']
                        .map((bg) =>
                            DropdownMenuItem(value: bg, child: Text(bg)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBloodGroup = v),
                    validator: (v) =>
                        v == null ? 'Please select blood group' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Confirm',
                      style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    if (_selectedGender == null ||
                        _selectedBloodGroup == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🚩 Fill the Form')));
                      return;
                    }
                    if (_formKey.currentState!.validate()) {
                      await _savePatient();
                    }
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildPatientsList() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by Serial or CNIC',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            ),
            onChanged: (v) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('patients')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final patients = snapshot.data!.docs
                    .map((doc) => Patient.fromDoc(doc))
                    .where((p) {
                  final query = _searchController.text.trim().toLowerCase();
                  return query.isEmpty ||
                      (p.visitDetails?['serial'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(query) ||
                      p.id.toLowerCase().contains(query);
                }).toList();

                if (_searchController.text.isNotEmpty && patients.isEmpty) {
                  return const Center(child: Text('❌ No patient found'));
                }

                return ListView.builder(
                  itemCount: patients.length,
                  itemBuilder: (context, index) {
                    final p = patients[index];
                    return ExpansionTile(
                      title: Text(
                          '${p.name} (Serial: ${p.visitDetails?['serial'] ?? "--"})'),
                      subtitle: Text('CNIC: ${p.id}'),
                      children: [
                        ListTile(
                          title: Text(
                              'Age: ${p.visitDetails?['age'] ?? '--'}, Weight: ${p.visitDetails?['weight'] ?? '--'}, Temp: ${p.visitDetails?['temperature'] ?? '--'}, Sugar: ${p.visitDetails?['sugar'] ?? '--'}, BP: ${p.visitDetails?['bloodPressure'] ?? '--'}'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
