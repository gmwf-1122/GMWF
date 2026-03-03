// lib/services/donations_local_storage.dart
//
// Offline-first storage for donations and credit ledger entries.
// Follows the exact same pattern as LocalStorageService:
//   1. Write to Hive immediately (UI never waits)
//   2. Enqueue via LocalStorageService.enqueueSync()
//   3. SyncService picks it up and uploads to Firestore
//   4. After upload, firestoreId is back-filled into Hive
//
// Box names  (opened alongside LocalStorageService.init):
//   'local_donations'      → donation records
//   'local_credit_ledger'  → OB→Manager and Manager→Chairman credit entries
//
// Key formats:
//   donations     → '{branchId}_{date}_{localId}'
//   creditLedger  → '{branchId}_credit_{localId}'
//
// SyncService action types added:
//   'save_donation'        → upsert to branches/{b}/donations/{stableId}
//   'update_donation'      → targeted .update() on a known Firestore doc
//   'save_credit_entry'    → upsert to branches/{b}/creditLedger/{stableId}
//   'update_credit_status' → targeted .update() on a known credit doc

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'local_storage_service.dart';

class DonationsLocalStorage {
  // ── Box names ──────────────────────────────────────────────────────────────
  static const String donationsBox    = 'local_donations';
  static const String creditLedgerBox = 'local_credit_ledger';

  // ── Init: call once in main() alongside LocalStorageService.init() ─────────
  static Future<void> init() async {
    await Future.wait([
      Hive.openBox(donationsBox),
      Hive.openBox(creditLedgerBox),
    ]);
    debugPrint('[DonationsLocalStorage] Boxes opened.');
  }

  // ── Key helpers ────────────────────────────────────────────────────────────

  static String _donationKey(String branchId, String date, String localId) =>
      '${branchId}_${date}_$localId';

  static String _creditKey(String branchId, String localId) =>
      '${branchId}_credit_$localId';

  static String _newLocalId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ═══════════════════════════════════════════════════════════════════════════
  // DONATIONS
  // ═══════════════════════════════════════════════════════════════════════════

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

    final sanitized = LocalStorageService.sanitize(record);
    await Hive.box(donationsBox).put(key, sanitized);
    debugPrint('[DonationsLS] Donation saved locally → $key');

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
      debugPrint('[DonationsLS] updateDonationField: key not found → $hiveKey');
      return;
    }

    final updated = Map<String, dynamic>.from(raw as Map)
      ..addAll(LocalStorageService.sanitize(fields));
    await box.put(hiveKey, updated);
    debugPrint('[DonationsLS] Donation updated → $hiveKey | ${fields.keys.join(', ')}');

    final fsId = (raw as Map)['firestoreId']?.toString();
    if (fsId != null && fsId.isNotEmpty) {
      await LocalStorageService.enqueueSync({
        'type':        'update_donation',
        'branchId':    branchId,
        'firestoreId': fsId,
        'fields':      LocalStorageService.sanitize(fields),
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
    debugPrint('[DonationsLS] Donation synced → $hiveKey → fs:$firestoreId');
  }

  // ── Local reads ────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> getDonationsForDate(
      String branchId, String date) {
    final prefix = '${branchId}_${date}_';
    final box    = Hive.box(donationsBox);
    return box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList()
      ..sort((a, b) {
        final at = (a['tokenNumber'] as int?) ?? 0;
        final bt = (b['tokenNumber'] as int?) ?? 0;
        return bt.compareTo(at);
      });
  }

  static List<Map<String, dynamic>> getApprovedUnsubmitted(
      String branchId, String date, String categoryId) {
    return getDonationsForDate(branchId, date).where((d) {
      return d['categoryId'] == categoryId &&
          d['status'] == 'approved' &&
          (d['submittedToManager'] != true);
    }).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamDonationsForDate(
      String branchId, String date) async* {
    yield getDonationsForDate(branchId, date);
    await for (final _ in Hive.box(donationsBox).watch()) {
      yield getDonationsForDate(branchId, date);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CREDIT LEDGER
  // ═══════════════════════════════════════════════════════════════════════════

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

    final sanitized = LocalStorageService.sanitize(record);
    await Hive.box(creditLedgerBox).put(key, sanitized);

    debugPrint('[DonationsLS] Credit entry saved → $key | '
        '${data['fromRole']} → ${data['toRole']} | PKR ${data['amount']}');

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
  }) async {
    final box = Hive.box(creditLedgerBox);
    final raw = box.get(hiveKey);
    if (raw == null) {
      debugPrint('[DonationsLS] updateCreditStatus: key not found → $hiveKey');
      return;
    }

    final fields = {
      'status':     status,
      'approvedBy': approvedBy,
      'approvedAt': DateTime.now().toIso8601String(),
    };

    final updated = Map<String, dynamic>.from(raw as Map)..addAll(fields);
    await box.put(hiveKey, updated);
    debugPrint('[DonationsLS] Credit status updated → $hiveKey → $status');

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
    debugPrint('[DonationsLS] Credit synced → $hiveKey → fs:$firestoreId');
  }

  // ── Local reads ────────────────────────────────────────────────────────────

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

    if (toRole != null) list = list.where((e) => e['toRole'] == toRole).toList();
    if (fromUserId != null) list = list.where((e) => e['fromUserId'] == fromUserId).toList();
    if (status != null) list = list.where((e) => e['status'] == status).toList();
    if (date != null) list = list.where((e) => e['date'] == date).toList();
    if (forwardedToChairman != null) {
      list = list.where((e) =>
          (e['forwardedToChairman'] as bool? ?? false) == forwardedToChairman).toList();
    }

    list.sort((a, b) {
      final at = (a['timestamp'] as String?) ?? '';
      final bt = (b['timestamp'] as String?) ?? '';
      return bt.compareTo(at);
    });

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
      status: status, date: date, forwardedToChairman: forwardedToChairman,
    );
    await for (final _ in Hive.box(creditLedgerBox).watch()) {
      yield getCreditEntries(
        branchId: branchId, toRole: toRole, fromUserId: fromUserId,
        status: status, date: date, forwardedToChairman: forwardedToChairman,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIRESTORE → HIVE  (called by SyncService post-upload refresh)
  // ═══════════════════════════════════════════════════════════════════════════

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
        final d       = doc.data();
        final date    = (d['date'] as String?) ?? today;
        final localId = (d['localId'] as String?) ?? doc.id;
        final key     = _donationKey(branchId, date, localId);

        final existing = box.get(key);
        if (existing == null) {
          await box.put(key, LocalStorageService.sanitize({
            ...d,
            'firestoreId': doc.id,
            'localId':     localId,
            'hiveKey':     key,
            'syncStatus':  'synced',
          }));
        } else {
          final ex = Map<String, dynamic>.from(existing as Map);
          if (ex['firestoreId'] == null && ex['syncStatus'] != 'pending') {
            ex['firestoreId'] = doc.id;
            ex['syncStatus']  = 'synced';
            await box.put(key, ex);
          }
        }
      }
      debugPrint('[DonationsLS] Downloaded ${snap.docs.length} donations for $today');
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
          await box.put(key, LocalStorageService.sanitize({
            ...d,
            'firestoreId': doc.id,
            'localId':     localId,
            'hiveKey':     key,
            'syncStatus':  'synced',
          }));
        } else {
          final ex = Map<String, dynamic>.from(existing as Map);
          if (ex['firestoreId'] == null && ex['syncStatus'] != 'pending') {
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

  // ── Cleanup ────────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    await Hive.box(donationsBox).clear();
    await Hive.box(creditLedgerBox).clear();
    debugPrint('[DonationsLS] All donation & credit data cleared.');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RECEIPT SEQUENCE  (Firestore transaction — unique across all devices)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the next sequential integer for a receipt number.
  /// Uses a Firestore transaction to guarantee uniqueness even under
  /// concurrent saves from multiple devices on the same branch+date.
  ///
  /// Counter document:
  ///   branches/{branchId}/donations/credit_ledger/receipt_seq/{dateKey}
  /// Field: `seq`  (starts at 1, incremented atomically)
  static Future<int> nextReceiptSeq({
    required String branchId,
    required String dateKey,   // e.g. '030326'  (ddMMyy)
  }) async {
    final seqRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('donations')
        .doc('credit_ledger')
        .collection('receipt_seq')
        .doc(dateKey);

    int next = 1;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(seqRef);
      if (snap.exists) {
        next = ((snap.data()?['seq'] as int?) ?? 0) + 1;
      } else {
        next = 1;
      }
      tx.set(seqRef, {'seq': next}, SetOptions(merge: true));
    });
    return next;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ATOMIC BATCH — approve OB entry + create Chairman entry in one commit
  // ═══════════════════════════════════════════════════════════════════════════

  /// Atomically:
  ///   1. Updates the OB→Manager credit entry [updateKey] to [updateStatus]
  ///   2. Creates a new Manager→Chairman credit entry [newEntry]
  ///
  /// [updateKey] is the Firestore doc ID stored in the entry's `hiveKey` /
  /// `firestoreId` field. Both writes commit together — no partial-write
  /// corruption. Local Hive boxes are also updated for offline consistency.
  static Future<void> batchCreditOps({
    required String branchId,
    required String updateKey,      // Firestore doc ID (== hiveKey) of OB entry
    required String updateStatus,   // e.g. 'approved'
    required String approvedBy,
    required Map<String, dynamic> newEntry,
  }) async {
    final db    = FirebaseFirestore.instance;
    final batch = db.batch();

    // 1 — update existing OB→Manager entry in Firestore
    final obRef = db
        .collection('branches')
        .doc(branchId)
        .collection('creditLedger')
        .doc(updateKey);

    batch.update(obRef, {
      'status':     updateStatus,
      'approvedBy': approvedBy,
      'approvedAt': FieldValue.serverTimestamp(),
    });

    // 2 — create new Manager→Chairman entry in Firestore
    final chairmanRef = db
        .collection('branches')
        .doc(branchId)
        .collection('creditLedger')
        .doc();   // auto-ID

    batch.set(chairmanRef, {
      ...newEntry,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Commit both writes atomically
    await batch.commit();

    // Mirror into local Hive so offline reads stay consistent
    await updateCreditStatus(
      updateKey,
      status:     updateStatus,
      approvedBy: approvedBy,
      branchId:   branchId,
    );
    await saveCreditEntry(branchId: branchId, data: newEntry);
  }
}