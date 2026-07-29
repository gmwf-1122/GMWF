// lib/services/finance_loans_storage.dart

import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'local_storage_service.dart';

/// Tracks employee loans/advances completely separately from salary.
/// A loan's balance never affects payroll math — repayments are their
/// own transactions, logged whenever they actually happen.
class FinanceLoansStorage {
  static const Uuid _uuid = Uuid();

  static Box get loansBox => Hive.box(LocalStorageService.financeLoansBox);
  static Box get _auditLogsBox => Hive.box(LocalStorageService.auditLogsBox);
  static Box get _settingsBox => Hive.box(LocalStorageService.financeSettingsBox);

  static String _newId() => _uuid.v4();
  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) {
      if (v is DateTime) {
        out[k] = v.toIso8601String();
      } else if (v is Map) {
        out[k] = _sanitize(Map<String, dynamic>.from(v));
      } else if (v is List) {
        out[k] = v.map((e) => e is Map ? _sanitize(Map<String, dynamic>.from(e)) : e).toList();
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  static Future<void> _logLoanAction({
    required String branchId,
    required String entityId,
    required String action,
    required String performedBy,
    String? reason,
  }) async {
    final id = _newId();
    final now = _nowIso();
    final entry = _sanitize({
      'id': id,
      'localId': id,
      'remoteId': null,
      'updatedAt': now,
      'syncStatus': 'pending',
      'module': 'finance',
      'entityType': 'loan',
      'entityId': entityId,
      'action': action,
      'performedBy': performedBy,
      'reason': reason,
      'branchContext': branchId,
      'timestamp': now,
    });
    await _auditLogsBox.put(id, entry);
    await _auditLogsBox.flush();
    await LocalStorageService.enqueueSync({
      'type': 'save_audit_log',
      'branchId': branchId,
      'data': entry,
    });
  }

  // -- Create a loan/advance -----------------------------------------------
  /// repaymentType: 'fixed' (expected monthly amount, we flag missed months)
  ///             or 'flexible' (no expectation, just log whatever comes in)
  static Future<String> createLoan({
    required String branchId,
    required String employeeId,
    required String employeeName,
    required double principal,
    required String repaymentType, // 'fixed' | 'flexible'
    double usualInstallment = 0.0,
    String reason = '',
    DateTime? dateIssued,
    required String performedBy,
  }) async {
    if (principal <= 0) {
      throw Exception('Loan amount must be greater than zero.');
    }
    final issued = dateIssued ?? DateTime.now();

    // Month Lock Check
    final monthKey = DateFormat('yyyy-MM').format(issued);
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('Loans cannot be issued in a closed and locked month: $monthKey');
    }

    // Check if employee already has an active loan
    final activeLoans = getActiveLoansForEmployee(employeeId);
    if (activeLoans.isNotEmpty) {
      final existingLoan = Map<String, dynamic>.from(activeLoans.first);
      final loanId = existingLoan['id'] as String;
      final now = _nowIso();

      final payments = List<Map<String, dynamic>>.from(
        (existingLoan['payments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final topupId = _newId();
      payments.add({
        'id': topupId,
        'date': issued.toIso8601String(),
        'amount': principal,
        'amountMinor': (principal * 100).round(),
        'currency': 'PKR',
        'note': reason.trim().isNotEmpty ? reason.trim() : 'Additional loan top-up.',
        'recordedBy': performedBy,
        'isVoided': false,
        'createdAt': now,
        'type': 'topup',
      });

      existingLoan['payments'] = payments;
      existingLoan['principal'] = (existingLoan['principal'] as num).toDouble() + principal;
      existingLoan['principalMinor'] = (existingLoan['principalMinor'] as num).toInt() + (principal * 100).round();
      existingLoan['updatedAt'] = now;
      existingLoan['syncStatus'] = 'pending';

      if (repaymentType == 'fixed' && usualInstallment > 0) {
        existingLoan['usualInstallment'] = usualInstallment;
        existingLoan['usualInstallmentMinor'] = (usualInstallment * 100).round();
      }

      final sanitized = _sanitize(existingLoan);
      await loansBox.put(loanId, sanitized);
      await loansBox.flush();

      await LocalStorageService.enqueueSync({
        'type': 'save_finance_loan',
        'branchId': branchId,
        'loanId': loanId,
        'data': sanitized,
      });

      await _logLoanAction(
        branchId: branchId,
        entityId: loanId,
        action: 'topup',
        performedBy: performedBy,
        reason: 'Added PKR ${principal.toStringAsFixed(0)} to existing active loan for $employeeName. New Principal: PKR ${existingLoan['principal'].toStringAsFixed(0)}',
      );

      return loanId;
    }

    final id = _newId();
    final now = _nowIso();

    final record = _sanitize({
      'id': id,
      'localId': id,
      'remoteId': null,
      'branchId': branchId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'principal': principal,
      'principalMinor': (principal * 100).round(),
      'usualInstallment': usualInstallment,
      'usualInstallmentMinor': (usualInstallment * 100).round(),
      'currency': 'PKR',
      'eventVersion': 1,
      'dateIssued': issued.toIso8601String(),
      'reason': reason.trim().isNotEmpty ? reason.trim() : 'Loan issued.',
      'repaymentType': repaymentType,
      'status': 'active',
      'payments': <Map<String, dynamic>>[],
      'createdAt': now,
      'updatedAt': now,
      'syncStatus': 'pending',
      'closedAt': null,
      'closeReason': null,
    });

    await loansBox.put(id, record);
    await loansBox.flush();

    await LocalStorageService.enqueueSync({
      'type': 'save_finance_loan',
      'branchId': branchId,
      'loanId': id,
      'data': record,
    });

    await _logLoanAction(
      branchId: branchId,
      entityId: id,
      action: 'create',
      performedBy: performedBy,
      reason: 'Issued loan of PKR ${principal.toStringAsFixed(0)} to $employeeName'
          '${repaymentType == 'fixed' ? ' (fixed installment PKR ${usualInstallment.toStringAsFixed(0)}/mo)' : ' (flexible repayment)'}',
    );

    return id;
  }

  // -- Record a repayment against a loan ------------------------------------
  static Future<String> recordPayment({
    required String loanId,
    required double amount,
    DateTime? date,
    String note = '',
    required String performedBy,
  }) async {
    if (amount <= 0) {
      throw Exception('Repayment amount must be greater than zero.');
    }
    final raw = loansBox.get(loanId);
    if (raw == null || raw is! Map) {
      throw Exception('Loan not found.');
    }
    final loan = Map<String, dynamic>.from(raw);
    if (loan['status'] == 'closed') {
      throw Exception('This loan is already closed/paid off.');
    }

    final payDate = date ?? DateTime.now();

    // Month Lock Check
    final monthKey = DateFormat('yyyy-MM').format(payDate);
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('Repayments cannot be recorded in a closed and locked month: $monthKey');
    }

    final currentBalance = getLoanBalance(loan);
    if (amount > currentBalance + 0.01) {
      throw Exception(
          'Payment (PKR ${amount.toStringAsFixed(0)}) exceeds remaining balance (PKR ${currentBalance.toStringAsFixed(0)}).');
    }

    final paymentId = _newId();
    final now = _nowIso();

    final payments = List<Map<String, dynamic>>.from(
      (loan['payments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    payments.add({
      'id': paymentId,
      'date': payDate.toIso8601String(),
      'amount': amount,
      'amountMinor': (amount * 100).round(),
      'currency': 'PKR',
      'note': note.trim(),
      'recordedBy': performedBy,
      'isVoided': false,
      'createdAt': now,
    });

    loan['payments'] = payments;
    loan['updatedAt'] = now;
    loan['syncStatus'] = 'pending';

    final newBalance = getLoanBalance(loan);
    if (newBalance <= 0.01) {
      loan['status'] = 'closed';
      loan['closedAt'] = now;
      loan['closeReason'] = 'Fully repaid.';
    }

    final sanitized = _sanitize(loan);
    await loansBox.put(loanId, sanitized);
    await loansBox.flush();

    await LocalStorageService.enqueueSync({
      'type': 'save_finance_loan',
      'branchId': loan['branchId'],
      'loanId': loanId,
      'data': sanitized,
    });

    await _logLoanAction(
      branchId: loan['branchId']?.toString() ?? '',
      entityId: loanId,
      action: 'repayment',
      performedBy: performedBy,
      reason: '${loan['employeeName']} paid PKR ${amount.toStringAsFixed(0)} towards loan'
          '${newBalance <= 0.01 ? ' (loan fully closed)' : ' (remaining: PKR ${newBalance.toStringAsFixed(0)})'}',
    );

    return paymentId;
  }

  // -- Void a mistaken payment entry ----------------------------------------
  static Future<void> voidPayment({
    required String loanId,
    required String paymentId,
    required String performedBy,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception('A reason is required to void a payment.');
    }
    final raw = loansBox.get(loanId);
    if (raw == null || raw is! Map) throw Exception('Loan not found.');
    final loan = Map<String, dynamic>.from(raw);

    final payments = List<Map<String, dynamic>>.from(
      (loan['payments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final idx = payments.indexWhere((p) => p['id'] == paymentId);
    if (idx == -1) throw Exception('Payment not found.');

    final dateStr = payments[idx]['date']?.toString() ?? '';
    if (dateStr.isNotEmpty) {
      final monthKey = dateStr.substring(0, 7);
      final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
      if (isLocked) {
        throw Exception('Repayments in a closed and locked month ($monthKey) cannot be voided.');
      }
    }

    final payType = payments[idx]['type']?.toString();
    final isTopup = payType == 'topup' || payType == 'loan_issue';
    final double amt = (payments[idx]['amount'] as num?)?.toDouble() ?? 0.0;

    payments[idx]['isVoided'] = true;
    payments[idx]['voidedBy'] = performedBy;
    payments[idx]['voidReason'] = reason.trim();
    payments[idx]['voidedAt'] = _nowIso();

    if (isTopup) {
      loan['principal'] = (loan['principal'] as num).toDouble() - amt;
      loan['principalMinor'] = (loan['principalMinor'] as num).toInt() - (amt * 100).round();
    }

    loan['payments'] = payments;
    loan['updatedAt'] = _nowIso();
    loan['syncStatus'] = 'pending';
    // Voiding a payment can never leave a loan "closed" if balance re-opens
    if (loan['status'] == 'closed' && getLoanBalance(loan) > 0.01) {
      loan['status'] = 'active';
      loan['closedAt'] = null;
      loan['closeReason'] = null;
    }

    final sanitized = _sanitize(loan);
    await loansBox.put(loanId, sanitized);
    await loansBox.flush();

    await LocalStorageService.enqueueSync({
      'type': 'save_finance_loan',
      'branchId': loan['branchId'],
      'loanId': loanId,
      'data': sanitized,
    });

    await _logLoanAction(
      branchId: loan['branchId']?.toString() ?? '',
      entityId: loanId,
      action: 'void_payment',
      performedBy: performedBy,
      reason: 'Voided a repayment entry: $reason',
    );
  }

  // -- Manually close a loan (write-off / forgiveness) ----------------------
  static Future<void> closeLoanManually({
    required String loanId,
    required String performedBy,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception('A reason is required to close a loan manually.');
    }
    final raw = loansBox.get(loanId);
    if (raw == null || raw is! Map) throw Exception('Loan not found.');
    final loan = Map<String, dynamic>.from(raw);

    // Period Lock Check
    final monthKey = DateFormat('yyyy-MM').format(DateTime.now());
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('Loans cannot be closed manually in a closed and locked month: $monthKey');
    }

    loan['status'] = 'closed';
    loan['closedAt'] = _nowIso();
    loan['closeReason'] = reason.trim();
    loan['updatedAt'] = _nowIso();
    loan['syncStatus'] = 'pending';

    final sanitized = _sanitize(loan);
    await loansBox.put(loanId, sanitized);
    await loansBox.flush();

    await LocalStorageService.enqueueSync({
      'type': 'save_finance_loan',
      'branchId': loan['branchId'],
      'loanId': loanId,
      'data': sanitized,
    });

    await _logLoanAction(
      branchId: loan['branchId']?.toString() ?? '',
      entityId: loanId,
      action: 'manual_close',
      performedBy: performedBy,
      reason: 'Closed loan manually: $reason',
    );
  }

  // -- Queries ---------------------------------------------------------------
  static double getLoanBalance(Map<String, dynamic> loan) {
    final pMinor = (loan['principalMinor'] as num?)?.toInt() ?? (((loan['principal'] as num?)?.toDouble() ?? 0.0) * 100).round();
    final payments = (loan['payments'] as List? ?? []);
    int paidMinor = 0;
    for (final p in payments) {
      if (p is! Map) continue;
      if (p['isVoided'] == true) continue;
      if (p['type'] == 'topup' || p['type'] == 'loan_issue') continue;
      paidMinor += (p['amountMinor'] as num?)?.toInt() ?? (((p['amount'] as num?)?.toDouble() ?? 0.0) * 100).round();
    }
    return ((pMinor - paidMinor) / 100).clamp(0.0, double.infinity);
  }

  static List<Map<String, dynamic>> getLoansForEmployee(String employeeId) {
    final list = <Map<String, dynamic>>[];
    for (final val in loansBox.values) {
      if (val is! Map) continue;
      final loan = Map<String, dynamic>.from(val);
      if (loan['employeeId'] == employeeId) list.add(loan);
    }
    list.sort((a, b) => (b['dateIssued']?.toString() ?? '').compareTo(a['dateIssued']?.toString() ?? ''));
    return list;
  }

  static List<Map<String, dynamic>> getActiveLoansForEmployee(String employeeId) {
    return getLoansForEmployee(employeeId).where((l) => l['status'] == 'active').toList();
  }

  static double getOutstandingBalance(String employeeId) {
    double total = 0.0;
    for (final loan in getActiveLoansForEmployee(employeeId)) {
      total += getLoanBalance(loan);
    }
    return total;
  }

  /// For 'fixed' loans -- has this month's usual installment been met?
  static Map<String, dynamic> getMonthlyRepaymentStatus(Map<String, dynamic> loan, String monthKey) {
    final usual = (loan['usualInstallment'] as num?)?.toDouble() ?? 0.0;
    final payments = (loan['payments'] as List? ?? []);
    double paidThisMonth = 0.0;
    for (final p in payments) {
      if (p is! Map) continue;
      if (p['isVoided'] == true) continue;
      final dateStr = p['date']?.toString() ?? '';
      if (dateStr.length >= 7 && dateStr.substring(0, 7) == monthKey) {
        paidThisMonth += (p['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return {
      'expected': usual,
      'paid': paidThisMonth,
      'met': loan['repaymentType'] != 'fixed' || usual <= 0 || paidThisMonth >= usual - 0.01,
    };
  }

  static List<Map<String, dynamic>> getAllLoansForBranch(String branchId, {bool activeOnly = true}) {
    final list = <Map<String, dynamic>>[];
    final isGlobal = branchId == 'all' || branchId.isEmpty;
    for (final val in loansBox.values) {
      if (val is! Map) continue;
      final loan = Map<String, dynamic>.from(val);
      if (!isGlobal && loan['branchId'] != branchId) continue;
      if (activeOnly && loan['status'] != 'active') continue;
      list.add(loan);
    }
    list.sort((a, b) => (b['dateIssued']?.toString() ?? '').compareTo(a['dateIssued']?.toString() ?? ''));
    return list;
  }

  // -- One-time migration from the old advance_payment/advanceDeductions
  //    ledger entries into the new Loan model. Safe to call multiple times --
  //    it no-ops after the first successful run. ----------------------------
  static Future<void> migrateLegacyAdvancesToLoans({required String performedBy}) async {
    final flagKey = 'legacy_advances_migrated_v1';
    if (_settingsBox.get(flagKey) == true) return;

    final ledgerBox = Hive.box(LocalStorageService.salaryLedgerBox);
    final employeesBox = Hive.box(LocalStorageService.employeesBox);

    // employeeId -> { issued: double, recovered: double, earliestDate, branchId, name }
    final Map<String, Map<String, dynamic>> agg = {};

    for (final val in ledgerBox.values) {
      if (val is! Map) continue;
      final entry = Map<String, dynamic>.from(val);
      if (entry['isVoided'] == true) continue;
      final empId = entry['employeeId']?.toString();
      if (empId == null || empId.isEmpty) continue;

      agg.putIfAbsent(empId, () => {
            'issued': 0.0,
            'recovered': 0.0,
            'earliestDate': entry['date']?.toString() ?? DateTime.now().toIso8601String(),
            'employeeName': entry['employeeName']?.toString() ?? 'Unknown',
          });

      final type = entry['type']?.toString();
      if (type == 'advance_payment') {
        agg[empId]!['issued'] += (entry['amount'] as num?)?.toDouble() ?? 0.0;
        final d = entry['date']?.toString();
        if (d != null && d.compareTo(agg[empId]!['earliestDate']) < 0) {
          agg[empId]!['earliestDate'] = d;
        }
      } else if (type == 'payout') {
        agg[empId]!['recovered'] += (entry['advanceDeductions'] as num?)?.toDouble() ?? 0.0;
      }
    }

    for (final entry in agg.entries) {
      final empId = entry.key;
      final issued = entry.value['issued'] as double;
      final recovered = entry.value['recovered'] as double;
      final remaining = (issued - recovered).clamp(0.0, double.infinity);
      if (remaining <= 0.01) continue;

      final empRaw = employeesBox.get(empId);
      final branchId = empRaw is Map ? (empRaw['branchId']?.toString() ?? '') : '';
      final name = entry.value['employeeName'] as String;
      final earliest = DateTime.tryParse(entry.value['earliestDate'] as String) ?? DateTime.now();

      await createLoan(
        branchId: branchId,
        employeeId: empId,
        employeeName: name,
        principal: remaining,
        repaymentType: 'flexible',
        usualInstallment: 0.0,
        reason: 'Migrated outstanding legacy advance balance.',
        dateIssued: earliest,
        performedBy: performedBy,
      );
    }

    await _settingsBox.put(flagKey, true);
    await _settingsBox.flush();
  }
}
