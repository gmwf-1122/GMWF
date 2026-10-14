import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/components/flushbar_compat.dart';

class AppNotification {
  static void show(
    BuildContext context,
    String message, {
    Color color = SoftPalette.green400,
    IconData icon = Icons.check_circle_outline,
    int seconds = 3,
  }) {
    Flushbar(
      messageText: Text(
        message,
        style: const TextStyle(
          color: SoftPalette.gray50,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      duration: Duration(seconds: seconds),
      flushbarPosition: FlushbarPosition.TOP,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: BorderRadius.circular(50),
      backgroundColor: color.withValues(alpha: 0.85),
      icon: Icon(icon, color: SoftPalette.gray50, size: 26),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      boxShadows: [
        BoxShadow(
          color: SoftPalette.gray900.withValues(alpha: 0.25),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ).show(context);
  }

  // ✅ Quick access helpers for consistency
  static void success(BuildContext context, String msg) =>
      show(context, msg, color: SoftPalette.green400, icon: Icons.check_circle_outline);

  static void error(BuildContext context, String msg) =>
      show(context, msg, color: SoftPalette.red400, icon: Icons.error_outline);

  static void warning(BuildContext context, String msg) => show(context, msg,
      color: SoftPalette.amber300, icon: Icons.warning_amber_rounded);

  static void info(BuildContext context, String msg) =>
      show(context, msg, color: SoftPalette.blue400, icon: Icons.info_outline);
}
