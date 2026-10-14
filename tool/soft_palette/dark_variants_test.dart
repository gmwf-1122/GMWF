// tool/soft_palette/dark_variants_test.dart
//
// Run with:  flutter test tool/soft_palette/dark_variants_test.dart
// (re-run after regenerate_test.dart whenever the palette is re-tuned)
//
// Gives every opaque palette colour a dark-mode partner on the mirrored tone
// (50↔900, 100↔800, 150↔750, 200↔700, 300↔600, 350↔550, 400↔500), same family
// and variant: light surfaces become dark, dark text becomes light, accents get
// a lighter step. Adds any missing partner entries, then writes the generated
// SoftPalette.adaptive() lookup. Light mode is never affected.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'soft_palette_engine.dart';

const paletteFile = 'lib/design/tokens/soft_palette.dart';
const _begin = '  // ── BEGIN GENERATED dark partners (tool/soft_palette/dark_variants_test.dart) ──';
const _end = '  // ── END GENERATED dark partners ──';

const _ladder = ['50', '100', '150', '200', '300', '350', '400', '500', '550', '600', '700', '750', '800', '900'];

String mirrorOf(String name) {
  final m = RegExp(r'^([a-z]+?)(\d+)(m|t)?$').firstMatch(name)!;
  final tone = m.group(2)!;
  final mirrored = _ladder[_ladder.length - 1 - _ladder.indexOf(tone)];
  return '${m.group(1)}$mirrored${m.group(3) ?? ''}';
}

void main() {
  test('generate dark partners', () {
    var src = File(paletteFile).readAsStringSync();
    // Drop a previous generated block so this is re-runnable.
    final b = src.indexOf(_begin);
    if (b >= 0) src = src.substring(0, b) + src.substring(src.indexOf(_end) + _end.length + 1);

    final entry = RegExp(r'static const Color ([A-Za-z0-9]+) = Color\(0x([0-9A-Fa-f]{8})\);');
    final existing = {for (final m in entry.allMatches(src)) m.group(1)!};
    final opaque = existing.where((n) => !RegExp(r'A\d+$').hasMatch(n)).toList()..sort();

    final missing = <String>{};
    for (final n in opaque) {
      final mirror = mirrorOf(n);
      if (!existing.contains(mirror)) missing.add(mirror);
    }

    final addLines = StringBuffer();
    for (final n in (missing.toList()..sort())) {
      final v = 0xFF000000 | colorForName(n);
      addLines.writeln('  static const Color $n = Color(0x${v.toRadixString(16).padLeft(8, '0').toUpperCase()});');
    }

    final gen = StringBuffer()
      ..writeln(_begin)
      ..write(addLines)
      ..writeln()
      ..writeln('  static final Map<int, Color> _darkPartner = {');
    for (final n in opaque) {
      gen.writeln('    $n.toARGB32(): ${mirrorOf(n)},');
    }
    gen
      ..writeln('  };')
      ..writeln()
      ..writeln('  /// The colour to use for [light] in the current theme: [light] itself in')
      ..writeln('  /// light mode (unchanged), its mirrored-tone partner in dark mode.')
      ..writeln('  /// Prefer `context.adapt(SoftPalette.x)` in widgets.')
      ..writeln('  static Color adaptive(Color light, bool isDark) {')
      ..writeln('    if (!isDark) return light;')
      ..writeln('    final partner = _darkPartner[light.toARGB32()];')
      ..writeln('    if (partner != null) return partner;')
      ..writeln('    // Transparent variants (A<n>): partner of the opaque colour, same opacity.')
      ..writeln('    final opaque = _darkPartner[light.toARGB32() | 0xFF000000];')
      ..writeln('    return opaque == null ? light : opaque.withValues(alpha: light.a);')
      ..writeln('  }')
      ..writeln(_end);

    final close = src.lastIndexOf('}');
    src = '${src.substring(0, close)}${gen.toString()}}\n';
    File(paletteFile).writeAsStringSync(src);
    // ignore: avoid_print
    print('opaque colours: ${opaque.length}, partner entries added: ${missing.length}');
  });
}
