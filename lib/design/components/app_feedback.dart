// lib/design/components/app_feedback.dart
//
// ── AppFeedback — Unified Notification / Toast ────────────────────────────────
// Replaces raw Flushbar calls with inconsistent Colors.green.shade700,
// Colors.red.shade700, Colors.orange.shade800 etc.
// Uses another_flushbar (already in pubspec) under the hood.
//
// Usage:
//   AppFeedback.success(context, 'Changes saved successfully');
//   AppFeedback.error(context, 'Failed to connect — check network');
//   AppFeedback.warning(context, 'Box payment is overdue');
//   AppFeedback.info(context, 'Syncing data in the background...');
// ─────────────────────────────────────────────────────────────────────────────

import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';
import '../tokens/radius.dart';
import '../tokens/typography.dart';
import '../tokens/colors.dart';

class AppFeedback {
  AppFeedback._(); // static-only

  // ── Success ───────────────────────────────────────────────────────────────
  static Future<void> success(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(
        context: context,
        message: message,
        title: title,
        icon: Icons.check_circle_rounded,
        color: GColor.success,
        duration: duration,
      );

  // ── Error ─────────────────────────────────────────────────────────────────
  static Future<void> error(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) =>
      _show(
        context: context,
        message: message,
        title: title,
        icon: Icons.error_rounded,
        color: GColor.danger,
        duration: duration,
      );

  // ── Warning ───────────────────────────────────────────────────────────────
  static Future<void> warning(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(
        context: context,
        message: message,
        title: title,
        icon: Icons.warning_rounded,
        color: GColor.warning,
        duration: duration,
      );

  // ── Info ──────────────────────────────────────────────────────────────────
  static Future<void> info(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(
        context: context,
        message: message,
        title: title,
        icon: Icons.info_rounded,
        color: GColor.info,
        duration: duration,
      );

  // ── Backward-compatible aliases ───────────────────────────────────────────
  static Future<void> showSuccess(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      success(context, message, title: subtitle, duration: duration);

  static Future<void> showWarning(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 4000),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      warning(context, message, title: subtitle, duration: duration);

  static Future<void> showError(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 4500),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      error(context, message, title: subtitle, duration: duration);

  static Future<void> showInfo(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      info(context, message, title: subtitle, duration: duration);

  // ── Role-accent (for generic confirmations) ───────────────────────────────
  static Future<void> accent(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    final t = RoleThemeScope.dataOf(context);
    return _show(
      context: context,
      message: message,
      title: title,
      icon: Icons.notifications_rounded,
      color: t.accent,
      duration: duration,
    );
  }

  // ── Core builder ──────────────────────────────────────────────────────────
  static Future<void> _show({
    required BuildContext context,
    required String message,
    required IconData icon,
    required Color color,
    String? title,
    required Duration duration,
  }) {
    final isDark = RoleThemeScope.dataOf(context).isDarkCanvas;
    final bg = isDark
        ? Color.lerp(Colors.black87, color, 0.15)!
        : Color.lerp(Colors.white, color, 0.08)!;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.6);

    return Flushbar(
      titleText: title != null
          ? Text(title, style: GText.body1Bold(textColor))
          : null,
      messageText: Text(message, style: GText.body2(subtextColor)),
      icon: Icon(icon, color: color, size: GColor.iconMd),
      leftBarIndicatorColor: color,
      backgroundColor: bg,
      borderRadius: Gr.card,
      margin: const EdgeInsets.all(Gsp.sp4),
      padding: EdgeInsets.symmetric(
        horizontal: Gsp.sp4,
        vertical: title != null ? Gsp.sp3 : Gsp.sp4,
      ),
      duration: duration,
      flushbarPosition: FlushbarPosition.TOP,
      animationDuration: const Duration(milliseconds: 300),
      forwardAnimationCurve: Curves.easeOut,
      reverseAnimationCurve: Curves.easeIn,
    ).show(context);
  }
}
