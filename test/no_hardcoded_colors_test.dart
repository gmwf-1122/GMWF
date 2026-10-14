// Guard: every screen colour must come from lib/design/tokens/soft_palette.dart
// (the eye-comfort palette). Use SoftPalette.<name>, or add an entry there.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no hard-coded colours outside SoftPalette', () {
    final hex = RegExp(r'(?<![A-Za-z0-9_.])Color\(0x[0-9A-Fa-f]{8}\)');
    final material = RegExp(r'(?<![A-Za-z0-9_])Colors\.(?!transparent\b)[a-zA-Z]');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart') || p.endsWith('design/tokens/soft_palette.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        if (hex.hasMatch(l) || material.hasMatch(l)) offenders.add('$p:${i + 1}: ${l.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'Use SoftPalette instead of hard-coded colours:\n${offenders.take(20).join('\n')}');
  });
}
