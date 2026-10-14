// lib/design/components/app_feedback.dart
//
// ── AppFeedback — Unified Notification / Toast ────────────────────────────────
// Thin semantic API over the app-wide toast system (app_toast.dart): toasts
// appear bottom-right on desktop (top on phones), stack up to 3, auto-close,
// and have a ✕ close button.
//
// Usage:
//   AppFeedback.success(context, 'Changes saved successfully');
//   AppFeedback.error(context, 'Failed to connect — check network');
//   AppFeedback.warning(context, 'Box payment is overdue');
//   AppFeedback.info(context, 'Syncing data in the background...');
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import 'app_toast.dart';

class AppFeedback {
  AppFeedback._(); // static-only

  // ── Success ───────────────────────────────────────────────────────────────
  static Future<void> success(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(GToastKind.success, title ?? message, title != null ? message : null, duration);

  // ── Error ─────────────────────────────────────────────────────────────────
  static Future<void> error(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) =>
      _show(GToastKind.error, title ?? message, title != null ? message : null, duration);

  // ── Warning ───────────────────────────────────────────────────────────────
  static Future<void> warning(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(GToastKind.warning, title ?? message, title != null ? message : null, duration);

  // ── Info ──────────────────────────────────────────────────────────────────
  static Future<void> info(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(GToastKind.info, title ?? message, title != null ? message : null, duration);

  // ── Backward-compatible aliases (message = headline, subtitle = detail) ────
  static Future<void> showSuccess(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      _show(GToastKind.success, message, subtitle, duration, actionLabel: actionLabel, onAction: onAction);

  static Future<void> showWarning(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 4000),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      _show(GToastKind.warning, message, subtitle, duration, actionLabel: actionLabel, onAction: onAction);

  static Future<void> showError(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 4500),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      _show(GToastKind.error, message, subtitle, duration, actionLabel: actionLabel, onAction: onAction);

  static Future<void> showInfo(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onAction,
    String? actionLabel,
  }) =>
      _show(GToastKind.info, message, subtitle, duration, actionLabel: actionLabel, onAction: onAction);

  // ── Role-accent (for generic confirmations) ───────────────────────────────
  static Future<void> accent(
    BuildContext context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    final t = RoleThemeScope.dataOf(context);
    return AppToast.show(
      title: title ?? message,
      message: title != null ? message : null,
      icon: Icons.notifications_rounded,
      accent: t.accent,
      duration: duration,
    );
  }

  // ── Core ──────────────────────────────────────────────────────────────────
  static Future<void> _show(
    GToastKind kind,
    String headline,
    String? detail,
    Duration duration, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final hasDetail = detail != null && detail.trim().isNotEmpty;
    return AppToast.show(
      kind: kind,
      title: hasDetail ? headline : null,
      message: hasDetail ? detail : headline,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}
