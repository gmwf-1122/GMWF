// lib/services/finance_local_storage.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'local_storage_service.dart';
import 'finance_loans_storage.dart';

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
  static bool _shouldRefresh(String key, {Duration ttl = const Duration(minutes: 60)}) {
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

    // CNIC validation check
    final cnic = (data['cnic'] as String? ?? '').trim();
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

    // Recalculate displays
    record['currentAdvanceBalance'] = getAdvanceBalance(localId);

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

    // Queue Sync
    await LocalStorageService.enqueueSync({
      'type': 'save_employee',
      'branchId': branchId,
      'localId': localId,
      'data': sanitized,
    });

    return localId;
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

  static Future<void> deleteEmployeePermanently({
    required String branchId,
    required String employeeId,
    required String performedBy,
  }) async {
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
      reason: 'Permanently deleted employee profile.',
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

    final historyRecord = {
      'id': localId,
      'localId': localId,
      'remoteId': null,
      'updatedAt': now,
      'syncStatus': 'pending',
      'lastSyncedAt': null,
      'amount': amount,
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
      final latest = historyList.isNotEmpty ? historyList.first['amount'] : amount;
      emp['currentSalary'] = (latest as num).toDouble();
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
      return (emp?['currentSalary'] as num?)?.toDouble() ?? 0.0;
    }

    final targetDate = DateTime(date.year, date.month, date.day);

    for (final h in history) {
      final effDateStr = h['effectiveDate']?.toString();
      if (effDateStr == null) continue;
      final effDate = DateTime.tryParse(effDateStr);
      if (effDate == null) continue;

      final effDay = DateTime(effDate.year, effDate.month, effDate.day);
      if (effDay.isBefore(targetDate) || effDay.isAtSameMomentAs(targetDate)) {
        return (h['amount'] as num).toDouble();
      }
    }

    return (history.last['amount'] as num).toDouble();
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

      final activeSalaryRate = getSalaryRateForDay(employeeId, date);
      final dailyRate = activeSalaryRate / daysInMonth;
      fullMonthWeightedSalary += dailyRate;

      if (!isEmployed) continue;

      totalEmployedDays++;

      // Future dates are neutral for salary — nothing earned, nothing
      // deducted, and they don't count as "unmarked" either, since the
      // day simply hasn't happened yet.
      final isFutureDay = date.isAfter(todayDateOnly);
      if (isFutureDay) continue;

      baseSalaryEarned += dailyRate;

      final key = '${employeeId}_$dateStr';
      final val = attendanceBox.get(key);
      final hasRecord = val != null;

      if (!hasRecord && date.weekday != DateTime.sunday) {
        unmarkedDays++;
      }

      String status;
      String? leaveType;
      String? overtimeDuration;

      if (val is Map) {
        status = val['status']?.toString() ?? 'absent';
        leaveType = val['leaveType']?.toString();
        overtimeDuration = val['overtimeDuration']?.toString();
      } else {
        // Defaults: Sunday defaults to 'off', other days default to 'unmarked'
        if (date.weekday == DateTime.sunday) {
          status = 'off';
        } else {
          status = 'unmarked';
        }
        leaveType = null;
        overtimeDuration = null;
      }

      final isHolidayDay = isHoliday(
        branchId: branchId,
        department: employeeDept,
        dateStr: dateStr,
      );
      if (isHolidayDay) {
        holidayCount++;
      }

      if (date.weekday == DateTime.sunday) {
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

    final sanitized = _sanitize(record);
    await salaryLedgerBox.put(localId, sanitized);
    await salaryLedgerBox.flush();

    // Trigger update of parent employee cached advance balance
    final employeeId = data['employeeId'] as String;
    final emp = getEmployee(employeeId);
    if (emp != null) {
      emp['currentAdvanceBalance'] = getAdvanceBalance(employeeId);
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
      emp['currentAdvanceBalance'] = getAdvanceBalance(employeeId);
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

          final key = '${employeeId}_$historyId';
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

          final data = doc.data();
          final record = Map<String, dynamic>.from(data);
          record['syncStatus'] = 'synced';

          for (final field in ['markedAt', 'createdAt', 'updatedAt']) {
            if (record[field] is Timestamp) {
              record[field] = (record[field] as Timestamp).toDate().toIso8601String();
            }
          }

          final key = '${employeeId}_$dateStr';
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

        if (record['payments'] is List) {
          final paymentsList = List<dynamic>.from(record['payments'] as List);
          final sanitizedPayments = <Map<String, dynamic>>[];
          for (final p in paymentsList) {
            if (p is Map) {
              final pMap = Map<String, dynamic>.from(p);
              for (final field in ['date', 'createdAt', 'voidedAt']) {
                if (pMap[field] is Timestamp) {
                  pMap[field] = (pMap[field] as Timestamp).toDate().toIso8601String();
                }
              }
              sanitizedPayments.add(pMap);
            }
          }
          record['payments'] = sanitizedPayments;
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
}
