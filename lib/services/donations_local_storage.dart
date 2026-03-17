// lib/services/donations_local_storage.dart
//
// FIXES vs previous revision:
//   1. init() now also opens 'sync_queue' and 'app_settings' boxes.
//      enqueueSync() (called on every save) uses Hive.box('sync_queue') and
//      nextReceiptNumber() uses Hive.box('app_settings') for the offline
//      fallback counter. If either box isn't open when saveDonation() is
//      called, Hive throws HiveError which is an Error (not Exception) and
//      escapes the try/catch in _submit(), killing the whole app.
//
//   2. All other logic is identical to the previous revision.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'local_storage_service.dart';

class DonationsLocalStorage {
  // ── Box names (public — SubmissionService references donationsBox) ─────────
  static const String donationsBox    = 'local_donations';
  static const String creditLedgerBox = 'local_credit_ledger';

  // ══════════════════════════════════════════════════════════════════════════
  // INIT — call once in main() before runApp()
  //
  // FIX 1: Also opens 'sync_queue' and 'app_settings' which are accessed
  // by LocalStorageService.enqueueSync() and nextReceiptNumber() respectively.
  // Missing these caused HiveError → uncaught Error → app killed.
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> init() async {
    if (!Hive.isBoxOpen(donationsBox)) {
      await Hive.openBox(donationsBox);
    }
    if (!Hive.isBoxOpen(creditLedgerBox)) {
      await Hive.openBox(creditLedgerBox);
    }
    // FIX 1: required by LocalStorageService.enqueueSync()
    if (!Hive.isBoxOpen(LocalStorageService.syncBox)) {
      await Hive.openBox(LocalStorageService.syncBox);
    }
    // FIX 1: required by LocalStorageService.nextReceiptNumber() offline path
    if (!Hive.isBoxOpen('app_settings')) {
      await Hive.openBox('app_settings');
    }
    debugPrint('[DonationsLocalStorage] Boxes opened. Init sequence FINISHED.');
  }

  // ── Public box accessors ───────────────────────────────────────────────────
  static Box getBox()       => Hive.box(donationsBox);
  static Box getCreditBox() => Hive.box(creditLedgerBox);

  // ══════════════════════════════════════════════════════════════════════════
  // SANITIZE
  //
  // Hive only supports: String, int, double, bool, List, Map, null.
  // DateTime, Timestamp, FieldValue, GeoPoint all crash Hive on put().
  // This converts DateTime/Timestamp → ISO string and drops anything else
  // that isn't a primitive Dart type.
  // ══════════════════════════════════════════════════════════════════════════

  static Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) => out[k] = _val(v));
    return out;
  }

  static dynamic _val(dynamic v) {
    if (v == null)       return null;
    if (v is String)     return v;
    if (v is int)        return v;
    if (v is double)     return v;
    if (v is bool)       return v;
    if (v is DateTime)   return v.toIso8601String();
    if (v is Timestamp)  return v.toDate().toIso8601String();
    if (v is Map)        return _sanitize(Map<String, dynamic>.from(v));
    if (v is List)       return v.map(_val).toList();
    // FieldValue, GeoPoint, DocumentReference etc. — not storable in Hive.
    debugPrint('[DonationsLS] _sanitize WARNING: dropping ${v.runtimeType} for value $v');
    return null;
  }

  // ── Key helpers ────────────────────────────────────────────────────────────
  // FIX: Using double underscore to match LocalStorageService (consistent with other app modules)
  static String _donationKey(String branchId, String date, String localId) =>
      '${branchId}__${date}__$localId';

  static String _creditKey(String branchId, String localId) =>
      '${branchId}_credit_$localId';

  static String _newLocalId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ══════════════════════════════════════════════════════════════════════════
  // DONATIONS — write
  // ══════════════════════════════════════════════════════════════════════════

  static Future<String> saveDonation({
    required String branchId,
    required Map<String, dynamic> data,
  }) async {
    final localId = _newLocalId();
    final date    = (data['date'] as String?) ?? _today();
    final key     = _donationKey(branchId, date, localId);

    final record = Map<String, dynamic>.from(data);
    record['localId']     = localId;
    record['hiveKey']     = key;
    record['branchId']    = branchId;
    record['syncStatus']  = 'pending';
    record['firestoreId'] = null;
    record['submitted']   = false;
    final sanitized = _sanitize(record);

    debugPrint('[DonationsLS] Put record into Hive... key: $key');
    await Hive.box(donationsBox).put(key, sanitized);
    debugPrint('[DonationsLS] Saved → $key');

    debugPrint('[DonationsLS] Enqueuing sync...');
    await LocalStorageService.enqueueSync({
      'type':     'save_donation',
      'branchId': branchId,
      'localId':  localId,
      'hiveKey':  key,
      'data':     sanitized,
    });

    return key;
  }

  static Future<void> updateDonationField(
    String hiveKey,
    Map<String, dynamic> fields, {
    required String branchId,
  }) async {
    final box = Hive.box(donationsBox);
    final raw = box.get(hiveKey);
    if (raw == null) {
      debugPrint('[DonationsLS] updateDonationField: not found → $hiveKey');
      return;
    }
    final updated = Map<String, dynamic>.from(raw as Map)
      ..addAll(_sanitize(fields));
    await box.put(hiveKey, updated);
    debugPrint('[DonationsLS] Updated → $hiveKey');

    final fsId = (raw as Map)['firestoreId']?.toString();
    if (fsId != null && fsId.isNotEmpty) {
      await LocalStorageService.enqueueSync({
        'type':        'update_donation',
        'branchId':    branchId,
        'firestoreId': fsId,
        'fields':      _sanitize(fields),
      });
    } else {
      await LocalStorageService.enqueueSync({
        'type':     'save_donation',
        'branchId': branchId,
        'localId':  (updated['localId'] as String?) ?? hiveKey,
        'hiveKey':  hiveKey,
        'data':     updated,
      });
    }
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
    debugPrint('[DonationsLS] Synced → $hiveKey → $firestoreId');
  }

  static Future<void> deleteDonation(String hiveKey, String branchId) async {
    final box = Hive.box(donationsBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;
    final fsId = (raw as Map)['firestoreId']?.toString();
    await box.delete(hiveKey);
    if (fsId != null && fsId.isNotEmpty) {
      await LocalStorageService.enqueueSync({
        'type':        'delete_donation',
        'branchId':    branchId,
        'firestoreId': fsId,
      });
    }
    debugPrint('[DonationsLS] Deleted → $hiveKey');
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> getDonationsForDate(
      String branchId, String date) {
    // FIX: Match both single and double underscore for transition safety
    final box    = Hive.box(donationsBox);
    return box.keys
        .where((k) {
          final s = k.toString();
          return (s.startsWith('${branchId}_${date}_') || 
                  s.startsWith('${branchId}__${date}__')) &&
                 !s.contains('_credit_');
        })
        .map((k) {
          try {
            return Map<String, dynamic>.from(box.get(k) as Map);
          } catch (e) {
            debugPrint('[DonationsLS] Skipping corrupted record $k: $e');
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => ((b['timestamp'] as String?) ?? '')
          .compareTo((a['timestamp'] as String?) ?? ''));
  }

  /// All donations for branch, newest first. Credit keys excluded.
  static List<Map<String, dynamic>> getAllDonations(String branchId) {
    // FIX: Match both single and double underscore for transition safety
    final box    = Hive.box(donationsBox);
    return box.keys
        .where((k) {
          final s = k.toString();
          return s.startsWith('${branchId}_') && !s.contains('_credit_');
        })
        .map((k) {
          try {
            return Map<String, dynamic>.from(box.get(k) as Map);
          } catch (e) {
            debugPrint('[DonationsLS] Skipping corrupted record $k: $e');
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => ((b['timestamp'] as String?) ?? '')
          .compareTo((a['timestamp'] as String?) ?? ''));
  }

  /// Alias used by SubmissionService.getUnsubmittedPool().
  static List<Map<String, dynamic>> getDonationsList(String branchId) =>
      getAllDonations(branchId);

  // ── Streams ────────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamDonationsForDate(
      String branchId, String date) async* {
    yield getDonationsForDate(branchId, date);
    await for (final _ in Hive.box(donationsBox).watch()) {
      yield getDonationsForDate(branchId, date);
    }
  }

  static Stream<List<Map<String, dynamic>>> streamAllDonations(
      String branchId) async* {
    yield getAllDonations(branchId);
    await for (final _ in Hive.box(donationsBox).watch()) {
      yield getAllDonations(branchId);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CREDIT LEDGER — write
  // ══════════════════════════════════════════════════════════════════════════

  static Future<String> saveCreditEntry({
    required String branchId,
    required Map<String, dynamic> data,
  }) async {
    final localId = _newLocalId();
    final key     = _creditKey(branchId, localId);

    final record = Map<String, dynamic>.from(data);
    record['localId']     = localId;
    record['hiveKey']     = key;
    record['branchId']    = branchId;
    record['syncStatus']  = 'pending';
    record['firestoreId'] = null;

    final sanitized = _sanitize(record);
    await Hive.box(creditLedgerBox).put(key, sanitized);
    debugPrint('[DonationsLS] Credit saved → $key');

    await LocalStorageService.enqueueSync({
      'type':     'save_credit_entry',
      'branchId': branchId,
      'localId':  localId,
      'hiveKey':  key,
      'data':     sanitized,
    });

    return key;
  }

  static Future<void> updateCreditStatus(
    String hiveKey, {
    required String status,
    required String approvedBy,
    required String branchId,
    String? rejectionReason,
  }) async {
    final box = Hive.box(creditLedgerBox);
    final raw = box.get(hiveKey);
    if (raw == null) {
      debugPrint('[DonationsLS] updateCreditStatus: not found → $hiveKey');
      return;
    }
    final isApproval = status == 'approved';
    final fields = <String, dynamic>{
      'status':     status,
      if (isApproval)  'approvedBy': approvedBy,
      if (isApproval)  'approvedAt': DateTime.now().toIso8601String(),
      if (!isApproval) 'rejectedBy': approvedBy,
      if (!isApproval) 'rejectedAt': DateTime.now().toIso8601String(),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };

    final updated = Map<String, dynamic>.from(raw as Map)..addAll(fields);
    await box.put(hiveKey, updated);

    final fsId = (raw as Map)['firestoreId']?.toString();
    if (fsId != null && fsId.isNotEmpty) {
      await LocalStorageService.enqueueSync({
        'type':        'update_credit_status',
        'branchId':    branchId,
        'firestoreId': fsId,
        'fields':      fields,
      });
    } else {
      await LocalStorageService.enqueueSync({
        'type':     'save_credit_entry',
        'branchId': branchId,
        'localId':  (updated['localId'] as String?) ?? hiveKey,
        'hiveKey':  hiveKey,
        'data':     updated,
      });
    }
  }

  static Future<void> markCreditForwarded(
      String hiveKey, String branchId) async {
    final box = Hive.box(creditLedgerBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..['forwardedToChairman'] = true;
    await box.put(hiveKey, updated);
    final fsId = (raw as Map)['firestoreId']?.toString();
    if (fsId != null && fsId.isNotEmpty) {
      await LocalStorageService.enqueueSync({
        'type':        'update_credit_status',
        'branchId':    branchId,
        'firestoreId': fsId,
        'fields':      {'forwardedToChairman': true},
      });
    }
  }

  static Future<void> markCreditSynced(
      String hiveKey, String firestoreId) async {
    final box = Hive.box(creditLedgerBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..['firestoreId'] = firestoreId
      ..['syncStatus']  = 'synced';
    await box.put(hiveKey, updated);
    debugPrint('[DonationsLS] Credit synced → $hiveKey → $firestoreId');
  }

  // ── Credit reads ───────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> getCreditEntries({
    required String branchId,
    String? toRole,
    String? fromUserId,
    String? status,
    String? date,
    bool? forwardedToChairman,
  }) {
    final prefix = '${branchId}_credit_';
    final box    = Hive.box(creditLedgerBox);
    var list = box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();

    if (toRole != null)
      list = list.where((e) => e['toRole'] == toRole).toList();
    if (fromUserId != null)
      list = list.where((e) => e['fromUserId'] == fromUserId).toList();
    if (status != null)
      list = list.where((e) => e['status'] == status).toList();
    if (date != null)
      list = list.where((e) => e['date'] == date).toList();
    if (forwardedToChairman != null) {
      list = list
          .where((e) =>
              (e['forwardedToChairman'] as bool? ?? false) ==
              forwardedToChairman)
          .toList();
    }
    list.sort((a, b) => ((b['timestamp'] as String?) ?? '')
        .compareTo((a['timestamp'] as String?) ?? ''));
    return list;
  }

  static Stream<List<Map<String, dynamic>>> streamCreditEntries({
    required String branchId,
    String? toRole,
    String? fromUserId,
    String? status,
    String? date,
    bool? forwardedToChairman,
  }) async* {
    yield getCreditEntries(
      branchId: branchId, toRole: toRole, fromUserId: fromUserId,
      status: status, date: date,
      forwardedToChairman: forwardedToChairman,
    );
    await for (final _ in Hive.box(creditLedgerBox).watch()) {
      yield getCreditEntries(
        branchId: branchId, toRole: toRole, fromUserId: fromUserId,
        status: status, date: date,
        forwardedToChairman: forwardedToChairman,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIRESTORE → HIVE  (called by SyncService after upload)
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> downloadTodayDonations(String branchId) async {
    try {
      final today = _today();
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
          await box.put(key, _sanitize({
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
      debugPrint('[DonationsLS] Downloaded ${snap.docs.length} donations ($today)');
    } catch (e) {
      debugPrint('[DonationsLS] downloadTodayDonations error: $e');
    }
  }

  static Future<void> downloadCreditLedger(String branchId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('creditLedger')
          .get();

      final box = Hive.box(creditLedgerBox);
      for (final doc in snap.docs) {
        final d       = doc.data();
        final localId = (d['localId'] as String?) ?? doc.id;
        final key     = _creditKey(branchId, localId);

        final existing = box.get(key);
        if (existing == null) {
          await box.put(key, _sanitize({
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
      debugPrint('[DonationsLS] Downloaded ${snap.docs.length} credit entries');
    } catch (e) {
      debugPrint('[DonationsLS] downloadCreditLedger error: $e');
    }
  }

  static Future<void> clearAll() async {
    await Hive.box(donationsBox).clear();
    await Hive.box(creditLedgerBox).clear();
    debugPrint('[DonationsLS] Cleared all data.');
  }
}