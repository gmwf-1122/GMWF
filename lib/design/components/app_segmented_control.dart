// lib/design/components/app_segmented_control.dart
//
// ── AppSegmentedControl — Unified Tab/Filter Switcher ────────────────────────
// Replaces 4+ different custom segmented controls across the app:
//   - donation_boxes_screen.dart → _buildViewSwitcher
//   - overview.dart              → _buildTabSwitcher
//   - donations_shared.dart      → filter tabs
//   - ramadan_welfare_screen.dart→ filter tabs
//
// Usage:
//   AppSegmentedControl(
//     options: ['Box Registry', 'Person Audit'],
//     selected: _tab,
//     onChanged: (v) => setState(() => _tab = v),
//   )
//
//   // With icons:
//   AppSegmentedControl(
//     options: ['Overview', 'Donations', 'Boxes'],
//     icons: [Icons.bar_chart, Icons.volunteer_activism, Icons.inbox],
//     selected: _tab,
//     onChanged: (v) => setState(() => _tab = v),
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/radius.dart';
import '../tokens/typography.dart';

class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.icons,
  });

  /// List of option labels.
  final List<String> options;

  /// Currently selected option (must match one of [options]).
  final String selected;

  final ValueChanged<String> onChanged;

  /// Optional icons — must be same length as [options] if provided.
  final List<IconData?>? icons;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isDark = t.isDarkCanvas;

    return Container(
      padding: const EdgeInsets.all(Gsp.sp1),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : t.bgCardAlt,
        borderRadius: Gr.segment,
        border: Border.all(
          color: t.bgRule,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) {
          final opt = options[i];
          final isSelected = opt == selected;
          final icon = (icons != null && i < icons!.length) ? icons![i] : null;

          return GestureDetector(
            onTap: () => onChanged(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                horizontal: Gsp.sp3,
                vertical: Gsp.sp2,
              ),
              decoration: BoxDecoration(
                color: isSelected ? t.bgCard : Colors.transparent,
                borderRadius: BorderRadius.circular(Gr.r7 - Gsp.sp1),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 14,
                      color: isSelected ? t.accent : t.textTertiary,
                    ),
                    const SizedBox(width: Gsp.sp1),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: GText.label(isSelected ? t.textPrimary : t.textTertiary).copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    child: Text(opt),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
