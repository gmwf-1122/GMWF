// lib/design/components/flushbar_compat.dart
//
// Drop-in replacement for `package:another_flushbar/flushbar.dart`.
// Existing `Flushbar(...).show(context)` calls keep compiling unchanged but are
// rendered by the app-wide toast system (AppToast: bottom-right on desktop, top
// on phones, max 3, ✕ to close). Position/shape/animation arguments are
// accepted for compatibility and ignored — the design system decides them.

// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

import 'app_toast.dart';

enum FlushbarPosition { TOP, BOTTOM }

enum FlushbarStyle { FLOATING, GROUNDED }

enum FlushbarDismissDirection { HORIZONTAL, VERTICAL }

class Flushbar<T> {
  final String? title;
  final String? message;
  final Widget? titleText;
  final Widget? messageText;
  final Widget? icon;
  final Color? backgroundColor;
  final Color? leftBarIndicatorColor;
  final Color? messageColor;
  final Color? titleColor;
  final Duration? duration;
  final Widget? mainButton;
  final FlushbarPosition flushbarPosition;
  final FlushbarStyle flushbarStyle;
  final FlushbarDismissDirection dismissDirection;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadows;
  final Duration animationDuration;
  final Curve forwardAnimationCurve;
  final Curve reverseAnimationCurve;
  final bool shouldIconPulse;
  final bool isDismissible;
  final double? maxWidth;
  final void Function(Flushbar<T>)? onTap;

  Flushbar({
    this.title,
    this.message,
    this.titleText,
    this.messageText,
    this.icon,
    this.backgroundColor,
    this.leftBarIndicatorColor,
    this.messageColor,
    this.titleColor,
    this.duration,
    this.mainButton,
    this.flushbarPosition = FlushbarPosition.BOTTOM,
    this.flushbarStyle = FlushbarStyle.FLOATING,
    this.dismissDirection = FlushbarDismissDirection.VERTICAL,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.borderColor,
    this.borderWidth = 1.0,
    this.boxShadows,
    this.animationDuration = const Duration(seconds: 1),
    this.forwardAnimationCurve = Curves.easeOutCirc,
    this.reverseAnimationCurve = Curves.easeOutCirc,
    this.shouldIconPulse = true,
    this.isDismissible = true,
    this.maxWidth,
    this.onTap,
  });

  /// Shows this notification as an app toast; completes when it closes.
  Future<T?> show(BuildContext context) async {
    // Re-typeset into the toast design: plain title/message, icon from an Icon
    // widget, kind (colour) inferred from the legacy background colour.
    final titleStr = title ?? AppToast.plainText(titleText);
    final messageStr = message ?? AppToast.plainText(messageText);
    final simple = (titleText == null || titleStr != null) && (messageText == null || messageStr != null);
    final iconWidget = icon;
    await AppToast.show(
      title: simple ? titleStr : null,
      message: simple ? messageStr : null,
      content: simple
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titleText != null) titleText! else if (title != null) Text(title!),
                if (messageText != null) messageText! else if (message != null) Text(message!),
              ],
            ),
      icon: iconWidget is Icon ? iconWidget.icon : null,
      background: backgroundColor ?? leftBarIndicatorColor,
      duration: duration,
    );
    return null;
  }

  /// Compatibility no-op (toasts close themselves / via ✕).
  Future<T?> dismiss([T? result]) async => result;
}
