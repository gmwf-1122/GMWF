// lib/pages/dispensary/user_settings_dialog.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:gmwf/design/components/app_toast.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../services/offline_auth_service.dart';
import '../../services/local_storage_service.dart';
import '../../realtime/realtime_manager.dart';
import '../../realtime/realtime_events.dart';

class DispensaryUserSettingsDialog {
  static Future<void> show(
    BuildContext context, {
    required String branchId,
    VoidCallback? onUserUpdated,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    bool isSubmitting = false;
    String initialName = '';
    String? currentUid;

    // Load initial values from Hive / FirebaseAuth
    String? photoUrl;
    try {
      final user = FirebaseAuth.instance.currentUser;
      currentUid = user?.uid;
      photoUrl = user?.photoURL;

      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final uData = box.get('user_data') ?? box.get('currentUser');
        if (uData is Map) {
          initialName = (uData['username'] ?? uData['name'] ?? '').toString();
          final url = uData['photoUrl'] ?? uData['photoURL'] ?? uData['profileImageUrl'] ?? uData['avatarUrl'];
          if (url != null && url.toString().trim().isNotEmpty) {
            photoUrl = url.toString().trim();
          }
        }
      }

      if (initialName.isEmpty && user?.displayName != null && user!.displayName!.isNotEmpty) {
        initialName = user.displayName!;
      }
      nameCtrl.text = initialName;
    } catch (_) {}

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: SoftPalette.teal200,
                            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                                ? NetworkImage(photoUrl)
                                : null,
                            child: (photoUrl == null || photoUrl.isEmpty)
                                ? Text(
                                    initialName.isNotEmpty ? initialName[0].toUpperCase() : 'U',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: SoftPalette.teal700,
                                      fontSize: 18,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'User Account Settings',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Change name & password',
                                  style: TextStyle(fontSize: 12, color: ctx.adapt(SoftPalette.gray500)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Display Name
                      const Text(
                        'Display Name / Username',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          hintText: 'Enter your display name',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                      ),

                      const SizedBox(height: 20),
                      const Text(
                        'Change Password (Optional)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),

                      TextFormField(
                        controller: oldPassCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'Current (Old) Password',
                          prefixIcon: const Icon(Icons.lock_clock_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextFormField(
                        controller: newPassCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'New Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          if (oldPassCtrl.text.isNotEmpty && (v == null || v.length < 4)) {
                            return 'New password must be at least 4 chars';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),

                      TextFormField(
                        controller: confirmPassCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'Confirm New Password',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          if (newPassCtrl.text.isNotEmpty && v != newPassCtrl.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),



                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SoftPalette.teal550,
                                foregroundColor: SoftPalette.gray50,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;
                                      setS(() => isSubmitting = true);

                                      try {
                                        final user = FirebaseAuth.instance.currentUser;
                                        final newName = nameCtrl.text.trim();
                                        final oldPass = oldPassCtrl.text.trim();
                                        final newPass = newPassCtrl.text.trim();

                                        // 1. Password change if requested
                                        if (oldPass.isNotEmpty) {
                                          if (newPass.isEmpty) {
                                            throw 'Please enter your new password';
                                          }
                                          if (user != null && user.email != null) {
                                            final cred = EmailAuthProvider.credential(
                                              email: user.email!,
                                              password: oldPass,
                                            );
                                            await user.reauthenticateWithCredential(cred);
                                            await user.updatePassword(newPass);
                                            await OfflineAuthService.updateCachedPassword(newPass, usernameOrEmail: user.email!);
                                          }
                                        }

                                        // 2. Name update if changed
                                        if (newName != initialName && newName.isNotEmpty) {
                                          if (user != null) {
                                            await user.updateDisplayName(newName).catchError((_) {});
                                          }

                                          // Update Firestore
                                          if (currentUid != null && currentUid.isNotEmpty) {
                                            final updates = {
                                              'username': newName,
                                              'usernameLower': newName.toLowerCase(),
                                              'name': newName,
                                              'displayName': newName,
                                            };
                                            await FirebaseFirestore.instance
                                                .collection('branches')
                                                .doc(branchId)
                                                .collection('users')
                                                .doc(currentUid)
                                                .update(updates)
                                                .catchError((_) {});

                                            await FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(currentUid)
                                                .update(updates)
                                                .catchError((_) {});

                                            // Enqueue for offline durable cloud sync
                                            try {
                                              await LocalStorageService.enqueueSync({
                                                'type': 'save_user',
                                                'uid': currentUid,
                                                'branchId': branchId,
                                                'data': updates,
                                              });
                                            } catch (_) {}

                                            // Update local users box
                                            try {
                                              if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
                                                final uBox = Hive.box(LocalStorageService.usersBox);
                                                final existingU = uBox.get(currentUid);
                                                if (existingU is Map) {
                                                  final uMerged = Map<String, dynamic>.from(existingU)..addAll(updates);
                                                  await uBox.put(currentUid, uMerged);
                                                }
                                              }
                                            } catch (_) {}

                                            // Broadcast over LAN WebSocket to all connected stations
                                            try {
                                              RealtimeManager().sendMessage(RealtimeEvents.payload(
                                                type: 'user_updated',
                                                branchId: branchId,
                                                data: {
                                                  'uid': currentUid,
                                                  ...updates,
                                                },
                                              ));
                                              RealtimeManager().updateUsername(newName);
                                            } catch (_) {}
                                          }

                                          // Update Hive app_settings user_data
                                          if (Hive.isBoxOpen('app_settings')) {
                                            final box = Hive.box('app_settings');
                                            final uData = box.get('user_data') ?? box.get('currentUser');
                                            if (uData is Map) {
                                              final updatedMap = Map<String, dynamic>.from(uData);
                                              updatedMap['username'] = newName;
                                              updatedMap['usernameLower'] = newName.toLowerCase();
                                              updatedMap['name'] = newName;
                                              updatedMap['displayName'] = newName;
                                              await box.put('user_data', updatedMap);
                                            }
                                          }
                                        }

                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (onUserUpdated != null) onUserUpdated();

                                        AppToast.showSnackBar(context, 
                                          const SnackBar(
                                            content: Text('Account settings updated successfully!'),
                                            backgroundColor: SoftPalette.teal500,
                                          ),
                                        );
                                      } catch (e) {
                                        setS(() => isSubmitting = false);
                                        AppToast.showSnackBar(ctx, 
                                          SnackBar(
                                            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
                                            backgroundColor: SoftPalette.red400,
                                          ),
                                        );
                                      }
                                    },
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(color: SoftPalette.gray50, strokeWidth: 2),
                                    )
                                  : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
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
