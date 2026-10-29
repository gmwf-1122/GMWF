// lib/design/tokens/typography.dart
//
// ── GText — Typography Scale (Design System v2) ───────────────────────────────
// One family for the whole UI: Inter (via google_fonts). Numbers in stat
// styles use tabular figures so columns of PKR amounts and counts line up.
// The Material TextTheme (lib/design/theme/gmwf_theme.dart) is built from the
// same scale, so plain Text() widgets inherit it too.
//
//   Role        Size  Weight  Use
//   display     32    w700    hero numbers, splash titles
//   h1          24    w700    page heading
//   h2          20    w600    card heading, dialog title
//   h3          16    w600    section heading, form section label
//   body1       14    w400    primary body text, list tile title
//   body2       13    w400    secondary body, subtitles
//   label       12    w600    chip text, field label, column header
//   caption     11    w400    helper text, timestamps
//   micro       10    w600    status badge, overline
//   statXl/Lg   28/22 w700    KPI numbers (tabular)
//
// Raw sizes still found in screens map onto the nearest role:
//   38–28 → display/statXl · 26–22 → h1/statLg · 20–18 → h2 · 17–15 → h3
//   14 → body1 · 13–12.5 → body2 · 12–10.5 → label · 11 → caption · 10 → micro
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GText {
  GText._(); // prevent instantiation

  /// The UI font family name, for `ThemeData.fontFamily` / `TextStyle.fontFamily`.
  static String? get family => GoogleFonts.inter().fontFamily;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle _inter(
    Color color, {
    required double size,
    required FontWeight weight,
    double? height,
    double letterSpacing = 0,
    bool tabular = false,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        fontFeatures: tabular ? _tabular : null,
      );

  // ── Display / Hero ────────────────────────────────────────────────────────

  /// 32px w700 — hero numbers, splash titles, PKR large amounts.
  static TextStyle display(Color color) =>
      _inter(color, size: 32, weight: FontWeight.w700, height: 1.15, letterSpacing: -0.8, tabular: true);

  // ── Headings ──────────────────────────────────────────────────────────────

  /// 24px w700 — page-level heading (AppBar title, section hero).
  static TextStyle h1(Color color) =>
      _inter(color, size: 24, weight: FontWeight.w700, height: 1.25, letterSpacing: -0.5);

  /// 20px w600 — card heading, dialog title.
  static TextStyle h2(Color color) =>
      _inter(color, size: 20, weight: FontWeight.w600, height: 1.3, letterSpacing: -0.3);

  /// 16px w600 — section heading, sub-card title, form section label.
  static TextStyle h3(Color color) =>
      _inter(color, size: 16, weight: FontWeight.w600, height: 1.35, letterSpacing: -0.1);

  // ── Body ──────────────────────────────────────────────────────────────────

  /// 14px w400 — primary body text, list tile title.
  static TextStyle body1(Color color) => _inter(color, size: 14, weight: FontWeight.w400, height: 1.5);

  /// 13px w400 — secondary body, list tile subtitle, description text.
  static TextStyle body2(Color color) => _inter(color, size: 13, weight: FontWeight.w400, height: 1.45);

  // ── Labels / UI ───────────────────────────────────────────────────────────

  /// 12px w600 — filter chip text, form field label, column header.
  static TextStyle label(Color color) =>
      _inter(color, size: 12, weight: FontWeight.w600, height: 1.35, letterSpacing: 0.1);

  /// 11px w400 — helper text, timestamp, secondary caption.
  static TextStyle caption(Color color) => _inter(color, size: 11, weight: FontWeight.w400, height: 1.35);

  /// 10px w600 — status badge, small tag, overline label.
  static TextStyle micro(Color color) =>
      _inter(color, size: 10, weight: FontWeight.w600, height: 1.3, letterSpacing: 0.4);

  /// 11px w600, wide tracking — UPPERCASE section labels ("RECENT ACTIVITY").
  static TextStyle overline(Color color) =>
      _inter(color, size: 11, weight: FontWeight.w600, height: 1.3, letterSpacing: 0.8);

  // ── Stat / Numeric ────────────────────────────────────────────────────────

  /// 28px w700 — large stat number (PKR amounts, counts on hero cards).
  static TextStyle statXl(Color color) =>
      _inter(color, size: 28, weight: FontWeight.w700, height: 1.15, letterSpacing: -0.6, tabular: true);

  /// 22px w700 — medium stat number (compact stat cards).
  static TextStyle statLg(Color color) =>
      _inter(color, size: 22, weight: FontWeight.w700, height: 1.2, letterSpacing: -0.4, tabular: true);

  /// 14px w600 tabular — numbers inside tables and lists.
  static TextStyle numeric(Color color) =>
      _inter(color, size: 14, weight: FontWeight.w600, height: 1.4, tabular: true);

  // ── Variants with extra weight ────────────────────────────────────────────

  /// body1 but semibold — for emphasized body text, row labels.
  static TextStyle body1Bold(Color color) => _inter(color, size: 14, weight: FontWeight.w600, height: 1.5);

  /// body2 but semibold — for secondary emphasized text.
  static TextStyle body2Bold(Color color) => _inter(color, size: 13, weight: FontWeight.w600, height: 1.45);

  // ── Button text (used by AppButton internally) ────────────────────────────
  static TextStyle buttonSm(Color color) =>
      _inter(color, size: 12, weight: FontWeight.w600, letterSpacing: 0.1);
  static TextStyle buttonMd(Color color) =>
      _inter(color, size: 13, weight: FontWeight.w600, letterSpacing: 0.1);
  static TextStyle buttonLg(Color color) =>
      _inter(color, size: 14, weight: FontWeight.w600, letterSpacing: 0.1);

  // ── Material TextTheme ────────────────────────────────────────────────────

  /// The scale above as a Material [TextTheme], for `ThemeData.textTheme`.
  ///
  /// No line heights here on purpose: bodyMedium becomes every Text widget's
  /// DefaultTextStyle, and ~5,700 inline styles in screens were laid out
  /// against the font's natural height. Adding one would shift those layouts.
  static TextTheme textTheme({required Color primary, required Color secondary}) {
    TextStyle s(Color color, double size, FontWeight weight, [double letterSpacing = 0]) =>
        _inter(color, size: size, weight: weight, letterSpacing: letterSpacing);
    return TextTheme(
      displayLarge: s(primary, 40, FontWeight.w700, -1.0),
      displayMedium: s(primary, 36, FontWeight.w700, -0.9),
      displaySmall: s(primary, 32, FontWeight.w700, -0.8),
      headlineLarge: s(primary, 28, FontWeight.w700, -0.6),
      headlineMedium: s(primary, 24, FontWeight.w700, -0.5),
      headlineSmall: s(primary, 20, FontWeight.w600, -0.3),
      titleLarge: s(primary, 18, FontWeight.w600, -0.2),
      titleMedium: s(primary, 16, FontWeight.w600, -0.1),
      titleSmall: s(primary, 14, FontWeight.w600),
      bodyLarge: s(primary, 15, FontWeight.w400),
      bodyMedium: s(primary, 14, FontWeight.w400),
      bodySmall: s(secondary, 12, FontWeight.w400),
      labelLarge: s(primary, 14, FontWeight.w600, 0.1),
      labelMedium: s(primary, 12, FontWeight.w600, 0.1),
      labelSmall: s(secondary, 11, FontWeight.w500, 0.2),
    );
  }
}
