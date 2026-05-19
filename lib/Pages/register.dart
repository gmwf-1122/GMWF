// lib/pages/register.dart

import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import '../services/auth_service.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  String? _selectedRole;
  String? _selectedBranch;
  String? _selectedDegree;

  final TextEditingController _usernameController       = TextEditingController();
  final TextEditingController _emailController          = TextEditingController();
  final TextEditingController _passwordController       = TextEditingController();
  final TextEditingController _phoneController          = TextEditingController();
  final TextEditingController _identificationController = TextEditingController();
  final TextEditingController _addressController        = TextEditingController();
  final TextEditingController _bankNameController       = TextEditingController();
  final TextEditingController _bankAccountController    = TextEditingController();
  final TextEditingController _customDegreeController   = TextEditingController();
  final TextEditingController _salaryController         = TextEditingController();
  final TextEditingController _studentRollSearchController = TextEditingController();

  String? _selectedStudentId;
  List<Map<String, dynamic>> _branchStudents = [];

  XFile?        _profileImageXFile;
  Uint8List?    _profileImageBytes;
  PlatformFile? _identificationFile;
  PlatformFile? _degreeFile;

  bool _loading         = false;
  bool _obscurePassword = true;

  late AnimationController _animController;
  late Animation<double>   _fadeAnim;

  // ── Roles ────────────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> _roleItems = [
    {'label': 'CEO',              'icon': Icons.workspace_premium_rounded,    'type': 'crown'},
    {'label': 'Admin',            'icon': Icons.workspace_premium_rounded,    'type': 'crown'},
    {'label': 'Chairman',         'icon': Icons.workspace_premium_rounded,    'type': 'crown'},
    {'label': 'HQ Manager',       'icon': Icons.business_center_rounded,      'type': 'crown'},
    {'label': 'Branch Manager',   'icon': Icons.manage_accounts_rounded,      'type': 'crown'},
    {'label': 'Server',           'icon': Icons.shield_rounded,               'type': 'shield'},
    {'label': 'Doctor',           'icon': Icons.medical_services_outlined,    'type': 'normal'},
    {'label': 'Receptionist',     'icon': Icons.support_agent_rounded,        'type': 'normal'},
    {'label': 'Dispenser',        'icon': Icons.medication_outlined,          'type': 'normal'},
    {'label': 'Supervisor',       'icon': Icons.manage_accounts_outlined,     'type': 'normal'},
    {'label': 'Office Boy',       'icon': Icons.confirmation_number_outlined, 'type': 'normal'},
    {'label': 'Kitchen',          'icon': Icons.restaurant_outlined,          'type': 'normal'},
    // ── Madrassa Roles (Staff only) ──────────────────────────────────────────
    {'label': 'Madrassa Admin',   'icon': Icons.menu_book_rounded,            'type': 'madrassa'},
    {'label': 'Madrassa Teacher', 'icon': Icons.school_rounded,               'type': 'madrassa'},
  ];

  final List<String> _degrees = ['MBBS', 'MD', 'DO', 'BDS', 'Other'];
  List<Map<String, dynamic>> _branches = [];
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _loadBranches();
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final c in [
      _usernameController, _emailController, _passwordController,
      _phoneController, _identificationController, _addressController,
      _bankNameController, _bankAccountController, _customDegreeController,
      _salaryController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('branches').get();
      setState(() {
        _branches = snap.docs.map((d) {
          final data = d.data();
          return {'id': d.id, 'name': data['name'] as String? ?? d.id};
        }).toList()
          ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      });
    } catch (e) {
      _snack('Failed to load branches: $e', error: true);
    }
  }

  Future<void> _loadStudentsForBranch(String bId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(bId)
          .collection('madrassa_students')
          .where('isActive', isEqualTo: true)
          .get();
      setState(() {
        _branchStudents = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _branchStudents.sort((a, b) => (a['rollNumber'] ?? '').compareTo(b['rollNumber'] ?? ''));
      });
    } catch (e) {
      _snack('Failed to load students: $e', error: true);
    }
  }

  Future<bool> _usernameExists(String username) async {
    final lower = username.trim().toLowerCase();
    final snap = await FirebaseFirestore.instance.collection('branches').get();
    for (final doc in snap.docs) {
      final res = await FirebaseFirestore.instance
          .collection('branches')
          .doc(doc.id)
          .collection('users')
          .where('usernameLower', isEqualTo: lower)
          .limit(1)
          .get();
      if (res.docs.isNotEmpty) return true;
    }
    return false;
  }

  bool _requiresBranch() {
    final r = _selectedRole?.toLowerCase();
    // Global executive roles — no branch scoping needed.
    return r != 'ceo' && r != 'chairman' && r != 'admin' && r != 'hq manager';
  }

  String _getBranchId() {
    if (!_requiresBranch()) return 'global';
    if (_selectedBranch == null) throw Exception('Please select a branch for this role');
    final match = _branches.where((b) => b['name'] == _selectedBranch).toList();
    if (match.isEmpty) throw Exception('Selected branch not found — please re-select');
    return match.first['id'] as String;
  }

  String _getBranchName() =>
      _requiresBranch() ? (_selectedBranch ?? 'Unknown') : 'All Branches';

  Future<void> _pickProfileImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      try {
        final t = RoleThemeScope.dataOf(context);
        final cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          compressQuality: 80,
          uiSettings: [
            AndroidUiSettings(
                toolbarTitle: 'Crop Photo',
                toolbarColor: t.accent,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.square,
                lockAspectRatio: true),
            IOSUiSettings(title: 'Crop Photo', aspectRatioLockEnabled: true),
            WebUiSettings(
                context: context,
                presentStyle: WebPresentStyle.dialog,
                size: const CropperSize(width: 500, height: 500),
                initialAspectRatio: 1.0),
          ],
        );
        if (cropped != null) {
          final cb = await cropped.readAsBytes();
          setState(() {
            _profileImageXFile = XFile(cropped.path);
            _profileImageBytes = cb;
          });
        } else {
          setState(() {
            _profileImageXFile = picked;
            _profileImageBytes = bytes;
          });
        }
      } catch (_) {
        setState(() {
          _profileImageXFile = picked;
          _profileImageBytes = bytes;
        });
      }
    } catch (e) {
      _snack('Failed to pick image: $e', error: true);
    }
  }

  void _removeProfileImage() =>
      setState(() { _profileImageXFile = null; _profileImageBytes = null; });

  Future<void> _pickDocument(String type) async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        if (type == 'identification') _identificationFile = result.files.first;
        else if (type == 'degree')    _degreeFile          = result.files.first;
      });
    }
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) {
      _snack('Please fill all required fields', error: true);
      return;
    }
    if (_selectedRole == null) {
      _snack('Please select a role', error: true);
      return;
    }
    if (_requiresBranch() && _selectedBranch == null) {
      _snack('Please select a branch for this role', error: true);
      return;
    }
    if (_selectedRole == 'Madrassa Parent' && _selectedStudentId == null) {
      _snack('Please select a student for this parent', error: true);
      return;
    }

    setState(() { _usernameError = null; _loading = true; });

    final email    = _emailController.text.trim().toLowerCase();
    final username = _usernameController.text.trim(); // preserve original casing

    try {
      if (await _usernameExists(username)) {
        setState(() => _usernameError = 'Username already taken');
        _snack('Username already exists', error: true);
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
          _snack('Invalid salary format', error: true);
          return;
        }
      }

      final branchId = _getBranchId();

      final user = await _authService.signUp(
        email:              email,
        password:           _passwordController.text.trim(),
        username:           username,
        role:               _selectedRole!,
        branchId:           branchId,
        branchName:         _getBranchName(),
        phone:              _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        identification:     _identificationController.text.trim().isNotEmpty ? _identificationController.text.trim() : null,
        address:            _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        bankName:           _bankNameController.text.trim().isNotEmpty ? _bankNameController.text.trim() : null,
        bankAccount:        _bankAccountController.text.trim().isNotEmpty ? _bankAccountController.text.trim() : null,
        degree:             degree.isNotEmpty ? degree : null,
        salary:             salary,
        studentId:          _selectedStudentId, // Pass the student ID
        profileImageXFile:  _profileImageXFile,
        profileImageBytes:  _profileImageBytes,
        identificationFile: _identificationFile,
        degreeFile:         _degreeFile,
      );

      if (user == null) throw Exception(
        'Account could not be created. If this persists, check Firebase Console '
        'for a partial account under $email and delete it before retrying.',
      );

      final registeredName = _usernameController.text.trim();
      // Reset the form so the admin can register another user without leaving the page.
      _formKey.currentState!.reset();
      setState(() {
        _selectedRole         = null;
        _selectedBranch       = null;
        _selectedDegree       = null;
        _selectedStudentId    = null;
        _profileImageXFile    = null;
        _profileImageBytes    = null;
        _identificationFile   = null;
        _degreeFile           = null;
        _usernameError        = null;
      });
      for (final c in [
        _usernameController, _emailController, _passwordController,
        _phoneController, _identificationController, _addressController,
        _bankNameController, _bankAccountController,
        _customDegreeController, _salaryController,
      ]) { c.clear(); }
      _snack('$registeredName registered successfully!', success: true);
    } on Exception catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''), error: true);
    } catch (e) {
      _snack('Unexpected error: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false, bool success = false}) {
    if (!mounted) return;
    final t = RoleThemeScope.dataOf(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            error ? Icons.error_outline : success ? Icons.check_circle_outline : Icons.info_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: error ? t.danger : success ? t.accent : const Color(0xFF37474F),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final requiresBranch = _requiresBranch();
    final isDoctor = _selectedRole?.toLowerCase() == 'doctor';

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 210,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [t.accent.withValues(alpha: 0.9), t.accentLight],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Register New User',
                          style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAvatarCard(t),
                            const SizedBox(height: 16),

                            _buildCard(t,
                              title: 'Role & Assignment',
                              icon: Icons.badge_outlined,
                              accent: const Color(0xFF6A1B9A),
                              child: Column(children: [
                                _buildRoleDropdown(t),
                                if (_selectedRole != null && requiresBranch) ...[
                                  const SizedBox(height: 14),
                                  _buildSimpleDropdown(t,
                                    value: _selectedBranch,
                                    items: _branches.map((b) => b['name'] as String).toList(),
                                    hint: _branches.isEmpty ? 'Loading branches...' : 'Select Branch *',
                                    icon: Icons.location_city_rounded,
                                    onChanged: (v) {
                                      setState(() {
                                        _selectedBranch = v;
                                        _selectedStudentId = null;
                                        if (_selectedRole == 'Madrassa Parent') {
                                          final bId = _getBranchId();
                                          _loadStudentsForBranch(bId);
                                        }
                                      });
                                    },
                                    validator: (v) => v == null ? 'Required' : null,
                                  ),
                                ],
                                if (_selectedRole == 'Madrassa Parent' && _selectedBranch != null) ...[
                                  const SizedBox(height: 14),
                                  _buildSimpleDropdown(t,
                                    value: _selectedStudentId,
                                    items: _branchStudents.map((s) => s['id'] as String).toList(),
                                    hint: _branchStudents.isEmpty ? 'No students found' : 'Select Child (Student) *',
                                    icon: Icons.child_care_rounded,
                                    itemLabel: (id) {
                                      final s = _branchStudents.firstWhere((element) => element['id'] == id);
                                      return "${s['name']} (Roll: ${s['rollNumber']})";
                                    },
                                    onChanged: (v) => setState(() => _selectedStudentId = v),
                                    validator: (v) => v == null ? 'Required' : null,
                                  ),
                                ],
                                if (_selectedRole != null && !requiresBranch) ...[
                                  const SizedBox(height: 14),
                                  _buildGlobalBadge(t),
                                ],
                              ]),
                            ),
                            const SizedBox(height: 16),

                            _buildCard(t,
                              title: 'Basic Information',
                              icon: Icons.person_outline_rounded,
                              accent: t.accentLight,
                              child: Column(children: [
                                _buildRow([
                                  _buildField(t,
                                      controller: _usernameController,
                                      label: 'Username',
                                      icon: Icons.alternate_email_rounded,
                                      required: true,
                                      validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
                                  _buildField(t,
                                      controller: _emailController,
                                      label: 'Email',
                                      icon: Icons.mail_outline_rounded,
                                      required: true,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
                                ]),
                                const SizedBox(height: 14),
                                _buildRow([
                                  _buildField(t,
                                      controller: _passwordController,
                                      label: 'Password',
                                      icon: Icons.lock_outline_rounded,
                                      isPassword: true,
                                      required: true,
                                      validator: (v) => (v?.length ?? 0) < 6 ? 'Min 6 chars' : null),
                                  _buildField(t,
                                      controller: _phoneController,
                                      label: 'Phone',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(11),
                                      ]),
                                ]),
                              ]),
                            ),
                            const SizedBox(height: 16),

                            _buildCard(t,
                              title: 'Contact & Address',
                              icon: Icons.contact_mail_outlined,
                              accent: const Color(0xFFE65100),
                              child: Column(children: [
                                _buildField(t,
                                    controller: _identificationController,
                                    label: 'CNIC / ID Number',
                                    icon: Icons.credit_card_outlined),
                                const SizedBox(height: 14),
                                _buildField(t,
                                    controller: _addressController,
                                    label: 'Address',
                                    icon: Icons.home_outlined,
                                    maxLines: 3),
                              ]),
                            ),
                            const SizedBox(height: 16),

                            _buildCard(t,
                              title: 'Financial Details',
                              icon: Icons.account_balance_wallet_outlined,
                              accent: t.accent,
                              child: Column(children: [
                                _buildRow([
                                  _buildField(t,
                                      controller: _bankNameController,
                                      label: 'Bank Name',
                                      icon: Icons.account_balance_outlined),
                                  _buildField(t,
                                      controller: _bankAccountController,
                                      label: 'Account No.',
                                      icon: Icons.numbers_outlined,
                                      keyboardType: TextInputType.number),
                                ]),
                                const SizedBox(height: 14),
                                _buildField(t,
                                    controller: _salaryController,
                                    label: 'Base Salary (PKR)',
                                    icon: Icons.payments_outlined,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))]),
                              ]),
                            ),

                            if (isDoctor) ...[
                              const SizedBox(height: 16),
                              _buildCard(t,
                                title: 'Medical Qualifications',
                                icon: Icons.local_hospital_outlined,
                                accent: const Color(0xFF00695C),
                                child: Column(children: [
                                  _buildSimpleDropdown(t,
                                    value: _selectedDegree,
                                    items: _degrees,
                                    hint: 'Select Degree *',
                                    icon: Icons.school_outlined,
                                    onChanged: (v) => setState(() {
                                      _selectedDegree = v;
                                      if (v != 'Other') _customDegreeController.clear();
                                    }),
                                    validator: (v) => v == null ? 'Required' : null,
                                  ),
                                  if (_selectedDegree == 'Other') ...[
                                    const SizedBox(height: 14),
                                    _buildField(t,
                                        controller: _customDegreeController,
                                        label: 'Specify Degree',
                                        icon: Icons.edit_outlined,
                                        required: true,
                                        validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null),
                                  ],
                                ]),
                              ),
                            ],

                            const SizedBox(height: 16),

                            _buildCard(t,
                              title: 'Documents',
                              icon: Icons.folder_outlined,
                              accent: const Color(0xFF37474F),
                              child: Column(children: [
                                _buildFileCard(t,
                                  title: 'Identification Document',
                                  subtitle: 'CNIC, Passport, or Government ID',
                                  file: _identificationFile,
                                  onTap: () => _pickDocument('identification'),
                                  onRemove: () => setState(() => _identificationFile = null),
                                  icon: Icons.badge_outlined,
                                ),
                                if (isDoctor) ...[
                                  const SizedBox(height: 12),
                                  _buildFileCard(t,
                                    title: 'Degree Certificate',
                                    subtitle: 'Medical degree / diploma',
                                    file: _degreeFile,
                                    onTap: () => _pickDocument('degree'),
                                    onRemove: () => setState(() => _degreeFile = null),
                                    icon: Icons.school_outlined,
                                  ),
                                ],
                              ]),
                            ),

                            const SizedBox(height: 32),
                            _buildSubmitButton(t),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_loading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 36),
                  decoration: BoxDecoration(
                    color: t.bgCard,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, 10))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 52, height: 52,
                        child: CircularProgressIndicator(
                            color: t.accent, strokeWidth: 4, backgroundColor: t.accentMuted),
                      ),
                      const SizedBox(height: 20),
                      Text('Creating Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.textPrimary)),
                      const SizedBox(height: 6),
                      Text('Please wait...', style: TextStyle(fontSize: 13, color: t.textTertiary)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildAvatarCard(RoleThemeData t) {
    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.bgRule),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(children: [
        GestureDetector(
          onTap: _pickProfileImage,
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _profileImageBytes != null ? t.accent : t.bgRule, width: 3),
                boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.15), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: CircleAvatar(
                radius: 54,
                backgroundColor: t.accentMuted,
                backgroundImage: _profileImageBytes != null ? MemoryImage(_profileImageBytes!) : null,
                child: _profileImageBytes == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.person_outline_rounded, size: 38, color: t.accent.withValues(alpha: 0.4)),
                        const SizedBox(height: 4),
                        Text('Add Photo', style: TextStyle(fontSize: 11, color: t.textTertiary, fontWeight: FontWeight.w500)),
                      ])
                    : null,
              ),
            ),
            Positioned(
              right: 2, bottom: 2,
              child: GestureDetector(
                onTap: _profileImageBytes != null ? _removeProfileImage : _pickProfileImage,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _profileImageBytes != null ? t.danger : t.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.bgCard, width: 2.5),
                  ),
                  child: Icon(
                    _profileImageBytes != null ? Icons.close_rounded : Icons.camera_alt_rounded,
                    color: Colors.white, size: 14,
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text('Profile Picture', style: TextStyle(fontSize: 13, color: t.textTertiary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text('Optional', style: TextStyle(fontSize: 11, color: t.textTertiary)),
      ]),
    );
  }

  Widget _buildRoleDropdown(RoleThemeData t) {
    return DropdownButtonFormField<String>(
      value: _selectedRole,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.textTertiary),
      dropdownColor: t.bgCard,
      hint: Row(children: [
        Icon(Icons.badge_outlined, color: t.textTertiary, size: 20),
        const SizedBox(width: 10),
        Text('Select Role *', style: TextStyle(color: t.textTertiary, fontSize: 13)),
      ]),
      decoration: InputDecoration(
        filled: true,
        fillColor: t.bgCardAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.accent, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.danger, width: 2)),
        errorStyle: const TextStyle(fontSize: 11),
      ),
      selectedItemBuilder: (context) => _roleItems.map((role) {
        final type = role['type'] as String;
        final Color iconColor = type == 'crown'
            ? t.accent
            : type == 'shield'
                ? t.accentLight
                : type == 'madrassa'
                    ? const Color(0xFF5C6BC0)
                    : t.textSecondary;
        return Row(children: [
          Icon(role['icon'] as IconData, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Text(role['label'] as String,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.textPrimary)),
        ]);
      }).toList(),
      items: _roleItems.map((role) {
        final type = role['type'] as String;
        final isCrown    = type == 'crown';
        final isShield   = type == 'shield';
        final isMadrassa = type == 'madrassa';
        const madrassaColor = Color(0xFF5C6BC0); // indigo-ish
        final Color iconColor = isCrown
            ? t.accent
            : isShield
                ? t.accentLight
                : isMadrassa
                    ? madrassaColor
                    : t.textSecondary;
        final Color textColor = isCrown
            ? t.accent
            : isShield
                ? t.accentLight
                : isMadrassa
                    ? madrassaColor
                    : t.textPrimary;
        final Color bgColor = (isCrown || isShield)
            ? t.accentMuted
            : isMadrassa
                ? madrassaColor.withValues(alpha: 0.07)
                : t.bgCardAlt;

        return DropdownMenuItem<String>(
          value: role['label'] as String,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
                child: Icon(role['icon'] as IconData, color: iconColor, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(role['label'] as String,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: (isCrown || isShield || isMadrassa) ? FontWeight.w700 : FontWeight.w500,
                        color: textColor)),
              ),
              if (isCrown)    _roleBadge('Authority', t.accent),
              if (isShield)   _roleBadge('Server', t.accentLight),
              if (isMadrassa) _roleBadge('Madrassa', madrassaColor),
            ]),
          ),
        );
      }).toList(),
      onChanged: (val) => setState(() {
        _selectedRole = val;
        if (val != 'Doctor') {
          _selectedDegree = null;
          _customDegreeController.clear();
          _degreeFile = null;
        }
        if (!_requiresBranch()) _selectedBranch = null;
      }),
      validator: (val) => val == null ? 'Please select a role' : null,
    );
  }

  Widget _roleBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.9), fontWeight: FontWeight.w700)),
      );

  Widget _buildGlobalBadge(RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [t.accent.withValues(alpha: 0.10), t.accent.withValues(alpha: 0.04)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accent.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: t.accentMuted, borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.workspace_premium_rounded, color: t.accent, size: 22),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Global Access Granted', style: TextStyle(color: t.accent, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text('Full access to all branches', style: TextStyle(color: t.textSecondary, fontSize: 12)),
        ]),
      ]),
    );
  }

  Widget _buildCard(RoleThemeData t, {
    required String title,
    required IconData icon,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.bgRule),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.bgRule))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.textPrimary, letterSpacing: 0.1)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(18), child: child),
      ]),
    );
  }

  Widget _buildRow(List<Widget> children) {
    return Row(
      children: children
          .expand((w) => [Expanded(child: w), const SizedBox(width: 12)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _buildField(RoleThemeData t, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool isPassword = false,
    bool required   = false,
    int maxLines    = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: TextStyle(fontSize: 14, color: t.textPrimary, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: TextStyle(fontSize: 13, color: t.textTertiary),
        floatingLabelStyle: TextStyle(fontSize: 12, color: t.accent, fontWeight: FontWeight.w600),
        prefixIcon: Icon(icon, color: t.textTertiary, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: t.textTertiary, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword))
            : null,
        filled: true,
        fillColor: t.bgCardAlt,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines > 1 ? 14 : 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.accent, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.danger, width: 2)),
        errorStyle: const TextStyle(fontSize: 11),
      ),
      validator: validator,
    );
  }

  Widget _buildSimpleDropdown(RoleThemeData t, {
    required String? value,
    required List<String> items,
    required String hint,
    required IconData icon,
    required Function(String?) onChanged,
    String? Function(String?)? validator,
    String Function(String)? itemLabel,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(hint, style: TextStyle(color: t.textTertiary, fontSize: 13)),
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.textTertiary),
      dropdownColor: t.bgCard,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: t.textTertiary, size: 20),
        filled: true,
        fillColor: t.bgCardAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.accent, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.danger)),
        errorStyle: const TextStyle(fontSize: 11),
      ),
      items: items.map((e) => DropdownMenuItem(
          value: e,
          child: Text(e, style: TextStyle(fontSize: 14, color: t.textPrimary)))).toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }

  Widget _buildFileCard(RoleThemeData t, {
    required String title,
    required String subtitle,
    required PlatformFile? file,
    required VoidCallback onTap,
    required VoidCallback onRemove,
    required IconData icon,
  }) {
    final has = file != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: has ? t.accentMuted : t.bgCardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: has ? t.accent.withValues(alpha: 0.4) : t.bgRule, width: 1.5),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: has ? t.accent.withValues(alpha: 0.15) : t.bgRule.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(has ? Icons.check_rounded : icon, color: has ? t.accent : t.textTertiary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: has ? t.accent : t.textPrimary)),
              const SizedBox(height: 3),
              Text(has ? file.name : subtitle,
                  style: TextStyle(fontSize: 12, color: has ? t.accent.withValues(alpha: 0.7) : t.textTertiary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (has)
            GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: t.danger.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.close_rounded, color: t.danger, size: 18),
              ),
            )
          else
            Icon(Icons.upload_file_rounded, color: t.textTertiary, size: 22),
        ]),
      ),
    );
  }

  Widget _buildSubmitButton(RoleThemeData t) {
    return GestureDetector(
      onTap: _loading ? null : _registerUser,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [t.accent, t.accentLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: _loading
            ? const Center(child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 12),
                  Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ],
              ),
      ),
    );
  }
}
