import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/design/design_system.dart';

void main() {
  testWidgets('context.comfort follows the theme', (tester) async {
    late GComfortColors lightC, darkC;
    Widget app(Brightness b, void Function(GComfortColors) out) => MaterialApp(
          theme: ThemeData(brightness: b, extensions: [b == Brightness.dark ? GComfortColors.dark : GComfortColors.light]),
          home: Builder(builder: (ctx) { out(ctx.comfort); return const SizedBox(); }),
        );
    await tester.pumpWidget(app(Brightness.light, (c) => lightC = c));
    await tester.pumpWidget(app(Brightness.dark, (c) => darkC = c));
    await tester.pumpAndSettle(); // theme changes animate
    expect(lightC.surface, GComfortColors.light.surface);
    expect(darkC.surface, GComfortColors.dark.surface);
    expect(lightC.textPrimary, isNot(darkC.textPrimary));
  });

  test('no pure white or black anywhere in the comfort sets', () {
    for (final set in [GComfortColors.light, GComfortColors.dark]) {
      for (final c in [set.background, set.surface, set.textPrimary, set.onBrand]) {
        expect(c.toARGB32() & 0xFFFFFF, isNot(0xFFFFFF));
        expect(c.toARGB32() & 0xFFFFFF, isNot(0x000000));
      }
    }
  });
}
