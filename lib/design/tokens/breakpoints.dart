// lib/design/tokens/breakpoints.dart
//
// ── GBreakpoint ───────────────────────────────────────────────────────────────
// Single source of truth for responsive layout.
// Replaces the 9 different inline isMobile/isTablet/isDesktop thresholds
// scattered across 40+ files in the codebase.
//
// Old patterns to migrate:
//   size.width < 600   → GBreakpoint.isMobile(ctx)
//   size.width < 760   → GBreakpoint.isMobile(ctx)   (gmwf_app_bar)
//   size.width < 850   → GBreakpoint.isCompact(ctx)  (donations_screen)
//   size.width >= 900  → GBreakpoint.isDesktop(ctx)
//   size.width < 1050  → GBreakpoint.isCompact(ctx)  (gmwf_app_bar isCompact)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class GBreakpoint {
  GBreakpoint._(); // prevent instantiation

  // ── Canonical thresholds ──────────────────────────────────────────────────
  /// Width below which layout is treated as mobile (phones in portrait).
  static const double mobile = 600;

  /// Width below which layout is treated as compact / handheld.
  static const double compact = 800;

  /// Width at or above which layout is treated as tablet.
  static const double tablet = 900;

  /// Width at or above which layout is treated as desktop/wide.
  static const double desktop = 1280;

  // ── Safe screen width resolver (never throws even without MediaQuery ancestor) ──
  static double widthOf(BuildContext ctx) {
    try {
      final mq = MediaQuery.maybeOf(ctx);
      if (mq != null) return mq.size.width;
      final s = MediaQuery.maybeSizeOf(ctx);
      if (s != null) return s.width;
    } catch (_) {}
    return 1024.0;
  }

  // ── BuildContext helpers (use in StatelessWidget / build()) ───────────────
  static bool isMobile(BuildContext ctx) => widthOf(ctx) < mobile;

  static bool isTablet(BuildContext ctx) {
    final w = widthOf(ctx);
    return w >= mobile && w < tablet;
  }

  static bool isDesktop(BuildContext ctx) => widthOf(ctx) >= tablet;

  /// True when width < 900 (tablet OR mobile) — use for 2-column vs 1-column
  /// decisions where tablet and mobile share the same compact layout.
  static bool isCompact(BuildContext ctx) => widthOf(ctx) < tablet;

  /// True when width >= 900 — mirror of isDesktop, named for readability.
  static bool isWide(BuildContext ctx) => widthOf(ctx) >= tablet;

  // ── BoxConstraints helpers (use inside LayoutBuilder) ────────────────────
  static bool isMobileC(BoxConstraints c) => c.maxWidth < mobile;
  static bool isTabletC(BoxConstraints c) =>
      c.maxWidth >= mobile && c.maxWidth < tablet;
  static bool isDesktopC(BoxConstraints c) => c.maxWidth >= tablet;
  static bool isCompactC(BoxConstraints c) => c.maxWidth < tablet;

  // ── Adaptive value helper ─────────────────────────────────────────────────
  /// Returns one of three values based on the current screen width.
  ///
  /// Example:
  /// ```dart
  /// Padding(
  ///   padding: EdgeInsets.symmetric(
  ///     horizontal: GBreakpoint.value(context,
  ///       mobile:  16.0,
  ///       tablet:  24.0,
  ///       desktop: 40.0,
  ///     ),
  ///   ),
  /// )
  /// ```
  static T value<T>(
    BuildContext ctx, {
    required T mobile,
    required T tablet,
    required T desktop,
  }) {
    final w = MediaQuery.sizeOf(ctx).width;
    if (w >= GBreakpoint.tablet) return desktop;
    if (w >= GBreakpoint.mobile) return tablet;
    return mobile;
  }

  /// Same as [value] but operates on [BoxConstraints] (for LayoutBuilder).
  static T valueC<T>(
    BoxConstraints c, {
    required T mobile,
    required T tablet,
    required T desktop,
  }) {
    if (c.maxWidth >= GBreakpoint.tablet) return desktop;
    if (c.maxWidth >= GBreakpoint.mobile) return tablet;
    return mobile;
  }

  // ── Grid column counts ────────────────────────────────────────────────────
  /// Standard stat-card grid column count.
  static int gridColumns(BuildContext ctx) => value(ctx,
        mobile: 2, tablet: 3, desktop: 4);

  /// Horizontal screen padding scaled by breakpoint.
  static double screenPadding(BuildContext ctx) => value(ctx,
        mobile: 16.0, tablet: 24.0, desktop: 40.0);
}
