// lib/tools/finance_v2_migration.dart

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/local_storage_service.dart';

class FinanceV2Migration {
  static int _toMinor(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val * 100;
    if (val is double) return (val * 100).round();
    if (val is String) {
      final parsed = double.tryParse(val);
      if (parsed != null) return (parsed * 100).round();
    }
    return 0;
  }

  static Future<void> runMigration() async {
    final settingsBox = Hive.box(LocalStorageService.financeSettingsBox);
    const flagKey = 'finance_v2_migrated';

    if (settingsBox.get(flagKey) == true) {
      debugPrint('[FinanceV2Migration] Migration already run. Skipping.');
      return;
    }

    debugPrint('[FinanceV2Migration] Starting GMWF Finance & HR Module v2 Schema Migration...');

    try {
      // 1. Employees migration
      final empBox = Hive.box(LocalStorageService.employeesBox);
      debugPrint('[FinanceV2Migration] Migrating ${empBox.length} employees...');
      for (final key in empBox.keys) {
        final raw = empBox.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          // Only migrate if not already migrated
          if (data['currentSalaryMinor'] == null) {
            data['currentSalaryMinor'] = _toMinor(data['currentSalary']);
            data['monthlyAdvanceInstallmentMinor'] = _toMinor(data['monthlyAdvanceInstallment']);
            data['currentAdvanceBalanceMinor'] = _toMinor(data['currentAdvanceBalance']);
            data['currency'] = 'PKR';
            data['eventVersion'] = 1;
            await empBox.put(key, data);
          }
        }
      }

      // 2. Salary history migration
      final historyBox = Hive.box(LocalStorageService.salaryHistoryBox);
      debugPrint('[FinanceV2Migration] Migrating ${historyBox.length} salary history rows...');
      for (final key in historyBox.keys) {
        final raw = historyBox.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          if (data['rateMinor'] == null) {
            data['rateMinor'] = _toMinor(data['rate']);
            data['currency'] = 'PKR';
            data['eventVersion'] = 1;
            await historyBox.put(key, data);
          }
        }
      }

      // 3. Salary ledger migration
      final ledgerBox = Hive.box(LocalStorageService.salaryLedgerBox);
      debugPrint('[FinanceV2Migration] Migrating ${ledgerBox.length} ledger entries...');
      for (final key in ledgerBox.keys) {
        final raw = ledgerBox.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          if (data['amountMinor'] == null) {
            data['amountMinor'] = _toMinor(data['amount']);
            data['advanceDeductionsMinor'] = _toMinor(data['advanceDeductions']);
            data['currency'] = 'PKR';
            data['periodLocked'] = data['periodLocked'] ?? false;
            data['eventVersion'] = 1;
            data['correctsId'] = data['correctsId'];
            await ledgerBox.put(key, data);
          }
        }
      }

      // 4. Loans migration
      final loansBox = Hive.box(LocalStorageService.financeLoansBox);
      debugPrint('[FinanceV2Migration] Migrating ${loansBox.length} loans...');
      for (final key in loansBox.keys) {
        final raw = loansBox.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          if (data['principalMinor'] == null) {
            data['principalMinor'] = _toMinor(data['principal']);
            data['usualInstallmentMinor'] = _toMinor(data['usualInstallment']);
            data['currency'] = 'PKR';
            data['eventVersion'] = 1;

            if (data['payments'] is List) {
              final list = List<dynamic>.from(data['payments'] as List);
              final migratedPayments = <Map<String, dynamic>>[];
              for (final p in list) {
                if (p is Map) {
                  final pMap = Map<String, dynamic>.from(p);
                  if (pMap['amountMinor'] == null) {
                    pMap['amountMinor'] = _toMinor(pMap['amount']);
                    pMap['currency'] = 'PKR';
                  }
                  migratedPayments.add(pMap);
                }
              }
              data['payments'] = migratedPayments;
            }
            await loansBox.put(key, data);
          }
        }
      }

      // 5. Expenses migration
      final expBox = Hive.box(LocalStorageService.expensesBox);
      debugPrint('[FinanceV2Migration] Migrating ${expBox.length} expenses...');
      for (final key in expBox.keys) {
        final raw = expBox.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          if (data['amountMinor'] == null) {
            data['amountMinor'] = _toMinor(data['amount']);
            data['currency'] = 'PKR';
            data['periodLocked'] = data['periodLocked'] ?? false;
            data['eventVersion'] = 1;
            data['correctsId'] = data['correctsId'];
            await expBox.put(key, data);
          }
        }
      }

      // 6. Validation - run balance-integrity checks
      debugPrint('[FinanceV2Migration] Running balance integrity validation...');
      int mismatchCount = 0;
      for (final key in empBox.keys) {
        final rawEmp = empBox.get(key);
        if (rawEmp is Map) {
          final emp = Map<String, dynamic>.from(rawEmp);
          final empId = emp['id']?.toString() ?? '';
          
          // Recompute outstanding balance from loan logs
          int calculatedOutstandingMinor = 0;
          for (final rawLoan in loansBox.values) {
            if (rawLoan is Map && rawLoan['employeeId'] == empId && rawLoan['status'] == 'active') {
              final pMinor = (rawLoan['principalMinor'] as num?)?.toInt() ?? 0;
              int paymentsPaidMinor = 0;
              final payments = rawLoan['payments'] as List? ?? [];
              for (final p in payments) {
                if (p is Map && p['isVoided'] != true) {
                  paymentsPaidMinor += (p['amountMinor'] as num?)?.toInt() ?? 0;
                }
              }
              calculatedOutstandingMinor += (pMinor - paymentsPaidMinor);
            }
          }

          final cachedOutstandingMinor = (emp['currentAdvanceBalanceMinor'] as num?)?.toInt() ?? 0;
          if (calculatedOutstandingMinor != cachedOutstandingMinor) {
            mismatchCount++;
            debugPrint('[FinanceV2Migration] WARNING: Balance mismatch for Employee ${emp['name']} ($empId). Cached: $cachedOutstandingMinor paisa, Computed: $calculatedOutstandingMinor paisa. Re-syncing cached balance.');
            emp['currentAdvanceBalanceMinor'] = calculatedOutstandingMinor;
            await empBox.put(key, emp);
          }
        }
      }

      await settingsBox.put(flagKey, true);
      await settingsBox.flush();
      debugPrint('[FinanceV2Migration] Schema migration completed successfully. Validation mismatch count resolved: $mismatchCount');
    } catch (e) {
      debugPrint('[FinanceV2Migration] CRITICAL: Schema migration failed with error: $e');
    }
  }
}
