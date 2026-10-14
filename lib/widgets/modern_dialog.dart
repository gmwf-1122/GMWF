// lib/widgets/modern_dialog.dart
import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import '../constants/colors.dart';

/// A modern, customizable dialog template with sleek aesthetics,
/// optional icon badge with gradient aura, responsive sizing, and clean actions.
class AppModernDialog extends StatelessWidget {
  final Widget? icon;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final String title;
  final String? subtitle;
  final Widget? content;
  final List<Widget>? actions;
  final double maxWidth;
  final bool showCloseButton;
  final VoidCallback? onClose;

  const AppModernDialog({
    super.key,
    this.icon,
    this.iconColor,
    this.iconBackgroundColor,
    required this.title,
    this.subtitle,
    this.content,
    this.actions,
    this.maxWidth = 460,
    this.showCloseButton = true,
    this.onClose,
  });

  /// Quick helper to show this modern dialog with built-in entrance animation
  static Future<T?> show<T>({
    required BuildContext context,
    Widget? icon,
    Color? iconColor,
    Color? iconBackgroundColor,
    required String title,
    String? subtitle,
    Widget? content,
    List<Widget>? actions,
    double maxWidth = 460,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: SoftPalette.gray900A45,
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) {
        return AppModernDialog(
          icon: icon,
          iconColor: iconColor,
          iconBackgroundColor: iconBackgroundColor,
          title: title,
          subtitle: subtitle,
          content: content,
          actions: actions,
          maxWidth: maxWidth,
          onClose: () => Navigator.of(ctx).pop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: isDark ? SoftPalette.slate900 : SoftPalette.gray50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? SoftPalette.slate750 : SoftPalette.slate150,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: SoftPalette.gray900.withValues(alpha: isDark ? 0.45 : 0.14),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 18, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: iconBackgroundColor ?? primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: IconTheme(
                          data: IconThemeData(
                            color: iconColor ?? primaryColor,
                            size: 24,
                          ),
                          child: icon!,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isDark ? SoftPalette.gray50 : AppColors.gray900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? SoftPalette.slate400 : AppColors.gray600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showCloseButton)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: isDark ? SoftPalette.slate400 : AppColors.gray400,
                        hoverColor: isDark ? SoftPalette.gray50A10 : SoftPalette.gray900.withValues(alpha: 0.05),
                        splashRadius: 18,
                        onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                      ),
                  ],
                ),
              ),

              // Content
              if (content != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: content!,
                ),

              // Actions
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? SoftPalette.slate900.withValues(alpha: 0.5)
                        : SoftPalette.gray50,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    border: Border(
                      top: BorderSide(
                        color: isDark ? SoftPalette.slate800 : SoftPalette.slate100,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions!,
                  ),
                ),
              ] else
                const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
