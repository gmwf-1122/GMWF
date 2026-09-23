// lib/design/tokens/radius.dart
//
// ── Gr — Border Radius System (all multiples of 4) ───────────────────────────
// Every border radius in the app comes from this class.
//
// Old value → Token mapping:
//   6   → r2 (8)    — RatioBar bar clip, ramadan chips
//   9   → r2 (8)    — donation_boxes_screen segmented thumb
//   10  → r2 (8)    — user_detail avatar corners
//   14  → r4 (16)   — PatientTypeCard, app_theme pills
//   18  → r5 (20)   — gmwf_app_bar floating card
//   Already on-grid (no change):
//   8   → r2        — buttons
//   12  → r3        — inputs, inner cards
//   16  → r4        — main cards
//   20  → r5        — modals, dialogs
//   24  → r6        — hero panels
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class Gr {
  Gr._(); // prevent instantiation

  // ── Base scale (table of 4) ───────────────────────────────────────────────
  static const double r0    = 0;    // flat / sharp
  static const double r1    = 4;    // badge, tag, progress bar
  static const double r2    = 8;    // button, small chip, icon container
  static const double r3    = 12;   // input field, inner card, list tile
  static const double r4    = 16;   // main content card
  static const double r5    = 20;   // modal / dialog card
  static const double r6    = 24;   // hero panel, full-screen sheet
  static const double r7    = 32;   // segment pill thumb, large badge
  static const double rFull = 999;  // fully rounded pill

  // ── Named BorderRadius helpers ────────────────────────────────────────────

  /// r4 (16) — standard card.
  static BorderRadius get card    => BorderRadius.circular(r4);

  /// r5 (20) — modal / dialog card.
  static BorderRadius get modal   => BorderRadius.circular(r5);

  /// r6 (24) — hero banner / fullscreen panel.
  static BorderRadius get hero    => BorderRadius.circular(r6);

  /// r2 (8) — button.
  static BorderRadius get button  => BorderRadius.circular(r2);

  /// r3 (12) — text input field.
  static BorderRadius get input   => BorderRadius.circular(r3);

  /// rFull (999) — full pill chip.
  static BorderRadius get chip    => BorderRadius.circular(rFull);

  /// r1 (4) — small badge / tag.
  static BorderRadius get badge   => BorderRadius.circular(r1);

  /// r7 (32) — segment control pill thumb.
  static BorderRadius get segment => BorderRadius.circular(r7);

  /// r2 (8) — icon container background.
  static BorderRadius get icon    => BorderRadius.circular(r2);

  // ── Top-only helpers (for bottom sheets) ─────────────────────────────────
  static BorderRadius get sheetTop => const BorderRadius.only(
    topLeft: Radius.circular(r5),
    topRight: Radius.circular(r5),
  );

  static BorderRadius get sheetTopHero => const BorderRadius.only(
    topLeft: Radius.circular(r6),
    topRight: Radius.circular(r6),
  );
}
