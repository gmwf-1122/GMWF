import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
      backgroundColor: const Color(0xFF065F46), // Deep emerald
      borderColor: const Color(0xFF10B981),
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF34D399),
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
      backgroundColor: const Color(0xFF78350F), // Warm amber-brown
      borderColor: const Color(0xFFF59E0B),
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFFBBF24),
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
      backgroundColor: const Color(0xFF7F1D1D), // Deep crimson
      borderColor: const Color(0xFFEF4444),
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFF87171),
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
      backgroundColor: const Color(0xFF1E293B), // Slate / Navy
      borderColor: const Color(0xFF38BDF8),
      icon: Icons.info_outline_rounded,
      iconColor: const Color(0xFF38BDF8),
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: backgroundColor,
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor.withValues(alpha: 0.35), width: 1),
        ),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.dmSans(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  actionLabel,
                  style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
        color: const Color(0xFFD97706),
        backgroundColor: const Color(0xFFFEF3C7),
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
        color: const Color(0xFF0284C7),
        backgroundColor: const Color(0xFFE0F2FE),
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
        color: const Color(0xFF059669),
        backgroundColor: const Color(0xFFD1FAE5),
        trailing: trailing,
      );

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFF4F46E5);
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
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: effectiveColor,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: GoogleFonts.dmSans(
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
