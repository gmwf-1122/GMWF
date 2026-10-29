// lib/design/components/app_dialog.dart
//
// ── AppConfirmDialog & showLogoutDialog — Unified Design System Dialogs ──────
// Standardized confirmation and destructive dialogs for the entire application.
// Enforces brand consistency:
//   • Destructive actions (Log Out, Delete) ALWAYS use Warning Red (SoftPalette.vividRed).
//   • Cancel actions ALWAYS use Emerald/Teal brand or neutral secondary styling.
//   • Fully supports dark/light mode with sleek modern geometry and soft shadows.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../tokens/soft_palette.dart';
import '../tokens/comfort_colors.dart';
import '../tokens/radius.dart';

/// Shows a standardized confirmation dialog across the application.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData? icon,
  bool isDanger = false,
  Widget? extraContent,
  String? warningNotice,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final c = context.comfort;
  final accentColor = isDanger ? SoftPalette.vividRed : SoftPalette.teal600;

  final result = await showDialog<bool>(
    context: context,
    barrierColor: SoftPalette.slate900.withValues(alpha: 0.45),
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: Gr.modal,
        side: BorderSide(
          color: c.border,
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Gr.r3),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          if (warningNotice != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isDark ? SoftPalette.orange900.withValues(alpha: 0.3) : SoftPalette.yellow50m,
                borderRadius: BorderRadius.circular(Gr.r2),
                border: Border.all(
                  color: isDark ? SoftPalette.orange600 : SoftPalette.yellow200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: isDark ? SoftPalette.amber200 : SoftPalette.orange400,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      warningNotice,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? SoftPalette.yellow150 : SoftPalette.orange800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (extraContent != null) ...[
            const SizedBox(height: 14),
            extraContent,
          ],
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: SoftPalette.teal600,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gr.r2)),
          ),
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: Text(
            cancelLabel,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDanger ? SoftPalette.vividRed : SoftPalette.teal600,
            foregroundColor: SoftPalette.gray50,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Gr.r2)),
          ),
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          icon: icon != null ? Icon(icon, size: 16) : const SizedBox.shrink(),
          label: Text(
            confirmLabel,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
        ),
      ],
    ),
  );

  return result == true;
}

/// Standardized Log Out confirmation dialog for the entire application.
/// Used everywhere a user attempts to log out:
///   • Warning Red action button (SoftPalette.vividRed)
///   • Brand Teal/Emerald cancel button (SoftPalette.teal600)
///   • Consistent iconography and reassurance
Future<bool> showLogoutDialog(
  BuildContext context, {
  String? subtitle,
  String? warningNotice,
}) {
  return showAppConfirmDialog(
    context: context,
    title: 'Log Out',
    message: subtitle ?? 'Are you sure you want to log out of GMWF?',
    confirmLabel: 'Log Out',
    cancelLabel: 'Cancel',
    icon: Icons.logout_rounded,
    isDanger: true,
    warningNotice: warningNotice,
  );
}
