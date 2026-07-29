import 'dart:io';
import 'package:hive/hive.dart';
import 'package:gmwf/services/finance_local_storage.dart';
import 'package:gmwf/services/payroll_calculator_service.dart';

void main() async {
  final path = r'C:\Users\win\AppData\Roaming\com.example\gmwf\gmwf_hive';
  Hive.init(path);
  
  // Open the required boxes
  await Hive.openBox('local_employees');
  await Hive.openBox('local_salary_history');
  await Hive.openBox('local_employee_attendance');
  await Hive.openBox('local_employee_salaries');
  await Hive.openBox('local_finance_settings');
  await Hive.openBox('local_employee_branch_transfers');
  await Hive.openBox('local_audit_logs');
  await Hive.openBox('local_finance_loans');
  await Hive.openBox('local_finance_holidays');

  final empId = '6e9fe8e6-0c26-4084-ac36-9b401275925f'; // ANS SULEMAN
  final monthKey = '2026-07';
  
  final summary = FinanceLocalStorage.getPayrollAttendanceSummary(empId, monthKey);
  print('=== Summary from FinanceLocalStorage ===');
  print('Total days in month: ${summary['totalDays']}');
  print('Total employed days: ${summary['totalEmployedDays']}');
  print('Working days: ${summary['workingDays']}');
  print('Absent days: ${summary['absentDays']}');
  print('Unpaid leaves: ${summary['unpaidLeaves']}');
  print('Base salary earned: ${summary['baseSalaryEarned']}');
  
  final results = await PayrollCalculatorService().calculatePayroll(
    branchId: 'gujrat',
    monthKey: monthKey,
  );
  
  final empResult = results.firstWhere((r) => r['employeeId'] == empId);
  print('\n=== Result from PayrollCalculatorService ===');
  print('Employee: ${empResult['employeeName']}');
  print('Base Salary Earned: ${empResult['baseSalaryEarned']}');
  print('Net Salary: ${empResult['netSalary']}');
}
