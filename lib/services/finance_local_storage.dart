// lib/services/finance_local_storage.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'local_storage_service.dart';
import 'finance_loans_storage.dart';
import 'finance_ledger_storage.dart';


class FinanceLocalStorage {
  static const Uuid _uuid = Uuid();

  // ── Box Accessors ─────────────────────────────────────────────────────────
  static Box get employeesBox => Hive.box(LocalStorageService.employeesBox);
  static Box get salaryHistoryBox => Hive.box(LocalStorageService.salaryHistoryBox);
  static Box get attendanceBox => Hive.box(LocalStorageService.attendanceBox);
  static Box get salaryLedgerBox => Hive.box(LocalStorageService.salaryLedgerBox);
  static Box get settingsBox => Hive.box(LocalStorageService.financeSettingsBox);
  static Box get transfersBox => Hive.box(LocalStorageService.branchTransfersBox);
  static Box get auditLogsBox => Hive.box(LocalStorageService.auditLogsBox);

  // ── Serialization Helpers ──────────────────────────────────────────────────
  static Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) => out[k] = _val(v));
    return out;
  }

  static dynamic _val(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is int) return v;
    if (v is double) return v;
    if (v is bool) return v;
    if (v is DateTime) return v.toIso8601String();
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is Map) return _sanitize(Map<String, dynamic>.from(v));
    if (v is List) return v.map(_val).toList();
    debugPrint('[FinanceLS] _sanitize WARNING: dropping ${v.runtimeType} for value $v');
    return null;
  }

  static String _newLocalId() => _uuid.v4();
  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  // ── Quota-Guard: TTL-based refresh throttle ────────────────────────────────
  // Returns true if enough time has passed since the last successful sync of
  // [key], meaning a fresh download should be performed. Stores the timestamp
  // in the finance settings box so it persists across restarts.
  static bool _shouldRefresh(String key, {Duration ttl = const Duration(minutes: 5)}) {
    try {
      final box = Hive.box(LocalStorageService.financeSettingsBox);
      final raw = box.get('__sync_ts_$key') as String?;
      if (raw == null) return true;
      final last = DateTime.tryParse(raw);
      if (last == null) return true;
      return DateTime.now().difference(last) > ttl;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _markRefreshed(String key) async {
    try {
      final box = Hive.box(LocalStorageService.financeSettingsBox);
      await box.put('__sync_ts_$key', DateTime.now().toUtc().toIso8601String());
    } catch (_) {}
  }

  // Force the next call to re-download regardless of TTL.
  static Future<void> invalidateCache(String key) async {
    try {
      final box = Hive.box(LocalStorageService.financeSettingsBox);
      await box.delete('__sync_ts_$key');
    } catch (_) {}
  }

  // ── Helper: Recalculate Advance Balance (Atomic Local Rule) ───────────────
  static double getAdvanceBalance(String employeeId) {
    return FinanceLoansStorage.getOutstandingBalance(employeeId);
  }

  // ── AUDIT LOG WRITER ──────────────────────────────────────────────────────
  static Future<void> logAction({
    required String branchId,
    required String entityType,
    required String entityId,
    required String action,
    required String performedBy,
    String? approvedBy,
    String? reason,
    List<Map<String, dynamic>>? fieldChanges,
    Map<String, dynamic>? rawData,
  }) async {
    final localId = _newLocalId();
    final now = _nowIso();

    final auditMap = {
      'id': localId,
      'localId': localId,
      'remoteId': null,
      'updatedAt': now,
      'syncStatus': 'pending',
      'module': 'finance',
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'fieldChanges': fieldChanges,
      'performedBy': performedBy,
      'approvedBy': approvedBy,
      'reason': reason,
      'branchContext': branchId,
      'timestamp': now,
    };

    final sanitized = _sanitize(auditMap);
    await auditLogsBox.put(localId, sanitized);
    await auditLogsBox.flush();

    // Mirror to sync queue
    await LocalStorageService.enqueueSync({
      'type': 'save_audit_log',
      'branchId': branchId,
      'data': sanitized,
    });
  }

  // ── Employees Operations ──────────────────────────────────────────────────
  static Future<String> saveEmployee({
    required String branchId,
    required Map<String, dynamic> data,
    required String performedBy,
  }) async {
    final localId = data['localId'] as String? ?? _newLocalId();
    final isNew = !employeesBox.containsKey(localId);
    final now = _nowIso();

    // CNIC validation check — only if CNIC is provided
    final cnic = (data['cnic'] as String? ?? '').trim();
    if (cnic.isNotEmpty) {
      final cnicRegex = RegExp(r'^\d{5}-\d{7}-\d{1}$');
      if (!cnicRegex.hasMatch(cnic)) {
        throw Exception('Invalid CNIC format. Expected XXXXX-XXXXXXX-X');
      }

      // CNIC Duplicate check (excluding current employee being updated)
      for (final key in employeesBox.keys) {
        if (key == localId) continue;
        final val = employeesBox.get(key);
        if (val is Map) {
          final existingCnic = val['cnic']?.toString() ?? '';
          if (existingCnic == cnic) {
            final existingName = val['name']?.toString() ?? 'Unknown';
            throw Exception('An employee is already registered with CNIC $cnic (Name: $existingName)');
          }
        }
      }
    }

    Map<String, dynamic> oldRecord = {};
    if (!isNew) {
      final existing = employeesBox.get(localId);
      if (existing is Map) {
        oldRecord = Map<String, dynamic>.from(existing);
      }
    }

    final record = Map<String, dynamic>.from(data);
    record['id'] = localId;
    record['localId'] = localId;
    record['remoteId'] = oldRecord['remoteId'];
    record['branchId'] = branchId;
    record['updatedAt'] = now;
    record['syncStatus'] = 'pending';
    record['isActive'] = record['isActive'] ?? true;
    record['status'] = record['status'] ?? 'Active';
    record['createdAt'] = oldRecord['createdAt'] ?? now;
    record['createdBy'] = oldRecord['createdBy'] ?? performedBy;

    // Convert money to minor units (paisa)
    final double salary = (record['currentSalary'] as num?)?.toDouble() ?? 0.0;
    final double installment = (record['monthlyAdvanceInstallment'] as num?)?.toDouble() ?? 0.0;
    final double advBalance = getAdvanceBalance(localId);

    record['currentSalaryMinor'] = (salary * 100).round();
    record['monthlyAdvanceInstallmentMinor'] = (installment * 100).round();
    record['currentAdvanceBalanceMinor'] = (advBalance * 100).round();
    record['currentSalary'] = salary;
    record['monthlyAdvanceInstallment'] = installment;
    record['currentAdvanceBalance'] = advBalance;
    record['currency'] = 'PKR';
    record['eventVersion'] = 1;

    final sanitized = _sanitize(record);
    await employeesBox.put(localId, sanitized);
    await employeesBox.flush();

    // Logging Audit Trail
    if (isNew) {
      await logAction(
        branchId: branchId,
        entityType: 'employee',
        entityId: localId,
        action: 'create',
        performedBy: performedBy,
        reason: 'Added employee: ${sanitized["name"]} as ${sanitized["role"]}',
        rawData: sanitized,
      );
    } else {
      final List<Map<String, dynamic>> changes = [];
      final monitoredFields = [
        'name', 'dob', 'cnic', 'cnicExpiry', 'phone', 'alternatePhone',
        'relationshipName', 'relationshipType', 'maritalStatus', 'role', 'department',
        'joiningDate', 'compensationType', 'currentSalary', 'bankName', 'bankAccount',
        'education', 'currentAddress', 'monthlyAdvanceInstallment', 'gender'
      ];
      for (final f in monitoredFields) {
        final oldVal = oldRecord[f];
        final newVal = record[f];
        if (oldVal != newVal) {
          changes.add({'field': f, 'oldValue': oldVal, 'newValue': newVal});
        }
      }
      final oldWinter = oldRecord['workScheduleOverride']?['winter'];
      final newWinter = record['workScheduleOverride']?['winter'];
      if (oldWinter != newWinter) {
        changes.add({'field': 'winterShift', 'oldValue': oldWinter, 'newValue': newWinter});
      }
      final oldSummer = oldRecord['workScheduleOverride']?['summer'];
      final newSummer = record['workScheduleOverride']?['summer'];
      if (oldSummer != newSummer) {
        changes.add({'field': 'summerShift', 'oldValue': oldSummer, 'newValue': newSummer});
      }
      if (changes.isNotEmpty) {
        await logAction(
          branchId: branchId,
          entityType: 'employee',
          entityId: localId,
          action: 'update',
          performedBy: performedBy,
          reason: 'Updated employee details for ${record["name"]}',
          fieldChanges: changes,
        );
      }
    }

    // Automatic CNIC-based linking between Employee and Registered User
    if (cnic.isNotEmpty) {
      await linkEmployeeWithUserByCnic(
        employeeId: localId,
        employeeName: sanitized['name']?.toString() ?? '',
        cnic: cnic,
        department: sanitized['department']?.toString(),
      );
    }

    // Queue Sync
    await LocalStorageService.enqueueSync({
      'type': 'save_employee',
      'branchId': branchId,
      'localId': localId,
      'data': sanitized,
    });

    return localId;
  }

  static Future<void> linkEmployeeWithUserByCnic({
    required String employeeId,
    required String employeeName,
    required String cnic,
    String? department,
  }) async {
    final cleanCnic = cnic.replaceAll(RegExp(r'\D'), '');
    if (cleanCnic.isEmpty) return;

    try {
      if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
        final uBox = Hive.box(LocalStorageService.usersBox);
        for (final key in uBox.keys) {
          final raw = uBox.get(key);
          if (raw is Map) {
            final userCnic = ((raw['cnic'] ?? raw['identification']) ?? '').toString().replaceAll(RegExp(r'\D'), '');
            if (userCnic.isNotEmpty && userCnic == cleanCnic) {
              final uMap = Map<String, dynamic>.from(raw);
              final userId = key.toString();
              uMap['linkedEmployeeId'] = employeeId;
              uMap['linkedEmployeeName'] = employeeName;
              if (department != null) uMap['linkedDepartment'] = department;
              await uBox.put(userId, uMap);

              final empRaw = employeesBox.get(employeeId);
              if (empRaw is Map) {
                final empMap = Map<String, dynamic>.from(empRaw);
                empMap['linkedUserId'] = userId;
                empMap['linkedUserRole'] = uMap['role'];
                empMap['linkedUserName'] = uMap['username'] ?? uMap['name'];
                await employeesBox.put(employeeId, empMap);
              }

              try {
                await FirebaseFirestore.instance.collection('users').doc(userId).set({
                  'linkedEmployeeId': employeeId,
                  'linkedEmployeeName': employeeName,
                  if (department != null) 'linkedDepartment': department,
                }, SetOptions(merge: true));
              } catch (_) {}
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[FinanceLocalStorage] Automatic user-employee linking error: $e');
    }
  }

  static Future<void> linkUserAndEmployeeByCnic({
    required String cnic,
    required String userId,
    String? userRole,
    String? userName,
    String? email,
    String? department,
    String branchId = '',
  }) async {
    try {
      final match = findMatchingEmployeeForUser(
        branchId: branchId,
        cnic: cnic,
        email: email,
        username: userName,
        department: department,
        role: userRole,
      );

      if (match != null) {
        final empId = match['id']?.toString() ?? match['localId']?.toString() ?? '';
        if (empId.isNotEmpty) {
          await linkUserToEmployee(userId: userId, employeeId: empId);
          debugPrint('[FinanceLS] Auto-linked User $userId to Employee $empId (${match['matchReason']})');
        }
      }
    } catch (e) {
      debugPrint('[FinanceLocalStorage] Automatic user-employee linking error: $e');
    }
  }

  static String getBranchName(String branchId) {

    if (branchId.isEmpty || branchId == 'all') return 'All Branches';
    if (Hive.isBoxOpen(LocalStorageService.branchesBox)) {
      final box = Hive.box(LocalStorageService.branchesBox);
      final raw = box.get(branchId) ?? box.get('branch:$branchId');
      if (raw is Map) {
        final name = (raw['name'] ?? raw['branchName'] ?? raw['label'])?.toString();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    if (branchId.toLowerCase() == 'gujrat' || branchId.toLowerCase() == 'guj') return 'Gujrat';
    return branchId;
  }

  static List<Map<String, dynamic>> getEmployees(String branchId) {

    final list = <Map<String, dynamic>>[];
    final isGlobal = branchId == 'all' || branchId.isEmpty;

    for (final val in employeesBox.values) {
      if (val is! Map) continue;
      final record = Map<String, dynamic>.from(val);
      if (!isGlobal && record['branchId'] != branchId) continue;
      // Recalculate advance balance on demand
      record['currentAdvanceBalance'] = getAdvanceBalance(record['localId']);
      list.add(record);
    }
    return list..sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
  }

  static Map<String, dynamic>? getEmployee(String employeeId) {
    final val = employeesBox.get(employeeId);
    if (val == null || val is! Map) return null;
    final record = Map<String, dynamic>.from(val);
    record['currentAdvanceBalance'] = getAdvanceBalance(employeeId);
    return record;
  }

  static Future<void> syncBiDirectionalOffboarding({
    String? employeeId,
    String? userId,
    String? cnic,
    required String performedBy,
  }) async {
    final cleanCnic = (cnic ?? '').replaceAll(RegExp(r'\D'), '');

    // 1. Offboard & stop salary on Employee record
    Map<String, dynamic>? emp;
    String? empKey = employeeId;
    if (empKey != null && empKey.isNotEmpty) {
      final raw = employeesBox.get(empKey);
      if (raw is Map) emp = Map<String, dynamic>.from(raw);
    }
    if (emp == null && cleanCnic.isNotEmpty) {
      for (final k in employeesBox.keys) {
        final raw = employeesBox.get(k);
        if (raw is Map) {
          final eCnic = (raw['cnic'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
          if (eCnic.isNotEmpty && eCnic == cleanCnic) {
            emp = Map<String, dynamic>.from(raw);
            empKey = k.toString();
            break;
          }
        }
      }
    }

    if (emp != null && empKey != null) {
      emp['isActive'] = false;
      emp['status'] = 'Inactive';
      emp['currentSalary'] = 0.0;
      emp['currentSalaryMinor'] = 0;
      emp['payrollStatus'] = 'Salary Stopped';
      emp['updatedAt'] = _nowIso();
      await employeesBox.put(empKey, _sanitize(emp));
      await employeesBox.flush();
    }

    // 2. Revoke App Access on System User Account
    String? uKey = userId ?? emp?['linkedUserId']?.toString();
    if (uKey == null && cleanCnic.isNotEmpty && Hive.isBoxOpen(LocalStorageService.usersBox)) {
      final uBox = Hive.box(LocalStorageService.usersBox);
      for (final k in uBox.keys) {
        final raw = uBox.get(k);
        if (raw is Map) {
          final uCnic = ((raw['cnic'] ?? raw['identification']) ?? '').toString().replaceAll(RegExp(r'\D'), '');
          if (uCnic.isNotEmpty && uCnic == cleanCnic) {
            uKey = k.toString();
            break;
          }
        }
      }
    }

    if (uKey != null && Hive.isBoxOpen(LocalStorageService.usersBox)) {
      final uBox = Hive.box(LocalStorageService.usersBox);
      final raw = uBox.get(uKey);
      if (raw is Map) {
        final uMap = Map<String, dynamic>.from(raw);
        uMap['status'] = 'revoked';
        uMap['isRevoked'] = true;
        uMap['accessRevoked'] = true;
        uMap['updatedAt'] = _nowIso();
        await uBox.put(uKey, uMap);
      }

      try {
        await FirebaseFirestore.instance.collection('users').doc(uKey).set({
          'status': 'revoked',
          'isRevoked': true,
          'accessRevoked': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  static Future<void> deleteEmployeePermanently({
    required String branchId,
    required String employeeId,
    required String performedBy,
  }) async {
    final emp = getEmployee(employeeId);
    await syncBiDirectionalOffboarding(
      employeeId: employeeId,
      cnic: emp?['cnic']?.toString(),
      performedBy: performedBy,
    );

    await employeesBox.delete(employeeId);
    await employeesBox.flush();

    await LocalStorageService.enqueueSync({
      'type': 'delete_employee',
      'branchId': branchId,
      'localId': employeeId,
    });

    await logAction(
      branchId: branchId,
      entityType: 'employee',
      entityId: employeeId,
      action: 'delete',
      performedBy: performedBy,
      reason: 'Permanently deleted employee profile & revoked linked app access.',
    );
  }

  // ── Salary History Operations ─────────────────────────────────────────────
  static Future<String> saveSalaryHistory({
    required String branchId,
    required String employeeId,
    required double amount,
    required DateTime effectiveDate,
    required String reason,
    required String approvedBy,
    required String performedBy,
  }) async {
    final localId = _newLocalId();
    final now = _nowIso();

    // Check if retroactive
    final isRetroactive = effectiveDate.isBefore(DateTime.now());

    final empBefore = getEmployee(employeeId);
    final oldSalary = empBefore != null ? ((empBefore['currentSalary'] as num?)?.toDouble() ?? amount) : amount;

    // Period Lock Check
    final monthKey = DateFormat('yyyy-MM').format(effectiveDate);
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('Salary changes are blocked: the period $monthKey is closed and locked.');
    }

    final historyRecord = {
      'id': localId,
      'localId': localId,
      'remoteId': null,
      'updatedAt': now,
      'syncStatus': 'pending',
      'lastSyncedAt': null,
      'amount': amount,
      'rateMinor': (amount * 100).round(),
      'currency': 'PKR',
      'eventVersion': 1,
      'effectiveDate': effectiveDate.toIso8601String(),
      'reason': reason,
      'isRetroactive': isRetroactive,
      'approvedBy': approvedBy,
      'createdAt': now,
    };

    final sanitizedHistory = _sanitize(historyRecord);
    final historyKey = '${employeeId}_$localId';
    await salaryHistoryBox.put(historyKey, sanitizedHistory);
    await salaryHistoryBox.flush();

    // Update parent employee cached currentSalary
    final emp = getEmployee(employeeId);
    if (emp != null) {
      // Find latest salary rate effective
      final historyList = getSalaryHistory(employeeId);
      final latest = historyList.isNotEmpty ? (historyList.first['rateMinor'] as num? ?? historyList.first['amount'] as num? ?? amount) : amount;
      final double latestDouble = latest is int ? latest / 100 : (latest as num).toDouble();
      
      emp['currentSalary'] = latestDouble;
      emp['currentSalaryMinor'] = (latestDouble * 100).round();
      
      await employeesBox.put(employeeId, _sanitize(emp));
      await employeesBox.flush();

      // Queue update to employee too
      await LocalStorageService.enqueueSync({
        'type': 'save_employee',
        'branchId': emp['branchId'],
        'localId': employeeId,
        'data': _sanitize(emp),
      });
    }

    // Queue Sync for Salary History
    await LocalStorageService.enqueueSync({
      'type': 'save_salary_history',
      'branchId': branchId,
      'employeeId': employeeId,
      'historyId': localId,
      'data': sanitizedHistory,
    });

    // Logging Audit Trail
    await logAction(
      branchId: branchId,
      entityType: 'salary_history',
      entityId: employeeId,
      action: 'create',
      performedBy: performedBy,
      approvedBy: approvedBy,
      reason: '$reason (Rate: PKR $amount, Effective: ${DateFormat('yyyy-MM-dd').format(effectiveDate)})',
      rawData: sanitizedHistory,
    );

    // Compute retroactive arrears
    if (isRetroactive && emp != null) {
      await computeAndLogRetroactiveArrears(
        branchId: branchId,
        employeeId: employeeId,
        employeeName: emp['name']?.toString() ?? 'Unknown',
        newSalary: amount,
        oldSalary: oldSalary,
        effectiveDate: effectiveDate,
        approvedBy: approvedBy,
        performedBy: performedBy,
      );
    }

    return localId;
  }

  static List<Map<String, dynamic>> getSalaryHistory(String employeeId) {
    final list = <Map<String, dynamic>>[];
    final prefix = '${employeeId}_';

    for (final key in salaryHistoryBox.keys) {
      if (key.toString().startsWith(prefix)) {
        final val = salaryHistoryBox.get(key);
        if (val is Map) {
          list.add(Map<String, dynamic>.from(val));
        }
      }
    }
    // Sort descending by effectiveDate
    return list..sort((a, b) {
      final da = a['effectiveDate']?.toString() ?? '';
      final db = b['effectiveDate']?.toString() ?? '';
      return db.compareTo(da);
    });
  }

  static double getSalaryRateForDay(String employeeId, DateTime date) {
    final history = getSalaryHistory(employeeId);
    if (history.isEmpty) {
      final emp = getEmployee(employeeId);
      if (emp == null) return 0.0;
      if (emp['currentSalary'] != null) {
        return (emp['currentSalary'] as num).toDouble();
      }
      if (emp['currentSalaryMinor'] != null) {
        return (emp['currentSalaryMinor'] as num).toDouble() / 100.0;
      }
      return 0.0;
    }

    final targetDate = DateTime(date.year, date.month, date.day);

    for (final h in history) {
      final effDateStr = h['effectiveDate']?.toString();
      if (effDateStr == null) continue;
      final effDate = DateTime.tryParse(effDateStr);
      if (effDate == null) continue;

      final effDay = DateTime(effDate.year, effDate.month, effDate.day);
      if (effDay.isBefore(targetDate) || effDay.isAtSameMomentAs(targetDate)) {
        final amt = h['amount'];
        final amtMinor = h['amountMinor'];
        if (amt != null) return (amt as num).toDouble();
        if (amtMinor != null) return (amtMinor as num).toDouble() / 100.0;
      }
    }

    final last = history.last;
    final amt = last['amount'];
    final amtMinor = last['amountMinor'];
    if (amt != null) return (amt as num).toDouble();
    if (amtMinor != null) return (amtMinor as num).toDouble() / 100.0;
    return 0.0;
  }


  // Helper to find salary rate active for a specific monthKey
  static double getSalaryRateForMonth(String employeeId, String monthKey) {
    final parts = monthKey.split('-');
    final yr = int.parse(parts[0]);
    final mo = int.parse(parts[1]);
    final target = DateTime(yr, mo + 1, 0, 23, 59, 59); // end of that month
    return getSalaryRateForDay(employeeId, target);
  }

  // ── Retroactive Arrears Computations ──────────────────────────────────────
  static Future<void> computeAndLogRetroactiveArrears({
    required String branchId,
    required String employeeId,
    required String employeeName,
    required double newSalary,
    required double oldSalary,
    required DateTime effectiveDate,
    required String approvedBy,
    required String performedBy,
  }) async {
    final today = DateTime.now();
    DateTime checkDate = DateTime(effectiveDate.year, effectiveDate.month, 15);
    final limitDate = DateTime(today.year, today.month, 1);
    
    double totalArrears = 0.0;
    final List<String> affectedMonths = [];

    // Loop through each month between effectiveDate and current payroll month
    while (checkDate.isBefore(limitDate)) {
      final mKey = DateFormat('yyyy-MM').format(checkDate);
      
      // Check if there is an existing payout ledger entry for this month
      final payouts = salaryLedgerBox.values.where((val) {
        if (val is! Map) return false;
        final entry = Map<String, dynamic>.from(val);
        return entry['employeeId'] == employeeId &&
               entry['monthKey'] == mKey &&
               entry['type'] == 'payout' &&
               entry['isVoided'] != true;
      }).toList();

      if (payouts.isNotEmpty) {
        final delta = newSalary - oldSalary;
        if (delta > 0) {
          totalArrears += delta;
          affectedMonths.add(mKey);
        }
      }

      checkDate = DateTime(checkDate.year, checkDate.month + 1, 15);
    }

    if (totalArrears > 0) {
      // Create an arrears payment ledger entry
      final ledgerId = _newLocalId();
      final now = _nowIso();

      final record = {
        'id': ledgerId,
        'localId': ledgerId,
        'remoteId': null,
        'updatedAt': now,
        'syncStatus': 'pending',
        'employeeId': employeeId,
        'employeeName': employeeName,
        'type': 'arrears_payment',
        'amount': totalArrears,
        'amountMinor': (totalArrears * 100).round(),
        'advanceDeductionsMinor': 0,
        'absenceDeductionsMinor': 0,
        'otherDeductionsMinor': 0,
        'advanceAddedMinor': 0,
        'currency': 'PKR',
        'periodLocked': false,
        'eventVersion': 1,
        'correctsId': null,
        'monthKey': DateFormat('yyyy-MM').format(today),
        'date': now,
        'advanceDeductions': 0.0,
        'absenceDeductions': 0.0,
        'otherDeductions': 0.0,
        'advanceAdded': 0.0,
        'paymentMethod': 'bank_transfer',
        'note': 'Retroactive arrears computed for months: ${affectedMonths.join(", ")}',
        'recordedBy': performedBy,
        'approvedBy': approvedBy,
        'createdAt': now,
        'isVoided': false,
        'voidedBy': null,
        'voidedAt': null,
        'voidReason': null,
      };

      final sanitized = _sanitize(record);
      await salaryLedgerBox.put(ledgerId, sanitized);
      await salaryLedgerBox.flush();

      // Mirror to sync
      await LocalStorageService.enqueueSync({
        'type': 'save_salary_ledger',
        'branchId': branchId,
        'recordId': ledgerId,
        'data': sanitized,
      });

      // Audit Log
      await logAction(
        branchId: branchId,
        entityType: 'salary_ledger',
        entityId: ledgerId,
        action: 'create',
        performedBy: performedBy,
        approvedBy: approvedBy,
        reason: 'Arrears of PKR $totalArrears generated retroactively for months: ${affectedMonths.join(", ")}',
        rawData: sanitized,
      );
    }
  }

  // ── Attendance Operations ─────────────────────────────────────────────────
  static Future<String> saveAttendanceRecord({
    required String branchId,
    required Map<String, dynamic> data,
    required String performedBy,
  }) async {
    final employeeId = data['employeeId'] as String;
    final dateStr = data['date'] as String; // YYYY-MM-DD
    
    // Period Lock Check
    final monthKey = dateStr.substring(0, 7);
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('Attendance changes are blocked: the period $monthKey is closed and locked.');
    }

    final attendanceKey = '${employeeId}_$dateStr';
    final now = _nowIso();

    final record = Map<String, dynamic>.from(data);
    record['localId'] = attendanceKey;
    record['remoteId'] = null;
    record['updatedAt'] = now;
    record['syncStatus'] = 'pending';
    record['markedBy'] = performedBy;
    record['markedAt'] = now;

    final sanitized = _sanitize(record);
    await attendanceBox.put(attendanceKey, sanitized);
    await attendanceBox.flush();

    // Mirror to sync
    await LocalStorageService.enqueueSync({
      'type': 'save_attendance_record',
      'branchId': branchId,
      'date': dateStr,
      'employeeId': employeeId,
      'data': sanitized,
    });

    return attendanceKey;
  }

  static bool hasAttendanceDataForMonth(String employeeId, String monthKey) {
    final daysInMonth = getDaysInMonth(monthKey);
    for (var d = 1; d <= daysInMonth; d++) {
      final dd = d.toString().padLeft(2, '0');
      final key = '${employeeId}_$monthKey-$dd';
      if (attendanceBox.containsKey(key)) {
        return true;
      }
    }
    return false;
  }

  static List<Map<String, dynamic>> getAttendanceForDate(String branchId, String dateStr) {
    final results = <Map<String, dynamic>>[];
    
    // We can load all active employees and map their attendance
    final employees = getEmployees(branchId);
    for (final emp in employees) {
      final empId = emp['localId'] as String;
      final key = '${empId}_$dateStr';
      final att = attendanceBox.get(key);
      if (att is Map) {
        results.add(Map<String, dynamic>.from(att));
      } else {
        // Return default placeholder
        results.add({
          'employeeId': empId,
          'date': dateStr,
          'status': 'absent',
          'leaveType': null,
          'arrivalTime': null,
          'departureTime': null,
          'note': null,
          'markedBy': 'System',
          'markedAt': _nowIso(),
        });
      }
    }
    return results;
  }

  static int getDaysInMonth(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    if (month == 2) {
      final isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return isLeapYear ? 29 : 28;
    }
    if ([4, 6, 9, 11].contains(month)) return 30;
    return 31;
  }
  static bool isHoliday({
    required String branchId,
    required String department,
    required String dateStr,
  }) {
    if (branchId.isEmpty) return false;

    final prefix = '${branchId.toLowerCase().trim()}__hol__';
    final box = Hive.box(LocalStorageService.financeHolidaysBox);
    final cleanDept = department.trim().toLowerCase();
    final cleanBranch = branchId.trim().toLowerCase();

    for (final key in box.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;

      final record = Map<String, dynamic>.from(raw);
      
      // Date check
      final rawDate = record['date'];
      String? recordDateStr;
      if (rawDate is Timestamp) {
        recordDateStr = DateFormat('yyyy-MM-dd').format(rawDate.toDate());
      } else if (rawDate is String) {
        try {
          recordDateStr = DateFormat('yyyy-MM-dd').format(DateTime.parse(rawDate));
        } catch (_) {
          recordDateStr = rawDate;
        }
      }
      
      if (recordDateStr != dateStr) continue;

      // Department scope check
      final departments = record['departments'] is List
          ? List<String>.from(record['departments'] as List).map((d) => d.trim().toLowerCase()).toList()
          : <String>[];
      
      // If departments list is empty or contains 'all', it applies to all departments
      bool deptApplies = departments.isEmpty || departments.contains('all') || departments.contains(cleanDept);
      if (!deptApplies) continue;

      // Exception check
      final exceptions = record['exceptions'] is List
          ? List<dynamic>.from(record['exceptions'] as List)
          : [];
      
      bool isExcepted = false;
      for (final ex in exceptions) {
        if (ex is! Map) continue;
        final exBranch = ex['branchId']?.toString().trim().toLowerCase() ?? '';
        final exDept = ex['department']?.toString().trim().toLowerCase() ?? '';

        if (exBranch == 'all' && exDept == cleanDept) {
          isExcepted = true;
          break;
        }
        if (exBranch == cleanBranch && exDept == cleanDept) {
          isExcepted = true;
          break;
        }
        if (exBranch == cleanBranch && exDept == 'all') {
          isExcepted = true;
          break;
        }
      }

      if (isExcepted) {
        continue;
      }

      return true;
    }

    return false;
  }

  static List<Map<String, dynamic>> getHolidays(String branchId) {
    final list = <Map<String, dynamic>>[];
    if (branchId.isEmpty) return list;

    final prefix = '${branchId.toLowerCase().trim()}__hol__';
    final box = Hive.box(LocalStorageService.financeHolidaysBox);

    for (final key in box.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final raw = box.get(key);
      if (raw is Map) {
        list.add(Map<String, dynamic>.from(raw));
      }
    }
    // Sort descending by date
    list.sort((a, b) {
      final da = a['date']?.toString() ?? '';
      final db = b['date']?.toString() ?? '';
      return db.compareTo(da);
    });
    return list;
  }

  static Future<void> saveHoliday({
    required String name,
    required DateTime date,
    required List<String> branches,
    required List<String> departments,
    required List<Map<String, dynamic>> exceptions,
    required String performedBy,
  }) async {
    final localId = _uuid.v4();
    final now = _nowIso();

    List<String> targetBranches = [];
    if (branches.contains('all')) {
      final branchesBox = Hive.box(LocalStorageService.branchesBox);
      targetBranches = branchesBox.values
          .map((v) => Map<String, dynamic>.from(v as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } else {
      targetBranches = branches;
    }

    for (final bId in targetBranches) {
      final record = {
        'id': localId,
        'localId': localId,
        'remoteId': null,
        'name': name,
        'date': date.toIso8601String(),
        'branches': branches,
        'departments': departments,
        'exceptions': exceptions,
        'updatedAt': now,
        'syncStatus': 'pending',
      };

      final sanitized = _sanitize(record);
      final prefix = '${bId.toLowerCase().trim()}__hol__';
      final box = Hive.box(LocalStorageService.financeHolidaysBox);
      await box.put('$prefix$localId', sanitized);
      await box.flush();

      // Mirror to sync queue
      await LocalStorageService.enqueueSync({
        'type': 'save_finance_holiday',
        'branchId': bId,
        'holidayId': localId,
        'data': sanitized,
      });

      // Audit Log
      await logAction(
        branchId: bId,
        entityType: 'finance_holiday',
        entityId: localId,
        action: 'create',
        performedBy: performedBy,
        reason: 'Created holiday: $name on ${DateFormat('yyyy-MM-dd').format(date)}',
        rawData: sanitized,
      );
    }
  }

  static Future<void> deleteHoliday({
    required String holidayId,
    required List<String> branches,
    required String performedBy,
  }) async {
    List<String> targetBranches = [];
    if (branches.contains('all')) {
      final branchesBox = Hive.box(LocalStorageService.branchesBox);
      targetBranches = branchesBox.values
          .map((v) => Map<String, dynamic>.from(v as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } else {
      targetBranches = branches;
    }

    for (final bId in targetBranches) {
      final prefix = '${bId.toLowerCase().trim()}__hol__';
      final box = Hive.box(LocalStorageService.financeHolidaysBox);
      final key = '$prefix$holidayId';
      if (box.containsKey(key)) {
        await box.delete(key);
        await box.flush();

        // Enqueue deletion sync
        await LocalStorageService.enqueueSync({
          'type': 'delete_finance_holiday',
          'branchId': bId,
          'holidayId': holidayId,
        });

        // Audit Log
        await logAction(
          branchId: bId,
          entityType: 'finance_holiday',
          entityId: holidayId,
          action: 'delete',
          performedBy: performedBy,
          reason: 'Deleted holiday with ID: $holidayId',
        );
      }
    }
  }
  static Map<String, dynamic> getPayrollAttendanceSummary(String employeeId, String monthKey) {
    final emp = getEmployee(employeeId);
    final branchId = emp?['branchId']?.toString() ?? '';
    final employeeDept = emp?['department']?.toString() ?? '';

    double presentDays = 0.0;
    double lateDays = 0.0;
    double paidLeaves = 0.0;
    double unpaidLeaves = 0.0;
    double absentDays = 0.0;
    double holidayWorkedDays = 0.0;
    double sundayOvertimeDays = 0.0;
    int holidayCount = 0;

    double baseSalaryEarned = 0.0;
    double absenceDeductions = 0.0;
    double holidayBonus = 0.0;
    double sundayOvertimeBonus = 0.0;
    double fullMonthWeightedSalary = 0.0;
    int totalEmployedDays = 0;
    int unmarkedDays = 0;
    int forfeitedSundaysCount = 0;

    final joinStr = emp?['joiningDate']?.toString();
    final exitStr = emp?['exitDate']?.toString();

    DateTime? joinDate;
    if (joinStr != null && joinStr.isNotEmpty) {
      joinDate = DateTime.tryParse(joinStr);
    }
    DateTime? exitDate;
    if (exitStr != null && exitStr.isNotEmpty) {
      exitDate = DateTime.tryParse(exitStr);
    }

    final parts = monthKey.split('-');
    final yr = int.parse(parts[0]);
    final mo = int.parse(parts[1]);
    final daysInMonth = getDaysInMonth(monthKey);
    final todayDateOnly = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    // Determine the cutoff date for this month calculation
    DateTime cutoffDate;
    final endOfMonth = DateTime(yr, mo, daysInMonth);
    if (todayDateOnly.isAfter(endOfMonth) || todayDateOnly.isBefore(DateTime(yr, mo, 1))) {
      cutoffDate = endOfMonth;
    } else {
      cutoffDate = todayDateOnly;
    }


    for (var d = 1; d <= daysInMonth; d++) {
      final dd = d.toString().padLeft(2, '0');
      final dateStr = '$monthKey-$dd'; // YYYY-MM-DD
      final date = DateTime(yr, mo, d);

      // Check if employed on this day
      bool isEmployed = true;
      if (joinDate != null) {
        final joinDay = DateTime(joinDate.year, joinDate.month, joinDate.day);
        if (date.isBefore(joinDay)) {
          isEmployed = false;
        }
      }
      if (exitDate != null) {
        final exitDay = DateTime(exitDate.year, exitDate.month, exitDate.day);
        if (date.isAfter(exitDay)) {
          isEmployed = false;
        }
      }

      if (!isEmployed) continue;

      final activeSalaryRate = getSalaryRateForDay(employeeId, date);
      final dailyRate = activeSalaryRate / daysInMonth;
      fullMonthWeightedSalary += dailyRate;

      final isFutureDay = date.isAfter(cutoffDate);
      final key = '${employeeId}_$dateStr';
      final val = attendanceBox.get(key);
      final hasRecord = val != null;

      final isHolidayDay = isHoliday(
        branchId: branchId,
        department: employeeDept,
        dateStr: dateStr,
      );
      final isSunday = date.weekday == DateTime.sunday;

      // Skip future dates if they do not have any explicit attendance record marked.
      if (isFutureDay && !hasRecord) {
        continue;
      }

      totalEmployedDays++;
      baseSalaryEarned += dailyRate;

      if (!hasRecord && date.weekday != DateTime.sunday) {
        if (!isFutureDay) {
          unmarkedDays++;
        }
      }

      String status;
      String? leaveType;
      String? overtimeDuration;

      if (val is Map) {
        status = val['status']?.toString() ?? 'absent';
        leaveType = val['leaveType']?.toString();
        overtimeDuration = val['overtimeDuration']?.toString();
      } else {
        if (isFutureDay && !isSunday && !isHolidayDay) continue;

        // Defaults: Sunday defaults to 'off', other days default to 'unmarked'
        if (isSunday) {
          status = 'off';
        } else {
          status = 'unmarked';
        }
        leaveType = null;
        overtimeDuration = null;
      }
      if (isHolidayDay) {
        holidayCount++;
      }

      if (date.weekday == DateTime.sunday) {
        // Evaluate Sunday Eligibility
        bool isSundayPayable = true;

        // Sunday Weekly Work Check: Must work at least one day in the preceding weekdays (Monday to Saturday) of this week
        if (isSundayPayable) {
          bool workedInWeek = false;
          int eligibleWeekdaysCount = 0;

          for (int offset = 1; offset <= 6; offset++) {
            final weekdayDate = date.subtract(Duration(days: offset));
            
            // Check if the weekday is within the employee's employment period
            if (joinDate != null) {
              final joinDay = DateTime(joinDate.year, joinDate.month, joinDate.day);
              if (weekdayDate.isBefore(joinDay)) continue;
            }
            if (exitDate != null) {
              final exitDay = DateTime(exitDate.year, exitDate.month, exitDate.day);
              if (weekdayDate.isAfter(exitDay)) continue;
            }

            eligibleWeekdaysCount++;

            final weekdayDateStr = DateFormat('yyyy-MM-dd').format(weekdayDate);
            final weekdayKey = '${employeeId}_$weekdayDateStr';
            final weekdayVal = attendanceBox.get(weekdayKey);

            if (weekdayVal == null) {
              // Defaults to unmarked, which counts as worked/paid for eligibility
              workedInWeek = true;
              break;
            } else if (weekdayVal is Map) {
              final status = weekdayVal['status']?.toString();
              final leaveType = weekdayVal['leaveType']?.toString();

              if (status != 'absent' && !(status == 'leave' && leaveType == 'unpaid')) {
                workedInWeek = true;
                break;
              }
            }
          }

          // If there are no preceding weekdays in the week that fall within their employment period, they get paid for Sunday by default.
          if (eligibleWeekdaysCount > 0 && !workedInWeek) {
            isSundayPayable = false;
          }
        }

        if (!isSundayPayable) {
          // Forfeited Sunday contributes Rs. 0 to earned salary.
          // Since baseSalaryEarned += dailyRate was already done, we subtract it here to make it Rs. 0.
          baseSalaryEarned -= dailyRate;
          forfeitedSundaysCount++;
        } else {
          // Sundays are off. We only check for overtime.
          if (status == 'overtime') {
            if (overtimeDuration == 'half') {
              sundayOvertimeDays += 0.5;
              sundayOvertimeBonus += 0.5 * dailyRate;
            } else {
              sundayOvertimeDays += 1.0;
              sundayOvertimeBonus += dailyRate;
            }
          }
        }
      } else {
        // Weekdays (Monday - Saturday)
        if (isHolidayDay) {
          if (status == 'present' || status == 'late') {
            holidayWorkedDays += 1.0;
            holidayBonus += dailyRate;
          } else if (status == 'half_day') {
            holidayWorkedDays += 0.5;
            holidayBonus += 0.5 * dailyRate;
          }
        }

        if (status == 'present') {
          presentDays += 1.0;
        } else if (status == 'late') {
          lateDays += 1.0;
        } else if (status == 'leave') {
          if (leaveType == 'unpaid') {
            unpaidLeaves += 1.0;
            absenceDeductions += dailyRate;
          } else {
            paidLeaves += 1.0;
          }
        } else if (status == 'absent') {
          if (!isHolidayDay) {
            absentDays += 1.0;
            absenceDeductions += dailyRate;
          }
        } else if (status == 'half_day') {
          final hdType = val is Map ? (val['halfDayType']?.toString() ?? 'unpaid') : 'unpaid';
          if (hdType == 'unpaid') {
            presentDays += 0.5;
            unpaidLeaves += 0.5;
            absenceDeductions += 0.5 * dailyRate;
          } else {
            presentDays += 0.5;
            paidLeaves += 0.5;
          }
        }
      }
    }

    return {
      'totalDays': daysInMonth,
      'totalEmployedDays': totalEmployedDays,
      'workingDays': presentDays + lateDays,
      'presentDays': presentDays,
      'lateDays': lateDays,
      'paidLeaves': paidLeaves,
      'unpaidLeaves': unpaidLeaves,
      'absentDays': absentDays,
      'holidayWorkedDays': holidayWorkedDays,
      'holidayCount': holidayCount,
      'holidayDays': holidayCount,
      'baseSalaryEarned': baseSalaryEarned,
      'absenceDeductions': absenceDeductions,
      'holidayBonus': holidayBonus,
      'sundayOvertimeDays': sundayOvertimeDays,
      'sundayOvertimeBonus': sundayOvertimeBonus,
      'fullMonthWeightedSalary': fullMonthWeightedSalary,
      'unmarkedDays': unmarkedDays,
      'forfeitedSundays': forfeitedSundaysCount,
    };
  }

  static int getAbsentDaysCount(String employeeId, String monthKey) {
    return (getPayrollAttendanceSummary(employeeId, monthKey)['absentDays'] as num).toInt();
  }

  static Map<String, double> getLeaveUsage(String employeeId, int year) {
    double sick = 0.0;
    double casual = 0.0;
    double annual = 0.0;
    double unpaid = 0.0;

    final prefix = '${employeeId}_$year-';

    for (final key in attendanceBox.keys) {
      if (key.toString().startsWith(prefix)) {
        final val = attendanceBox.get(key);
        if (val is Map) {
          final status = val['status']?.toString();
          final leaveType = val['leaveType']?.toString();
          final halfDayType = val['halfDayType']?.toString();

          if (status == 'leave') {
            if (leaveType == 'sick') sick += 1.0;
            else if (leaveType == 'casual') casual += 1.0;
            else if (leaveType == 'annual') annual += 1.0;
            else if (leaveType == 'unpaid') unpaid += 1.0;
            else sick += 1.0;
          } else if (status == 'half_day') {
            if (halfDayType == 'unpaid') {
              unpaid += 0.5;
            } else {
              if (leaveType == 'sick') sick += 0.5;
              else if (leaveType == 'annual') annual += 0.5;
              else casual += 0.5;
            }
          }
        }
      }
    }
    return {
      'sick': sick,
      'casual': casual,
      'annual': annual,
      'unpaid': unpaid,
    };
  }

  static Map<String, int> getLeaveQuotas() {
    return {
      'sick': 10,
      'casual': 12,
      'annual': 15,
    };
  }

  // ── Salary Ledger Operations ──────────────────────────────────────────────
  static Future<String> saveLedgerEntry({
    required String branchId,
    required Map<String, dynamic> data,
    required String performedBy,
    String? approvedBy,
  }) async {
    final monthKey = data['monthKey']?.toString() ?? DateFormat('yyyy-MM').format(DateTime.now());
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('This month ($monthKey) is closed and locked. Modifying ledger entries is blocked.');
    }

    final localId = _newLocalId();
    final now = _nowIso();

    final record = Map<String, dynamic>.from(data);
    record['id'] = localId;
    record['localId'] = localId;
    record['remoteId'] = null;
    record['updatedAt'] = now;
    record['syncStatus'] = 'pending';
    record['recordedBy'] = performedBy;
    record['approvedBy'] = approvedBy;
    record['createdAt'] = now;
    record['isVoided'] = false;

    // Convert money to minor units
    final double amount = (record['amount'] as num?)?.toDouble() ?? 0.0;
    final double advanceDeductions = (record['advanceDeductions'] as num?)?.toDouble() ?? 0.0;
    final double absenceDeductions = (record['absenceDeductions'] as num?)?.toDouble() ?? 0.0;
    final double otherDeductions = (record['otherDeductions'] as num?)?.toDouble() ?? 0.0;
    final double advanceAdded = (record['advanceAdded'] as num?)?.toDouble() ?? 0.0;

    record['amountMinor'] = (amount * 100).round();
    record['advanceDeductionsMinor'] = (advanceDeductions * 100).round();
    record['absenceDeductionsMinor'] = (absenceDeductions * 100).round();
    record['otherDeductionsMinor'] = (otherDeductions * 100).round();
    record['advanceAddedMinor'] = (advanceAdded * 100).round();
    record['currency'] = 'PKR';
    record['eventVersion'] = 1;
    record['periodLocked'] = false;
    record['correctsId'] = record['correctsId'];

    final sanitized = _sanitize(record);
    await salaryLedgerBox.put(localId, sanitized);
    await salaryLedgerBox.flush();

    // Trigger update of parent employee cached advance balance
    final employeeId = data['employeeId'] as String;
    final emp = getEmployee(employeeId);
    if (emp != null) {
      final double bal = getAdvanceBalance(employeeId);
      emp['currentAdvanceBalance'] = bal;
      emp['currentAdvanceBalanceMinor'] = (bal * 100).round();
      await employeesBox.put(employeeId, _sanitize(emp));
      await employeesBox.flush();

      // Sync updated employee
      await LocalStorageService.enqueueSync({
        'type': 'save_employee',
        'branchId': emp['branchId'],
        'localId': employeeId,
        'data': _sanitize(emp),
      });
    }

    // Mirror to sync
    await LocalStorageService.enqueueSync({
      'type': 'save_salary_ledger',
      'branchId': branchId,
      'recordId': localId,
      'data': sanitized,
    });

    // Logging Audit Trail
    await logAction(
      branchId: branchId,
      entityType: 'salary_ledger',
      entityId: localId,
      action: 'create',
      performedBy: performedBy,
      approvedBy: approvedBy,
      reason: 'Ledger entry: ${data['type']} for PKR ${data['amount']}',
      rawData: sanitized,
    );

    return localId;
  }

  static Future<void> voidLedgerEntry({
    required String branchId,
    required String recordId,
    required String voidedBy,
    required String voidReason,
    String? approvedBy,
  }) async {
    if (voidReason.trim().isEmpty) {
      throw Exception('Void reason is required and cannot be empty.');
    }

    final raw = salaryLedgerBox.get(recordId);
    if (raw == null || raw is! Map) {
      throw Exception('Salary ledger entry not found.');
    }

    final entry = Map<String, dynamic>.from(raw);
    if (entry['isVoided'] == true) return; // already voided

    final monthKey = entry['monthKey']?.toString() ?? DateFormat('yyyy-MM').format(DateTime.now());
    final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('This month ($monthKey) is closed and locked. Voiding ledger entries is blocked.');
    }

    final now = _nowIso();
    entry['isVoided'] = true;
    entry['voidedBy'] = voidedBy;
    entry['voidedAt'] = now;
    entry['voidReason'] = voidReason;
    entry['approvedBy'] = approvedBy ?? entry['approvedBy'];
    entry['updatedAt'] = now;
    entry['syncStatus'] = 'pending';

    final sanitized = _sanitize(entry);
    await salaryLedgerBox.put(recordId, sanitized);
    await salaryLedgerBox.flush();

    // Trigger update of parent employee cached advance balance
    final employeeId = entry['employeeId'] as String;
    final emp = getEmployee(employeeId);
    if (emp != null) {
      final double bal = getAdvanceBalance(employeeId);
      emp['currentAdvanceBalance'] = bal;
      emp['currentAdvanceBalanceMinor'] = (bal * 100).round();
      await employeesBox.put(employeeId, _sanitize(emp));
      await employeesBox.flush();

      // Sync updated employee
      await LocalStorageService.enqueueSync({
        'type': 'save_employee',
        'branchId': emp['branchId'],
        'localId': employeeId,
        'data': _sanitize(emp),
      });
    }

    // Mirror to sync
    await LocalStorageService.enqueueSync({
      'type': 'save_salary_ledger',
      'branchId': branchId,
      'recordId': recordId,
      'data': sanitized,
    });

    // Logging Audit Trail
    await logAction(
      branchId: branchId,
      entityType: 'salary_ledger',
      entityId: recordId,
      action: 'void',
      performedBy: voidedBy,
      approvedBy: approvedBy,
      reason: 'Voided entry: $voidReason',
      rawData: sanitized,
    );
  }

  static List<Map<String, dynamic>> getLedgerEntries(String branchId, {String? employeeId}) {
    final list = <Map<String, dynamic>>[];
    final isGlobal = branchId == 'all' || branchId.isEmpty;

    for (final val in salaryLedgerBox.values) {
      if (val is! Map) continue;
      final record = Map<String, dynamic>.from(val);
      if (employeeId != null && record['employeeId'] != employeeId) continue;
      
      // If we are showing for a specific branch, check branch context
      // Note: for transferred employees, ledger transactions remain under their original branch context
      final recordBranch = record['branchId']?.toString() ?? branchId;
      if (!isGlobal && employeeId == null && recordBranch != branchId) continue;

      list.add(record);
    }
    // Sort descending by date/createdAt
    return list..sort((a, b) {
      final da = a['createdAt']?.toString() ?? '';
      final db = b['createdAt']?.toString() ?? '';
      return db.compareTo(da);
    });
  }

  // ── Settings Operations ───────────────────────────────────────────────────
  static Map<String, dynamic> getFinanceSettings(String branchId) {
    final val = settingsBox.get(branchId);
    if (val is Map) {
      return Map<String, dynamic>.from(val);
    }
    // Return default settings
    return {
      'branchId': branchId,
      'winter': '09:00 AM - 05:00 PM',
      'summer': '08:00 AM - 04:00 PM',
      'absenceDeductionRule': {
        'method': 'per_calendar_day',
        'divisor': 30,
      },
    };
  }

  static Future<void> saveFinanceSettings({
    required String branchId,
    required Map<String, dynamic> data,
    required String performedBy,
  }) async {
    final now = _nowIso();
    final record = Map<String, dynamic>.from(data);
    record['branchId'] = branchId;
    record['updatedAt'] = now;
    record['syncStatus'] = 'pending';
    record['lastSyncedAt'] = null;

    final sanitized = _sanitize(record);
    await settingsBox.put(branchId, sanitized);
    await settingsBox.flush();

    // Mirror to sync
    await LocalStorageService.enqueueSync({
      'type': 'save_finance_settings',
      'branchId': branchId,
      'data': sanitized,
    });

    // Log audit
    await logAction(
      branchId: branchId,
      entityType: 'finance_settings',
      entityId: branchId,
      action: 'update',
      performedBy: performedBy,
      rawData: sanitized,
    );
  }

  // ── Branch Transfer Operations ────────────────────────────────────────────
  static Future<String> transferEmployee({
    required String employeeId,
    required String fromBranchId,
    required String toBranchId,
    required String reason,
    required String approvedBy,
    required String performedBy,
    required DateTime effectiveDate,
  }) async {
    if (reason.trim().isEmpty) {
      throw Exception('Transfer reason is required.');
    }

    final emp = getEmployee(employeeId);
    if (emp == null) {
      throw Exception('Employee not found.');
    }

    final localId = _newLocalId();
    final now = _nowIso();

    // 1. Create transfer record locally
    final transferRecord = {
      'id': localId,
      'localId': localId,
      'remoteId': null,
      'updatedAt': now,
      'syncStatus': 'pending',
      'lastSyncedAt': null,
      'employeeId': employeeId,
      'fromBranchId': fromBranchId,
      'toBranchId': toBranchId,
      'effectiveDate': effectiveDate.toIso8601String(),
      'reason': reason,
      'requestedBy': performedBy,
      'approvedBy': approvedBy,
      'createdAt': now,
    };

    final sanitizedTransfer = _sanitize(transferRecord);
    await transfersBox.put(localId, sanitizedTransfer);
    await transfersBox.flush();

    // 2. Update parent Employee's branchId
    emp['branchId'] = toBranchId;
    emp['updatedAt'] = now;
    emp['syncStatus'] = 'pending';
    await employeesBox.put(employeeId, _sanitize(emp));
    await employeesBox.flush();

    // 3. Mirror the employee update and transfer to sync queue
    // Note: the background sync processor handles employee branch moves inside a transaction
    await LocalStorageService.enqueueSync({
      'type': 'save_branch_transfer',
      'branchId': fromBranchId,
      'transferId': localId,
      'employeeId': employeeId,
      'fromBranchId': fromBranchId,
      'toBranchId': toBranchId,
      'data': sanitizedTransfer,
    });

    // Sync updated employee document position
    await LocalStorageService.enqueueSync({
      'type': 'save_employee',
      'branchId': toBranchId,
      'localId': employeeId,
      'data': _sanitize(emp),
    });

    // 4. Audit Log (old branch context)
    await logAction(
      branchId: fromBranchId,
      entityType: 'branch_transfer',
      entityId: localId,
      action: 'transfer',
      performedBy: performedBy,
      approvedBy: approvedBy,
      reason: 'Transferred $employeeId from $fromBranchId to $toBranchId. Reason: $reason',
      rawData: sanitizedTransfer,
    );

    return localId;
  }

  static List<Map<String, dynamic>> getTransfersForEmployee(String employeeId) {
    final list = <Map<String, dynamic>>[];
    for (final val in transfersBox.values) {
      if (val is Map && val['employeeId'] == employeeId) {
        list.add(Map<String, dynamic>.from(val));
      }
    }
    return list..sort((a, b) => (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));
  }

  // ── Audit Log Retrieval ───────────────────────────────────────────────────
  static List<Map<String, dynamic>> getAuditLogs(String branchId, {String? searchQuery}) {
    final list = <Map<String, dynamic>>[];
    final isGlobal = branchId == 'all' || branchId.isEmpty;
    final query = searchQuery?.trim().toLowerCase();

    for (final val in auditLogsBox.values) {
      if (val is! Map) continue;
      final record = Map<String, dynamic>.from(val);
      if (!isGlobal && record['branchContext'] != branchId) continue;

      if (query != null && query.isNotEmpty) {
        final reason = record['reason']?.toString().toLowerCase() ?? '';
        final performedBy = record['performedBy']?.toString().toLowerCase() ?? '';
        final approvedBy = record['approvedBy']?.toString().toLowerCase() ?? '';
        final entityId = record['entityId']?.toString().toLowerCase() ?? '';
        
        // Match by basic fields
        bool match = reason.contains(query) ||
                     performedBy.contains(query) ||
                     approvedBy.contains(query) ||
                     entityId.contains(query);

        // Match by employee name/CNIC if entityType is employee
        if (!match && record['entityType'] == 'employee') {
          final emp = getEmployee(record['entityId']?.toString() ?? '');
          if (emp != null) {
            final name = emp['name']?.toString().toLowerCase() ?? '';
            final cnic = emp['cnic']?.toString().toLowerCase() ?? '';
            match = name.contains(query) || cnic.contains(query);
          }
        }
        
        if (!match) continue;
      }

      list.add(record);
    }
    return list..sort((a, b) => (b['timestamp']?.toString() ?? '').compareTo(a['timestamp']?.toString() ?? ''));
  }

  // ── Employee Specific Audit Logs ──────────────────────────────────────────
  static List<Map<String, dynamic>> getAuditLogsForEmployee(String employeeId) {
    final list = <Map<String, dynamic>>[];
    for (final val in auditLogsBox.values) {
      if (val is! Map) continue;
      final record = Map<String, dynamic>.from(val);
      if (record['entityType'] == 'employee' && record['entityId'] == employeeId) {
        list.add(record);
      }
    }
    // Sort descending by timestamp
    return list..sort((a, b) {
      final ta = a['timestamp']?.toString() ?? '';
      final tb = b['timestamp']?.toString() ?? '';
      return tb.compareTo(ta);
    });
  }

  // ── Custom Roles & Departments Persistence ───────────────────────────────
  static List<String> getCustomRolesForDepartment(String dept) {
    final val = settingsBox.get('custom_roles_for_dept_${dept.toLowerCase().trim()}');
    if (val is List) {
      return List<String>.from(val);
    }
    return [];
  }

  static Future<void> addCustomRoleForDepartment(String dept, String role) async {
    final list = getCustomRolesForDepartment(dept);
    if (!list.contains(role)) {
      list.add(role);
      await settingsBox.put('custom_roles_for_dept_${dept.toLowerCase().trim()}', list);
      await settingsBox.flush();
    }
  }

  static List<String> getRolesForDepartment(String dept) {
    final normDept = dept.trim();
    final defaultRoles = <String>[];
    if (normDept.toLowerCase() == 'administration' || normDept.toLowerCase() == 'admin') {
      defaultRoles.addAll(['Chairman', 'CEO', 'HQ Manager', 'Admin', 'Branch Manager', 'IT']);
    } else if (normDept.toLowerCase() == 'dispensary') {
      defaultRoles.addAll(['Supervisor', 'Dispenser', 'Receptionist', 'Doctor']);
    } else if (normDept.toLowerCase() == 'office') {
      defaultRoles.addAll(['Sweeper', 'CEO', 'Admin', 'IT', 'Office Boy', 'Branch Manager']);
    } else if (normDept.toLowerCase() == 'madrassa') {
      defaultRoles.addAll(['Madrassa Teacher', 'Madrassa Admin', 'Principal', 'Khateeb', 'Imam', 'Moazan']);
    } else if (normDept.toLowerCase() == 'school') {
      defaultRoles.addAll(['Peon', 'Admin', 'Principal']);
    } else if (normDept.toLowerCase() == 'dasterkhwaan') {
      defaultRoles.addAll(['Helper', 'Cook']);
    } else {
      defaultRoles.addAll(['Helper', 'Staff', 'Manager']);
    }

    final custom = getCustomRolesForDepartment(normDept);
    for (final r in custom) {
      if (!defaultRoles.contains(r)) {
        defaultRoles.add(r);
      }
    }
    return defaultRoles;
  }

  static List<String> getCustomRoles() {
    final val = settingsBox.get('global_custom_roles');
    if (val is List) {
      return List<String>.from(val);
    }
    return [];
  }

  static Future<void> addCustomRole(String role) async {
    final list = getCustomRoles();
    if (!list.contains(role)) {
      list.add(role);
      await settingsBox.put('global_custom_roles', list);
      await settingsBox.flush();
    }
  }

  static List<String> getCustomDepartments() {
    final val = settingsBox.get('global_custom_departments');
    if (val is List) {
      return List<String>.from(val);
    }
    return [];
  }

  static Future<void> addCustomDepartment(String dept) async {
    final list = getCustomDepartments();
    if (!list.contains(dept)) {
      list.add(dept);
      await settingsBox.put('global_custom_departments', list);
      await settingsBox.flush();
    }
  }

  static List<String> getCustomBanks() {
    final val = settingsBox.get('global_custom_banks');
    if (val is List) {
      return List<String>.from(val);
    }
    return [];
  }

  static Future<void> addCustomBank(String bank) async {
    final list = getCustomBanks();
    if (!list.contains(bank)) {
      list.add(bank);
      await settingsBox.put('global_custom_banks', list);
      await settingsBox.flush();
    }
  }

  static List<Map<String, dynamic>> getCustomBranches() {
    final val = settingsBox.get('global_custom_branches');
    if (val is List) {
      return List<Map<String, dynamic>>.from(val.map((e) => Map<String, dynamic>.from(e as Map)));
    }
    return [];
  }

  static Future<void> addCustomBranch(String id, String name) async {
    final list = getCustomBranches();
    if (!list.any((b) => b['id'] == id)) {
      list.add({'id': id, 'name': name});
      await settingsBox.put('global_custom_branches', list.map((e) => Map<dynamic, dynamic>.from(e)).toList());
      await settingsBox.flush();
    }
    
    final box = Hive.box(LocalStorageService.branchesBox);
    await box.put(id, {'id': id, 'name': name});
    await box.flush();
  }

  static List<Map<String, dynamic>> getAllBranches(List<Map<String, dynamic>> originalBranches) {
    final list = List<Map<String, dynamic>>.from(originalBranches);
    final custom = getCustomBranches();
    for (final c in custom) {
      if (!list.any((b) => b['id'] == c['id'])) {
        list.add(c);
      }
    }
    return list;
  }

  // ── Firestore Download Operations ─────────────────────────────────────────
  static Future<void> downloadEmployees(String branchId, {bool force = false}) async {
    final key = 'employees_$branchId';
    if (!force && !_shouldRefresh(key)) {
      debugPrint('[FinanceLS] Skipping downloadEmployees — cache is fresh');
      return;
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snap;
      if (branchId == 'all' || branchId.isEmpty) {
        snap = await FirebaseFirestore.instance.collectionGroup('employees').get();
      } else {
        snap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('employees')
            .get();
      }

      final box = employeesBox;
      final Map<String, dynamic> updates = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final localId = data['localId'] as String? ?? doc.id;
        final localRecord = box.get(localId);
        if (localRecord is Map && localRecord['syncStatus'] == 'pending') {
          continue;
        }
        final docBranchId = data['branchId'] as String? ?? doc.reference.parent.parent?.id ?? branchId;

        final record = Map<String, dynamic>.from(data);
        record['id'] = localId;
        record['localId'] = localId;
        record['branchId'] = docBranchId;
        record['syncStatus'] = 'synced';

        for (final field in ['dob', 'cnicExpiry', 'joiningDate', 'exitDate', 'createdAt', 'updatedAt']) {
          if (record[field] is Timestamp) {
            record[field] = (record[field] as Timestamp).toDate().toIso8601String();
          }
        }

        updates[localId] = _sanitize(record);
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed(key);
      debugPrint('[FinanceLS] Downloaded ${snap.docs.length} employees');
    } catch (e) {
      debugPrint('[FinanceLS] downloadEmployees error: $e');
    }
  }

  static Future<void> downloadSalaryHistory(String branchId, {bool force = false}) async {
    final key = 'salary_history_$branchId';
    if (!force && !_shouldRefresh(key)) {
      debugPrint('[FinanceLS] Skipping downloadSalaryHistory — cache is fresh');
      return;
    }
    try {
      // NOTE: requires a Firestore composite index on (branchId) for this collectionGroup — create in Firebase console if query fails with FAILED_PRECONDITION.
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collectionGroup('salary_history');
      if (branchId != 'all' && branchId.isNotEmpty) {
        q = q.where('branchId', isEqualTo: branchId);
      }
      final snap = await q.get();
      final box = salaryHistoryBox;
      final Map<String, dynamic> updates = {};
      for (final doc in snap.docs) {
        final pathSegments = doc.reference.path.split('/');
        if (pathSegments.length >= 6) {
          final docBranchId = pathSegments[1];
          final employeeId = pathSegments[3];
          final historyId = doc.id;

          if (branchId != 'all' && branchId.isNotEmpty && docBranchId != branchId) {
            continue;
          }

          final key = '${employeeId}_$historyId';
          final localRecord = box.get(key);
          if (localRecord is Map && localRecord['syncStatus'] == 'pending') {
            continue;
          }

          final data = doc.data();
          final record = Map<String, dynamic>.from(data);
          record['id'] = historyId;
          record['localId'] = historyId;
          record['syncStatus'] = 'synced';

          for (final field in ['effectiveDate', 'createdAt', 'updatedAt']) {
            if (record[field] is Timestamp) {
              record[field] = (record[field] as Timestamp).toDate().toIso8601String();
            }
          }

          updates[key] = _sanitize(record);
        }
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed('salary_history_$branchId');
      debugPrint('[FinanceLS] Downloaded salary history');
    } catch (e) {
      debugPrint('[FinanceLS] downloadSalaryHistory error: $e');
    }
  }

  static Future<void> downloadAttendance(String branchId, {bool force = false}) async {
    final key = 'attendance_$branchId';
    if (!force && !_shouldRefresh(key)) {
      debugPrint('[FinanceLS] Skipping downloadAttendance — cache is fresh');
      return;
    }
    try {
      // NOTE: requires a Firestore composite index on (branchId) for this collectionGroup — create in Firebase console if query fails with FCON.
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collectionGroup('records');
      if (branchId != 'all' && branchId.isNotEmpty) {
        q = q.where('branchId', isEqualTo: branchId);
      }
      final snap = await q.get();
      final box = attendanceBox;
      final Map<String, dynamic> updates = {};
      for (final doc in snap.docs) {
        final pathSegments = doc.reference.path.split('/');
        if (pathSegments.length >= 6 && pathSegments[2] == 'employee_attendance') {
          final docBranchId = pathSegments[1];
          final dateStr = pathSegments[3];
          final employeeId = doc.id;

          if (branchId != 'all' && branchId.isNotEmpty && docBranchId != branchId) {
            continue;
          }

          final key = '${employeeId}_$dateStr';
          final localRecord = box.get(key);
          if (localRecord is Map && localRecord['syncStatus'] == 'pending') {
            continue;
          }

          final data = doc.data();
          final record = Map<String, dynamic>.from(data);
          record['syncStatus'] = 'synced';

          for (final field in ['markedAt', 'createdAt', 'updatedAt']) {
            if (record[field] is Timestamp) {
              record[field] = (record[field] as Timestamp).toDate().toIso8601String();
            }
          }

          updates[key] = _sanitize(record);
        }
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed('attendance_$branchId');
      debugPrint('[FinanceLS] Downloaded attendance');
    } catch (e) {
      debugPrint('[FinanceLS] downloadAttendance error: $e');
    }
  }

  static Future<void> downloadSalaryLedger(String branchId, {bool force = false}) async {
    final key = 'salary_ledger_$branchId';
    if (!force && !_shouldRefresh(key)) {
      debugPrint('[FinanceLS] Skipping downloadSalaryLedger — cache is fresh');
      return;
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snap;
      if (branchId == 'all' || branchId.isEmpty) {
        snap = await FirebaseFirestore.instance.collectionGroup('employee_salaries').get();
      } else {
        snap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('employee_salaries')
            .get();
      }

      final box = salaryLedgerBox;
      final Map<String, dynamic> updates = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final recordId = data['localId'] as String? ?? doc.id;
        final localRecord = box.get(recordId);
        if (localRecord is Map && localRecord['syncStatus'] == 'pending') {
          continue;
        }
        final docBranchId = data['branchId'] as String? ?? doc.reference.parent.parent?.id ?? branchId;

        final record = Map<String, dynamic>.from(data);
        record['id'] = recordId;
        record['localId'] = recordId;
        record['branchId'] = docBranchId;
        record['syncStatus'] = 'synced';

        for (final field in ['date', 'createdAt', 'updatedAt', 'voidedAt']) {
          if (record[field] is Timestamp) {
            record[field] = (record[field] as Timestamp).toDate().toIso8601String();
          }
        }

        updates[recordId] = _sanitize(record);
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed(key);
      debugPrint('[FinanceLS] Downloaded ${snap.docs.length} ledger entries');
    } catch (e) {
      debugPrint('[FinanceLS] downloadSalaryLedger error: $e');
    }
  }

  static Future<void> downloadFinanceSettings(String branchId, {bool force = false}) async {
    final key = 'finance_settings_$branchId';
    if (!force && !_shouldRefresh(key)) {
      debugPrint('[FinanceLS] Skipping downloadFinanceSettings — cache is fresh');
      return;
    }
    try {
      final box = settingsBox;
      final Map<String, dynamic> updates = {};
      if (branchId == 'all' || branchId.isEmpty) {
        final snap = await FirebaseFirestore.instance.collectionGroup('settings').get();
        for (final doc in snap.docs) {
          if (doc.id == 'workSchedule') {
            final data = doc.data();
            final docBranchId = doc.reference.parent.parent?.id;
            if (docBranchId != null) {
              final record = Map<String, dynamic>.from(data);
              record['branchId'] = docBranchId;
              record['syncStatus'] = 'synced';
              updates[docBranchId] = _sanitize(record);
            }
          }
        }
      } else {
        final doc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('settings')
            .doc('workSchedule')
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          final record = Map<String, dynamic>.from(data);
          record['branchId'] = branchId;
          record['syncStatus'] = 'synced';
          updates[branchId] = _sanitize(record);
        }
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed(key);
      debugPrint('[FinanceLS] Downloaded settings');
    } catch (e) {
      debugPrint('[FinanceLS] downloadFinanceSettings error: $e');
    }
  }

  static Future<void> downloadTransfers(String branchId, {bool force = false}) async {
    final key = 'transfers_$branchId';
    if (!force && !_shouldRefresh(key)) {
      debugPrint('[FinanceLS] Skipping downloadTransfers — cache is fresh');
      return;
    }
    try {
      // NOTE: requires a Firestore composite index on (branchId) for this collectionGroup — create in Firebase console if query fails with FAILED_PRECONDITION.
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collectionGroup('branch_transfers');
      if (branchId != 'all' && branchId.isNotEmpty) {
        q = q.where('branchId', isEqualTo: branchId);
      }
      final snap = await q.get();
      final box = transfersBox;
      final Map<String, dynamic> updates = {};
      for (final doc in snap.docs) {
        final pathSegments = doc.reference.path.split('/');
        if (pathSegments.length >= 6) {
          final docBranchId = pathSegments[1];
          final transferId = doc.id;

          if (branchId != 'all' && branchId.isNotEmpty && docBranchId != branchId) {
            continue;
          }

          final localRecord = box.get(transferId);
          if (localRecord is Map && localRecord['syncStatus'] == 'pending') {
            continue;
          }

          final data = doc.data();
          final record = Map<String, dynamic>.from(data);
          record['id'] = transferId;
          record['localId'] = transferId;
          record['syncStatus'] = 'synced';

          for (final field in ['effectiveDate', 'createdAt', 'updatedAt']) {
            if (record[field] is Timestamp) {
              record[field] = (record[field] as Timestamp).toDate().toIso8601String();
            }
          }

          updates[transferId] = _sanitize(record);
        }
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed('transfers_$branchId');
      debugPrint('[FinanceLS] Downloaded transfers');
    } catch (e) {
      debugPrint('[FinanceLS] downloadTransfers error: $e');
    }
  }

  static Future<void> downloadAuditLogs(String branchId, {bool force = false}) async {
    final ttlKey = 'audit_logs_$branchId';
    if (!force && !_shouldRefresh(ttlKey)) {
      debugPrint('[FinanceLS] Skipping downloadAuditLogs — cache is fresh');
      return;
    }
    try {
      final sBox = Hive.box(LocalStorageService.financeSettingsBox);
      final lastSyncRaw = sBox.get('__audit_last_ts_$branchId') as String?;
      Timestamp? lastSyncTs;
      if (lastSyncRaw != null) {
        final parsed = DateTime.tryParse(lastSyncRaw);
        if (parsed != null) lastSyncTs = Timestamp.fromDate(parsed);
      }

      final QuerySnapshot<Map<String, dynamic>> snap;
      if (branchId == 'all' || branchId.isEmpty) {
        var q = FirebaseFirestore.instance
            .collectionGroup('audit_logs')
            .where('module', isEqualTo: 'finance');
        if (lastSyncTs != null) q = q.where('timestamp', isGreaterThan: lastSyncTs);
        snap = await q.get();
      } else {
        var q = FirebaseFirestore.instance
            .collection('branches').doc(branchId).collection('audit_logs')
            .where('module', isEqualTo: 'finance');
        if (lastSyncTs != null) q = q.where('timestamp', isGreaterThan: lastSyncTs);
        snap = await q.get();
      }

      final box = auditLogsBox;
      final Map<String, dynamic> updates = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['module'] != 'finance') continue;

        final logId = data['id'] as String? ?? doc.id;
        final docBranchId = data['branchContext'] as String? ?? doc.reference.parent.parent?.id ?? branchId;

        final record = Map<String, dynamic>.from(data);
        record['id'] = logId;
        record['localId'] = logId;
        record['branchContext'] = docBranchId;
        record['syncStatus'] = 'synced';

        for (final field in ['timestamp', 'updatedAt']) {
          if (record[field] is Timestamp) {
            record[field] = (record[field] as Timestamp).toDate().toIso8601String();
          }
        }

        updates[logId] = _sanitize(record);
      }
      if (snap.docs.isNotEmpty) {
        await sBox.put('__audit_last_ts_$branchId', DateTime.now().toUtc().toIso8601String());
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed(ttlKey);
      debugPrint('[FinanceLS] Downloaded ${snap.docs.length} audit logs (incremental)');
    } catch (e) {
      debugPrint('[FinanceLS] downloadAuditLogs error: $e');
    }
  }

  static Future<void> downloadFinanceHolidays(String branchId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('finance_holidays')
          .get();

      final box = Hive.box(LocalStorageService.financeHolidaysBox);
      final prefix = '${branchId.toLowerCase().trim()}__hol__';
      
      // Clear existing cached holidays for this branch first
      final keysToDelete = box.keys.where((k) => k.toString().startsWith(prefix)).toList();
      await box.deleteAll(keysToDelete);

      final Map<String, dynamic> holidayUpdates = {};
      for (final doc in snap.docs) {
        final key = '$prefix${doc.id}';
        holidayUpdates[key] = _sanitize(doc.data());
      }
      if (holidayUpdates.isNotEmpty) {
        await box.putAll(holidayUpdates);
      }
      await box.flush();
      debugPrint('[FinanceLS] Downloaded and cached ${snap.docs.length} finance holidays.');
    } catch (e) {
      debugPrint('[FinanceLS] Error downloading finance holidays: $e');
    }
  }

  static Future<void> downloadLoans(String branchId, {bool force = false}) async {
    final key = 'loans_$branchId';
    if (!force && !_shouldRefresh(key)) {
      debugPrint('[FinanceLS] Skipping downloadLoans — cache is fresh');
      return;
    }
    try {
      final QuerySnapshot<Map<String, dynamic>> snap;
      if (branchId == 'all' || branchId.isEmpty) {
        snap = await FirebaseFirestore.instance.collectionGroup('finance_loans').get();
      } else {
        snap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('finance_loans')
            .get();
      }

      final box = Hive.box(LocalStorageService.financeLoansBox);
      final Map<String, dynamic> updates = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final loanId = data['localId'] as String? ?? doc.id;
        final localRecord = box.get(loanId);
        if (localRecord is Map && localRecord['syncStatus'] == 'pending') {
          continue;
        }
        final docBranchId = data['branchId'] as String? ?? doc.reference.parent.parent?.id ?? branchId;

        final record = Map<String, dynamic>.from(data);
        record['id'] = loanId;
        record['localId'] = loanId;
        record['branchId'] = docBranchId;
        record['syncStatus'] = 'synced';

        for (final field in ['dateIssued', 'closedAt', 'createdAt', 'updatedAt']) {
          if (record[field] is Timestamp) {
            record[field] = (record[field] as Timestamp).toDate().toIso8601String();
          }
        }

        updates[loanId] = _sanitize(record);
      }
      if (updates.isNotEmpty) {
        await box.putAll(updates);
      }
      await box.flush();
      await _markRefreshed(key);
      debugPrint('[FinanceLS] Downloaded ${snap.docs.length} loans');
    } catch (e) {
      debugPrint('[FinanceLS] downloadLoans error: $e');
    }
  }

  static Future<void> downloadAllFinanceData(String branchId) async {
    await downloadEmployees(branchId);
    await downloadSalaryHistory(branchId);
    await downloadAttendance(branchId);
    await downloadSalaryLedger(branchId);
    await downloadFinanceSettings(branchId);
    await downloadTransfers(branchId);
    await downloadAuditLogs(branchId);
    await downloadFinanceHolidays(branchId);
    await downloadLoans(branchId);
  }

  // ── Smart User-Employee Linking Helpers ─────────────────────────────────────

  /// Helper to sanitize CNIC numbers by removing dashes, spaces, and slashes
  static String _cleanCnic(String cnic) {
    return cnic.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Automatically finds matching Employee for a User based on:
  /// 1. CNIC Match (highest confidence)
  /// 2. Email Match
  /// 3. Name + Department + Role Match
  static Map<String, dynamic>? findMatchingEmployeeForUser({
    required String branchId,
    String? cnic,
    String? email,
    String? username,
    String? department,
    String? role,
  }) {
    if (!Hive.isBoxOpen(LocalStorageService.employeesBox)) return null;
    final empBox = Hive.box(LocalStorageService.employeesBox);

    final cleanCnic = (cnic != null && cnic.isNotEmpty) ? _cleanCnic(cnic) : '';
    final cleanEmail = email?.trim().toLowerCase() ?? '';
    final cleanName = username?.trim().toLowerCase() ?? '';
    final cleanDept = department?.trim().toLowerCase() ?? '';
    final cleanRole = role?.trim().toLowerCase() ?? '';

    Map<String, dynamic>? bestMatch;
    String matchReason = '';

    for (var val in empBox.values) {
      if (val is Map) {
        final emp = Map<String, dynamic>.from(val);

        // Filter by branch if applicable
        final empBranch = emp['branchId']?.toString() ?? '';
        if (branchId.isNotEmpty && empBranch.isNotEmpty && empBranch != branchId && empBranch != 'all') {
          continue;
        }

        final empCnic = _cleanCnic(emp['cnic']?.toString() ?? emp['identification']?.toString() ?? '');
        final empEmail = (emp['email']?.toString() ?? '').trim().toLowerCase();
        final empName = (emp['name']?.toString() ?? '').trim().toLowerCase();
        final empDept = (emp['department']?.toString() ?? '').trim().toLowerCase();
        final empRole = (emp['designation']?.toString() ?? emp['role']?.toString() ?? '').trim().toLowerCase();

        // 1. Check CNIC Match
        if (cleanCnic.length >= 10 && empCnic.length >= 10 && cleanCnic == empCnic) {
          bestMatch = emp;
          matchReason = 'Matched by CNIC ($cleanCnic)';
          break; // Highest priority match
        }

        // 2. Check Email Match
        if (bestMatch == null && cleanEmail.isNotEmpty && empEmail.isNotEmpty && cleanEmail == empEmail) {
          bestMatch = emp;
          matchReason = 'Matched by Email ($cleanEmail)';
        }

        // 3. Check Name + Department + Role Match
        if (bestMatch == null && cleanName.isNotEmpty && empName.isNotEmpty && cleanName == empName) {
          final deptMatches = cleanDept.isEmpty || empDept.isEmpty || cleanDept == empDept;
          final roleMatches = cleanRole.isEmpty || empRole.isEmpty || cleanRole == empRole;
          if (deptMatches && roleMatches) {
            bestMatch = emp;
            matchReason = 'Matched by Name ($empName) & Department/Role';
          }
        }
      }
    }

    if (bestMatch != null) {
      final res = Map<String, dynamic>.from(bestMatch);
      res['matchReason'] = matchReason;
      return res;
    }

    return null;
  }

  /// Manually or Programmatically links a User account to an Employee profile
  static Future<bool> linkUserToEmployee({
    required String userId,
    required String employeeId,
  }) async {
    try {
      // 1. Update User Record in local_users
      if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
        final usersBox = Hive.box(LocalStorageService.usersBox);
        final userRaw = usersBox.get(userId);
        if (userRaw is Map) {
          final uMap = Map<String, dynamic>.from(userRaw);
          uMap['employeeId'] = employeeId;
          await usersBox.put(userId, uMap);
          await usersBox.flush();
        }
      }

      // 2. Update Employee Record in local_employees
      if (Hive.isBoxOpen(LocalStorageService.employeesBox)) {
        final empBox = Hive.box(LocalStorageService.employeesBox);
        final empRaw = empBox.get(employeeId);
        if (empRaw is Map) {
          final eMap = Map<String, dynamic>.from(empRaw);
          eMap['userId'] = userId;
          await empBox.put(employeeId, eMap);
          await empBox.flush();
        }
      }

      // 3. Update Firestore if online
      try {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({'employeeId': employeeId});
        await FirebaseFirestore.instance.collection('employees').doc(employeeId).update({'userId': userId});
      } catch (e) {
        debugPrint('[FinanceLS] Firestore user-employee link update warning: $e');
      }

      debugPrint('[FinanceLS] Successfully linked User $userId <-> Employee $employeeId');
      return true;
    } catch (e) {
      debugPrint('[FinanceLS] Error linking user to employee: $e');
      return false;
    }
  }

  /// Creates or updates a unified Employee profile for an App User account.
  /// Guarantees that registering a user automatically registers them as an Employee in Finance & HR.
  static Future<String> createOrUpdateUnifiedEmployeeProfile({
    required String userId,
    required String username,
    required String email,
    required String role,
    required String branchId,
    String? cnic,
    String? phone,
    String? department,
    double? baseSalary,
    String? bankName,
    String? bankAccount,
    String? profilePictureUrl,
  }) async {
    try {
      final empBox = employeesBox;

      // 1. Check if employee already exists for this user ID, CNIC, or Email
      Map<String, dynamic>? existingEmp = findMatchingEmployeeForUser(
        branchId: branchId,
        cnic: cnic,
        email: email,
        username: username,
        department: department,
        role: role,
      );

      String empId = existingEmp?['id']?.toString() ?? existingEmp?['localId']?.toString() ?? '';
      if (empId.isEmpty) {
        empId = 'EMP_${DateTime.now().millisecondsSinceEpoch}';
      }

      final deptName = (department != null && department.isNotEmpty)
          ? department
          : (role.toLowerCase().contains('doc') ? 'Dispensary' : 'Office');

      final empData = <String, dynamic>{
        'id': empId,
        'localId': empId,
        'userId': userId,
        'linkedUserId': userId,
        'name': username,
        'email': email.trim().toLowerCase(),
        'phone': phone ?? '',
        'cnic': cnic ?? '',
        'identification': cnic ?? '',
        'role': role,
        'designation': role,
        'department': deptName,
        'branchId': branchId,
        'currentSalary': baseSalary ?? 0.0,
        'baseSalary': baseSalary ?? 0.0,
        'bankName': bankName ?? 'Cash',
        'bankAccount': bankAccount ?? '',
        'profilePictureUrl': profilePictureUrl ?? '',
        'isActive': true,
        'status': 'Active',
        'joiningDate': _nowIso(),
        'createdAt': _nowIso(),
        'updatedAt': _nowIso(),
        'syncStatus': 'synced',
      };

      if (existingEmp != null) {
        final merged = Map<String, dynamic>.from(existingEmp)..addAll(empData);
        await empBox.put(empId, _sanitize(merged));
      } else {
        await empBox.put(empId, _sanitize(empData));
      }
      await empBox.flush();

      // 2. Link in User record
      await linkUserToEmployee(userId: userId, employeeId: empId);

      // 3. Sync to Firestore
      try {
        await FirebaseFirestore.instance.collection('employees').doc(empId).set(empData, SetOptions(merge: true));
        await FirebaseFirestore.instance.collection('users').doc(userId).set({'employeeId': empId}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[FinanceLS] Firestore unified employee sync warning: $e');
      }

      debugPrint('[FinanceLS] Successfully unified User $userId -> Employee $empId');
      return empId;
    } catch (e) {
      debugPrint('[FinanceLS] Error creating unified employee profile: $e');
      return '';
    }
  }
}
