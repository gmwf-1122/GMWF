// lib/pages/support_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return RolePageScaffold(
      title: "Support & Help",
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAboutCard(t),
            const SizedBox(height: 32),
            _sectionLabel(t, "CONTACT SUPPORT"),
            RoleCard(
              child: Column(
                children: [
                  _supportAction(
                    t,
                    Icons.chat_bubble_outline_rounded,
                    "WhatsApp Support",
                    "+92 300 1234567",
                    Colors.green,
                    () => _launchURL("https://wa.me/923001234567"),
                  ),
                  _divider(t),
                  _supportAction(
                    t,
                    Icons.alternate_email_rounded,
                    "Email Support",
                    "support@gmwf.org",
                    Colors.blue,
                    () => _launchURL("mailto:support@gmwf.org"),
                  ),
                  _divider(t),
                  _supportAction(
                    t,
                    Icons.public_rounded,
                    "Official Website",
                    "www.gmwf.org",
                    t.accent,
                    () => _launchURL("https://www.gmwf.org"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _sectionLabel(t, "HELPFUL RESOURCES"),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.4,
              children: [
                _resourceCard(t, Icons.menu_book_rounded, "Manual", "How to use"),
                _resourceCard(t, Icons.videocam_outlined, "Videos", "Tutorials"),
                _resourceCard(t, Icons.bug_report_outlined, "Report", "Found a bug?"),
                _resourceCard(t, Icons.info_outline_rounded, "Privacy", "Data policy"),
              ],
            ),
            const SizedBox(height: 48),
            Center(
              child: Column(
                children: [
                  Opacity(
                    opacity: 0.5,
                    child: Image.asset("assets/logo/gmwf.png", height: 40, errorBuilder: (_, __, ___) => const Icon(Icons.favorite, color: Colors.red, size: 30)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Working for Humanity\nBuilding a Better Tomorrow",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textTertiary, fontSize: 13, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.accent, t.accentLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: t.accent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volunteer_activism_rounded, color: Colors.white, size: 40),
          const SizedBox(height: 16),
          const Text(
            "About GMWF",
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            "Ghulam Muhammad Welfare Foundation (GMWF) is dedicated to providing free medical assistance and social welfare services to those in need.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
          ),
        ],
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

  Widget _supportAction(RoleThemeData t, IconData icon, String label, String value, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      subtitle: Text(value, style: TextStyle(color: t.textTertiary, fontSize: 13)),
      trailing: Icon(Icons.open_in_new_rounded, color: t.textTertiary, size: 18),
    );
  }

  Widget _resourceCard(RoleThemeData t, IconData icon, String label, String sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.bgRule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: t.accent, size: 24),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
          Text(sub, style: TextStyle(color: t.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _divider(RoleThemeData t) {
    return Divider(color: t.bgRule, height: 1);
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
