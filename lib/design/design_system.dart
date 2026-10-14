// lib/design/design_system.dart
//
// ── GMWF Design System — Barrel Export ───────────────────────────────────────
// Single import for the entire design system:
//   import 'package:gmwf/design/design_system.dart';
//
// Provides: Gsp, Gr, GText, GShadow, GColor, GBreakpoint,
//           SoftPalette, GComfortColors (context.comfort),
//           AppButton, AppCard, AppChip, StatusBadge,
//           AppSectionHeader, AppSegmentedControl,
//           StatCard, HeroStatCard,
//           AppEmptyState, AppFeedback, AppToast,
//           AppDivider, AppVerticalDivider,
//           AppResponsiveLayout, AppResponsivePadding, AppResponsiveGrid
//
// ── Colour rules (eye comfort) ───────────────────────────────────────────────
//   • Every colour comes from SoftPalette (tokens/soft_palette.dart): no pure
//     white/black, no neon. test/no_hardcoded_colors_test.dart enforces this.
//   • Prefer semantic colours that follow light/dark automatically:
//       context.comfort.surface / .textPrimary / .border / .danger / .dangerBg …
//   • Need a shade that isn't there? Add it to the palette by regenerating it
//     with tool/soft_palette/ — never add Color(0x…) or Colors.* in a screen.
//   • Notifications: AppFeedback / AppToast (bottom-right, theme-aware, max 3).
// ─────────────────────────────────────────────────────────────────────────────

// ── Tokens ────────────────────────────────────────────────────────────────────
export 'tokens/breakpoints.dart';
export 'tokens/colors.dart';
export 'tokens/comfort_colors.dart';
export 'tokens/soft_palette.dart';
export 'tokens/radius.dart';
export 'tokens/shadows.dart';
export 'tokens/spacing.dart';
export 'tokens/typography.dart';

// ── Components ────────────────────────────────────────────────────────────────
export 'components/app_button.dart';
export 'components/app_card.dart';
export 'components/app_chip.dart';
export 'components/app_divider.dart';
export 'components/app_empty_state.dart';
export 'components/app_feedback.dart';
export 'components/app_toast.dart';
export 'components/decorative_image.dart';
export 'components/app_responsive_layout.dart';
export 'components/app_section_header.dart';
export 'components/app_segmented_control.dart';
export 'components/app_dialog.dart';
export 'components/stat_card.dart';
