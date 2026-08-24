// lib/services/local_storage_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:gmwf/services/sync_service.dart';
import 'camp_session_service.dart';
import 'master_proforma_service.dart';
import 'serials_service.dart';
import '../tools/legacy_data_migration_adapter.dart';

class LocalStorageService {
  // ── Box names ──────────────────────────────────────────────────────────────
  static const String usersBox         = 'local_users';
  static const String branchCacheBox = 'branch_data_cache';
  static const String patientsBox      = 'local_patients';
  static const String entriesBox       = 'local_entries';
  static const String syncBox          = 'sync_queue';
  static const String prescriptionsBox = 'local_prescriptions';
  static const String stockBox         = 'local_stock_items';
  static const String branchesBox      = 'local_branches';
  static const String dispensaryBox    = 'local_dispensary';
  static const String medicineRestrictionsBox = 'local_medicine_restrictions';
  static const String masterProformaBox       = 'master_proforma_catalog';
  static const String donationsBox     = 'local_donations';
  static const String donorsBox        = 'local_donors';
  static const String reportsCacheBox   = 'local_reports_cache';
  
  static const String employeesBox       = 'local_employees';
  static const String salaryHistoryBox   = 'local_salary_history';
  static const String attendanceBox      = 'local_employee_attendance';
  static const String salaryLedgerBox    = 'local_employee_salaries';
  static const String financeSettingsBox = 'local_finance_settings';
  static const String branchTransfersBox = 'local_employee_branch_transfers';
  static const String auditLogsBox       = 'local_audit_logs';

  static const String madrassaStudentsBox = 'local_madrassa_students';
  static const String madrassaLogsBox     = 'local_madrassa_logs';
  static const String madrassaHolidaysBox = 'local_madrassa_holidays';
  static const String schoolStudentsBox   = 'local_school_students';
  static const String schoolLogsBox       = 'local_school_logs';
  static const String schoolTeachersBox   = 'local_school_teachers';
  static const String schoolBooksBox      = 'local_school_books';
  static const String schoolBookLoansBox  = 'local_school_book_loans';
  static const String schoolAuditLogsBox  = 'local_school_audit_logs';
  static const String schoolGradesBox     = 'local_school_grades';
  static const String schoolFeesBox       = 'local_school_fees';
  static const String schoolHomeroomBox   = 'local_school_homeroom';
  static const String financeHolidaysBox = 'local_finance_holidays';
  static const String financeLoansBox    = 'local_finance_loans';
  static const String expensesBox        = 'local_expenses';
  static const String syncMetaBox        = 'local_sync_meta';

  static const String biometricDevicesBox = 'local_biometric_devices';
  static const String biometricCredentialsBox = 'local_biometric_credentials';
  static const String unmappedPunchesBox = 'local_unmapped_punches';
  static const String crossBranchPunchesBox = 'local_cross_branch_punches';
  static const String tokenExceptionsBox = 'local_token_exceptions';

  // ── ERP Double-Entry Ledger Boxes ───────────────────────────────────────────
  static const String chartOfAccountsBox  = 'org_chart_of_accounts';
  static const String orgBankAccountsBox  = 'org_bank_accounts';

  static Map<String, List<Map<String, String>>> getDefaultBranchFacilities(String branchId) {
    final b = branchId.toLowerCase().trim();
    if (b.contains('gujrat')) {
      return {
        'dispensaries': [{'id': 'main_dispensary', 'name': 'Dispensary'}],
        'dasterkhwaans': [{'id': 'main_dasterkhwaan', 'name': 'Dasterkhwaan'}],
        'madrassas': [{'id': 'main_madrassa', 'name': 'Madrassa'}],
        'schools': [{'id': 'main_school', 'name': 'School'}],
      };
    } else if (b.contains('sialkot')) {
      return {
        'dispensaries': [{'id': 'main_dispensary', 'name': 'Dispensary'}],
        'dasterkhwaans': [{'id': 'main_dasterkhwaan', 'name': 'Dasterkhwaan'}],
        'madrassas': [],
        'schools': [],
      };
    } else if (b.contains('rawalpindi') || b.contains('pindi')) {
      return {
        'dispensaries': [{'id': 'main_dispensary', 'name': 'Dispensary'}],
        'dasterkhwaans': [{'id': 'main_dasterkhwaan', 'name': 'Dasterkhwaan'}],
        'madrassas': [],
        'schools': [],
      };
    } else if (b.contains('karachi')) {
      return {
        'dispensaries': [
          {'id': 'saddar', 'name': 'Saddar Dispensary'},
          {'id': 'haji_camp', 'name': 'Haji Camp Dispensary'},
        ],
        'dasterkhwaans': [{'id': 'main_dasterkhwaan', 'name': 'Dasterkhwaan'}],
        'madrassas': [{'id': 'main_madrassa', 'name': 'Madrassa'}],
        'schools': [],
      };
    }

    return {
      'dispensaries': [{'id': 'main_dispensary', 'name': 'Dispensary'}],
      'dasterkhwaans': [{'id': 'main_dasterkhwaan', 'name': 'Dasterkhwaan'}],
      'madrassas': [],
      'schools': [],
    };
  }

  static bool hasSchoolFacility(String branchId) {
    final b = branchId.toLowerCase().trim();
    if (b == 'all' || b == 'global' || b.isEmpty) return true;

    if (Hive.isBoxOpen(branchesBox)) {
      final box = Hive.box(branchesBox);
      final raw = box.get('branch:$b');
      if (raw is Map) {
        final facs = raw['facilities'];
        if (facs is Map) {
          final schools = facs['schools'];
          if (schools is List && schools.isNotEmpty) return true;
        }
      }
    }

    final defaults = getDefaultBranchFacilities(branchId);
    final defaultSchools = defaults['schools'];
    return defaultSchools != null && defaultSchools.isNotEmpty;
  }

  static String getBranchName(String branchId) {
    final b = branchId.toLowerCase().trim();
    if (b.contains('gujrat')) return 'Gujrat';
    if (b.contains('sialkot')) return 'Sialkot';
    if (b.contains('pindi') || b.contains('rawalpindi')) return 'Rawalpindi';
    if (b.contains('karachi')) return 'Karachi';
    if (b.isEmpty || b == 'all' || b == 'global') return 'All Branches';
    return branchId.isNotEmpty ? branchId[0].toUpperCase() + branchId.substring(1) : branchId;
  }
  static const String journalEntriesBox   = 'local_finance_journal_entries';
  static const String journalIndexBox     = 'local_finance_journal_index';
  static const String departmentMapBox    = 'local_finance_department_map';

  static String? _hiveDirPath;

  static void setHiveDirectoryPath(String path) {
    _hiveDirPath = path;
  }

  static Future<Box<T>> openBoxSafe<T>(String name) async {
    try {
      return await Hive.openBox<T>(name).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException("Timeout (30s) opening Hive box: $name");
        },
      );
    } on TimeoutException catch (tex, st) {
      debugPrint('[LocalStorageService] ⚠️ Timeout opening "$name" (30s). Retrying once (15s)...');
      await _logStorageError(name, 'Initial open timed out: $tex', st);

      if (Hive.isBoxOpen(name)) {
        debugPrint('[LocalStorageService] ✅ Box "$name" completed opening in background during timeout window.');
        return Hive.box<T>(name);
      }

      try {
        await Future.delayed(const Duration(milliseconds: 500));
        if (Hive.isBoxOpen(name)) {
          debugPrint('[LocalStorageService] ✅ Box "$name" completed opening in background after 500ms delay.');
          return Hive.box<T>(name);
        }
        return await Hive.openBox<T>(name).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException("Retry timeout (15s) opening Hive box: $name");
          },
        );
      } catch (retryEx, retrySt) {
        if (Hive.isBoxOpen(name)) {
          debugPrint('[LocalStorageService] ✅ Box "$name" is open despite retry exception.');
          return Hive.box<T>(name);
        }
        final errStr = retryEx.toString().toLowerCase();
        final isLockError = errStr.contains('lock') || errStr.contains('already open');
        if (isLockError) {
          debugPrint('[LocalStorageService] ⚠️ Lock contention for "$name". Preserving box file on disk without deletion.');
          await _logStorageError(name, 'Lock contention error: $retryEx', retrySt);
          await _surfaceRecoveryNeededEvent(name, 'Lock Contention: $retryEx', false, isTimeout: true);
          rethrow;
        }
        debugPrint('[LocalStorageService] ❌ Retry open timed out for "$name". Preserving box file on disk without deletion.');
        await _logStorageError(name, 'Retry open timed out: $retryEx', retrySt);
        await _surfaceRecoveryNeededEvent(name, 'Timeout: Box file preserved on disk without deletion', false, isTimeout: true);
        rethrow; // DO NOT DELETE BOX ON TIMEOUT
      }
    } catch (e, st) {
      debugPrint('[LocalStorageService] ⚠️ Open attempt failed for "$name": $e. Retrying once before backup...');
      await _logStorageError(name, 'Initial open failed: $e', st);

      if (Hive.isBoxOpen(name)) {
        return Hive.box<T>(name);
      }

      try {
        await Future.delayed(const Duration(milliseconds: 500));
        if (Hive.isBoxOpen(name)) {
          return Hive.box<T>(name);
        }
        return await Hive.openBox<T>(name).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException("Retry timeout (15s) opening Hive box: $name");
          },
        );
      } catch (retryEx, retrySt) {
        if (Hive.isBoxOpen(name)) {
          return Hive.box<T>(name);
        }
        debugPrint('[LocalStorageService] ❌ Retry failed for "$name": $retryEx. Proceeding to backup + single-box recovery.');
        await _logStorageError(name, 'Retry open failed: $retryEx', retrySt);

        final backupCreated = await _backupCorruptedBoxFiles(name);

        await _surfaceRecoveryNeededEvent(name, retryEx.toString(), backupCreated, isTimeout: false);

        try {
          debugPrint('[LocalStorageService] Resetting single box "$name" after securing backup (backupCreated: $backupCreated)...');
          await Hive.deleteBoxFromDisk(name);
          return await Hive.openBox<T>(name);
        } catch (err, errSt) {
          debugPrint('[LocalStorageService] ❌ Failed to recreate box "$name": $err');
          await _logStorageError(name, 'Recreation failed: $err', errSt);
          rethrow;
        }
      }
    }
  }

  static Future<void> _logStorageError(String boxName, String error, StackTrace? st) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final logFile = File(p.join(appDir.path, 'gmwf_storage_errors.log'));
      
      if (await logFile.exists()) {
        final length = await logFile.length();
        if (length > 512000) {
          final oldFile = File(p.join(appDir.path, 'gmwf_storage_errors.log.old'));
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
          await logFile.rename(oldFile.path);
        }
      }

      final logEntry = '${DateTime.now().toIso8601String()} [STORAGE_ERROR] Box: $boxName | $error\nStack: ${st ?? "N/A"}\n---\n';
      await logFile.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      debugPrint('[LocalStorageService] Failed to write storage error log: $e');
    }
  }

  static Future<String?> _getHiveDirectoryPath() async {
    try {
      final sampleBoxes = ['app_settings', usersBox, entriesBox, patientsBox, syncBox];
      for (final name in sampleBoxes) {
        if (Hive.isBoxOpen(name)) {
          final boxPath = Hive.box(name).path;
          if (boxPath != null && boxPath.isNotEmpty) {
            return p.dirname(boxPath);
          }
        }
      }
      final appSupportDir = await getApplicationSupportDirectory();
      if (!kIsWeb && Platform.isWindows) {
        final winHiveDir = p.join(appSupportDir.path, 'gmwf_hive');
        if (await Directory(winHiveDir).exists()) {
          return winHiveDir;
        }
      }
      return appSupportDir.path;
    } catch (e) {
      debugPrint('[LocalStorageService] Error getting Hive directory path: $e');
      return null;
    }
  }

  static Future<bool> _backupCorruptedBoxFiles(String boxName) async {
    try {
      final hivePath = await _getHiveDirectoryPath();
      if (hivePath == null || hivePath.isEmpty) return false;
      final hiveDir = Directory(hivePath);
      if (!await hiveDir.exists()) return false;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      bool backedUp = false;

      await for (final entity in hiveDir.list()) {
        if (entity is File) {
          final fileName = p.basename(entity.path);
          if (fileName == '$boxName.hive' ||
              fileName == '$boxName.lock' ||
              fileName.startsWith('$boxName.')) {
            final backupPath = p.join(hiveDir.path, '${boxName}_corrupted_${nowMs}_$fileName.bak');
            await entity.copy(backupPath);
            debugPrint('[LocalStorageService] 🛡️ Corrupted box file backed up: $fileName -> ${p.basename(backupPath)}');
            backedUp = true;
          }
        }
      }
      return backedUp;
    } catch (e) {
      debugPrint('[LocalStorageService] Failed to backup box files for $boxName: $e');
      return false;
    }
  }

  static Future<void> _surfaceRecoveryNeededEvent(String boxName, String error, bool backupCreated, {bool isTimeout = false}) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final recoveryFile = File(p.join(appDir.path, 'gmwf_data_recovery_needed.json'));
      List<dynamic> existing = [];
      if (await recoveryFile.exists()) {
        try {
          final content = await recoveryFile.readAsString();
          existing = jsonDecode(content) as List<dynamic>;
        } catch (parseErr) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final corruptedJsonBackup = File(p.join(appDir.path, 'gmwf_data_recovery_needed_corrupted_$nowMs.json.bak'));
          await recoveryFile.copy(corruptedJsonBackup.path);
          debugPrint('[LocalStorageService] ⚠️ Recovery JSON corrupted. Backed up to ${p.basename(corruptedJsonBackup.path)}: $parseErr');
        }
      }
      existing.add({
        'boxName': boxName,
        'timestamp': DateTime.now().toIso8601String(),
        'error': error,
        'backupCreated': backupCreated,
        'isTimeout': isTimeout,
      });
      await recoveryFile.writeAsString(jsonEncode(existing));
    } catch (e) {
      debugPrint('[LocalStorageService] Failed to record recovery event: $e');
    }
  }

  static Future<List<File>> getUnrecoveredBackups() async {
    final List<File> backups = [];
    try {
      final hivePath = await _getHiveDirectoryPath();
      if (hivePath == null || hivePath.isEmpty) return backups;
      final hiveDir = Directory(hivePath);
      if (!await hiveDir.exists()) return backups;

      await for (final entity in hiveDir.list()) {
        if (entity is File && entity.path.contains('_corrupted_') && entity.path.endsWith('.bak')) {
          backups.add(entity);
        }
      }
    } catch (e) {
      debugPrint('[LocalStorageService] Error scanning for backup files: $e');
    }
    return backups;
  }

  static Future<void> checkForUnrecoveredBackups() async {
    final backups = await getUnrecoveredBackups();
    if (backups.isNotEmpty) {
      debugPrint('[LocalStorageService] ⚠️ WARNING: Found ${backups.length} unrecovered corrupted box backup (.bak) files on disk:');
      for (final f in backups) {
        debugPrint('  -> ${p.basename(f.path)} (${await f.length()} bytes)');
      }
    }
  }

  static Future<bool> restoreBoxFromBackup(String boxName, String backupFilePath) async {
    try {
      final backupFile = File(backupFilePath);
      if (!await backupFile.exists()) {
        debugPrint('[LocalStorageService] Restore failed: Backup file does not exist at $backupFilePath');
        return false;
      }

      final hivePath = await _getHiveDirectoryPath();
      if (hivePath == null || hivePath.isEmpty) return false;

      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }

      final targetHivePath = p.join(hivePath, '$boxName.hive');
      await backupFile.copy(targetHivePath);
      debugPrint('[LocalStorageService] ✅ Box "$boxName" restored from ${p.basename(backupFilePath)} -> $targetHivePath');

      await Hive.openBox(boxName);
      return true;
    } catch (e) {
      debugPrint('[LocalStorageService] ❌ Failed to restore box "$boxName" from backup: $e');
      return false;
    }
  }

  static Future<void> init() async {
    debugPrint('[LocalStorageService.init] Opening all Hive boxes...');
    await checkForUnrecoveredBackups();
    final boxNames = [
      usersBox,
      patientsBox,
      entriesBox,
      syncBox,
      prescriptionsBox,
      stockBox,
      branchesBox,
      dispensaryBox,
      branchCacheBox,
      donationsBox,
      donorsBox,
      medicineRestrictionsBox,
      reportsCacheBox,
      'app_settings',
      'app_flags',
      employeesBox,
      salaryHistoryBox,
      attendanceBox,
      salaryLedgerBox,
      financeSettingsBox,
      branchTransfersBox,
      auditLogsBox,
      madrassaStudentsBox,
      madrassaLogsBox,
      madrassaHolidaysBox,
      schoolStudentsBox,
      schoolLogsBox,
      schoolTeachersBox,
      schoolBooksBox,
      schoolBookLoansBox,
      schoolAuditLogsBox,
      schoolGradesBox,
      financeHolidaysBox,
      financeLoansBox,
      expensesBox,
      syncMetaBox,
      biometricDevicesBox,
      biometricCredentialsBox,
      unmappedPunchesBox,
      crossBranchPunchesBox,
      tokenExceptionsBox,
      chartOfAccountsBox,
      orgBankAccountsBox,
      journalEntriesBox,
      journalIndexBox,
      departmentMapBox,
      masterProformaBox,
      schoolFeesBox,
      schoolHomeroomBox,
      'local_user_module_access',
      'issued_token_keys',
      'server_record_versions',
      'realtime_entity_versions',
    ];


    for (final name in boxNames) {
      await openBoxSafe(name);
    }

    await LegacyDataMigrationAdapter.runOnce();

    final settings = Hive.box('app_settings');
    if (settings.get('terminal_id') == null) {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      final tid = now.substring(now.length - 2);
      await settings.put('terminal_id', tid);
    }

    debugPrint('[LocalStorageService.init] All Hive boxes opened safely.');
    
    try {
      await MasterProformaService.seedDefaultProformaIfEmpty();
      await MasterProformaService.sanitizeAllSavedStockItems();
    } catch (e) {
      debugPrint('[LocalStorageService.init] Error seeding proforma: $e');
    }

    try {
      await sanitizeLocalEntriesCasingAndUnknowns('default');
    } catch (_) {}

    try {
      await purgeDuplicateSyncQueue();
    } catch (_) {}

    try {
      if (Hive.isBoxOpen(prescriptionsBox)) {
        final pBox = Hive.box(prescriptionsBox);
        final toDelete = <dynamic>[];
        for (final k in pBox.keys) {
          final kStr = k.toString().toLowerCase();
          if (kStr.startsWith('disp_') || kStr.startsWith('legacy_') || kStr.startsWith('hist_')) {
            toDelete.add(k);
          }
        }
        for (final k in toDelete) {
          await pBox.delete(k);
        }
      }
    } catch (_) {}

    compactAllBoxes();
  }

  static Future<void> compactAllBoxes() async {
    final boxNames = [
      usersBox, patientsBox, entriesBox, syncBox, prescriptionsBox, branchCacheBox,
      stockBox, branchesBox, dispensaryBox, donationsBox, donorsBox,
      medicineRestrictionsBox, reportsCacheBox, 'app_settings', 'app_flags',
      'local_submissions', 'server_sync_queue', 'local_edit_requests',
      employeesBox, salaryHistoryBox, attendanceBox, salaryLedgerBox,
      financeSettingsBox, branchTransfersBox, auditLogsBox,
      madrassaStudentsBox, madrassaLogsBox, madrassaHolidaysBox, financeHolidaysBox,
      financeLoansBox, expensesBox,
    ];

    for (final name in boxNames) {
      try {
        if (Hive.isBoxOpen(name)) {
          await Hive.box(name).compact();
        }
      } catch (_) {}
    }
    debugPrint('[LocalStorageService] All Hive boxes compacted.');
  }

  static Future<void> clearAllInventory(String branchId, {String? dispensaryId}) async {
    try {
      if (!Hive.isBoxOpen(stockBox)) {
        await Hive.openBox(stockBox);
      }
      final box = Hive.box(stockBox);
      final activeCamp = dispensaryId?.trim().toLowerCase() ?? '';
      final keysToRemove = <dynamic>[];

      for (final k in box.keys) {
        final val = box.get(k);
        if (val is Map) {
          final itemBranch = (val['branchId'] ?? '').toString().trim().toLowerCase();
          final itemCamp = (val['dispensaryId'] ?? val['campId'] ?? '').toString().trim().toLowerCase();

          bool matchBranch = branchId.isEmpty || branchId == 'default' || itemBranch.isEmpty || itemBranch == 'default' || itemBranch == branchId.toLowerCase();
          bool matchCamp = activeCamp.isEmpty || activeCamp == 'all' || itemCamp.isEmpty || itemCamp == 'all' || itemCamp == activeCamp;

          if (matchBranch && matchCamp) {
            keysToRemove.add(k);
          }
        } else {
          keysToRemove.add(k);
        }
      }

      await box.deleteAll(keysToRemove);
      debugPrint('[LocalStorageService] 🗑️ Cleared ${keysToRemove.length} inventory items locally.');
    } catch (e) {
      debugPrint('[LocalStorageService] Error clearing inventory: $e');
    }
  }


  static Future<void> clearAllData() async {
    final boxNames = [
      usersBox, patientsBox, entriesBox, syncBox, prescriptionsBox, branchCacheBox,
      stockBox, branchesBox, dispensaryBox, donationsBox, donorsBox,
      medicineRestrictionsBox, reportsCacheBox, 'app_settings', 'app_flags',
      'local_submissions', 'server_sync_queue', 'local_edit_requests',
      'server_sync_failed',
      employeesBox, salaryHistoryBox, attendanceBox, salaryLedgerBox,
      financeSettingsBox, branchTransfersBox, auditLogsBox,
      madrassaStudentsBox, madrassaLogsBox, madrassaHolidaysBox, financeHolidaysBox,
      financeLoansBox, expensesBox,
    ];

    for (final name in boxNames) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).close();
      }
      await Hive.deleteBoxFromDisk(name);
    }
    debugPrint('[LocalStorage] All local data wiped from disk.');
  }


  // ════════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ════════════════════════════════════════════════════════════════════════════

  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static String? getLastSyncTimestamp(String collectionKey) {
    if (!Hive.isBoxOpen(syncMetaBox)) return null;
    final box = Hive.box(syncMetaBox);
    return box.get('sync_ts_$collectionKey')?.toString();
  }

  static Future<void> setLastSyncTimestamp(String collectionKey, String timestamp) async {
    if (!Hive.isBoxOpen(syncMetaBox)) return;
    final box = Hive.box(syncMetaBox);
    await box.put('sync_ts_$collectionKey', timestamp);
    await box.flush();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BRANCH DAY CACHE (local-first historic data cache)
  // ════════════════════════════════════════════════════════════════════════════

  static const String _cacheVersion = 'v1';

  static String branchCacheKey(String branchId, String dateKey, String type) =>
      '$_cacheVersion|$branchId|$dateKey|$type';

  static Future<void> putBranchDayCache(
      String branchId, String dateKey, String type, List<Map<String, dynamic>> docs) async {
    try {
      final box = Hive.box(branchCacheBox);
      final key = branchCacheKey(branchId, dateKey, type);
      final sanitizedDocs = docs.map((d) => sanitize(d)).toList();
      await box.put(key, sanitizedDocs);
      await _evictOldBranchCacheEntries(box);
    } catch (e) {
      debugPrint('[LocalStorage] putBranchDayCache error: $e');
    }
  }

  static List<Map<String, dynamic>>? getBranchDayCache(
      String branchId, String dateKey, String type) {
    try {
      if (!Hive.isBoxOpen(branchCacheBox)) return null;
      final box = Hive.box(branchCacheBox);
      final raw = box.get(branchCacheKey(branchId, dateKey, type));
      if (raw == null) return null;
      return (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('[LocalStorage] getBranchDayCache error: $e');
      return null;
    }
  }

  static Future<void> _evictOldBranchCacheEntries(Box box, {int retentionDays = 180}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
      final keysToRemove = <dynamic>[];
      for (final k in box.keys) {
        final parts = k.toString().split('|');
        if (parts.length != 4) continue;
        try {
          final date = parseDdMMyy(parts[2]);
          if (date.isBefore(cutoff)) keysToRemove.add(k);
        } catch (_) { continue; }
      }
      if (keysToRemove.isNotEmpty) {
        await box.deleteAll(keysToRemove);
        debugPrint('[LocalStorage] Evicted ${keysToRemove.length} stale branch cache entries');
      }
    } catch (e) {
      debugPrint('[LocalStorage] _evictOldBranchCacheEntries error: $e');
    }
  }


  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime)  return value;
    if (value is String) {
      try { return DateTime.parse(value); } catch (_) {}
    }
    return DateTime.now();
  }

  static int calculateAgeFromDob(dynamic dobValue) {
    if (dobValue == null) return 0;
    final DateTime birthDate = _toDateTime(dobValue);
    final DateTime today     = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age >= 0 ? age : 0;
  }

  static Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    data.forEach((key, value) {
      if (value == null) {
        result[key] = null;
      } else if (value is Timestamp || value is DateTime) {
        final dt = _toDateTime(value);
        result[key] = dt.toIso8601String();
        if (key == 'dob') result['age'] = calculateAgeFromDob(dt);
      } else if (value.runtimeType.toString().contains('FieldValue')) {
        debugPrint('[sanitize] Dropped FieldValue for key: $key');
      } else if (value is Map) {
        result[key] = sanitize(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((e) => sanitizeValue(e)).toList();
      } else {
        result[key] = value;
      }
    });
    if (data['dob'] != null) result['age'] = calculateAgeFromDob(data['dob']);
    return result;
  }

  static dynamic sanitizeValue(dynamic item) {
    if (item is Timestamp || item is DateTime) {
      return _toDateTime(item).toIso8601String();
    }
    if (item is Map) return sanitize(Map<String, dynamic>.from(item));
    return item;
  }

  static String getTodayDateKey() => DateFormat('ddMMyy').format(DateTime.now());

  static DateTime parseDdMMyy(String s) {
    if (s.length != 6) throw FormatException('Invalid date key length: $s');
    final day = int.tryParse(s.substring(0, 2));
    final month = int.tryParse(s.substring(2, 4));
    final yearPart = int.tryParse(s.substring(4, 6));
    if (day == null || month == null || yearPart == null) {
      throw FormatException('Invalid date key components: $s');
    }
    final year = 2000 + yearPart;
    return DateTime(year, month, day);
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static String _newLocalId() => const Uuid().v4();

  // ════════════════════════════════════════════════════════════════════════════
  // SYNC QUEUE
  // ════════════════════════════════════════════════════════════════════════════

  static Future<int> purgeDuplicateSyncQueue() async {
    try {
      if (!Hive.isBoxOpen(syncBox)) return 0;
      final box = Hive.box(syncBox);
      final initialCount = box.length;
      if (initialCount <= 1) return 0;

      final Map<String, dynamic> uniqueLatest = {};
      final List<dynamic> keysToDelete = [];

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw == null || raw is! Map) {
          keysToDelete.add(key);
          continue;
        }
        final item = Map<String, dynamic>.from(raw);
        final type = (item['type'] ?? '').toString();
        final entityId = (item['entityId'] ?? item['syncId'] ?? item['localId'] ?? item['id'] ?? '').toString();

        if (entityId.isEmpty) continue;
        final uniqueKey = '${type}_$entityId';

        if (uniqueLatest.containsKey(uniqueKey)) {
          final existingKey = uniqueLatest[uniqueKey]['_boxKey'];
          keysToDelete.add(existingKey);
        }
        uniqueLatest[uniqueKey] = {...item, '_boxKey': key};
      }

      for (final key in keysToDelete) {
        await box.delete(key);
      }
      final purged = initialCount - box.length;
      if (purged > 0) {
        debugPrint('[SyncQueue] 🧹 Purged $purged redundant duplicate items. Remaining: ${box.length}');
      }
      return purged;
    } catch (e) {
      debugPrint('[SyncQueue] Error purging duplicate sync queue: $e');
      return 0;
    }
  }

  static Future<void> enqueueSync(Map<String, dynamic> action) async {
    if (!Hive.isBoxOpen(syncBox)) {
      await openBoxSafe(syncBox);
    }
    final box = Hive.box(syncBox);
    final actionCopy = Map<String, dynamic>.from(action);
    final type = (actionCopy['type'] ?? 'unknown').toString();

    // FIX 1: For token/prescription actions, derive a stable entityId from
    // branchId+serial BEFORE falling back to a freshly generated syncId, so
    // retries or re-broadcasts of the same token are recognized as duplicates
    // by the existing type+entityId dedup logic below (instead of each retry
    // silently generating a brand-new syncId and being enqueued as "new").
    if (['save_entry', 'save_prescription', 'update_serial_status'].contains(type)) {
      final branchIdRaw = (actionCopy['branchId'] ?? actionCopy['data']?['branchId'])?.toString();
      final serialRaw   = (actionCopy['serial']   ?? actionCopy['data']?['serial'])?.toString();
      if (branchIdRaw != null && branchIdRaw.trim().isNotEmpty &&
          serialRaw   != null && serialRaw.trim().isNotEmpty) {
        actionCopy['entityId'] ??= '${branchIdRaw.toLowerCase().trim()}-${serialRaw.trim()}';
      }
    }

    // Ensure stable syncId and entityId (UUID v4)
    actionCopy['syncId'] ??= const Uuid().v4();
    actionCopy['entityId'] ??= actionCopy['localId'] ?? actionCopy['data']?['localId'] ?? actionCopy['data']?['id'] ?? actionCopy['id'] ?? actionCopy['syncId'];
    final entityId = actionCopy['entityId'].toString();

    String key = actionCopy['syncId'].toString();

    // Deduplicate: check if an existing item matches the same type + entityId
    if (entityId.isNotEmpty) {
      for (final existingBoxKey in box.keys) {
        final raw = box.get(existingBoxKey);
        if (raw is Map) {
          final eType = (raw['type'] ?? '').toString();
          final eEntityId = (raw['entityId'] ?? raw['localId'] ?? raw['data']?['localId'] ?? raw['data']?['id'] ?? raw['id'] ?? '').toString();
          if (eType == type && eEntityId == entityId) {
            key = existingBoxKey.toString();
            break;
          }
        }
      }
    }

    if (['update_inventory', 'add_inventory_stock', 'register_medicine', 'save_token_exception_request', 'approve_token_exception'].contains(actionCopy['type'])) {
      actionCopy['txId'] ??= const Uuid().v4();
    }
    final enriched = {
      ...actionCopy,
      'attempts':    0,
      'createdAt':   _nowIso(),
      'lastAttempt': null,
      'lastError':   null,
      'status':      'pending',
    };
    await box.put(key, sanitize(enriched));
    debugPrint('[SyncQueue] Enqueued: $type | key: $key | entityId: $entityId | total: ${box.length}');
    
    // Trigger sync upload immediately in background (Hive -> Firestore)
    SyncService().triggerUpload();
  }

  static Map<String, Map<String, dynamic>> getAllSync() {
    final box = Hive.box(syncBox);
    return Map.fromEntries(box.keys.map((k) {
      final v = box.get(k);
      if (v == null || v is! Map) return MapEntry(k.toString(), <String, dynamic>{});
      return MapEntry(k.toString(), Map<String, dynamic>.from(v));
    }));
  }

  static Future<void> removeSyncKey(String key) async {
    await Hive.box(syncBox).delete(key);
  }


  static String _branchCode(String branchId) {
    final id = branchId.toLowerCase().trim();
    if (id.contains('gujrat'))     return 'GRT';
    if (id.contains('jalalpur'))   return 'JPT';
    if (id.contains('karachi-1') || id == 'karachi1') return 'KHI1';
    if (id.contains('karachi-2') || id == 'karachi2') return 'KHI2';
    if (id.contains('rawalpindi')) return 'RWP';
    if (id.contains('sialkot'))    return 'SKT';
    if (id.contains('lahore') || id == 'lhr') return 'LHR';
    return id.length >= 3 ? id.substring(0, 3).toUpperCase() : id.toUpperCase();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DONATIONS — local read/write
  // ════════════════════════════════════════════════════════════════════════════

  static String _donationKey(String branchId, String date, String localId) =>
      '${branchId}__${date}__$localId';

  static Future<String> saveDonation({
    required String branchId,
    required Map<String, dynamic> data,
  }) async {
    final branchIdNorm = branchId.toLowerCase().trim();
    final localId = _newLocalId();
    final date    = (data['date'] as String?) ??
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    final key     = _donationKey(branchIdNorm, date, localId);

    final record = Map<String, dynamic>.from(data);
    record['localId']     = localId;
    record['hiveKey']     = key;
    record['branchId']    = branchIdNorm;
    record['syncStatus']  = 'pending';
    record['firestoreId'] = null;

    final sanitized = sanitize(record);
    await Hive.box(donationsBox).put(key, sanitized);
    await Hive.box(donationsBox).flush();
    debugPrint('[LS] Donation saved locally → $key');

    await enqueueSync({
      'type':     'save_donation',
      'branchId': branchIdNorm,
      'localId':  localId,
      'hiveKey':  key,
      'data':     sanitized,
    });

    return key;
  }

  static Future<void> markDonationSynced(
      String hiveKey, String firestoreId) async {
    final box = Hive.box(donationsBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..['firestoreId'] = firestoreId
      ..['syncStatus']  = 'synced';
    await box.put(hiveKey, updated);
    debugPrint('[LS] Donation synced → $hiveKey → fs:$firestoreId');
  }

  static List<Map<String, dynamic>> getDonations(String branchIdRaw) {
    final branchId = branchIdRaw.toLowerCase().trim();
    final prefix = '${branchId}__';
    final box    = Hive.box(donationsBox);
    return box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList()
      ..sort((a, b) {
          final at = (a['timestamp'] as String?) ?? '';
          final bt = (b['timestamp'] as String?) ?? '';
          return bt.compareTo(at);
        });
  }

  static Stream<List<Map<String, dynamic>>> streamDonations(
      String branchIdRaw) async* {
    final branchId = branchIdRaw.toLowerCase().trim();
    yield getDonations(branchId);
    await for (final _ in Hive.box(donationsBox).watch()) {
      yield getDonations(branchId);
    }
  }

  static Future<void> deleteDonation(String hiveKey, String branchId) async {
    final box = Hive.box(donationsBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;

    final fsId = (raw as Map)['firestoreId']?.toString();
    await box.delete(hiveKey);

    if (fsId != null && fsId.isNotEmpty) {
      await enqueueSync({
        'type':        'delete_donation',
        'branchId':    branchId,
        'firestoreId': fsId,
      });
    }
  }

  static Future<void> downloadDonations(String branchId) async {
    // FIX 2: normalize branchId before it's used to build the Hive key
    // (_donationKey) below — saveDonation() always lowercases, so a
    // differently-cased caller here would otherwise create a parallel,
    // never-reconciled set of Hive entries.
    branchId = branchId.toLowerCase().trim();
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final snap  = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('donations')
          .where('date', isEqualTo: today)
          .get();

      final box = Hive.box(donationsBox);
      for (final doc in snap.docs) {
        if (doc.id == 'credit_ledger') continue;
        final d       = doc.data();
        final date    = (d['date'] as String?) ?? today;
        final localId = (d['localId'] as String?) ?? doc.id;
        final key     = _donationKey(branchId, date, localId);

        final existing = box.get(key);
        if (existing == null) {
          await box.put(key, sanitize({
            ...d,
            'firestoreId': doc.id,
            'localId':     localId,
            'hiveKey':     key,
            'syncStatus':  'synced',
          }));
        } else {
          final ex = Map<String, dynamic>.from(existing as Map);
          if (ex['syncStatus'] != 'pending') {
            ex['firestoreId'] = doc.id;
            ex['syncStatus']  = 'synced';
            await box.put(key, ex);
          }
        }
      }
      debugPrint('[LS] Downloaded ${snap.docs.length} donations for $today');
    } catch (e) {
      debugPrint('[LS] downloadDonations error: $e');
    }
  }


  // ════════════════════════════════════════════════════════════════════════════
  // FULL DOWNLOAD HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> fullDownloadOnce(String branchId) async {
    await downloadAllPatients(branchId);
    await downloadInventory(branchId);
    await refreshPrescriptions(branchId);
    await downloadTodayTokens(branchId);
    await downloadDonations(branchId);
    await downloadMedicineRestrictions(branchId);
    debugPrint('[LS] fullDownloadOnce completed for branch: $branchId');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PATIENTS
  // ════════════════════════════════════════════════════════════════════════════

  static String _normalizeName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String getPatientKey(Map<String, dynamic> patient) {
    final patientId = (patient['patientId'] ?? patient['id'])?.toString().trim();
    if (patientId != null && patientId.isNotEmpty) {
      return patientId;
    }

    final isAdult      = patient['isAdult'] as bool? ?? true;
    final cnic         = (patient['cnic'] ?? patient['patientCnic'])?.toString().replaceAll('-', '').trim();
    final guardianCnic = (patient['guardianCnic'] ?? patient['guardian_cnic'])?.toString().replaceAll('-', '').trim();
    final name         = (patient['name'] ?? patient['patientName'] ?? patient['fullName'])?.toString().trim() ?? '';

    if (isAdult && cnic != null && cnic.isNotEmpty) return cnic;
    if (!isAdult &&
        guardianCnic != null &&
        guardianCnic.isNotEmpty &&
        name.isNotEmpty) {
      return '${guardianCnic}_child_${_normalizeName(name)}';
    }
    if (cnic != null && cnic.isNotEmpty) return cnic;
    if (guardianCnic != null && guardianCnic.isNotEmpty) return guardianCnic;

    final newId = const Uuid().v4();
    patient['patientId'] = newId;
    return newId;
  }

  static Future<void> seedLocalAdmins() async {
    final box = Hive.box(usersBox);

    Future<void> seedOne(String email, String password, String role,
        String branchId) async {
      final key = 'user:$email';
      if (!box.containsKey(key)) {
        await box.put(key, {
          'email':        email,
          'username':     role == 'server'
              ? 'server'
              : (role == 'chairman' ? 'chairman' : 'admin'),
          'passwordHash': hashPassword(password),
          'role':         role,
          'uid':          'local-${email.replaceAll('@', '_').replaceAll('.', '_')}',
          'branchId':     branchId,
          'branchName':   role == 'server'
              ? 'Server'
              : (role == 'chairman' ? 'Chairman' : 'HQ'),
          'createdAt':    DateTime.now().toIso8601String(),
        });
        debugPrint('Seeded user: $email');
      }
    }

    await seedOne('admin@gmd.com',   'Admin@123',   'admin',   'all');
    await seedOne('manager@gmd.com', 'Manager@123', 'manager', 'all');
    await seedOne('server@gmd.com',  'Server@123',  'server',  'sialkot');
  }

  static Future<void> forceDeduplicatePatients() async {
    final box      = Hive.box(patientsBox);
    final flagsBox = Hive.box('app_flags');
    if (flagsBox.get('patients_deduplicated_v2') == true) return;

    final Map<String, Map<String, dynamic>> uniquePatients = {};
    final Map<String, List<String>> keyToOldKeys           = {};

    for (final oldKey in box.keys.toList()) {
      final val = box.get(oldKey);
      if (val is! Map) continue;
      final patient = Map<String, dynamic>.from(val);
      try {
        final newKey = getPatientKey(patient);
        if (!uniquePatients.containsKey(newKey)) {
          uniquePatients[newKey] = patient;
        } else {
          uniquePatients[newKey]!.addAll(patient);
        }
        keyToOldKeys.putIfAbsent(newKey, () => []).add(oldKey.toString());
      } catch (_) {
        continue;
      }
    }

    final eBox = Hive.box(entriesBox);
    final Map<String, List<String>> patientToTokenKeys = {};
    for (final tokenKey in eBox.keys.toList()) {
      final tokenVal = eBox.get(tokenKey);
      if (tokenVal is Map && tokenVal['patientId'] != null) {
        final pId = tokenVal['patientId'].toString();
        patientToTokenKeys.putIfAbsent(pId, () => []).add(tokenKey.toString());
      }
    }

    for (final entry in uniquePatients.entries) {
      final newKey = entry.key;
      var patient  = sanitize(entry.value);
      patient['patientId'] = newKey;
      await box.put(newKey, patient);

      final oldKeys = keyToOldKeys[newKey]!;
      for (final oldKey in oldKeys) {
        if (oldKey == newKey) continue;
        
        final tokenKeysToUpdate = patientToTokenKeys[oldKey] ?? [];
        for (final tKey in tokenKeysToUpdate) {
          final tokenVal = eBox.get(tKey);
          if (tokenVal is Map) {
            final upd = Map<String, dynamic>.from(tokenVal);
            upd['patientId'] = newKey;
            await eBox.put(tKey, upd);
          }
        }
        
        await box.delete(oldKey);
      }
    }

    await flagsBox.put('patients_deduplicated_v2', true);
    debugPrint('[LocalStorage] Patient deduplication completed');
  }

  static Future<void> saveLocalUser(Map<String, dynamic> user) async {
    if (user['email'] == null) return;
    final sanitized = sanitize(user);
    await Hive.box(usersBox).put('user:${sanitized['email']}', sanitized);
  }

  static Map<String, dynamic>? getLocalUserByEmail(String email) {
    final val = Hive.box(usersBox).get('user:$email');
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static Map<String, dynamic>? getLocalUserByUid(String uid) {
    final box = Hive.box(usersBox);
    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map && val['uid'] == uid) return Map<String, dynamic>.from(val);
    }
    return null;
  }

  static Map<String, dynamic>? findLocalUser(String identifier) {
    if (identifier.trim().isEmpty) return null;
    final box = Hive.box(usersBox);
    final target = identifier.toLowerCase().trim();

    final direct = box.get('user:$target') ?? box.get(target);
    if (direct is Map) return Map<String, dynamic>.from(direct);

    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map) {
        final uEmail = (val['email'] ?? '').toString().toLowerCase().trim();
        final uUid = (val['uid'] ?? '').toString().toLowerCase().trim();
        final uName = (val['username'] ?? val['userName'] ?? val['name'] ?? '').toString().toLowerCase().trim();

        if (uEmail == target || uUid == target || uName == target || (uEmail.isNotEmpty && uEmail.split('@').first == target)) {
          return Map<String, dynamic>.from(val);
        }
      }
    }
    return null;
  }

  static Future<void> deleteLocalUser(String email) async {
    await Hive.box(usersBox).delete('user:$email');
  }

  static Future<void> saveUserOffline({
    required String uid,
    required String branchId,
    required Map<String, dynamic> userData,
  }) async {
    final sanitized = sanitize(userData);
    await Hive.box(usersBox).put('user:${sanitized['email']}', sanitized);
    await Hive.box(usersBox).flush();

    await enqueueSync({
      'type': 'save_user',
      'uid': uid,
      'branchId': branchId,
      'data': sanitized,
    });
  }

  static Future<void> deleteUserOffline({
    required String uid,
    required String branchId,
    required String email,
  }) async {
    await Hive.box(usersBox).delete('user:${email.toLowerCase()}');
    await Hive.box(usersBox).flush();

    await enqueueSync({
      'type': 'delete_user',
      'uid': uid,
      'branchId': branchId,
      'email': email.toLowerCase(),
    });
  }

  static Future<void> saveLocalPatient(Map<String, dynamic> patient) async {
    var sanitized      = sanitize(patient);
    final key          = getPatientKey(sanitized);
    sanitized['patientId'] = key;
    final box = Hive.box(patientsBox);
    await box.put(key, sanitized);
    await box.flush();
    await updateActiveEntriesForPatient(sanitized['branchId']?.toString() ?? '', key, sanitized);
  }

  static Future<void> updateActiveEntriesForPatient(String branchId, String patientId, Map<String, dynamic> changes) async {
    try {
      if (!Hive.isBoxOpen(entriesBox)) return;
      final box = Hive.box(entriesBox);
      final sanitizedChanges = sanitize(changes);
      final keysToUpdate = <dynamic, Map<String, dynamic>>{};

      final targetCnic = (sanitizedChanges['patientCnic'] ?? sanitizedChanges['cnic'] ?? sanitizedChanges['guardianCnic'] ?? patientId).toString().replaceAll('-', '').trim();
      final targetName = (sanitizedChanges['patientName'] ?? sanitizedChanges['name'] ?? '').toString().trim();

      for (final key in box.keys) {
        final val = box.get(key);
        if (val is Map) {
          final entry = Map<String, dynamic>.from(val);
          final ePid = (entry['patientId'] ?? entry['id'])?.toString();
          final eCnic = (entry['patientCnic'] ?? entry['cnic'] ?? entry['guardianCnic'])?.toString().replaceAll('-', '').trim();

          if (ePid == patientId || (targetCnic.isNotEmpty && eCnic == targetCnic)) {
            final updatedEntry = Map<String, dynamic>.from(entry)..addAll(sanitizedChanges);

            if (targetName.isNotEmpty) {
              updatedEntry['patientName'] = targetName;
              updatedEntry['name'] = targetName;
            }

            if (sanitizedChanges.containsKey('vitals')) {
              final newVitals = Map<String, dynamic>.from(entry['vitals'] is Map ? entry['vitals'] : {});
              if (sanitizedChanges['vitals'] is Map) {
                newVitals.addAll(Map<String, dynamic>.from(sanitizedChanges['vitals']));
              }
              updatedEntry['vitals'] = newVitals;
            }

            keysToUpdate[key] = updatedEntry;
          }
        }
      }

      for (final e in keysToUpdate.entries) {
        await box.put(e.key, e.value);
      }
      await box.flush();
    } catch (e) {
      debugPrint('[LocalStorage] Error updating active entries for patient $patientId: $e');
    }
  }

  static Future<void> saveAllLocalPatients(
      List<Map<String, dynamic>> patients) async {
    final box     = Hive.box(patientsBox);
    final updates = <String, Map<String, dynamic>>{};
    for (final patient in patients) {
      try {
        var s = sanitize(patient);
        final key  = getPatientKey(s);
        s['patientId'] = key;
        updates[key] = s;
      } catch (e) {
        debugPrint('[LocalStorage] Skipped invalid patient: $e');
      }
    }
    await box.putAll(updates);
    await box.flush();
  }

  static Map<String, dynamic>? getLocalPatientByCnic(String cnic) {
    final normalized = cnic.replaceAll('-', '').trim();
    final box        = Hive.box(patientsBox);
    final direct     = box.get(normalized);
    if (direct != null) {
      return Map<String, dynamic>.from(direct as Map);
    }
    for (final key in box.keys) {
      if (key is String && key.startsWith('${normalized}_child_')) {
        final val = box.get(key);
        if (val is Map) {
          return Map<String, dynamic>.from(val);
        }
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> getAllLocalPatients({String? branchId}) {
    var patients = Hive.box(patientsBox)
        .values
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    if (branchId != null) {
      patients = patients
          .where((p) => p['branchId'] == branchId)
          .toList();
    }
    return patients;
  }

  static List<Map<String, dynamic>> searchPatientsByCnicOrGuardian(
      String input, {String? branchId, bool globalSearch = true}) {
    final normalized      = input.replaceAll('-', '').trim().toLowerCase();
    final normalizedPhone = normalized.replaceAll(RegExp(r'\D'), '');
    final normalizedName  = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');

    final box = Hive.box(patientsBox);
    final results = <Map<String, dynamic>>[];

    for (final raw in box.values) {
      if (raw is! Map) continue;
      
      if (!globalSearch && branchId != null) {
        final branch = raw['branchId']?.toString();
        if (branch != branchId) continue;
      }

      final cnic     = raw['cnic']?.toString().replaceAll('-', '').trim().toLowerCase() ?? '';
      final guardian = raw['guardianCnic']?.toString().replaceAll('-', '').trim().toLowerCase() ?? '';
      final phone    = raw['phone']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      final name     = _normalizeName(raw['name']?.toString() ?? '');

      bool match = false;
      if (cnic.isNotEmpty && cnic.contains(normalized)) {
        match = true;
      } else if (guardian.isNotEmpty && guardian.contains(normalized)) {
        match = true;
      } else if (normalizedPhone.length >= 4 &&
          phone.isNotEmpty &&
          phone.contains(normalizedPhone)) {
        match = true;
      } else if (normalizedName.length >= 3 &&
          name.isNotEmpty &&
          name.contains(normalizedName)) {
        match = true;
      }

      if (match) {
        final p = Map<String, dynamic>.from(raw);
        if (p['patientId'] == null) {
          p['patientId'] = getPatientKey(p);
        }
        results.add(p);
      }
    }
    return results;
  }

  static Future<void> deleteLocalPatient(String patientId) async {
    await Hive.box(patientsBox).delete(patientId);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ENTRIES / TOKENS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveEntryLocal(
      String branchId, String serial, Map<String, dynamic> entryData) async {
    final normBranch = branchId.toLowerCase().trim();
    final normSerial = serial.trim();
    final key        = '$normBranch-$normSerial';
    var sanitized    = sanitize(entryData);
    final todayKey   = getTodayDateKey();
    sanitized['dateKey']  = sanitized['dateKey'] ?? todayKey;
    sanitized['branchId'] = normBranch;
    sanitized['serial']   = normSerial;

    final normSerialUpper = normSerial.toUpperCase();
    if (normSerialUpper.contains('-SADD-') || normSerialUpper.contains('-KAP-') || normSerialUpper.contains('-KAPAYYA-')) {
      sanitized['dispensaryId'] = 'saddar';
      sanitized['campId']       = 'saddar';
      sanitized['dispensaryTag'] = sanitized['dispensaryTag'] ?? 'SADD';
    } else if (normSerialUpper.contains('-HAJI-') || normSerialUpper.contains('-HAJ-') || normSerialUpper.contains('-HC-')) {
      sanitized['dispensaryId'] = 'haji_camp';
      sanitized['campId']       = 'haji_camp';
      sanitized['dispensaryTag'] = sanitized['dispensaryTag'] ?? 'HAJI';
    } else {
      final activeCamp = CampSessionService.getActiveCamp();
      if (activeCamp != null && activeCamp.isNotEmpty && activeCamp != 'all') {
        sanitized['dispensaryId'] = sanitized['dispensaryId'] ?? activeCamp;
        sanitized['campId']       = sanitized['campId']       ?? activeCamp;
      }
    }

    final rawTime = sanitized['timestamp'] ?? sanitized['createdAt'] ?? sanitized['date'];
    final dt = rawTime != null ? _toDateTime(rawTime) : DateTime.now();
    sanitized['session'] = sanitized['session'] ?? CampSessionService.getCurrentSession(dt);

    const terminalStatuses = ['completed', 'dispensed'];

    void preservePatientFields(Map existing) {
      for (final field in [
        'patientName', 'name', 'fullName', 'patientCnic', 'cnic', 'guardianName',
        'guardianCnic', 'patientAge', 'age', 'patientGender', 'gender',
        'queueType', 'session', 'visitReason', 'isVitalsOnly', 'vitalsOnly',
        'suggestedDays', 'doctorName', 'doctorId', 'performedBy', 'createdByName', 'createdBy'
      ]) {
        final curVal = sanitized[field];
        final oldVal = existing[field];
        final isCurEmpty = curVal == null || curVal.toString().trim().isEmpty || curVal.toString().trim().toLowerCase() == 'unknown' || curVal.toString().trim().toLowerCase() == 'unknown patient';
        final isOldValid = oldVal != null && oldVal.toString().trim().isNotEmpty && oldVal.toString().trim().toLowerCase() != 'unknown' && oldVal.toString().trim().toLowerCase() != 'unknown patient';
        if (isCurEmpty && isOldValid) {
          sanitized[field] = oldVal;
        }
      }
    }

    // 1. Clean up duplicate case keys and preserve terminal status & patient info
    try {
      if (Hive.isBoxOpen(entriesBox)) {
        final box = Hive.box(entriesBox);
        final targetUpper = normSerial.toUpperCase();
        for (final k in box.keys.toList()) {
          final kStr = k.toString();
          if (kStr.toLowerCase().startsWith('$normBranch-') &&
              kStr.substring(normBranch.length + 1).toUpperCase() == targetUpper &&
              kStr != key) {
            final existing = box.get(k);
            if (existing is Map) {
              preservePatientFields(existing);
              final localStatus    = (existing['status'] ?? '').toString().toLowerCase();
              final incomingStatus = (sanitized['status'] ?? '').toString().toLowerCase();
              if (terminalStatuses.contains(localStatus) && !terminalStatuses.contains(incomingStatus)) {
                sanitized['status']         = existing['status'] ?? 'completed';
                sanitized['completedAt']    = existing['completedAt'] ?? sanitized['completedAt'];
                sanitized['prescription']   = existing['prescription'] ?? sanitized['prescription'];
                sanitized['prescriptionId'] = existing['prescriptionId'] ?? sanitized['prescriptionId'];
                sanitized['dispenseStatus'] = existing['dispenseStatus'] ?? sanitized['dispenseStatus'];
                sanitized['vitals']         = existing['vitals'] ?? sanitized['vitals'];
                sanitized['daysOfMedicine'] = existing['daysOfMedicine'] ?? sanitized['daysOfMedicine'];
                sanitized['doctorName']     = existing['doctorName'] ?? sanitized['doctorName'];
                sanitized['doctorId']       = existing['doctorId'] ?? sanitized['doctorId'];
              }
            }
            await box.delete(k);
          }
        }
      }
    } catch (_) {}

    // 2. Check exact key in entriesBox and preserve terminal status & patient info
    try {
      if (Hive.isBoxOpen(entriesBox)) {
        final box = Hive.box(entriesBox);
        final existingExact = box.get(key);
        if (existingExact is Map) {
          preservePatientFields(existingExact);
          final localStatus    = (existingExact['status'] ?? '').toString().toLowerCase();
          final incomingStatus = (sanitized['status'] ?? '').toString().toLowerCase();
          if (terminalStatuses.contains(localStatus) && !terminalStatuses.contains(incomingStatus)) {
            sanitized['status']         = existingExact['status'] ?? 'completed';
            sanitized['completedAt']    = existingExact['completedAt'] ?? sanitized['completedAt'];
            sanitized['prescription']   = existingExact['prescription'] ?? sanitized['prescription'];
            sanitized['prescriptionId'] = existingExact['prescriptionId'] ?? sanitized['prescriptionId'];
            sanitized['dispenseStatus'] = existingExact['dispenseStatus'] ?? sanitized['dispenseStatus'];
            sanitized['vitals']         = existingExact['vitals'] ?? sanitized['vitals'];
            sanitized['daysOfMedicine'] = existingExact['daysOfMedicine'] ?? sanitized['daysOfMedicine'];
            sanitized['doctorName']     = existingExact['doctorName'] ?? sanitized['doctorName'];
            sanitized['doctorId']       = existingExact['doctorId'] ?? sanitized['doctorId'];
          }
        }
      }
    } catch (_) {}

    // 3. Check if a local prescription already exists in prescriptionsBox for this exact token in this branch
    try {
      final incomingStatus = (sanitized['status'] ?? '').toString().toLowerCase();
      if (incomingStatus != 'waiting' || sanitized['prescription'] != null) {
        final existingPrescription = getLocalPrescription(
          normSerial,
          branchId: branchId,
          cnic: sanitized['patientCnic'] ?? sanitized['cnic'],
          patientId: sanitized['patientId'] ?? sanitized['id'],
          patientName: sanitized['patientName'] ?? sanitized['name'],
          dateKey: sanitized['dateKey']?.toString(),
        );
        if (existingPrescription != null) {
          final pSerial = (existingPrescription['serial'] ?? existingPrescription['id'] ?? '').toString().toLowerCase().trim();
          if (pSerial == normSerial) {
            preservePatientFields(existingPrescription);
            sanitized['status']         = 'completed';
            sanitized['prescription']   = existingPrescription;
            sanitized['prescriptionId'] = existingPrescription['id'] ?? normSerial;
            if (existingPrescription['completedAt'] != null && sanitized['completedAt'] == null) {
              sanitized['completedAt'] = existingPrescription['completedAt'];
            }
            if (existingPrescription['doctorName'] != null && sanitized['doctorName'] == null) {
              sanitized['doctorName'] = existingPrescription['doctorName'];
            }
            if (existingPrescription['doctorId'] != null && sanitized['doctorId'] == null) {
              sanitized['doctorId'] = existingPrescription['doctorId'];
            }
            if (existingPrescription['daysOfMedicine'] != null && sanitized['daysOfMedicine'] == null) {
              sanitized['daysOfMedicine'] = existingPrescription['daysOfMedicine'];
            }
          }
        }
      }
    } catch (_) {}

    await Hive.box(entriesBox).put(key, sanitized);
  }

  static List<Map<String, dynamic>> getLocalEntries(String branchId,
      {String? dispensaryId, bool filterByCamp = false, String? session, bool filterBySession = false}) {
    final box = Hive.box(entriesBox);
    final normBranch = branchId.toLowerCase().trim();
    var list = box.keys
        .where((k) => k.toString().toLowerCase().startsWith('$normBranch-'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();

    if (filterByCamp) {
      final activeCamp = (dispensaryId != null && dispensaryId.trim().isNotEmpty)
          ? dispensaryId.trim().toLowerCase()
          : CampSessionService.getActiveCamp(branchId);

      if (activeCamp != null && activeCamp.isNotEmpty && activeCamp != 'all') {
        list = list.where((entry) {
          return CampSessionService.matchesCamp(
            selectedCamp: activeCamp,
            dispensaryId: entry['dispensaryId']?.toString(),
            campId: entry['campId']?.toString(),
            dispensaryTag: entry['dispensaryTag']?.toString(),
            serial: (entry['serial'] ?? entry['id'])?.toString(),
          );
        }).toList();
      }
    }

    if (filterBySession) {
      final targetSession = (session != null && session.trim().isNotEmpty)
          ? session.trim().toLowerCase()
          : CampSessionService.getCurrentSession();

      if (targetSession != 'all') {
        list = list.where((entry) {
          final s = entry['session']?.toString().toLowerCase().trim();
          if (s != null && s.isNotEmpty) {
            return s == targetSession;
          }
          final rawTime = entry['timestamp'] ?? entry['createdAt'] ?? entry['date'];
          if (rawTime != null) {
            final dt = _toDateTime(rawTime);
            return CampSessionService.getCurrentSession(dt) == targetSession;
          }
          return true;
        }).toList();
      }
    }

    return list;
  }

  static Map<String, dynamic>? getLocalEntry(
      String branchId, String serial) {
    final normBranch = branchId.toLowerCase().trim();
    final normSerial = serial.trim();
    final val = Hive.box(entriesBox).get('$normBranch-$normSerial');
    if (val != null) return Map<String, dynamic>.from(val as Map);

    final box = Hive.box(entriesBox);
    final targetUpper = normSerial.toUpperCase();
    for (final k in box.keys) {
      final kStr = k.toString();
      if (kStr.toLowerCase().startsWith('$normBranch-') &&
          kStr.substring(normBranch.length + 1).toUpperCase() == targetUpper) {
        final item = box.get(k);
        if (item is Map) return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  static Future<void> updateLocalEntryField(
      String branchId, String serial, Map<String, dynamic> fields) async {
    final normBranch = branchId.toLowerCase().trim();
    final normSerial = serial.trim();
    final key = '$normBranch-$normSerial';
    final box = Hive.box(entriesBox);
    var raw = box.get(key);
    if (raw == null) {
      final targetUpper = normSerial.toUpperCase();
      for (final k in box.keys) {
        final kStr = k.toString();
        if (kStr.toLowerCase().startsWith('$normBranch-') &&
            kStr.substring(normBranch.length + 1).toUpperCase() == targetUpper) {
          raw = box.get(k);
          break;
        }
      }
    }
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..addAll(sanitize(fields));
    await box.put(key, updated);
  }

  static Future<bool> deleteLocalEntry(String branchId, String tokenSerial) async {
    try {
      final box = Hive.box(entriesBox);
      if (!box.isOpen) return false;
      final normBranch = branchId.toLowerCase().trim();
      final targetUpper = tokenSerial.trim().toUpperCase();
      final keys = box.keys.toList();
      bool deleted = false;
      for (final key in keys) {
        final kStr = key.toString();
        final entry = box.get(key);
        if (entry == null) continue;
        final serial = (entry['serial'] ?? '').toString().trim().toUpperCase();
        final entryBranch = (entry['branchId'] ?? '').toString().trim().toLowerCase();
        if ((serial == targetUpper || kStr.substring(kStr.indexOf('-') + 1).toUpperCase() == targetUpper) &&
            (entryBranch.isEmpty || entryBranch == normBranch)) {
          await box.delete(key);
          debugPrint('[LocalStorage] ✅ Deleted $tokenSerial (key: $key)');
          deleted = true;
        }
      }
      await box.flush();
      return deleted;
    } catch (e) {
      debugPrint('[LocalStorage] ❌ deleteLocalEntry error: $e');
      return false;
    }
  }

  static Future<void> remapTempSerialToCanonical(
    String branchId,
    String oldTempSerial,
    String canonicalSerial,
    Map<String, dynamic> canonicalData,
  ) async {
    final box = Hive.box(entriesBox);
    final normBranch = branchId.toLowerCase().trim();
    final oldTempUpper = oldTempSerial.trim().toUpperCase();

    for (final k in box.keys.toList()) {
      final kStr = k.toString();
      if (kStr.toLowerCase().startsWith('$normBranch-') &&
          kStr.toUpperCase().contains(oldTempUpper)) {
        await box.delete(k);
      }
    }

    final newKey = '$normBranch-${canonicalSerial.trim()}';
    final merged = Map<String, dynamic>.from(canonicalData);
    merged['serial'] = canonicalSerial;
    merged['originalTempSerial'] = oldTempSerial;
    merged['renumberedOnSync'] = true;
    merged.remove('pendingSync');

    await box.put(newKey, sanitize(merged));
    await box.flush();
    debugPrint('[LocalStorage] Remapped temp serial $oldTempSerial → canonical $canonicalSerial');
  }

  static Future<void> sanitizeLocalEntriesCasingAndUnknowns(String branchId) async {
    try {
      if (!Hive.isBoxOpen(entriesBox)) return;
      final box = Hive.box(entriesBox);
      final normBranch = branchId.toLowerCase().trim();
      final keys = box.keys.where((k) => k.toString().toLowerCase().startsWith('$normBranch-')).toList();

      final Map<String, List<dynamic>> serialToKeys = {};
      for (final key in keys) {
        final val = box.get(key);
        if (val is! Map) continue;
        final serial = (val['serial'] ?? key.toString().replaceFirst(RegExp('^$normBranch-', caseSensitive: false), '')).toString().trim().toUpperCase();
        if (serial.isEmpty) continue;
        serialToKeys.putIfAbsent(serial, () => []).add(key);
      }

      for (final entry in serialToKeys.entries) {
        final keyList = entry.value;
        if (keyList.length > 1) {
          dynamic bestKey = keyList.first;
          Map<String, dynamic>? bestData;

          for (final k in keyList) {
            final data = Map<String, dynamic>.from(box.get(k) as Map);
            final name = (data['patientName'] ?? data['name'] ?? '').toString().trim().toLowerCase();
            final isUnknown = name.isEmpty || name == 'unknown patient' || name == 'unknown';

            if (bestData == null) {
              bestData = data;
              bestKey = k;
            } else {
              final bestName = (bestData['patientName'] ?? bestData['name'] ?? '').toString().trim().toLowerCase();
              final bestIsUnknown = bestName.isEmpty || bestName == 'unknown patient' || bestName == 'unknown';

              if (bestIsUnknown && !isUnknown) {
                bestData = data;
                bestKey = k;
              }
            }
          }

          for (final k in keyList) {
            if (k != bestKey) {
              await box.delete(k);
              debugPrint('[LocalStorage] Cleaned up duplicate casing/unknown key: $k');
            }
          }
        }
      }
      await box.flush();
    } catch (e) {
      debugPrint('[LocalStorage] Error in sanitizeLocalEntriesCasingAndUnknowns: $e');
    }
  }

  static List<Map<String, dynamic>> getUnservedPreviousDaysTokens(
    String branchId, {
    int daysBack = 3,
    String? dispensaryId,
  }) {
    // FIX 2: normalize branchId before it's used to build the Hive key
    // prefix below — this method previously used the raw, possibly
    // differently-cased parameter, which could miss real local entries.
    branchId = branchId.toLowerCase().trim();
    final box = Hive.box(entriesBox);
    final shiftInfo = CampSessionService.resolveShiftAndDateKey();
    final today = shiftInfo.dateKey;

    final now = DateTime.now();
    final validDates = <String>{};
    for (int i = 1; i <= daysBack; i++) {
      validDates.add(DateFormat('ddMMyy').format(now.subtract(Duration(days: i))));
    }

    final list = box.keys
        .where((k) => k.toString().startsWith('$branchId-'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .where((e) {
          final dk = e['dateKey']?.toString() ?? '';
          if (dk == today || !validDates.contains(dk)) return false;
          final status = (e['status'] ?? '').toString().toLowerCase();
          final isUnserved = status != 'completed' && status != 'served' && status != 'dispensed' && status != 'cancelled' && status != 'expired';
          if (!isUnserved) return false;

          if (dispensaryId != null && dispensaryId.isNotEmpty && dispensaryId != 'all') {
            final rawD = (e['dispensaryId'] ?? e['campId'])?.toString().toLowerCase().trim();
            if (rawD == null || rawD.isEmpty || rawD == 'all') return true;
            final normD = rawD.replaceAll(RegExp(r'[^a-z0-9]'), '');
            final normCamp = dispensaryId.replaceAll(RegExp(r'[^a-z0-9]'), '');
            return normD == normCamp || normD.contains(normCamp) || normCamp.contains(normD);
          }
          return true;
        })
        .toList();

    return list;
  }

  static Future<int> expireUnservedTokensForDate(String branchId, String dateKey) async {
    // FIX 2: normalize branchId before it's used to build the Hive key
    // prefix below.
    branchId = branchId.toLowerCase().trim();
    final box = Hive.box(entriesBox);
    int count = 0;
    for (final key in box.keys.toList()) {
      if (!key.toString().startsWith('$branchId-')) continue;
      final val = box.get(key);
      if (val is Map) {
        final entry = Map<String, dynamic>.from(val);
        final dk = entry['dateKey']?.toString();
        if (dk == dateKey) {
          final status = (entry['status'] ?? '').toString().toLowerCase();
          if (status != 'served' && status != 'dispensed' && status != 'cancelled' && status != 'expired') {
            entry['status'] = 'expired';
            entry['expiredAt'] = DateTime.now().toIso8601String();
            await box.put(key, sanitize(entry));
            count++;
          }
        }
      }
    }
    await box.flush();
    return count;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRESCRIPTIONS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveLocalPrescription(
      Map<String, dynamic> prescription) async {
    final serialRaw =
        prescription['serial']?.toString() ?? prescription['id']?.toString();
    final serial = serialRaw?.trim();
    if (serial == null || serial.isEmpty) return;

    const cnicFields = [
      'patientCnic', 'cnic', 'patientCNIC', 'guardianCnic',
      'patient_cnic', 'guardian_cnic', 'cnic_number'
    ];
    String? cnicRaw;
    for (final field in cnicFields) {
      final v = prescription[field]?.toString();
      if (v != null && v.trim().isNotEmpty && v != '00000-0000000-0') {
        cnicRaw = v;
        break;
      }
    }
    cnicRaw ??= 'unknown_cnic_${DateTime.now().millisecondsSinceEpoch}';

    final cleanCnic  = cnicRaw.trim().replaceAll('-', '').replaceAll(' ', '');
    final normSerial = serial.toLowerCase().trim();

    final key       = '${cleanCnic}_$serial';
    var sanitized   = sanitize(prescription);
    sanitized['patientCnic'] = cleanCnic;
    sanitized['cnic']        = cleanCnic;
    sanitized['serial']      = serial;

    final activeCamp = CampSessionService.getActiveCamp();
    if (activeCamp != null && activeCamp.isNotEmpty) {
      sanitized['dispensaryId'] = sanitized['dispensaryId'] ?? activeCamp;
      sanitized['campId']       = sanitized['campId']       ?? activeCamp;
      sanitized['campName']     = sanitized['campName']     ?? CampSessionService.getCampLabel(activeCamp);
    }

    final box = Hive.box(prescriptionsBox);
    await box.put(key, sanitized);
    await box.put(serial, sanitized);
    await box.put('${cleanCnic}_$normSerial', sanitized);
    await box.put(normSerial, sanitized);

    final entriesBoxRef = Hive.box(entriesBox);
    for (final entryKey in entriesBoxRef.keys) {
      if (entryKey is String) {
        final entry = entriesBoxRef.get(entryKey);
        if (entry is Map) {
          final eSerial = (entry['serial'] ?? entry['id'] ?? entry['tokenSerial'] ?? '')
              .toString().trim().toLowerCase();

          final isMatch = eSerial == normSerial ||
              entryKey.toLowerCase() == normSerial ||
              entryKey.toLowerCase().endsWith('-$normSerial');

          if (isMatch) {
            final updatedEntry = Map<String, dynamic>.from(entry);
            updatedEntry['prescription'] = sanitized;
            updatedEntry['status']       = 'completed';
            await entriesBoxRef.put(entryKey, updatedEntry);
          }
        }
      }
    }
  }

  static Future<void> updateDispenseStatus(
      String branchId, String serial, String status) async {
    // FIX 2: normalize branchId before it's used to build the Hive key below.
    branchId = branchId.toLowerCase().trim();
    final key = '$branchId-$serial';
    final box = Hive.box(entriesBox);
    final entry = box.get(key);
    if (entry is Map) {
      final updated = Map<String, dynamic>.from(entry);
      updated['dispenseStatus'] = status;
      await box.put(key, updated);
      await box.flush();
    }
  }

  static Map<String, dynamic>? getLocalPrescription(
    String serial, {
    String? cnic,
    String? patientName,
    String? patientId,
    String? branchId,
    String? dateKey,
  }) {
    if (serial.trim().isEmpty) return null;
    final cleanSerial = serial.trim();
    final lowerSerial = cleanSerial.toLowerCase();
    final normBranch  = (branchId ?? '').trim().toLowerCase();
    final cleanCnic   = (cnic ?? '').trim().replaceAll(RegExp(r'[-\s]'), '');
    final cleanPId    = (patientId ?? '').trim();

    // Helper: validate candidate prescription against branch and patient identity
    bool matchesPatient(Map data) {
      // 1. Branch verification
      if (normBranch.isNotEmpty && normBranch != 'all' && normBranch != 'global') {
        final pBranch = (data['branchId'] ?? '').toString().trim().toLowerCase();
        if (pBranch.isNotEmpty && pBranch != normBranch && !pBranch.contains(normBranch) && !normBranch.contains(pBranch)) {
          return false;
        }
      }

      // 2. DateKey verification
      if (dateKey != null && dateKey.trim().isNotEmpty) {
        final pDateKey = (data['dateKey'] ?? '').toString().trim();
        if (pDateKey.isNotEmpty && pDateKey != dateKey.trim()) {
          return false;
        }
      }

      // 3. Patient ID verification
      if (cleanPId.isNotEmpty) {
        final pId = (data['patientId'] ?? data['id'] ?? '').toString().trim();
        if (pId.isNotEmpty && pId != cleanPId) {
          return false;
        }
      }

      // 4. CNIC verification
      if (cleanCnic.isNotEmpty) {
        final pCnic = (data['patientCnic'] ?? data['cnic'] ?? '')
            .toString()
            .trim()
            .replaceAll(RegExp(r'[-\s]'), '');
        if (pCnic.isNotEmpty &&
            pCnic != cleanCnic &&
            !pCnic.contains(cleanCnic) &&
            !cleanCnic.contains(pCnic)) {
          return false;
        }
      }

      // 5. Patient Name verification (ignore vague names like '0', '02', 'unknown')
      if (patientName != null && patientName.trim().isNotEmpty) {
        final pName = (data['patientName'] ?? data['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final qName = patientName.trim().toLowerCase();
        if (pName.isNotEmpty &&
            qName.isNotEmpty &&
            pName != 'unknown' &&
            qName != 'unknown' &&
            pName.length > 2 &&
            qName.length > 2) {
          if (pName != qName && !pName.contains(qName) && !qName.contains(pName)) {
            return false;
          }
        }
      }
      return true;
    }

    // 1. Check entriesBox strictly for this branch
    try {
      if (Hive.isBoxOpen(entriesBox)) {
        final eBox = Hive.box(entriesBox);
        if (normBranch.isNotEmpty) {
          final exactEntry = eBox.get('$normBranch-$cleanSerial') ??
              eBox.get('$normBranch-$lowerSerial') ??
              eBox.get('$normBranch-${cleanSerial.toUpperCase()}');
          if (exactEntry is Map && exactEntry['prescription'] is Map) {
            final presc = exactEntry['prescription'] as Map;
            if (presc.isNotEmpty && matchesPatient(presc)) {
              return Map<String, dynamic>.from(presc);
            }
          }
        }
      }
    } catch (_) {}

    // 2. Direct key lookups in prescriptionsBox with strict branch/patient validation
    final box = Hive.box(prescriptionsBox);
    final keyCandidates = [
      if (normBranch.isNotEmpty) '$normBranch-$cleanSerial',
      if (normBranch.isNotEmpty) '$normBranch-${cleanSerial.toUpperCase()}',
      cleanSerial,
      cleanSerial.toUpperCase(),
      lowerSerial,
    ];

    for (final k in keyCandidates) {
      final direct = box.get(k);
      if (direct != null && direct is Map && matchesPatient(direct)) {
        return Map<String, dynamic>.from(direct);
      }
    }

    return null;
  }

  static Future<void> deleteLocalPrescription(String serial) async {
    if (serial.trim().isEmpty) return;
    try {
      if (Hive.isBoxOpen(prescriptionsBox)) {
        final box = Hive.box(prescriptionsBox);
        final lowerSerial = serial.trim().toLowerCase();
        final upperSerial = serial.trim().toUpperCase();
        await box.delete(serial);
        await box.delete(lowerSerial);
        await box.delete(upperSerial);
        final keysToDelete = <dynamic>[];
        for (final k in box.keys) {
          final kStr = k.toString().toLowerCase();
          if (kStr == lowerSerial || kStr.endsWith('_$lowerSerial') || kStr.endsWith('-$lowerSerial')) {
            keysToDelete.add(k);
          }
        }
        for (final k in keysToDelete) {
          await box.delete(k);
        }
      }
    } catch (_) {}
  }

  static Map<String, dynamic>? getLocalPrescriptionByCnic(String cnic) {
    final box = Hive.box(prescriptionsBox);
    if (!box.isOpen) return null;
    var cleanCnic = cnic.trim().replaceAll('-', '').replaceAll(' ', '');
    cleanCnic = cleanCnic.replaceAll(RegExp(r'^0+'), '');
    for (final value in box.values) {
      final presc = Map<String, dynamic>.from(value as Map);
      final raw   = presc['patientCnic']?.toString() ??
          presc['cnic']?.toString() ?? '';
      var pc = raw.trim().replaceAll('-', '').replaceAll(' ', '');
      pc = pc.replaceAll(RegExp(r'^0+'), '');
      if (pc == cleanCnic || pc.contains(cleanCnic) || cleanCnic.contains(pc)) {
        return presc;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> getAllLocalPrescriptions() =>
      Hive.box(prescriptionsBox)
          .values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();

  static List<Map<String, dynamic>> getBranchPrescriptions(String branchId) =>
      getAllLocalPrescriptions()
          .where((p) => p['branchId'] == branchId)
          .toList();

  // ════════════════════════════════════════════════════════════════════════════
  // STOCK
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveAllLocalStockItems(
      List<Map<String, dynamic>> items) async {
    final box = Hive.box(stockBox);
    final sBox = Hive.box(syncBox);

    final pendingDeltas = <String, double>{};
    for (final key in sBox.keys) {
      final val = sBox.get(key);
      if (val is Map) {
        final type = val['type'];
        if (type == 'update_inventory') {
          final medId = val['inventoryId']?.toString();
          final delta = (val['delta'] as num?)?.toDouble() ?? 0.0;
          if (medId != null && delta != 0) {
            pendingDeltas[medId] = (pendingDeltas[medId] ?? 0.0) + delta;
          }
        } else if (type == 'add_inventory_stock') {
          final medId = val['medicineId']?.toString();
          final qty = (val['quantity'] as num?)?.toDouble() ?? 0.0;
          if (medId != null && qty > 0) {
            pendingDeltas[medId] = (pendingDeltas[medId] ?? 0.0) + qty;
          }
        }
      }
    }

    final pendingRegistrations = sBox.values
        .whereType<Map>()
        .where((v) => v['type'] == 'register_medicine')
        .map((v) {
          final dataMap = v['data'] is Map ? Map<String, dynamic>.from(v['data'] as Map) : <String, dynamic>{};
          return (dataMap['id'] ?? dataMap['medicineId'])?.toString();
        })
        .whereType<String>()
        .toSet();

    final Map<String, dynamic> updatedMap = {};
    final downloadedIds = <String>{};
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      downloadedIds.add(id);
      final key = 'stock:$id';
      
      if (pendingDeltas.containsKey(id)) {
        final downloadedQty = (item['quantity'] ?? 0) as num;
        item['quantity'] = (downloadedQty.toDouble() + pendingDeltas[id]!).clamp(0.0, double.infinity);
        debugPrint('[LocalStorage] Re-applied pending local delta of ${pendingDeltas[id]} to downloaded stock of $id');
      } else {
        final rawQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        item['quantity'] = rawQty.clamp(0.0, double.infinity);
      }
      updatedMap[key] = item;
    }

    final currentLocalItems = <String, dynamic>{};
    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map) {
        final itemMap = Map<String, dynamic>.from(val);
        final id = (itemMap['id'] ?? itemMap['medicineId'])?.toString() ?? '';
        if (id.isNotEmpty) {
          currentLocalItems[id] = itemMap;
        }
      }
    }

    for (final regId in pendingRegistrations) {
      if (!downloadedIds.contains(regId) && currentLocalItems.containsKey(regId)) {
        final key = 'stock:$regId';
        updatedMap[key] = currentLocalItems[regId];
        debugPrint('[LocalStorage] Preserved locally-registered-but-unsynced medicine $regId in stock list');
      }
    }

    await box.clear();
    await box.putAll(updatedMap);
  }

  static Future<void> saveLocalStockItem(
      Map<String, dynamic> stockItem) async {
    final id = stockItem['id']?.toString();
    if (id == null) return;
    final item = Map<String, dynamic>.from(stockItem);
    if (item['name'] != null) item['name'] = MasterProformaService.cleanBrandToFormula(item['name'].toString());
    if (item['formula'] != null) item['formula'] = MasterProformaService.cleanBrandToFormula(item['formula'].toString());
    final rawQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    item['quantity'] = rawQty.clamp(0.0, double.infinity);
    final activeCamp = CampSessionService.getActiveCamp();
    if (activeCamp != null && activeCamp.isNotEmpty) {
      item['dispensaryId'] = item['dispensaryId'] ?? activeCamp;
      item['campId']       = item['campId']       ?? activeCamp;
    }
    await Hive.box(stockBox).put('stock:$id', sanitize(item));
  }

  static void saveLocalInventoryItem(Map<String, dynamic> item) {
    final rawId = (item['id'] ?? item['medicineId'])?.toString().trim();
    if (rawId == null || rawId.isEmpty) return;
    final normalised = Map<String, dynamic>.from(item);
    normalised['id']         = rawId;
    normalised['medicineId'] = rawId;
    if (normalised['name'] != null) normalised['name'] = MasterProformaService.cleanBrandToFormula(normalised['name'].toString());
    if (normalised['formula'] != null) normalised['formula'] = MasterProformaService.cleanBrandToFormula(normalised['formula'].toString());
    final rawQty = (normalised['quantity'] as num?)?.toDouble() ?? 0.0;
    normalised['quantity']   = rawQty.clamp(0.0, double.infinity);
    final activeCamp = CampSessionService.getActiveCamp();
    if (activeCamp != null && activeCamp.isNotEmpty) {
      normalised['dispensaryId'] = activeCamp;
      normalised['campId']       = activeCamp;
    }
    Hive.box(stockBox).put('stock:$rawId', sanitize(normalised));
  }

  static Map<String, dynamic>? getLocalInventoryItem(String id) {
    final val = Hive.box(stockBox).get('stock:$id');
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static Future<void> updateLocalStockQuantity(String id, double delta) async {
    final box = Hive.box(stockBox);
    final key = 'stock:$id';
    final raw = box.get(key);
    if (raw == null) return;
    final item = Map<String, dynamic>.from(raw as Map);

    final activeCamp = CampSessionService.getActiveCamp();
    if (activeCamp != null && activeCamp.isNotEmpty) {
      final itemCamp = (item['campId'] ?? item['dispensaryId'] ?? '').toString();
      if (itemCamp.isNotEmpty && itemCamp != activeCamp) {
        return;
      }
      item['dispensaryId'] = activeCamp;
      item['campId']       = activeCamp;
    }

    final currentQty = (item['quantity'] ?? 0) as num;
    item['quantity'] = (currentQty.toDouble() + delta).clamp(0.0, double.infinity);
    item['updatedAt'] = DateTime.now().toIso8601String();
    await box.put(key, sanitize(item));
  }

  static Future<void> deleteLocalStockItem(String id) async =>
      Hive.box(stockBox).delete('stock:$id');

  static Future<int> clearLocalBranchStock(String branchId) async {
    final box = Hive.box(stockBox);
    final targetBranch = branchId.toLowerCase().trim();
    final keysToDelete = <dynamic>[];

    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map) {
        final bId = (val['branchId'] ?? '').toString().toLowerCase().trim();
        if (bId == targetBranch ||
            bId.contains('karachi') ||
            bId.contains('khi') ||
            targetBranch.contains('karachi') ||
            targetBranch.isEmpty ||
            bId.isEmpty) {
          keysToDelete.add(key);
        }
      } else {
        keysToDelete.add(key);
      }
    }

    for (final k in keysToDelete) {
      await box.delete(k);
    }
    return keysToDelete.length;
  }

  static List<Map<String, dynamic>> getAllLocalStockItems(
      {String? branchId, String? dispensaryId, bool filterByCamp = true}) {
    if (!Hive.isBoxOpen(stockBox)) return [];
    var items = Hive.box(stockBox)
        .values
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    if (branchId != null && branchId.isNotEmpty) {
      final norm = branchId.toLowerCase().trim();
      items = items.where((i) {
        final b = i['branchId']?.toString().toLowerCase().trim();
        if (b == null || b.isEmpty) return true; // Branch stock fallback
        return b == norm ||
            b == 'branch_$norm' ||
            'branch_$b' == norm ||
            (norm.isNotEmpty && b.contains(norm)) ||
            (b.isNotEmpty && norm.contains(b));
      }).toList();
    }
    if (filterByCamp && CampSessionService.hasCampsForBranch(branchId)) {
      final activeCamp = (dispensaryId != null && dispensaryId.isNotEmpty && dispensaryId.toLowerCase() != 'all')
          ? dispensaryId.toLowerCase().trim()
          : CampSessionService.getActiveCamp(branchId);

      if (activeCamp != null && activeCamp.isNotEmpty && activeCamp != 'all') {
        final campFiltered = items.where((i) {
          return CampSessionService.matchesCamp(
            selectedCamp: activeCamp,
            dispensaryId: i['dispensaryId']?.toString(),
            campId: i['campId']?.toString(),
            dispensaryTag: i['dispensaryTag']?.toString(),
            serial: (i['barcode'] ?? i['code'] ?? i['id'])?.toString(),
          );
        }).toList();
        if (campFiltered.isNotEmpty) {
          items = campFiltered;
        }
      }
    }
    return items.map((i) {
      final name = i['name']?.toString() ?? '';
      final formula = i['formula']?.toString() ?? '';
      final cleanN = MasterProformaService.cleanBrandToFormula(name);
      final cleanF = MasterProformaService.cleanBrandToFormula(formula);
      if (cleanN != name || cleanF != formula) {
        final copy = Map<String, dynamic>.from(i);
        copy['name'] = cleanN;
        copy['formula'] = cleanF;
        return copy;
      }
      return i;
    }).toList();
  }

  // ─── Inventory Audit Logs ───────────────────────────────────────────────────

  static Future<void> saveLocalInventoryLog(Map<String, dynamic> logData) async {
    try {
      if (!Hive.isBoxOpen(auditLogsBox)) {
        await Hive.openBox(auditLogsBox);
      }
      final box = Hive.box(auditLogsBox);
      final id = logData['id'] ?? logData['docId'] ?? const Uuid().v4();
      final key = 'inv_log_$id';
      await box.put(key, sanitize({
        ...logData,
        'id': id,
        'savedAt': DateTime.now().toIso8601String(),
      }));
      debugPrint('[LocalStorageService] 📝 Saved local inventory audit log: $key (${logData['action']})');
    } catch (e) {
      debugPrint('[LocalStorageService] Error saving local inventory log: $e');
    }
  }

  static List<Map<String, dynamic>> getLocalInventoryLogs({String? branchId, String? medicineId}) {
    try {
      if (!Hive.isBoxOpen(auditLogsBox)) return [];
      final box = Hive.box(auditLogsBox);
      final logs = <Map<String, dynamic>>[];
      for (final k in box.keys) {
        if (k.toString().startsWith('inv_log_')) {
          final val = box.get(k);
          if (val is Map) {
            final map = Map<String, dynamic>.from(val);
            if (branchId != null && branchId.isNotEmpty && branchId != 'default') {
              final b = (map['branchId'] ?? '').toString().trim().toLowerCase();
              if (b.isNotEmpty && b != 'default' && b != branchId.toLowerCase()) continue;
            }
            if (medicineId != null && medicineId.isNotEmpty) {
              final mId = (map['medicineId'] ?? map['docId'] ?? '').toString().trim();
              if (mId != medicineId) continue;
            }
            logs.add(map);
          }
        }
      }
      logs.sort((a, b) => (b['createdAt'] ?? b['timestamp'] ?? '').toString().compareTo((a['createdAt'] ?? a['timestamp'] ?? '').toString()));
      return logs;
    } catch (_) {
      return [];
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DISPENSARY
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveLocalDispensaryRecord(
      Map<String, dynamic> record) async {
    final branchId = record['branchId']?.toString() ?? '';
    final serial   = record['serial']?.toString() ?? '';
    final dateKey  = record['dateKey']?.toString() ?? getTodayDateKey();
    if (branchId.isEmpty || serial.isEmpty) return;
    await Hive.box(dispensaryBox)
        .put('${branchId}_${dateKey}_$serial', sanitize(record));
  }

  static Map<String, dynamic>? getLocalDispensaryRecord(
      String branchId, String serial, {String? dateKey}) {
    // FIX 2: normalize branchId before it's used to build the Hive key below.
    branchId = branchId.toLowerCase().trim();
    final dk  = dateKey ?? getTodayDateKey();
    final val = Hive.box(dispensaryBox).get('${branchId}_${dk}_$serial');
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static List<Map<String, dynamic>> getLocalDispensaryRecords(
      String branchId, {String? dateKey}) {
    // FIX 2: normalize branchId before it's used to build the Hive key prefix.
    branchId = branchId.toLowerCase().trim();
    final dk     = dateKey ?? getTodayDateKey();
    final prefix = '${branchId}_${dk}_';
    return Hive.box(dispensaryBox)
        .keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => Map<String, dynamic>.from(
            Hive.box(dispensaryBox).get(k) as Map))
        .toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BRANCHES
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveLocalBranch(Map<String, dynamic> branch) async {
    final id = branch['id']?.toString();
    if (id == null) return;
    await Hive.box(branchesBox).put('branch:$id', sanitize(branch));
  }

  static Future<void> deleteLocalBranch(String id) async =>
      Hive.box(branchesBox).delete('branch:$id');

  // ════════════════════════════════════════════════════════════════════════════
  // FIRESTORE DOWNLOAD HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> downloadAllPatients(String branchId) async {
    branchId = branchId.toLowerCase().trim();
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .get();
      final patients = snapshot.docs.map((doc) {
        final d = doc.data();
        d['patientId'] = doc.id;
        d['branchId']  = branchId;
        return d;
      }).toList();
      await saveAllLocalPatients(patients);

      final flagsBox = Hive.box('app_flags');
      for (final doc in snapshot.docs) {
        await flagsBox.put('patient_synced_${doc.id}', true);
      }
    } catch (e) {
      debugPrint('[LocalStorage] downloadAllPatients error: $e');
    }
  }

  static Future<void> downloadTodayTokens(String branchId) async {
    // FIX 2: normalize branchId FIRST — this is the primary method Fix 2
    // targets. Every Hive key built below ('$branchId-...') previously used
    // whatever casing the caller passed, while saveEntryLocal() always
    // lowercases, so a differently-cased caller here would miss the real
    // local record and let stale server data silently overwrite a
    // completed/dispensed token's protected status.
    branchId = branchId.toLowerCase().trim();
    final today = getTodayDateKey();
    final box   = Hive.box(entriesBox);

    try {
      final dateDocs = CampSessionService.getAllCampDateDocIds(
        branchId: branchId,
        dateKey: today,
      );

      final Map<String, Map<String, dynamic>> freshEntries = {};
      final List<DocumentReference> duplicateDocsToDelete = [];

      for (final docDateKey in dateDocs) {
        final serialsRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(docDateKey);

        for (final type in ['zakat', 'non-zakat', 'gmwf']) {
          try {
            final snap = await serialsRef.collection(type).get();
          for (final doc in snap.docs) {
            final rawId = doc.id.trim();
            final upperId = rawId.toUpperCase();
            final isLowercase = (rawId != upperId);

            final d = Map<String, dynamic>.from(doc.data());
            d['serial']    = upperId;
            d['dateKey']   = today;
            d['branchId']  = branchId;
            d['queueType'] = type;
            if (upperId.contains('-SADD-') || upperId.contains('-KAP-') || upperId.contains('-KAPAYYA-')) {
              d['dispensaryId'] = 'saddar';
              d['campId']       = 'saddar';
              d['dispensaryTag'] = 'SADD';
            } else if (upperId.contains('-HAJI-') || upperId.contains('-HAJ-') || upperId.contains('-HC-')) {
              d['dispensaryId'] = 'haji_camp';
              d['campId']       = 'haji_camp';
              d['dispensaryTag'] = 'HAJI';
            } else if (d['dispensaryTag'] == null || d['dispensaryTag'].toString().trim().isEmpty) {
              final parts = upperId.split('-');
              if (parts.length >= 3) {
                d['dispensaryTag'] = parts[1].toUpperCase();
              }
            }

            final hiveKey = '$branchId-$upperId';

            if (freshEntries.containsKey(hiveKey)) {
              // Merge data into canonical uppercase entry
              final existingData = freshEntries[hiveKey]!;
              if (d['prescription'] != null && existingData['prescription'] == null) {
                existingData['prescription'] = d['prescription'];
                existingData['prescriptionId'] = d['prescriptionId'];
              }
              if (d['prescriptions'] != null && existingData['prescriptions'] == null) {
                existingData['prescriptions'] = d['prescriptions'];
              }
              if (d['status'] == 'completed' || d['status'] == 'dispensed') {
                existingData['status'] = d['status'];
              }
              if (isLowercase) {
                duplicateDocsToDelete.add(doc.reference);
              }
            } else {
              freshEntries[hiveKey] = d;
              if (isLowercase) {
                duplicateDocsToDelete.add(doc.reference);
              }
            }
          }
        } catch (_) {}
      }
    }

      // Cleanup duplicate lowercase docs from Firestore to save cloud space & quota
      for (final docRef in duplicateDocsToDelete) {
        try {
          await docRef.delete();
          debugPrint('[LocalStorage] 🧹 Cleaned duplicate lowercase doc from Firestore: ${docRef.path}');
        } catch (_) {}
      }

      const terminalStatuses = ['completed', 'dispensed'];
      final Map<String, dynamic> tokensToPut = {};
      for (final entry in freshEntries.entries) {
        final hiveKey  = entry.key;
        final fresh    = entry.value;
        final existing = box.get(hiveKey);
        Map<String, dynamic> merged = sanitize(fresh);
        if (existing is Map) {
          final ex = Map<String, dynamic>.from(existing);
          final localStatus  = ex['status']?.toString() ?? '';
          final mergedStatus = merged['status']?.toString() ?? '';
          final exDisp = (ex['dispensaryId'] ?? ex['campId'])?.toString().trim();
          if (exDisp != null && exDisp.isNotEmpty) {
            merged['dispensaryId'] = (merged['dispensaryId']?.toString().isNotEmpty == true) ? merged['dispensaryId'] : exDisp;
            merged['campId']       = (merged['campId']?.toString().isNotEmpty == true)       ? merged['campId']       : exDisp;
          }
          if (terminalStatuses.contains(localStatus) &&
              !terminalStatuses.contains(mergedStatus)) {
            merged['status'] = localStatus;
          }
          if (ex['dispenseStatus']?.toString() == 'dispensed') {
            merged['dispenseStatus'] = 'dispensed';
            if (ex['dispensedAt'] != null) merged['dispensedAt'] = ex['dispensedAt'];
            if (ex['dispensedBy'] != null) merged['dispensedBy'] = ex['dispensedBy'];
          }
          if (ex['prescription'] != null && merged['prescription'] == null) {
            merged['prescription']   = ex['prescription'];
            merged['prescriptionId'] = ex['prescriptionId'];
          }
          for (final field in ['dispenserName', 'completedAt']) {
            if (ex[field] != null && merged[field] == null) merged[field] = ex[field];
          }
        }

        // Cross-check local prescription in prescriptionsBox to ensure completed status is never reverted
        final serial = (merged['serial'] ?? fresh['serial'])?.toString() ?? '';
        if (serial.isNotEmpty) {
          final localPresc = getLocalPrescription(serial);
          if (localPresc != null) {
            merged['status'] = 'completed';
            merged['prescription'] = localPresc;
            merged['prescriptionId'] = localPresc['id'] ?? serial;
            if (localPresc['completedAt'] != null && merged['completedAt'] == null) {
              merged['completedAt'] = localPresc['completedAt'];
            }
            if (localPresc['doctorName'] != null && merged['doctorName'] == null) {
              merged['doctorName'] = localPresc['doctorName'];
            }
            if (localPresc['doctorId'] != null && merged['doctorId'] == null) {
              merged['doctorId'] = localPresc['doctorId'];
            }
            if (localPresc['daysOfMedicine'] != null && merged['daysOfMedicine'] == null) {
              merged['daysOfMedicine'] = localPresc['daysOfMedicine'];
            }
          }
        }

        tokensToPut[hiveKey] = merged;
      }
      if (tokensToPut.isNotEmpty) {
        await box.putAll(tokensToPut);
      }

      final now = DateTime.now();
      for (final key in box.keys.toList()) {
        final keyStr = key.toString();
        if (!keyStr.startsWith('$branchId-')) continue;
        final val = box.get(key);
        if (val is! Map) continue;
        final entry = Map<String, dynamic>.from(val);

        final dk = entry['dateKey']?.toString();
        if (dk != today) continue;

        if (entry['pendingSync'] == true || entry['isTempSerial'] == true) continue;

        final serial = entry['serial']?.toString();
        if (serial == null || serial.isEmpty) continue;

        if (!freshEntries.containsKey(keyStr)) {
          final createdStr = entry['createdAt']?.toString();
          if (createdStr != null) {
            try {
              final createdDt = DateTime.parse(createdStr);
              if (now.difference(createdDt).inMinutes >= 5) {
                final status = (entry['status'] ?? '').toString().toLowerCase();
                if (status != 'cancelled' && status != 'deleted') {
                  entry['status'] = 'cancelled';
                  await box.put(key, sanitize(entry));
                  debugPrint('[LocalStorage] Server deletion reconciled: marked $serial as cancelled');
                }
              }
            } catch (_) {}
          }
        }
      }
      await box.flush();
    } catch (e) {
      debugPrint('[LocalStorage] downloadTodayTokens error: $e');
    }
  }

  static Future<void> downloadInventory(String branchId, {bool forceFull = false, String? campId}) async {
    branchId = branchId.toLowerCase().trim();
    try {
      final invPaths = CampSessionService.getAllCampInventoryPaths(
        branchId: branchId,
        selectedCamp: campId ?? CampSessionService.getActiveCamp(),
      );

      for (final invCol in invPaths) {
        final syncKey = 'inventory_${branchId}_$invCol';
        final lastSyncedStr = getLastSyncedServerTimestamp(syncKey);
        final currentCount = Hive.box(stockBox).length;

        Query query = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection(invCol);

        if (!forceFull && currentCount >= 15 && lastSyncedStr != null && lastSyncedStr.isNotEmpty) {
          final dt = DateTime.tryParse(lastSyncedStr);
          if (dt != null) {
            query = query.where('updatedAt', isGreaterThan: Timestamp.fromDate(dt));
          }
        }

        var snapshot = await query.get();
        // Fallback: If incremental returned nothing but cache is unexpectedly low, fetch all
        if (snapshot.docs.isEmpty && currentCount < 10) {
          snapshot = await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .collection(invCol)
              .get();
        }

        if (snapshot.docs.isNotEmpty) {
          final items = snapshot.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            d['id'] = doc.id;
            d['branchId'] = branchId;
            if (invCol == 'inventory_saddar') {
              d['campId'] = 'saddar';
              d['dispensaryId'] = 'saddar';
            } else if (invCol == 'inventory_haji') {
              d['campId'] = 'haji_camp';
              d['dispensaryId'] = 'haji_camp';
            }
            return d;
          }).toList();
          await saveAllLocalStockItems(items);

          Timestamp? maxTs;
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            final ts = data?['updatedAt'] ?? data?['addedAt'] ?? data?['timestamp'];
            if (ts is Timestamp) {
              if (maxTs == null || ts.compareTo(maxTs) > 0) {
                maxTs = ts;
              }
            }
          }
          if (maxTs != null) {
            await setLastSyncedServerTimestamp(
              syncKey,
              maxTs.toDate().toUtc().toIso8601String(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalStorage] downloadInventory error: $e');
    }
  }

  static Future<void> refreshPrescriptions(String branchId) async {
    branchId = branchId.toLowerCase().trim();
    try {
      final cnicDocs = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('prescriptions')
          .get();
      final prescMap = <String, Map<String, dynamic>>{};
      for (final cnicDoc in cnicDocs.docs) {
        final patientCnic = cnicDoc.id;
        final subSnap     = await cnicDoc.reference
            .collection('prescriptions')
            .get();
        for (final presDoc in subSnap.docs) {
          final d = presDoc.data();
          d['id'] = presDoc.id;
          d['serial']      = presDoc.id;
          d['patientCnic'] = patientCnic;
          d['cnic']        = patientCnic;
          d['branchId']    = branchId;
          prescMap['${patientCnic}_${presDoc.id}'] = sanitize(d);
        }
      }
      await Hive.box(prescriptionsBox).clear();
      await Hive.box(prescriptionsBox).putAll(prescMap);
    } catch (e) {
      debugPrint('[LocalStorage] refreshPrescriptions error: $e');
    }
  }

  // ── Medicine Restrictions (Multi-day tokens) ───────────────────────────────

  static String _cleanId(String id) => id.trim().replaceAll(RegExp(r'[-\s]'), '');

  static Future<void> saveMedicineRestriction({
    required String branchId,
    required String patientId,
    required int daysCovered,
  }) async {
    // FIX 2: normalize branchId before it's used to build the Hive key below.
    branchId = branchId.toLowerCase().trim();
    final cleanId = _cleanId(patientId);
    if (cleanId.isEmpty) return;

    final box  = Hive.box(medicineRestrictionsBox);
    final key  = '${branchId}_$cleanId';
    final now  = DateTime.now();

    final issuedDate     = DateTime(now.year, now.month, now.day);
    final lastBlockedDay = issuedDate.add(Duration(days: daysCovered - 1));

    final record = <String, dynamic>{
      'patientId':      cleanId,
      'branchId':       branchId,
      'issuedAt':       now.toIso8601String(),
      'issuedDateOnly': issuedDate.toIso8601String(),
      'daysCovered':    daysCovered,
      'lastBlockedDay': lastBlockedDay.toIso8601String(),
    };

    await box.put(key, record);
    await box.flush();

    await enqueueSync({
      'type':      'save_medicine_restriction',
      'branchId':  branchId,
      'patientId': cleanId,
      'data':      record,
    });

    debugPrint('[LSS] Restriction saved + enqueued for Firestore sync: $cleanId '
        'blocked until $lastBlockedDay ($daysCovered-day rx)');
  }

  static Future<void> downloadMedicineRestrictions(String branchId) async {
    // FIX 2: normalize branchId before it's used to build the Hive key prefix
    // (and cleared-stale-key logic) below.
    branchId = branchId.toLowerCase().trim();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('medicine_restrictions')
          .get();

      final box   = Hive.box(medicineRestrictionsBox);
      final today = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
      
      final downloadedIds = <String>{};
      int loaded = 0;

      for (final doc in snap.docs) {
        final d              = Map<String, dynamic>.from(doc.data());
        final lastBlockedStr = d['lastBlockedDay'] as String?;

        if (lastBlockedStr != null) {
          final lb             = DateTime.parse(lastBlockedStr);
          final lastBlockedDay = DateTime(lb.year, lb.month, lb.day);
          if (today.isAfter(lastBlockedDay)) continue;
        }

        final patientId = doc.id;
        final hiveKey   = '${branchId}_$patientId';
        await box.put(hiveKey, d);
        downloadedIds.add(patientId);
        loaded++;
      }

      final prefix = '${branchId}_';
      final localKeysToClear = box.keys
          .where((k) => k.toString().startsWith(prefix))
          .map((k) => k.toString().replaceFirst(prefix, ''))
          .where((id) => !downloadedIds.contains(id))
          .toList();

      for (final id in localKeysToClear) {
        final key = '$prefix$id';
        await box.delete(key);
        debugPrint('[LSS] Cleared stale restriction (synced delete) for $id');
      }

      await box.flush();
      debugPrint('[LSS] Downloaded $loaded active medicine restrictions for $branchId. '
          'Cleared ${localKeysToClear.length} stale ones.');
    } catch (e) {
      debugPrint('[LSS] downloadMedicineRestrictions error: $e');
    }
  }

  static Map<String, dynamic>? getMedicineRestriction(String branchId, String patientId) {
    if (!Hive.isBoxOpen(medicineRestrictionsBox)) return null;
    // FIX 2: normalize branchId before it's used to build the Hive key below.
    branchId = branchId.toLowerCase().trim();
    final cleanId = _cleanId(patientId);
    final box = Hive.box(medicineRestrictionsBox);
    final key = '${branchId}_$cleanId';
    final data = box.get(key);
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<void> clearMedicineRestriction(String branchId, String patientId) async {
    // FIX 2: normalize branchId before it's used to build the Hive key below.
    branchId = branchId.toLowerCase().trim();
    final cleanId = _cleanId(patientId);
    final box = Hive.box(medicineRestrictionsBox);
    final key = '${branchId}_$cleanId';
    await box.delete(key);
    await box.flush();
    debugPrint('[LocalStorage] 🗑️ Medicine restriction cleared for $cleanId');
  }

  // ── TOKEN EXCEPTIONS ────────────────────────────────────────────────────────
  /// Grants a token exception for a patient on a specific dateKey.
  static Future<void> grantTokenException(
    String branchId,
    String patientId, {
    String? dateKey,
    String? reason,
    String? approvedBy,
    String? requestId,
  }) async {
    final normBranch = branchId.toLowerCase().trim();
    final normPid = _cleanId(patientId);
    final today = dateKey ?? getTodayDateKey();
    final key = '${normBranch}_${normPid}_$today';

    try {
      if (Hive.isBoxOpen(tokenExceptionsBox)) {
        await Hive.box(tokenExceptionsBox).put(key, {
          'branchId': normBranch,
          'patientId': normPid,
          'dateKey': today,
          'reason': reason ?? 'Approved by Doctor',
          'approvedBy': approvedBy ?? 'Doctor',
          'approvedAt': DateTime.now().toIso8601String(),
          'used': false,
          'requestId': requestId,
        });
      }
    } catch (_) {}

    // Also clear from issued_token_keys so idempotency check does not block
    try {
      final idempotencyKey = '${normBranch}_${normPid}_$today';
      if (Hive.isBoxOpen('issued_token_keys')) {
        await Hive.box('issued_token_keys').delete(idempotencyKey);
        await Hive.box('issued_token_keys').delete('${branchId}_${patientId}_$today');
      }
    } catch (_) {}

    // Clear medicine restriction as well
    await clearMedicineRestriction(normBranch, patientId);
    debugPrint('[LocalStorage] 🎟️ Token exception granted for $normPid on $today ($reason)');
  }

  /// Checks if an approved and unused token exception exists for this patient today
  static bool hasApprovedTokenException(String branchId, String patientId, {String? dateKey}) {
    final normBranch = branchId.toLowerCase().trim();
    final normPid = _cleanId(patientId);
    final today = dateKey ?? getTodayDateKey();
    final key = '${normBranch}_${normPid}_$today';

    try {
      if (Hive.isBoxOpen(tokenExceptionsBox)) {
        final val = Hive.box(tokenExceptionsBox).get(key);
        if (val is Map) {
          final used = val['used'] == true;
          return !used;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Consumes the token exception once a new token is successfully generated
  static Future<void> consumeTokenException(String branchId, String patientId, {String? dateKey}) async {
    final normBranch = branchId.toLowerCase().trim();
    final normPid = _cleanId(patientId);
    final today = dateKey ?? getTodayDateKey();
    final key = '${normBranch}_${normPid}_$today';

    try {
      if (Hive.isBoxOpen(tokenExceptionsBox)) {
        final val = Hive.box(tokenExceptionsBox).get(key);
        if (val is Map) {
          final updated = Map<String, dynamic>.from(val);
          updated['used'] = true;
          updated['usedAt'] = DateTime.now().toIso8601String();
          await Hive.box(tokenExceptionsBox).put(key, updated);
          debugPrint('[LocalStorage] 🎟️ Token exception consumed for $normPid on $today');
        }
      }
    } catch (_) {}
  }

  /// Gets the token exception details for a patient
  static Map<String, dynamic>? getTokenException(String branchId, String patientId, {String? dateKey}) {
    final normBranch = branchId.toLowerCase().trim();
    final normPid = _cleanId(patientId);
    final today = dateKey ?? getTodayDateKey();
    final key = '${normBranch}_${normPid}_$today';

    try {
      if (Hive.isBoxOpen(tokenExceptionsBox)) {
        final val = Hive.box(tokenExceptionsBox).get(key);
        if (val is Map) return Map<String, dynamic>.from(val);
      }
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic>? isPatientBlockedByMedicine(
      String branchId, String patientId) {
    final restriction = getMedicineRestriction(branchId, patientId);
    if (restriction == null) return null;

    final today = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);

    final lastBlockedStr =
        restriction['lastBlockedDay'] as String?;

    if (lastBlockedStr != null) {
      final lastBlocked = DateTime.parse(lastBlockedStr);
      final lastBlockedDay =
          DateTime(lastBlocked.year, lastBlocked.month, lastBlocked.day);

      if (today.isAfter(lastBlockedDay)) {
        clearMedicineRestriction(branchId, patientId);
        return null;
      }
      final todayOnly = DateTime(today.year, today.month, today.day);
      final diff = lastBlockedDay.difference(todayOnly).inDays;

      return {
        ...restriction,
        'remainingDays': diff,
        'isLastDay': diff == 0,
      };
    }

    final expiresStr = restriction['expiresAt'] as String?;
    if (expiresStr == null) {
      clearMedicineRestriction(branchId, patientId);
      return null;
    }
    final expiresAt    = DateTime.parse(expiresStr);
    final expireDay    =
        DateTime(expiresAt.year, expiresAt.month, expiresAt.day)
        .subtract(const Duration(days: 1));

    if (today.isAfter(expireDay)) {
      clearMedicineRestriction(branchId, patientId);
      return null;
    }
    final remaining = expireDay.difference(today).inDays + 1;
    return {...restriction, 'remainingDays': remaining};
  }
  // ════════════════════════════════════════════════════════════════════════════
  // DONATION RECEIPT NUMBERING
  // ════════════════════════════════════════════════════════════════════════════

  static String getBranchCode(String branchId) {
    final b = branchId.toLowerCase().trim();
    if (b.contains('gujrat')) return 'grt';
    if (b.contains('sialkot')) return 'skt';
    if (b.contains('lahore')) return 'lhr';
    if (b.contains('karachi 1')) return 'krh1';
    if (b.contains('karachi')) return 'khi';
    if (b.contains('rawalpindi')) return 'rwp';
    if (b.contains('peshawar')) return 'psh';
    if (b.contains('multan')) return 'mul';
    if (b.contains('faisalabad')) return 'fsd';
    if (b.contains('islamabad')) return 'isb';
    if (b.contains('quetta')) return 'qta';
    if (b.length <= 3) return b;
    return b.substring(0, 3);
  }

  static Future<String> nextReceiptNumber([String branchId = '']) async {
    final box = Hive.box('app_settings');
    final code = getBranchCode(branchId);
    
    final key = 'receipt_seq_$code';
    final current = box.get(key, defaultValue: 0) as int;
    final next = current + 1;
    await box.put(key, next);
    
    final globalKey = 'receipt_seq_global';
    final globalCurrent = box.get(globalKey, defaultValue: 0) as int;
    if (next > globalCurrent) await box.put(globalKey, next);

    return formatReceiptNumber(next, code);
  }

  static Future<int> getNextLocalSerialSequence(
    String branchId,
    String dateKey, {
    String? dispensaryId,
    bool increment = false,
  }) async {
    // FIX 2: normalize branchId before it's used (via getLocalEntries and
    // the counter key below) to build/read Hive keys.
    branchId = branchId.toLowerCase().trim();
    final counterBox = Hive.box('app_settings');
    final activeCamp = dispensaryId ?? CampSessionService.getActiveCamp();
    final dispTag = CampSessionService.getDispensaryKeyword(activeCamp);
    final counterKey = 'counter_${branchId}_${dateKey}_$dispTag';
    final savedSeq = (counterBox.get(counterKey) as num?)?.toInt() ?? 0;

    final entries = getLocalEntries(branchId, dispensaryId: activeCamp, filterByCamp: true)
        .where((m) => (m['dateKey'] as String?) == dateKey);

    int maxSeq = savedSeq;
    for (final m in entries) {
      final s = (m['serial'] ?? '').toString().trim();
      if (s.isEmpty) continue;
      final seq = parseSequenceFromSerial(s);
      if (seq < 9999 && seq > maxSeq) {
        maxSeq = seq;
      }
    }

    final nextSeq = maxSeq + 1;
    if (increment) {
      await counterBox.put(counterKey, nextSeq);
    }
    return nextSeq;
  }

  static String formatReceiptNumber(int seq, [String branchCode = '']) {
    final padded = seq.toString().padLeft(3, '0');
    final tid = Hive.box('app_settings').get('terminal_id', defaultValue: '');
    
    String res = 'GMWF';
    if (branchCode.isNotEmpty) res += '-$branchCode';
    res += '-$padded';
    if (tid.isNotEmpty) res += '-$tid';
    
    return res;
  }

  static Future<String> nextDonorNumber() async {
    final box = Hive.box('app_settings');
    const key = 'donor_global_seq';
    final current = box.get(key, defaultValue: 0) as int;
    final next = current + 1;
    await box.put(key, next);
    
    return formatDonorId(next);
  }

  static String formatDonorId(int seq) {
    final padded = seq.toString().padLeft(8, '0');
    return 'DNR-$padded';
  }

  // ── Branch Data Enrichment Helper ──────────────────────────────────────────
  static String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty && s != 'N/A' && s != 'null') return s;
    }
    return '';
  }

  static String _resolvePatientId(Map<String, dynamic> data) {
    for (final key in ['patientId', 'id', 'uid']) {
      final v = data[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _resolveType(Map<String, dynamic> data) {
    final raw = (data['queueType'] ?? data['type'] ?? '').toString().toLowerCase().trim();
    switch (raw) {
      case 'zakat':     return 'zakat';
      case 'non-zakat': return 'non-zakat';
      case 'gmwf':      return 'gmwf';
      default:          return 'Unknown';
    }
  }

  static Future<List<Map<String, dynamic>>> enrichRawDocs(
      String branchId, List<Map<String, dynamic>> rawList) async {
    if (rawList.isEmpty) return [];
    final normBranchId = branchId.toLowerCase().trim();

    final serialToDoctor  = <String, String>{};
    final serialToTokenBy = <String, String>{};
    final serialToDays    = <String, int>{};
    
    final List<String> missingDoctorSerials = [];
    for (final item in rawList) {
      final serial = item['serial']?.toString() ?? '';
      final existingDoctor = _firstNonEmpty([item['doctorName'], item['prescribedBy'], item['updatedBy']]);
      if (existingDoctor.isEmpty && serial.isNotEmpty) {
        missingDoctorSerials.add(serial);
      }
    }

    final List<List<String>> serialChunks = [];
    for (int i = 0; i < missingDoctorSerials.length; i += 30) {
      serialChunks.add(missingDoctorSerials.sublist(i, (i + 30).clamp(0, missingDoctorSerials.length)));
    }

    final List<Future<QuerySnapshot>> presFutures = [];
    for (final chunk in serialChunks) {
      presFutures.add(FirebaseFirestore.instance
          .collectionGroup('prescriptions')
          .where('branchId', isEqualTo: normBranchId)
          .where('serial', whereIn: chunk)
          .get());
    }

    try {
      if (presFutures.isNotEmpty) {
        final presSnaps = await Future.wait(presFutures);
        for (final snap in presSnaps) {
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final serial = data['serial']?.toString() ?? '';
            if (serial.isEmpty) continue;
            final doctor = _firstNonEmpty([data['doctorName'], data['prescribedBy'], data['updatedBy']]);
            if (doctor.isNotEmpty) serialToDoctor[serial] = doctor;
            if (!serialToDays.containsKey(serial)) {
              final pd = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
              if (pd > 1) serialToDays[serial] = pd;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalStorage] collectionGroup prescriptions query failed: $e. Falling back to direct doc gets.');
      for (final item in rawList) {
        final serial = item['serial']?.toString() ?? '';
        if (serial.isEmpty) continue;
        final existingDoctor = _firstNonEmpty([item['doctorName'], item['prescribedBy'], item['updatedBy']]);
        if (existingDoctor.isNotEmpty) continue;
        final pId = _firstNonEmpty([
          item['patientCnic'], item['cnic'], item['guardianCnic'],
          item['patientId'], item['id']
        ]);
        if (pId.isEmpty) continue;
        try {
          final doc = await FirebaseFirestore.instance
              .collection('branches')
              .doc(normBranchId)
              .collection('prescriptions')
              .doc(pId)
              .collection('prescriptions')
              .doc(serial)
              .get();
          if (doc.exists && doc.data() != null) {
            final data = doc.data() as Map<String, dynamic>;
            final doctor = _firstNonEmpty([data['doctorName'], data['prescribedBy'], data['updatedBy']]);
            if (doctor.isNotEmpty) serialToDoctor[serial] = doctor;
            if (!serialToDays.containsKey(serial)) {
              final pd = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
              if (pd > 1) serialToDays[serial] = pd;
            }
          }
        } catch (directErr) {
          debugPrint('[LocalStorage] Direct prescription fetch failed for $serial: $directErr');
        }
      }
    }

    final List<String> missingTokenZakat = [];
    final List<String> missingTokenNonZakat = [];
    final List<String> missingTokenGmwf = [];

    for (final item in rawList) {
      final serial = item['serial']?.toString() ?? '';
      if (serial.isEmpty) continue;

      final days = (item['daysOfMedicine'] as num?)?.toInt() ?? 1;
      if (days > 1) serialToDays[serial] = days;

      final existingToken = _firstNonEmpty(
          [item['createdByName'], item['tokenBy'], item['createdBy']]);
      if (existingToken.isEmpty) {
        final type = _resolveType(item);
        if (type == 'zakat') {
          missingTokenZakat.add(serial);
        } else if (type == 'non-zakat') {
          missingTokenNonZakat.add(serial);
        } else if (type == 'gmwf') {
          missingTokenGmwf.add(serial);
        }
      }
    }

    final List<Future<QuerySnapshot>> tokenFutures = [];
    void addTokenFutures(List<String> serials, String collectionName) {
      for (int i = 0; i < serials.length; i += 30) {
        final chunk = serials.sublist(i, (i + 30).clamp(0, serials.length));
        tokenFutures.add(FirebaseFirestore.instance
            .collectionGroup(collectionName)
            .where('branchId', isEqualTo: normBranchId)
            .where('serial', whereIn: chunk)
            .get());
      }
    }

    addTokenFutures(missingTokenZakat, 'zakat');
    addTokenFutures(missingTokenNonZakat, 'non-zakat');
    addTokenFutures(missingTokenGmwf, 'gmwf');

    try {
      if (tokenFutures.isNotEmpty) {
        final tokenSnaps = await Future.wait(tokenFutures);
        for (final snap in tokenSnaps) {
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final serial = data['serial']?.toString() ?? '';
            if (serial.isEmpty) continue;
            final tokenBy = _firstNonEmpty([data['createdByName'], data['tokenBy'], data['createdBy']]);
            if (tokenBy.isNotEmpty) serialToTokenBy[serial] = tokenBy;
            if (!serialToDays.containsKey(serial)) {
              final pd = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
              if (pd > 1) serialToDays[serial] = pd;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalStorage] collectionGroup tokens query failed: $e. Falling back to direct doc gets.');
      for (final item in rawList) {
        final serial = item['serial']?.toString() ?? '';
        if (serial.isEmpty) continue;
        final existingToken = _firstNonEmpty([item['createdByName'], item['tokenBy'], item['createdBy']]);
        if (existingToken.isNotEmpty) continue;
        
        final type = _resolveType(item);
        if (type == 'Unknown') continue;
        
        final dateKey = item['dateKey']?.toString() ?? 
                       (serial.contains('-') ? serial.split('-')[0] : DateFormat('ddMMyy').format(DateTime.now()));
                       
        try {
          final doc = await FirebaseFirestore.instance
              .collection('branches')
              .doc(normBranchId)
              .collection('serials')
              .doc(dateKey)
              .collection(type)
              .doc(serial)
              .get();
          if (doc.exists && doc.data() != null) {
            final data = doc.data() as Map<String, dynamic>;
            final tokenBy = _firstNonEmpty([data['createdByName'], data['tokenBy'], data['createdBy']]);
            if (tokenBy.isNotEmpty) serialToTokenBy[serial] = tokenBy;
            if (!serialToDays.containsKey(serial)) {
              final pd = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
              if (pd > 1) serialToDays[serial] = pd;
            }
          }
        } catch (directErr) {
          debugPrint('[LocalStorage] Direct token fetch failed for $serial (type: $type, date: $dateKey): $directErr');
        }
      }
    }


    final uniquePatientIds =
        rawList.map((d) => _resolvePatientId(d)).where((id) => id.isNotEmpty).toSet();
    Map<String, Map<String, dynamic>> patientMap = {};
    final patientBox = Hive.box(patientsBox);
    for (final pid in uniquePatientIds) {
      final localData = patientBox.get(pid);
      if (localData is Map) {
        patientMap[pid] = Map<String, dynamic>.from(localData);
      }
    }

    final guardianCnics = <String>{};
    for (final p in patientMap.values) {
      final cnic = p['cnic']?.toString().trim() ?? '';
      if (cnic.isEmpty) {
        final gcnic = p['guardianCnic']?.toString().trim() ?? '';
        if (gcnic.isNotEmpty) guardianCnics.add(gcnic);
      }
    }
    final Map<String, String> guardianNames = {};
    for (final gcnic in guardianCnics) {
      final localGuardian = getLocalPatientByCnic(gcnic);
      if (localGuardian != null) {
        guardianNames[gcnic] = localGuardian['name'] ?? 'N/A';
      }
    }

    final enriched = <Map<String, dynamic>>[];
    for (final data in rawList) {
      final pid    = _resolvePatientId(data);
      final p      = pid.isNotEmpty ? patientMap[pid] : null;
      final serial = data['serial']?.toString() ?? '';

      final vitals = data['vitals'] as Map<String, dynamic>? ?? {};

      final name = _firstNonEmpty([
        data['patientName'], data['name'], vitals['name'], p?['name'], 'Unknown',
      ]);
      final phone = _firstNonEmpty([data['phone'], p?['phone'], 'N/A']);
      final age   = _firstNonEmpty([
        data['patientAge'], data['age'], vitals['age']?.toString(), p?['age']?.toString(), 'N/A',
      ]);
      final gender = _firstNonEmpty([
        data['patientGender'], data['gender'], vitals['gender'], p?['gender'], 'N/A',
      ]);
      final bloodGroup = _firstNonEmpty([
        data['bloodGroup'], vitals['bloodGroup'], p?['bloodGroup'], 'N/A',
      ]);

      String  displayCnic = 'N/A';
      bool    isChild     = false;
      String? guardianName;
      final directCnic = _firstNonEmpty(
          [data['patientCnic'], data['cnic'], p?['cnic']?.toString().trim()]);
      if (directCnic.isNotEmpty && directCnic != 'N/A' && directCnic != '0000000000000') {
        displayCnic = directCnic;
        isChild     = false;
      } else {
        final gcnic = _firstNonEmpty([data['guardianCnic'], p?['guardianCnic']?.toString().trim()]);
        displayCnic = gcnic.isNotEmpty ? gcnic : 'N/A';
        isChild     = true;
        if (gcnic.isNotEmpty) guardianName = guardianNames[gcnic];
      }

      final possibleIds = <String>{};
      if (pid.isNotEmpty) possibleIds.add(pid);
      if (directCnic.isNotEmpty && directCnic != 'N/A') possibleIds.add(directCnic);
      if (isChild && displayCnic != 'N/A') possibleIds.add(displayCnic);

      final medicDays = serialToDays[serial] ?? 1;

      final type = _resolveType(data);
      int tokenAmount = 0;
      if (type == 'zakat')     tokenAmount = 20  * medicDays;
      if (type == 'non-zakat') tokenAmount = 100 * medicDays;

      enriched.add({
        ...data,
        'name':           name,
        'phone':          phone,
        'age':            age,
        'gender':         gender,
        'bloodGroup':     bloodGroup,
        'displayCnic':    displayCnic,
        'isChild':        isChild,
        if (guardianName != null) 'guardianName': guardianName,
        'patientId':      pid,
        'possibleIds':    possibleIds.toList(),
        'doctorName':     _firstNonEmpty([
          data['doctorName'], data['prescribedBy'], data['updatedBy'],
          serialToDoctor[serial], 'Unknown',
        ]),
        'dispenserName':  _firstNonEmpty([data['dispenserName'], data['dispensedBy'], 'Unknown']),
        'tokenBy':        _firstNonEmpty([
          data['createdByName'], data['tokenBy'], serialToTokenBy[serial],
          data['createdBy'], 'Unknown',
        ]),
        'frequentFlag':   p?['frequentFlag'] ?? false,
        'daysOfMedicine': medicDays,
        'tokenAmount':    tokenAmount,
      });
    }

    return enriched;
  }

  // ── Delta Sync Metadata & Server Timestamp Helpers ─────────────────────────
  static String? getLastSyncedServerTimestamp(String collectionKey) {
    try {
      final box = Hive.box(syncMetaBox);
      return box.get('last_server_ts_$collectionKey') as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setLastSyncedServerTimestamp(String collectionKey, String isoTimestamp) async {
    try {
      final box = Hive.box(syncMetaBox);
      await box.put('last_server_ts_$collectionKey', isoTimestamp);
      await box.flush();
    } catch (e) {
      debugPrint('[LocalStorageService] setLastSyncedServerTimestamp error: $e');
    }
  }

  static Future<void> logSyncConflict({
    required String collectionKey,
    required String docId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> cloudData,
  }) async {
    try {
      final box = Hive.box(syncMetaBox);
      final rawLogs = box.get('sync_conflicts_log', defaultValue: <dynamic>[]);
      final logs = List<Map<String, dynamic>>.from(
        (rawLogs as List).map((item) => Map<String, dynamic>.from(item as Map)),
      );

      logs.add({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'collection': collectionKey,
        'docId': docId,
        'localData': localData,
        'cloudData': cloudData,
      });

      if (logs.length > 100) {
        logs.removeRange(0, logs.length - 100);
      }

      await box.put('sync_conflicts_log', logs);
      await box.flush();
      debugPrint('[LocalStorageService] Sync conflict logged for $collectionKey/$docId');
    } catch (e) {
      debugPrint('[LocalStorageService] logSyncConflict error: $e');
    }
  }

  static bool isSoftDeleted(Map<String, dynamic> record) {
    return record['isDeleted'] == true;
  }
}