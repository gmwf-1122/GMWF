// lib/design/tokens/spacing.dart
//
// ── Gsp — Table-of-4 Spacing System ──────────────────────────────────────────
// Every spacing value in the app is a multiple of 4.
// Use Gsp tokens instead of raw SizedBox/EdgeInsets numbers.
//
// Old value → Token mapping:
//   3  → sp1 (4)    — +1px, imperceptible
//   6  → sp2 (8)    — +2px, imperceptible
//   9  → sp2 (8)    — -1px, imperceptible
//   10 → sp2 (8)    — or sp3 (12) depending on context
//   13 → sp3 (12)   — -1px, imperceptible
//   14 → sp4 (16)   — +2px
//   17 → sp4 (16)   — -1px
//   18 → sp4 (16)   — slightly tighter (fine)
// ─────────────────────────────────────────────────────────────────────────────

class Gsp {
  Gsp._(); // prevent instantiation

  // ── Base scale (table of 4) ───────────────────────────────────────────────
  static const double sp0  = 0;
  static const double sp1  = 4;
  static const double sp2  = 8;
  static const double sp3  = 12;
  static const double sp4  = 16;
  static const double sp5  = 20;
  static const double sp6  = 24;
  static const double sp7  = 28;
  static const double sp8  = 32;
  static const double sp9  = 36;
  static const double sp10 = 40;
  static const double sp12 = 48;
  static const double sp14 = 56;
  static const double sp16 = 64;
  static const double sp20 = 80;

  // Direct pixel name aliases
  static const double s0  = sp0;
  static const double s4  = sp1;
  static const double s8  = sp2;
  static const double s12 = sp3;
  static const double s16 = sp4;
  static const double s20 = sp5;
  static const double s24 = sp6;
  static const double s28 = sp7;
  static const double s32 = sp8;
  static const double s36 = sp9;
  static const double s40 = sp10;
  static const double s48 = sp12;
  static const double s56 = sp14;
  static const double s64 = sp16;
  static const double s80 = sp20;

  // ── Semantic aliases ──────────────────────────────────────────────────────

  /// 16px — standard horizontal screen edge padding on mobile.
  static const double screenH = sp4;

  /// 24px — standard horizontal screen edge padding on tablet/desktop.
  static const double screenHD = sp6;

  /// 16px — standard inner padding for content cards.
  static const double cardPad = sp4;

  /// 24px — inner padding for hero / banner cards.
  static const double cardPadL = sp6;

  /// 8px — tight gap between inline elements (icon + text, row items).
  static const double gap = sp2;

  /// 12px — medium gap between related elements.
  static const double gapMd = sp3;

  /// 16px — large gap between loosely related elements.
  static const double gapLg = sp4;

  /// 12px — vertical gap between consecutive cards in a list.
  static const double sectionGap = sp3;

  /// 80px — bottom page padding to clear floating action buttons.
  static const double pageBottom = sp20;
}
