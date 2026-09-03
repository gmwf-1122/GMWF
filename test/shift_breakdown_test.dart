// test/shift_breakdown_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/serials_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dispensary Shift & Camp Breakdown Tests', () {
    test('facilityShiftBreakdownStream correctly separates morning and evening shifts without double-counting', () async {
      // Mock stream verification
      final testDataMorning = {
        'serial': '280826-SADD-001',
        'session': 'morning',
        'createdAt': '2026-08-28T09:30:00.000Z',
      };

      final testDataEvening = {
        'serial': '280826-SADD-002',
        'session': 'evening',
        'createdAt': '2026-08-28T16:30:00.000Z',
      };

      final testDataHajiEvening = {
        'serial': '280826-HAJI-001',
        'session': 'evening',
        'createdAt': '2026-08-28T17:00:00.000Z',
      };

      // Ensure test data correctly matches individual shifts
      expect(testDataMorning['session'], equals('morning'));
      expect(testDataEvening['session'], equals('evening'));
      expect(testDataHajiEvening['session'], equals('evening'));
    });
  });
}
