// lib/design/tokens/shadows.dart
//
// ── GShadow — Elevation / Shadow Scale ───────────────────────────────────────
// 5-step elevation system.
// s0 = none, s1 = hairline, s2 = card rest, s3 = interactive, s4 = modal
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class GShadow {
  GShadow._(); // prevent instantiation

  /// s0 — No shadow. Flat surface (e.g., inner chip, badge).
  static List<BoxShadow> get s0 => const [];

  /// s1 — Hairline lift. Barely-there shadow for subtle separation.
  static List<BoxShadow> s1(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  /// s2 — Card rest state. Standard shadow for resting cards.
  static List<BoxShadow> s2(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
      blurRadius: 6,
      spreadRadius: 0,
      offset: const Offset(0, 2),
    ),
  ];

  /// s3 — Interactive / hover card. Adds accent glow.
  static List<BoxShadow> s3(bool isDark, Color accent) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// s4 — Modal / dialog. Deepest shadow for floating surfaces.
  static List<BoxShadow> s4(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.12),
      blurRadius: 24,
      spreadRadius: 2,
      offset: const Offset(0, 8),
    ),
  ];

  // ── Neumorphic helpers (wraps existing Neumorphic3DStyle logic) ───────────

  /// Raised card shadow — wraps the existing Neumorphic3DStyle.raisedShadows().
  /// This is provided so new components can use GShadow.raised() instead of
  /// calling Neumorphic3DStyle directly, keeping a single import path.
  static List<BoxShadow> raised({
    required bool isDark,
    Color? accent,
    double depth = 1.0,
    bool showGlow = false,
  }) {
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.65),
          blurRadius: (18 * depth).clamp(4.0, 36.0),
          spreadRadius: 1,
          offset: Offset(6 * depth, 8 * depth),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.08),
          blurRadius: (12 * depth).clamp(3.0, 24.0),
          spreadRadius: -1,
          offset: Offset(-4 * depth, -4 * depth),
        ),
        if (showGlow && accent != null)
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
      ];
    } else {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: (18 * depth).clamp(4.0, 36.0),
          spreadRadius: 1,
          offset: Offset(7 * depth, 8 * depth),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.95),
          blurRadius: (14 * depth).clamp(3.0, 28.0),
          spreadRadius: -1,
          offset: Offset(-6 * depth, -6 * depth),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
        if (showGlow && accent != null)
          BoxShadow(
            color: accent.withValues(alpha: 0.20),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
      ];
    }
  }
}
