import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import '../utils/localization_helper.dart';
import '../services/local_storage_service.dart';
import '../utils/formatters.dart';
import '../services/offline_auth_service.dart' as offline_auth;
import '../services/auto_update_service.dart';
import '../services/image_upload_service.dart';
import '../widgets/update_dialog_widget.dart';


class SettingsPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const SettingsPage({super.key, required this.userData});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Box _settingsBox;
  late TextEditingController _terminalIdController;

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box('app_settings');
    
    final currentTid = _settingsBox.get('terminal_id', defaultValue: '') as String;
    _terminalIdController = TextEditingController(text: currentTid);
    
    _terminalIdController.addListener(_onTerminalIdChanged);
  }

  @override
  void dispose() {
    _terminalIdController.removeListener(_onTerminalIdChanged);
    _terminalIdController.dispose();
    super.dispose();
  }

  void _onTerminalIdChanged() {
    final text = _terminalIdController.text.trim().toUpperCase();
    _settingsBox.put('terminal_id', text);
  }

  ImageProvider? _getProfileImageProvider(String? photoStr) {
    if (photoStr == null || photoStr.trim().isEmpty) return null;
    final s = photoStr.trim();
    if (s.startsWith('data:image') || s.length > 200) {
      try {
        final base64Str = s.contains(',') ? s.split(',').last : s;
        final bytes = base64Decode(base64Str.replaceAll(RegExp(r'\s+'), ''));
        return MemoryImage(bytes);
      } catch (_) {}
    }
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return NetworkImage(s);
    }
    try {
      if (File(s).existsSync()) {
        return FileImage(File(s));
      }
    } catch (_) {}
    return null;
  }

  Future<void> _pickProfilePicture(BuildContext context) async {
    final source = await ImageUploadService.showSourceDialog(context, title: 'Choose Profile Photo');
    if (source == null) return;

    final base64Img = await ImageUploadService.pickAndProcessImage(source: source, maxWidth: 512, maxHeight: 512);
    if (base64Img == null || base64Img.isEmpty) return;

    setState(() {
      widget.userData['profileImage'] = base64Img;
      widget.userData['photoUrl'] = base64Img;
      widget.userData['profilePictureUrl'] = base64Img;
    });

    await LocalStorageService.saveLocalUser(widget.userData);
    await offline_auth.OfflineAuthService.updateCachedUserData(widget.userData);

    try {
      final uid = (FirebaseAuth.instance.currentUser?.uid ?? widget.userData['uid'] ?? widget.userData['id'])?.toString();
      if (uid != null && uid.isNotEmpty) {
        final updateData = {
          'profileImage': base64Img,
          'photoUrl': base64Img,
          'profilePictureUrl': base64Img,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await FirebaseFirestore.instance.collection('users').doc(uid).set(updateData, SetOptions(merge: true));

        final branchId = widget.userData['branchId']?.toString();
        if (branchId != null && branchId.isNotEmpty && branchId != 'all' && branchId != 'unknown') {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .collection('users')
              .doc(uid)
              .set(updateData, SetOptions(merge: true));
        }

        try {
          final cgSnap = await FirebaseFirestore.instance
              .collectionGroup('users')
              .where('uid', isEqualTo: uid)
              .get()
              .timeout(const Duration(seconds: 4));
          for (final doc in cgSnap.docs) {
            await doc.reference.set(updateData, SetOptions(merge: true));
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[SettingsPage] Error uploading profile photo to cloud: $e');
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profile picture updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  TextStyle _getStyle(RoleThemeData t, {double size = 14, FontWeight weight = FontWeight.normal, double height = 1.2}) {
    return TextStyle(
      color: t.textPrimary,
      fontSize: size,
      fontWeight: weight,
      height: height,
    );
  }

  Widget _sectionLabel(RoleThemeData t, String labelKey) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12, top: 16),
      child: Text(
        context.tr(labelKey).toUpperCase(),
        style: TextStyle(
          color: t.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _profileItem(RoleThemeData t, IconData icon, String labelKey, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.bgRule),
            ),
            child: Icon(icon, color: t.textSecondary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(labelKey),
                  style: TextStyle(color: t.textTertiary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(RoleThemeData t) {
    return Divider(color: t.bgRule, height: 24);
  }

  Widget _buildColorPill(RoleThemeData t, String label, String? hexColor, Color previewColor) {
    final activeHex = _settingsBox.get('custom_accent_color') as String?;
    final isSelected = (hexColor == null && (activeHex == null || activeHex.isEmpty)) || (hexColor != null && activeHex == hexColor);
    final isLightColor = previewColor.computeLuminance() > 0.45;
    
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: () async {
          if (hexColor == null) {
            await _settingsBox.delete('custom_accent_color');
          } else {
            await _settingsBox.put('custom_accent_color', hexColor);
          }
          setState(() {});
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: previewColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? t.textPrimary : t.bgRule,
              width: isSelected ? 3.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: previewColor.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]
                : [],
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  color: isLightColor ? Colors.black : Colors.white,
                  size: 20,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildCustomHexColorPill(RoleThemeData t) {
    final activeHex = _settingsBox.get('custom_accent_color') as String?;
    const presetHexes = {
      '#4A7FB5', '#B8860B', '#0047AB', '#2C4A8F', '#3A5178',
      '#00A86B', '#2E7D5B', '#0E6E63', '#0E7C90', '#4B0082',
      '#008080', '#5E5490', '#C2185B', '#D97706', '#DC2626'
    };
    final isCustomSelected = activeHex != null && activeHex.isNotEmpty && !presetHexes.contains(activeHex);

    Color customPreview = t.accent;
    if (isCustomSelected) {
      try {
        final hex = activeHex.replaceAll('#', '');
        customPreview = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }

    final isLightColor = customPreview.computeLuminance() > 0.45;

    return Tooltip(
      message: isCustomSelected ? 'Custom ($activeHex)' : 'Custom Hex Color',
      child: GestureDetector(
        onTap: () => _showCustomColorDialog(t),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isCustomSelected ? customPreview : t.bgCardAlt,
            shape: BoxShape.circle,
            border: Border.all(
              color: isCustomSelected ? t.textPrimary : t.bgRule,
              width: isCustomSelected ? 3.0 : 1.0,
            ),
            boxShadow: isCustomSelected
                ? [BoxShadow(color: customPreview.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]
                : [],
          ),
          child: isCustomSelected
              ? Icon(
                  Icons.check,
                  color: isLightColor ? Colors.black : Colors.white,
                  size: 20,
                )
              : Icon(
                  Icons.colorize_rounded,
                  color: t.textSecondary,
                  size: 20,
                ),
        ),
      ),
    );
  }

  Future<void> _showCustomColorDialog(RoleThemeData t) async {
    final activeHex = _settingsBox.get('custom_accent_color') as String? ?? '#4A7FB5';
    final ctrl = TextEditingController(text: activeHex);
    String tempHex = activeHex;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Color? preview;
            try {
              final hex = tempHex.replaceAll('#', '').trim();
              if (hex.length == 6) {
                preview = Color(int.parse('FF$hex', radix: 16));
              }
            } catch (_) {}

            return AlertDialog(
              backgroundColor: t.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Custom Accent Color', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: preview ?? t.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.bgRule, width: 2),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
                          decoration: roleInputDecoration(context, label: 'HEX Code (e.g. #4A7FB5)', icon: Icons.palette_outlined),
                          onChanged: (val) {
                            tempHex = val;
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: t.textTertiary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: preview ?? t.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: preview != null ? () => Navigator.pop(ctx, tempHex.toUpperCase().trim()) : null,
                  child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      String cleanHex = result.startsWith('#') ? result : '#$result';
      await _settingsBox.put('custom_accent_color', cleanHex);
      setState(() {});
    }
  }

  Widget _buildToggleButton(RoleThemeData t, String text, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? t.accent : t.bgCardAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? t.accent : t.bgRule,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: t.accent.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))]
                : [],
          ),
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : t.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedSelector<T>(
    RoleThemeData t, 
    String labelKey, 
    T activeValue, 
    Map<T, String> options, 
    Function(T) onSelected
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(labelKey),
          style: _getStyle(t, size: 13, weight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: options.entries.map((entry) {
            final isSelected = activeValue == entry.key;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildToggleButton(
                  t, 
                  context.tr(entry.value), 
                  isSelected, 
                  () => onSelected(entry.key)
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showEditProfileDialog(BuildContext context, RoleThemeData t, Map<String, dynamic> userData, String userName, String email) {
    final nameController = TextEditingController(text: userName);
    final emailController = TextEditingController(text: email);
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.edit_calendar_outlined, color: t.accent),
            const SizedBox(width: 12),
            Text(context.tr('edit_profile'), style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: roleInputDecoration(context, label: "Display Name", icon: Icons.person_outline_rounded),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: roleInputDecoration(context, label: "Email Address", icon: Icons.alternate_email_rounded),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: roleInputDecoration(context, label: "Reason for name change (optional)", icon: Icons.help_outline_rounded),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel'), style: TextStyle(color: t.textTertiary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newEmail = emailController.text.trim();
              final newReason = reasonController.text.trim();
              if (newName.isEmpty || newEmail.isEmpty) return;

              final oldName = userName;
              final nameChanged = newName != oldName;

              if (nameChanged) {
                final history = List<Map<String, dynamic>>.from(userData['nameHistory'] ?? []);
                history.add({
                  'oldName': oldName,
                  'newName': newName,
                  'changedBy': userData['username'] ?? userData['email'] ?? 'User',
                  'changedAt': DateTime.now().toIso8601String(),
                  'how': 'Settings Page',
                  if (newReason.isNotEmpty) 'reason': newReason,
                });
                userData['nameHistory'] = history;
              }

              setState(() {
                userData['name'] = newName;
                userData['username'] = newName;
                userData['email'] = newEmail;
              });

              // Save to Hive users database & secure storage credentials cache
              await LocalStorageService.saveLocalUser(userData);
              await offline_auth.OfflineAuthService.updateCachedUserData(userData);

              // Update online in Firebase Firestore
              try {
                final uid = (FirebaseAuth.instance.currentUser?.uid ?? userData['uid'] ?? userData['id'])?.toString();
                if (uid != null && uid.isNotEmpty) {
                  final updateData = {
                    'name': newName,
                    'username': newName,
                    'email': newEmail,
                    'updatedAt': FieldValue.serverTimestamp(),
                    if (nameChanged) 'nameHistory': userData['nameHistory'],
                  };

                  await FirebaseFirestore.instance.collection('users').doc(uid).set(updateData, SetOptions(merge: true));

                  final branchId = userData['branchId']?.toString();
                  if (branchId != null && branchId.isNotEmpty && branchId != 'all' && branchId != 'unknown') {
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(branchId)
                        .collection('users')
                        .doc(uid)
                        .set(updateData, SetOptions(merge: true));
                  }

                  try {
                    final cgSnap = await FirebaseFirestore.instance
                        .collectionGroup('users')
                        .where('uid', isEqualTo: uid)
                        .get()
                        .timeout(const Duration(seconds: 4));
                    for (final doc in cgSnap.docs) {
                      await doc.reference.set(updateData, SetOptions(merge: true));
                    }
                  } catch (_) {}
                }
              } catch (e) {
                debugPrint('[SettingsPage] Error syncing profile to Firebase: $e');
              }

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Profile updated and saved locally!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(context.tr('confirm'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, RoleThemeData t) {
    final oldPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool showOldPw = false;
    bool showNewPw = false;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: t.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: t.accent),
                const SizedBox(width: 12),
                Text(
                  context.tr('change_password'),
                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: oldPwCtrl,
                    obscureText: !showOldPw,
                    style: TextStyle(color: t.textPrimary),
                    decoration: roleInputDecoration(
                      context, 
                      label: "Old Password", 
                      icon: Icons.lock_open_rounded
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          showOldPw ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: t.accent.withValues(alpha: 0.8),
                          size: 20,
                        ),
                        onPressed: () => setDialogState(() => showOldPw = !showOldPw),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? "Old password is required" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: newPwCtrl,
                    obscureText: !showNewPw,
                    style: TextStyle(color: t.textPrimary),
                    decoration: roleInputDecoration(
                      context, 
                      label: "New Password", 
                      icon: Icons.lock_outline_rounded
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          showNewPw ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: t.accent.withValues(alpha: 0.8),
                          size: 20,
                        ),
                        onPressed: () => setDialogState(() => showNewPw = !showNewPw),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().length < 6) ? "Minimum 6 characters required" : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: Text(context.tr('cancel'), style: TextStyle(color: t.textTertiary, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  if (!formKey.currentState!.validate()) return;
                  
                  final email = (widget.userData['email'] as String? ?? widget.userData['username'] as String? ?? '').trim();
                  if (email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("❌ Email/Username not found on this profile!"),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final oldPw = oldPwCtrl.text.trim();
                  final newPw = newPwCtrl.text.trim();

                  if (oldPw == newPw) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("⚠️ New password must be different from old password!"),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  setDialogState(() => isSubmitting = true);

                  try {
                    // Check online authentication if current user is logged into Firebase
                    final currentUser = FirebaseAuth.instance.currentUser;
                    bool firebaseAuthUpdated = false;

                    if (currentUser != null && currentUser.email != null) {
                      try {
                        final cred = EmailAuthProvider.credential(
                          email: currentUser.email!,
                          password: oldPw,
                        );
                        await currentUser.reauthenticateWithCredential(cred);
                        await currentUser.updatePassword(newPw);
                        firebaseAuthUpdated = true;
                      } on FirebaseAuthException catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          final errMsg = e.code == 'wrong-password' || e.code == 'invalid-credential'
                              ? "❌ Incorrect old password! Please re-type your current password."
                              : (e.message ?? "Failed to update Firebase Auth password.");
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(errMsg), backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }
                    } else {
                      // Validate against stored local credentials if Firebase currentUser is null or offline
                      final cachedPw = await offline_auth.OfflineAuthService.getStoredPassword(email);
                      final profilePw = widget.userData['password'] as String?;
                      
                      final expectedPw = (cachedPw != null && cachedPw.isNotEmpty) ? cachedPw : profilePw;
                      if (expectedPw != null && expectedPw.isNotEmpty && expectedPw != oldPw) {
                        setDialogState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("❌ Incorrect old password! Please check your credentials."),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        return;
                      }
                    }

                    // Sync to Firestore documents if online user ID exists
                    if (currentUser != null) {
                      final userId = currentUser.uid;
                      final branchId = widget.userData['branchId'] as String? ?? '';
                      final updateMap = {
                        'password': newPw,
                        'updatedAt': FieldValue.serverTimestamp(),
                      };
                      await FirebaseFirestore.instance.collection('users').doc(userId).update(updateMap).catchError((_) {});
                      if (branchId.isNotEmpty && branchId != 'all') {
                        await FirebaseFirestore.instance
                            .collection('branches')
                            .doc(branchId)
                            .collection('users')
                            .doc(userId)
                            .update(updateMap)
                            .catchError((_) {});
                      }
                    }

                    // Update local storage in Hive and FlutterSecureStorage
                    widget.userData['password'] = newPw;
                    await LocalStorageService.saveLocalUser(widget.userData);
                    await offline_auth.OfflineAuthService.updateCachedPassword(newPw, usernameOrEmail: email);
                    await offline_auth.OfflineAuthService.saveCredentials(
                      usernameOrEmail: email, 
                      password: newPw, 
                      userData: widget.userData
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            firebaseAuthUpdated
                                ? "✅ Password changed successfully in Cloud & Local storage!"
                                : "✅ Password changed successfully in local database!"
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  } catch (e) {
                    setDialogState(() => isSubmitting = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("❌ Failed to change password: $e"), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(context.tr('confirm'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleStr = (widget.userData['role'] as String? ?? 'admin').toLowerCase().trim();
    final roleTheme = RoleThemeData.fromString(roleStr);

    return RoleThemeScope(
      role: roleTheme,
      child: ValueListenableBuilder(
        valueListenable: Hive.box('app_settings').listenable(keys: [
          'custom_accent_color',
          'card_radius',
          'is_dark_mode',
          'language',
          'font_scale',
        ]),
        builder: (context, Box box, child) {
          final t = RoleThemeScope.dataOf(context);
          final isDesktop = MediaQuery.of(context).size.width >= 900;
          final userName = resolveUserDisplayName(widget.userData);
          final email = widget.userData['email'] ?? 'No email set';
          final rawRole = widget.userData['role'] as String? ?? 'staff';
          final role = rawRole.toLowerCase() == 'madrassa parent' ? 'GUARDIAN' : rawRole.toUpperCase();
          final branch = widget.userData['branchName'] ?? 'All Branches';

          final initials = userName.isNotEmpty
              ? userName.split(' ').map((e) => e[0]).take(2).join().toUpperCase()
              : 'U';

          final profileImgStr = (widget.userData['profileImage'] ?? widget.userData['profilePictureUrl'] ?? widget.userData['photoUrl'])?.toString();
          final profileProvider = _getProfileImageProvider(profileImgStr);

          final activeRadius = box.get('card_radius', defaultValue: 16.0) as double;
          final activeFontScale = box.get('font_scale', defaultValue: 1.0) as double;
          final isDarkMode = box.get('is_dark_mode', defaultValue: false) as bool;
          final activeLanguage = box.get('language', defaultValue: 'en') as String;

          return Directionality(
            textDirection: activeLanguage == 'ur' ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              backgroundColor: t.bg,
              appBar: AppBar(
                backgroundColor: t.bgCard,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: Icon(
                    Icons.arrow_back_rounded, 
                    color: t.textSecondary, 
                    size: 22
                  ),
                  onPressed: () => Navigator.maybePop(context),
                ),
                title: Text(
                  context.tr('settings'),
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Divider(color: t.bgRule, height: 1),
                ),
              ),
              body: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 680 : double.infinity),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // PROFILE SECTION
                        _sectionLabel(t, 'account_profile'),
                        RoleCard(
                          showGlow: true,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _pickProfilePicture(context),
                                    child: Stack(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: [t.accent, t.accent.withValues(alpha: 0.35)],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: t.accent.withValues(alpha: 0.35),
                                                blurRadius: 20,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            radius: 60,
                                            backgroundColor: isDarkMode ? const Color(0xFF161B22) : Colors.white,
                                            backgroundImage: profileProvider,
                                            child: profileProvider == null
                                                ? Text(
                                                    initials,
                                                    style: TextStyle(
                                                      color: t.accent,
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 36,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 2,
                                          right: 2,
                                          child: Container(
                                            padding: const EdgeInsets.all(7),
                                            decoration: BoxDecoration(
                                              color: t.accent,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isDarkMode ? const Color(0xFF161B22) : Colors.white,
                                                width: 2.5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: t.accent.withValues(alpha: 0.4),
                                                  blurRadius: 8,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt_rounded,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                userName,
                                                style: TextStyle(
                                                  color: t.textPrimary,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 20,
                                                  letterSpacing: -0.3,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.edit_note_rounded, color: t.accent, size: 26),
                                              onPressed: () => _showEditProfileDialog(context, t, widget.userData, userName, email),
                                              tooltip: 'Edit Profile',
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          email,
                                          style: TextStyle(color: t.textTertiary, fontSize: 13.5),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              _divider(t),
                              _profileItem(t, Icons.badge_outlined, 'role', role),
                              _divider(t),
                              _profileItem(t, Icons.location_on_outlined, 'branch', branch),
                              _divider(t),
                              ListTile(
                                onTap: () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Checking for application updates...'),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: t.accent,
                                    ),
                                  );
                                  final info = await AutoUpdateService.checkForUpdates();
                                  if (context.mounted) {
                                    if (info != null && info.hasUpdate) {
                                      UpdateDialogWidget.showUpdateDialogIfNeeded(context, manualCheck: true);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Your GMWF Platform is up to date (v${AutoUpdateService.currentVersion})!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  }
                                },
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: t.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.system_update_rounded, color: t.accent, size: 20),
                                ),
                                title: Text(
                                  'App Version v${AutoUpdateService.currentVersion}',
                                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  'Tap to check for updates',
                                  style: TextStyle(color: t.textTertiary, fontSize: 12),
                                ),
                                trailing: Icon(Icons.chevron_right_rounded, color: t.textTertiary, size: 20),
                              ),
                              _divider(t),
                              ListTile(
                                onTap: () => _showChangePasswordDialog(context, t),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: t.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: t.accent.withOpacity(0.2)),
                                  ),
                                  child: Icon(Icons.lock_outline_rounded, color: t.accent, size: 22),
                                ),
                                title: Text(
                                  context.tr('change_password'),
                                  style: _getStyle(t, size: 14, weight: FontWeight.w800),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded, 
                                  color: t.textTertiary
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (widget.userData['nameHistory'] != null && (widget.userData['nameHistory'] as List).isNotEmpty) ...[
                                _divider(t),
                                Theme(
                                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    iconColor: t.accent,
                                    collapsedIconColor: t.textTertiary,
                                    title: Row(
                                      children: [
                                        Icon(Icons.history_toggle_off_rounded, color: t.accent, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Profile Name History',
                                          style: _getStyle(t, size: 13, weight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    childrenPadding: EdgeInsets.zero,
                                    children: (widget.userData['nameHistory'] as List).map((entry) {
                                      final item = Map<String, dynamic>.from(entry as Map);
                                      final oldName = item['oldName'] ?? '';
                                      final newName = item['newName'] ?? '';
                                      final changedBy = item['changedBy'] ?? '';
                                      final how = item['how'] ?? '';
                                      final whenStr = item['changedAt'] ?? '';
                                      final reason = item['reason'] ?? '';
                                      
                                      String timeFormatted = whenStr;
                                      try {
                                        final dt = DateTime.parse(whenStr);
                                        timeFormatted = DateFormat('MMM dd, yyyy - hh:mm a').format(dt.toLocal());
                                      } catch (_) {}

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: t.bgCardAlt,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: t.bgRule),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.person_outline_rounded, color: t.accent, size: 18),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            "$oldName ➔ $newName",
                                                            style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        Text(
                                                          timeFormatted,
                                                          style: TextStyle(color: t.textTertiary, fontSize: 11),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      'Edited by: $changedBy via $how',
                                                      style: TextStyle(color: t.textSecondary, fontSize: 11.5),
                                                    ),
                                                    if (reason.isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Reason: $reason',
                                                        style: TextStyle(color: t.textTertiary, fontSize: 11.5, fontStyle: FontStyle.italic),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList().reversed.toList(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // PERSONALIZATION SECTION
                        _sectionLabel(t, 'personalization'),
                        RoleCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Accent Color presets
                              Row(
                                children: [
                                  Icon(Icons.color_lens_outlined, color: t.accent),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.tr('theme_color'),
                                    style: _getStyle(t, size: 14, weight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _buildColorPill(t, 'Role Default', null, t.accentGradient.colors.first),
                                    _buildColorPill(t, 'CEO Steel Blue', '#4A7FB5', const Color(0xFF4A7FB5)),
                                    _buildColorPill(t, 'Gold Authority', '#B8860B', const Color(0xFFB8860B)),
                                    _buildColorPill(t, 'Electric Blue', '#0047AB', const Color(0xFF0047AB)),
                                    _buildColorPill(t, 'Sapphire Indigo', '#2C4A8F', const Color(0xFF2C4A8F)),
                                    _buildColorPill(t, 'Midnight Slate', '#3A5178', const Color(0xFF3A5178)),
                                    _buildColorPill(t, 'Emerald Mint', '#00A86B', const Color(0xFF00A86B)),
                                    _buildColorPill(t, 'Forest Sage', '#2E7D5B', const Color(0xFF2E7D5B)),
                                    _buildColorPill(t, 'Executive Teal', '#0E6E63', const Color(0xFF0E6E63)),
                                    _buildColorPill(t, 'Clinical Cyan', '#0E7C90', const Color(0xFF0E7C90)),
                                    _buildColorPill(t, 'Royal Indigo', '#4B0082', const Color(0xFF4B0082)),
                                    _buildColorPill(t, 'Clinical Teal', '#008080', const Color(0xFF008080)),
                                    _buildColorPill(t, 'Slate Plum', '#5E5490', const Color(0xFF5E5490)),
                                    _buildColorPill(t, 'Warm Rose', '#C2185B', const Color(0xFFC2185B)),
                                    _buildColorPill(t, 'Sunset Amber', '#D97706', const Color(0xFFD97706)),
                                    _buildColorPill(t, 'Crimson Red', '#DC2626', const Color(0xFFDC2626)),
                                    _buildCustomHexColorPill(t),
                                  ],
                                ),
                              ),
                              _divider(t),

                              // 2. Card corner radius choices
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSegmentedSelector<double>(
                                    t, 
                                    'card_radius', 
                                    activeRadius, 
                                    {
                                      8.0: 'sharp',
                                      16.0: 'medium',
                                      24.0: 'round',
                                    }, 
                                    (radius) async {
                                      await box.put('card_radius', radius);
                                      setState(() {});
                                    }
                                  ),
                                  const SizedBox(height: 12),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: t.accent.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(activeRadius),
                                      border: Border.all(color: t.accent.withValues(alpha: 0.3), width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: t.accent,
                                            borderRadius: BorderRadius.circular((activeRadius / 2).clamp(4.0, 12.0)),
                                          ),
                                          child: const Icon(Icons.rounded_corner_rounded, color: Colors.white, size: 20),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Card Radius Preview (${activeRadius.toInt()}px)',
                                                style: TextStyle(
                                                  color: t.textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Cards, dialogs, and UI cards adjust live across the app.',
                                                style: TextStyle(
                                                  color: t.textSecondary,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              _divider(t),

                              // 3. Text scaling scale slider/selector
                              _buildSegmentedSelector<double>(
                                t, 
                                'font_scale', 
                                activeFontScale, 
                                {
                                  0.85: 'small',
                                  1.0: 'medium',
                                  1.15: 'large',
                                  1.30: 'extra_large',
                                }, 
                                (scale) => box.put('font_scale', scale)
                              ),
                              _divider(t),

                              // 4. Dark Mode / Light Mode Toggle
                              SwitchListTile(
                                value: isDarkMode,
                                activeThumbColor: t.accent,
                                onChanged: (val) async {
                                  await box.put('is_dark_mode', val);
                                  setState(() {});
                                },
                                secondary: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: t.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                    color: t.accent,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  'Dark Mode',
                                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  isDarkMode ? 'Dark charcoal theme active' : 'Light surface theme active',
                                  style: TextStyle(color: t.textSecondary, fontSize: 12),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              _divider(t),

                              // 5. App Language Selector
                              _buildSegmentedSelector<String>(
                                t, 
                                'language', 
                                activeLanguage, 
                                {
                                  'en': 'English 🇬🇧',
                                  'ur': 'اردو 🇵🇰',
                                }, 
                                (lang) async {
                                  await box.put('language', lang);
                                  setState(() {});
                                }
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        Center(
                          child: Text(
                            "GMWF System Hub v${AutoUpdateService.currentVersion}\nDesign & Theming by Antigravity Studio",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: t.textTertiary, fontSize: 11, fontWeight: FontWeight.w500, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
