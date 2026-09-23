// lib/design/tokens/colors.dart
//
// ── GColor — Global Semantic Colors ──────────────────────────────────────────
// Role-theme accent colors live in RoleThemeData (app_theme.dart).
// GColor covers semantic status colors that are global and theme-independent.
//
// Replaces:
//   Colors.green.shade700   → GColor.success / GColor.successOf(isDark)
//   Colors.red.shade700     → GColor.danger  / GColor.dangerOf(isDark)
//   Colors.orange.shade800  → GColor.warning / GColor.warningOf(isDark)
//   Colors.blueAccent       → GColor.info    / GColor.infoOf(isDark)
//   Colors.purpleAccent     → use t.accent from role theme instead
//   Colors.amber.shade400   → GColor.warningOf(isDark)
//   Colors.grey.shade600    → t.textTertiary from role theme instead
//   Color(0xFF10B981)       → GColor.success (teal-emerald green)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class GColor {
  GColor._(); // prevent instantiation

  // ── Success — green ───────────────────────────────────────────────────────
  static const Color success    = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF22C55E);
  static const Color successBg   = Color(0xFFDCFCE7);
  static const Color successBgDark = Color(0xFF14532D);

  // ── Info — blue ───────────────────────────────────────────────────────────
  static const Color info       = Color(0xFF2563EB);
  static const Color infoDark   = Color(0xFF3B82F6);
  static const Color infoBg     = Color(0xFFEFF6FF);
  static const Color infoBgDark = Color(0xFF1E3A5F);

  // ── Warning — amber ───────────────────────────────────────────────────────
  static const Color warning      = Color(0xFFD97706);
  static const Color warningDark  = Color(0xFFFBBF24);
  static const Color warningBg    = Color(0xFFFFF7ED);
  static const Color warningBgDark = Color(0xFF4A2800);

  // ── Danger — red ──────────────────────────────────────────────────────────
  static const Color danger     = Color(0xFFDC2626);
  static const Color dangerDark = Color(0xFFEF4444);
  static const Color dangerBg   = Color(0xFFFEF2F2);
  static const Color dangerBgDark = Color(0xFF4C0519);

  // ── Neutral — grey ────────────────────────────────────────────────────────
  static const Color neutral     = Color(0xFF6B7280);
  static const Color neutralDark = Color(0xFF9CA3AF);
  static const Color neutralBg   = Color(0xFFF9FAFB);
  static const Color neutralBgDark = Color(0xFF374151);

  // ── Theme-aware helpers ───────────────────────────────────────────────────
  /// Returns the correct success color based on the current canvas darkness.
  static Color successOf(bool isDark) => isDark ? successDark : success;
  static Color successBgOf(bool isDark) => isDark ? successBgDark : successBg;

  static Color infoOf(bool isDark)    => isDark ? infoDark    : info;
  static Color infoBgOf(bool isDark)  => isDark ? infoBgDark  : infoBg;

  static Color warningOf(bool isDark) => isDark ? warningDark : warning;
  static Color warningBgOf(bool isDark) => isDark ? warningBgDark : warningBg;

  static Color dangerOf(bool isDark)  => isDark ? dangerDark  : danger;
  static Color dangerBgOf(bool isDark) => isDark ? dangerBgDark : dangerBg;

  static Color neutralOf(bool isDark) => isDark ? neutralDark : neutral;
  static Color neutralBgOf(bool isDark) => isDark ? neutralBgDark : neutralBg;

  // ── Icon size constants (standardised) ───────────────────────────────────
  // These aren't colors but live here as a convenience reference.
  // Actual usage: Icon(icon, size: GColor.iconSm)
  static const double iconXs  = 12; // badge / chip icon
  static const double iconSm  = 16; // button icon
  static const double iconMd  = 20; // list / card leading, app bar
  static const double iconLg  = 24; // section header icon
  static const double iconXl  = 32; // feature / hero icon
  static const double iconXxl = 48; // empty state illustration icon
}
