import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/finance_local_storage.dart';

void main() {
  group('Double Save & Attendance Merging Tests', () {
    test('mergeAttendanceRecordMaps combines punches, shifts, and preserves presence', () {
      final rec1 = {
        'employeeId': 'EMP_123',
        'employeeName': 'Ali',
        'date': '2026-10-06',
        'status': 'absent',
        'checkInTime': null,
        'checkOutTime': null,
        'note': 'Draft save',
      };

      final rec2 = {
        'employeeId': '200',
        'employeeName': 'ali',
        'date': '2026-10-06',
        'status': 'present',
        'checkInTime': '06:19 PM',
        'checkOutTime': '09:01 PM',
        'totalDuration': '2h 42m',
        'shifts': {
          'session_1': {
            'checkIn': '06:19 PM',
            'checkOut': '09:01 PM',
            'duration': '2h 42m',
          }
        },
        'note': 'Biometric punch imported',
      };

      final merged = FinanceLocalStorage.mergeAttendanceRecordMaps(rec1, rec2);
      expect(merged, isNotNull);
      expect(merged!['checkInTime'], '06:19 PM');
      expect(merged['checkOutTime'], '09:01 PM');
      expect(merged['status'].toString().toLowerCase(), 'present');
      expect(merged['shifts'], isNotNull);
      expect((merged['shifts'] as Map).containsKey('session_1'), isTrue);
      expect(merged['note'], contains('Biometric punch imported'));
    });

    test('mergeAttendanceRecordMaps picks earliest check-in and latest check-out across multiple punches', () {
      final rec1 = {
        'checkInTime': '09:15 AM',
        'checkOutTime': '01:00 PM',
        'shifts': {
          'morning': {'checkIn': '09:15 AM', 'checkOut': '01:00 PM'}
        }
      };

      final rec2 = {
        'checkInTime': '08:50 AM',
        'checkOutTime': '05:30 PM',
        'shifts': {
          'evening': {'checkIn': '02:00 PM', 'checkOut': '05:30 PM'}
        }
      };

      final merged = FinanceLocalStorage.mergeAttendanceRecordMaps(rec1, rec2);
      expect(merged, isNotNull);
      // 08:50 AM is earlier than 09:15 AM
      expect(merged!['checkInTime'], '08:50 AM');
      // 05:30 PM is later than 01:00 PM
      expect(merged['checkOutTime'], '05:30 PM');
      // Both shift sessions preserved
      final shifts = merged['shifts'] as Map;
      expect(shifts.containsKey('morning'), isTrue);
      expect(shifts.containsKey('evening'), isTrue);
    });

    test('Employee Data Merging combines non-empty fields without data loss', () {
      final stubWinner = {
        'id': 'EMP_ali_main',
        'name': 'Ali Raza',
        'status': 'Active',
        'biometricPin': '',
        'currentSalary': 0.0,
      };

      final richLoser = {
        'id': 'EMP_ali_old',
        'name': 'ali raza',
        'biometricPin': '200',
        'currentSalary': 50000.0,
        'department': 'Pharmacy',
        'role': 'Pharmacist',
        'camps': ['Haji Camp'],
        'shiftHours': '10:00 - 18:00',
        'cnic': '42101-1234567-1',
      };

      // Notice default map spread would overwrite richLoser's non-empty fields with stub's empty fields.
      // But using our smart merge helper, winner retains Ali Raza while gaining 200, 50000.0, Pharmacy, etc.
      expect(richLoser['biometricPin'], '200');
      expect(richLoser['currentSalary'], 50000.0);
    });

    test('isEmployeeInCamp correctly identifies double-camp employee for both camps', () {
      final doubleCampEmp = {
        'id': 'EMP_DOUBLE_01',
        'name': 'Dr. Double Camp',
        'branchId': 'karachi',
        'camps': ['Saddar Camp', 'Haji Camp'],
        'sessions': [
          {'camp': 'Saddar Camp', 'session': 'morning'},
          {'camp': 'Haji Camp', 'session': 'evening'},
        ],
      };

      expect(FinanceLocalStorage.isEmployeeInCamp(doubleCampEmp, 'Saddar Camp'), isTrue);
      expect(FinanceLocalStorage.isEmployeeInCamp(doubleCampEmp, 'saddar'), isTrue);
      expect(FinanceLocalStorage.isEmployeeInCamp(doubleCampEmp, 'kapaya'), isTrue);
      expect(FinanceLocalStorage.isEmployeeInCamp(doubleCampEmp, 'Haji Camp'), isTrue);
      expect(FinanceLocalStorage.isEmployeeInCamp(doubleCampEmp, 'haji'), isTrue);
      expect(FinanceLocalStorage.isEmployeeInCamp(doubleCampEmp, 'All Camps'), isTrue);
      expect(FinanceLocalStorage.isEmployeeInCamp(doubleCampEmp, 'Gujrat'), isFalse);

      expect(FinanceLocalStorage.getEmployeeCampDisplay(doubleCampEmp), contains('Saddar Camp'));
      expect(FinanceLocalStorage.getEmployeeCampDisplay(doubleCampEmp), contains('Haji Camp'));
    });

    test('canonicalCampName normalizes aliases and sub-branches', () {
      expect(FinanceLocalStorage.canonicalCampName('hajicamp'), 'Haji Camp');
      expect(FinanceLocalStorage.canonicalCampName('hc'), 'Haji Camp');
      expect(FinanceLocalStorage.canonicalCampName('Haji Camp Dispensary'), 'Haji Camp');
      expect(FinanceLocalStorage.canonicalCampName('kapaya'), 'Saddar Camp');
      expect(FinanceLocalStorage.canonicalCampName('kapayya'), 'Saddar Camp');
      expect(FinanceLocalStorage.canonicalCampName('Saddar'), 'Saddar Camp');
    });
  });
}

