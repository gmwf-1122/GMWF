// lib/services/finance_expenses_storage.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'local_storage_service.dart';

class FinanceExpensesStorage {
  static const Uuid _uuid = Uuid();

  // ── Box Accessors ─────────────────────────────────────────────────────────
  static Box get expensesBox => Hive.box(LocalStorageService.expensesBox);
  static Box get settingsBox => Hive.box(LocalStorageService.financeSettingsBox);

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
    debugPrint('[ExpensesStorage] _sanitize WARNING: dropping ${v.runtimeType} for value $v');
    return null;
  }

  static String _newLocalId() => _uuid.v4();
  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  // ── Quota-Guard: TTL-based refresh throttle ────────────────────────────────
  static bool _shouldRefresh(String branchId, {Duration ttl = const Duration(minutes: 5)}) {
    try {
      final key = 'expenses_$branchId';
      final raw = settingsBox.get('__sync_ts_$key') as String?;
      if (raw == null) return true;
      final last = DateTime.tryParse(raw);
      if (last == null) return true;
      return DateTime.now().difference(last) > ttl;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _markRefreshed(String branchId) async {
    try {
      final key = 'expenses_$branchId';
      await settingsBox.put('__sync_ts_$key', DateTime.now().toUtc().toIso8601String());
    } catch (_) {}
  }

  // ── CRUD Operations ────────────────────────────────────────────────────────

  static Future<void> saveExpense({
    required String branchId,
    required double amount,
    required String category,
    String? customCategory,
    required String description,
    required String performedBy,
    required String performedByName,
    DateTime? date,
  }) async {
    final transactionDate = date ?? DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(transactionDate);

    // Month Lock Check
    final monthKey = DateFormat('yyyy-MM').format(transactionDate);
    final isLocked = settingsBox.get('month_lock_$monthKey') == true;
    if (isLocked) {
      throw Exception('Expenses cannot be recorded in a closed and locked month: $monthKey');
    }

    final id = _newLocalId();
    final now = _nowIso();

    final expenseMap = {
      'id': id,
      'branchId': branchId,
      'amount': amount,
      'amountMinor': (amount * 100).round(),
      'currency': 'PKR',
      'periodLocked': false,
      'eventVersion': 1,
      'correctsId': null,
      'category': category,
      'customCategory': customCategory,
      'description': description,
      'date': transactionDate.toIso8601String(),
      'dateKey': dateKey,
      'performedBy': performedBy,
      'performedByName': performedByName,
      'createdAt': now,
      'updatedAt': now,
      'lastModifiedBy': performedBy,
      'isVoided': false,
      'syncStatus': 'pending',
    };

    final sanitized = _sanitize(expenseMap);
    await expensesBox.put(id, sanitized);

    // Enqueue for background upload
    await LocalStorageService.enqueueSync({
      'type': 'save_expense',
      'branchId': branchId,
      'expenseId': id,
      'data': sanitized,
      'createdAt': now,
    });

    debugPrint('[ExpensesStorage] Expense saved locally & sync enqueued: $id');
  }

  static Future<void> voidExpense({
    required String branchId,
    required String expenseId,
    required String voidedBy,
    required String voidReason,
  }) async {
    final localRecord = expensesBox.get(expenseId);
    if (localRecord == null || localRecord is! Map) {
      throw Exception('Expense record not found locally: $expenseId');
    }

    final dateStr = localRecord['date']?.toString() ?? '';
    if (dateStr.isNotEmpty) {
      final monthKey = dateStr.substring(0, 7);
      final isLocked = settingsBox.get('month_lock_$monthKey') == true;
      if (isLocked) {
        throw Exception('Expenses in a closed and locked month ($monthKey) cannot be voided.');
      }
    }

    final updatedMap = Map<String, dynamic>.from(localRecord)
      ..['isVoided'] = true
      ..['voidedBy'] = voidedBy
      ..['voidedAt'] = _nowIso()
      ..['voidReason'] = voidReason
      ..['updatedAt'] = _nowIso()
      ..['lastModifiedBy'] = voidedBy
      ..['syncStatus'] = 'pending';

    final sanitized = _sanitize(updatedMap);
    await expensesBox.put(expenseId, sanitized);

    // Enqueue for background void upload
    await LocalStorageService.enqueueSync({
      'type': 'void_expense',
      'branchId': branchId,
      'expenseId': expenseId,
      'data': sanitized,
      'createdAt': _nowIso(),
    });

    debugPrint('[ExpensesStorage] Expense voided locally & sync enqueued: $expenseId');
  }

  // ── Queries and Summaries ──────────────────────────────────────────────────

  static List<Map<String, dynamic>> getExpensesForDate(String branchId, String dateKey) {
    try {
      final list = expensesBox.values
          .where((v) {
            if (v is! Map) return false;
            final recordBranch = v['branchId']?.toString();
            final recordDateKey = v['dateKey']?.toString();
            
            // Filters based on branch context
            final branchMatch = (branchId == 'all' || recordBranch == branchId);
            final dateMatch = (recordDateKey == dateKey);
            
            return branchMatch && dateMatch;
          });

      // Sort by date ascending
      final sorted = list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
          final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
          return da.compareTo(db);
        });

      return sorted;
    } catch (e) {
      debugPrint('[ExpensesStorage] getExpensesForDate error: $e');
      return [];
    }
  }

  static List<Map<String, dynamic>> getExpensesForRange(String branchId, DateTime start, DateTime end) {
    try {
      final list = expensesBox.values
          .where((v) {
            if (v is! Map) return false;
            final recordBranch = v['branchId']?.toString();
            final dateStr = v['date']?.toString();
            if (dateStr == null) return false;
            
            final dt = DateTime.tryParse(dateStr);
            if (dt == null) return false;

            final branchMatch = (branchId == 'all' || recordBranch == branchId);
            final rangeMatch = dt.isAfter(start.subtract(const Duration(seconds: 1))) && 
                               dt.isBefore(end.add(const Duration(seconds: 1)));
            
            return branchMatch && rangeMatch;
          });

      final sorted = list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
          final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
          return da.compareTo(db);
        });

      return sorted;
    } catch (e) {
      debugPrint('[ExpensesStorage] getExpensesForRange error: $e');
      return [];
    }
  }

  static Map<String, double> getCategoryBreakdown(List<Map<String, dynamic>> expenses) {
    final breakdown = <String, double>{};
    for (final exp in expenses) {
      if (exp['isVoided'] == true) continue;
      
      final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
      var cat = exp['category']?.toString() ?? 'Other';
      if (cat == 'Other' && exp['customCategory'] != null && exp['customCategory'].toString().isNotEmpty) {
        cat = exp['customCategory'].toString();
      }

      breakdown[cat] = (breakdown[cat] ?? 0.0) + amt;
    }
    return breakdown;
  }

  // ── Sync Logic ─────────────────────────────────────────────────────────────

  static Future<void> mergeRemoteExpenses(String branchId, List<Map<String, dynamic>> remoteList) async {
    for (final remote in remoteList) {
      final id = remote['id']?.toString();
      if (id == null) continue;

      final local = expensesBox.get(id);
      if (local == null) {
        // Safe to put directly
        final record = Map<String, dynamic>.from(remote)..['syncStatus'] = 'synced';
        await expensesBox.put(id, _sanitize(record));
      } else if (local is Map) {
        final localSync = local['syncStatus']?.toString() ?? 'synced';
        final remoteUpdatedStr = remote['updatedAt']?.toString() ?? '';
        final localUpdatedStr = local['updatedAt']?.toString() ?? '';

        final remoteUpdated = DateTime.tryParse(remoteUpdatedStr) ?? DateTime(2000);
        final localUpdated = DateTime.tryParse(localUpdatedStr) ?? DateTime(2000);

        if (localSync == 'synced') {
          // If remote is newer, replace local
          if (remoteUpdated.isAfter(localUpdated)) {
            final record = Map<String, dynamic>.from(remote)..['syncStatus'] = 'synced';
            await expensesBox.put(id, _sanitize(record));
          }
        } else {
          // Local is pending upload. Apply Last-Write-Wins conflict resolution:
          // If remote is strictly newer than our local edit time, overwrite local.
          if (remoteUpdated.isAfter(localUpdated)) {
            final record = Map<String, dynamic>.from(remote)..['syncStatus'] = 'synced';
            await expensesBox.put(id, _sanitize(record));
          }
        }
      }
    }
  }

  static Future<void> downloadExpenses(String branchId, {bool force = false}) async {
    if (branchId == 'all' || branchId.isEmpty) return;

    if (!force && !_shouldRefresh(branchId)) {
      debugPrint('[ExpensesStorage] Skipping downloadExpenses for $branchId — cache is fresh');
      return;
    }

    try {
      debugPrint('[ExpensesStorage] Downloading expenses for $branchId...');
      
      // Sync window: rolling 60 days (current month + previous month)
      final cutoffDate = DateTime.now().subtract(const Duration(days: 60));
      
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('expenses')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate))
          .get();

      final remoteList = snap.docs.map((doc) {
        final data = doc.data();
        // Ensure date fields are correctly formatted
        if (data['date'] is Timestamp) {
          data['date'] = (data['date'] as Timestamp).toDate().toIso8601String();
        }
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
        }
        if (data['updatedAt'] is Timestamp) {
          data['updatedAt'] = (data['updatedAt'] as Timestamp).toDate().toIso8601String();
        }
        if (data['voidedAt'] is Timestamp) {
          data['voidedAt'] = (data['voidedAt'] as Timestamp).toDate().toIso8601String();
        }
        return data;
      }).toList();

      await mergeRemoteExpenses(branchId, remoteList);
      await _markRefreshed(branchId);
      debugPrint('[ExpensesStorage] Successfully synced ${remoteList.length} expenses for $branchId');
    } catch (e) {
      debugPrint('[ExpensesStorage] downloadExpenses error: $e');
    }
  }
}
