// tool/soft_palette/soft_palette_engine.dart
//
// Maps any sRGB colour onto the GMWF "soft" eye-comfort palette:
//   • lightness clamped to [L 0.22 … 0.985] (no pure black / pure white)
//   • chroma capped per tone (no neon / fully saturated colours)
//   • snapped to a fixed ladder: neutral families (gray, slate) + 14 hue
//     families × 14 tones, so the app uses one small named palette.
// Uses OKLab/OKLCH so "same lightness" means the same perceived lightness,
// which keeps text/background contrast relationships intact.

import 'dart:math' as math;

class SoftColor {
  final String name; // e.g. teal550, slate900, green400m
  final int rgb; // 0xRRGGBB
  const SoftColor(this.name, this.rgb);
}

class _Lab {
  final double l, a, b;
  const _Lab(this.l, this.a, this.b);
}

double _toLinear(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _toGamma(double c) => c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
double _cbrt(double x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

_Lab rgbToOklab(int rgb) {
  final r = _toLinear(((rgb >> 16) & 0xFF) / 255);
  final g = _toLinear(((rgb >> 8) & 0xFF) / 255);
  final b = _toLinear((rgb & 0xFF) / 255);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return _Lab(
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  );
}

/// Returns null when out of sRGB gamut.
int? oklabToRgb(double L, double a, double b) {
  final l = math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
  final m = math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
  final s = math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
  final r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  const eps = 0.0005;
  if ([r, g, bb].any((c) => c < -eps || c > 1 + eps)) return null;
  int ch(double c) => (_toGamma(c.clamp(0.0, 1.0)) * 255).round().clamp(0, 255);
  return (ch(r) << 16) | (ch(g) << 8) | ch(bb);
}

int _lch(double L, double c, double hDeg) {
  // Reduce chroma until the colour fits in sRGB.
  var cc = c;
  while (cc >= 0) {
    final h = hDeg * math.pi / 180;
    final v = oklabToRgb(L, cc * math.cos(h), cc * math.sin(h));
    if (v != null) return v;
    cc -= 0.002;
  }
  return oklabToRgb(L, 0, 0) ?? 0x808080;
}

/// Tone ladder (OKLab lightness) and its names.
const tones = <(double, String)>[
  (0.985, '50'), (0.965, '100'), (0.930, '150'), (0.870, '200'), (0.800, '300'), (0.730, '350'), (0.660, '400'),
  (0.590, '500'), (0.520, '550'), (0.450, '600'), (0.380, '700'), (0.320, '750'), (0.270, '800'), (0.220, '900'),
];

/// Hue families (OKLCH hue centre in degrees).
const families = <String, double>{
  'red': 25, 'orange': 50, 'amber': 75, 'yellow': 100, 'lime': 125, 'green': 145, 'emerald': 163, 'teal': 182,
  'cyan': 210, 'sky': 235, 'blue': 260, 'indigo': 278, 'violet': 295, 'purple': 315, 'pink': 350,
};

/// Soft chroma ceiling for a tone: muted mid-tones, near-neutral extremes.
double chromaCap(double L, [String family = '']) {
  final x = (L - 0.60) / 0.46;
  // v2 (after staff feedback): peak lowered 0.122 → 0.092 so large fills and
  // bold status text (BP values, "Waiting" cards, purple badges) are calmer.
  final base = math.max(0.014, 0.092 * (1 - x * x));
  // Yellows/ambers need more chroma to still read as colour (warning must look amber).
  final boost = switch (family) { 'amber' || 'yellow' => 1.3, 'orange' => 1.1, _ => 1.0 };
  return base * boost;
}

/// The colour for a palette name (e.g. teal550, red100t, amber750m, slate900).
/// Single source of truth for values — softFor() picks the name, this the RGB,
/// so the whole palette can be re-tuned and regenerated without touching screens.
int colorForName(String name) {
  final m = RegExp(r'^([a-z]+?)(\d+)(m|t)?$').firstMatch(name);
  if (m == null) throw ArgumentError('Not a palette name: $name');
  final family = m.group(1)!, tone = m.group(2)!, variant = m.group(3);
  final L = _toneL(tone);
  if (family == 'gray') return _lch(L, 0.004, 85);
  if (family == 'slate') {
    // Barely tinted when light (no blue cast on backgrounds), cooler when dark.
    return _lch(L, L > 0.9 ? 0.008 : (L > 0.78 ? 0.014 : 0.024), 257);
  }
  final hue = families[family]!;
  if (variant == 't') return _lch(L, 0.012, hue);
  final cap = chromaCap(L, family);
  return _lch(L, variant == 'm' ? cap * 0.5 : cap, hue);
}

String _nearestTone(double L) {
  final clamped = L.clamp(0.22, 0.985);
  var best = tones.first;
  for (final t in tones) {
    if ((t.$1 - clamped).abs() < (best.$1 - clamped).abs()) best = t;
  }
  return best.$2;
}

double _toneL(String tone) => tones.firstWhere((t) => t.$2 == tone).$1;

String _nearestFamily(double hue) {
  var best = families.keys.first;
  double dist(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
  for (final f in families.keys) {
    if (dist(families[f]!, hue) < dist(families[best]!, hue)) best = f;
  }
  return best;
}

/// Maps an opaque RGB colour to its soft palette entry.
SoftColor softFor(int rgb) {
  final lab = rgbToOklab(rgb);
  final c = math.sqrt(lab.a * lab.a + lab.b * lab.b);
  var hue = math.atan2(lab.b, lab.a) * 180 / math.pi;
  if (hue < 0) hue += 360;
  final tone = _nearestTone(lab.l);
  final L = _toneL(tone);

  // Neutrals: warm "paper" grey, or cool slate (the app's many slate tones).
  // Cool greys (e.g. #E2E8F0 borders) stay slate so they match the slate text.
  final coolHue = hue >= 200 && hue <= 290;
  if (c < 0.015 && !(coolHue && c >= 0.006)) {
    // Pale status/brand tints (#FEF2F2 error bg, #F1F8F5 brand bg) keep a
    // whisper of their hue — that tint carries meaning.
    if (L >= 0.93 && c >= 0.006) {
      final name = '${_nearestFamily(hue)}${tone}t';
      return SoftColor(name, colorForName(name));
    }
    return SoftColor('gray$tone', colorForName('gray$tone'));
  }
  if (c < 0.06 && coolHue) {
    return SoftColor('slate$tone', colorForName('slate$tone'));
  }
  final family = _nearestFamily(hue);
  final cap = chromaCap(L, family);
  // Dusty originals keep a muted variant instead of being boosted to the cap.
  final name = '$family$tone${c < cap * 0.55 ? 'm' : ''}';
  return SoftColor(name, colorForName(name));
}
