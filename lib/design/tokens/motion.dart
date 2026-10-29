// lib/design/tokens/motion.dart
//
// ── GMotion — Durations & Curves ─────────────────────────────────────────────
// Short, calm motion. Use `fast` for hovers/presses, `base` for state changes
// (selected tab, expanding card), `slow` for page-level reveals.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/animation.dart';

class GMotion {
  GMotion._(); // prevent instantiation

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  /// Default easing for most transitions.
  static const Curve standard = Curves.easeOutCubic;

  /// Things entering the screen.
  static const Curve enter = Curves.easeOutQuart;

  /// Things leaving the screen.
  static const Curve exit = Curves.easeInCubic;
}
