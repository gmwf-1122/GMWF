// lib/design/components/decorative_image.dart
//
// ── GDecorativeImage — purely decorative artwork, centrally switchable ───────
// Repeating patterns and ornaments (islamic_pattern.webp, mandala 1.webp,
// lattice 2.webp) are known triggers for headaches / migraines ("pattern
// glare"), which staff reported. They are OFF app-wide via [GDecor].
//
// Use GDecorativeImage.asset(...) — same arguments as Image.asset — for any
// image that is decoration only. Meaningful images (logos, the red-crescent
// symbol, photos) must keep using Image.asset.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

abstract final class GDecor {
  /// Eye comfort: decorative patterns are hidden everywhere.
  static const bool patternsEnabled = false;

  /// Eye comfort: no endlessly looping pulse/flash animations on working
  /// screens (brief loading spinners/skeletons are fine).
  static const bool reduceMotion = true;
}

class GDecorativeImage extends StatelessWidget {
  final String asset;
  final BoxFit? fit;
  final ImageRepeat repeat;
  final Color? color;
  final BlendMode? colorBlendMode;
  final AlignmentGeometry alignment;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final ImageErrorWidgetBuilder? errorBuilder;

  const GDecorativeImage.asset(
    this.asset, {
    super.key,
    this.fit,
    this.repeat = ImageRepeat.noRepeat,
    this.color,
    this.colorBlendMode,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = false,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (!GDecor.patternsEnabled) return const SizedBox.shrink();
    return Image.asset(
      asset,
      fit: fit,
      repeat: repeat,
      color: color,
      colorBlendMode: colorBlendMode,
      alignment: alignment,
      cacheWidth: cacheWidth,
      filterQuality: filterQuality,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder,
    );
  }
}
