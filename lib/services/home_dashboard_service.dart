// lib/services/home_dashboard_service.dart
//
// Data-layer helpers for the new "Home" snapshot dashboard.
// Adds yesterday-vs-today comparisons, time-series revenue series,
// and recent activity feed.
//
// Yesterday's data is historical/immutable, so — unlike the 5-minute TTL
// cache used for "today" — we cache it indefinitely per branch+date.

import 'dart:async';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/dashboard_widgets.dart';
import 'local_storage_service.dart';
import 'camp_session_service.dart';
import 'donations_local_storage.dart';
import '../pages/madrassa/utils/madrassa_local_storage.dart';

/// Indefinite cache for historical (non-today) BranchStats.
/// Keyed by "branchId|yyyy-MM-dd".
final Map<String, BranchStats> _historicalStatsCache = {};
final Map<String, _CachedLocalBranchStats> _localStatsTTLCache = {};

void clearLocalStatsCache() => _localStatsTTLCache.clear();

/// Computations already running, so a second caller (the dashboard's provider and its
/// initState ask for the same figures together) waits for that one instead of starting a
/// second scan of the same boxes.
final Map<String, Future<BranchStats>> _statsInFlight = {};

/// Hive boxes are held in memory and these scans run on the UI isolate. On Windows that is
/// also the window's own thread, so going through a whole history in one go makes Windows
/// mark the app "Not Responding". Long scans hand control back every [_scanSlice] records.
const int _scanSlice = 400;
Future<void> _breathe() => Future<void>.delayed(Duration.zero);

class _CachedLocalBranchStats {
  final BranchStats stats;
  final DateTime cachedAt;
  _CachedLocalBranchStats(this.stats) : cachedAt = DateTime.now();

  bool get isValid => DateTime.now().difference(cachedAt).inSeconds < 45;
}

String _dayKey(String branchId, DateTime day) =>
    '${branchId.toLowerCase().trim()}|${DateFormat('yyyy-MM-dd').format(day)}';

bool _isSameDate(dynamic rawDate, String ymd, String dmyy) {
  if (rawDate == null) return false;
  final str = rawDate.toString().trim();
  if (str.isEmpty) return false;
  if (str.startsWith(ymd) || str.contains(ymd) || str.startsWith(dmyy) || str.contains(dmyy)) return true;
  try {
    final dt = DateTime.tryParse(str);
    if (dt != null) {
      final formattedYmd = DateFormat('yyyy-MM-dd').format(dt);
      if (formattedYmd == ymd) return true;
      final formattedDmyy = DateFormat('ddMMyy').format(dt);
      if (formattedDmyy == dmyy) return true;
    }
  } catch (_) {}
  return false;
}

bool _isMatchingBranch(String docBranchId, String targetBranchId, [String serial = '']) {
  final b1 = docBranchId.toLowerCase().trim().replaceAll(' ', '_').replaceAll('-', '_');
  final b2 = targetBranchId.toLowerCase().trim().replaceAll(' ', '_').replaceAll('-', '_');
  if (b2 == 'all' || b2 == 'global') return true;

  final sUpper = serial.toUpperCase();

  // Karachi sub-camps and aliases
  if (b2 == 'karachi' || b2.contains('karachi') || b2.contains('saddar') || b2.contains('haji') || b2.contains('kapaya')) {
    if (b1.contains('karachi') || b1.contains('haji') || b1.contains('saddar') || b1.contains('kapaya') || b1.contains('kap')) return true;
    if (sUpper.contains('SADD') || sUpper.contains('HAJI') || sUpper.contains('KAP') || sUpper.contains('HC')) return true;
    if (b1.isEmpty) return b2 == 'karachi';
  }

  // Jalalpur Jattan aliases
  if (b2.contains('jalal') || b2 == 'jlj' || b2 == 'jpj') {
    if (b1.contains('jalal') || b1 == 'jlj' || b1 == 'jpj' || b1.contains('jattan')) return true;
    if (sUpper.contains('JLJ') || sUpper.contains('JPJ')) return true;
  }

  // Gujrat aliases
  if (b2.contains('gujrat') || b2 == 'grt' || b2 == 'gjt') {
    if (b1.contains('gujrat') || b1 == 'grt' || b1 == 'gjt') return true;
    if (sUpper.contains('GRT') || sUpper.contains('GJT')) return true;
  }

  // Sialkot aliases
  if (b2.contains('sialkot') || b2 == 'skt') {
    if (b1.contains('sialkot') || b1 == 'skt') return true;
    if (sUpper.contains('SKT')) return true;
  }

  // Rawalpindi aliases
  if (b2.contains('rawalpindi') || b2 == 'rwp' || b2.contains('pindi')) {
    if (b1.contains('rawalpindi') || b1 == 'rwp' || b1.contains('pindi')) return true;
    if (sUpper.contains('RWP')) return true;
  }

  if (b1.isEmpty) return false;
  if (b1 == b2) return true;
  if (b1.replaceAll('_', '') == b2.replaceAll('_', '')) return true;
  return b1.contains(b2) || b2.contains(b1);
}

/// Computes branch statistics from local Hive data (local_entries, local_donations, and historical branch cache).
/// Pure instantaneous local retrieval by default (0-2ms).
Future<BranchStats> fetchLocalBranchStats(String branchId, DateTime date, {bool allowRemoteFallback = false}) async {
  final bId = branchId.toLowerCase().trim();
  final dateKeyYmd = DateFormat('yyyy-MM-dd').format(date);
  // The local-only snapshot is built first; a cloud-combined request must not get it back.
  final cacheTTLKey = allowRemoteFallback ? '$bId|$dateKeyYmd|cloud' : '$bId|$dateKeyYmd';

  final now = DateTime.now();
  final isToday = (date.year == now.year && date.month == now.month && date.day == now.day);

  // Instant historical cache lookup (past dates are immutable)
  if (!isToday && _historicalStatsCache.containsKey(cacheTTLKey)) {
    return _historicalStatsCache[cacheTTLKey]!;
  }

  // Instant today cache lookup (valid for 45s)
  if ((isToday || allowRemoteFallback) && _localStatsTTLCache.containsKey(cacheTTLKey) && _localStatsTTLCache[cacheTTLKey]!.isValid) {
    return _localStatsTTLCache[cacheTTLKey]!.stats;
  }

  final running = _statsInFlight[cacheTTLKey];
  if (running != null) return running;
  final job = _computeLocalBranchStats(branchId, bId, date, isToday, cacheTTLKey, allowRemoteFallback);
  _statsInFlight[cacheTTLKey] = job;
  try {
    return await job;
  } finally {
    _statsInFlight.remove(cacheTTLKey);
  }
}

Future<BranchStats> _computeLocalBranchStats(String branchId, String bId, DateTime date, bool isToday,
    String cacheTTLKey, bool allowRemoteFallback) async {
  final dateKeyYmd = DateFormat('yyyy-MM-dd').format(date);
  final dateKeyDmyy = DateFormat('ddMMyy').format(date);
  var scanned = 0;

  // 1. Calculate donations from DonationsLocalStorage
  int donTotal = 0;
  try {
    if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
      final donBox = Hive.box(DonationsLocalStorage.donationsBox);
      for (final val in donBox.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (val is Map) {
          final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
          final d = val['date'] ?? val['createdAt'] ?? val['timestamp'];
          if (_isMatchingBranch(b, bId) && _isSameDate(d, dateKeyYmd, dateKeyDmyy)) {
            final status = val['status']?.toString().toLowerCase();
            final syncStatus = val['syncStatus']?.toString().toLowerCase();
            if (status == 'deleted' || syncStatus == 'deleted') continue;

            final payMethod = val['paymentMethod']?.toString().toLowerCase() ?? '';
            if (payMethod == 'bank_deposit') continue;

            final amt = val['amount'];
            final amtDouble = (amt is num) ? amt.toDouble() : (double.tryParse(amt?.toString() ?? '0') ?? 0.0);
            donTotal += amtDouble.toInt();
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Error fetching local donations: $e');
  }

  // 2. Calculate tokens & dispensary revenue (high-performance values scan)
  int z = 0, nz = 0, gm = 0, das = 0, served = 0, dispensed = 0, dispRev = 0;
  int zRev = 0, nzRev = 0, gmRev = 0;

  try {
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final box = Hive.box(LocalStorageService.entriesBox);
      final Map<String, Map> entryMap = {};

      for (final e in box.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (e is Map) {
          final status = e['status']?.toString().toLowerCase();
          final syncStatus = e['syncStatus']?.toString().toLowerCase();
          if (status == 'deleted' || syncStatus == 'deleted') continue;

          final b = (e['branchId'] as String? ?? '').toLowerCase().trim();
          final dk = e['dateKey']?.toString();
          final rawDate = e['dateKey'] ?? e['date'] ?? e['createdAt'] ?? e['timestamp'] ?? e['serial'];
          final rawSerial = (e['serial'] ?? e['id'] ?? e['tokenNumber'] ?? '').toString().trim().toLowerCase();
          if (_isMatchingBranch(b, bId, rawSerial) && (dk == dateKeyDmyy || _isSameDate(rawDate, dateKeyYmd, dateKeyDmyy))) {
            final parts = rawSerial.split('-');
            final sNum = parts.length > 1 ? parts.last : rawSerial;
            final canonicalKey = parts.length > 2
                ? '${parts[1]}-${parts[2]}'
                : (parts.length > 1 ? '${parts[0]}-${parts[1]}' : sNum);
            entryMap[canonicalKey] = e;
          }
        }
      }

      for (final val in entryMap.values) {
        final type = (val['queueType'] ?? val['category'] ?? val['type'] ?? '').toString().toLowerCase();
        final days = (val['daysOfMedicine'] as num?)?.toInt() ?? 1;
        final status = val['status']?.toString().toLowerCase();

        if (type.contains('non-zakat') || type.contains('nonzakat') || type.contains('non_zakat')) {
          nz++;
          final rev = 100 * days;
          dispRev += rev;
          nzRev += rev;
        } else if (type.contains('gmwf')) {
          gm++;
        } else if (type.contains('dasterkhwan')) {
          das++;
        } else {
          // Default to Zakat (standard dispensary token)
          z++;
          final rev = 20 * days;
          dispRev += rev;
          zRev += rev;
        }

        if (status == 'dispensed' || status == 'completed') {
          dispensed++;
        }
      }
    }
  } catch (e) {
    debugPrint('Error reading local entries: $e');
  }

  // 2b. Calculate food tokens from dasterkhwaan_tokens box
  try {
    if (!Hive.isBoxOpen(LocalStorageService.dasterkhwaanTokensBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.dasterkhwaanTokensBox);
    }
    if (Hive.isBoxOpen(LocalStorageService.dasterkhwaanTokensBox)) {
      final tokenBox = Hive.box(LocalStorageService.dasterkhwaanTokensBox);
      for (final t in tokenBox.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (t is! Map) continue;
        final status = t['status']?.toString().toLowerCase();
        final syncStatus = t['syncStatus']?.toString().toLowerCase();
        if (status == 'deleted' || status == 'void' || syncStatus == 'deleted') continue;

        final b = (t['branchId'] as String? ?? '').toLowerCase().trim();
        if (b.isNotEmpty && !_isMatchingBranch(b, bId)) continue;
        final dk = t['dateKey']?.toString() ?? '';
        final rawD = t['createdAt'] ?? t['timestamp'] ?? t['date'] ?? t['time'];
        if (dk == dateKeyYmd || dk == dateKeyDmyy || _isSameDate(rawD, dateKeyYmd, dateKeyDmyy)) {
          das++;
          if (t['served'] == true) {
            served++;
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Error reading local food tokens: $e');
  }

  // Fast check: if local Hive had 0 food tokens for this branch, check Firestore day summary doc
  if (das == 0) {
    try {
      final dasDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(bId)
          .collection('dasterkhwaan')
          .doc(dateKeyYmd)
          .get()
          .timeout(const Duration(milliseconds: 2500));
      if (dasDoc.exists) {
        final dData = dasDoc.data() ?? {};
        final tot = (dData['totalTokens'] as num?)?.toInt() ?? 0;
        final srv = (dData['servedTokens'] as num?)?.toInt() ?? 0;
        if (tot > 0) {
          das = tot;
          if (srv > 0) served = srv;
          // Trigger asynchronous background download of tokens into local Hive box
          unawaited(LocalStorageService.downloadDasterkhwaanTokens(bId, days: 2));
        }
      }
    } catch (_) {}
  }

  // If no local entries were found, fallback to cached docs from remote
  if (z == 0 && nz == 0 && gm == 0 && das == 0) {
    try {
      final cachedDocs = LocalStorageService.getBranchDayCache(bId, dateKeyDmyy, 'dispensary');
      if (cachedDocs != null) {
        for (final val in cachedDocs) {
          final type = val['type']?.toString().toLowerCase();
          final days = (val['daysOfMedicine'] as num?)?.toInt() ?? 1;
          
          if (type == 'zakat') {
            z++;
            final rev = 20 * days;
            dispRev += rev;
            zRev += rev;
          } else if (type == 'non-zakat') {
            nz++;
            final rev = 100 * days;
            dispRev += rev;
            nzRev += rev;
          } else if (type == 'gmwf') {
            gm++;
          }
          dispensed++;
        }
      }
    } catch (e) {
      debugPrint('Error reading cached historical entries: $e');
    }
  }

  int madrassaAttendance = 0;
  try {
    final dateKeyMadrassa = DateFormat('yyyy-MM-dd').format(date);
    final log = MadrassaLocalStorage.getLogCached(branchId, dateKeyMadrassa);
    if (log != null) {
      for (final v in log.values) {
        if (v is Map && v['attendance'] == 'present') {
          madrassaAttendance++;
        }
      }
    }
  } catch (e) {
    debugPrint('Error loading madrassa stats: $e');
  }

  int empAttendance = 0;
  try {
    final dateKeyEmp = DateFormat('yyyy-MM-dd').format(date);
    if (Hive.isBoxOpen(LocalStorageService.attendanceBox)) {
      final box = Hive.box(LocalStorageService.attendanceBox);
      for (final key in box.keys.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        final keyStr = key.toString();
        if (keyStr.endsWith('_$dateKeyEmp') || keyStr.endsWith(dateKeyEmp)) {
          final val = box.get(key);
          if (val is Map) {
            final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
            if (_isMatchingBranch(b, bId)) {
              final status = val['status']?.toString().toLowerCase();
              if (status == 'present' || status == 'late' || status == 'overtime') {
                empAttendance++;
              }
            }
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Error loading employee attendance stats: $e');
  }

  BranchStats res = BranchStats(
    zakat: z,
    nonZakat: nz,
    gmwf: gm,
    dispensed: dispensed,
    prescribed: madrassaAttendance,
    dasterkhwaan: das,
    dasterkhwaanServed: served,
    donations: donTotal,
    dispensaryRevenue: dispRev,
    zakatRevenue: zRev,
    nonZakatRevenue: nzRev,
    gmwfRevenue: gmRev,
    employeeAttendance: empAttendance,
  );

  // With remote allowed (HQ), combine with the cloud counts: this PC may hold some of the
  // branch's records (a clinic PC holds newer ones than the cloud), so each figure takes the
  // larger of the two. Cloud figures are cached (see fetchCloudDayCountsCached).
  if (allowRemoteFallback) {
    try {
      final fsRes = await _fetchFirestoreBranchStats(bId, date);
      if (fsRes != null) {
        int mx(int a, int b) => a > b ? a : b;
        res = BranchStats(
          zakat: mx(z, fsRes.zakat),
          nonZakat: mx(nz, fsRes.nonZakat),
          gmwf: mx(gm, fsRes.gmwf),
          dispensed: mx(dispensed, fsRes.dispensed),
          prescribed: madrassaAttendance,
          dasterkhwaan: mx(das, fsRes.dasterkhwaan),
          dasterkhwaanServed: mx(served, fsRes.dasterkhwaanServed),
          donations: mx(donTotal, fsRes.donations),
          dispensaryRevenue: mx(dispRev, fsRes.dispensaryRevenue),
          zakatRevenue: mx(zRev, fsRes.zakatRevenue),
          nonZakatRevenue: mx(nzRev, fsRes.nonZakatRevenue),
          gmwfRevenue: gmRev,
          employeeAttendance: empAttendance,
        );
      }
    } catch (_) {}
  }

  // Cloud-combined past days can still change (late uploads), so they get the short TTL cache.
  if (!isToday && !allowRemoteFallback) {
    _historicalStatsCache[cacheTTLKey] = res;
  } else {
    _localStatsTTLCache[cacheTTLKey] = _CachedLocalBranchStats(res);
  }
  return res;
}

// ── Cloud token counts (HQ dashboard) ─────────────────────────────────────────
// HQ is on no clinic's LAN, so its local boxes hold almost none of the branches' tokens and
// the dashboard has to ask Firestore. Reading every token document cost one read per token
// on every refresh; count queries cost one read each (per 1000 matches), however many tokens
// a day has. The Windows Firestore plugin supports count() only (sum() is a no-op there), so
// multi-day courses are counted per daysOfMedicine value.

/// Token counts of one queue (zakat / non-zakat / gmwf) for one camp and day.
class CloudQueueCount {
  int total = 0;
  int completed = 0;
  int evening = 0;
  /// Days beyond the first, summed over all tokens (revenue is fee x days).
  int extraDays = 0;

  int get morning => total - evening;

  void add(CloudQueueCount o) {
    total += o.total;
    completed += o.completed;
    evening += o.evening;
    extraDays += o.extraDays;
  }
}

const _cloudQueues = ['zakat', 'non-zakat', 'gmwf'];
const _cloudQueryTimeout = Duration(seconds: 6);

Future<int> _countOf(Query<Map<String, dynamic>> q) async =>
    (await q.count().get().timeout(_cloudQueryTimeout)).count ?? 0;

Future<CloudQueueCount> _countQueue(CollectionReference<Map<String, dynamic>> col) async {
  final c = CloudQueueCount();
  final all = await _countOf(col);
  if (all == 0) return c; // an empty queue costs one read
  final r = await Future.wait([
    _countOf(col.where('status', whereIn: ['deleted', 'void', 'cancelled'])),
    _countOf(col.where('status', isEqualTo: 'completed')),
    _countOf(col.where('session', isEqualTo: 'evening')),
    _countOf(col.where('daysOfMedicine', isGreaterThan: 1)),
  ]);
  c.total = all - r[0];
  c.completed = r[1];
  c.evening = r[2];
  if (r[3] > 0) {
    final perDay = await Future.wait([
      for (var d = 2; d <= 7; d++) _countOf(col.where('daysOfMedicine', isEqualTo: d)),
    ]);
    var counted = 0;
    for (var i = 0; i < perDay.length; i++) {
      c.extraDays += perDay[i] * (i + 1);
      counted += perDay[i];
    }
    c.extraDays += (r[3] - counted) * 6; // longer courses are counted as 7 days
  }
  return c;
}

/// Counts tokens by reading the documents, merging one token found in several collections
/// (a Haji Camp token can be in both `<date>_haji` and v1.6.2's `<date>_haji_camp`).
Future<CloudQueueCount> _countQueueDeduped(List<CollectionReference<Map<String, dynamic>>> cols) async {
  final snaps = await Future.wait(cols.map((col) => col.get().timeout(_cloudQueryTimeout)));
  final byId = <String, Map<String, dynamic>>{};
  for (final snap in snaps) {
    for (final doc in snap.docs) {
      final m = byId.putIfAbsent(doc.id.toUpperCase(), () => <String, dynamic>{});
      doc.data().forEach((k, v) {
        if (LocalStorageService.isPlaceholderValue(m[k])) m[k] = v;
      });
      if (doc.data()['status'] == 'completed') m['status'] = 'completed';
    }
  }
  final c = CloudQueueCount();
  for (final m in byId.values) {
    final status = (m['status'] ?? '').toString().toLowerCase();
    if (status == 'deleted' || status == 'void' || status == 'cancelled') continue;
    c.total++;
    if (status == 'completed') c.completed++;
    if ((m['session'] ?? '').toString().toLowerCase() == 'evening') c.evening++;
    final days = (m['daysOfMedicine'] as num?)?.toInt() ?? 1;
    if (days > 1) c.extraDays += days - 1;
  }
  return c;
}

/// One branch-day's cloud token counts: camp key -> queue -> counts. The camp key is the
/// serials day-document suffix ('' for the plain `<date>` document); Karachi's
/// `<date>_haji` and `<date>_haji_camp` are both 'haji'.
typedef CloudDayCounts = Map<String, Map<String, CloudQueueCount>>;

Future<CloudDayCounts> _fetchCloudDayCounts(String branchId, String dmyy) async {
  final out = <String, Map<String, CloudQueueCount>>{};
  final jobs = <Future<void>>[];
  for (final fsBranch in CampSessionService.firestoreBranchIds(branchId)) {
    final base = FirebaseFirestore.instance.collection('branches').doc(fsBranch).collection('serials');
    final groups = <String, List<String>>{};
    for (final id in CampSessionService.getAllCampDateDocIds(branchId: fsBranch, dateKey: dmyy)) {
      var key = id == dmyy ? '' : id.substring(dmyy.length + 1);
      if (CampSessionService.isKarachiFamily(fsBranch) && key.contains('haji')) key = 'haji';
      groups.putIfAbsent(key, () => []).add(id);
    }
    groups.forEach((campKey, docIds) {
      for (final q in _cloudQueues) {
        jobs.add(() async {
          final cols = [for (final id in docIds) base.doc(id).collection(q)];
          final counts = await Future.wait(cols.map(_countQueue));
          final filled = counts.where((c) => c.total > 0).length;
          final c = filled > 1
              ? await _countQueueDeduped(cols)
              : counts.firstWhere((c) => c.total > 0, orElse: CloudQueueCount.new);
          out.putIfAbsent(campKey, () => {}).putIfAbsent(q, CloudQueueCount.new).add(c);
        }());
      }
    });
  }
  await Future.wait(jobs);
  return out;
}

final Map<String, (DateTime, Future<CloudDayCounts?>)> _cloudDayCountsCache = {};

/// Cloud token counts for a branch and day, shared by the stat tiles, the branch table and the
/// Karachi camp rows. Today's counts are reused for 10 minutes, older days for 6 hours (late
/// uploads still arrive). Concurrent callers share one fetch; a failed fetch is not cached.
Future<CloudDayCounts?> fetchCloudDayCountsCached(String branchId, DateTime date) {
  final dmyy = DateFormat('ddMMyy').format(date);
  final key = '${branchId.toLowerCase().trim()}|$dmyy';
  final now = DateTime.now();
  final isToday = DateFormat('ddMMyy').format(now) == dmyy;
  final ttl = isToday ? const Duration(minutes: 10) : const Duration(hours: 6);
  final cached = _cloudDayCountsCache[key];
  if (cached != null && now.difference(cached.$1) < ttl) return cached.$2;

  final future = _fetchCloudDayCounts(branchId, dmyy).then<CloudDayCounts?>((v) => v).catchError((Object e) {
    debugPrint('[HomeDashboard] cloud token counts for $key failed: $e');
    _cloudDayCountsCache.remove(key);
    return null;
  });
  _cloudDayCountsCache[key] = (now, future);
  return future;
}

final Map<String, (DateTime, BranchStats?)> _cloudBranchStatsCache = {};

Future<BranchStats?> _fetchFirestoreBranchStats(String branchId, DateTime date) async {
  final bId = branchId.toLowerCase().trim();
  final dateKeyYmd = DateFormat('yyyy-MM-dd').format(date);
  final dateKeyDmyy = DateFormat('ddMMyy').format(date);
  final cacheKey = '$bId|$dateKeyDmyy';
  final isToday = DateFormat('ddMMyy').format(DateTime.now()) == dateKeyDmyy;
  final ttl = isToday ? const Duration(minutes: 10) : const Duration(hours: 6);
  final cached = _cloudBranchStatsCache[cacheKey];
  if (cached != null && DateTime.now().difference(cached.$1) < ttl) return cached.$2;

  try {
    final fsBranches = CampSessionService.firestoreBranchIds(bId);

    // 1. Donations (stored with date 'yyyy-MM-dd').
    int donTotal = 0;
    for (final fsBranch in fsBranches) {
      try {
        final donSnap = await FirebaseFirestore.instance
            .collection('branches').doc(fsBranch).collection('donations')
            .where('date', isEqualTo: dateKeyYmd)
            .get()
            .timeout(_cloudQueryTimeout);
        for (final doc in donSnap.docs) {
          final val = doc.data();
          final status = val['status']?.toString().toLowerCase();
          final syncStatus = val['syncStatus']?.toString().toLowerCase();
          if (status == 'deleted' || syncStatus == 'deleted') continue;
          final payMethod = val['paymentMethod']?.toString().toLowerCase() ?? '';
          if (payMethod == 'bank_deposit') continue;
          final amt = val['amount'];
          final amtDouble = (amt is num) ? amt.toDouble() : (double.tryParse(amt?.toString() ?? '0') ?? 0.0);
          donTotal += amtDouble.toInt();
        }
      } catch (_) {}
    }

    // 2. Patient tokens (count queries, see fetchCloudDayCountsCached).
    int z = 0, nz = 0, gm = 0, dispensed = 0, zRev = 0, nzRev = 0;
    final counts = await fetchCloudDayCountsCached(bId, date);
    for (final queues in (counts ?? const <String, Map<String, CloudQueueCount>>{}).values) {
      queues.forEach((q, c) {
        dispensed += c.completed;
        if (q == 'zakat') {
          z += c.total;
          zRev += 20 * (c.total + c.extraDays);
        } else if (q == 'non-zakat') {
          nz += c.total;
          nzRev += 100 * (c.total + c.extraDays);
        } else {
          gm += c.total;
        }
      });
    }

    // 3. Food tokens: the day summary document.
    int das = 0, served = 0;
    for (final fsBranch in fsBranches) {
      for (final dayId in [dateKeyYmd, dateKeyDmyy]) {
        if (das > 0) break;
        try {
          final dasDoc = await FirebaseFirestore.instance
              .collection('branches').doc(fsBranch).collection('dasterkhwaan').doc(dayId)
              .get().timeout(_cloudQueryTimeout);
          final dData = dasDoc.data() ?? {};
          das = (dData['totalTokens'] as num?)?.toInt() ?? 0;
          served = (dData['servedTokens'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }
    }

    final res = counts == null && donTotal == 0 && das == 0
        ? null
        : BranchStats(
            zakat: z,
            nonZakat: nz,
            gmwf: gm,
            dispensed: dispensed,
            prescribed: 0,
            dasterkhwaan: das,
            dasterkhwaanServed: served,
            donations: donTotal,
            dispensaryRevenue: zRev + nzRev,
            zakatRevenue: zRev,
            nonZakatRevenue: nzRev,
            gmwfRevenue: 0,
            employeeAttendance: 0,
          );
    if (res != null) _cloudBranchStatsCache[cacheKey] = (DateTime.now(), res);
    return res;
  } catch (e) {
    return null;
  }
}

/// Fetches stats for a single historical day (e.g. yesterday) for one
/// branch, using an indefinite in-memory cache since past days never change.
Future<BranchStats> fetchHistoricalDayStats(String branchId, DateTime day) async {
  final key = _dayKey(branchId, day);
  final cached = _historicalStatsCache[key];
  if (cached != null) return cached;

  final stats = await fetchLocalBranchStats(branchId, day);
  _historicalStatsCache[key] = stats;
  return stats;
}

/// Combines a list of BranchStats into one aggregate. Public so both this
/// file and the widgets that consume it can share the same logic instead
/// of each re-summing the fields by hand.
BranchStats combineBranchStats(List<BranchStats> results) {
  int z = 0, nz = 0, gm = 0, das = 0, dasServed = 0, don = 0, disp = 0, presc = 0, dispRev = 0;
  int zRev = 0, nzRev = 0, gmRev = 0;
  int empAtt = 0;
  for (final r in results) {
    z += r.zakat; nz += r.nonZakat; gm += r.gmwf;
    das += r.dasterkhwaan; dasServed += r.dasterkhwaanServed;
    don += r.donations; disp += r.dispensed; presc += r.prescribed;
    dispRev += r.dispensaryRevenue;
    zRev += r.zakatRevenue; nzRev += r.nonZakatRevenue; gmRev += r.gmwfRevenue;
    empAtt += r.employeeAttendance;
  }
  return BranchStats(
    zakat: z, nonZakat: nz, gmwf: gm,
    dasterkhwaan: das, dasterkhwaanServed: dasServed,
    donations: don, dispensed: disp, prescribed: presc,
    dispensaryRevenue: dispRev,
    zakatRevenue: zRev, nonZakatRevenue: nzRev, gmwfRevenue: gmRev,
    employeeAttendance: empAtt,
  );
}

/// Today's stats + yesterday's stats for one branch (or a pre-combined
/// aggregate), plus a helper to compute a %-change for any BranchStats field.
class TodayVsYesterday {
  final BranchStats today;
  final BranchStats yesterday;
  const TodayVsYesterday({required this.today, required this.yesterday});

  /// Percent change, today vs yesterday. Returns null if yesterday's value
  /// was 0 — there's no meaningful percentage to show, caller should
  /// render something like "New today" instead.
  double? deltaPct(int Function(BranchStats) selector) {
    final t = selector(today);
    final y = selector(yesterday);
    if (y == 0) return null;
    return ((t - y) / y) * 100;
  }
}

/// Per-branch today-vs-yesterday, for every branch in [ids]. Both the 5
/// stat tiles (aggregated) and the branch table (per-row) are built from
/// this single fetch so we don't hit Firestore/cache twice.
Future<Map<String, TodayVsYesterday>> fetchTodayVsYesterdayPerBranch(
    List<String> ids, {bool allowRemoteFallback = false}) async {
  if (ids.isEmpty) return {};
  final yesterday = DateTime.now().subtract(const Duration(days: 1));

  final todayResults = await Future.wait(ids.map((id) => fetchLocalBranchStats(id, DateTime.now(), allowRemoteFallback: allowRemoteFallback)));
  final yestResults = await Future.wait(ids.map((id) => fetchLocalBranchStats(id, yesterday, allowRemoteFallback: allowRemoteFallback)));

  final out = <String, TodayVsYesterday>{};
  for (var i = 0; i < ids.length; i++) {
    out[ids[i]] = TodayVsYesterday(today: todayResults[i], yesterday: yestResults[i]);
  }
  return out;
}

class KarachiCampBreakdown {
  final int hajiCampPatients;
  final int hajiCampZakat;
  final int hajiCampNonZakat;
  final int hajiCampGmwf;
  final int hajiCampRevenue;

  final int hajiCampMorningPatients;
  final int hajiCampMorningZakat;
  final int hajiCampMorningNonZakat;
  final int hajiCampMorningGmwf;

  final int hajiCampEveningPatients;
  final int hajiCampEveningZakat;
  final int hajiCampEveningNonZakat;
  final int hajiCampEveningGmwf;

  final int kapayaPatients;
  final int kapayaZakat;
  final int kapayaNonZakat;
  final int kapayaGmwf;
  final int kapayaRevenue;

  final int kapayaMorningPatients;
  final int kapayaMorningZakat;
  final int kapayaMorningNonZakat;
  final int kapayaMorningGmwf;

  final int kapayaEveningPatients;
  final int kapayaEveningZakat;
  final int kapayaEveningNonZakat;
  final int kapayaEveningGmwf;

  const KarachiCampBreakdown({
    this.hajiCampPatients = 0,
    this.hajiCampZakat = 0,
    this.hajiCampNonZakat = 0,
    this.hajiCampGmwf = 0,
    this.hajiCampRevenue = 0,
    this.hajiCampMorningPatients = 0,
    this.hajiCampMorningZakat = 0,
    this.hajiCampMorningNonZakat = 0,
    this.hajiCampMorningGmwf = 0,
    this.hajiCampEveningPatients = 0,
    this.hajiCampEveningZakat = 0,
    this.hajiCampEveningNonZakat = 0,
    this.hajiCampEveningGmwf = 0,
    this.kapayaPatients = 0,
    this.kapayaZakat = 0,
    this.kapayaNonZakat = 0,
    this.kapayaGmwf = 0,
    this.kapayaRevenue = 0,
    this.kapayaMorningPatients = 0,
    this.kapayaMorningZakat = 0,
    this.kapayaMorningNonZakat = 0,
    this.kapayaMorningGmwf = 0,
    this.kapayaEveningPatients = 0,
    this.kapayaEveningZakat = 0,
    this.kapayaEveningNonZakat = 0,
    this.kapayaEveningGmwf = 0,
  });

  int get totalPatients => hajiCampPatients + kapayaPatients;
  int get totalRevenue => hajiCampRevenue + kapayaRevenue;
  int get morningTotal => hajiCampMorningPatients + kapayaMorningPatients;
  int get eveningTotal => hajiCampEveningPatients + kapayaEveningPatients;
}

KarachiCampBreakdown? _cachedKarachiCampBreakdown;
DateTime? _lastKarachiCampBreakdownTime;
String? _cachedKarachiCampDateKey;

Future<KarachiCampBreakdown> fetchKarachiCampBreakdown([DateTime? date, bool allowRemote = false]) async {
  final targetDate = date ?? DateTime.now();
  final ymd = DateFormat('yyyy-MM-dd').format(targetDate);
  final dmyy = DateFormat('ddMMyy').format(targetDate);

  if (_cachedKarachiCampBreakdown != null &&
      _cachedKarachiCampDateKey == '$ymd|$allowRemote' &&
      _lastKarachiCampBreakdownTime != null &&
      DateTime.now().difference(_lastKarachiCampBreakdownTime!).inSeconds < 45) {
    return _cachedKarachiCampBreakdown!;
  }

  int hajiMZ = 0, hajiMNZ = 0, hajiMGM = 0;
  int hajiEZ = 0, hajiENZ = 0, hajiEGM = 0;
  int kapayaMZ = 0, kapayaMNZ = 0, kapayaMGM = 0;
  int kapayaEZ = 0, kapayaENZ = 0, kapayaEGM = 0;
  int hajiRev = 0;
  int kapayaRev = 0;

  final Map<String, Map<String, dynamic>> entryMap = {};

  void addEntryIfValid(Map<String, dynamic> e, dynamic fallbackKey) {
    final status = e['status']?.toString().toLowerCase();
    final syncStatus = e['syncStatus']?.toString().toLowerCase();
    if (status == 'deleted' || syncStatus == 'deleted' || status == 'void' || status == 'cancelled') return;

    final rawDateVal = e['dateKey'] ?? e['date'] ?? e['createdAt'] ?? e['timestamp'] ?? e['serial'];
    if (!_isSameDate(rawDateVal, ymd, dmyy)) return;

    final rawSerial = (e['serial'] ?? e['id'] ?? e['tokenNumber'] ?? e['tokenSerial'] ?? fallbackKey ?? '').toString().trim().toLowerCase();
    final cleanSerial = rawSerial.replaceAll(RegExp(r'^(entry:|serial:|token:|karachi_)'), '');
    final parts = cleanSerial.split('-');
    final sNum = parts.length > 1 ? parts.last : cleanSerial;
    final canonicalKey = parts.length > 2
        ? '${parts[1]}-${parts[2]}'
        : (parts.length > 1 ? '${parts[0]}-${parts[1]}' : sNum);

    if (canonicalKey.isNotEmpty && !entryMap.containsKey(canonicalKey)) {
      entryMap[canonicalKey] = e;
    }
  }

  // 1. Local entries strictly belonging to Karachi (fast values scan)
  try {
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final box = Hive.box(LocalStorageService.entriesBox);
      var scanned = 0;
      for (final val in box.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (val is Map) {
          final b = (val['branchId'] ?? '').toString().toLowerCase().trim();
          if (b.isEmpty || b.contains('karachi') || b.contains('haji') || b.contains('kapaya') || b.contains('saddar')) {
            final e = Map<String, dynamic>.from(val);
            addEntryIfValid(e, e['id'] ?? e['serial']);
          }
        }
      }
    }
  } catch (_) {}

  for (final e in entryMap.values) {
    final status = e['status']?.toString().toLowerCase();
    final syncStatus = e['syncStatus']?.toString().toLowerCase();
    if (status == 'deleted' || syncStatus == 'deleted' || status == 'void' || status == 'cancelled') continue;
    final rawDateVal = e['dateKey'] ?? e['date'] ?? e['createdAt'] ?? e['timestamp'] ?? e['serial'];
    if (!_isSameDate(rawDateVal, ymd, dmyy)) continue;

    final isExplicitHaji = CampSessionService.matchesCamp(
      selectedCamp: 'haji',
      dispensaryId: e['dispensaryId']?.toString(),
      campId: e['campId']?.toString(),
      dispensaryTag: e['dispensaryTag']?.toString(),
      serial: (e['serial'] ?? e['id'])?.toString(),
    );

    final sTag = (e['session'] ?? e['shift'] ?? e['campSession'] ?? e['slot'] ?? '').toString().toLowerCase().trim();
    bool isEvening = sTag == 'evening' || sTag == 'night';
    if (sTag == 'morning') {
      isEvening = false;
    } else if (sTag.isEmpty || sTag == 'day') {
      final rawTime = e['timestamp'] ?? e['createdAt'] ?? e['time'] ?? e['dispensedAt'] ?? e['date'] ?? e['lastUpdatedAt'];
      if (rawTime != null) {
        try {
          DateTime? dt;
          if (rawTime is Timestamp) {
            dt = rawTime.toDate().toLocal();
          } else if (rawTime is DateTime) {
            dt = rawTime.toLocal();
          } else {
            dt = DateTime.tryParse(rawTime.toString())?.toLocal();
          }
          if (dt != null) {
            isEvening = dt.hour >= 14 || dt.hour < 6;
          }
        } catch (_) {
          isEvening = false;
        }
      }
    }

    final serialUpper = (e['serial'] ?? e['tokenNumber'] ?? e['token'] ?? '').toString().toUpperCase();
    final cat = (e['category'] ?? e['queueType'] ?? e['type'] ?? '').toString().toLowerCase().trim();
    final isGmwf = cat.contains('gmwf') || cat.contains('free') || e['isFreeToken'] == true || serialUpper.contains('-G-');
    final isNonZakat = !isGmwf && (cat.contains('non-zakat') || cat.contains('nonzakat') || cat.contains('non_zakat') || serialUpper.contains('-NZ-') || serialUpper.contains('NZ'));

    final feeVal = e['fee'] ?? e['tokenFee'] ?? e['amount'] ?? e['price'] ?? e['dispensaryRevenue'];
    int eRev = 0;
    if (feeVal != null && (feeVal is num || double.tryParse(feeVal.toString()) != null)) {
      eRev = (feeVal is num ? feeVal.toInt() : double.tryParse(feeVal.toString())?.toInt() ?? 0);
    } else {
      final daysRaw = e['daysOfMedicine'] ?? 1;
      final days = (daysRaw is num ? daysRaw.toInt() : int.tryParse(daysRaw.toString()) ?? 1);
      if (isGmwf) {
        eRev = 0;
      } else if (isNonZakat) {
        eRev = 100 * days;
      } else {
        eRev = 20 * days; // Default Karachi token fee (Zakat Rs 20)
      }
    }

    if (isExplicitHaji) {
      hajiRev += eRev;
      if (isEvening) {
        if (isGmwf) {
          hajiEGM++;
        } else if (isNonZakat) {
          hajiENZ++;
        } else {
          hajiEZ++;
        }
      } else {
        if (isGmwf) {
          hajiMGM++;
        } else if (isNonZakat) {
          hajiMNZ++;
        } else {
          hajiMZ++;
        }
      }
    } else {
      // All other Karachi patient data attributes to Saddar (Kapaya) Camp
      kapayaRev += eRev;
      if (isEvening) {
        if (isGmwf) {
          kapayaEGM++;
        } else if (isNonZakat) {
          kapayaENZ++;
        } else {
          kapayaEZ++;
        }
      } else {
        if (isGmwf) {
          kapayaMGM++;
        } else if (isNonZakat) {
          kapayaMNZ++;
        } else {
          kapayaMZ++;
        }
      }
    }
  }

  // 2. Cloud counts (HQ, which holds few Karachi tokens locally): each figure takes the larger
  // of this PC's and the cloud's. '<date>_haji' / '_haji_camp' are Haji Camp; everything
  // else in Karachi ('<date>_saddar' and the plain '<date>') is Saddar, as for local entries.
  if (allowRemote) {
    final counts = await fetchCloudDayCountsCached('karachi', targetDate);
    if (counts != null) {
      final haji = <String, CloudQueueCount>{};
      final saddar = <String, CloudQueueCount>{};
      counts.forEach((camp, queues) {
        final target = camp == 'haji' ? haji : saddar;
        queues.forEach((q, c) => target.putIfAbsent(q, CloudQueueCount.new).add(c));
      });
      CloudQueueCount qc(Map<String, CloudQueueCount> m, String q) => m[q] ?? CloudQueueCount();
      int mx(int a, int b) => a > b ? a : b;
      int rev(Map<String, CloudQueueCount> m) =>
          20 * (qc(m, 'zakat').total + qc(m, 'zakat').extraDays) +
          100 * (qc(m, 'non-zakat').total + qc(m, 'non-zakat').extraDays);

      hajiMZ = mx(hajiMZ, qc(haji, 'zakat').morning);
      hajiEZ = mx(hajiEZ, qc(haji, 'zakat').evening);
      hajiMNZ = mx(hajiMNZ, qc(haji, 'non-zakat').morning);
      hajiENZ = mx(hajiENZ, qc(haji, 'non-zakat').evening);
      hajiMGM = mx(hajiMGM, qc(haji, 'gmwf').morning);
      hajiEGM = mx(hajiEGM, qc(haji, 'gmwf').evening);
      hajiRev = mx(hajiRev, rev(haji));

      kapayaMZ = mx(kapayaMZ, qc(saddar, 'zakat').morning);
      kapayaEZ = mx(kapayaEZ, qc(saddar, 'zakat').evening);
      kapayaMNZ = mx(kapayaMNZ, qc(saddar, 'non-zakat').morning);
      kapayaENZ = mx(kapayaENZ, qc(saddar, 'non-zakat').evening);
      kapayaMGM = mx(kapayaMGM, qc(saddar, 'gmwf').morning);
      kapayaEGM = mx(kapayaEGM, qc(saddar, 'gmwf').evening);
      kapayaRev = mx(kapayaRev, rev(saddar));
    }
  }

  final hajiZ = hajiMZ + hajiEZ;
  final hajiNZ = hajiMNZ + hajiENZ;
  final hajiGM = hajiMGM + hajiEGM;

  final kapayaZ = kapayaMZ + kapayaEZ;
  final kapayaNZ = kapayaMNZ + kapayaENZ;
  final kapayaGM = kapayaMGM + kapayaEGM;

  final res = KarachiCampBreakdown(
    hajiCampPatients: hajiZ + hajiNZ + hajiGM,
    hajiCampZakat: hajiZ,
    hajiCampNonZakat: hajiNZ,
    hajiCampGmwf: hajiGM,
    hajiCampRevenue: hajiRev,

    hajiCampMorningPatients: hajiMZ + hajiMNZ + hajiMGM,
    hajiCampMorningZakat: hajiMZ,
    hajiCampMorningNonZakat: hajiMNZ,
    hajiCampMorningGmwf: hajiMGM,

    hajiCampEveningPatients: hajiEZ + hajiENZ + hajiEGM,
    hajiCampEveningZakat: hajiEZ,
    hajiCampEveningNonZakat: hajiENZ,
    hajiCampEveningGmwf: hajiEGM,

    kapayaPatients: kapayaZ + kapayaNZ + kapayaGM,
    kapayaZakat: kapayaZ,
    kapayaNonZakat: kapayaNZ,
    kapayaGmwf: kapayaGM,
    kapayaRevenue: kapayaRev,

    kapayaMorningPatients: kapayaMZ + kapayaMNZ + kapayaMGM,
    kapayaMorningZakat: kapayaMZ,
    kapayaMorningNonZakat: kapayaMNZ,
    kapayaMorningGmwf: kapayaMGM,

    kapayaEveningPatients: kapayaEZ + kapayaENZ + kapayaEGM,
    kapayaEveningZakat: kapayaEZ,
    kapayaEveningNonZakat: kapayaENZ,
    kapayaEveningGmwf: kapayaEGM,
  );

  _cachedKarachiCampBreakdown = res;
  _cachedKarachiCampDateKey = '$ymd|$allowRemote';
  _lastKarachiCampBreakdownTime = DateTime.now();
  return res;
}

/// Fetches daily revenue total for the past [days] days for the list of branches,
/// returning chronologically sorted historical entries.
Future<List<MapEntry<DateTime, int>>> fetchRevenueSeries(List<String> branchIds, {int days = 30}) async {
  if (branchIds.isEmpty) return [];
  final now = DateTime.now();
  // Generate dates in chronological order
  final dates = List.generate(days, (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1 - i)));

  final futures = dates.map((date) async {
    final results = await Future.wait(branchIds.map((id) => fetchHistoricalDayStats(id, date)));
    final combined = combineBranchStats(results);
    return MapEntry(date, combined.totalRevenue);
  });

  return await Future.wait(futures);
}

/// Consolidated Activity feed event representation.
class RecentActivity {
  final String id;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final String type; // 'donation' or 'token'
  final String branchId;
  final String branchName;
  final double? amount;
  final String? status;

  RecentActivity({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.type,
    required this.branchId,
    required this.branchName,
    this.amount,
    this.status,
  });
}

class RecentActivityService {
  static String resolveBranchName(String branchId) {
    final cleanId = branchId.toLowerCase().trim();
    if (Hive.isBoxOpen(LocalStorageService.branchesBox)) {
      final box = Hive.box(LocalStorageService.branchesBox);
      final cached = box.get('branch:$cleanId') ??
          box.get('branch:${cleanId.replaceAll('_', '')}') ??
          box.get(cleanId) ??
          box.get(cleanId.replaceAll('_', ''));
      if (cached is Map) {
        return (cached['name'] as String?) ?? branchId;
      }
    }
    if (cleanId == 'jalalpurjattan' || cleanId == 'jalalpur_jattan') return 'Jalal Pur Jattan';
    if (branchId.isEmpty) return 'Global';
    return branchId[0].toUpperCase() + branchId.substring(1);
  }

  /// The [limit] newest donations and tokens. Only the newest few are ever shown, so the
  /// activity rows are built for those alone; building and sorting one for every record in
  /// the history held the UI thread for seconds on PCs with a long history.
  static List<RecentActivity> getRecentActivity({String? branchId, int limit = 20}) {
    final targetBranch = (branchId ?? '').toLowerCase().trim();
    final anyBranch = targetBranch.isEmpty || targetBranch == 'all' || targetBranch == 'global';
    final newest = _NewestFirst<RecentActivity Function()>(limit);

    DateTime timeOf(dynamic raw) => raw == null ? DateTime.now() : (DateTime.tryParse(raw.toString()) ?? DateTime.now());

    // 1. Fetch local donations
    if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
      final donBox = Hive.box(DonationsLocalStorage.donationsBox);
      for (final key in donBox.keys) {
        final data = donBox.get(key);
        if (data is! Map) continue;
        final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
        if (!anyBranch && !_isMatchingBranch(bId, targetBranch)) continue;

        final dt = timeOf(data['timestamp'] ?? data['lastUpdatedAt'] ?? data['date']);
        newest.offer(dt, () {
          final donor = data['donorName']?.toString() ?? 'Walk-in Donor';
          final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
          final rcpt = data['receiptNo']?.toString() ?? '';
          return RecentActivity(
            id: 'don_${data['localId'] ?? key}',
            title: 'Donation of PKR ${amt.toStringAsFixed(0)}',
            subtitle: 'Received from $donor (Rcpt: $rcpt)',
            timestamp: dt,
            type: 'donation',
            branchId: bId,
            branchName: resolveBranchName(bId),
            amount: amt,
            status: data['status']?.toString(),
          );
        });
      }
    }

    // 2. Fetch local dispensary token / patient registrations
    if (Hive.isBoxOpen(LocalStorageService.dispensaryBox)) {
      final dispBox = Hive.box(LocalStorageService.dispensaryBox);
      for (final key in dispBox.keys) {
        final data = dispBox.get(key);
        if (data is! Map) continue;
        final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
        if (!anyBranch && !_isMatchingBranch(bId, targetBranch)) continue;

        final dt = timeOf(data['createdAt'] ?? data['timestamp'] ?? data['date']);
        newest.offer(dt, () {
          final serial = data['serial']?.toString() ?? key.toString();
          final pName = data['patientName']?.toString() ?? data['name']?.toString() ?? 'Patient';
          final qType = (data['queueType'] ?? data['category'] ?? 'zakat').toString().toUpperCase();
          return RecentActivity(
            id: 'disp_${data['id'] ?? key}',
            title: 'Patient Token #$serial',
            subtitle: 'Patient: $pName ($qType)',
            timestamp: dt,
            type: 'token',
            branchId: bId,
            branchName: resolveBranchName(bId),
            status: data['status']?.toString() ?? 'issued',
          );
        });
      }
    }

    // 3. Fetch local token entries box
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      for (final key in entriesBox.keys) {
        final data = entriesBox.get(key);
        if (data is! Map) continue;
        final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
        if (!anyBranch && !_isMatchingBranch(bId, targetBranch)) continue;

        final dt = timeOf(data['createdAt'] ?? data['timestamp']);
        newest.offer(dt, () {
          final serial = data['serial']?.toString() ?? '';
          final pName = data['patientName']?.toString() ?? 'Unknown Patient';
          final qType = (data['queueType'] as String? ?? 'zakat').toUpperCase();
          return RecentActivity(
            id: 'tok_${data['id'] ?? key}',
            title: 'Token #$serial Issued',
            subtitle: 'Patient: $pName ($qType)',
            timestamp: dt,
            type: 'token',
            branchId: bId,
            branchName: resolveBranchName(bId),
            status: data['status']?.toString() ?? 'issued',
          );
        });
      }
    }

    return [for (final build in newest.take()) build()];
  }

  static Future<List<RecentActivity>> getRecentActivityAsync({String? branchId, int limit = 20}) async {
    List<RecentActivity> list = getRecentActivity(branchId: branchId, limit: limit);

    if (list.isEmpty) {
      try {
        final donSnap = await FirebaseFirestore.instance
            .collection('donations')
            .limit(limit)
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in donSnap.docs) {
          final data = doc.data();
          final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
          if (branchId != null && bId != branchId.toLowerCase().trim() && branchId != 'all') continue;

          final dtStr = data['timestamp'] ?? data['lastUpdatedAt'] ?? data['date'];
          DateTime dt = DateTime.now();
          if (dtStr != null) {
            dt = DateTime.tryParse(dtStr.toString()) ?? DateTime.now();
          }

          final donor = data['donorName']?.toString() ?? 'Walk-in Donor';
          final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
          final rcpt = data['receiptNo']?.toString() ?? '';

          list.add(RecentActivity(
            id: 'don_${doc.id}',
            title: 'Donation of PKR ${amt.toStringAsFixed(0)}',
            subtitle: 'Received from $donor (Rcpt: $rcpt)',
            timestamp: dt,
            type: 'donation',
            branchId: bId,
            branchName: resolveBranchName(bId),
            amount: amt,
            status: data['status']?.toString(),
          ));
        }
      } catch (_) {}

      try {
        final bId = (branchId != null && branchId != 'all') ? branchId : 'default';
        final localEntries = LocalStorageService.getLocalEntries(bId);
        for (final data in localEntries.take(limit)) {
          final dtStr = data['createdAt'] ?? data['timestamp'] ?? data['date'];
          DateTime dt = DateTime.now();
          if (dtStr != null) {
            dt = DateTime.tryParse(dtStr.toString()) ?? DateTime.now();
          }

          final serial = data['serial']?.toString() ?? data['id']?.toString() ?? 'N/A';
          final pName = data['patientName']?.toString() ?? 'Unknown Patient';
          final qType = (data['queueType'] as String? ?? 'zakat').toUpperCase();
          final status = data['status']?.toString() ?? 'issued';
          final entryBranch = (data['branchId'] as String? ?? bId).toLowerCase().trim();

          list.add(RecentActivity(
            id: 'tok_$serial',
            title: 'Token #$serial Issued',
            subtitle: 'Patient: $pName ($qType)',
            timestamp: dt,
            type: 'token',
            branchId: entryBranch,
            branchName: resolveBranchName(entryBranch),
            status: status,
          ));
        }
      } catch (_) {}

      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (list.length > limit) {
        list = list.sublist(0, limit);
      }
    }

    return list;
  }

  static List<String>? _branchIdsCache;
  static DateTime? _branchIdsCachedAt;

  /// Branches seen in the local boxes. Finding them means going through every token and
  /// donation, and new branches are rare, so the answer is reused for a few minutes.
  static List<String> getAllBranchIds() {
    final cached = _branchIdsCache;
    final cachedAt = _branchIdsCachedAt;
    if (cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < const Duration(minutes: 5)) {
      return List.of(cached);
    }
    final ids = _scanAllBranchIds();
    _branchIdsCache = ids;
    _branchIdsCachedAt = DateTime.now();
    return List.of(ids);
  }

  static List<String> _scanAllBranchIds() {
    final Set<String> idsSet = {'karachi', 'sialkot', 'gujrat', 'jalalpurjattan', 'rawalpindi'};
    void addBranchId(String raw) {
      final norm = raw.toLowerCase().trim();
      if (norm.isEmpty || norm == 'all' || norm == 'unknown') return;
      if (norm.contains('jalal')) {
        idsSet.add('jalalpurjattan');
      } else if (norm.contains('karachi') || norm.contains('haji') || norm.contains('kapaya') || norm.contains('saddar')) {
        idsSet.add('karachi');
      } else {
        idsSet.add(norm);
      }
    }

    try {
      if (Hive.isBoxOpen(LocalStorageService.branchesBox)) {
        final box = Hive.box(LocalStorageService.branchesBox);
        for (final k in box.keys) {
          addBranchId(k.toString().replaceFirst('branch:', ''));
        }
      }
    } catch (_) {}

    try {
      if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
        final box = Hive.box(LocalStorageService.entriesBox);
        for (final val in box.values) {
          if (val is Map) {
            addBranchId((val['branchId'] as String? ?? ''));
          }
        }
      }
    } catch (_) {}

    try {
      if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
        final box = Hive.box(DonationsLocalStorage.donationsBox);
        for (final val in box.values) {
          if (val is Map) {
            addBranchId((val['branchId'] as String? ?? ''));
          }
        }
      }
    } catch (_) {}

    return idsSet.toList();
  }

  static Future<List<String>> getAllBranchIdsAsync() async {
    final idsSet = Set<String>.from(getAllBranchIds());
    if (idsSet.length <= 1) {
      try {
        final snap = await FirebaseFirestore.instance.collection('branches').get().timeout(const Duration(seconds: 4));
        for (final doc in snap.docs) {
          final id = doc.id.toLowerCase().trim();
          if (id.isNotEmpty && id != 'all') idsSet.add(id);
        }
      } catch (_) {}
    }
    return idsSet.toList();
  }
}

class HomeLineChartPoint {
  final DateTime date;
  final int patientsRevenue;
  final int donations;
  final int tokens;
  final int employeesPresent;

  const HomeLineChartPoint({
    required this.date,
    required this.patientsRevenue,
    required this.donations,
    required this.tokens,
    required this.employeesPresent,
  });
}

Future<List<HomeLineChartPoint>> fetchChartPoints(List<String> branchIds, {int months = 5}) async {
  return fetchLocalChartPoints(branchIds, months: months);
}

final Map<String, (DateTime, List<HomeLineChartPoint>)> _chartPointsMemoryCache = {};

DateTime? _tryParseChartDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  final str = raw.toString().trim();
  if (str.isEmpty) return null;
  final dt = DateTime.tryParse(str);
  if (dt != null) return dt;
  if (str.length == 6 && int.tryParse(str) != null) {
    try {
      final day = int.parse(str.substring(0, 2));
      final month = int.parse(str.substring(2, 4));
      final year = 2000 + int.parse(str.substring(4, 6));
      return DateTime(year, month, day);
    } catch (_) {}
  }
  return null;
}

Future<List<HomeLineChartPoint>> fetchLocalChartPoints(List<String> branchIds, {int months = 5}) async {
  if (branchIds.isEmpty) return [];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final cacheKey = '${(List<String>.from(branchIds)..sort()).join('_')}_$months';

  // 1. Return instantaneous in-memory cached chart data if valid (15 min TTL)
  final cached = _chartPointsMemoryCache[cacheKey];
  if (cached != null && now.difference(cached.$1).inMinutes < 15) {
    return cached.$2;
  }

  // Precompute month boundaries
  final monthStarts = <DateTime>[];
  final nextMonths = <DateTime>[];
  final endOfMonths = <DateTime>[];
  for (int i = 0; i < months; i++) {
    final mStart = DateTime(today.year, today.month - (months - 1 - i), 1);
    final nMonth = DateTime(mStart.year, mStart.month + 1, 1);
    final eMonth = nMonth.subtract(const Duration(days: 1));
    monthStarts.add(mStart);
    nextMonths.add(nMonth);
    endOfMonths.add(eMonth);
  }

  int getMonthIndex(DateTime dt) {
    for (int m = 0; m < months; m++) {
      if (!dt.isBefore(monthStarts[m]) && dt.isBefore(nextMonths[m])) {
        return m;
      }
    }
    return -1;
  }

  bool isTargetBranch(String docBranch) {
    final b = docBranch.toLowerCase().trim();
    for (final id in branchIds) {
      if (_isMatchingBranch(b, id)) return true;
    }
    return false;
  }

  final revList = List<int>.filled(months, 0);
  final donList = List<int>.filled(months, 0);
  final tokenList = List<int>.filled(months, 0);
  final monthEmpDayCounts = List<Map<String, int>>.generate(months, (_) => <String, int>{});

  // Single pass 1: Donations
  try {
    if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
      final donBox = Hive.box(DonationsLocalStorage.donationsBox);
      var scanned = 0;
      for (final val in donBox.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (val is! Map) continue;
        final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
        if (!isTargetBranch(b)) continue;

        final status = val['status']?.toString().toLowerCase();
        final syncStatus = val['syncStatus']?.toString().toLowerCase();
        if (status == 'deleted' || syncStatus == 'deleted' || status == 'void') continue;

        final payMethod = val['paymentMethod']?.toString().toLowerCase() ?? '';
        if (payMethod == 'bank_deposit') continue;

        final dt = _tryParseChartDate(val['date'] ?? val['createdAt'] ?? val['timestamp']);
        if (dt == null) continue;
        final m = getMonthIndex(dt);
        if (m >= 0 && m < months) {
          final amt = val['amount'];
          final amtDouble = (amt is num) ? amt.toDouble() : (double.tryParse(amt?.toString() ?? '0') ?? 0.0);
          donList[m] += amtDouble.toInt();
        }
      }
    }
  } catch (e) {
    debugPrint('Error computing donations in chart points: $e');
  }

  // Single pass 2: Dispensary Entries
  try {
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final box = Hive.box(LocalStorageService.entriesBox);
      var scanned = 0;
      for (final val in box.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (val is! Map) continue;
        final status = val['status']?.toString().toLowerCase();
        final syncStatus = val['syncStatus']?.toString().toLowerCase();
        if (status == 'deleted' || syncStatus == 'deleted' || status == 'void' || status == 'cancelled') continue;

        final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
        if (!isTargetBranch(b)) continue;

        final dt = _tryParseChartDate(val['date'] ?? val['dateKey'] ?? val['createdAt'] ?? val['timestamp']);
        if (dt == null) continue;
        final m = getMonthIndex(dt);
        if (m >= 0 && m < months) {
          tokenList[m]++;
          final type = (val['queueType'] ?? val['category'] ?? val['type'] ?? '').toString().toLowerCase();
          final days = (val['daysOfMedicine'] as num?)?.toInt() ?? 1;
          if (type.contains('zakat') && !type.contains('non')) {
            revList[m] += 20 * days;
          } else if (type.contains('non-zakat') || type.contains('nonzakat') || type.contains('non_zakat')) {
            revList[m] += 100 * days;
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Error computing entries in chart points: $e');
  }

  // Single pass 3: Food tokens
  try {
    if (!Hive.isBoxOpen(LocalStorageService.dasterkhwaanTokensBox)) {
      await LocalStorageService.openBoxSafe(LocalStorageService.dasterkhwaanTokensBox);
    }
    if (Hive.isBoxOpen(LocalStorageService.dasterkhwaanTokensBox)) {
      final tokenBox = Hive.box(LocalStorageService.dasterkhwaanTokensBox);
      var scanned = 0;
      for (final raw in tokenBox.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (raw is! Map) continue;
        final status = raw['status']?.toString().toLowerCase();
        final syncStatus = raw['syncStatus']?.toString().toLowerCase();
        if (status == 'deleted' || status == 'void' || syncStatus == 'deleted') continue;

        final b = (raw['branchId'] as String? ?? '').toLowerCase().trim();
        if (b.isNotEmpty && !isTargetBranch(b)) continue;

        final dt = _tryParseChartDate(raw['date'] ?? raw['dateKey'] ?? raw['createdAt'] ?? raw['timestamp'] ?? raw['time']);
        if (dt == null) continue;
        final m = getMonthIndex(dt);
        if (m >= 0 && m < months) {
          tokenList[m]++;
        }
      }
    }
  } catch (e) {
    debugPrint('Error computing food tokens in chart points: $e');
  }

  // Single pass 4: Employee attendance
  try {
    if (Hive.isBoxOpen('finance_attendance')) {
      final attBox = Hive.box('finance_attendance');
      var scanned = 0;
      for (final k in attBox.keys.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        final kStr = k.toString();
        if (kStr.length >= 10) {
          final dateStr = kStr.substring(0, 10);
          final dt = DateTime.tryParse(dateStr);
          if (dt != null) {
            final m = getMonthIndex(dt);
            if (m >= 0 && m < months) {
              final val = attBox.get(k);
              if (val is List) {
                int dayPresent = 0;
                for (final a in val) {
                  if (a is Map) {
                    final b = (a['branchId'] as String? ?? '').toLowerCase().trim();
                    if (isTargetBranch(b) && a['status'] == 'present') {
                      dayPresent++;
                    }
                  }
                }
                if (dayPresent > 0) {
                  monthEmpDayCounts[m][dateStr] = (monthEmpDayCounts[m][dateStr] ?? 0) + dayPresent;
                }
              }
            }
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Error computing attendance in chart points: $e');
  }

  final points = List.generate(months, (m) {
    final empCounts = monthEmpDayCounts[m];
    final empAvg = empCounts.isEmpty
        ? 0
        : (empCounts.values.reduce((a, b) => a + b) / empCounts.length).round();
    return HomeLineChartPoint(
      date: endOfMonths[m],
      patientsRevenue: revList[m],
      donations: donList[m],
      tokens: tokenList[m],
      employeesPresent: empAvg,
    );
  });

  _chartPointsMemoryCache[cacheKey] = (now, points);
  return points;
}

Future<Map<String, int>> fetchWeeklyPatientCounts(List<String> branchIds) async {
  final result = <String, int>{for (final b in branchIds) b: 0};
  if (branchIds.isEmpty) return result;

  final now = DateTime.now();
  final startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

  try {
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final box = Hive.box(LocalStorageService.entriesBox);
      var scanned = 0;
      for (final val in box.values.toList()) {
        if (++scanned % _scanSlice == 0) await _breathe();
        if (val is! Map) continue;
        final status = val['status']?.toString().toLowerCase();
        final syncStatus = val['syncStatus']?.toString().toLowerCase();
        if (status == 'deleted' || syncStatus == 'deleted' || status == 'void' || status == 'cancelled') continue;

        final dt = _tryParseChartDate(val['date'] ?? val['dateKey'] ?? val['createdAt'] ?? val['timestamp']);
        if (dt == null || dt.isBefore(startDate) || dt.isAfter(endDate)) continue;

        final cat = (val['queueType'] ?? val['category'] ?? val['type'] ?? '').toString().toLowerCase();
        if (!cat.contains('zakat') && !cat.contains('gmwf')) continue;

        final docBranch = (val['branchId'] as String? ?? '').toLowerCase().trim();
        for (final targetId in branchIds) {
          if (_isMatchingBranch(docBranch, targetId)) {
            result[targetId] = (result[targetId] ?? 0) + 1;
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Error computing weekly patient counts: $e');
  }

  // Also check if any branches have 0 in entries and have cached historical entries in LocalStorageService
  for (final branchId in branchIds) {
    if ((result[branchId] ?? 0) == 0) {
      int branchCachedTotal = 0;
      for (int i = 0; i < 7; i++) {
        final d = now.subtract(Duration(days: i));
        final dmyy = DateFormat('ddMMyy').format(d);
        final cachedDocs = LocalStorageService.getBranchDayCache(branchId, dmyy, 'dispensary');
        if (cachedDocs != null) {
          for (final c in cachedDocs) {
            final t = c['type']?.toString().toLowerCase() ?? '';
            if (t == 'zakat' || t == 'non-zakat' || t == 'gmwf') {
              branchCachedTotal++;
            }
          }
        }
      }
      if (branchCachedTotal > 0) {
        result[branchId] = branchCachedTotal;
      }
    }
  }

  return result;
}

/// Keeps the [limit] newest of the values offered to it, without holding or sorting the rest.
class _NewestFirst<T> {
  final int limit;
  final List<MapEntry<DateTime, T>> _items = [];
  DateTime? _cutoff;
  _NewestFirst(this.limit);

  void offer(DateTime at, T value) {
    if (limit <= 0) return;
    if (_cutoff != null && !at.isAfter(_cutoff!)) return;
    _items.add(MapEntry(at, value));
    if (_items.length >= limit * 2 + 16) _trim();
  }

  void _trim() {
    _items.sort((a, b) => b.key.compareTo(a.key));
    if (_items.length > limit) _items.removeRange(limit, _items.length);
    if (_items.length == limit) _cutoff = _items.last.key;
  }

  List<T> take() {
    _trim();
    return [for (final e in _items) e.value];
  }
}
