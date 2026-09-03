import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/finance_local_storage.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('offboard_test_hive_');
    Hive.init(tempDir.path);

    await LocalStorageService.openBoxSafe(LocalStorageService.employeesBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.usersBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.attendanceBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.auditLogsBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.salaryHistoryBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.financeLoansBox);
    await LocalStorageService.openBoxSafe('local_employee_advances');
    await LocalStorageService.openBoxSafe(LocalStorageService.financeSettingsBox);
    await LocalStorageService.openBoxSafe(LocalStorageService.salaryLedgerBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Offboarding audit details, reasons, and exact timing persistence test', () async {
    final empBox = FinanceLocalStorage.employeesBox;
    final userBox = Hive.box(LocalStorageService.usersBox);
    final attBox = Hive.box(LocalStorageService.attendanceBox);

    // 1. Seed employee & linked user
    const empId = 'EMP_OFFBOARD_001';
    const userId = 'USR_OFFBOARD_001';
    const cnic = '42101-1234567-1';

    await empBox.put(empId, {
      'id': empId,
      'localId': empId,
      'name': 'Hamza Ahmed',
      'role': 'Dispenser',
      'branchId': 'karachi_saddar',
      'cnic': cnic,
      'currentSalary': 55000.0,
      'isActive': true,
      'status': 'Active',
      'hireDate': '2023-05-15',
      'linkedUserId': userId,
    });

    await userBox.put(userId, {
      'uid': userId,
      'username': 'hamza_dispenser',
      'role': 'dispenser',
      'cnic': cnic,
      'status': 'active',
      'isActive': true,
      'lastLogin': '2026-08-28T14:30:00.000',
    });

    await attBox.put('att_001', {
      'employeeId': empId,
      'cnic': cnic,
      'date': '2026-08-28',
      'checkInTime': '08:05 AM',
      'checkOutTime': '02:15 PM',
      'status': 'Present',
    });

    // 2. Fetch last recorded data audit snapshot
    final lastAudit = FinanceLocalStorage.getLastRecordedDataForEmployee(
      employeeId: empId,
      cnic: cnic,
      userId: userId,
    );

    expect(lastAudit['name'], equals('Hamza Ahmed'));
    expect(lastAudit['currentSalary'], equals(55000.0));
    expect(lastAudit['lastAttendance'], contains('28 Aug 2026'));
    expect(lastAudit['lastAttendance'], contains('Check-Out (02:15 PM)'));
    expect(lastAudit['lastActivity'], contains('hamza_dispenser'));

    // 3. Perform Bi-Directional Offboarding with detailed reasons & timings
    final exitDate = DateTime(2026, 8, 28);
    const exitTime = '02:30 PM';
    const reason = 'Resigned';
    const detailedRemarks = 'Submitted 1-month notice on 28 July. Departmental handover completed.';
    const shiftMilestone = 'End of Morning Shift';

    await FinanceLocalStorage.syncBiDirectionalOffboarding(
      employeeId: empId,
      userId: userId,
      cnic: cnic,
      performedBy: 'HQ Manager',
      reason: reason,
      detailedReason: detailedRemarks,
      effectiveDate: exitDate,
      effectiveTime: exitTime,
      shiftMilestone: shiftMilestone,
      lastRecordedData: lastAudit,
    );

    // 4. Verify employee record in Hive
    final updatedEmp = Map<String, dynamic>.from(empBox.get(empId) as Map);
    expect(updatedEmp['isActive'], isFalse);
    expect(updatedEmp['status'], equals('Inactive'));
    expect(updatedEmp['payrollStatus'], equals('Salary Stopped'));
    expect(updatedEmp['currentSalary'], equals(0.0));
    expect(updatedEmp['offboardingStatus'], equals('Resigned'));

    final offboardDetails = updatedEmp['offboardingDetails'] as Map;
    expect(offboardDetails['reason'], equals(reason));
    expect(offboardDetails['detailedReason'], equals(detailedRemarks));
    expect(offboardDetails['effectiveDate'], equals(exitDate.toIso8601String()));
    expect(offboardDetails['effectiveTime'], equals(exitTime));
    expect(offboardDetails['shiftMilestone'], equals(shiftMilestone));
    expect(offboardDetails['offboardedBy'], equals('HQ Manager'));
    expect(offboardDetails['lastRecordedData']['lastAttendance'], contains('28 Aug 2026'));

    // 5. Verify user account revocation in Hive
    final updatedUser = Map<String, dynamic>.from(userBox.get(userId) as Map);
    expect(updatedUser['status'], equals('revoked'));
    expect(updatedUser['isRevoked'], isTrue);
    expect(updatedUser['accessRevoked'], isTrue);
    expect(updatedUser['offboardingDetails']['reason'], equals(reason));
  });
}
