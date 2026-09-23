// lib/design/components/app_divider.dart

import 'package:flutter/material.dart';
import '../../theme/role_theme_provider.dart' show RoleThemeScope;
import '../tokens/spacing.dart';

/// Token-based divider. Uses t.bgRule for color.
/// Replaces raw Divider() usage which inherits ThemeData dividerColor.
class AppDivider extends StatelessWidget {
  const AppDivider({
    super.key,
    this.height = Gsp.sp1,
    this.indent = 0,
    this.endIndent = 0,
  });

  final double height;
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Divider(
      height: height,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: t.bgRule,
    );
  }
}

/// Vertical divider variant.
class AppVerticalDivider extends StatelessWidget {
  const AppVerticalDivider({super.key, this.width = Gsp.sp1});
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return VerticalDivider(width: width, thickness: 1, color: t.bgRule);
  }
}
