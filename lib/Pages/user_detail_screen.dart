// lib/pages/user_detail_screen.dart — Role-Theme Aware

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';

class UserDetailScreen extends StatefulWidget {
  final String userId;
  final String branchId;
  final bool isOnline;
  final Box localBox;

  const UserDetailScreen({
    super.key,
    required this.userId,
    required this.branchId,
    this.isOnline = true,
    required this.localBox,
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _usernameController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _degreeController = TextEditingController();
  final TextEditingController _identificationController =
      TextEditingController();
  final TextEditingController _addressController =
      TextEditingController();
  final TextEditingController _bankNameController =
      TextEditingController();
  final TextEditingController _bankAccountController =
      TextEditingController();

  String? _selectedRole;
  XFile? _profileFile, _idFile, _degreeFile;
  String? branchName;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Fallback palette (used inside dialogs where theme context may vary)
  static const Color _dialogAccent = Color(0xFF3949AB);
  static const Color _divider = Color(0xFFE9ECEF);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _bg = Color(0xFFF5F6FA);
  static const Color _ink = Color(0xFF1C1F26);
  static const Color _inkMid = Color(0xFF5A6072);
  static const Color _inkLight = Color(0xFFADB5BD);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _fetchBranchName();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _degreeController.dispose();
    _identificationController.dispose();
    _addressController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    super.dispose();
  }

  Future<void> _fetchBranchName() async {
    try {
      final doc = await _firestore
          .collection('branches')
          .doc(widget.branchId)
          .get();
      if (doc.exists)
        setState(() =>
            branchName = doc.data()!['name'] as String? ?? widget.branchId);
    } catch (_) {}
  }

  Future<bool> _checkPassword(RoleThemeData t) async {
    final completer = Completer<bool>();
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: t.bgCard,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: t.accentMuted,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.lock_outline_rounded,
                      color: t.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Admin Verification',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary)),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: t.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Enter admin password',
                  hintStyle: TextStyle(color: t.textTertiary),
                  prefixIcon: Icon(Icons.password_rounded,
                      color: t.textTertiary, size: 20),
                  filled: true,
                  fillColor: t.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.bgRule)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.bgRule)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: t.accent, width: 2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      completer.complete(false);
                    },
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: t.bgRule)),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: t.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (ctrl.text == 'admin1122') {
                        Navigator.pop(ctx);
                        completer.complete(true);
                      } else {
                        _snack('Wrong password', error: true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Verify',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    return completer.future;
  }

  Stream<DocumentSnapshot> _userStream() => _firestore
      .collection('branches')
      .doc(widget.branchId)
      .collection('users')
      .doc(widget.userId)
      .snapshots();

  void _showEditDialog(Map<String, dynamic> data, RoleThemeData t) async {
    if (!await _checkPassword(t)) return;

    final editKey = GlobalKey<FormState>();
    final passCtrl = TextEditingController();

    _usernameController.text = data['username'] ?? '';
    _emailController.text = data['email'] ?? '';
    _phoneController.text = data['phone'] ?? '';
    _selectedRole = data['role'] ?? '';
    _degreeController.text = data['degree'] ?? '';
    _identificationController.text = data['identification'] ?? '';
    _addressController.text = data['address'] ?? '';
    _bankNameController.text = data['bankName'] ?? '';
    _bankAccountController.text = data['bankAccount'] ?? '';
    _profileFile = _idFile = _degreeFile = null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final isDoctor =
              _selectedRole?.toLowerCase() == 'doctor';
          return Dialog(
            backgroundColor: t.bg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(24, 20, 20, 20),
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.edit_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('Edit User',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800))),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 22),
                      padding: EdgeInsets.zero,
                    ),
                  ]),
                ),
                // Form
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: editKey,
                      child: Column(children: [
                        _editField(t, _usernameController,
                            'Username', Icons.alternate_email_rounded,
                            validator: (v) =>
                                v?.trim().isEmpty ?? true
                                    ? 'Required'
                                    : null),
                        _editField(t, _emailController, 'Email',
                            Icons.mail_outline_rounded,
                            type: TextInputType.emailAddress,
                            validator: (v) =>
                                v?.trim().isEmpty ?? true
                                    ? 'Required'
                                    : null),
                        _editField(t, _phoneController, 'Phone',
                            Icons.phone_outlined,
                            type: TextInputType.phone,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            maxLen: 11),
                        _editField(t, passCtrl,
                            'New Password (blank = 1122)',
                            Icons.lock_outline_rounded,
                            obscure: true),
                        _editField(
                            t,
                            _identificationController,
                            'Identification',
                            Icons.credit_card_outlined),
                        _editField(t, _addressController, 'Address',
                            Icons.home_outlined,
                            maxLines: 2),
                        _editField(t, _bankNameController,
                            'Bank Name',
                            Icons.account_balance_outlined),
                        _editField(
                            t,
                            _bankAccountController,
                            'Account Number',
                            Icons.numbers_outlined,
                            type: TextInputType.number),
                        const SizedBox(height: 4),
                        _editDropdown(
                          t: t,
                          value: _selectedRole,
                          label: 'Role',
                          icon: Icons.badge_outlined,
                          items: const [
                            'CEO', 'Admin', 'Chairman', 'Doctor',
                            'Receptionist', 'Dispenser', 'Supervisor',
                            'Server', 'Food Token Generator', 'Kitchen'
                          ],
                          onChanged: (v) =>
                              setS(() => _selectedRole = v),
                        ),
                        if (isDoctor) ...[
                          const SizedBox(height: 12),
                          _editField(t, _degreeController,
                              'Degree', Icons.school_outlined),
                        ],
                        const SizedBox(height: 16),
                        _uploadTile(t, 'Profile Picture',
                            _profileFile,
                            (f) => setS(() => _profileFile = f)),
                        _uploadTile(t, 'ID Document', _idFile,
                            (f) => setS(() => _idFile = f)),
                        if (isDoctor)
                          _uploadTile(t, 'Degree Certificate',
                              _degreeFile,
                              (f) => setS(() => _degreeFile = f)),
                      ]),
                    ),
                  ),
                ),
                // Actions
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: BoxDecoration(
                    color: t.bgCard,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(24)),
                    border: Border(
                        top: BorderSide(color: t.bgRule)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12),
                              side: BorderSide(color: t.bgRule)),
                        ),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: t.textSecondary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save_rounded,
                            size: 18),
                        label: const Text('Save Changes',
                            style: TextStyle(
                                fontWeight: FontWeight.w700)),
                        onPressed: () async => _saveUser(ctx,
                            editKey, data, passCtrl, isDoctor),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveUser(
      BuildContext ctx,
      GlobalKey<FormState> key,
      Map<String, dynamic> old,
      TextEditingController passCtrl,
      bool isDoctor) async {
    if (!key.currentState!.validate()) return;
    final updates = <String, dynamic>{
      'username': _usernameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : null,
      'identification':
          _identificationController.text.trim().isNotEmpty
              ? _identificationController.text.trim()
              : null,
      'address': _addressController.text.trim().isNotEmpty
          ? _addressController.text.trim()
          : null,
      'bankName': _bankNameController.text.trim().isNotEmpty
          ? _bankNameController.text.trim()
          : null,
      'bankAccount': _bankAccountController.text.trim().isNotEmpty
          ? _bankAccountController.text.trim()
          : null,
      'role': _selectedRole,
      'password': passCtrl.text.trim().isEmpty
          ? '1122'
          : passCtrl.text.trim(),
    };
    if (isDoctor) updates['degree'] = _degreeController.text.trim();

    Future<String> upload(XFile f, String name) async {
      final path =
          'branches/${widget.branchId}/users/${widget.userId}/$name.${f.name.split('.').last}';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(File(f.path));
      return ref.getDownloadURL();
    }

    if (_profileFile != null)
      updates['profilePictureUrl'] =
          await upload(_profileFile!, 'profile');
    if (_idFile != null)
      updates['identificationUrl'] =
          await upload(_idFile!, 'identification');
    if (isDoctor && _degreeFile != null)
      updates['degreeUrl'] = await upload(_degreeFile!, 'degree');

    try {
      await _firestore
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(widget.userId)
          .update(updates);
      _snack('User updated successfully!', success: true);
      if (mounted) Navigator.pop(ctx);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _deleteUser(RoleThemeData t) async {
    if (!await _checkPassword(t)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: t.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: t.danger.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.delete_forever_rounded,
                    color: t.danger, size: 32),
              ),
              const SizedBox(height: 16),
              Text('Delete User?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary)),
              const SizedBox(height: 8),
              Text('This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: t.textSecondary)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: t.bgRule)),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: t.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.danger,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Delete',
                        style:
                            TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _firestore
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(widget.userId)
          .delete();
      _snack('User deleted', success: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _snack(String msg,
      {bool error = false, bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            error
                ? Icons.error_outline
                : success
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
            color: Colors.white,
            size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(msg,
                style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: error
          ? const Color(0xFFB00020)
          : success
              ? const Color(0xFF2E7D32)
              : const Color(0xFF37474F),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _userStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _errorState(t);
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: t.accent));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _notFoundState(t);
          }

          final data =
              snapshot.data!.data() as Map<String, dynamic>;
          return FadeTransition(
            opacity: _fadeAnim,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverAppBar(data, t),
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 20),
                      _buildInfoSection(data, t),
                      const SizedBox(height: 16),
                      _buildContactSection(data, t),
                      const SizedBox(height: 16),
                      _buildFinancialSection(data, t),
                      if ((data['role'] as String?)
                              ?.toLowerCase() ==
                          'doctor') ...[
                        const SizedBox(height: 16),
                        _buildMedicalSection(data, t),
                      ],
                      if (data['identificationUrl'] != null ||
                          data['degreeUrl'] != null) ...[
                        const SizedBox(height: 16),
                        _buildDocumentsSection(data, t),
                      ],
                      const SizedBox(height: 16),
                      _buildMetaSection(data, t),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(
      Map<String, dynamic> data, RoleThemeData t) {
    final username = data['username'] ?? 'User';
    final role =
        (data['role'] as String? ?? '').toUpperCase();
    final photoUrl = data['profilePictureUrl'] as String?;
    final initials = username.trim().isEmpty
        ? '?'
        : username
            .trim()
            .split(' ')
            .map((w) => w[0])
            .take(2)
            .join()
            .toUpperCase();

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: t.accent,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.edit_rounded,
                size: 18, color: Colors.white),
          ),
          onPressed: () => _userStream().first.then((s) {
            if (s.exists)
              _showEditDialog(
                  s.data() as Map<String, dynamic>, t);
          }),
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.delete_outline_rounded,
                size: 18, color: Colors.white),
          ),
          onPressed: () => _deleteUser(t),
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                t.bg == const Color(0xFF080C14)
                    ? const Color(0xFF080C14)
                    : t.accent.withOpacity(0.9),
                t.accent,
                t.accentLight,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 56, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      image: photoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(photoUrl),
                              fit: BoxFit.cover)
                          : null,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                          width: 2.5),
                    ),
                    alignment: Alignment.center,
                    child: photoUrl == null
                        ? Text(initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800))
                        : null,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(username,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withOpacity(0.2),
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: Text(role,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 6),
                        Text(branchName ?? widget.branchId,
                            style: TextStyle(
                                color:
                                    Colors.white.withOpacity(0.7),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(
      Map<String, dynamic> data, RoleThemeData t) {
    return _card(t, 'Account Info', Icons.person_outline_rounded,
        t.accent, [
      _infoRow(t, 'User ID', widget.userId,
          Icons.fingerprint_rounded),
      _infoRow(
          t, 'Username', data['username'] ?? 'N/A', Icons.alternate_email_rounded),
      _infoRow(t, 'Email', data['email'] ?? 'N/A',
          Icons.mail_outline_rounded),
      _infoRow(
          t,
          'Role',
          (data['role'] as String? ?? 'N/A').toUpperCase(),
          Icons.badge_outlined),
    ]);
  }

  Widget _buildContactSection(
      Map<String, dynamic> data, RoleThemeData t) {
    return _card(t, 'Contact', Icons.contact_phone_outlined,
        const Color(0xFF00695C), [
      _infoRow(t, 'Phone', data['phone'] ?? 'N/A',
          Icons.phone_outlined),
      _infoRow(t, 'ID / CNIC',
          data['identification'] ?? 'N/A',
          Icons.credit_card_outlined),
      _infoRow(t, 'Address', data['address'] ?? 'N/A',
          Icons.home_outlined),
      _infoRow(t, 'Branch', branchName ?? widget.branchId,
          Icons.location_on_outlined),
    ]);
  }

  Widget _buildFinancialSection(
      Map<String, dynamic> data, RoleThemeData t) {
    return _card(t, 'Financial',
        Icons.account_balance_wallet_outlined,
        const Color(0xFF6A1B9A), [
      _infoRow(t, 'Bank', data['bankName'] ?? 'N/A',
          Icons.account_balance_outlined),
      _infoRow(t, 'Account No.',
          data['bankAccount'] ?? 'N/A', Icons.numbers_outlined),
      if (data['salary'] != null)
        _infoRow(t, 'Salary', 'PKR ${data['salary']}',
            Icons.payments_outlined),
    ]);
  }

  Widget _buildMedicalSection(
      Map<String, dynamic> data, RoleThemeData t) {
    return _card(t, 'Medical', Icons.local_hospital_outlined,
        const Color(0xFF00796B), [
      _infoRow(t, 'Degree', data['degree'] ?? 'N/A',
          Icons.school_outlined),
    ]);
  }

  Widget _buildDocumentsSection(
      Map<String, dynamic> data, RoleThemeData t) {
    return _card(t, 'Documents', Icons.folder_outlined,
        t.textTertiary, [
      if (data['identificationUrl'] != null)
        _docRow(t, 'Identification',
            data['identificationUrl'] as String),
      if (data['degreeUrl'] != null)
        _docRow(t, 'Degree Certificate',
            data['degreeUrl'] as String),
    ]);
  }

  Widget _buildMetaSection(
      Map<String, dynamic> data, RoleThemeData t) {
    final joined = data['createdAt'] is Timestamp
        ? DateFormat('dd MMM yyyy')
            .format((data['createdAt'] as Timestamp).toDate())
        : 'N/A';
    return _card(t, 'Account Details', Icons.info_outline_rounded,
        t.textTertiary, [
      _infoRow(t, 'Joined On', joined,
          Icons.calendar_today_outlined),
    ]);
  }

  Widget _card(RoleThemeData t, String title, IconData icon,
      Color accent, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.bgRule, width: 0.8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary)),
            ]),
          ),
          Divider(height: 1, color: t.bgRule),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(RoleThemeData t, String label, String value,
      IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: t.textTertiary),
          const SizedBox(width: 10),
          SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: t.textSecondary,
                      fontWeight: FontWeight.w500))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      color: t.textPrimary,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _docRow(RoleThemeData t, String label, String url) {
    final isPdf = url.toLowerCase().contains('.pdf');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: t.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          if (!isPdf)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(url,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                        height: 80,
                        color: t.bg,
                        alignment: Alignment.center,
                        child: Icon(Icons.broken_image_outlined,
                            color: t.textTertiary),
                      )),
            )
          else
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: t.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.bgRule)),
                child: Row(children: [
                  const Icon(Icons.picture_as_pdf_rounded,
                      color: Colors.red, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('View PDF',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: t.textPrimary))),
                  Icon(Icons.open_in_new_rounded,
                      color: t.textTertiary, size: 16),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // ── Edit form helpers ──

  Widget _editField(RoleThemeData t, TextEditingController ctrl,
      String label, IconData icon,
      {TextInputType? type,
      List<TextInputFormatter>? formatters,
      int? maxLen,
      int maxLines = 1,
      bool obscure = false,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: type,
        inputFormatters: formatters,
        maxLength: maxLen,
        maxLines: maxLines,
        style: TextStyle(fontSize: 14, color: t.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(fontSize: 13, color: t.textTertiary),
          floatingLabelStyle: TextStyle(
              fontSize: 12,
              color: t.accent,
              fontWeight: FontWeight.w600),
          prefixIcon:
              Icon(icon, color: t.textTertiary, size: 20),
          filled: true,
          fillColor: t.bgCard,
          counterText: '',
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.bgRule)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.bgRule)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: t.accent, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: t.danger, width: 1.5)),
          errorStyle: const TextStyle(fontSize: 11),
        ),
        validator: validator,
      ),
    );
  }

  Widget _editDropdown({
    required RoleThemeData t,
    required String? value,
    required String label,
    required IconData icon,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        hint: Text(label,
            style:
                TextStyle(color: t.textTertiary, fontSize: 13)),
        isExpanded: true,
        dropdownColor: t.bgCard,
        icon: Icon(Icons.keyboard_arrow_down_rounded,
            color: t.textTertiary),
        decoration: InputDecoration(
          prefixIcon:
              Icon(icon, color: t.textTertiary, size: 20),
          filled: true,
          fillColor: t.bgCard,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.bgRule)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.bgRule)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: t.accent, width: 2)),
        ),
        items: items
            .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e,
                    style: TextStyle(
                        fontSize: 14,
                        color: t.textPrimary))))
            .toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'Select $label' : null,
      ),
    );
  }

  Widget _uploadTile(RoleThemeData t, String label, XFile? file,
      Function(XFile?) onPicked) {
    final has = file != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () async {
          final picked = await ImagePicker()
              .pickImage(source: ImageSource.gallery);
          if (picked != null) onPicked(picked);
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: has
                ? const Color(0xFFE8F5E9)
                : t.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: has
                    ? Colors.green.shade400
                    : t.bgRule,
                width: 1.5),
          ),
          child: Row(children: [
            Icon(
                has
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
                color: has
                    ? Colors.green.shade700
                    : t.textTertiary,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: t.textPrimary)),
                    if (has)
                      Text(file.name,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ]),
            ),
            Text(has ? 'Change' : 'Upload',
                style: TextStyle(
                    fontSize: 12,
                    color: has
                        ? Colors.green.shade700
                        : t.accent,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _errorState(RoleThemeData t) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: t.danger.withOpacity(0.6)),
          const SizedBox(height: 12),
          Text('Error loading user',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary)),
        ]),
      );

  Widget _notFoundState(RoleThemeData t) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_off_outlined,
              size: 48, color: t.textTertiary),
          const SizedBox(height: 12),
          Text('User not found',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary)),
        ]),
      );
}