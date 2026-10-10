import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/finance_local_storage.dart';

void main() {
  group('FinanceLocalStorage Double Entry Merge Tests', () {
    test('mergeAttendanceRecordMaps correctly merges biometric and manual draft punches', () {
      final bioRecord = {
        'employeeId': 'EMP_123',
        'date': '2026-10-06',
        'status': 'present',
        'checkInTime': '06:19 PM',
        'checkOutTime': '09:01 PM',
        'lastPunchTime': '09:01 PM',
        'workingDuration': '2h 42m',
        'shifts': {
          'Evening': {
            'checkIn': '06:19 PM',
            'checkOut': '09:01 PM',
            'duration': '2h 42m',
            'branch': 'Haji Camp',
          }
        },
      };

      final draftRecord = {
        'employeeId': 'EMP_123',
        'date': '2026-10-06',
        'status': 'absent', // draft initialized default
        'checkInTime': null,
        'checkOutTime': null,
        'note': 'Attended evening shift',
      };

      final merged = FinanceLocalStorage.mergeAttendanceRecordMaps(draftRecord, bioRecord);
      expect(merged, isNotNull);
      expect(merged!['status'].toString().toLowerCase(), equals('present'));
      expect(merged['checkInTime'], equals('06:19 PM'));
      expect(merged['checkOutTime'], equals('09:01 PM'));
      expect(merged['note'], equals('Attended evening shift'));
      expect(merged['shifts'], isNotNull);
      expect((merged['shifts'] as Map).containsKey('Evening'), isTrue);
    });

    test('mergeAttendanceRecordMaps picks earliest check-in and latest check-out across multiple punches', () {
      final punch1 = {
        'employeeId': 'EMP_456',
        'date': '2026-10-06',
        'status': 'present',
        'checkInTime': '09:15 AM',
        'checkOutTime': '01:00 PM',
        'shifts': {
          'Morning': {
            'checkIn': '09:15 AM',
            'checkOut': '01:00 PM',
            'branch': 'Saddar Camp',
          }
        }
      };

      final punch2 = {
        'employeeId': 'EMP_456',
        'date': '2026-10-06',
        'status': 'present',
        'checkInTime': '04:00 PM',
        'checkOutTime': '08:30 PM',
        'shifts': {
          'Evening': {
            'checkIn': '04:00 PM',
            'checkOut': '08:30 PM',
            'branch': 'Haji Camp',
          }
        }
      };

      final merged = FinanceLocalStorage.mergeAttendanceRecordMaps(punch1, punch2);
      expect(merged, isNotNull);
      expect(merged!['status'].toString().toLowerCase(), equals('present'));
      expect(merged['checkInTime'], equals('09:15 AM'));
      expect(merged['checkOutTime'], equals('08:30 PM'));
      
      final shifts = merged['shifts'] as Map;
      expect(shifts.length, equals(2));
      expect(shifts.containsKey('Morning'), isTrue);
      expect(shifts.containsKey('Evening'), isTrue);
    });
  });
}
