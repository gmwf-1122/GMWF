// lib/design/components/app_card.dart
//
// ── AppCard — Unified Card Component ─────────────────────────────────────────
// 3 variants: surface, accent, glass.
// Wraps the existing LuxuryDeco decoration system with token-based values.
//
// Usage:
//   AppCard(child: ...)                                   // surface, r4, shadow2
//   AppCard(variant: .accent, child: ...)                 // tinted accent card
//   AppCard(variant: .glass, child: ...)                  // glassmorphism
//   AppCard(padding: EdgeInsets.all(Gsp.sp6), child: ...) // custom padding
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/radius.dart';
import '../tokens/shadows.dart';

enum AppCardVariant {
  /// White/surface background. Shadow2. Standard content card.
  surface,

  /// Accent-tinted background + accent border + glow shadow. Use for KPI cards.
  accent,

  /// Glassmorphism with backdrop blur and glassTint overlay.
  glass,
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.variant   = AppCardVariant.surface,
    this.padding,
    this.margin,
    this.onTap,
    this.borderRadius,
    this.elevation,
  });

  final Widget child;
  final AppCardVariant variant;

  /// Override padding. Default: EdgeInsets.all(Gsp.cardPad) = 16.
  final EdgeInsetsGeometry? padding;

  /// Optional outer margin.
  final EdgeInsetsGeometry? margin;

  /// Optional tap handler — wraps with InkWell.
  final VoidCallback? onTap;

  /// Override border radius. Default: Gr.card = r4 (16).
  final BorderRadius? borderRadius;

  /// Override shadow level 0–4. null = variant default.
  final int? elevation;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isDark = t.isDarkCanvas;
    final r = borderRadius ?? Gr.card;
    final pad = padding ?? const EdgeInsets.all(Gsp.cardPad);

    Widget body = Padding(padding: pad, child: child);

    switch (variant) {
      case AppCardVariant.surface:
        body = Container(
          decoration: BoxDecoration(
            color: t.bgCard,
            borderRadius: r,
            boxShadow: elevation == 0
                ? GShadow.s0
                : elevation == 1
                    ? GShadow.s1(isDark)
                    : elevation == 3
                        ? GShadow.s3(isDark, t.accent)
                        : GShadow.s2(isDark),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: r,
            child: onTap != null
                ? InkWell(
                    onTap: onTap,
                    borderRadius: r,
                    child: Padding(padding: pad, child: child),
                  )
                : Padding(padding: pad, child: child),
          ),
        );

      case AppCardVariant.accent:
        body = Container(
          decoration: BoxDecoration(
            color: t.accentMuted,
            borderRadius: r,
            border: Border.all(color: t.accent.withValues(alpha: 0.30), width: 1),
            boxShadow: elevation == 0
                ? GShadow.s0
                : GShadow.s3(isDark, t.accent),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: r,
            child: onTap != null
                ? InkWell(
                    onTap: onTap,
                    borderRadius: r,
                    child: Padding(padding: pad, child: child),
                  )
                : Padding(padding: pad, child: child),
          ),
        );

      case AppCardVariant.glass:
        body = ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: t.glassTint,
                borderRadius: r,
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.30),
                  width: 1,
                ),
                boxShadow: elevation == 0
                    ? GShadow.s0
                    : GShadow.s3(isDark, t.accent),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: r,
                child: onTap != null
                    ? InkWell(
                        onTap: onTap,
                        borderRadius: r,
                        child: Padding(padding: pad, child: child),
                      )
                    : Padding(padding: pad, child: child),
              ),
            ),
          ),
        );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: body);
    }
    return body;
  }
}
