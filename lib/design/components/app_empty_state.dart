// lib/design/components/app_empty_state.dart
//
// ── AppEmptyState — Unified Empty State Component ─────────────────────────────
// Replaces 8+ different bespoke empty state patterns across the app.
//
// Usage:
//   AppEmptyState(
//     icon: Icons.inbox_outlined,
//     title: 'No Boxes Found',
//   )
//   AppEmptyState(
//     icon: Icons.search_off_rounded,
//     title: 'Nothing matched',
//     subtitle: 'Try adjusting your filters.',
//     action: AppButton(label: 'Clear Filters', onTap: _clear, variant: .ghost),
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../tokens/colors.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Optional action button (typically an AppButton with ghost or primary variant).
  final Widget? action;

  /// If true, uses smaller padding and icon for use in constrained areas.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final iconSize = compact ? Gsp.sp12 : GColor.iconXxl;
    final vPad = compact ? Gsp.sp6 : Gsp.sp12;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Gsp.sp6, vertical: vPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: iconSize + Gsp.sp6,
              height: iconSize + Gsp.sp6,
              decoration: BoxDecoration(
                color: t.accentMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: t.accent.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: Gsp.sp4),
            Text(
              title,
              style: GText.h3(t.textPrimary),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: Gsp.sp2),
              Text(
                subtitle!,
                style: GText.body2(t.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: Gsp.sp5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
