import 'package:flutter/material.dart';
import 'package:another_flushbar/flushbar.dart';

class AppNotification {
  static void show(
    BuildContext context,
    String message, {
    Color color = Colors.green,
    IconData icon = Icons.check_circle_outline,
    int seconds = 3,
  }) {
    Flushbar(
      messageText: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      duration: Duration(seconds: seconds),
      flushbarPosition: FlushbarPosition.TOP,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: BorderRadius.circular(50),
      backgroundColor: color.withOpacity(0.85),
      icon: Icon(icon, color: Colors.white, size: 26),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      boxShadows: [
        BoxShadow(
          color: Colors.black.withOpacity(0.25),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ).show(context);
  }

  // ✅ Quick access helpers for consistency
  static void success(BuildContext context, String msg) =>
      show(context, msg, color: Colors.green, icon: Icons.check_circle_outline);

  static void error(BuildContext context, String msg) =>
      show(context, msg, color: Colors.redAccent, icon: Icons.error_outline);

  static void warning(BuildContext context, String msg) => show(context, msg,
      color: Colors.orangeAccent, icon: Icons.warning_amber_rounded);

  static void info(BuildContext context, String msg) =>
      show(context, msg, color: Colors.blueAccent, icon: Icons.info_outline);
}
