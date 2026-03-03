// lib/pages/patient_register.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../services/firestore_service.dart';
import '../../../services/local_storage_service.dart';

class PatientRegisterPage extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String? initialCnic;
  final void Function(String patientId)? onPatientRegistered;

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

  final _nameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();

  String? _selectedGender;
  String? _selectedBloodGroup;
  String _visitType = 'Zakat';
  int _calculatedAge = 0;
  bool _isSaving = false;
  bool _isChild = false;

  final _nameNode = FocusNode();
  final _cnicNode = FocusNode();
  final _phoneNode = FocusNode();
  final _dobNode = FocusNode();
  final _genderNode = FocusNode();
  final _bloodGroupNode = FocusNode();
  final _visitNode = FocusNode();
  final _registerButtonNode = FocusNode();

  final _nameKey = GlobalKey();
  final _cnicKey = GlobalKey();
  final _phoneKey = GlobalKey();
  final _dobKey = GlobalKey();
  final _genderKey = GlobalKey();
  final _bloodGroupKey = GlobalKey();
  final _visitKey = GlobalKey();

  List<FocusNode> get activeFocusNodes {
    if (_isChild) {
      return [
        _cnicNode,
        _phoneNode,
        _nameNode,
        _dobNode,
        _genderNode,
        _bloodGroupNode,
        _visitNode,
        _registerButtonNode,
      ];
    } else {
      return [
        _nameNode,
        _cnicNode,
        _phoneNode,
        _dobNode,
        _genderNode,
        _bloodGroupNode,
        _visitNode,
        _registerButtonNode,
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    _addFocusListeners();
    if (widget.initialCnic != null && widget.initialCnic!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        prefillCnic(widget.initialCnic!);
      });
    }
  }

  void _addFocusListeners() {
    void scrollToContext(BuildContext? context) {
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }

    _nameNode.addListener(() {
      if (_nameNode.hasFocus) scrollToContext(_nameKey.currentContext);
    });
    _cnicNode.addListener(() {
      if (_cnicNode.hasFocus) scrollToContext(_cnicKey.currentContext);
    });
    _phoneNode.addListener(() {
      if (_phoneNode.hasFocus) scrollToContext(_phoneKey.currentContext);
    });
    _dobNode.addListener(() {
      if (_dobNode.hasFocus) scrollToContext(_dobKey.currentContext);
    });
    _genderNode.addListener(() {
      if (_genderNode.hasFocus) scrollToContext(_genderKey.currentContext);
    });
    _bloodGroupNode.addListener(() {
      if (_bloodGroupNode.hasFocus) scrollToContext(_bloodGroupKey.currentContext);
    });
    _visitNode.addListener(() {
      if (_visitNode.hasFocus) scrollToContext(_visitKey.currentContext);
    });
  }

  @override
  void dispose() {
    _formScopeNode.dispose();
    for (var c in [_nameController, _cnicController, _phoneController, _dobController]) {
      c.dispose();
    }
    for (var n in [
      _nameNode,
      _cnicNode,
      _phoneNode,
      _dobNode,
      _genderNode,
      _bloodGroupNode,
      _visitNode,
      _registerButtonNode,
    ]) {
      n.dispose();
    }
    super.dispose();
  }

  void prefillCnic(String cnic) {
    setState(() {
      _cnicController.text = _formatCnic(cnic);
    });
    _nameNode.requestFocus();
  }

  String _formatCnic(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 5) return digits;
    if (digits.length <= 12) return '${digits.substring(0, 5)}-${digits.substring(5)}';
    return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-${digits.substring(12)}';
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
    if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) {
      age--;
    }
    setState(() => _calculatedAge = age);
  }

  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Registration'),
        content: const Text('Are you sure you want to register this patient?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    final formattedCnic = _cnicController.text.trim();
    final cleanCnic = formattedCnic.replaceAll('-', '');

    setState(() => _isSaving = true);

    try {
      final parts = _dobController.text.split('-');
      final dob = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));

      final patientMap = {
        'name': _nameController.text.trim(),
        'isAdult': !_isChild,
        'guardianCnic': _isChild ? formattedCnic : null,
        'cnic': _isChild ? null : formattedCnic,
        'dob': dob,
        'gender': _selectedGender,
        'bloodGroup': _selectedBloodGroup ?? 'N/A',
        'status': _visitType,
        'phone': _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        'age': _calculatedAge,
        'branchId': widget.branchId,
        'createdBy': widget.receptionistId,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final patientId = LocalStorageService.getPatientKey(patientMap);
      patientMap['patientId'] = patientId;

      if (Hive.box(LocalStorageService.patientsBox).containsKey(patientId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Patient with this identifier already exists!"),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await FirestoreService().savePatient(
        branchId: widget.branchId,
        patientId: patientId,
        patientData: patientMap,
      );

      final message = _isChild ? 'Child patient registered successfully!' : 'Adult patient registered successfully!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );

      widget.onPatientRegistered?.call(patientId);

      _nameController.clear();
      _cnicController.clear();
      _phoneController.clear();
      _dobController.clear();
      setState(() {
        _selectedGender = null;
        _selectedBloodGroup = null;
        _visitType = 'Zakat';
        _isChild = false;
        _calculatedAge = 0;
      });
    } catch (e, stack) {
      print('Patient registration failed: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _normalizeName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final formWidth = isMobile ? double.infinity : 480.0;
    final fontSize = isMobile ? 14.0 : 16.0;

    return FocusScope(
      node: _formScopeNode,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (_genderNode.hasFocus) {
            String? newValue;
            if (event.logicalKey == LogicalKeyboardKey.keyM) newValue = 'Male';
            else if (event.logicalKey == LogicalKeyboardKey.keyF) newValue = 'Female';
            else if (event.logicalKey == LogicalKeyboardKey.keyO) newValue = 'Other';
            if (newValue != null) {
              setState(() => _selectedGender = newValue);
              _formScopeNode.requestFocus(_bloodGroupNode);
              return KeyEventResult.handled;
            }
          }
          if (_visitNode.hasFocus) {
            if (event.logicalKey == LogicalKeyboardKey.keyZ) {
              setState(() => _visitType = 'Zakat');
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyN) {
              setState(() => _visitType = 'Non-Zakat');
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyG) {
              setState(() => _visitType = 'GMWF');
              return KeyEventResult.handled;
            }
          }
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
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green[200]!, width: 1.5),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/logo/gmwf.png', height: isMobile ? 80 : 100),
                    const SizedBox(height: 16),
                    Text(
                      'Patient Registration',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_add, color: Colors.green[900], size: isMobile ? 18 : 20),
                              SizedBox(width: isMobile ? 4 : 8),
                              Text(
                                'Registration Type',
                                style: TextStyle(color: Colors.green[700], fontSize: isMobile ? 12 : 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<bool>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('Adult', style: TextStyle(color: Colors.green[900], fontSize: fontSize)),
                                  value: false,
                                  groupValue: _isChild,
                                  activeColor: Colors.green,
                                  onChanged: (v) => setState(() => _isChild = v!),
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<bool>(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('Child', style: TextStyle(color: Colors.green[900], fontSize: fontSize)),
                                  value: true,
                                  groupValue: _isChild,
                                  activeColor: Colors.green,
                                  onChanged: (v) {
                                    setState(() {
                                      if (!_isChild && v == true) {
                                        _nameController.clear();
                                        _dobController.clear();
                                      }
                                      _isChild = v!;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _cnicController,
                      label: _isChild ? 'Guardian CNIC (XXXXX-XXXXXXX-X)' : 'CNIC (XXXXX-XXXXXXX-X)',
                      icon: Icons.credit_card,
                      focusNode: _cnicNode,
                      key: _cnicKey,
                      maxLength: 15,
                      inputFormatters: [CNICInputFormatter()],
                      validator: (v) {
                        final r = RegExp(r'^\d{5}-\d{7}-\d{1}$');
                        if (v?.isEmpty ?? true) return 'Enter ${_isChild ? 'Guardian ' : ''}CNIC';
                        if (!r.hasMatch(v!)) return 'Format: 12345-1234567-1';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number (optional)',
                      icon: Icons.phone,
                      focusNode: _phoneNode,
                      key: _phoneKey,
                      maxLength: 11,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v != null && v.isNotEmpty && v.length != 11) {
                          return 'Phone must be 11 digits';
                        }
                        return null;
                      },
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name${_isChild ? ' (Child)' : ''}',
                      icon: Icons.person,
                      focusNode: _nameNode,
                      key: _nameKey,
                      validator: (v) => v?.isEmpty ?? true ? 'Enter name' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: _dobKey,
                      controller: _dobController,
                      focusNode: _dobNode,
                      cursorColor: Colors.green[900],
                      style: TextStyle(color: Colors.green[900], fontSize: fontSize - 2),
                      decoration: _inputDecoration(
                        '${_isChild ? 'Child ' : ''}Date of Birth (dd-MM-yyyy)',
                        Icons.cake,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                        LengthLimitingTextInputFormatter(10),
                        _DobFormatter(),
                      ],
                      keyboardType: TextInputType.datetime,
                      validator: (v) {
                        if (v!.isEmpty) return 'Enter DOB';
                        if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(v)) return 'Use dd-MM-yyyy';

                        final parts = v.split('-');
                        final day = int.tryParse(parts[0]) ?? 0;
                        final month = int.tryParse(parts[1]) ?? 0;
                        final year = int.tryParse(parts[2]) ?? 0;

                        if (day < 1 || day > 31) return 'Day must be 01-31';
                        if (month < 1 || month > 12) return 'Month must be 01-12';
                        if (year < 1900 || year > DateTime.now().year + 1) {
                          return 'Year must be between 1900 and ${DateTime.now().year + 1}';
                        }

                        try {
                          final date = DateTime(year, month, day);
                          if (date.day != day || date.month != month) {
                            return 'Invalid date (e.g., Feb 30 does not exist)';
                          }

                          _calculateAge(v);
                          return null;
                        } catch (_) {
                          return 'Invalid date';
                        }
                      },
                      onChanged: _calculateAge,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _formScopeNode.requestFocus(_genderNode),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      focusNode: _genderNode,
                      value: _selectedGender,
                      label: '${_isChild ? 'Child ' : ''}Gender',
                      icon: Icons.person_outline,
                      key: _genderKey,
                      items: const ['Male', 'Female', 'Other'],
                      onChanged: (val) {
                        setState(() => _selectedGender = val);
                        _formScopeNode.requestFocus(_bloodGroupNode);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown(
                      focusNode: _bloodGroupNode,
                      value: _selectedBloodGroup,
                      label: '${_isChild ? 'Child ' : ''}Blood Group',
                      icon: Icons.bloodtype_outlined,
                      key: _bloodGroupKey,
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
                    Focus(
                      focusNode: _visitNode,
                      child: Container(
                        key: _visitKey,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.mosque, color: Colors.green[900], size: isMobile ? 18 : 20),
                                SizedBox(width: isMobile ? 4 : 8),
                                Text(
                                  'Visit Type',
                                  style: TextStyle(color: Colors.green[700], fontSize: isMobile ? 12 : 14),
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
                                    title: Text('Zakat', style: TextStyle(color: Colors.green[900], fontSize: fontSize)),
                                    value: 'Zakat',
                                    groupValue: _visitType,
                                    activeColor: Colors.green,
                                    onChanged: (v) => setState(() => _visitType = v!),
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<String>(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text('Non-Zakat', style: TextStyle(color: Colors.green[900], fontSize: fontSize)),
                                    value: 'Non-Zakat',
                                    groupValue: _visitType,
                                    activeColor: Colors.green,
                                    onChanged: (v) => setState(() => _visitType = v!),
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<String>(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text('GMWF', style: TextStyle(color: Colors.green[900], fontSize: fontSize)),
                                    value: 'GMWF',
                                    groupValue: _visitType,
                                    activeColor: Colors.green,
                                    onChanged: (v) => setState(() => _visitType = v!),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Focus(
                      focusNode: _registerButtonNode,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _savePatient,
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save, size: 18),
                        label: Text(_isSaving ? 'Saving...' : 'Register Patient'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.green[500],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required FocusNode focusNode,
    GlobalKey? key,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return TextFormField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      cursorColor: Colors.green[900],
      style: TextStyle(color: Colors.green[900], fontSize: isMobile ? 14 : 16),
      decoration: _inputDecoration(label, icon),
      validator: validator,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) {
        final idx = activeFocusNodes.indexOf(focusNode);
        if (idx < activeFocusNodes.length - 1) {
          _formScopeNode.requestFocus(activeFocusNodes[idx + 1]);
        }
      },
    );
  }

  Widget _buildDropdown({
    required FocusNode focusNode,
    required String? value,
    required String label,
    required IconData icon,
    required GlobalKey? key,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return DropdownButtonFormField2<String>(
      key: key,
      focusNode: focusNode,
      isExpanded: true,
      value: value,
      items: items.map((e) => DropdownMenuItem<String>(value: e, child: Text(e, style: TextStyle(color: Colors.green[900])))).toList(),
      onChanged: onChanged,
      decoration: _inputDecoration(label, icon),
      validator: (val) => val == null ? 'Select $label' : null,
      style: TextStyle(color: Colors.green[900], fontSize: isMobile ? 14 : 16),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.green),
      prefixIcon: Icon(icon, color: Colors.green[900]),
      filled: true,
      fillColor: Colors.green[50],
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.green),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.green, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

class CNICInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
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
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) {
    var t = newVal.text.replaceAll(RegExp(r'\D'), '');
    if (t.length > 8) t = t.substring(0, 8);

    final b = StringBuffer();

    if (t.isNotEmpty) {
      var day = t.substring(0, t.length.clamp(0, 2));
      if (day.length == 2) {
        final d = int.tryParse(day) ?? 0;
        if (d > 31 || d == 0) day = day[0];
      }
      b.write(day);
    }

    if (t.length > 2) {
      b.write('-');
      var month = t.substring(2, t.length.clamp(2, 4));
      if (month.length == 2) {
        final m = int.tryParse(month) ?? 0;
        if (m > 12 || m == 0) month = month[0];
      }
      b.write(month);
    }

    if (t.length > 4) {
      b.write('-');
      b.write(t.substring(4));
    }

    final formatted = b.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}