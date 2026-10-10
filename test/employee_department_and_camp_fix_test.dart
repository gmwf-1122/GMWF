import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/finance_local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_emp_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('app_settings');
    await Hive.openBox(LocalStorageService.employeesBox);
    await Hive.openBox(LocalStorageService.salaryHistoryBox);
    await Hive.openBox(LocalStorageService.attendanceBox);
    await Hive.openBox(LocalStorageService.salaryLedgerBox);
    await Hive.openBox(LocalStorageService.financeSettingsBox);
    await Hive.openBox(LocalStorageService.branchTransfersBox);
    await Hive.openBox(LocalStorageService.auditLogsBox);
    await Hive.openBox(LocalStorageService.branchesBox);
    await Hive.openBox(LocalStorageService.usersBox);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.biometricCredentialsBox);
  });

  tearDown(() async {
    await Hive.close();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Employee Department Management Fixes', () {
    test('normalizeDepartment properly distinguishes Office and Administration', () {
      expect(FinanceLocalStorage.normalizeDepartment('Office'), 'Office');
      expect(FinanceLocalStorage.normalizeDepartment('office'), 'Office');
      expect(FinanceLocalStorage.normalizeDepartment('Office Boy'), 'Office');
      expect(FinanceLocalStorage.normalizeDepartment('Front Office'), 'Office');

      expect(FinanceLocalStorage.normalizeDepartment('Administration'), 'Administration');
      expect(FinanceLocalStorage.normalizeDepartment('Administration Staff'), 'Administration');
      expect(FinanceLocalStorage.normalizeDepartment('Admin'), 'Administration');
      expect(FinanceLocalStorage.normalizeDepartment('Accounts'), 'Administration');
      expect(FinanceLocalStorage.normalizeDepartment('Finance'), 'Administration');
      expect(FinanceLocalStorage.normalizeDepartment('HR'), 'Administration');

      expect(FinanceLocalStorage.normalizeDepartment('Dispensary'), 'Dispensary');
      expect(FinanceLocalStorage.normalizeDepartment('Madrassa'), 'Madrassa');
      expect(FinanceLocalStorage.normalizeDepartment('School'), 'School');
      expect(FinanceLocalStorage.normalizeDepartment('Dasterkhwaan'), 'Dasterkhwaan');
      expect(FinanceLocalStorage.normalizeDepartment('Security & Maintenance'), 'Security & Maintenance');
    });

    test('getRolesForDepartment supports Office, Administration, and Administration Staff', () {
      final officeRoles = FinanceLocalStorage.getRolesForDepartment('Office');
      expect(officeRoles.contains('Office Boy'), isTrue);
      expect(officeRoles.contains('Sweeper'), isTrue);

      final adminRoles = FinanceLocalStorage.getRolesForDepartment('Administration');
      expect(adminRoles.contains('Chairman'), isTrue);
      expect(adminRoles.contains('Branch Manager'), isTrue);

      final adminStaffRoles = FinanceLocalStorage.getRolesForDepartment('Administration Staff');
      expect(adminStaffRoles.contains('Chairman'), isTrue);
      expect(adminStaffRoles.contains('Branch Manager'), isTrue);

      final schoolRoles = FinanceLocalStorage.getRolesForDepartment('School');
      expect(schoolRoles.contains('Teacher'), isTrue);
    });

    test('Saving and retrieving employee department changes from Dispensary to Office persists correctly', () async {
      final empBox = FinanceLocalStorage.employeesBox;
      final empId = 'EMP_001';
      final initialData = <String, dynamic>{
        'id': empId,
        'localId': empId,
        'name': 'Muhammad Ali',
        'branchId': 'gujrat',
        'department': 'Dispensary',
        'role': 'Dispenser',
        'isActive': true,
        'updatedAt': '2026-10-01T10:00:00.000Z',
      };
      await empBox.put(empId, initialData);

      // Verify initially loaded as Dispensary
      var employees = FinanceLocalStorage.getEmployees('gujrat');
      expect(employees.first['department'], 'Dispensary');

      // Now change department to Office
      final updatedData = Map<String, dynamic>.from(initialData);
      updatedData['department'] = 'Office';
      updatedData['role'] = 'Office Boy';
      updatedData['updatedAt'] = '2026-10-08T12:00:00.000Z';
      await empBox.put(empId, updatedData);

      // Re-fetch employees
      employees = FinanceLocalStorage.getEmployees('gujrat');
      expect(employees.first['department'], 'Office');
      expect(employees.first['role'], 'Office Boy');
    });
  });

  group('Camp Auto-Creation & Isolation Fixes', () {
    test('Non-camp branch employees have spurious camps cleansed in getEmployeeCamp and getEmployeeCamps', () {
      final gujratEmp = <String, dynamic>{
        'branchId': 'gujrat',
        'camp': 'Saddar Camp',
        'camps': ['Saddar Camp', 'Haji Camp'],
      };
      expect(FinanceLocalStorage.getEmployeeCamp(gujratEmp), '');
      expect(FinanceLocalStorage.getEmployeeCamps(gujratEmp), isEmpty);

      final karachiEmp = <String, dynamic>{
        'branchId': 'karachi',
        'camp': 'saddar',
        'camps': ['saddar', 'haji_camp'],
      };
      expect(FinanceLocalStorage.getEmployeeCamp(karachiEmp), 'Saddar Camp');
      expect(FinanceLocalStorage.getEmployeeCamps(karachiEmp), contains('Saddar Camp'));
    });

    test('getEmployees cleanses spurious camps and allowedBranches for non-camp branches', () async {
      final empBox = FinanceLocalStorage.employeesBox;
      final empId = 'EMP_GUJRAT_01';
      final buggyData = <String, dynamic>{
        'id': empId,
        'localId': empId,
        'name': 'Usman Tariq',
        'branchId': 'gujrat',
        'department': 'Office',
        'role': 'Office Boy',
        'camps': ['Saddar Camp', 'Haji Camp'],
        'sessions': [
          {'camp': 'Saddar Camp', 'session': 'Morning'},
          {'camp': 'Haji Camp', 'session': 'Evening'},
        ],
        'allowedBranches': ['karachi', 'saddar', 'haji_camp', 'gujrat'],
        'isActive': true,
      };
      await empBox.put(empId, buggyData);

      final employees = FinanceLocalStorage.getEmployees('gujrat');
      expect(employees.length, 1);
      final e = employees.first;

      // Spurious camps & sessions must be sanitized away
      expect(e['camps'], isEmpty);
      expect(e['camp'], '');
      expect(e['sessions'], isEmpty);
      expect(e['allowedBranches'], equals(['gujrat']));
    });
  });
}
