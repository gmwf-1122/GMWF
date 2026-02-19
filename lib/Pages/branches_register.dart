// lib/pages/branches_register.dart

import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import '../services/auth_service.dart';

class BranchesRegister extends StatefulWidget {
  const BranchesRegister({super.key});

  @override
  State<BranchesRegister> createState() => _BranchesRegisterState();
}

class _BranchesRegisterState extends State<BranchesRegister> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _identificationController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _bankAccountController = TextEditingController();
  final TextEditingController _customDegreeController = TextEditingController();
  final TextEditingController _salaryController = TextEditingController();

  String? _selectedRole;
  String? _selectedDegree;

  XFile? _profileImageXFile;
  Uint8List? _profileImageBytes;

  PlatformFile? _identificationFile;
  PlatformFile? _degreeFile;

  bool _loading = false;
  bool _obscurePassword = true;

  final List<String> roles = ["Supervisor", "Doctor", "Receptionist", "Dispenser"];
  final List<String> degrees = ['MBBS', 'MD', 'DO', 'BDS', 'Other'];

  String? _usernameError;

  Future<bool> _usernameExists(String username) async {
    final snapshot = await FirebaseFirestore.instance.collection('branches').get();
    for (var doc in snapshot.docs) {
      final result = await FirebaseFirestore.instance
          .collection('branches')
          .doc(doc.id)
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      if (result.docs.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _pickProfileImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);

    if (pickedFile == null) return;

    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 80,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Picture',
          toolbarColor: Colors.green.shade700,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Crop Profile Picture', aspectRatioLockEnabled: true),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 500, height: 500),
          initialAspectRatio: 1.0,
        ),
      ],
    );

    if (croppedFile != null) {
      final bytes = await croppedFile.readAsBytes();
      setState(() {
        _profileImageXFile = XFile(croppedFile.path);
        _profileImageBytes = bytes;
      });
    }
  }

  void _removeProfileImage() {
    setState(() {
      _profileImageXFile = null;
      _profileImageBytes = null;
    });
  }

  Future<void> _pickDocument(String type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        if (type == 'identification') _identificationFile = result.files.first;
        if (type == 'degree') _degreeFile = result.files.first;
      });
    }
  }

  void _removeIdentificationFile() {
    setState(() {
      _identificationFile = null;
    });
  }

  void _removeDegreeFile() {
    setState(() {
      _degreeFile = null;
    });
  }

  Future<void> _registerBranch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _usernameError = null;
      _loading = true;
    });

    try {
      final branchName = _branchController.text.trim();
      final branchId = branchName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      final branchDoc = await FirebaseFirestore.instance.collection('branches').doc(branchId).get();
      if (branchDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Branch already exists"), backgroundColor: Colors.red),
        );
        return;
      }

      final username = _usernameController.text.trim();

      final exists = await _usernameExists(username);
      if (exists) {
        setState(() => _usernameError = "Username already taken");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Username already exists"), backgroundColor: Colors.red),
        );
        return;
      }

      final degree = _selectedDegree == 'Other'
          ? _customDegreeController.text.trim()
          : (_selectedDegree ?? '');

      double? salary;
      final salaryText = _salaryController.text.trim();
      if (salaryText.isNotEmpty) {
        salary = double.tryParse(salaryText);
        if (salary == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid salary format"), backgroundColor: Colors.red),
          );
          return;
        }
      }

      final user = await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        username: username,
        role: _selectedRole!,
        branchId: branchId,
        branchName: branchName,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        identification: _identificationController.text.trim().isNotEmpty ? _identificationController.text.trim() : null,
        address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        bankName: _bankNameController.text.trim().isNotEmpty ? _bankNameController.text.trim() : null,
        bankAccount: _bankAccountController.text.trim().isNotEmpty ? _bankAccountController.text.trim() : null,
        degree: degree.isNotEmpty ? degree : null,
        salary: salary,
        profileImageXFile: _profileImageXFile,
        profileImageBytes: _profileImageBytes,
        identificationFile: _identificationFile,
        degreeFile: _degreeFile,
      );

      if (user == null) {
        throw Exception("Failed to create account");
      }

      await FirebaseFirestore.instance.collection('branches').doc(branchId).set({'name': branchName});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Branch '$branchName' created successfully"),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Create New Branch", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF006D5B),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 24.0, vertical: 16.0),
              child: Center(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Image.asset("assets/logo/gmwf.png", height: isMobile ? 80 : 120),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Register New Branch",
                                      style: TextStyle(fontSize: isMobile ? 22 : 26, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Fill in the details to create a branch",
                                      style: TextStyle(fontSize: isMobile ? 12 : 14, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Profile Picture (moved to top)
                          Column(
                            children: [
                              const Text("Profile Picture - jpg/png", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              Center(
                                child: GestureDetector(
                                  onTap: _pickProfileImage,
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.green.shade700, width: 2),
                                        ),
                                        child: CircleAvatar(
                                          radius: 70,
                                          backgroundColor: Colors.grey.shade200,
                                          backgroundImage: _profileImageBytes != null ? MemoryImage(_profileImageBytes!) : null,
                                          child: _profileImageBytes == null
                                              ? Icon(Icons.camera_alt, size: 50, color: Colors.green.shade700)
                                              : null,
                                        ),
                                      ),
                                      if (_profileImageBytes != null)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: IconButton(
                                            icon: const Icon(Icons.cancel, color: Colors.red, size: 30),
                                            onPressed: _removeProfileImage,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _pickProfileImage,
                                icon: const Icon(Icons.photo_library),
                                label: const Text("Choose & Crop Profile Picture"),
                                style: TextButton.styleFrom(foregroundColor: Colors.green.shade700),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                          const SizedBox(height: 32),

                          _buildTextField(
                            controller: _branchController,
                            label: "Branch Name",
                            icon: Icons.apartment,
                            validator: (v) => v?.trim().isEmpty ?? true ? "Enter branch name" : null,
                          ),
                          const SizedBox(height: 16),

                          if (isMobile) ...[
                            _buildTextField(
                              controller: _usernameController,
                              label: "Username",
                              icon: Icons.person_outline,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return "Enter username";
                                if (_usernameError != null) return _usernameError;
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _phoneController,
                              label: "Phone Number",
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                            const SizedBox(height: 16),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _usernameController,
                                    label: "Username",
                                    icon: Icons.person_outline,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) return "Enter username";
                                      if (_usernameError != null) return _usernameError;
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    controller: _phoneController,
                                    label: "Phone Number",
                                    icon: Icons.phone_outlined,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          _buildTextField(
                            controller: _emailController,
                            label: "Email Address",
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => v?.trim().isEmpty ?? true ? "Enter email" : null,
                          ),
                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: _passwordController,
                            label: "Password",
                            icon: Icons.lock_outline,
                            isPassword: true,
                            validator: (v) => v == null || v.length < 6 ? "Password must be 6+ chars" : null,
                          ),
                          const SizedBox(height: 16),

                          if (isMobile) ...[
                            _buildTextField(
                              controller: _identificationController,
                              label: "Identification",
                              icon: Icons.credit_card,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _addressController,
                              label: "Address",
                              icon: Icons.home_outlined,
                            ),
                            const SizedBox(height: 16),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _identificationController,
                                    label: "Identification",
                                    icon: Icons.credit_card,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    controller: _addressController,
                                    label: "Address",
                                    icon: Icons.home_outlined,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (isMobile) ...[
                            _buildTextField(
                              controller: _bankNameController,
                              label: "Bank Name",
                              icon: Icons.account_balance,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _bankAccountController,
                              label: "Bank Account Number",
                              icon: Icons.account_balance_wallet,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _bankNameController,
                                    label: "Bank Name",
                                    icon: Icons.account_balance,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    controller: _bankAccountController,
                                    label: "Bank Account Number",
                                    icon: Icons.account_balance_wallet,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],

                          _buildTextField(
                            controller: _salaryController,
                            label: "Salary",
                            icon: Icons.attach_money,
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                          ),
                          const SizedBox(height: 16),

                          _buildDropdown(
                            value: _selectedRole,
                            items: roles,
                            hint: "Select Role",
                            icon: Icons.badge_outlined,
                            onChanged: (val) {
                              setState(() {
                                _selectedRole = val;
                                if (val != 'Doctor') {
                                  _selectedDegree = null;
                                  _customDegreeController.clear();
                                  _degreeFile = null;
                                }
                              });
                            },
                            validator: (val) => val == null ? "Select role" : null,
                          ),
                          const SizedBox(height: 16),

                          // Identification
                          _buildFilePickerTile(
                            "Upload Identification - pdf/jpg/png",
                            _identificationFile,
                            () => _pickDocument('identification'),
                          ),
                          const SizedBox(height: 16),
                          if (_identificationFile != null) ...[
                            const Text("Identification Preview:", style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            if (_identificationFile!.extension?.toLowerCase() != 'pdf')
                              Center(
                                child: Stack(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.green.shade700, width: 2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: kIsWeb
                                            ? Image.memory(_identificationFile!.bytes!, height: 200, fit: BoxFit.cover)
                                            : Image.file(File(_identificationFile!.path!), height: 200, fit: BoxFit.cover),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: IconButton(
                                        icon: const Icon(Icons.cancel, color: Colors.red, size: 30),
                                        onPressed: _removeIdentificationFile,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                height: 200,
                                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
                                      const SizedBox(height: 8),
                                      Text(_identificationFile!.name, textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],

                          if (_selectedRole == 'Doctor') ...[
                            _buildDropdown(
                              value: _selectedDegree,
                              items: degrees,
                              hint: "Select Degree",
                              icon: Icons.school_outlined,
                              onChanged: (val) {
                                setState(() {
                                  _selectedDegree = val;
                                  if (val != 'Other') _customDegreeController.clear();
                                });
                              },
                              validator: (val) => val == null ? "Select degree" : null,
                            ),
                            const SizedBox(height: 16),
                            if (_selectedDegree == 'Other')
                              _buildTextField(
                                controller: _customDegreeController,
                                label: "Enter Custom Degree",
                                icon: Icons.edit_outlined,
                              ),
                            const SizedBox(height: 16),
                            _buildFilePickerTile(
                              "Upload Degree Certificate - pdf/jpg/png",
                              _degreeFile,
                              () => _pickDocument('degree'),
                            ),
                            const SizedBox(height: 16),
                            if (_degreeFile != null) ...[
                              const Text("Degree Preview:", style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (_degreeFile!.extension?.toLowerCase() != 'pdf')
                                Center(
                                  child: Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.green.shade700, width: 2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: kIsWeb
                                              ? Image.memory(_degreeFile!.bytes!, height: 200, fit: BoxFit.cover)
                                              : Image.file(File(_degreeFile!.path!), height: 200, fit: BoxFit.cover),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.red, size: 30),
                                          onPressed: _removeDegreeFile,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Container(
                                  height: 200,
                                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
                                        const SizedBox(height: 8),
                                        Text(_degreeFile!.name, textAlign: TextAlign.center),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          const SizedBox(height: 32),

                          SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _registerBranch,
                              icon: const Icon(Icons.upload, size: 24),
                              label: const Text("Create Branch", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 4,
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
            if (_loading)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green.shade700),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        errorStyle: const TextStyle(fontSize: 13),
      ),
      validator: validator,
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required String hint,
    required IconData icon,
    required Function(String?) onChanged,
    required String? Function(String?) validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(hint),
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.green.shade700),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }

  Widget _buildFilePickerTile(String label, PlatformFile? file, VoidCallback onTap) {
    return ListTile(
      leading: Icon(Icons.upload_file, color: Colors.green.shade700),
      title: Text(label),
      subtitle: file != null ? Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis) : const Text("No file selected"),
      trailing: const Icon(Icons.attach_file),
      tileColor: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }

  @override
  void dispose() {
    _branchController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _identificationController.dispose();
    _addressController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    _customDegreeController.dispose();
    _salaryController.dispose();
    super.dispose();
  }
}