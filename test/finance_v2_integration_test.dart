import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/finance_local_storage.dart';
import 'package:gmwf/services/finance_loans_storage.dart';
import 'package:gmwf/services/finance_expenses_storage.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/payroll_calculator_service.dart';

void main() {
  setUpAll(() async {
    final tempDir = Directory.systemTemp.createTempSync();
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.financeSettingsBox);
    await Hive.openBox(LocalStorageService.employeesBox);
    await Hive.openBox(LocalStorageService.salaryHistoryBox);
    await Hive.openBox(LocalStorageService.salaryLedgerBox);
    await Hive.openBox(LocalStorageService.financeLoansBox);
    await Hive.openBox(LocalStorageService.expensesBox);
    await Hive.openBox(LocalStorageService.attendanceBox);
    await Hive.openBox(LocalStorageService.financeHolidaysBox);
    await Hive.openBox(LocalStorageService.auditLogsBox);
    await Hive.openBox(LocalStorageService.branchTransfersBox);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.usersBox);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    await Hive.box(LocalStorageService.financeSettingsBox).clear();
    await Hive.box(LocalStorageService.employeesBox).clear();
    await Hive.box(LocalStorageService.salaryHistoryBox).clear();
    await Hive.box(LocalStorageService.salaryLedgerBox).clear();
    await Hive.box(LocalStorageService.financeLoansBox).clear();
    await Hive.box(LocalStorageService.expensesBox).clear();
    await Hive.box(LocalStorageService.attendanceBox).clear();
    await Hive.box(LocalStorageService.financeHolidaysBox).clear();
    await Hive.box(LocalStorageService.auditLogsBox).clear();
    await Hive.box(LocalStorageService.branchTransfersBox).clear();
    await Hive.box(LocalStorageService.syncBox).clear();
    await Hive.box(LocalStorageService.usersBox).clear();
  });

  group('Finance Rewrite v2 Integration Tests', () {
    test('Employee creation converts double PKR to integer paisa (minor units)', () async {
      final empId = await FinanceLocalStorage.saveEmployee(
        branchId: 'gujrat',
        data: {
          'name': 'Test Employee',
          'joiningDate': '2026-01-01',
          'cnic': '34101-1234567-1',
          'currentSalary': 45000.50, // 45000.50 PKR
          'monthlyAdvanceInstallment': 5000.0,
          'isActive': true,
        },
        performedBy: 'Test Admin',
      );

      final emp = FinanceLocalStorage.getEmployee(empId);
      expect(emp, isNotNull);
      expect(emp!['currentSalaryMinor'], equals(4500050)); // paisa
      expect(emp['monthlyAdvanceInstallmentMinor'], equals(500000));
    });

    test('Period lock checks block writes on locked months', () async {
      final settings = Hive.box(LocalStorageService.financeSettingsBox);
      await settings.put('month_lock_2026-06', true); // Lock June 2026

      // Attempting to record attendance in June 2026 should fail
      expect(
        () => FinanceLocalStorage.saveAttendanceRecord(
          branchId: 'gujrat',
          data: {
            'employeeId': 'emp_123',
            'date': '2026-06-15',
            'status': 'present',
          },
          performedBy: 'Admin',
        ),
        throwsA(isA<Exception>()),
      );

      // Attempting to save expense in June 2026 should fail
      expect(
        () => FinanceExpensesStorage.saveExpense(
          branchId: 'gujrat',
          amount: 250.0,
          category: 'Office',
          description: 'Supplies',
          performedBy: 'user_1',
          performedByName: 'User',
          date: DateTime(2026, 6, 10),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Payroll Calculator service offline fallback handles minor units correctly', () async {
      // Setup base employee
      final empId = await FinanceLocalStorage.saveEmployee(
        branchId: 'gujrat',
        data: {
          'id': 'emp_abc',
          'name': 'Ali Khan',
          'joiningDate': '2026-01-01',
          'cnic': '34101-1234567-1',
          'currentSalary': 30000.0,
          'monthlyAdvanceInstallment': 0.0,
          'isActive': true,
        },
        performedBy: 'Admin',
      );

      // Register initial salary rate
      await FinanceLocalStorage.saveSalaryHistory(
        branchId: 'gujrat',
        employeeId: empId,
        amount: 30000.0,
        effectiveDate: DateTime(2026, 1, 1),
        reason: 'Onboarding',
        approvedBy: 'Admin',
        performedBy: 'Admin',
      );

      // Log attendance for June 2026 (30 days total)
      // We log 2 absences
      for (int d = 1; d <= 30; d++) {
        final dateStr = '2026-06-${d.toString().padLeft(2, '0')}';
        final status = (d == 5 || d == 12) ? 'absent' : 'present';
        await FinanceLocalStorage.saveAttendanceRecord(
          branchId: 'gujrat',
          data: {
            'employeeId': empId,
            'date': dateStr,
            'status': status,
          },
          performedBy: 'Admin',
        );
      }

      // Run local calculator calculation directly
      final result = await PayrollCalculatorService().calculatePayroll(
        branchId: 'gujrat',
        monthKey: '2026-06',
      );

      expect(result, isNotEmpty);
      final item = result.firstWhere((r) => r['employeeId'] == empId);
      expect(item, isNotNull);

      // Base salary: 30,000.0 PKR
      // Daily rate: 30,000 / 30 = 1,000.0 PKR
      // Absences: 2 days => Deductions: 2,000.0 PKR
      // Net salary: 28,000.0 PKR (2,800,000 paisa)
      expect(item['baseSalaryEarned'], equals(30000.0));
      expect(item['absenceDeductions'], equals(2000.0));
      expect(item['netSalary'], equals(28000.0));
    });
  });
}
