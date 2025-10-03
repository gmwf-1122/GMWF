// lib/pages/patient_register.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class PatientRegisterPage extends StatefulWidget {
  final String branchId;
  final String receptionistId;

  const PatientRegisterPage({
    super.key,
    required this.branchId,
    required this.receptionistId,
  });

  @override
  State<PatientRegisterPage> createState() => _PatientRegisterPageState();
}

class _PatientRegisterPageState extends State<PatientRegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();

  String? _selectedGender;
  String? _selectedBloodGroup;
  bool _isSaving = false;

  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final cnic = _cnicController.text.trim();

      final patientData = {
        "name": _nameController.text.trim(),
        "cnic": cnic,
        "phone": _phoneController.text.trim(),
        "age": int.parse(_ageController.text.trim()),
        "gender": _selectedGender,
        "bloodGroup": _selectedBloodGroup,
        "branchId": widget.branchId,
        "createdBy": widget.receptionistId,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      };

      // 🔹 Save using CNIC as document ID
      await FirebaseFirestore.instance
          .collection("branches")
          .doc(widget.branchId)
          .collection("patients")
          .doc(cnic) // Use CNIC as document ID
          .set(patientData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Patient registered successfully")),
      );

      // Reset form
      _formKey.currentState!.reset();
      _nameController.clear();
      _cnicController.clear();
      _phoneController.clear();
      _ageController.clear();
      setState(() {
        _selectedGender = null;
        _selectedBloodGroup = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error saving patient: $e")),
      );
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // ✅ allow sidebar background
      body: Container(
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage("assets/images/1.jpg"),
            fit: BoxFit.cover,
          ),
          color: Colors.green.withOpacity(0.8),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 600,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration("Full Name", Icons.person),
                      validator: (val) =>
                          val == null || val.isEmpty ? "Enter name" : null,
                    ),
                    const SizedBox(height: 16),

                    // CNIC
                    TextFormField(
                      controller: _cnicController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                          "CNIC (XXXXX-XXXXXXX-X)", Icons.credit_card),
                      inputFormatters: [CNICInputFormatter()],
                      maxLength: 15,
                      buildCounter: (context,
                              {required int currentLength,
                              required bool isFocused,
                              int? maxLength}) =>
                          null,
                      validator: (val) {
                        final regex = RegExp(r'^\d{5}-\d{7}-\d{1}$');
                        if (val == null || val.isEmpty) return "Enter CNIC";
                        if (!regex.hasMatch(val)) {
                          return "Format: 12345-1234567-1";
                        }
                        return null;
                      },
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Phone
                    TextFormField(
                      controller: _phoneController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration("Phone Number", Icons.phone),
                      maxLength: 11,
                      buildCounter: (context,
                              {required int currentLength,
                              required bool isFocused,
                              int? maxLength}) =>
                          null,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return "Enter phone number";
                        }
                        if (val.length != 11) {
                          return "Phone number must be 11 digits";
                        }
                        return null;
                      },
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    // Age
                    TextFormField(
                      controller: _ageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration("Age", Icons.cake),
                      maxLength: 3,
                      buildCounter: (context,
                              {required int currentLength,
                              required bool isFocused,
                              int? maxLength}) =>
                          null,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (val) {
                        if (val == null || val.isEmpty) return "Enter age";
                        final age = int.tryParse(val);
                        if (age == null || age < 1 || age > 120) {
                          return "Enter valid age (1-120)";
                        }
                        return null;
                      },
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Gender
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      items: ["Male", "Female", "Other"]
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedGender = val),
                      decoration: _inputDecoration("Gender", Icons.person),
                      validator: (val) => val == null ? "Select gender" : null,
                      dropdownColor: Colors.green[800],
                      style: const TextStyle(color: Colors.white),
                      iconEnabledColor: Colors.white,
                      iconDisabledColor: Colors.white,
                    ),
                    const SizedBox(height: 16),

                    // Blood Group
                    DropdownButtonFormField<String>(
                      value: _selectedBloodGroup,
                      items: ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e),
                              ))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedBloodGroup = val),
                      decoration:
                          _inputDecoration("Blood Group", Icons.bloodtype),
                      validator: (val) =>
                          val == null ? "Select blood group" : null,
                      dropdownColor: Colors.green[800],
                      style: const TextStyle(color: Colors.white),
                      iconEnabledColor: Colors.white,
                      iconDisabledColor: Colors.white,
                    ),
                    const SizedBox(height: 30),

                    // Register Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _savePatient,
                        icon: _isSaving
                            ? const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)
                            : const Icon(Icons.save),
                        label:
                            Text(_isSaving ? "Saving..." : "Register Patient"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white70),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    );
  }
}

// ✅ CNIC Formatter for proper formatting
class CNICInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 4 || i == 11) {
        if (i != digits.length - 1) buffer.write('-');
      }
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.toString().length),
    );
  }
}
