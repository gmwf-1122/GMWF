// lib/services/submission_service.dart

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'donations_local_storage.dart';
import 'local_storage_service.dart';

// ── Status constants ────────────────────────────────────────────────────────
const String kSubPending  = 'pending';
const String kSubApproved = 'approved';
const String kSubReturned = 'returned';

// ── Pool summary value object ───────────────────────────────────────────────
class SubmitPoolSummary {
  final int    total;
  final int    ownCount;
  final int    forwardedCount;
  final double cashTotal;
  final List<Map<String, dynamic>> donations;

  const SubmitPoolSummary({
    required this.total,
    required this.ownCount,
    required this.forwardedCount,
    required this.cashTotal,
    required this.donations,
  });

  bool get isEmpty      => total == 0;
  bool get hasForwarded => forwardedCount > 0;

  String get label {
    if (isEmpty) return '0 records';
    final base = '$total record${total != 1 ? "s" : ""}';
    if (!hasForwarded) return base;
    return '$base ($ownCount own · $forwardedCount from staff)';
  }
}

// ── Service ─────────────────────────────────────────────────────────────────
class SubmissionService {
  static const String _boxName = 'local_submissions';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    debugPrint('[SubmissionService] ready');
  }

  static Box get _box => Hive.box(_boxName);

  // ══════════════════════════════════════════════════════════════════════════
  // READ — pool helpers
  // ══════════════════════════════════════════════════════════════════════════

  static List<Map<String, dynamic>> getUnsubmittedPool({
    required String branchId,
    required String userId,
    required String role,   // 'Office Boy' | 'Manager'
  }) {
    // FIX: DonationsLocalStorage.getDonationsList() — not LocalStorageService
    final all = DonationsLocalStorage.getDonationsList(branchId);
    return all.where((d) {
      if (d['submitted'] == true) return false;
      if (role == 'Manager') {
        return d['collectorId'] == userId || d['forwardedBy'] == userId;
      }
      return d['collectorId'] == userId;
    }).toList();
  }

  static SubmitPoolSummary getPoolSummary({
    required String branchId,
    required String userId,
    required String role,
  }) {
    final pool     = getUnsubmittedPool(branchId: branchId, userId: userId, role: role);
    final ownCount = pool.where((d) => d['forwardedBy'] != userId).length;
    final fwdCount = pool.where((d) => d['forwardedBy'] == userId).length;
    final cash     = pool
        .where((d) => d['amount'] != null)
        .fold<double>(0.0, (s, d) => s + ((d['amount'] as num?)?.toDouble() ?? 0.0));
    return SubmitPoolSummary(
      total:          pool.length,
      ownCount:       ownCount,
      forwardedCount: fwdCount,
      cashTotal:      cash,
      donations:      pool,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // READ — inbox
  // ══════════════════════════════════════════════════════════════════════════

  static List<Map<String, dynamic>> getInboxFor({
    required String toUserId,
    String? statusFilter,
  }) {
    var items = _box.keys
        .where((k) => _box.get(k) != null)
        .map((k) => Map<String, dynamic>.from(_box.get(k) as Map))
        .where((s) => s['toUserId'] == toUserId)
        .toList();

    if (statusFilter != null && statusFilter != 'all') {
      items = items.where((s) => s['status'] == statusFilter).toList();
    }
    items.sort((a, b) => ((b['timestamp'] as String?) ?? '')
        .compareTo((a['timestamp'] as String?) ?? ''));
    return items;
  }

  static List<Map<String, dynamic>> getSentBy(String fromUserId) {
    var items = _box.keys
        .where((k) => _box.get(k) != null)
        .map((k) => Map<String, dynamic>.from(_box.get(k) as Map))
        .where((s) => s['fromUserId'] == fromUserId)
        .toList();
    items.sort((a, b) => ((b['timestamp'] as String?) ?? '')
        .compareTo((a['timestamp'] as String?) ?? ''));
    return items;
  }

  static Stream<List<Map<String, dynamic>>> streamInboxFor({
    required String toUserId,
    String? statusFilter,
  }) async* {
    yield getInboxFor(toUserId: toUserId, statusFilter: statusFilter);
    await for (final _ in _box.watch()) {
      yield getInboxFor(toUserId: toUserId, statusFilter: statusFilter);
    }
  }

  static Stream<int> streamPendingCount(String toUserId) async* {
    int count() =>
        getInboxFor(toUserId: toUserId, statusFilter: kSubPending).length;
    yield count();
    await for (final _ in _box.watch()) {
      yield count();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WRITE — submit to superior
  // ══════════════════════════════════════════════════════════════════════════

  static Future<String?> submitToSuperior({
    required String branchId,
    required String fromUserId,
    required String fromUsername,
    required String fromRole,
    required String toUserId,
    required String toUsername,
    required String toRole,
    required List<Map<String, dynamic>> pool,
  }) async {
    if (pool.isEmpty) return null;

    final id      = 'sub_${DateTime.now().millisecondsSinceEpoch}';
    final donKeys = pool
        .map((d) => (d['hiveKey'] as String?) ?? (d['id'] as String?) ?? '')
        .where((k) => k.isNotEmpty)
        .toList();

    final cashTotal = pool
        .where((d) => d['amount'] != null)
        .fold<double>(0.0, (s, d) => s + ((d['amount'] as num?)?.toDouble() ?? 0.0));

    final fwdDons = pool.where((d) => d['forwardedBy'] == fromUserId).toList();
    final ownDons = pool.where((d) => d['forwardedBy'] != fromUserId).toList();

    final submission = <String, dynamic>{
      'id':                id,
      'hiveKey':           id,
      'branchId':          branchId,
      'fromUserId':        fromUserId,
      'fromUsername':      fromUsername,
      'fromRole':          fromRole,
      'toUserId':          toUserId,
      'toUsername':        toUsername,
      'toRole':            toRole,
      'donationHiveKeys':  donKeys,
      'count':             pool.length,
      'cashTotal':         cashTotal,
      'includesForwarded': fwdDons.isNotEmpty,
      'forwardedCount':    fwdDons.length,
      'ownCount':          ownDons.length,
      'status':            kSubPending,
      'date':              DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'timestamp':         DateTime.now().toIso8601String(),
      'acknowledgedAt':    null,
      'acknowledgedBy':    null,
      'returnReason':      null,
      'syncStatus':        'pending',
      'firestoreId':       null,
    };

    await _box.put(id, submission);

    // Mark donations as submitted.
    // FIX: Use DonationsLocalStorage.donationsBox — not LocalStorageService.donationsBox
    final donBox = Hive.box(DonationsLocalStorage.donationsBox);
    for (final key in donKeys) {
      final raw = donBox.get(key);
      if (raw == null) continue;
      final updated = Map<String, dynamic>.from(raw as Map)
        ..['submitted']    = true
        ..['submissionId'] = id;
      await donBox.put(key, updated);
    }

    await LocalStorageService.enqueueSync({
      'type':     'save_submission',
      'branchId': branchId,
      'hiveKey':  id,
      'data':     submission,
    });

    debugPrint('[SubmissionService] Created $id | ${pool.length} donations '
        '(${ownDons.length} own, ${fwdDons.length} fwd) | $fromRole→$toRole | PKR $cashTotal');
    return id;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WRITE — acknowledge
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> acknowledgeSubmission({
    required String submissionKey,
    required String actorUserId,
    required String actorUsername,
    required String actorRole,
    required String branchId,
  }) async {
    final raw = _box.get(submissionKey);
    if (raw == null) {
      debugPrint('[SubmissionService] acknowledgeSubmission: not found → $submissionKey');
      return;
    }
    final sub = Map<String, dynamic>.from(raw as Map);
    final now = DateTime.now().toIso8601String();

    sub['status']         = kSubApproved;
    sub['acknowledgedAt'] = now;
    sub['acknowledgedBy'] = actorUsername;
    await _box.put(submissionKey, sub);

    if (actorRole == 'Manager') {
      final keys = List<String>.from(
          (sub['donationHiveKeys'] as List? ?? []).map((e) => e.toString()));
      // FIX: DonationsLocalStorage.donationsBox — not LocalStorageService.donationsBox
      final donBox = Hive.box(DonationsLocalStorage.donationsBox);
      for (final key in keys) {
        final donRaw = donBox.get(key);
        if (donRaw == null) continue;
        final updated = Map<String, dynamic>.from(donRaw as Map)
          ..['submitted']       = false
          ..['submissionId']    = null
          ..['forwardedBy']     = actorUserId
          ..['forwardedByName'] = actorUsername;
        await donBox.put(key, updated);
      }
      debugPrint('[SubmissionService] Re-pooled ${keys.length} donations under $actorUsername');
    }

    await LocalStorageService.enqueueSync({
      'type':           'update_submission_status',
      'branchId':       branchId,
      'hiveKey':        submissionKey,
      'firestoreId':    sub['firestoreId'],
      'status':         kSubApproved,
      'acknowledgedBy': actorUsername,
      'acknowledgedAt': now,
    });

    debugPrint('[SubmissionService] Acknowledged $submissionKey by $actorUsername ($actorRole)');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WRITE — return
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> returnSubmission({
    required String submissionKey,
    required String actorUsername,
    required String branchId,
    String reason = '',
  }) async {
    final raw = _box.get(submissionKey);
    if (raw == null) return;

    final sub = Map<String, dynamic>.from(raw as Map);
    final now = DateTime.now().toIso8601String();

    sub['status']         = kSubReturned;
    sub['acknowledgedAt'] = now;
    sub['acknowledgedBy'] = actorUsername;
    sub['returnReason']   = reason;
    await _box.put(submissionKey, sub);

    final keys = List<String>.from(
        (sub['donationHiveKeys'] as List? ?? []).map((e) => e.toString()));
    // FIX: DonationsLocalStorage.donationsBox
    final donBox = Hive.box(DonationsLocalStorage.donationsBox);
    for (final key in keys) {
      final donRaw = donBox.get(key);
      if (donRaw == null) continue;
      final updated = Map<String, dynamic>.from(donRaw as Map)
        ..['submitted']    = false
        ..['submissionId'] = null;
      await donBox.put(key, updated);
    }

    await LocalStorageService.enqueueSync({
      'type':           'update_submission_status',
      'branchId':       branchId,
      'hiveKey':        submissionKey,
      'firestoreId':    sub['firestoreId'],
      'status':         kSubReturned,
      'acknowledgedBy': actorUsername,
      'returnReason':   reason,
      'acknowledgedAt': now,
    });

    debugPrint('[SubmissionService] Returned $submissionKey by $actorUsername | $reason');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SYNC helpers
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> markSynced(String hiveKey, String firestoreId) async {
    final raw = _box.get(hiveKey);
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..['firestoreId'] = firestoreId
      ..['syncStatus']  = 'synced';
    await _box.put(hiveKey, updated);
  }
}