// lib/services/hourly_dispensary_sync.dart
//
// Hourly upload of dispensary stock changes.
//
// Tokens, prescriptions and dispense statuses still upload as they happen: HQ watches the
// live queue, and a PC can fail in the middle of a session. Stock is different. Every
// dispensed medicine used to be its own Firestore write (a 6-medicine prescription = 6
// writes), which was about two thirds of a clinic's daily writes. Stock changes now wait in
// the sync queue for up to an hour and are then added up per medicine, so a medicine given
// to 40 patients in that hour costs one write instead of 40.
//
// Nothing here blocks the UI: the queue is read in slices with pauses in between, and the
// upload itself is the normal SyncService pass.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'camp_session_service.dart';
import 'local_storage_service.dart';
import 'sync_service.dart';

class HourlyDispensarySync {
  HourlyDispensarySync._();

  static const Duration interval = Duration(hours: 1);

  /// A stock change is never held longer than this, even when the hourly run did not happen
  /// (app closed, Android background isolate): the uploader then sends it as it is.
  static const Duration maxHold = Duration(minutes: 70);

  static Timer? _timer;
  static Timer? _firstRun;
  static bool _running = false;
  static DateTime? lastRunAt;
  static int lastRunMerged = 0;

  /// Starts the hourly runs (idempotent). The first run comes shortly after start-up so
  /// changes held when the app last closed go out soon.
  static void start() {
    if (_timer != null) return;
    _firstRun = Timer(const Duration(minutes: 2), () => unawaited(runNow()));
    _timer = Timer.periodic(interval, (_) => unawaited(runNow()));
    debugPrint('[HourlyDispensarySync] started (every ${interval.inMinutes} min)');
  }

  static void stop() {
    _firstRun?.cancel();
    _timer?.cancel();
    _firstRun = null;
    _timer = null;
  }

  /// Whether the uploader should leave [item] in the queue for the next hourly run.
  static bool isHeld(dynamic item) {
    if (item is! Map) return false;
    if (item['type'] != 'update_inventory' || item['aggregated'] == true) return false;
    final created = DateTime.tryParse((item['createdAt'] ?? item['enqueuedAt'] ?? '').toString());
    if (created == null) return false;
    return DateTime.now().difference(created) < maxHold;
  }

  /// Adds up the queued stock changes per medicine and starts an upload pass.
  /// Returns how many queued changes were folded together.
  static Future<int> runNow() async {
    if (_running) return 0;
    _running = true;
    try {
      final merged = await _aggregateStockChanges();
      await _pruneClaims();
      lastRunAt = DateTime.now();
      lastRunMerged = merged;
      if (merged > 0) debugPrint('[HourlyDispensarySync] folded $merged stock change(s) for upload');
      unawaited(SyncService().triggerUpload(urgent: true));
      return merged;
    } catch (e) {
      debugPrint('[HourlyDispensarySync] run failed: $e');
      return 0;
    } finally {
      _running = false;
    }
  }

  /// Adds up the queued stock changes without starting an upload (for a pass already running).
  static Future<int> foldNow() async {
    if (_running) return 0;
    _running = true;
    try {
      return await _aggregateStockChanges();
    } catch (e) {
      debugPrint('[HourlyDispensarySync] fold failed: $e');
      return 0;
    } finally {
      _running = false;
    }
  }

  static Future<void> _breathe() => Future<void>.delayed(Duration.zero);

  static double _delta(Map v) {
    final raw = v['delta'] ?? (v['data'] is Map ? (v['data'] as Map)['delta'] : null);
    return raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  /// Identity of one queued stock change. Keys alone are reused (a later change for the same
  /// token and medicine gets the same key), so the creation time is part of it.
  static String _identity(dynamic key, Map v) => '$key|${v['createdAt'] ?? v['enqueuedAt'] ?? ''}';

  /// Changes that land on the same Firestore stock document, worked out the same way the
  /// uploader does (SyncService, 'update_inventory'); null when it cannot be worked out.
  static String? _targetDoc(Map v) {
    final data = v['data'] is Map ? v['data'] as Map : const {};
    final medicineId = (v['medicineId'] ?? v['inventoryId'] ?? data['medicineId'] ?? data['inventoryId'] ??
            data['id'] ?? data['docId'])
        ?.toString()
        .trim();
    if (medicineId == null || medicineId.isEmpty) return null;
    final branch = (v['branchId'] ?? data['branchId'] ?? '').toString().toLowerCase().trim();
    if (branch.isEmpty) return null;
    final serialHint = medicineId.startsWith('hajicamp--')
        ? 'HAJI'
        : (medicineId.startsWith('saddar--') ? 'SADDAR' : (v['serial'] ?? data['serial'])?.toString());
    final path = CampSessionService.getCampInventoryPath(
      branchId: branch,
      campId: (v['campId'] ?? data['campId'] ?? data['dispensaryId'])?.toString(),
      dispensaryTag: (v['dispensaryTag'] ?? data['dispensaryTag'])?.toString(),
      serial: serialHint,
    );
    return '$branch|$path|$medicineId';
  }

  static Future<int> _aggregateStockChanges() async {
    if (!Hive.isBoxOpen(LocalStorageService.syncBox)) return 0;
    final box = Hive.box(LocalStorageService.syncBox);
    final keys = box.keys.toList();

    // Changes already folded into an aggregate whose sources were not deleted yet (the app
    // stopped between the two writes). Sending them again would change the stock twice.
    final alreadyFolded = <String>{};
    var scanned = 0;
    for (final k in keys) {
      if (++scanned % 300 == 0) await _breathe();
      final v = box.get(k);
      if (v is Map && v['type'] == 'update_inventory' && v['aggregated'] == true && v['mergedFrom'] is List) {
        alreadyFolded.addAll((v['mergedFrom'] as List).map((e) => e.toString()));
      }
    }

    final groups = <String, List<MapEntry<dynamic, Map>>>{};
    final leftovers = <dynamic>[];
    scanned = 0;
    for (final k in keys) {
      if (++scanned % 300 == 0) await _breathe();
      final v = box.get(k);
      if (v is! Map || v['type'] != 'update_inventory' || v['aggregated'] == true) continue;
      if (alreadyFolded.contains(_identity(k, v))) {
        leftovers.add(k);
        continue;
      }
      final target = _targetDoc(v);
      if (target == null) continue; // the uploader sends it unchanged once it is no longer held
      groups.putIfAbsent(target, () => []).add(MapEntry(k, v));
    }
    if (leftovers.isNotEmpty) await box.deleteAll(leftovers);

    var folded = 0;
    var done = 0;
    for (final group in groups.values) {
      if (++done % 25 == 0) await _breathe();
      final sum = group.fold<double>(0, (s, e) => s + _delta(e.value));
      final sourceKeys = [for (final e in group) e.key];
      if (sum == 0) {
        await box.deleteAll(sourceKeys); // changes cancel out: nothing to write
        folded += group.length;
        continue;
      }
      final first = Map<String, dynamic>.from(group.first.value);
      final firstData = first['data'] is Map ? Map<String, dynamic>.from(first['data'] as Map) : <String, dynamic>{};
      final now = DateTime.now().toIso8601String();
      final medicineId = (first['medicineId'] ?? firstData['medicineId'] ?? firstData['id'] ?? 'med').toString();
      final branch = (first['branchId'] ?? firstData['branchId'] ?? '').toString().toLowerCase().trim();
      final aggregate = <String, dynamic>{
        ...first,
        'medicineId': medicineId,
        'delta': sum,
        'data': {...firstData, 'medicineId': medicineId, 'delta': sum, 'aggregatedCount': group.length},
        'aggregated': true,
        'mergedFrom': [for (final e in group) _identity(e.key, e.value)],
        'txId': const Uuid().v4(),
        'createdAt': now,
        'enqueuedAt': now,
        'attempts': 0,
        'status': 'pending',
      }
        ..remove('nextRetryAt')
        ..remove('lastError')
        ..remove('lastAttempt');
      final aggKey = 'sync_inv_agg_${branch}_${medicineId.toLowerCase()}_${DateTime.now().microsecondsSinceEpoch}';
      await box.put(aggKey, aggregate);
      await box.deleteAll(sourceKeys);
      folded += group.length;
    }
    return folded;
  }

  // ── Once-only stock deductions on the LAN server ──────────────────────────────
  static const String _claimsBox = 'app_flags';
  static const String _claimPrefix = 'stock_claim|';

  /// Records that the stock change queued under [lineKey] (one dispensed line of one token)
  /// has been queued. Returns false if it already was, so a re-sent or replayed dispense
  /// does not change the stock a second time.
  static bool claimStockDeduction(String lineKey) {
    try {
      if (!Hive.isBoxOpen(_claimsBox)) return true; // cannot remember: keep the old behaviour
      final box = Hive.box(_claimsBox);
      final k = '$_claimPrefix$lineKey';
      if (box.containsKey(k)) return false;
      box.put(k, DateTime.now().toIso8601String());
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Claims older than a few days are dropped; a dispense is not replayed that late.
  static Future<void> _pruneClaims() async {
    if (!Hive.isBoxOpen(_claimsBox)) return;
    final box = Hive.box(_claimsBox);
    final cutoff = DateTime.now().subtract(const Duration(days: 4));
    final old = <dynamic>[];
    var scanned = 0;
    for (final k in box.keys.toList()) {
      if (++scanned % 300 == 0) await _breathe();
      if (k is! String || !k.startsWith(_claimPrefix)) continue;
      final at = DateTime.tryParse(box.get(k)?.toString() ?? '');
      if (at == null || at.isBefore(cutoff)) old.add(k);
    }
    if (old.isNotEmpty) await box.deleteAll(old);
  }

  /// Sum of the stock changes still waiting in the queue, per medicine id. A stock download
  /// from the cloud does not include them yet, so it must take them off again or local stock
  /// would jump back up until the next hourly upload.
  static Map<String, double> pendingStockChanges() {
    final out = <String, double>{};
    try {
      if (!Hive.isBoxOpen(LocalStorageService.syncBox)) return out;
      final box = Hive.box(LocalStorageService.syncBox);
      for (final v in box.values) {
        if (v is! Map || v['type'] != 'update_inventory') continue;
        final data = v['data'] is Map ? v['data'] as Map : const {};
        final id = (v['medicineId'] ?? v['inventoryId'] ?? data['medicineId'] ?? data['inventoryId'] ?? data['id'])
            ?.toString()
            .trim();
        if (id == null || id.isEmpty) continue;
        out[id] = (out[id] ?? 0) + _delta(v);
      }
    } catch (_) {}
    return out;
  }
}
