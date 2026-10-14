// lib/design/tokens/colors.dart
//
// â”€â”€ GColor â€” Global Semantic Colors â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Role-theme accent colors live in RoleThemeData (app_theme.dart).
// GColor covers semantic status colors that are global and theme-independent.
//
// Replaces:
//   SoftPalette.green500   â†’ GColor.success / GColor.successOf(isDark)
//   SoftPalette.red500     â†’ GColor.danger  / GColor.dangerOf(isDark)
//   SoftPalette.orange400  â†’ GColor.warning / GColor.warningOf(isDark)
//   SoftPalette.blue400       â†’ GColor.info    / GColor.infoOf(isDark)
//   SoftPalette.purple400     â†’ use t.accent from role theme instead
//   SoftPalette.yellow200   â†’ GColor.warningOf(isDark)
//   SoftPalette.gray500    â†’ t.textTertiary from role theme instead
//   SoftPalette.emerald350       â†’ GColor.success (teal-emerald green)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';

class GColor {
  GColor._(); // prevent instantiation

  // â”€â”€ Success â€” green â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const Color success    = SoftPalette.vividGreen;
  static const Color successDark = SoftPalette.green350;
  static const Color successBg   = SoftPalette.vividGreenBg;
  static const Color successBgDark = SoftPalette.green700;

  // â”€â”€ Info â€” blue â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const Color info       = SoftPalette.vividBlue;
  static const Color infoDark   = SoftPalette.blue500;
  static const Color infoBg     = SoftPalette.vividBlueBg;
  static const Color infoBgDark = SoftPalette.blue750;

  // â”€â”€ Warning â€” amber â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const Color warning      = SoftPalette.vividAmber;
  static const Color warningDark  = SoftPalette.amber200;
  static const Color warningBg    = SoftPalette.vividAmberBg;
  static const Color warningBgDark = SoftPalette.amber750;

  // â”€â”€ Danger â€” red â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const Color danger     = SoftPalette.vividRed;
  static const Color dangerDark = SoftPalette.red400;
  static const Color dangerBg   = SoftPalette.vividRedBg;
  static const Color dangerBgDark = SoftPalette.red800;

  // â”€â”€ Neutral â€” grey â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const Color neutral     = SoftPalette.slate550;
  static const Color neutralDark = SoftPalette.slate350;
  static const Color neutralBg   = SoftPalette.gray50;
  static const Color neutralBgDark = SoftPalette.slate700;

  // â”€â”€ Theme-aware helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Returns the correct success color based on the current canvas darkness.
  static Color successOf(bool isDark) => isDark ? successDark : success;
  static Color successBgOf(bool isDark) => isDark ? successBgDark : successBg;

  static Color infoOf(bool isDark)    => isDark ? infoDark    : info;
  static Color infoBgOf(bool isDark)  => isDark ? infoBgDark  : infoBg;

  static Color warningOf(bool isDark) => isDark ? warningDark : warning;
  static Color warningBgOf(bool isDark) => isDark ? warningBgDark : warningBg;

  static Color dangerOf(bool isDark)  => isDark ? dangerDark  : danger;
  static Color dangerBgOf(bool isDark) => isDark ? dangerBgDark : dangerBg;

  static Color neutralOf(bool isDark) => isDark ? neutralDark : neutral;
  static Color neutralBgOf(bool isDark) => isDark ? neutralBgDark : neutralBg;

  // â”€â”€ Icon size constants (standardised) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // These aren't colors but live here as a convenience reference.
  // Actual usage: Icon(icon, size: GColor.iconSm)
  static const double iconXs  = 12; // badge / chip icon
  static const double iconSm  = 16; // button icon
  static const double iconMd  = 20; // list / card leading, app bar
  static const double iconLg  = 24; // section header icon
  static const double iconXl  = 32; // feature / hero icon
  static const double iconXxl = 48; // empty state illustration icon
}
