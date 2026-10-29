import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:google_fonts/google_fonts.dart';
import '../design/components/app_toast.dart';

/// Standardized, premium UI/UX feedback system used across all departments and modules
/// (Dispensary, Madrassa, Dasterkhwaan, School, Office, Donations).
///
/// Eliminates silent saves and inconsistent alerts with unified typography,
/// micro-icons, role/state-appropriate colors, and floating micro-animations.
class AppFeedback {
  AppFeedback._();

  /// 🟢 Success Toast / Snackbar
  /// Used when data is successfully saved locally, queued, or synchronized.
  static void showSuccess(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    _showSnackBar(
      context,
      message: message,
      subtitle: subtitle ?? 'Saved locally • Syncing to cloud',
      backgroundColor: SoftPalette.emerald600, // Deep emerald
      borderColor: SoftPalette.emerald350,
      icon: Icons.check_circle_rounded,
      iconColor: SoftPalette.emerald300,
      duration: duration,
      onAction: onAction,
      actionLabel: actionLabel,
    );
  }

  /// 🟠 Warning / Offline Toast
  /// Used for offline fallback saves, low stock, backdated entries, or pending review alerts.
  static void showWarning(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 4000),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    _showSnackBar(
      context,
      message: message,
      subtitle: subtitle,
      backgroundColor: SoftPalette.orange700, // Warm amber-brown
      borderColor: SoftPalette.amber300,
      icon: Icons.warning_amber_rounded,
      iconColor: SoftPalette.amber200,
      duration: duration,
      onAction: onAction,
      actionLabel: actionLabel,
    );
  }

  /// 🔴 Error Toast
  /// Used for validation failures, network issues, or duplicate constraints.
  static void showError(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 4500),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    _showSnackBar(
      context,
      message: message,
      subtitle: subtitle,
      backgroundColor: SoftPalette.red700, // Deep crimson
      borderColor: SoftPalette.red400,
      icon: Icons.error_outline_rounded,
      iconColor: SoftPalette.red350,
      duration: duration,
      onAction: onAction,
      actionLabel: actionLabel,
    );
  }

  /// 🔵 Info Toast
  /// Used for general updates, filter notices, or instructional feedback.
  static void showInfo(
    BuildContext context,
    String message, {
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3200),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    _showSnackBar(
      context,
      message: message,
      subtitle: subtitle,
      backgroundColor: SoftPalette.slate800, // Slate / Navy
      borderColor: SoftPalette.sky350,
      icon: Icons.info_outline_rounded,
      iconColor: SoftPalette.sky350,
      duration: duration,
      onAction: onAction,
      actionLabel: actionLabel,
    );
  }

  static void _showSnackBar(
    BuildContext context, {
    required String message,
    String? subtitle,
    required Color backgroundColor,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required Duration duration,
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    // Rendered by the app-wide toast system (bottom-right / top on phones, ✕, max 3).
    final hasDetail = subtitle != null && subtitle.trim().isNotEmpty;
    AppToast.show(
      title: hasDetail ? message : null,
      message: hasDetail ? subtitle : message,
      icon: icon,
      background: backgroundColor,
      accent: iconColor,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

/// A standardized in-screen notice card to display warnings, approval states,
/// or offline sync indicators directly inside dialogs, modals, and sheets.
class AppFeedbackNoticeCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final Color? backgroundColor;
  final Widget? trailing;

  const AppFeedbackNoticeCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.backgroundColor,
    this.trailing,
  });

  factory AppFeedbackNoticeCard.warning({
    required String title,
    String? subtitle,
    Widget? trailing,
  }) =>
      AppFeedbackNoticeCard(
        title: title,
        subtitle: subtitle,
        icon: Icons.warning_amber_rounded,
        color: SoftPalette.orange400,
        backgroundColor: SoftPalette.yellow100,
        trailing: trailing,
      );

  factory AppFeedbackNoticeCard.info({
    required String title,
    String? subtitle,
    Widget? trailing,
  }) =>
      AppFeedbackNoticeCard(
        title: title,
        subtitle: subtitle,
        icon: Icons.info_outline_rounded,
        color: SoftPalette.sky500,
        backgroundColor: SoftPalette.slate100,
        trailing: trailing,
      );

  factory AppFeedbackNoticeCard.success({
    required String title,
    String? subtitle,
    Widget? trailing,
  }) =>
      AppFeedbackNoticeCard(
        title: title,
        subtitle: subtitle,
        icon: Icons.check_circle_outline_rounded,
        color: SoftPalette.emerald500,
        backgroundColor: SoftPalette.emerald100,
        trailing: trailing,
      );

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? SoftPalette.indigo550;
    final effectiveBg = backgroundColor ?? effectiveColor.withValues(alpha: 0.08);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: effectiveColor.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: effectiveColor, size: 18),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: effectiveColor,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: effectiveColor.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
