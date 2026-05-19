// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';

class SettingsPage extends StatelessWidget {
  final Map<String, dynamic> userData;

  const SettingsPage({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final userName = userData['name'] ?? userData['username'] ?? 'User';
    final email = userData['email'] ?? 'No email set';
    final role = (userData['role'] as String? ?? 'staff').toUpperCase();
    final branch = userData['branchName'] ?? 'All Branches';

    return RolePageScaffold(
      title: "Settings",
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(t, "ACCOUNT PROFILE"),
            RoleCard(
              child: Column(
                children: [
                  _profileItem(t, Icons.person_outline_rounded, "Name", userName),
                  _divider(t),
                  _profileItem(t, Icons.alternate_email_rounded, "Email", email),
                  _divider(t),
                  _profileItem(t, Icons.badge_outlined, "Role", role),
                  _divider(t),
                  _profileItem(t, Icons.location_on_outlined, "Branch", branch),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _sectionLabel(t, "SECURITY"),
            RoleCard(
              child: ListTile(
                onTap: () => _showChangePasswordDialog(context, t),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.lock_outline_rounded, color: t.accent, size: 20),
                ),
                title: Text(
                  "Change Password",
                  style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(
                  "Update your account credentials",
                  style: TextStyle(color: t.textTertiary, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: t.textTertiary),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 32),
            _sectionLabel(t, "APPLICATION"),
            RoleCard(
              child: Column(
                children: [
                  _infoItem(t, "App Version", "2.1.0 (Modular)"),
                  _divider(t),
                  _infoItem(t, "Build Type", "Production Release"),
                  _divider(t),
                  _infoItem(t, "Last Sync", DateFormat('MMM dd, hh:mm a').format(DateTime.now())),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _sectionLabel(t, "DEVELOPER DIAGNOSTICS"),
            RoleCard(
              child: Column(
                children: [
                  ListTile(
                    onTap: () async {
                      await Sentry.captureMessage(
                        'Manual Test: Sentry is working for ${userData['role']} at ${userData['branchId']}',
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
                      "Test Crash Reporting",
                      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: Text(
                      "Sends a test event to your Sentry dashboard",
                      style: TextStyle(color: t.textTertiary, fontSize: 12),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: t.textTertiary),
                    contentPadding: EdgeInsets.zero,
                  ),
                  _divider(t),
                  ListTile(
                    onTap: () {
                      throw StateError(
                        'Intentional Test Crash — Branch: ${userData['branchId']}, Role: ${userData['role']}',
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
                      "Simulate a Crash",
                      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: Text(
                      "Throws an intentional error to verify Sentry captures it",
                      style: TextStyle(color: t.textTertiary, fontSize: 12),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: t.textTertiary),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            Center(
              child: Text(
                "GMWF Modular Dashboard v2.1\nDesign by Antigravity Studio",
                textAlign: TextAlign.center,
                style: TextStyle(color: t.textTertiary, fontSize: 11, fontWeight: FontWeight.w500, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(RoleThemeData t, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label,
        style: TextStyle(color: t.textTertiary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
      ),
    );
  }

  Widget _profileItem(RoleThemeData t, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: t.textSecondary, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: t.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoItem(RoleThemeData t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
          Text(value, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _divider(RoleThemeData t) {
    return Divider(color: t.bgRule, height: 24);
  }

  void _showChangePasswordDialog(BuildContext context, RoleThemeData t) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: t.accent),
            const SizedBox(width: 12),
            Text("Update Password", style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              decoration: roleInputDecoration(context, label: "Current Password", icon: Icons.lock_open_rounded),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: roleInputDecoration(context, label: "New Password", icon: Icons.lock_outline_rounded),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: roleInputDecoration(context, label: "Confirm Password", icon: Icons.verified_user_outlined),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("CANCEL", style: TextStyle(color: t.textTertiary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("UPDATE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
