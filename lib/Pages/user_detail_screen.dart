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
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/local_storage_service.dart';
import '../services/finance_local_storage.dart';
import '../services/image_upload_service.dart';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/device_badge_widget.dart';
import '../utils/formatters.dart';

class UserDetailScreen extends StatefulWidget {
  final String userId;
  final String branchId;
  final bool isOnline;
  final Box localBox;
  final String? currentUserRole;

  const UserDetailScreen({
    super.key,
    required this.userId,
    required this.branchId,
    this.isOnline = true,
    required this.localBox,
    this.currentUserRole,
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _updateFirebaseAuthUser(String email, String password, {String? newEmail, String? newPassword}) async {
    try {
      final appName = 'TempAuthApp_${DateTime.now().millisecondsSinceEpoch}';
      final secondaryApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final creds = await secondaryAuth.signInWithEmailAndPassword(email: email, password: password);
      final user = creds.user;
      if (user != null) {
        if (newEmail != null && newEmail != email) {
          await user.verifyBeforeUpdateEmail(newEmail);
        }
        if (newPassword != null && newPassword != password) {
          await user.updatePassword(newPassword);
        }
      }
      await secondaryApp.delete();
    } catch (e) {
      debugPrint('[UserDetailScreen] Failed to update Firebase Auth user: $e');
    }
  }

  Future<void> _deleteFirebaseAuthUser(String email, String password) async {
    try {
      final appName = 'TempAuthApp_${DateTime.now().millisecondsSinceEpoch}';
      final secondaryApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final creds = await secondaryAuth.signInWithEmailAndPassword(email: email, password: password);
      final user = creds.user;
      if (user != null) {
        await user.delete();
      }
      await secondaryApp.delete();
    } catch (e) {
      debugPrint('[UserDetailScreen] Failed to delete Firebase Auth user: $e');
    }
  }

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
  String? _selectedStatus;
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
    if (widget.branchId.isEmpty || widget.branchId == 'all' || widget.branchId == 'global') {
      setState(() => branchName = 'All Branches');
      return;
    }
    try {
      final doc = await _firestore
          .collection('branches')
          .doc(widget.branchId)
          .get();
      if (doc.exists) {
        setState(() =>
            branchName = doc.data()!['name'] as String? ?? widget.branchId);
      }
    } catch (_) {}
  }

  Future<bool> _checkPassword(RoleThemeData t) async {
    final completer = Completer<bool>();
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        void onVerify() {
          if (ctrl.text == 'admin1122') {
            Navigator.pop(ctx);
            completer.complete(true);
          } else {
            _snack('Wrong password', error: true);
          }
        }

        return Dialog(
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
                        borderSide: BorderSide(color: t.accent, width: 2)),
                  ),
                  onSubmitted: (_) => onVerify(),
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
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
                      onPressed: onVerify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
        );
      },
    );
    return completer.future;
  }

  Stream<DocumentSnapshot> _userStream() {
    if (widget.userId.trim().isEmpty) {
      return const Stream.empty();
    }
    if (widget.branchId.isNotEmpty && widget.branchId != 'all' && widget.branchId != 'global') {
      return _firestore
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(widget.userId)
          .snapshots();
    }
    return _firestore
        .collection('users')
        .doc(widget.userId)
        .snapshots();
  }

  Map<String, dynamic>? _getLocalUser() {
    try {
      final box = Hive.box('local_users');
      for (final val in box.values) {
        if (val is Map) {
          final Map<String, dynamic> u = Map<String, dynamic>.from(val);
          final uid = u['uid']?.toString() ?? u['id']?.toString() ?? u['docId']?.toString() ?? '';
          final username = u['username']?.toString() ?? '';
          if (uid == widget.userId || (username.isNotEmpty && username.toLowerCase() == widget.userId.toLowerCase())) {
            return u;
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading local users: $e');
    }
    return null;
  }

  Future<DocumentSnapshot?> _fetchFallbackUser() async {
    if (widget.userId.trim().isEmpty) return null;
    try {
      // 1. Check top-level users collection
      final topDoc = await _firestore.collection('users').doc(widget.userId).get();
      if (topDoc.exists) return topDoc;

      // 2. Query collectionGroup users by uid field
      final queryByUid = await _firestore
          .collectionGroup('users')
          .where('uid', isEqualTo: widget.userId)
          .limit(1)
          .get();
      if (queryByUid.docs.isNotEmpty) return queryByUid.docs.first;
    } catch (e) {
      debugPrint('Fallback user fetch error: $e');
    }
    return null;
  }

  void _showEditDialog(Map<String, dynamic> data, RoleThemeData t) async {
    if (!await _checkPassword(t)) return;

    final editKey = GlobalKey<FormState>();
    final passCtrl = TextEditingController();

    _usernameController.text = data['username'] ?? '';
    _emailController.text = data['email'] ?? '';
    _phoneController.text = data['phone'] ?? '';
    
    // Roles configuration for dropdown and normalization
    List<Map<String, dynamic>> roleConfigs = [
      {'value': 'CEO', 'label': 'CEO', 'type': 'crown', 'icon': Icons.workspace_premium_rounded},
      {'value': 'Admin', 'label': 'Admin', 'type': 'crown', 'icon': Icons.workspace_premium_rounded},
      {'value': 'Chairman', 'label': 'Chairman', 'type': 'crown', 'icon': Icons.workspace_premium_rounded},
      {'value': 'HQ Manager', 'label': 'HQ Manager', 'type': 'crown', 'icon': Icons.business_center_rounded},
      {'value': 'Branch Manager', 'label': 'Branch Manager', 'type': 'normal', 'icon': Icons.manage_accounts_rounded},
      {'value': 'Doctor', 'label': 'Doctor', 'type': 'normal', 'icon': Icons.medical_services_outlined},
      {'value': 'Receptionist', 'label': 'Receptionist', 'type': 'normal', 'icon': Icons.support_agent_rounded},
      {'value': 'Dispenser', 'label': 'Dispenser', 'type': 'normal', 'icon': Icons.medication_outlined},
      {'value': 'rec+dis', 'label': 'Rec + Dispenser', 'type': 'hybrid', 'icon': Icons.swap_horiz_rounded},
      {'value': 'doc+rec', 'label': 'Doc + Receptionist', 'type': 'hybrid', 'icon': Icons.swap_horiz_rounded},
      {'value': 'doc+dis', 'label': 'Doc + Dispenser', 'type': 'hybrid', 'icon': Icons.swap_horiz_rounded},
      {'value': 'doc+rec+dis', 'label': 'Doc + Rec + Dispenser', 'type': 'hybrid', 'icon': Icons.swap_horiz_rounded},
      {'value': 'Supervisor', 'label': 'Supervisor', 'type': 'normal', 'icon': Icons.manage_accounts_outlined},
      {'value': 'Server', 'label': 'Server', 'type': 'shield', 'icon': Icons.shield_rounded},
      {'value': 'Office Boy', 'label': 'Office Boy', 'type': 'normal', 'icon': Icons.confirmation_number_outlined},
      {'value': 'Kitchen', 'label': 'Kitchen', 'type': 'normal', 'icon': Icons.restaurant_outlined},
      {'value': 'Food Token Generator', 'label': 'Food Token Generator', 'type': 'normal', 'icon': Icons.confirmation_number_outlined},
      {'value': 'Madrassa Admin', 'label': 'Madrassa Admin', 'type': 'madrassa', 'icon': Icons.menu_book_rounded},
      {'value': 'Madrassa Teacher', 'label': 'Madrassa Teacher', 'type': 'madrassa', 'icon': Icons.school_rounded},
      {'value': 'Madrassa Parent', 'label': 'Madrassa Parent', 'type': 'madrassa', 'icon': Icons.child_care_rounded},
    ];

    if (!_canManageUserAccess({'role': 'chairman'})) {
      roleConfigs.removeWhere((r) => r['value'].toString().toLowerCase().trim() == 'chairman');
    }

    final String rawRole = (data['role'] ?? '').toString();
    final matchingRole = roleConfigs.firstWhere(
      (r) => r['value'].toString().toLowerCase() == rawRole.toLowerCase() ||
             r['label'].toString().toLowerCase() == rawRole.toLowerCase(),
      orElse: () => roleConfigs.first,
    );
    _selectedRole = matchingRole['value'] as String;

    final List<String> statusList = ['Active', 'Inactive', 'Resigned', 'Terminated', 'Retired', 'Suspended'];
    final String rawStatus = (data['status'] ?? data['accountStatus'] ?? 'Active').toString();
    _selectedStatus = statusList.firstWhere(
      (s) => s.toLowerCase() == rawStatus.toLowerCase(),
      orElse: () => 'Active',
    );
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
          final isDoctor = _selectedRole != null &&
              (_selectedRole!.toLowerCase() == 'doctor' ||
                  _selectedRole!.toLowerCase().contains('doc'));
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
                        _editRoleDropdown(
                          t: t,
                          value: _selectedRole,
                          roles: roleConfigs,
                          onChanged: (v) =>
                              setS(() => _selectedRole = v),
                        ),
                        const SizedBox(height: 12),
                        _editDropdown(
                          t: t,
                          value: _selectedStatus,
                          label: 'Account Status / Access',
                          icon: Icons.no_accounts_rounded,
                          items: const [
                            'Active',
                            'Inactive',
                            'Resigned',
                            'Terminated',
                            'Retired',
                            'Suspended'
                          ],
                          onChanged: (v) => setS(() => _selectedStatus = v),
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

    final String targetRole = (old['role'] ?? '').toString().toLowerCase().trim();
    final String currentActorRole = (Hive.box('app_settings').get('user_role') ?? 'admin').toString().toLowerCase().trim();
    final String newStatus = (_selectedStatus ?? 'Active').toLowerCase();

    final bool isRevoking = newStatus == 'suspended' || newStatus == 'terminated' || newStatus == 'inactive';

    if (isRevoking) {
      if ((targetRole == 'principal' || targetRole == 'chairman' || targetRole == 'ceo') &&
          (currentActorRole == 'school admin' || currentActorRole == 'admin' || currentActorRole == 'branch manager')) {
        _snack('Permission Denied: School Admin cannot revoke Principal access!', error: true);
        return;
      }
    }
    final updates = <String, dynamic>{
      'username': _usernameController.text.trim(),                              // original casing
      'usernameLower': _usernameController.text.trim().toLowerCase(),            // for lookup
      'email': _emailController.text.trim().toLowerCase(),
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
      'status': _selectedStatus ?? 'Active',
      'accountStatus': _selectedStatus ?? 'Active',
      'isActive': (_selectedStatus ?? 'Active') == 'Active',
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

    if (_profileFile != null) {
      updates['profilePictureUrl'] =
          await upload(_profileFile!, 'profile');
    }
    if (_idFile != null) {
      updates['identificationUrl'] =
          await upload(_idFile!, 'identification');
    }
    if (isDoctor && _degreeFile != null) {
      updates['degreeUrl'] = await upload(_degreeFile!, 'degree');
    }

    try {
      final String oldEmail = old['email']?.toString() ?? '';
      final String oldPassword = old['password']?.toString() ?? '1122';
      final String newEmail = updates['email'] as String;
      final String newPassword = updates['password'] as String;
      final isLocal = widget.userId.startsWith('local-');
      if (!isLocal) {
        await _updateFirebaseAuthUser(oldEmail, oldPassword, newEmail: newEmail, newPassword: newPassword);
      }

      await LocalStorageService.saveUserOffline(
        uid: widget.userId,
        branchId: widget.branchId,
        userData: {
          ...old,
          ...updates,
          'uid': widget.userId,
          'branchId': widget.branchId,
        },
      );

      final cnicVal = ((updates['cnic'] ?? updates['identification']) ?? (old['cnic'] ?? old['identification']))?.toString() ?? '';
      if (cnicVal.isNotEmpty) {
        await FinanceLocalStorage.linkUserAndEmployeeByCnic(
          cnic: cnicVal,
          userId: widget.userId,
          userRole: (updates['role'] ?? old['role'])?.toString(),
          userName: (updates['username'] ?? old['username'])?.toString(),
        );
      }

      if (widget.isOnline && !isLocal) {
        await _firestore
            .collection('users')
            .doc(widget.userId)
            .update(updates);

        if (widget.branchId != 'all' && widget.branchId.isNotEmpty) {
          await _firestore
              .collection('branches')
              .doc(widget.branchId)
              .collection('users')
              .doc(widget.userId)
              .update(updates);
        }
      }
      _snack('User updated successfully!', success: true);
      if (mounted) Navigator.pop(ctx);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _deleteUser(Map<String, dynamic> data, RoleThemeData t) async {
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
                    color: t.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(Icons.delete_forever_rounded,
                    color: t.danger, size: 40),
              ),
              const SizedBox(height: 16),
              Text('Delete User?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: t.textPrimary,
                      letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text(
                  'Are you sure you want to delete this user profile? This action is permanent.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: t.textSecondary,
                      height: 1.4)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: t.textSecondary,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Delete',
                        style: TextStyle(fontWeight: FontWeight.w700)),
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
      final String email = data['email']?.toString() ?? '';
      final String password = data['password']?.toString() ?? '1122';
      final isLocal = widget.userId.startsWith('local-');
      if (email.isNotEmpty && !isLocal) {
        await _deleteFirebaseAuthUser(email, password);
      }

      await FinanceLocalStorage.syncBiDirectionalOffboarding(
        userId: widget.userId,
        cnic: (data['cnic'] ?? data['identification'])?.toString(),
        performedBy: 'UserAdmin',
      );

      await LocalStorageService.deleteUserOffline(
        uid: widget.userId,
        branchId: widget.branchId,
        email: email,
      );

      if (widget.isOnline && !isLocal) {
        await _firestore
            .collection('users')
            .doc(widget.userId)
            .delete();

        if (widget.branchId != 'all' && widget.branchId.isNotEmpty) {
          await _firestore
              .collection('branches')
              .doc(widget.branchId)
              .collection('users')
              .doc(widget.userId)
              .delete();
        }
      }
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
          Map<String, dynamic>? userData;
          bool hasUserData = false;

          final localUser = _getLocalUser();
          if (snapshot.hasData && snapshot.data!.exists) {
            userData = snapshot.data!.data() as Map<String, dynamic>?;
            hasUserData = true;
          } else if (localUser != null) {
            userData = localUser;
            hasUserData = true;
          }

          if (snapshot.hasError && !hasUserData) return _errorState(t);
          if (snapshot.connectionState == ConnectionState.waiting && !hasUserData) {
            return Center(
                child: CircularProgressIndicator(color: t.accent));
          }
          if (!hasUserData && snapshot.connectionState != ConnectionState.waiting) {
            return FutureBuilder<DocumentSnapshot?>(
              future: _fetchFallbackUser(),
              builder: (context, fbSnap) {
                if (fbSnap.hasData && fbSnap.data != null && fbSnap.data!.exists) {
                  final fbData = fbSnap.data!.data() as Map<String, dynamic>?;
                  if (fbData != null) {
                    return FadeTransition(
                      opacity: _fadeAnim,
                      child: CustomScrollView(
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          _buildSliverAppBar(fbData, t),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                const SizedBox(height: 20),
                                _buildInfoSection(fbData, t),
                                const SizedBox(height: 16),
                                _buildContactSection(fbData, t),
                                const SizedBox(height: 16),
                                _buildFinancialSection(fbData, t),
                                const SizedBox(height: 16),
                                _buildDocumentsSection(fbData, t),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                }
                if (fbSnap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: t.accent));
                }
                return _notFoundState(t);
              },
            );
          }

          final data = userData!;
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
                      if ((data['role'] as String?) != null &&
                          ((data['role'] as String).toLowerCase() == 'doctor' ||
                              (data['role'] as String).toLowerCase().contains('doc'))) ...[
                        const SizedBox(height: 16),
                        _buildMedicalSection(data, t),
                      ],
                      if (data['identificationUrl'] != null ||
                          data['degreeUrl'] != null) ...[
                        const SizedBox(height: 16),
                        _buildDocumentsSection(data, t),
                      ],
                      const SizedBox(height: 16),
                      _buildActiveDeviceSection(data, t),
                      const SizedBox(height: 16),
                      _buildMetaSection(data, t),
                      const SizedBox(height: 16),
                      _buildRevokeAccessCard(data, t),
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
    final username = resolveUserDisplayName(data);
    final rawRole = data['role'] as String? ?? '';
    final role = rawRole.toLowerCase() == 'madrassa parent' ? 'GUARDIAN' : rawRole.toUpperCase();
    final isGuardian = rawRole.toLowerCase() == 'madrassa parent' || rawRole.toLowerCase() == 'madrassa guardian';
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
        if (_canManageUserAccess(data)) ...[
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.edit_rounded,
                  size: 18, color: Colors.white),
            ),
            tooltip: 'Edit User',
            onPressed: () => _showEditDialog(data, t),
          ),
          if (!isGuardian)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.no_accounts_rounded,
                    size: 18, color: Colors.white),
              ),
              tooltip: 'Revoke Access',
              onPressed: () => _showRevokeAccessDialog(data, t),
            ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: Colors.white),
            ),
            tooltip: 'Delete User',
            onPressed: () => _deleteUser(data, t),
          ),
          const SizedBox(width: 8),
        ],
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
                    : t.accent.withValues(alpha: 0.9),
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
                      color: Colors.white.withValues(alpha: 0.2),
                      image: (photoUrl != null && photoUrl.isNotEmpty)
                          ? DecorationImage(
                              image: (photoUrl.startsWith('http://') || photoUrl.startsWith('https://'))
                                  ? NetworkImage(photoUrl) as ImageProvider
                                  : MemoryImage(ImageUploadService.decodeBase64ToBytes(photoUrl) ?? Uint8List(0)),
                              fit: BoxFit.cover)
                          : null,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2.5),
                    ),
                    alignment: Alignment.center,
                    child: (photoUrl == null || photoUrl.isEmpty)
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(role,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: ((data['status'] ?? data['accountStatus'] ?? 'Active').toString().toLowerCase() == 'active')
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                (data['status'] ?? data['accountStatus'] ?? 'ACTIVE').toString().toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(branchName ?? widget.branchId,
                            style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.7),
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
          (data['role'] as String? ?? 'N/A').toLowerCase() == 'madrassa parent'
              ? 'GUARDIAN'
              : (data['role'] as String? ?? 'N/A').toUpperCase(),
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

  Widget _buildActiveDeviceSection(Map<String, dynamic> data, RoleThemeData t) {
    Map<String, dynamic>? deviceInfo = (data['lastDeviceInfo'] != null && data['lastDeviceInfo'] is Map)
        ? Map<String, dynamic>.from(data['lastDeviceInfo'] as Map)
        : ((data['deviceInfo'] != null && data['deviceInfo'] is Map)
            ? Map<String, dynamic>.from(data['deviceInfo'] as Map)
            : null);

    if (deviceInfo == null && widget.userId.isNotEmpty) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.userId).snapshots(),
        builder: (context, snapshot) {
          Map<String, dynamic>? fetchedInfo;
          if (snapshot.hasData && snapshot.data!.exists) {
            final docData = snapshot.data!.data() as Map<String, dynamic>?;
            if (docData != null && docData['lastDeviceInfo'] is Map) {
              fetchedInfo = Map<String, dynamic>.from(docData['lastDeviceInfo'] as Map);
            }
          }

          if (fetchedInfo == null) {
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('user_sessions').doc(widget.userId).snapshots(),
              builder: (context, sessionSnap) {
                if (sessionSnap.hasData && sessionSnap.data!.exists) {
                  final sData = sessionSnap.data!.data() as Map<String, dynamic>?;
                  if (sData != null) fetchedInfo = sData;
                }
                return _renderDeviceCard(fetchedInfo, t, userDoc: data);
              },
            );
          }
          return _renderDeviceCard(fetchedInfo, t, userDoc: data);
        },
      );
    }

    return _renderDeviceCard(deviceInfo, t, userDoc: data);
  }

  Widget _renderDeviceCard(Map<String, dynamic>? deviceInfo, RoleThemeData t, {Map<String, dynamic>? userDoc}) {
    final platform = deviceInfo?['platform']?.toString() ?? 'N/A';
    final browser = deviceInfo?['browser']?.toString() ?? 'N/A';
    final os = deviceInfo?['os']?.toString() ?? 'N/A';
    final deviceName = deviceInfo?['deviceName']?.toString() ?? deviceInfo?['deviceModel']?.toString() ?? 'N/A';
    final deviceModel = deviceInfo?['deviceModel']?.toString() ?? 'N/A';
    final appVersion = deviceInfo?['appVersion']?.toString() ?? '1.2.5';
    final isOnline = deviceInfo?['isOnline'] as bool? ?? widget.isOnline;

    final Map<String, dynamic>? devicesMap = (userDoc != null && userDoc['devices'] is Map)
        ? Map<String, dynamic>.from(userDoc['devices'] as Map)
        : null;

    return _card(
      t,
      'Active Device & Session History',
      Icons.devices_rounded,
      Colors.blue.shade700,
      [
        if (deviceInfo != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text('Active Badge:', style: TextStyle(fontSize: 13, color: t.textSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                DeviceBadgeWidget(deviceInfo: deviceInfo),
              ],
            ),
          ),
          _infoRow(t, 'App Version', 'v$appVersion', Icons.verified_rounded),
          _infoRow(t, 'Platform', platform, Icons.computer_rounded),
          _infoRow(t, 'Browser / App', browser, Icons.language_rounded),
          _infoRow(t, 'Operating System', os, Icons.phonelink_setup_rounded),
          _infoRow(t, 'Device / PC Name', deviceName, Icons.badge_outlined),
          if (deviceModel != deviceName && deviceModel.isNotEmpty && deviceModel != 'N/A')
            _infoRow(t, 'Hardware Model', deviceModel, Icons.memory_rounded),
          _infoRow(t, 'Status', isOnline ? 'ONLINE NOW' : 'Offline', isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded),
          if (devicesMap != null && devicesMap.length > 1) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
            Text('All Transitioned Devices (${devicesMap.length}):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: devicesMap.values.map((dev) {
                if (dev is Map) {
                  return DeviceBadgeWidget(deviceInfo: Map<String, dynamic>.from(dev));
                }
                return const SizedBox.shrink();
              }).toList(),
            ),
          ],
        ] else ...[
          Text(
            'No active device session recorded yet. Session info will automatically record once the user opens or logs into the app.',
            style: TextStyle(fontSize: 12, color: t.textSecondary, fontStyle: FontStyle.italic),
          ),
        ]
      ],
    );
  }

  Widget _buildMetaSection(
      Map<String, dynamic> data, RoleThemeData t) {
    final joined = data['createdAt'] is Timestamp
        ? DateFormat('dd MMM yyyy')
            .format((data['createdAt'] as Timestamp).toDate())
        : 'N/A';

    final lastLoginRaw = data['lastLoginAt'] ?? data['lastOnlineAt'] ?? data['updatedAt'];
    String lastLoginText = 'Never / Not Available';
    if (lastLoginRaw is Timestamp) {
      lastLoginText = DateFormat('dd MMM yyyy, hh:mm a').format(lastLoginRaw.toDate());
    } else if (lastLoginRaw is String && lastLoginRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(lastLoginRaw);
      if (parsed != null) {
        lastLoginText = DateFormat('dd MMM yyyy, hh:mm a').format(parsed);
      } else {
        lastLoginText = lastLoginRaw;
      }
    }

    return _card(t, 'Account Details', Icons.info_outline_rounded,
        t.textTertiary, [
      _infoRow(t, 'Joined On', joined,
          Icons.calendar_today_outlined),
      const SizedBox(height: 10),
      _infoRow(t, 'Last Sign-In / Online', lastLoginText,
          Icons.access_time_rounded),
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
              color: Colors.black.withValues(alpha: 0.05),
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
                    color: accent.withValues(alpha: 0.10),
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
              child: (url.startsWith('http://') || url.startsWith('https://'))
                  ? Image.network(
                      url,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 80,
                        color: t.bg,
                        alignment: Alignment.center,
                        child: Icon(Icons.broken_image_outlined, color: t.textTertiary),
                      ),
                    )
                  : (ImageUploadService.decodeBase64ToBytes(url) != null
                      ? Image.memory(
                          ImageUploadService.decodeBase64ToBytes(url)!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 80,
                            color: t.bg,
                            alignment: Alignment.center,
                            child: Icon(Icons.broken_image_outlined, color: t.textTertiary),
                          ),
                        )
                      : Container(
                          height: 80,
                          color: t.bg,
                          alignment: Alignment.center,
                          child: Icon(Icons.insert_drive_file_outlined, color: t.textTertiary),
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
        initialValue: value,
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

  Widget _editRoleDropdown({
    required RoleThemeData t,
    required String? value,
    required List<Map<String, dynamic>> roles,
    required Function(String?) onChanged,
  }) {
    Widget roleBadge(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20)),
          child: Text(text,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700)),
        );

    final bool hasValidValue = roles.any((r) => r['value'].toString().toLowerCase() == value?.toLowerCase());
    final String? currentValue = hasValidValue
        ? roles.firstWhere((r) => r['value'].toString().toLowerCase() == value?.toLowerCase())['value'] as String
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: currentValue,
        hint: Row(
          children: [
            Icon(Icons.badge_outlined, color: t.textTertiary, size: 20),
            const SizedBox(width: 10),
            Text('Select Role *',
                style: TextStyle(color: t.textTertiary, fontSize: 13)),
          ],
        ),
        isExpanded: true,
        dropdownColor: t.bgCard,
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.textTertiary),
        decoration: InputDecoration(
          filled: true,
          fillColor: t.bgCard,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.bgRule)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.bgRule)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.accent, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.danger, width: 1.5)),
          errorStyle: const TextStyle(fontSize: 11),
        ),
        selectedItemBuilder: (context) => roles.map((role) {
          final type = role['type'] as String;
          final Color iconColor = type == 'crown'
              ? t.accent
              : type == 'shield'
                  ? t.accentLight
                  : type == 'madrassa'
                      ? const Color(0xFF5C6BC0)
                      : type == 'hybrid'
                          ? const Color(0xFF00796B)
                          : t.textSecondary;
          return Row(
            children: [
              Icon(role['icon'] as IconData, color: iconColor, size: 18),
              const SizedBox(width: 10),
              Text(role['label'] as String,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary)),
            ],
          );
        }).toList(),
        items: roles.map((role) {
          final type = role['type'] as String;
          final isCrown = type == 'crown';
          final isShield = type == 'shield';
          final isMadrassa = type == 'madrassa';
          final isHybrid = type == 'hybrid';
          const madrassaColor = Color(0xFF5C6BC0);
          const hybridColor = Color(0xFF00796B);
          
          final Color iconColor = isCrown
              ? t.accent
              : isShield
                  ? t.accentLight
                  : isMadrassa
                      ? madrassaColor
                      : isHybrid
                          ? hybridColor
                          : t.textSecondary;
          final Color textColor = isCrown
              ? t.accent
              : isShield
                  ? t.accentLight
                  : isMadrassa
                      ? madrassaColor
                      : isHybrid
                          ? hybridColor
                          : t.textPrimary;
          final Color bgColor = (isCrown || isShield)
              ? t.accentMuted
              : isMadrassa
                  ? madrassaColor.withValues(alpha: 0.07)
                  : isHybrid
                      ? hybridColor.withValues(alpha: 0.07)
                      : t.bgCard;

          return DropdownMenuItem<String>(
            value: role['value'] as String,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                  color: bgColor, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(role['icon'] as IconData,
                        color: iconColor, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(role['label'] as String,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: (isCrown ||
                                    isShield ||
                                    isMadrassa ||
                                    isHybrid)
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: textColor)),
                  ),
                  if (isCrown) roleBadge('Authority', t.accent),
                  if (isShield) roleBadge('Server', t.accentLight),
                  if (isMadrassa) roleBadge('Madrassa', madrassaColor),
                  if (isHybrid) roleBadge('Hybrid', hybridColor),
                ],
              ),
            ),
          );
        }).toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'Role is mandatory' : null,
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
          final source = await ImageUploadService.showSourceDialog(context, title: 'Select Image / File Source');
          if (source == null) return;
          final b64 = await ImageUploadService.pickAndProcessImage(source: source);
          if (b64 != null && b64.isNotEmpty) {
            onPicked(XFile(b64));
          }
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

  Future<void> _showGuardianStatusDialog(Map<String, dynamic> data, RoleThemeData t) async {
    final currentStatus = (data['status'] ?? data['studentStatus'] ?? 'active').toString().toLowerCase().trim();

    String selectedStatus = currentStatus;
    final reasonCtrl = TextEditingController();

    final statusOptions = [
      {'key': 'active', 'label': 'Active Student / Guardian', 'color': Colors.green, 'icon': Icons.check_circle_rounded},
      {'key': 'hifz_completed', 'label': 'Hifz Completed', 'color': const Color(0xFF4C4DDC), 'icon': Icons.workspace_premium_rounded},
      {'key': 'left', 'label': 'Left Madrassa', 'color': Colors.redAccent, 'icon': Icons.exit_to_app_rounded},
      {'key': 'dropped', 'label': 'Dropped Out', 'color': Colors.red, 'icon': Icons.person_off_rounded},
      {'key': 'archived', 'label': 'Archived', 'color': Colors.orange, 'icon': Icons.archive_rounded},
    ];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final currentOpt = statusOptions.firstWhere((o) => o['key'] == selectedStatus, orElse: () => statusOptions[0]);
          return Dialog(
            backgroundColor: t.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (currentOpt['color'] as Color).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(currentOpt['icon'] as IconData, color: currentOpt['color'] as Color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Madrassa Guardian Status',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: t.textPrimary),
                            ),
                            Text(
                              'Update enrolment status for @${data['username'] ?? 'Guardian'}',
                              style: TextStyle(fontSize: 12, color: t.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Select Student / Guardian Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary)),
                  const SizedBox(height: 8),
                  ...statusOptions.map((opt) {
                    final isSelected = selectedStatus == opt['key'];
                    final optColor = opt['color'] as Color;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? optColor.withValues(alpha: 0.1) : t.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? optColor : t.bgRule,
                          width: isSelected ? 1.5 : 0.8,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: Icon(opt['icon'] as IconData, color: optColor, size: 20),
                        title: Text(
                          opt['label'] as String,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? optColor : t.textPrimary,
                            fontSize: 13.5,
                          ),
                        ),
                        trailing: isSelected ? Icon(Icons.check_circle_rounded, color: optColor, size: 18) : null,
                        onTap: () => setS(() => selectedStatus = opt['key'] as String),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text('Remarks / Reason (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    style: TextStyle(fontSize: 13, color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. Completed Hifz exam / Relocated to another city',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: t.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bgRule)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentOpt['color'] as Color,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Update Status', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirm != true) return;

    final reason = reasonCtrl.text.trim();
    final isReadOnly = selectedStatus != 'active';

    final updates = <String, dynamic>{
      'status': selectedStatus,
      'studentStatus': selectedStatus,
      'accountStatus': selectedStatus,
      'isReadOnly': isReadOnly,
      'statusReason': reason.isNotEmpty ? reason : 'Status updated to $selectedStatus',
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await LocalStorageService.saveUserOffline(
        uid: widget.userId,
        branchId: widget.branchId,
        userData: {...data, ...updates, 'uid': widget.userId, 'branchId': widget.branchId},
      );

      if (widget.isOnline && !widget.userId.startsWith('local-')) {
        await FirebaseFirestore.instance.collection('users').doc(widget.userId).set(updates, SetOptions(merge: true));
        if (widget.branchId.isNotEmpty && widget.branchId != 'all') {
          await FirebaseFirestore.instance.collection('branches').doc(widget.branchId).collection('users').doc(widget.userId).set(updates, SetOptions(merge: true));
        }
      }

      if (mounted) {
        setState(() {});
        _snack('Guardian status updated to ${selectedStatus.replaceAll('_', ' ').toUpperCase()}', success: true);
      }
    } catch (e) {
      if (mounted) {
        _snack('Failed to update status: $e', error: true);
      }
    }
  }

  Widget _buildRevokeAccessCard(Map<String, dynamic> data, RoleThemeData t) {
    final rawRole = (data['role'] as String? ?? '').toLowerCase();
    final isGuardian = rawRole == 'madrassa parent' || rawRole == 'madrassa guardian';
    final canManageAccess = _canManageUserAccess(data);

    if (!canManageAccess) {
      return const SizedBox.shrink();
    }

    if (isGuardian) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.bgRule, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.family_restroom_rounded, color: Colors.teal, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Madrassa Family / Guardian Portal',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: t.textPrimary,
                        ),
                      ),
                      Text(
                        'Guardian accounts are linked to student profiles. Historical records remain read-only when students leave, complete Hifz, or archive.',
                        style: TextStyle(fontSize: 12, color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showGuardianStatusDialog(data, t),
                icon: const Icon(Icons.school_rounded, size: 18),
                label: const Text(
                  'Update Student / Guardian Status',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final status = (data['status'] ?? data['accountStatus'] ?? 'active').toString().toLowerCase().trim();
    final isRevoked = status == 'inactive' ||
        status == 'suspended' ||
        status == 'terminated' ||
        status == 'resigned' ||
        status == 'retired' ||
        status == 'offboarded' ||
        status == 'revoked' ||
        data['isActive'] == false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isRevoked
            ? Colors.red.withValues(alpha: 0.08)
            : t.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRevoked ? Colors.red.withValues(alpha: 0.3) : t.bgRule,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isRevoked ? Colors.red.withValues(alpha: 0.15) : t.accentMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isRevoked ? Icons.no_accounts_rounded : Icons.shield_outlined,
                  color: isRevoked ? Colors.red : t.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Access Control & Offboarding',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      isRevoked
                          ? 'Account access is currently revoked (${data['status'] ?? 'Revoked'}).'
                          : 'Revoke user access to immediately block app login.',
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (data['revocationReason'] != null && data['revocationReason'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Text(
                'Reason: ${data['revocationReason']}',
                style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showRevokeAccessDialog(data, t),
              icon: Icon(isRevoked ? Icons.key_rounded : Icons.lock_person_rounded, size: 18),
              label: Text(
                isRevoked ? 'Update Access / Status' : 'Revoke User Access',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRevoked ? const Color(0xFF334155) : Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canManageUserAccess(Map<String, dynamic> targetData) {
    String actorRole = '';

    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final currentMap = box.get('user_data') ?? box.get('currentUser') ?? box.get('active_user');
        if (currentMap is Map && currentMap['role'] != null) {
          actorRole = (currentMap['role'] as String).toLowerCase().trim();
        }
      }
    } catch (_) {}

    if (actorRole.isEmpty) {
      try {
        final currentMap = widget.localBox.get('user_data') ?? widget.localBox.get('currentUser') ?? widget.localBox.get('active_user');
        if (currentMap is Map && currentMap['role'] != null) {
          actorRole = (currentMap['role'] as String).toLowerCase().trim();
        }
      } catch (_) {}
    }

    if (actorRole.isEmpty) {
      final currentUser = FirebaseAuth.instance.currentUser;
      final actorUid = currentUser?.uid ?? '';
      if (actorUid.isNotEmpty && Hive.isBoxOpen(LocalStorageService.usersBox)) {
        final curMap = Hive.box(LocalStorageService.usersBox).get(actorUid);
        if (curMap is Map && curMap['role'] != null) {
          actorRole = (curMap['role'] as String).toLowerCase().trim();
        }
      }
    }

    if (actorRole.isEmpty) {
      actorRole = (widget.currentUserRole ?? '').toLowerCase().trim();
    }

    if (actorRole.isEmpty && mounted) {
      try {
        final scope = context.dependOnInheritedWidgetOfExactType<RoleThemeScope>();
        if (scope != null) {
          actorRole = scope.role.name.toLowerCase().trim();
        }
      } catch (_) {}
    }

    // GOD MODE: Chairman role can edit, delete, or revoke ANY role at all (including CEO, HQ Manager, Admins, global roles, server, self)
    if (actorRole == 'chairman') {
      return true;
    }

    final actorUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final targetUid = (targetData['uid'] ?? targetData['id'] ?? targetData['docId'] ?? '').toString();
    if (actorUid.isNotEmpty && targetUid.isNotEmpty && actorUid == targetUid) {
      return false;
    }

    final targetRole = (targetData['role'] as String? ?? '').toLowerCase().trim();

    // Rule 2: Server accounts protection for non-chairman
    if (targetRole == 'server' || targetRole.contains('server')) {
      return false;
    }

    // Rule 3: Non-chairman roles CANNOT manage Administration / Executive employees (HQ Manager, CEO, Admin, Chairman)
    final isTargetExecOrAdmin = targetRole == 'ceo' ||
        targetRole == 'hq manager' ||
        targetRole == 'hq_manager' ||
        targetRole == 'admin' ||
        targetRole == 'chairman' ||
        targetRole == 'global user' ||
        targetRole == 'administration';

    if (isTargetExecOrAdmin) {
      return false;
    }

    return true;
  }

  Future<void> _showRevokeAccessDialog(Map<String, dynamic> data, RoleThemeData t) async {
    if (!_canManageUserAccess(data)) {
      _snack('Access Denied: You do not have permission to revoke or alter access for ${(data['role'] as String? ?? 'User').toUpperCase()} accounts.', error: true);
      return;
    }

    final status = (data['status'] ?? data['accountStatus'] ?? 'active').toString().toLowerCase().trim();
    final isRevoked = status == 'inactive' ||
        status == 'suspended' ||
        status == 'terminated' ||
        status == 'resigned' ||
        status == 'retired' ||
        status == 'offboarded' ||
        status == 'revoked' ||
        data['isActive'] == false;

    String selectedCategory = isRevoked ? 'Active' : 'Resigned';
    final reasonCtrl = TextEditingController();
    final categories = ['Resigned', 'Terminated', 'Retired', 'Suspended', 'Offboarded', 'Inactive'];

    final confirmCategory = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Dialog(
            backgroundColor: t.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isRevoked ? Colors.green : Colors.red).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isRevoked ? Icons.lock_open_rounded : Icons.no_accounts_rounded,
                          color: isRevoked ? Colors.green : Colors.red,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isRevoked ? 'Re-Enable App Access' : 'Revoke App Access',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: t.textPrimary,
                              ),
                            ),
                            Text(
                              isRevoked
                                  ? 'Restore access for @${data['username'] ?? 'User'}'
                                  : 'Offboard employee & block app access',
                              style: TextStyle(fontSize: 12, color: t.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!isRevoked) ...[
                    Text(
                      'Select Revocation Category',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCategory,
                          isExpanded: true,
                          dropdownColor: t.bgCard,
                          style: TextStyle(fontSize: 14, color: t.textPrimary, fontWeight: FontWeight.w600),
                          items: categories.map((cat) {
                            return DropdownMenuItem(
                              value: cat,
                              child: Text(cat),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setS(() => selectedCategory = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    isRevoked ? 'Restoration Remarks (Optional)' : 'Reason / Remarks (Optional)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    style: TextStyle(fontSize: 13, color: t.textPrimary),
                    decoration: InputDecoration(
                      hintText: isRevoked ? 'e.g. Access restored by HQ Manager' : 'e.g. Resigned voluntarily / End of contract',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: t.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: t.bgRule),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: t.bgRule),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: t.bgRule),
                            ),
                          ),
                          child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: Icon(isRevoked ? Icons.lock_open_rounded : Icons.lock_person_rounded, size: 18),
                          label: Text(isRevoked ? 'Restore' : 'Proceed'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRevoked ? Colors.green : Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmCategory != true) return;

    if (!await _checkPassword(t)) return;

    final String reason = reasonCtrl.text.trim();
    final isLocal = widget.userId.startsWith('local-');

    final Map<String, dynamic> updates;

    if (isRevoked) {
      updates = <String, dynamic>{
        'status': 'active',
        'accountStatus': 'active',
        'isActive': true,
        'revocationReason': null,
        'revokedAt': null,
        'restoredAt': FieldValue.serverTimestamp(),
      };
    } else {
      updates = <String, dynamic>{
        'status': selectedCategory,
        'accountStatus': selectedCategory,
        'isActive': false,
        'revocationReason': reason.isNotEmpty ? reason : 'Access revoked by admin ($selectedCategory)',
        'revokedAt': FieldValue.serverTimestamp(),
      };
    }

    try {
      await LocalStorageService.saveUserOffline(
        uid: widget.userId,
        branchId: widget.branchId,
        userData: {
          ...data,
          ...updates,
          'uid': widget.userId,
          'branchId': widget.branchId,
        },
      );

      if (widget.isOnline && !isLocal) {
        await _firestore
            .collection('users')
            .doc(widget.userId)
            .set(updates, SetOptions(merge: true));

        if (widget.branchId != 'all' && widget.branchId.isNotEmpty) {
          await _firestore
              .collection('branches')
              .doc(widget.branchId)
              .collection('users')
              .doc(widget.userId)
              .set(updates, SetOptions(merge: true));
        }
      }

      _snack(isRevoked ? 'App access restored for ${data['username'] ?? 'user'}' : 'Access revoked for ${data['username'] ?? 'user'} ($selectedCategory)', success: true);
    } catch (e) {
      _snack('Error updating access status: $e', error: true);
    }
  }

  Widget _errorState(RoleThemeData t) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: t.danger.withValues(alpha: 0.6)),
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
