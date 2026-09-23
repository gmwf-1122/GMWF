// lib/design/components/app_button.dart
//
// ── AppButton — Unified Button Component ─────────────────────────────────────
// 4 variants × 3 sizes × loading state.
// Replaces all raw ElevatedButton.styleFrom() / OutlinedButton.styleFrom() calls.
//
// Usage:
//   AppButton(label: 'Save', onTap: _save)                              // primary md
//   AppButton(label: 'Cancel', onTap: _back, variant: .secondary)       // secondary md
//   AppButton(label: 'Delete', onTap: _del, variant: .danger, size: .sm)
//   AppButton(label: 'Export', icon: Icons.download_rounded, loading: _busy, onTap: _export)
//   AppButton.icon(icon: Icons.add, onTap: _add)                        // icon-only
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/radius.dart';
import '../tokens/typography.dart';
import '../tokens/colors.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum AppButtonVariant {
  /// Filled background with role accent color. Default.
  primary,

  /// Transparent background, accent-colored border and text.
  secondary,

  /// Transparent background, accent-colored text only. No border.
  ghost,

  /// Filled background with GColor.danger (red). For destructive actions.
  danger,
}

enum AppButtonSize {
  /// h:32, hPad:12, font:12
  sm,

  /// h:40, hPad:16, font:13. Default.
  md,

  /// h:48, hPad:24, font:14
  lg,
}

// ── Widget ────────────────────────────────────────────────────────────────────

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant  = AppButtonVariant.primary,
    this.size     = AppButtonSize.md,
    this.icon,
    this.loading  = false,
    this.disabled = false,
    this.expand   = false,
  });

  /// Icon-only button (no label). Use [label] for accessibility tooltip.
  const AppButton.icon({
    super.key,
    required this.icon,
    required this.onTap,
    this.label    = '',
    this.variant  = AppButtonVariant.ghost,
    this.size     = AppButtonSize.md,
    this.loading  = false,
    this.disabled = false,
    this.expand   = false,
  });

  final String label;
  final VoidCallback? onTap;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool disabled;

  /// If true, button expands to fill available width.
  final bool expand;

  // ── Size metrics ──────────────────────────────────────────────────────────

  double get _height => switch (size) {
    AppButtonSize.sm => 32,
    AppButtonSize.md => 40,
    AppButtonSize.lg => 48,
  };

  double get _hPad => switch (size) {
    AppButtonSize.sm => Gsp.sp3,
    AppButtonSize.md => Gsp.sp4,
    AppButtonSize.lg => Gsp.sp6,
  };

  double get _iconSize => switch (size) {
    AppButtonSize.sm => 14,
    AppButtonSize.md => 16,
    AppButtonSize.lg => 18,
  };

  TextStyle _textStyle(Color color) => switch (size) {
    AppButtonSize.sm => GText.buttonSm(color),
    AppButtonSize.md => GText.buttonMd(color),
    AppButtonSize.lg => GText.buttonLg(color),
  };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isDark = t.isDarkCanvas;
    final isDisabled = disabled || loading;

    // Resolve colors by variant
    final (bgColor, fgColor, borderColor) = _resolveColors(t, isDark, isDisabled);

    Widget child;
    if (loading) {
      child = SizedBox(
        width: _iconSize,
        height: _iconSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(fgColor),
        ),
      );
    } else if (label.isEmpty && icon != null) {
      // Icon-only
      child = Icon(icon, size: _iconSize + 2, color: fgColor);
    } else {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: _iconSize, color: fgColor),
            SizedBox(width: Gsp.sp2),
          ],
          Text(label, style: _textStyle(fgColor)),
        ],
      );
    }

    final btn = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: _height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: Gr.button,
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1.5)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: Gr.button,
        child: InkWell(
          onTap: isDisabled ? null : onTap,
          borderRadius: Gr.button,
          splashColor: fgColor.withValues(alpha: 0.12),
          highlightColor: fgColor.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _hPad),
            child: Center(child: child),
          ),
        ),
      ),
    );

    if (expand) return SizedBox(width: double.infinity, child: btn);
    return btn;
  }

  // ── Color resolution ──────────────────────────────────────────────────────

  (Color bg, Color fg, Color? border) _resolveColors(
    RoleThemeData t,
    bool isDark,
    bool isDisabled,
  ) {
    if (isDisabled) {
      return (
        GColor.neutralOf(isDark).withValues(alpha: 0.15),
        GColor.neutralOf(isDark).withValues(alpha: 0.5),
        null,
      );
    }

    return switch (variant) {
      AppButtonVariant.primary => (
        t.accent,
        Colors.white,
        null,
      ),
      AppButtonVariant.secondary => (
        Colors.transparent,
        t.accent,
        t.accent,
      ),
      AppButtonVariant.ghost => (
        Colors.transparent,
        t.accent,
        null,
      ),
      AppButtonVariant.danger => (
        GColor.dangerOf(isDark),
        Colors.white,
        null,
      ),
    };
  }
}
