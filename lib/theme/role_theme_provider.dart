// lib/theme/role_theme_provider.dart
// Provides current role context to shared pages (Branches, Register, Users, etc.)
import 'package:flutter/material.dart';
import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoleThemeScope — InheritedWidget that propagates the active RoleTheme down
// the entire widget tree.
//
// HOW IT WORKS:
//   1. At login, convert the Firestore role string once:
//        final role = RoleThemeData.fromString(userData['role']);
//
//   2. Wrap the top-level body of each role screen with RoleThemeScope:
//        RoleThemeScope(role: role, child: YourScreen())
//
//   3. In EVERY sub-screen (Branches, Patients, Users, Downloads, etc.)
//      read the theme with ONE line — no parameters needed:
//        final t = RoleThemeScope.dataOf(context);
//      Then use t.bg, t.accent, t.bgCard, etc. everywhere.
//
//   Result: CEO opens Branches → rose gold. Chairman opens same screen → gold.
//           Admin/Manager open it → identical light palette. Zero duplication;
//           no theme params passed through constructors.
// ─────────────────────────────────────────────────────────────────────────────

class RoleThemeScope extends InheritedWidget {
  final RoleTheme role;

  const RoleThemeScope({
    super.key,
    required this.role,
    required super.child,
  });

  /// Returns the active [RoleTheme] from the nearest [RoleThemeScope].
  /// Falls back to [RoleTheme.admin] if no scope is found.
  static RoleTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RoleThemeScope>();
    return scope?.role ?? RoleTheme.admin;
  }

  /// Returns the full [RoleThemeData] colour set for the signed-in role.
  /// This is the primary call used by every screen and sub-screen:
  ///   final t = RoleThemeScope.dataOf(context);
  static RoleThemeData dataOf(BuildContext context) {
    return RoleThemeData.of(of(context));
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

  const RoleCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.bgRule, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
  return InputDecoration(
    labelText: required ? '$label *' : label,
    labelStyle: TextStyle(fontSize: 13.5, color: t.textTertiary),
    floatingLabelStyle: TextStyle(fontSize: 12, color: t.accent, fontWeight: FontWeight.w600),
    prefixIcon: Icon(icon, color: t.textTertiary, size: 20),
    filled: true,
    fillColor: t.bgCardAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.bgRule, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.bgRule, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.accent, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.danger, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.danger, width: 2),
    ),
    errorStyle: const TextStyle(fontSize: 11.5),
    counterText: '',
  );
}