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

  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Build the app.
    await tester.pumpWidget(const MyApp());
    await tester.pump(); // advance a frame
  });
}
