// lib/theme/role_theme_provider.dart

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'app_theme.dart';


class RoleThemeScope extends InheritedWidget {
  final RoleTheme role;

  const RoleThemeScope({
    super.key,
    required this.role,
    required super.child,
  });

  static RoleTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RoleThemeScope>();
    return scope?.role ?? RoleTheme.admin;
  }

  static RoleTheme roleOf(BuildContext context) => of(context);


  static RoleThemeData dataOf(BuildContext context, [Color? customColor]) {
    Color? resolvedColor = customColor;
    if (resolvedColor == null && Hive.isBoxOpen('app_settings')) {
      final prefColorStr = Hive.box('app_settings').get('custom_accent_color') as String?;
      if (prefColorStr != null && prefColorStr.isNotEmpty) {
        try {
          final hex = prefColorStr.replaceAll('#', '');
          resolvedColor = Color(int.parse('FF$hex', radix: 16));
        } catch (_) {}
      }
    }
    return RoleThemeData.of(of(context), resolvedColor);
  }

  @override
  bool updateShouldNotify(RoleThemeScope oldWidget) => role != oldWidget.role;
}

// ─────────────────────────────────────────────────────────────────────────────
// Themed scaffold helper shared across all role-aware pages
// ─────────────────────────────────────────────────────────────────────────────

class RolePageScaffold extends StatelessWidget {
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showBack;

  const RolePageScaffold({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: title != null
          ? AppBar(
              backgroundColor: t.bgCard,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              leading: showBack
                  ? IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: t.textSecondary, size: 22),
                      onPressed: () => Navigator.maybePop(context),
                    )
                  : null,
              title: Text(
                title!,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: actions,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: t.bgRule),
              ),
            )
          : null,
      body: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Themed card container
// ─────────────────────────────────────────────────────────────────────────────

class RoleCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool showGlow;

  const RoleCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 16,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    double resolvedRadius = radius;
    if (radius == 16 && Hive.isBoxOpen('app_settings')) {
      resolvedRadius = Hive.box('app_settings').get('card_radius', defaultValue: 16.0) as double;
    }
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(resolvedRadius),
        border: Border.all(color: t.bgRule, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          if (showGlow)
            BoxShadow(
              color: t.accent.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Themed text field decoration
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration roleInputDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  bool required = false,
}) {
  final t = RoleThemeScope.dataOf(context);
  final radius = Hive.isBoxOpen('app_settings')
      ? Hive.box('app_settings').get('card_radius', defaultValue: 16.0) as double
      : 12.0;

  return InputDecoration(
    labelText: required ? '$label *' : label,
    labelStyle: TextStyle(fontSize: 13.5, color: t.textTertiary),
    floatingLabelStyle: TextStyle(fontSize: 12, color: t.accent, fontWeight: FontWeight.w600),
    prefixIcon: Icon(icon, color: t.textTertiary, size: 20),
    filled: true,
    fillColor: t.bgCardAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: t.bgRule, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: t.bgRule, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: t.accent, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: t.danger, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: t.danger, width: 2),
    ),
    errorStyle: const TextStyle(fontSize: 11.5),
    counterText: '',
  );
}