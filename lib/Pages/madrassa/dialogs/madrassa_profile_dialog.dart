import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_storage_service.dart';
import '../../../widgets/app_feedback.dart';
import '../madrassa_strings.dart';
import '../widgets/madrassa_common_widgets.dart';

class MadrassaProfileDialog extends StatefulWidget {
  final String branchId;
  final String currentUsername;
  final String userRole;

  const MadrassaProfileDialog({
    super.key,
    required this.branchId,
    required this.currentUsername,
    required this.userRole,
  });

  static Future<String?> show(
    BuildContext context, {
    required String branchId,
    required String currentUsername,
    required String userRole,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MadrassaProfileDialog(
        branchId: branchId,
        currentUsername: currentUsername,
        userRole: userRole,
      ),
    );
  }

  @override
  State<MadrassaProfileDialog> createState() => _MadrassaProfileDialogState();
}

class _MadrassaProfileDialogState extends State<MadrassaProfileDialog> {
  late TextEditingController _nameController;
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isSaving = false;
  String? _nameError;
  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmPasswordError;
  String _userUid = '';
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUsername);
    _loadUserMetadata();
  }

  void _loadUserMetadata() {
    final curUser = FirebaseAuth.instance.currentUser;
    if (curUser != null) {
      _userUid = curUser.uid;
      _userEmail = curUser.email ?? '';
      if (curUser.displayName != null && curUser.displayName!.trim().isNotEmpty) {
        _nameController.text = curUser.displayName!.trim();
      }
    }

    if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
      final box = Hive.box(LocalStorageService.usersBox);
      for (final k in box.keys) {
        final val = box.get(k);
        if (val is Map) {
          final uName = (val['username'] ?? '').toString().toLowerCase().trim();
          final uEmail = (val['email'] ?? '').toString().toLowerCase().trim();
          final uUid = (val['uid'] ?? val['id'] ?? '').toString().trim();
          if (uName == widget.currentUsername.toLowerCase().trim() || (_userEmail.isNotEmpty && uEmail == _userEmail.toLowerCase()) || (_userUid.isNotEmpty && uUid == _userUid)) {
            if (_userUid.isEmpty && uUid.isNotEmpty) _userUid = uUid;
            if (_userEmail.isEmpty && uEmail.isNotEmpty) _userEmail = uEmail;
            final fullName = (val['name'] ?? val['displayName'] ?? '').toString().trim();
            if (fullName.isNotEmpty) {
              _nameController.text = fullName;
            }
            break;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() {
      _nameError = null;
      _currentPasswordError = null;
      _newPasswordError = null;
      _confirmPasswordError = null;
    });

    final newName = _nameController.text.trim();
    final curPass = _currentPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confPass = _confirmPasswordController.text.trim();

    if (newName.isEmpty) {
      setState(() => _nameError = context.isUrdu ? 'براہ کرم اپنا نام درج کریں' : 'Please enter your name');
      return;
    }

    bool changingPassword = newPass.isNotEmpty || confPass.isNotEmpty;

    if (changingPassword) {
      if (curPass.isEmpty) {
        setState(() => _currentPasswordError = context.isUrdu ? 'موجودہ پاس ورڈ درج کرنا لازمی ہے' : 'Current password is required');
        return;
      }
      if (newPass.length < 6) {
        setState(() => _newPasswordError = context.isUrdu ? 'پاس ورڈ کم از کم 6 حروف پر مشتمل ہونا چاہیے' : 'Password must be at least 6 characters');
        return;
      }
      if (newPass != confPass) {
        setState(() => _confirmPasswordError = context.isUrdu ? 'پاس ورڈز آپس میں مماثل نہیں ہیں' : 'Passwords do not match');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final uidToUpdate = _userUid.isNotEmpty
          ? _userUid
          : (FirebaseAuth.instance.currentUser?.uid ?? widget.currentUsername);

      await AuthService().updateUserProfileAndCredentials(
        uid: uidToUpdate,
        newName: newName,
        currentPassword: changingPassword ? curPass : null,
        newPassword: changingPassword ? newPass : null,
        branchId: widget.branchId,
      );

      if (mounted) {
        AppFeedback.showSuccess(
          context,
          context.isUrdu ? 'پروفائل کامیابی سے اپ ڈیٹ ہو گیا!' : 'Profile updated successfully!',
          subtitle: changingPassword
              ? (context.isUrdu ? 'نام اور پاس ورڈ تبدیل کر دیے گئے ہیں۔' : 'Name and password have been updated.')
              : (context.isUrdu ? 'آپ کا نام اپ ڈیٹ ہو گیا ہے۔' : 'Your name has been updated.'),
        );
        Navigator.of(context).pop(newName);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      final errStr = e.toString();
      if (errStr.contains('Incorrect current password') || errStr.contains('wrong-password') || errStr.contains('invalid-credential')) {
        setState(() => _currentPasswordError = context.isUrdu ? 'موجودہ پاس ورڈ غلط ہے' : 'Incorrect current password');
      } else {
        AppFeedback.showWarning(
          context,
          context.isUrdu ? 'اپ ڈیٹ کرنے میں خرابی پیش آگئی' : 'Failed to update profile',
          subtitle: errStr.replaceAll('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF0F766E), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.isUrdu ? 'پروفائل اور سیکیورٹی سیٹنگز' : 'Profile & Account Security',
                          style: context.urduStyle(
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                        ),
                        Text(
                          '${widget.branchId.toUpperCase()} • ${widget.userRole}',
                          style: TextStyle(fontSize: 11.5, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: borderColor),
              const SizedBox(height: 18),

              // Section 1: Edit Name
              Text(
                context.isUrdu ? 'آپ کا مکمل نام' : 'Your Full / Display Name',
                style: context.urduStyle(
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                style: TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: context.isUrdu ? 'اپنا نام درج کریں' : 'Enter your name',
                  errorText: _nameError,
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: Color(0xFF0F766E)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                ),
              ),
              const SizedBox(height: 20),

              // Section 2: Change Password
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_reset_rounded, size: 18, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        Text(
                          context.isUrdu ? 'پاس ورڈ تبدیل کریں (اختیاری)' : 'Change Password (Optional)',
                          style: context.urduStyle(
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.isUrdu
                          ? 'اگر آپ پاس ورڈ تبدیل نہیں کرنا چاہتے تو ان خانوں کو خالی چھوڑ دیں۔'
                          : 'Leave these blank if you only wish to update your name.',
                      style: context.urduStyle(
                        style: TextStyle(fontSize: 11, color: textMuted),
                      ),
                    ),
                    const SizedBox(height: 12),

                    PasswordField(
                      controller: _currentPasswordController,
                      label: context.isUrdu ? 'موجودہ پاس ورڈ' : 'Current Password',
                      isRequired: false,
                      enabled: !_isSaving,
                      errorText: _currentPasswordError,
                      onChanged: (_) {
                        if (_currentPasswordError != null) setState(() => _currentPasswordError = null);
                      },
                    ),
                    const SizedBox(height: 10),

                    PasswordField(
                      controller: _newPasswordController,
                      label: context.isUrdu ? 'نیا پاس ورڈ (کم از کم 6 حروف)' : 'New Password (min 6 characters)',
                      isRequired: false,
                      enabled: !_isSaving,
                      errorText: _newPasswordError,
                      onChanged: (_) {
                        if (_newPasswordError != null) setState(() => _newPasswordError = null);
                      },
                    ),
                    const SizedBox(height: 10),

                    PasswordField(
                      controller: _confirmPasswordController,
                      label: context.isUrdu ? 'نئے پاس ورڈ کی تصدیق کریں' : 'Confirm New Password',
                      isRequired: false,
                      enabled: !_isSaving,
                      errorText: _confirmPasswordError,
                      onChanged: (_) {
                        if (_confirmPasswordError != null) setState(() => _confirmPasswordError = null);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: Text(
                      context.isUrdu ? 'منسوخ کریں' : 'Cancel',
                      style: TextStyle(color: textMuted),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _handleSave,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 16),
                    label: Text(
                      _isSaving
                          ? (context.isUrdu ? 'محفوظ ہو رہا ہے...' : 'Saving...')
                          : (context.isUrdu ? 'محفوظ کریں' : 'Save Changes'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
