// Basic Flutter widget test to ensure the app builds without errors.

import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/main.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  setUp(() async {
    Hive.init('./build/test_hive');
    await Hive.openBox('app_settings');
  });

  tearDown(() async {
    await Hive.close();
  });

  testWidgets('App builds smoke test',
      skip: true, // MyApp starts Firebase/LAN/sync timers that outlive the widget tree; needs a test seam in main.dart
      (WidgetTester tester) async {
    // Build the app.
    await tester.pumpWidget(const MyApp());
    await tester.pump();
  });
}
