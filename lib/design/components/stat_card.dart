// lib/design/components/stat_card.dart
//
// ── StatCard — Dashboard KPI Card ─────────────────────────────────────────────
// 2 variants: compact (dashboard grid) and hero (summary banner).
//
// Usage:
//   StatCard(
//     label: 'Total Donations',
//     value: 'PKR 1.2M',
//     icon: Icons.volunteer_activism_rounded,
//   )
//   StatCard.hero(
//     label: 'Monthly Revenue',
//     value: 'PKR 245,000',
//     trend: '+12%',
//     trendUp: true,
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/radius.dart';
import '../tokens/shadows.dart';
import '../tokens/typography.dart';
import '../tokens/colors.dart';

// ── Compact StatCard ──────────────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.onTap,
    this.subtitle,
  });

  /// Hero variant — large number + trend, full-width.
  const StatCard.hero({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.onTap,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  /// Optional secondary line (e.g. trend, sub-metric).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isDark = t.isDarkCanvas;
    final resolvedIconColor = iconColor ?? t.accent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Gsp.cardPad),
        decoration: BoxDecoration(
          color: t.bgCard,
          borderRadius: Gr.card,
          boxShadow: GShadow.s2(isDark),
          border: Border.all(color: t.bgRule, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon + label row
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: resolvedIconColor.withValues(alpha: 0.12),
                      borderRadius: Gr.icon,
                    ),
                    child: Icon(icon, size: GColor.iconSm, color: resolvedIconColor),
                  ),
                  const SizedBox(width: Gsp.sp2),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: GText.caption(t.textTertiary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gsp.sp2),
            // Primary value
            Text(
              value,
              style: GText.statLg(t.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Optional subtitle / trend
            if (subtitle != null) ...[
              const SizedBox(height: Gsp.sp1),
              Text(
                subtitle!,
                style: GText.caption(t.textSecondary),
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

// ── Hero StatCard ─────────────────────────────────────────────────────────────

class HeroStatCard extends StatelessWidget {
  const HeroStatCard({
    super.key,
    required this.label,
    required this.value,
    this.trend,
    this.trendUp = true,
    this.icon,
    this.gradient,
    this.onTap,
  });

  final String label;
  final String value;

  /// Optional trend string e.g. '+12%' or '-3%'.
  final String? trend;
  final bool trendUp;
  final IconData? icon;
  final LinearGradient? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isDark = t.isDarkCanvas;
    final resolvedGradient = gradient ?? t.accentGradient;

    final trendColor = trendUp ? GColor.successOf(isDark) : GColor.dangerOf(isDark);
    final trendIcon = trendUp ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Gsp.cardPadL),
        decoration: BoxDecoration(
          gradient: resolvedGradient,
          borderRadius: Gr.card,
          boxShadow: GShadow.s3(isDark, t.accent),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GText.label(Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: Gsp.sp2),
                  Text(value, style: GText.statXl(Colors.white)),
                  if (trend != null) ...[
                    const SizedBox(height: Gsp.sp2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(trendIcon, size: GColor.iconSm, color: trendColor),
                        const SizedBox(width: Gsp.sp1),
                        Text(trend!, style: GText.label(trendColor)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: Gsp.sp4),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: Gr.card,
                ),
                child: Icon(icon, size: GColor.iconXl, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
