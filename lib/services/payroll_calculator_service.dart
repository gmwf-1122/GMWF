// lib/services/payroll_calculator_service.dart

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'finance_local_storage.dart';
import 'finance_loans_storage.dart';



class PayrollCalculatorService {
  static final PayrollCalculatorService _instance = PayrollCalculatorService._internal();
  factory PayrollCalculatorService() => _instance;
  PayrollCalculatorService._internal();

  static const String _cacheBoxName = 'payroll_cache';

  Future<Box> get _cacheBox async {
    return await Hive.openBox(_cacheBoxName);
  }

  /// Calculates payroll for all employees in a branch for a given month.
  /// First attempts to call the Cloud Function via REST API, then falls back to local computation.
  Future<List<Map<String, dynamic>>> calculatePayroll({
    required String branchId,
    required String monthKey,
  }) async {
    // Perform calculation locally to ensure local rules (such as Sunday pay eligibility) are correct.
    return _calculateOfflineFallback(branchId, monthKey);
  }

  /// Performs local offline payroll calculations using integer minor units (paisa) to avoid rounding drift.
  List<Map<String, dynamic>> _calculateOfflineFallback(String branchId, String monthKey) {
    debugPrint('[PayrollCalculatorService] Running offline payroll math for branch: $branchId, month: $monthKey');
    final employees = FinanceLocalStorage.getEmployees(branchId);
    final results = <Map<String, dynamic>>[];

    for (final emp in employees) {
      final employeeId = emp['localId'] as String;
      final employeeName = emp['name'] as String? ?? 'Unknown';

      // 1. Fetch attendance & salary details
      final summary = FinanceLocalStorage.getPayrollAttendanceSummary(employeeId, monthKey);
      
      // Derive per-day and earned salary from attendance summary to ensure
      // consistent rules across UI and service.
      final int totalDays = (summary['totalDays'] as num?)?.toInt() ?? 30;
      final int totalEmployedDays = (summary['totalEmployedDays'] as num?)?.toInt() ?? 0;
      final double absentDays = (summary['absentDays'] as num?)?.toDouble() ?? 0.0;
      final double unpaidLeaves = (summary['unpaidLeaves'] as num?)?.toDouble() ?? 0.0;
      final double sundayOvertimeDays = (summary['sundayOvertimeDays'] as num?)?.toDouble() ?? 0.0;
      final double holidayBonusDouble = (summary['holidayBonus'] as num?)?.toDouble() ?? 0.0;
      final double sundayOvertimeBonusDouble = (summary['sundayOvertimeBonus'] as num?)?.toDouble() ?? 0.0;
      final double absenceDeductionsDouble = (summary['absenceDeductions'] as num?)?.toDouble() ?? 0.0;
      final double fullMonthWeightedSalary = (summary['fullMonthWeightedSalary'] as num?)?.toDouble() ?? 0.0;

      final double perDay = totalDays > 0 ? (fullMonthWeightedSalary / totalDays) : 0.0;
      final double paidDays = (totalEmployedDays.toDouble() - absentDays - unpaidLeaves).clamp(0.0, double.infinity);
      final double baseSalaryDouble = perDay * (paidDays + sundayOvertimeDays);

      // 2. Convert to minor units (paisa)
      final baseSalaryMinor = (baseSalaryDouble * 100).round();
      final absenceDeductionsMinor = (absenceDeductionsDouble * 100).round();
      final holidayBonusMinor = (holidayBonusDouble * 100).round();
      final sundayOvertimeBonusMinor = (sundayOvertimeBonusDouble * 100).round();

      // 3. Compute Gross Salary
      final grossSalaryMinor = baseSalaryMinor + holidayBonusMinor + sundayOvertimeBonusMinor - absenceDeductionsMinor;

      // 4. Calculate outstanding advance/loans installment recovery
      final activeLoans = FinanceLoansStorage.getLoansForEmployee(employeeId)
          .where((l) => l['status'] == 'active')
          .toList();

      double outstandingLoansTotalDouble = 0.0;
      for (final loan in activeLoans) {
        outstandingLoansTotalDouble += FinanceLoansStorage.getLoanBalance(loan);
      }
      final outstandingLoansTotalMinor = (outstandingLoansTotalDouble * 100).round();

      // Installment from profile
      final double monthlyInstallmentDouble = (emp['monthlyAdvanceInstallment'] as num?)?.toDouble() ?? 0.0;
      final monthlyInstallmentMinor = (monthlyInstallmentDouble * 100).round();

      // Recovery is the minimum of the outstanding balance and the scheduled installment
      int advanceInstallmentMinor = 0;
      if (outstandingLoansTotalMinor > 0) {
        advanceInstallmentMinor = monthlyInstallmentMinor < outstandingLoansTotalMinor
            ? monthlyInstallmentMinor
            : outstandingLoansTotalMinor;
      }

      // Recovery cannot exceed gross salary
      if (advanceInstallmentMinor > grossSalaryMinor) {
        advanceInstallmentMinor = grossSalaryMinor.clamp(0, advanceInstallmentMinor);
      }

      // 5. Compute Net Salary
      final netSalaryMinor = grossSalaryMinor - advanceInstallmentMinor;

      results.add({
        'employeeId': employeeId,
        'employeeName': employeeName,
        'baseSalaryEarnedMinor': baseSalaryMinor,
        'absenceDeductionsMinor': absenceDeductionsMinor,
        'holidayBonusMinor': holidayBonusMinor,
        'sundayOvertimeBonusMinor': sundayOvertimeBonusMinor,
        'grossSalaryMinor': grossSalaryMinor,
        'advanceInstallmentMinor': advanceInstallmentMinor,
        'netSalaryMinor': netSalaryMinor,
        // Legacy fields for UI binding compatibility
        'baseSalaryEarned': baseSalaryMinor / 100.0,
        'absenceDeductions': absenceDeductionsMinor / 100.0,
        'holidayBonus': holidayBonusMinor / 100.0,
        'sundayOvertimeBonus': sundayOvertimeBonusMinor / 100.0,
        'grossSalary': grossSalaryMinor / 100.0,
        'advanceInstallment': advanceInstallmentMinor / 100.0,
        'netSalary': netSalaryMinor / 100.0,
        'isCalculatedByServer': false,
      });
    }

    return results;
  }
}
