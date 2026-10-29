// lib/design/tokens/shadows.dart
//
// ── GShadow — Elevation / Shadow Scale (Design System v2) ────────────────────
// Clean, layered shadows: a tight contact shadow plus a soft ambient one, both
// tinted with the cool slate ink so they sit naturally on the slate canvas.
// Surfaces are separated mainly by a 1px border; shadows only hint at depth.
//
//   s0  none          inner chip, badge, flat panel
//   s1  hairline      resting card, list group
//   s2  card          raised card, sticky header
//   s3  interactive   hovered / selected card (optional accent glow)
//   s4  overlay       dialog, menu, toast
//
// The old neumorphic dual shadows (light highlight top-left) are gone:
// raised() keeps its signature for existing callers but returns s2/s3.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';

class GShadow {
  GShadow._(); // prevent instantiation

  static const Color _ink = SoftPalette.slate900;

  static BoxShadow _layer(bool isDark, double light, double dark, double blur, double y, [double spread = 0]) =>
      BoxShadow(
        color: _ink.withValues(alpha: isDark ? dark : light),
        blurRadius: blur,
        spreadRadius: spread,
        offset: Offset(0, y),
      );

  /// s0 — No shadow. Flat surface (e.g., inner chip, badge).
  static List<BoxShadow> get s0 => const [];

  /// s1 — Hairline lift. Resting cards on the canvas.
  static List<BoxShadow> s1(bool isDark) => [
        _layer(isDark, 0.04, 0.30, 2, 1),
      ];

  /// s2 — Raised card. Contact shadow + soft ambient.
  static List<BoxShadow> s2(bool isDark) => [
        _layer(isDark, 0.04, 0.30, 2, 1),
        _layer(isDark, 0.05, 0.28, 12, 4, -2),
      ];

  /// s3 — Interactive / hover / selected card, with a faint accent glow.
  static List<BoxShadow> s3(bool isDark, Color accent) => [
        _layer(isDark, 0.05, 0.32, 4, 2),
        _layer(isDark, 0.08, 0.34, 24, 10, -4),
        BoxShadow(
          color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
          blurRadius: 20,
          spreadRadius: -6,
          offset: const Offset(0, 8),
        ),
      ];

  /// s4 — Overlay: dialog, menu, toast. Deepest shadow.
  static List<BoxShadow> s4(bool isDark) => [
        _layer(isDark, 0.06, 0.36, 6, 2),
        _layer(isDark, 0.14, 0.50, 48, 20, -8),
      ];

  // ── Legacy raised helper ──────────────────────────────────────────────────

  /// Raised surface shadow. Kept for callers of the old neumorphic API
  /// (Neumorphic3DStyle, RoleCard): depth ≥ 1.5 or [showGlow] lifts to s3.
  static List<BoxShadow> raised({
    required bool isDark,
    Color? accent,
    double depth = 1.0,
    bool showGlow = false,
  }) {
    if (showGlow && accent != null) return s3(isDark, accent);
    if (depth <= 0) return s0;
    if (depth < 0.75) return s1(isDark);
    return s2(isDark);
  }
}
