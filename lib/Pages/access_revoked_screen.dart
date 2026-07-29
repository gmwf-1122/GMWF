// lib/pages/access_revoked_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/offline_auth_service.dart';
import 'login_page.dart';

class AccessRevokedScreen extends StatelessWidget {
  final Map<String, dynamic>? userData;
  final String? reason;

  const AccessRevokedScreen({
    super.key,
    this.userData,
    this.reason,
  });

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    await OfflineAuthService.clearCredentials();

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = userData?['name'] ?? userData?['username'] ?? 'User';
    final email = userData?['email'] ?? userData?['username'] ?? '';
    final branch = userData?['branchId'] ?? 'HQ';
    final status = userData?['status']?.toString().toUpperCase() ?? 'INACTIVE';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate theme
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF334155)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Glowing Lock Icon
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(
                    Icons.no_accounts_rounded,
                    color: Color(0xFFEF4444),
                    size: 46,
                  ),
                ),
                const SizedBox(height: 24),

                // Main Title
                const Text(
                  'Access Revoked',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Thank you subtitle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Thank you for your services',
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Revocation Message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your app access has been revoked. Please contact the HQ Manager or the manager of your branch to request app access again.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // User details summary box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow('Account Name', name),
                      if (email.isNotEmpty) ...[
                        const Divider(color: Color(0xFF334155), height: 16),
                        _buildDetailRow('Email / Username', email),
                      ],
                      const Divider(color: Color(0xFF334155), height: 16),
                      _buildDetailRow('Branch', branch),
                      const Divider(color: Color(0xFF334155), height: 16),
                      _buildDetailRow('Account Status', status, isBadge: true),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Logout Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _handleLogout(context),
                    icon: const Icon(Icons.logout_rounded, size: 20),
                    label: const Text(
                      'Back to Login',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBadge = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
        ),
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
            ),
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11, fontWeight: FontWeight.bold),
            ),
          )
        else
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}
