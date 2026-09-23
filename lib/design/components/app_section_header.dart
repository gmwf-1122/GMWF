// lib/design/components/app_section_header.dart
//
// ── AppSectionHeader — Unified Section Label ──────────────────────────────────
// Replaces 6+ different inline section label implementations and LuxuryDeco.label().
//
// Usage:
//   AppSectionHeader(label: 'DONATION BOXES')
//   AppSectionHeader(label: 'STAFF', icon: Icons.people_rounded)
//   AppSectionHeader(
//     label: 'RECENT ACTIVITY',
//     trailing: TextButton(onPressed: ..., child: Text('See All')),
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import '../tokens/colors.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.label,
    this.icon,
    this.trailing,
    this.bottomPad = true,
  });

  final String label;

  /// Optional leading icon (size: GColor.iconSm = 16).
  final IconData? icon;

  /// Optional trailing widget (e.g. a 'See All' TextButton).
  final Widget? trailing;

  /// If true, adds Gsp.sp3 (12) bottom padding below the header.
  final bool bottomPad;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad ? Gsp.sp3 : 0),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: GColor.iconSm, color: t.textTertiary),
            const SizedBox(width: Gsp.sp2),
          ],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: GText.label(t.textTertiary).copyWith(letterSpacing: 1.0),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
