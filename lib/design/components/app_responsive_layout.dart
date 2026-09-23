// lib/design/components/app_responsive_layout.dart
//
// ── AppResponsiveLayout — Responsive 3-Slot Layout Builder ───────────────────
// Declarative breakpoint-based layout. Replaces inline isMobile ? x : y chains.
// Uses GBreakpoint canonical thresholds (mobile:600, tablet:900).
//
// Usage:
//   AppResponsiveLayout(
//     mobile:  _buildSingleColumn(),
//     desktop: _buildThreeColumn(),         // optional: falls back to tablet
//     tablet:  _buildTwoColumn(),           // optional: falls back to mobile
//   )
//
//   // Simple value-based adaptive:
//   EdgeInsets.symmetric(
//     horizontal: GBreakpoint.screenPadding(context),
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../tokens/breakpoints.dart';
import '../tokens/spacing.dart';

class AppResponsiveLayout extends StatelessWidget {
  const AppResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  /// Layout used on screens < 600px wide.
  final Widget mobile;

  /// Layout used on screens 600–899px wide.
  /// Falls back to [mobile] if not provided.
  final Widget? tablet;

  /// Layout used on screens >= 900px wide.
  /// Falls back to [tablet] (or [mobile]) if not provided.
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    if (GBreakpoint.isDesktop(context)) {
      return desktop ?? tablet ?? mobile;
    }
    if (GBreakpoint.isTablet(context)) {
      return tablet ?? mobile;
    }
    return mobile;
  }
}

// ── AppResponsivePadding ──────────────────────────────────────────────────────
/// Wraps [child] with horizontal screen padding that adapts to breakpoints.
///
/// Mobile:  Gsp.screenH  = 16
/// Tablet:  Gsp.screenHD = 24
/// Desktop: custom (default 40)
class AppResponsivePadding extends StatelessWidget {
  const AppResponsivePadding({
    super.key,
    required this.child,
    this.desktopHPad = Gsp.sp10,
  });

  final Widget child;

  /// Horizontal padding on desktop. Defaults to 40 (Gsp.sp10).
  final double desktopHPad;

  @override
  Widget build(BuildContext context) {
    final hPad = GBreakpoint.value<double>(
      context,
      mobile: Gsp.screenH,
      tablet: Gsp.screenHD,
      desktop: desktopHPad,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: child,
    );
  }
}

// ── AppResponsiveGrid ─────────────────────────────────────────────────────────
/// A GridView that automatically picks column count based on breakpoint.
class AppResponsiveGrid extends StatelessWidget {
  const AppResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns  = 2,
    this.tabletColumns  = 3,
    this.desktopColumns = 4,
    this.spacing        = Gsp.sectionGap,
    this.childAspectRatio = 1.6,
    this.shrinkWrap     = false,
    this.physics,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double spacing;
  final double childAspectRatio;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final cols = GBreakpoint.value<int>(
      context,
      mobile: mobileColumns,
      tablet: tabletColumns,
      desktop: desktopColumns,
    );

    return GridView.count(
      crossAxisCount: cols,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
      shrinkWrap: shrinkWrap,
      physics: physics,
      children: children,
    );
  }
}
