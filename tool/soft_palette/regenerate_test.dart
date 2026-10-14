// tool/soft_palette/regenerate_test.dart
//
// Run with:  flutter test tool/soft_palette/regenerate_test.dart
//
// Re-tunes the palette: recomputes every value in lib/design/tokens/soft_palette.dart
// from its NAME with the current engine settings (colorForName), keeping each
// entry's opacity. Screens reference names, so no other file changes.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'soft_palette_engine.dart';

const paletteFile = 'lib/design/tokens/soft_palette.dart';

void main() {
  test('regenerate soft palette values', () {
    final entry = RegExp(r'static const Color ([A-Za-z0-9]+) = Color\(0x([0-9A-Fa-f]{8})\);');
    final src = File(paletteFile).readAsStringSync();
    final changes = <(String, int, int)>[];
    final out = src.replaceAllMapped(entry, (m) {
      final name = m.group(1)!;
      final old = int.parse(m.group(2)!, radix: 16);
      final base = name.replaceFirst(RegExp(r'A\d+$'), '');
      final rgb = colorForName(base);
      final argb = (old & 0xFF000000) | rgb;
      if ((old & 0xFFFFFF) != rgb) changes.add((name, old, argb));
      return 'static const Color $name = Color(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()});';
    });
    File(paletteFile).writeAsStringSync(out);

    int dist(int a, int b) {
      int ch(int v, int s) => (v >> s) & 0xFF;
      return [16, 8, 0].map((s) => (ch(a, s) - ch(b, s)).abs()).reduce(math.max);
    }
    changes.sort((x, y) => dist(y.$2, y.$3).compareTo(dist(x.$2, x.$3)));
    String hex(int v) => '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    // ignore: avoid_print
    print('entries changed: ${changes.length}');
    for (final c in changes.take(14)) {
      // ignore: avoid_print
      print('  ${c.$1.padRight(14)} ${hex(c.$2)} -> ${hex(c.$3)}');
    }
  });
}
