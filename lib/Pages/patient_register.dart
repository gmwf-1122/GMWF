// lib/pages/patient_register.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

class PatientRegisterPage extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String? initialCnic;
  final void Function(String cnic)? onPatientRegistered;

  const PatientRegisterPage({
    super.key,
    required this.branchId,
    required this.receptionistId,
    this.initialCnic,
    this.onPatientRegistered,
  });

  @override
  State<PatientRegisterPage> createState() => PatientRegisterPageState();
}

class PatientRegisterPageState extends State<PatientRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _formScopeNode = FocusScopeNode();

  // Controllers
  final _nameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();

  // State
  String? _selectedGender;
  String? _selectedBloodGroup;
  String _visitType = 'Zakat';
  int _calculatedAge = 0;
  bool _isSaving = false;

  // Focus nodes (order matters for Tab / Arrow navigation)
  final _nameNode = FocusNode();
  final _cnicNode = FocusNode();
  final _phoneNode = FocusNode();
  final _dobNode = FocusNode();
  final _genderNode = FocusNode();
  final _bloodGroupNode = FocusNode();
  final _visitNode = FocusNode();
  final _registerButtonNode = FocusNode();

  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _focusNodes = [
      _nameNode,
      _cnicNode,
      _phoneNode,
      _dobNode,
      _genderNode,
      _bloodGroupNode,
      _visitNode,
      _registerButtonNode,
    ];

    if (widget.initialCnic != null && widget.initialCnic!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cnicController.text = _formatCnic(widget.initialCnic!);
        _nameNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _formScopeNode.dispose();
    for (var c in [
      _nameController,
      _cnicController,
      _phoneController,
      _dobController
    ]) {
      c.dispose();
    }
    for (var n in _focusNodes) n.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------
  void prefillCnic(String cnic) {
    setState(() => _cnicController.text = _formatCnic(cnic));
    _nameNode.requestFocus();
  }

  String _formatCnic(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9]'), '');
    final b = StringBuffer();
    for (int i = 0; i < d.length; i++) {
      b.write(d[i]);
      if (i == 4 || i == 11) if (i != d.length - 1) b.write('-');
    }
    return b.toString();
  }

  void _calculateAge(String dob) {
    if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(dob)) {
      setState(() => _calculatedAge = 0);
      return;
    }
    final p = dob.split('-');
    final birth = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    final today = DateTime.now();
    int age = today.year - birth.year;
    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) age--;
    setState(() => _calculatedAge = age);
  }

  // -----------------------------------------------------------------
  // Save patient
  // -----------------------------------------------------------------
  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;

    final cnic = _cnicController.text.trim();
    setState(() => _isSaving = true);

    try {
      final branchRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('patients');

      final existing = await branchRef.doc(cnic).get();
      if (existing.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A patient with this CNIC already exists.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final parts = _dobController.text.split('-');
      final dob = DateTime(
          int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));

      await branchRef.doc(cnic).set({
        'name': _nameController.text.trim(),
        'cnic': cnic,
        'phone': _phoneController.text.trim(),
        'dob': Timestamp.fromDate(dob),
        'age': _calculatedAge,
        'gender': _selectedGender,
        'bloodGroup': _selectedBloodGroup ?? 'N/A',
        'status': _visitType,
        'branchId': widget.branchId,
        'createdBy': widget.receptionistId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient registered!'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onPatientRegistered?.call(cnic);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // -----------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final formWidth = isMobile ? double.infinity : 480.0;

    return FocusScope(
      node: _formScopeNode,
      onKey: (node, event) {
        // Handle M F O when gender has focus
        if (event is RawKeyDownEvent && _genderNode.hasFocus) {
          String? newValue;
          if (event.logicalKey == LogicalKeyboardKey.keyM)
            newValue = 'Male';
          else if (event.logicalKey == LogicalKeyboardKey.keyF)
            newValue = 'Female';
          else if (event.logicalKey == LogicalKeyboardKey.keyO)
            newValue = 'Other';
          if (newValue != null) {
            setState(() => _selectedGender = newValue);
            _formScopeNode.requestFocus(_bloodGroupNode);
            return KeyEventResult.handled;
          }
        }

        // Handle Z N when visit has focus
        if (event is RawKeyDownEvent && _visitNode.hasFocus) {
          if (event.logicalKey == LogicalKeyboardKey.keyZ) {
            setState(() => _visitType = 'Zakat');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyN) {
            setState(() => _visitType = 'Non-Zakat');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            setState(() =>
                _visitType = _visitType == 'Zakat' ? 'Non-Zakat' : 'Zakat');
            return KeyEventResult.handled;
          }
        }

        // Tab / Shift+Tab
        if (event.isKeyPressed(LogicalKeyboardKey.tab)) {
          final idx = _focusNodes.indexWhere((f) => f.hasFocus);
          if (idx == -1) return KeyEventResult.ignored;
          final next = event.isShiftPressed
              ? (idx - 1 + _focusNodes.length) % _focusNodes.length
              : (idx + 1) % _focusNodes.length;
          _formScopeNode.requestFocus(_focusNodes[next]);
          return KeyEventResult.handled;
        }

        // Arrow Up / Down
        if (event.isKeyPressed(LogicalKeyboardKey.arrowDown) ||
            event.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
          final idx = _focusNodes.indexWhere((f) => f.hasFocus);
          if (idx == -1) return KeyEventResult.ignored;
          final next = event.isKeyPressed(LogicalKeyboardKey.arrowDown)
              ? (idx + 1) % _focusNodes.length
              : (idx - 1 + _focusNodes.length) % _focusNodes.length;
          _formScopeNode.requestFocus(_focusNodes[next]);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: formWidth,
              margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withOpacity(0.4), width: 1.5),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Patient Registration',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ---- Name ----
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person,
                      focusNode: _nameNode,
                      validator: (v) =>
                          v?.isEmpty ?? true ? 'Enter name' : null,
                    ),
                    const SizedBox(height: 12),

                    // ---- CNIC ----
                    _buildTextField(
                      controller: _cnicController,
                      label: 'CNIC (XXXXX-XXXXXXX-X)',
                      icon: Icons.credit_card,
                      focusNode: _cnicNode,
                      maxLength: 15,
                      inputFormatters: [CNICInputFormatter()],
                      validator: (v) {
                        final r = RegExp(r'^\d{5}-\d{7}-\d{1}$');
                        if (v?.isEmpty ?? true) return 'Enter CNIC';
                        if (!r.hasMatch(v!)) return 'Format: 12345-1234567-1';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // ---- Phone ----
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      icon: Icons.phone,
                      focusNode: _phoneNode,
                      maxLength: 11,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v?.isEmpty ?? true) return 'Enter phone';
                        if (v!.length != 11) return 'Phone must be 11 digits';
                        return null;
                      },
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),

                    // ---- DOB (text) ----
                    TextFormField(
                      controller: _dobController,
                      focusNode: _dobNode,
                      cursorColor: Colors.white,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDecoration(
                          'Date of Birth (dd-MM-yyyy)', Icons.cake),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                        LengthLimitingTextInputFormatter(10),
                        _DobFormatter(),
                      ],
                      keyboardType: TextInputType.datetime,
                      validator: (v) {
                        if (v!.isEmpty) return 'Enter DOB';
                        if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(v))
                          return 'Use dd-MM-yyyy';
                        try {
                          final p = v.split('-');
                          DateTime(int.parse(p[2]), int.parse(p[1]),
                              int.parse(p[0]));
                          _calculateAge(v);
                          return null;
                        } catch (_) {
                          return 'Invalid date';
                        }
                      },
                      onChanged: _calculateAge,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          _formScopeNode.requestFocus(_genderNode),
                    ),
                    const SizedBox(height: 12),

                    // ---- Gender ----
                    _buildDropdown(
                      focusNode: _genderNode,
                      value: _selectedGender,
                      label: 'Gender',
                      icon: Icons.person_outline,
                      items: const ['Male', 'Female', 'Other'],
                      onChanged: (val) {
                        setState(() => _selectedGender = val);
                        _formScopeNode.requestFocus(_bloodGroupNode);
                      },
                    ),
                    const SizedBox(height: 12),

                    // ---- Blood Group ----
                    _buildDropdown(
                      focusNode: _bloodGroupNode,
                      value: _selectedBloodGroup,
                      label: 'Blood Group',
                      icon: Icons.bloodtype_outlined,
                      items: const [
                        'N/A',
                        'A+',
                        'A-',
                        'B+',
                        'B-',
                        'AB+',
                        'AB-',
                        'O+',
                        'O-',
                      ],
                      onChanged: (val) {
                        setState(() => _selectedBloodGroup = val);
                        _formScopeNode.requestFocus(_visitNode);
                      },
                    ),
                    const SizedBox(height: 12),

                    // ---- Visit Type (Zakat / Non-Zakat) ----
                    Focus(
                      focusNode: _visitNode,
                      onKey: (node, event) {
                        if (event is RawKeyDownEvent) {
                          if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft ||
                              event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight) {
                            setState(() {
                              _visitType =
                                  _visitType == 'Zakat' ? 'Non-Zakat' : 'Zakat';
                            });
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white70),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.mosque,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Visit Type',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: RadioListTile<String>(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Zakat',
                                        style: TextStyle(color: Colors.white)),
                                    value: 'Zakat',
                                    groupValue: _visitType,
                                    activeColor: Colors.amber,
                                    onChanged: (v) =>
                                        setState(() => _visitType = v!),
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<String>(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Non-Zakat',
                                        style: TextStyle(color: Colors.white)),
                                    value: 'Non-Zakat',
                                    groupValue: _visitType,
                                    activeColor: Colors.amber,
                                    onChanged: (v) =>
                                        setState(() => _visitType = v!),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ---- Register Button ----
                    Focus(
                      focusNode: _registerButtonNode,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _savePatient,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.save, size: 18),
                        label:
                            Text(_isSaving ? 'Saving...' : 'Register Patient'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
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

  // -----------------------------------------------------------------
  // Re-usable widgets
  // -----------------------------------------------------------------
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required FocusNode focusNode,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      cursorColor: Colors.white,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: _inputDecoration(label, icon),
      validator: validator,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) {
        final idx = _focusNodes.indexOf(focusNode);
        if (idx < _focusNodes.length - 1) {
          _formScopeNode.requestFocus(_focusNodes[idx + 1]);
        }
      },
    );
  }

  Widget _buildDropdown({
    required FocusNode focusNode,
    required String? value,
    required String label,
    required IconData icon,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField2<String>(
      focusNode: focusNode,
      isExpanded: true,
      value: value,
      items: items
          .map((e) => DropdownMenuItem<String>(
                value: e,
                child: Text(e, style: const TextStyle(color: Colors.white)),
              ))
          .toList(),
      onChanged: onChanged,
      onMenuStateChange: (open) {
        if (!open) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) _formScopeNode.requestFocus(focusNode);
          });
        }
      },
      dropdownStyleData: DropdownStyleData(
        decoration: BoxDecoration(
            color: Colors.green[900], borderRadius: BorderRadius.circular(8)),
      ),
      iconStyleData: const IconStyleData(
          icon: Icon(Icons.arrow_drop_down, color: Colors.white)),
      decoration: _inputDecoration(label, icon),
      validator: (val) => val == null ? 'Select $label' : null,
      style: const TextStyle(color: Colors.white, fontSize: 14),
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
        borderSide: const BorderSide(color: Colors.white, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

// -----------------------------------------------------------------
// Formatters
// -----------------------------------------------------------------
class CNICInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 4 || i == 11) if (i != digits.length - 1) buffer.write('-');
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

class _DobFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue newVal) {
    var t = newVal.text.replaceAll(RegExp(r'\D'), '');
    if (t.length > 8) t = t.substring(0, 8);
    final b = StringBuffer();
    for (int i = 0; i < t.length; i++) {
      if (i == 2 || i == 4) b.write('-');
      b.write(t[i]);
    }
    return TextEditingValue(
      text: b.toString(),
      selection: TextSelection.collapsed(offset: b.length),
    );
  }
}
