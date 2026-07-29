// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import '../utils/localization_helper.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../utils/formatters.dart';
import '../services/offline_auth_service.dart' as offline_auth;
import 'admin/data_cleanup_screen.dart';
import 'settings/biometric_device_manager_page.dart';
import '../services/auto_update_service.dart';
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
  
  bool _isSyncing = false;
  int _pendingSyncCount = 0;

  @override
  void initState() {
    super.initState();
    _settingsBox = Hive.box('app_settings');
    
    final currentTid = _settingsBox.get('terminal_id', defaultValue: '') as String;
    _terminalIdController = TextEditingController(text: currentTid);
    
    _terminalIdController.addListener(_onTerminalIdChanged);
    _updatePendingSyncCount();
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

  void _updatePendingSyncCount() {
    if (Hive.isBoxOpen(LocalStorageService.syncBox)) {
      setState(() {
        _pendingSyncCount = Hive.box(LocalStorageService.syncBox).length;
      });
    }
  }

  Future<void> _triggerManualSync() async {
    setState(() => _isSyncing = true);
    try {
      await SyncService().triggerUpload();
      _updatePendingSyncCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('sync_completed')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _forceFullRefresh(String branchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = RoleThemeScope.dataOf(context);
        return AlertDialog(
          backgroundColor: t.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            context.tr('confirm'),
            style: _getStyle(t, size: 18, weight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to force a full database redownload? This will fetch all records from the server and may take a few minutes.',
            style: _getStyle(t, size: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'), style: TextStyle(color: t.textTertiary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(context.tr('confirm')),
            ),
          ],
        );
      }
    );

    if (confirmed == true) {
      setState(() => _isSyncing = true);
      try {
        await SyncService().forceFullRefresh(branchId);
        _updatePendingSyncCount();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Full database refresh completed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Refresh failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSyncing = false);
        }
      }
    }
  }

  Future<void> _factoryReset() async {
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = RoleThemeScope.dataOf(context);
        return AlertDialog(
          backgroundColor: t.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: t.danger, size: 28),
              const SizedBox(width: 12),
              Text(
                'CRITICAL WARNING!',
                style: TextStyle(color: t.danger, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This action is irreversible. It will wipe all local Hive boxes and reset the application to its initial state.',
                style: _getStyle(t, size: 14),
              ),
              const SizedBox(height: 16),
              Text(
                'Please type "WIPE" to confirm factory reset:',
                style: _getStyle(t, size: 12, weight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (val) {
                  if (val.trim().toUpperCase() == 'WIPE') {
                    Navigator.pop(context, true);
                  }
                },
                decoration: roleInputDecoration(context, label: "Type WIPE to reset", icon: Icons.delete_forever_outlined),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'), style: TextStyle(color: t.textTertiary)),
            ),
          ],
        );
      }
    );

    if (doubleConfirmed == true) {
      await LocalStorageService.clearAllData();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      }
    }
  }

  Future<void> _clearFinanceAndDonationsData() async {
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = RoleThemeScope.dataOf(context);
        return AlertDialog(
          backgroundColor: t.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: t.danger, size: 28),
              const SizedBox(width: 12),
              Text(
                'WIPE FINANCE & DONATIONS',
                style: TextStyle(color: t.danger, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will delete all local employee list, attendance sheets, salary ledger records, expenses, and donors/donations database. Other data like patients, dispensary, and stock will not be affected.',
                style: _getStyle(t, size: 14),
              ),
              const SizedBox(height: 16),
              Text(
                'Please type "WIPE" to confirm:',
                style: _getStyle(t, size: 12, weight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (val) {
                  if (val.trim().toUpperCase() == 'WIPE') {
                    Navigator.pop(context, true);
                  }
                },
                decoration: roleInputDecoration(context, label: "Type WIPE to confirm", icon: Icons.delete_forever_outlined),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'), style: TextStyle(color: t.textTertiary)),
            ),
          ],
        );
      }
    );

    if (doubleConfirmed == true) {
      setState(() => _isSyncing = true);
      try {
        final boxesToClear = [
          LocalStorageService.donationsBox,
          LocalStorageService.donorsBox,
          LocalStorageService.employeesBox,
          LocalStorageService.salaryHistoryBox,
          LocalStorageService.attendanceBox,
          LocalStorageService.salaryLedgerBox,
          LocalStorageService.branchTransfersBox,
          LocalStorageService.expensesBox,
          LocalStorageService.financeLoansBox,
          LocalStorageService.financeHolidaysBox,
          LocalStorageService.financeSettingsBox,
        ];
        
        for (final boxName in boxesToClear) {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            await box.clear();
          } else {
            final box = await Hive.openBox(boxName);
            await box.clear();
            await box.close();
          }
        }

        // Also clean the sync queue for any finance/donation tasks to prevent syncing them to firebase
        if (Hive.isBoxOpen(LocalStorageService.syncBox)) {
          final syncBox = Hive.box(LocalStorageService.syncBox);
          final keysToRemove = [];
          for (var i = 0; i < syncBox.length; i++) {
            final key = syncBox.keyAt(i);
            final val = syncBox.get(key);
            if (val is Map) {
              final type = val['type']?.toString() ?? '';
              if (type.contains('employee') ||
                  type.contains('attendance') ||
                  type.contains('salary') ||
                  type.contains('expense') ||
                  type.contains('donation') ||
                  type.contains('donor')) {
                keysToRemove.add(key);
              }
            }
          }
          for (final k in keysToRemove) {
            await syncBox.delete(k);
          }
        }

        _updatePendingSyncCount();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Finance and Donation data has been cleared from local database.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSyncing = false);
        }
      }
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

  Widget _infoItem(RoleThemeData t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600, fontSize: 13.5)),
          Text(value, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      ),
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

              // Update online in Firebase Firestore if online
              try {
                final currentUser = FirebaseAuth.instance.currentUser;
                if (currentUser != null) {
                  final uid = currentUser.uid;
                  final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
                  final userDoc = await userRef.get();
                  if (userDoc.exists) {
                    await userRef.set({
                      'name': newName,
                      'username': newName,
                      'email': newEmail,
                      if (nameChanged) 'nameHistory': userData['nameHistory'],
                    }, SetOptions(merge: true));
                  }

                  final branchId = userData['branchId'] as String?;
                  if (branchId != null && branchId.isNotEmpty) {
                    final branchUserRef = FirebaseFirestore.instance
                        .collection('branches')
                        .doc(branchId)
                        .collection('users')
                        .doc(uid);
                    final branchUserDoc = await branchUserRef.get();
                    if (branchUserDoc.exists) {
                      await branchUserRef.set({
                        'name': newName,
                        'username': newName,
                        'email': newEmail,
                        if (nameChanged) 'nameHistory': userData['nameHistory'],
                      }, SetOptions(merge: true));
                    }
                  }
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                obscureText: true,
                style: TextStyle(color: t.textPrimary),
                decoration: roleInputDecoration(context, label: "Old Password", icon: Icons.lock_open_rounded),
                validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: newPwCtrl,
                obscureText: true,
                style: TextStyle(color: t.textPrimary),
                decoration: roleInputDecoration(context, label: "New Password", icon: Icons.lock_outline_rounded),
                validator: (v) => (v == null || v.length < 6) ? "Min 6 characters" : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel'), style: TextStyle(color: t.textTertiary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              
              final email = widget.userData['email'] as String?;
              if (email == null || email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Email not found on this profile"), backgroundColor: Colors.red),
                );
                return;
              }

              // Check connectivity
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Password change requires online connectivity"), backgroundColor: Colors.red),
                );
                return;
              }

              try {
                final cred = EmailAuthProvider.credential(
                  email: email.toLowerCase().trim(),
                  password: oldPwCtrl.text.trim(),
                );
                await currentUser.reauthenticateWithCredential(cred);
                await currentUser.updatePassword(newPwCtrl.text.trim());

                // Update cached offline password
                await offline_auth.OfflineAuthService.updateCachedPassword(
                  newPwCtrl.text.trim(),
                  usernameOrEmail: email.toLowerCase().trim(),
                );

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ Password changed successfully!"), backgroundColor: Colors.green),
                  );
                }
              } on FirebaseAuthException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.code == 'wrong-password' ? "Incorrect old password" : e.message ?? "Failed to change password"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Unexpected error: $e"), backgroundColor: Colors.red),
                  );
                }
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

  @override
  Widget build(BuildContext context) {
    final roleStr = (widget.userData['role'] as String? ?? 'admin').toLowerCase().trim();
    final roleTheme = RoleThemeData.fromString(roleStr);
    final isFullExecutive = ['admin', 'global admin', 'ceo', 'chairman', 'global user', 'manager', 'hq manager'].contains(roleStr);

    return RoleThemeScope(
      role: roleTheme,
      child: ValueListenableBuilder(
        valueListenable: Hive.box('app_settings').listenable(),
        builder: (context, Box box, child) {
          final t = RoleThemeScope.dataOf(context);
          final isDesktop = MediaQuery.of(context).size.width >= 900;
          final userName = resolveUserDisplayName(widget.userData);
          final email = widget.userData['email'] ?? 'No email set';
          final rawRole = widget.userData['role'] as String? ?? 'staff';
          final role = rawRole.toLowerCase() == 'madrassa parent' ? 'GUARDIAN' : rawRole.toUpperCase();
          final branch = widget.userData['branchName'] ?? 'All Branches';
          final branchId = widget.userData['branchId'] as String? ?? '';

          final initials = userName.isNotEmpty
              ? userName.split(' ').map((e) => e[0]).take(2).join().toUpperCase()
              : 'U';

          final activePrinter = box.get('printer_mode', defaultValue: 'pdf') as String;
          final activeWidth = box.get('receipt_width', defaultValue: '80mm') as String;
          final activeRadius = box.get('card_radius', defaultValue: 16.0) as double;
          final activeFontScale = box.get('font_scale', defaultValue: 1.0) as double;

          return Directionality(
            textDirection: TextDirection.ltr,
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
                                  CircleAvatar(
                                    radius: 36,
                                    backgroundColor: t.accent.withOpacity(0.12),
                                    child: Text(
                                      initials,
                                      style: TextStyle(color: t.accent, fontWeight: FontWeight.bold, fontSize: 24),
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
                                                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 18),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.edit_note_rounded, color: t.accent, size: 24),
                                              onPressed: () => _showEditProfileDialog(context, t, widget.userData, userName, email),
                                            ),
                                          ],
                                        ),
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
                                      UpdateDialogWidget.showUpdateDialogIfNeeded(context);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Your GMWF Platform is up to date (v1.2.6)!'),
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
                              _buildSegmentedSelector<double>(
                                t, 
                                'card_radius', 
                                activeRadius, 
                                {
                                  8.0: 'sharp',
                                  16.0: 'medium',
                                  24.0: 'round',
                                }, 
                                (radius) => box.put('card_radius', radius)
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
                            ],
                          ),
                        ),

                        // DEVICES & PRINTERS SECTION
                        _sectionLabel(t, 'devices_printer'),
                        RoleCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.print_outlined, color: t.accent),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.tr('printer_mode'),
                                    style: _getStyle(t, size: 14, weight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                dropdownColor: t.bgCard,
                                initialValue: activePrinter,
                                items: [
                                  DropdownMenuItem(value: 'pdf', child: Text(context.tr('standard_pdf'), style: TextStyle(color: t.textPrimary))),
                                  DropdownMenuItem(value: 'thermal', child: Text(context.tr('thermal_receipt'), style: TextStyle(color: t.textPrimary))),
                                ],
                                onChanged: (val) async {
                                  if (val != null) {
                                    await box.put('printer_mode', val);
                                  }
                                },
                                decoration: roleInputDecoration(context, label: "Mode Selection", icon: Icons.settings_input_hdmi_outlined),
                              ),
                              if (activePrinter == 'thermal') ...[
                                const SizedBox(height: 20),
                                Text(
                                  context.tr('receipt_width'),
                                  style: _getStyle(t, size: 13, weight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  dropdownColor: t.bgCard,
                                  initialValue: activeWidth,
                                  items: [
                                    DropdownMenuItem(value: '58mm', child: Text('58 mm (Standard)', style: TextStyle(color: t.textPrimary))),
                                    DropdownMenuItem(value: '80mm', child: Text('80 mm (Wide)', style: TextStyle(color: t.textPrimary))),
                                  ],
                                  onChanged: (val) async {
                                    if (val != null) {
                                      await box.put('receipt_width', val);
                                    }
                                  },
                                  decoration: roleInputDecoration(context, label: "Width Selection", icon: Icons.aspect_ratio_outlined),
                                ),
                              ],
                              _divider(t),
                              Text(
                                context.tr('terminal_id'),
                                style: _getStyle(t, size: 13, weight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _terminalIdController,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                                  LengthLimitingTextInputFormatter(4),
                                ],
                                style: TextStyle(color: t.textPrimary),
                                decoration: roleInputDecoration(
                                  context,
                                  label: "Configure 4-digit terminal ID code",
                                  icon: Icons.device_hub_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // DATABASE & SYNC SECTION
                        _sectionLabel(t, 'database_sync'),
                        RoleCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.cloud_sync_outlined, color: t.accent),
                                      const SizedBox(width: 8),
                                      Text(
                                        context.tr('sync_queue'),
                                        style: _getStyle(t, size: 14, weight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _pendingSyncCount > 0 ? t.danger.withOpacity(0.12) : Colors.green.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$_pendingSyncCount ${context.tr('pending')}',
                                      style: TextStyle(
                                        color: _pendingSyncCount > 0 ? t.danger : Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _isSyncing ? null : _triggerManualSync,
                                      icon: _isSyncing
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.cloud_upload_outlined),
                                      label: Text(context.tr('manual_upload')),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: t.accent,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _isSyncing ? null : () => _forceFullRefresh(branchId),
                                      icon: const Icon(Icons.sync_outlined),
                                      label: Text(context.tr('db_refresh')),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: t.accent, width: 1.5),
                                        foregroundColor: t.accent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isFullExecutive) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const DataCleanupScreen()),
                                        ),
                                        icon: const Icon(Icons.cleaning_services_outlined),
                                        label: const Text('Data Integrity & Cleanup'),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: t.accent, width: 1.5),
                                          foregroundColor: t.accent,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              _divider(t),
                              Text(
                                "Clear Finance & Donations Data",
                                style: TextStyle(color: t.danger, fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Wipe all local employees, attendance history, payroll ledger, expenses, and donation records.",
                                style: TextStyle(color: t.textTertiary, fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _clearFinanceAndDonationsData,
                                      icon: const Icon(Icons.money_off_rounded),
                                      label: const Text('Clear Finance & Donations'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange.shade800,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _divider(t),
                              Text(
                                "Factory Data Reset",
                                style: TextStyle(color: t.danger, fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Clear all cached documents, patient entries, and login parameters from the local disk.",
                                style: TextStyle(color: t.textTertiary, fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _factoryReset,
                                      icon: const Icon(Icons.delete_forever_outlined),
                                      label: Text(context.tr('factory_wipe')),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: t.danger,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // APPLICATION DIAGNOSTICS & SYSTEM INFO
                        _sectionLabel(t, 'diagnostics'),
                        RoleCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoItem(t, context.tr('app_version'), "2.1.3 (RTL Single-Page)"),
                              _divider(t),
                              _infoItem(t, context.tr('build_type'), "Production Stable"),
                              _divider(t),
                              _infoItem(t, context.tr('last_sync'), DateFormat('MMM dd, hh:mm a').format(DateTime.now())),
                              _divider(t),
                              ListTile(
                                onTap: () async {
                                  await Sentry.captureMessage(
                                    'Manual Test: Sentry is working for ${widget.userData['role']} at ${widget.userData['branchId']}',
                                    level: SentryLevel.info,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('✅ Test event sent to Sentry dashboard!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                },
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.radar_rounded, color: Colors.blue, size: 20),
                                ),
                                title: Text(
                                  context.tr('test_crash'),
                                  style: _getStyle(t, size: 14, weight: FontWeight.w700),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded, 
                                  color: t.textTertiary
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              _divider(t),
                              ListTile(
                                onTap: () {
                                  throw StateError(
                                    'Intentional Test Crash — Branch: ${widget.userData['branchId']}, Role: ${widget.userData['role']}',
                                  );
                                },
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.bug_report_outlined, color: Colors.red, size: 20),
                                ),
                                title: Text(
                                  context.tr('simulate_crash'),
                                  style: _getStyle(t, size: 14, weight: FontWeight.w700),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded, 
                                  color: t.textTertiary
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        Center(
                          child: Text(
                            "GMWF System Hub v2.1.3\nDesign & Theming by Antigravity Studio",
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
