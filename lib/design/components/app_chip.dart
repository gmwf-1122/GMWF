// lib/design/components/app_chip.dart
//
// ── AppChip / StatusBadge — Semantic Status Chip ─────────────────────────────
// 6 semantic states + custom color variant.
// Full pill shape. Small, used inline or in table cells.
//
// Usage:
//   AppChip(label: 'Active', state: AppChipState.active)
//   AppChip(label: 'Overdue', state: AppChipState.overdue, icon: Icons.warning_rounded)
//   AppChip(label: 'Custom', color: Colors.purple)     // custom color
//   AppChip.dot(label: 'Online')                        // dot prefix variant
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/radius.dart';
import '../tokens/typography.dart';
import '../tokens/colors.dart';

enum AppChipState {
  active,
  inactive,
  overdue,
  danger,
  warning,
  info,
  neutral,
  custom,
}

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.state = AppChipState.neutral,
    this.icon,
    this.color,
    this.onTap,
  });

  /// Dot-prefix variant — shows a colored circle before the label.
  const AppChip.dot({
    super.key,
    required this.label,
    this.state = AppChipState.active,
    this.color,
    this.onTap,
  }) : icon = null;

  final String label;
  final AppChipState state;
  final IconData? icon;

  /// Used when state == AppChipState.custom.
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final (fg, bg) = _resolveColors(t);

    Widget chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gsp.sp2,
        vertical: Gsp.sp1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Gr.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: GColor.iconXs, color: fg),
            const SizedBox(width: Gsp.sp1),
          ],
          Text(label, style: GText.micro(fg)),
        ],
      ),
    );

    if (onTap != null) {
      chip = GestureDetector(onTap: onTap, child: chip);
    }

    return chip;
  }

  (Color fg, Color bg) _resolveColors(RoleThemeData t) {
    final isDark = t.isDarkCanvas;
    return switch (state) {
      AppChipState.active   => (GColor.successOf(isDark), GColor.successBgOf(isDark)),
      AppChipState.inactive => (GColor.neutralOf(isDark), GColor.neutralBgOf(isDark)),
      AppChipState.overdue  => (GColor.warningOf(isDark), GColor.warningBgOf(isDark)),
      AppChipState.danger   => (GColor.dangerOf(isDark),  GColor.dangerBgOf(isDark)),
      AppChipState.warning  => (GColor.warningOf(isDark), GColor.warningBgOf(isDark)),
      AppChipState.info     => (GColor.infoOf(isDark),    GColor.infoBgOf(isDark)),
      AppChipState.neutral  => (GColor.neutralOf(isDark), GColor.neutralBgOf(isDark)),
      AppChipState.custom   => (
          color ?? t.accent,
          (color ?? t.accent).withValues(alpha: 0.15),
        ),
    };
  }
}

// ── StatusBadge ───────────────────────────────────────────────────────────────
// Even smaller — just a colored dot + text. Used in data tables.

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Gsp.sp1),
        Text(label, style: GText.caption(color)),
      ],
    );
  }
}
