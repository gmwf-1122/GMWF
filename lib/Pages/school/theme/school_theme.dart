// lib/pages/school/theme/school_theme.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import '../../../theme/role_theme_provider.dart';

class SchoolTheme {
  // ── Brand Colors (Deep Ocean Academic) ──────────────────────────────────
  static const Color primary       = SoftPalette.sky700; // Deep Ocean Teal
  static const Color primaryDark   = SoftPalette.slate800; // Navy Dark
  static const Color primaryLight  = SoftPalette.slate150; // Pale Ocean Wash

  static const Color accent        = SoftPalette.teal500; // Sage Teal
  static const Color accentDark    = SoftPalette.teal550; // Deep Sage
  static const Color accentLight   = SoftPalette.teal100m; // Mint Wash

  static const Color secondary     = SoftPalette.blue600; // Muted Navy-Blue
  static const Color secondaryLight = SoftPalette.slate100; // Pale Steel

  static const Color sidebarBg     = SoftPalette.slate900; // Deep Navy
  static const Color sidebarBorder = SoftPalette.slate750; // Navy Mid
  static const Color sidebarText   = SoftPalette.slate200; // Slate Cloud
  static const Color sidebarMuted  = SoftPalette.slate400; // Muted Ocean

  // ── Status Palette ─────────────────────────────────────────────────────
  /// Present / Active / Success -> Sage Teal
  static const Color statusPresent = SoftPalette.teal500;
  static const Color statusPresentBg = SoftPalette.teal100m;

  /// Absent / Error -> Warm Coral Red
  static const Color statusAbsent  = SoftPalette.red500;
  static const Color statusAbsentBg  = SoftPalette.red100t;

  /// On Leave / Warning -> Warm Amber
  static const Color statusLeave   = SoftPalette.amber350;
  static const Color statusLeaveBg   = SoftPalette.yellow50m;

  /// Late / Info -> Soft Violet
  static const Color statusLate    = SoftPalette.violet500;
  static const Color statusLateBg    = SoftPalette.violet100t;

  /// Graduated / Transferred -> Academic Blue
  static const Color statusGraduated   = SoftPalette.blue500;
  static const Color statusGraduatedBg = SoftPalette.slate100;

  // ── Grade Band Visual Colors ──────────────────────────────────────────
  static Color getGradeColor(String grade) {
    final g = grade.trim().toLowerCase();
    if (g.contains('pre'))  return SoftPalette.teal500; // Sage Teal
    if (g.contains('9th') || g == '9')  return SoftPalette.sky700; // Deep Ocean
    if (g.contains('10th') || g == '10') return SoftPalette.blue500; // Academic Blue
    if (g.contains('nursery') || g.contains('kg')) return SoftPalette.pink400; // Dusty Rose
    return SoftPalette.blue600; // Muted Navy
  }

  // ── Letter Grade Spectrum Scale (A+ down to F) ────────────────────────
  static Color getLetterGradeColor(String letterGrade) {
    final lg = letterGrade.trim().toUpperCase();
    if (lg == 'A+') return SoftPalette.teal500; // Sage Teal
    if (lg == 'A')  return SoftPalette.teal550; // Deep Sage
    if (lg == 'B')  return SoftPalette.blue500; // Academic Blue
    if (lg == 'C')  return SoftPalette.amber350; // Warm Amber
    if (lg == 'D')  return SoftPalette.orange400; // Orange
    return SoftPalette.red500; // Warm Red (F)
  }

  // ── Surface & Neutral Light Tokens ─────────────────────────────────────
  static const Color bgLight        = SoftPalette.gray50; // Cool Off-white
  static const Color cardLight      = SoftPalette.gray50;
  static const Color borderLight    = SoftPalette.slate200; // Soft Slate
  static const Color textDark       = SoftPalette.slate900; // Deep Navy
  static const Color textMid        = SoftPalette.blue600; // Muted Navy-Blue
  static const Color textMuted      = SoftPalette.sky400m; // Soft Steel-Blue

  // ── Surface & Neutral Dark Tokens ──────────────────────────────────────
  static const Color bgDark         = SoftPalette.slate900;
  static const Color cardDark       = SoftPalette.slate800;
  static const Color borderDark     = SoftPalette.slate750;
  static const Color textDarkTheme  = SoftPalette.slate100;
  static const Color textMidDark    = SoftPalette.slate350;

  // ── Radii Constants ───────────────────────────────────────────────────
  static const double r8  = 8.0;
  static const double r12 = 12.0;
  static const double r14 = 14.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;

  static BorderRadius radius8  = BorderRadius.circular(r8);
  static BorderRadius radius12 = BorderRadius.circular(r12);
  static BorderRadius radius14 = BorderRadius.circular(r14);
  static BorderRadius radius16 = BorderRadius.circular(r16);
  static BorderRadius radius20 = BorderRadius.circular(r20);
  static BorderRadius radius24 = BorderRadius.circular(r24);

  // ── Card Shadows ──────────────────────────────────────────────────────
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: SoftPalette.slate900.withValues(alpha: 0.06),
      blurRadius: 18,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: SoftPalette.sky700.withValues(alpha: 0.03),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];


  // ── Typography Scale ──────────────────────────────────────────────────────
  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: textDark,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textMid,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.normal,
    color: textDark,
  );

  static const TextStyle captionStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: textMuted,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.1,
    color: textMuted,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable School UI Components (Themed with original app design system)
// ─────────────────────────────────────────────────────────────────────────────

/// Status badge with soft background and subtle border.
class SchoolBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? backgroundColor;
  final IconData? icon;
  final double fontSize;

  const SchoolBadge({
    super.key,
    required this.label,
    required this.color,
    this.backgroundColor,
    this.icon,
    this.fontSize = 11.5,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? color.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 1, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat Card aligned with the app design system and RoleThemeData.
class SchoolMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final Color? bgColor;
  final VoidCallback? onTap;

  const SchoolMetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.accentColor = SchoolTheme.primary,
    this.bgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor ?? t.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.bgRule),
          boxShadow: [
            BoxShadow(
              color: SoftPalette.gray900.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: t.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: accentColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
                letterSpacing: -0.4,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: t.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Access Restricted / Data Isolation view shown when a user (e.g. teacher) attempts
/// to access restricted modules like fee management or audit trails.
class SchoolAccessDenied extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onBack;

  const SchoolAccessDenied({
    super.key,
    this.title = 'Access Restricted / رسائی ممنوع',
    this.message = 'This school module is restricted to School Administration and Principal. Contact system administration if you require access.',
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: t.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.bgRule),
          boxShadow: [
            BoxShadow(
              color: SoftPalette.gray900.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: SoftPalette.red400.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, size: 36, color: SoftPalette.red400),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: t.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onBack ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Return Back', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: SoftPalette.gray50,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
