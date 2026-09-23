// lib/design/tokens/typography.dart
//
// ── GText — Typography Scale ──────────────────────────────────────────────────
// Font: Inter (via google_fonts — already in pubspec.yaml).
// All TextStyles in the app come from this class.
//
// Scale mapping — raw sizes currently in code → token:
//   38, 32, 28 → display / statXl    w800
//   26, 24, 22 → h1 / statLg         w700/w800
//   20, 18     → h2                  w700
//   17, 16, 15 → h3                  w600
//   14         → body1               w400
//   13, 12.5   → body2               w400
//   12, 10.5   → label               w600
//   11         → caption             w400
//   10         → micro               w600
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GText {
  GText._(); // prevent instantiation

  // ── Display / Hero ────────────────────────────────────────────────────────

  /// 32px w800 — hero numbers, splash titles, PKR large amounts.
  static TextStyle display(Color color) => GoogleFonts.inter(
    fontSize: 32, fontWeight: FontWeight.w800,
    color: color, letterSpacing: -0.5,
  );

  // ── Headings ──────────────────────────────────────────────────────────────

  /// 24px w700 — page-level heading (AppBar title, section hero).
  static TextStyle h1(Color color) => GoogleFonts.inter(
    fontSize: 24, fontWeight: FontWeight.w700, color: color,
  );

  /// 20px w700 — card heading, dialog title.
  static TextStyle h2(Color color) => GoogleFonts.inter(
    fontSize: 20, fontWeight: FontWeight.w700, color: color,
  );

  /// 16px w600 — section heading, sub-card title, form section label.
  static TextStyle h3(Color color) => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w600, color: color,
  );

  // ── Body ──────────────────────────────────────────────────────────────────

  /// 14px w400 — primary body text, list tile title.
  static TextStyle body1(Color color) => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400, color: color,
  );

  /// 13px w400 — secondary body, list tile subtitle, description text.
  static TextStyle body2(Color color) => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w400, color: color,
  );

  // ── Labels / UI ───────────────────────────────────────────────────────────

  /// 12px w600 — filter chip text, form field label, column header.
  static TextStyle label(Color color) => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w600, color: color,
  );

  /// 11px w400 — helper text, timestamp, secondary caption.
  static TextStyle caption(Color color) => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w400, color: color,
  );

  /// 10px w600 — status badge, small tag, overline label.
  static TextStyle micro(Color color) => GoogleFonts.inter(
    fontSize: 10, fontWeight: FontWeight.w600, color: color,
    letterSpacing: 0.5,
  );

  // ── Stat / Numeric ────────────────────────────────────────────────────────

  /// 28px w800 — large stat number (PKR amounts, counts on hero cards).
  static TextStyle statXl(Color color) => GoogleFonts.inter(
    fontSize: 28, fontWeight: FontWeight.w800,
    color: color, letterSpacing: -0.5,
  );

  /// 22px w800 — medium stat number (compact stat cards).
  static TextStyle statLg(Color color) => GoogleFonts.inter(
    fontSize: 22, fontWeight: FontWeight.w800, color: color,
  );

  // ── Variants with extra weight ────────────────────────────────────────────

  /// body1 but semibold — for emphasized body text, row labels.
  static TextStyle body1Bold(Color color) => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w600, color: color,
  );

  /// body2 but semibold — for secondary emphasized text.
  static TextStyle body2Bold(Color color) => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w600, color: color,
  );

  // ── Button text (used by AppButton internally) ────────────────────────────
  static TextStyle buttonSm(Color color) => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w600, color: color,
  );
  static TextStyle buttonMd(Color color) => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w600, color: color,
  );
  static TextStyle buttonLg(Color color) => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w600, color: color,
  );
}
