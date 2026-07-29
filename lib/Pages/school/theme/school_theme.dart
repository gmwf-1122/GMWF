// lib/pages/school/theme/school_theme.dart

import 'package:flutter/material.dart';

class SchoolTheme {
  // ── Brand Colors ──────────────────────────────────────────────────────────
  static const Color primary       = Color(0xFF6366F1); // Indigo 500
  static const Color primaryDark   = Color(0xFF4338CA); // Indigo 700
  static const Color primaryLight  = Color(0xFFEEF2FF); // Indigo 50

  static const Color accent        = Color(0xFF10B981); // Emerald 500
  static const Color accentDark    = Color(0xFF059669); // Emerald 600
  static const Color accentLight   = Color(0xFFECFDF5); // Emerald 50

  static const Color sidebarBg     = Color(0xFF0F172A); // Slate 900
  static const Color sidebarBorder = Color(0xFF1E293B); // Slate 800
  static const Color sidebarText   = Color(0xFFCBD5E1); // Slate 300
  static const Color sidebarMuted  = Color(0xFF94A3B8); // Slate 400 (High contrast WCAG AA)

  // ── Documented Status Palette ─────────────────────────────────────────────
  /// Present / Active / Success -> Emerald
  static const Color statusPresent = Color(0xFF10B981);
  static const Color statusPresentBg = Color(0xFFECFDF5);

  /// Absent / Suspended / Error / Dropped -> Red
  static const Color statusAbsent  = Color(0xFFEF4444);
  static const Color statusAbsentBg  = Color(0xFFFEF2F2);

  /// On Leave / Warning / Overdue -> Amber
  static const Color statusLeave   = Color(0xFFF59E0B);
  static const Color statusLeaveBg   = Color(0xFFFFFBEB);

  /// Late / Info / Registered -> Purple / Violet
  static const Color statusLate    = Color(0xFF8B5CF6);
  static const Color statusLateBg    = Color(0xFFF5F3FF);

  /// Graduated / Transferred -> Blue
  static const Color statusGraduated   = Color(0xFF3B82F6);
  static const Color statusGraduatedBg = Color(0xFFEFF6FF);

  // ── Grade Band Visual Colors ──────────────────────────────────────────────
  static Color getGradeColor(String grade) {
    final g = grade.trim().toLowerCase();
    if (g.contains('pre'))  return const Color(0xFF0D9488); // Teal
    if (g.contains('9th') || g == '9')  return const Color(0xFF6366F1); // Indigo
    if (g.contains('10th') || g == '10') return const Color(0xFF2563EB); // Royal Blue
    if (g.contains('nursery') || g.contains('kg')) return const Color(0xFFEC4899); // Pink
    return const Color(0xFF4B5563); // Slate
  }

  // ── Letter Grade Spectrum Scale (A+ down to F) ────────────────────────────
  static Color getLetterGradeColor(String letterGrade) {
    final lg = letterGrade.trim().toUpperCase();
    if (lg == 'A+') return const Color(0xFF10B981); // Emerald
    if (lg == 'A')  return const Color(0xFF059669); // Dark Emerald
    if (lg == 'B')  return const Color(0xFF3B82F6); // Blue
    if (lg == 'C')  return const Color(0xFFF59E0B); // Amber
    if (lg == 'D')  return const Color(0xFFF97316); // Orange
    return const Color(0xFFEF4444); // Red (F)
  }

  // ── Surface & Neutral Light Tokens ─────────────────────────────────────────
  static const Color bgLight        = Color(0xFFF8FAFC); // Slate 50
  static const Color cardLight      = Colors.white;
  static const Color borderLight    = Color(0xFFE2E8F0); // Slate 200
  static const Color textDark       = Color(0xFF0F172A); // Slate 900
  static const Color textMid        = Color(0xFF475569); // Slate 600
  static const Color textMuted      = Color(0xFF64748B); // Slate 500

  // ── Surface & Neutral Dark Tokens ──────────────────────────────────────────
  static const Color bgDark         = Color(0xFF0B0F19);
  static const Color cardDark       = Color(0xFF151D2A);
  static const Color borderDark     = Color(0xFF232E42);
  static const Color textDarkTheme  = Color(0xFFF1F5F9);
  static const Color textMidDark    = Color(0xFF94A3B8);

  // ── Radii Constants ───────────────────────────────────────────────────────
  static const double r8  = 8.0;
  static const double r12 = 12.0;
  static const double r14 = 14.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;

  static BorderRadius radius8  = BorderRadius.circular(r8);
  static BorderRadius radius12 = BorderRadius.circular(r12);
  static BorderRadius radius14 = BorderRadius.circular(r14);
  static BorderRadius radius16 = BorderRadius.circular(r16);
  static BorderRadius radius20 = BorderRadius.circular(r20);

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
