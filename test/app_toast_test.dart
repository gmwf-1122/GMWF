import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/design/components/app_toast.dart';

Widget _app(Size size) => MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [child ?? const SizedBox.shrink(), const AppToastHost()],
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );

void main() {
  tearDown(AppToast.clear);

  testWidgets('max 3 visible: a 4th removes the oldest', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const Size(1400, 900)));

    for (final m in ['one', 'two', 'three', 'four']) {
      AppToast.show(message: m);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    expect(find.text('four'), findsOneWidget);
  });

  testWidgets('✕ closes a toast and it auto-closes after its duration', (tester) async {
    await tester.pumpWidget(_app(const Size(1400, 900)));

    AppToast.show(message: 'closable', duration: const Duration(seconds: 10));
    AppToast.show(message: 'auto', duration: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('closable'), findsOneWidget);

    // Desktop stacks oldest first, so the first ✕ belongs to 'closable'.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('closable'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('auto'), findsNothing);
  });

  testWidgets('desktop: bottom-right; phone: top', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const Size(1400, 900)));
    AppToast.show(message: 'where');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final desktop = tester.getRect(find.text('where'));
    expect(desktop.center.dx, greaterThan(1400 * 0.6));
    expect(desktop.center.dy, greaterThan(900 * 0.8));
    AppToast.clear();
    await tester.pump();

    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpWidget(_app(const Size(390, 800)));
    AppToast.show(message: 'phone');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final phone = tester.getRect(find.text('phone'));
    expect(phone.center.dy, lessThan(800 * 0.2));
  });

  testWidgets('identical message already visible is not duplicated; SnackBar routed', (tester) async {
    await tester.pumpWidget(_app(const Size(1400, 900)));
    AppToast.show(message: 'dup');
    AppToast.show(message: 'dup');
    AppToast.showSnackBar(tester.element(find.byType(Scaffold)), const SnackBar(content: Text('from snackbar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('dup'), findsOneWidget);
    expect(find.text('from snackbar'), findsOneWidget);
  });

  testWidgets('leading emoji sets the kind and is removed; legacy Row content is re-typeset', (tester) async {
    await tester.pumpWidget(_app(const Size(1400, 900)));
    AppToast.show(message: '✅ Token issued');
    AppToast.fromSnackBar(const SnackBar(
      backgroundColor: Colors.red,
      content: Row(children: [Icon(Icons.wifi_off), SizedBox(width: 8), Expanded(child: Text('Offline'))]),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Token issued'), findsOneWidget); // emoji stripped
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget); // success badge
    expect(find.text('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off), findsOneWidget); // legacy icon reused in the badge
  });
}
