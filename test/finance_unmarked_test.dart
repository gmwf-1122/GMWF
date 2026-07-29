import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/finance_local_storage.dart';
import 'package:gmwf/services/finance_loans_storage.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.employeesBox);
    await Hive.openBox(LocalStorageService.salaryHistoryBox);
    await Hive.openBox(LocalStorageService.attendanceBox);
    await Hive.openBox(LocalStorageService.salaryLedgerBox);
    await Hive.openBox(LocalStorageService.financeLoansBox);
    await Hive.openBox(LocalStorageService.financeSettingsBox);
    await Hive.openBox(LocalStorageService.auditLogsBox);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.financeHolidaysBox);
    await Hive.openBox(LocalStorageService.branchesBox);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    await Hive.box(LocalStorageService.employeesBox).clear();
    await Hive.box(LocalStorageService.salaryHistoryBox).clear();
    await Hive.box(LocalStorageService.attendanceBox).clear();
    await Hive.box(LocalStorageService.salaryLedgerBox).clear();
    await Hive.box(LocalStorageService.financeLoansBox).clear();
    await Hive.box(LocalStorageService.financeSettingsBox).clear();
    await Hive.box(LocalStorageService.auditLogsBox).clear();
    await Hive.box(LocalStorageService.syncBox).clear();
    await Hive.box(LocalStorageService.financeHolidaysBox).clear();
    await Hive.box(LocalStorageService.branchesBox).clear();
  });

  test('Unmarked weekdays result in unmarked status and zero deductions', () async {
    final empId = 'emp_test_1';
    final employeesBox = Hive.box(LocalStorageService.employeesBox);
    final historyBox = Hive.box(LocalStorageService.salaryHistoryBox);

    // Save employee profile
    await employeesBox.put(empId, {
      'id': empId,
      'localId': empId,
      'name': 'Test Employee',
      'branchId': 'islamabad',
      'joiningDate': '2026-06-01',
      'currentSalary': 30000.0,
      'isActive': true,
    });

    // Save a salary rate change
    await historyBox.put('${empId}_hist1', {
      'id': 'hist1',
      'amount': 30000.0,
      'effectiveDate': '2026-06-01',
    });

    // Compute payroll summary for 2026-06 (30 days total)
    // No attendance records exist in the box (all unmarked)
    final summary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, '2026-06');

    // Expected:
    // unpaidLeaves = 0.0
    // absentDays = 0.0
    // unmarkedDays = 26 (weekdays excluding Sundays)
    // absenceDeductions = 0.0
    // baseSalaryEarned = 30000.0
    expect(summary['unmarkedDays'], equals(26));
    expect(summary['absentDays'], equals(0.0));
    expect(summary['unpaidLeaves'], equals(0.0));
    expect(summary['absenceDeductions'], equals(0.0));
    expect(summary['baseSalaryEarned'], equals(30000.0));
  });

  test('Legacy loan migration correctly calculates outstanding and registers flexible loan', () async {
    final empId = 'emp_test_2';
    final employeesBox = Hive.box(LocalStorageService.employeesBox);
    final ledgerBox = Hive.box(LocalStorageService.salaryLedgerBox);

    // Save employee profile
    await employeesBox.put(empId, {
      'id': empId,
      'localId': empId,
      'name': 'Test Employee 2',
      'branchId': 'islamabad',
      'isActive': true,
    });

    // Save legacy advance payments and payout deductions
    // 1. Advance of PKR 10,000
    await ledgerBox.put('led1', {
      'id': 'led1',
      'employeeId': empId,
      'employeeName': 'Test Employee 2',
      'type': 'advance_payment',
      'amount': 10000.0,
      'date': '2026-05-10',
      'isVoided': false,
    });

    // 2. Recovery deduction of PKR 4,000 in a payout entry
    await ledgerBox.put('led2', {
      'id': 'led2',
      'employeeId': empId,
      'employeeName': 'Test Employee 2',
      'type': 'payout',
      'advanceDeductions': 4000.0,
      'date': '2026-05-31',
      'isVoided': false,
    });

    // 3. Voided advance payment (should be ignored)
    await ledgerBox.put('led3', {
      'id': 'led3',
      'employeeId': empId,
      'employeeName': 'Test Employee 2',
      'type': 'advance_payment',
      'amount': 5000.0,
      'date': '2026-05-12',
      'isVoided': true,
    });

    // Execute migration
    await FinanceLoansStorage.migrateLegacyAdvancesToLoans(performedBy: 'Test System');

    // Expected:
    // Outstanding legacy amount = 10000 - 4000 = 6000
    // Check if a loan of 6000 was created
    final loansBox = Hive.box(LocalStorageService.financeLoansBox);
    expect(loansBox.length, equals(1));

    final loan = Map<String, dynamic>.from(loansBox.values.first as Map);
    expect(loan['employeeId'], equals(empId));
    expect(loan['principal'], equals(6000.0));
    expect(loan['repaymentType'], equals('flexible'));
    expect(loan['status'], equals('active'));
    
    // Check migration flag
    final settingsBox = Hive.box(LocalStorageService.financeSettingsBox);
    expect(settingsBox.get('legacy_advances_migrated_v1'), isTrue);
  });

  test('Sunday pay proration for mid-month joining and leaving', () async {
    final empId1 = 'emp_june_proration_1';
    final empId2 = 'emp_june_proration_2';
    final employeesBox = Hive.box(LocalStorageService.employeesBox);
    final historyBox = Hive.box(LocalStorageService.salaryHistoryBox);

    // Scenario 1: Employed 10 June - 24 June (15 days)
    // June 2026 has 30 days. Salary 30,000 PKR => Daily rate 1,000 PKR.
    // 2 Sundays in this period: June 14 and June 21.
    // We expect baseSalaryEarned = 15,000 PKR.
    await employeesBox.put(empId1, {
      'id': empId1,
      'localId': empId1,
      'name': 'Proration Employee 1',
      'branchId': 'islamabad',
      'joiningDate': '2026-06-10',
      'exitDate': '2026-06-24',
      'currentSalary': 30000.0,
      'isActive': true,
    });

    await historyBox.put('${empId1}_hist', {
      'id': 'hist_${empId1}',
      'amount': 30000.0,
      'effectiveDate': '2026-06-10',
    });

    final summary1 = FinanceLocalStorage.getPayrollAttendanceSummary(empId1, '2026-06');
    expect(summary1['totalEmployedDays'], equals(15));
    // Verify that Sunday June 21 is NOT forfeited (which would make it 14000)
    expect(summary1['baseSalaryEarned'], equals(15000.0));

    // Scenario 2: Employed 21 June - 30 June (10 days)
    // Joins on Sunday June 21.
    // 2 Sundays in this period: June 21 and June 28.
    // We expect baseSalaryEarned = 10,000 PKR.
    await employeesBox.put(empId2, {
      'id': empId2,
      'localId': empId2,
      'name': 'Proration Employee 2',
      'branchId': 'islamabad',
      'joiningDate': '2026-06-21',
      'currentSalary': 30000.0,
      'isActive': true,
    });

    await historyBox.put('${empId2}_hist', {
      'id': 'hist_${empId2}',
      'amount': 30000.0,
      'effectiveDate': '2026-06-21',
    });

    final summary2 = FinanceLocalStorage.getPayrollAttendanceSummary(empId2, '2026-06');
    expect(summary2['totalEmployedDays'], equals(10));
    // Verify Sunday June 21 is paid (not forfeited due to 0 preceding weekdays)
    expect(summary2['baseSalaryEarned'], equals(10000.0));
  });
}
