// lib/services/home_dashboard_service.dart
//
// Data-layer helpers for the new "Home" snapshot dashboard.
// Adds yesterday-vs-today comparisons, time-series revenue series,
// and recent activity feed.
//
// Yesterday's data is historical/immutable, so — unlike the 5-minute TTL
// cache used for "today" — we cache it indefinitely per branch+date.

import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/dashboard_widgets.dart';
import 'local_storage_service.dart';
import 'camp_session_service.dart';
import 'donations_local_storage.dart';
import 'finance_local_storage.dart';
import '../pages/madrassa/utils/madrassa_local_storage.dart';

/// Indefinite cache for historical (non-today) BranchStats.
/// Keyed by "branchId|yyyy-MM-dd".
final Map<String, BranchStats> _historicalStatsCache = {};
final Map<String, _CachedLocalBranchStats> _localStatsTTLCache = {};

class _CachedLocalBranchStats {
  final BranchStats stats;
  final DateTime cachedAt;
  _CachedLocalBranchStats(this.stats) : cachedAt = DateTime.now();

  bool get isValid => DateTime.now().difference(cachedAt).inSeconds < 5;
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

bool _isMatchingBranch(String docBranchId, String targetBranchId) {
  final b1 = docBranchId.toLowerCase().trim();
  final b2 = targetBranchId.toLowerCase().trim();
  if (b2 == 'all' || b2 == 'hq' || b2 == 'gujrat') return true;
  return b1 == b2 || b1.isEmpty || b1 == 'all';
}

/// Computes branch statistics from local Hive data (local_entries, local_donations, and historical branch cache).
/// Falls back to Firestore only if local data is completely empty, with a short timeout.
Future<BranchStats> fetchLocalBranchStats(String branchId, DateTime date) async {
  final bId = branchId.toLowerCase().trim();
  final dateKeyYmd = DateFormat('yyyy-MM-dd').format(date);
  final cacheTTLKey = '$bId|$dateKeyYmd';

  if (_localStatsTTLCache.containsKey(cacheTTLKey) && _localStatsTTLCache[cacheTTLKey]!.isValid) {
    return _localStatsTTLCache[cacheTTLKey]!.stats;
  }

  final dateKeyDmyy = DateFormat('ddMMyy').format(date);

  // 1. Calculate donations from DonationsLocalStorage
  int donTotal = 0;
  try {
    if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
      final donBox = Hive.box(DonationsLocalStorage.donationsBox);
      for (final val in donBox.values) {
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

  // 2. Calculate tokens & dispensary revenue
  int z = 0, nz = 0, gm = 0, das = 0, served = 0, dispensed = 0, dispRev = 0;
  int zRev = 0, nzRev = 0, gmRev = 0;

  try {
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final box = Hive.box(LocalStorageService.entriesBox);
      final Map<String, Map<String, dynamic>> entryMap = {};

      for (final k in box.keys) {
        final val = box.get(k);
        if (val is Map) {
          final e = Map<String, dynamic>.from(val);
          final status = e['status']?.toString().toLowerCase();
          final syncStatus = e['syncStatus']?.toString().toLowerCase();
          if (status == 'deleted' || syncStatus == 'deleted') continue;

          final b = (e['branchId'] as String? ?? '').toLowerCase().trim();
          final dk = e['dateKey']?.toString();
          if ((bId == 'all' || b == bId) && dk == dateKeyDmyy) {
            final rawSerial = (e['serial'] ?? e['id'] ?? e['tokenNumber'] ?? k).toString().trim().toLowerCase();
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

        if (type.contains('zakat') && !type.contains('non')) {
          z++;
          final rev = 20 * days;
          dispRev += rev;
          zRev += rev;
        } else if (type.contains('non-zakat') || type.contains('nonzakat') || type.contains('non_zakat')) {
          nz++;
          final rev = 100 * days;
          dispRev += rev;
          nzRev += rev;
        } else if (type.contains('gmwf')) {
          gm++;
        } else if (type.contains('dasterkhwan')) {
          das++;
        }

        if (status == 'dispensed' || status == 'completed') {
          dispensed++;
        }
      }
    }
  } catch (e) {
    debugPrint('Error reading local entries: $e');
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
      for (final key in box.keys) {
        final keyStr = key.toString();
        if (keyStr.endsWith('_$dateKeyEmp') || keyStr.endsWith(dateKeyEmp)) {
          final val = box.get(key);
          if (val is Map) {
            final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
            if (bId == 'all' || b == bId || b.isEmpty) {
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

  // If all local numbers are 0 (e.g. fresh Chrome Web session without offline Hive storage), attempt a quick Firestore fetch
  if (z == 0 && nz == 0 && donTotal == 0 && dispRev == 0 && empAttendance == 0) {
    try {
      final fsRes = await _fetchFirestoreBranchStats(bId, date);
      if (fsRes != null) {
        res = fsRes;
      }
    } catch (_) {}
  }

  _localStatsTTLCache[cacheTTLKey] = _CachedLocalBranchStats(res);
  return res;
}

Future<BranchStats?> _fetchFirestoreBranchStats(String branchId, DateTime date) async {
  try {
    final bId = branchId.toLowerCase().trim();
    final dateKeyYmd = DateFormat('yyyy-MM-dd').format(date);
    final dateKeyDmyy = DateFormat('ddMMyy').format(date);
    int donTotal = 0;
    int empAtt = 0;
    int z = 0, nz = 0, gm = 0, das = 0, dispensed = 0, dispRev = 0;
    int zRev = 0, nzRev = 0, gmRev = 0;

    // 1. Donations
    try {
      final donSnap = await FirebaseFirestore.instance
          .collection('branches').doc(bId).collection('donations')
          .where('date', isGreaterThanOrEqualTo: dateKeyYmd)
          .where('date', isLessThanOrEqualTo: dateKeyYmd)
          .get()
          .timeout(const Duration(milliseconds: 1500));
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

    // Fallback: try top-level donations collection if branch-level found nothing
    if (donTotal == 0) {
      try {
        final donSnap = await FirebaseFirestore.instance
            .collection('donations')
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in donSnap.docs) {
          final val = doc.data();
          final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
          final d = val['date'] ?? val['createdAt'] ?? val['timestamp'];
          if (_isMatchingBranch(b, bId) && _isSameDate(d, dateKeyYmd, dateKeyDmyy)) {
            final status = val['status']?.toString().toLowerCase();
            if (status == 'deleted') continue;
            final amt = val['amount'];
            final amtDouble = (amt is num) ? amt.toDouble() : (double.tryParse(amt?.toString() ?? '0') ?? 0.0);
            donTotal += amtDouble.toInt();
          }
        }
      } catch (_) {}
    }

    // 2. Serials (zakat, non-zakat, gmwf) + dispensary + dasterkhwaan
    try {
      final base = FirebaseFirestore.instance
          .collection('branches').doc(bId).collection('serials').doc(dateKeyDmyy);

      final results = await Future.wait([
        base.collection('zakat').get(),
        base.collection('non-zakat').get(),
        base.collection('gmwf').get(),
        base.collection('dasterkhwan').get(),
        FirebaseFirestore.instance.collection('branches/$bId/dispensary/$dateKeyDmyy/$dateKeyDmyy').get(),
      ]).timeout(const Duration(seconds: 6));

      // Zakat patients
      for (final doc in (results[0] as QuerySnapshot).docs) {
        z++;
        final d = (doc.data() as Map<String, dynamic>?)?['daysOfMedicine'] as num? ?? 1;
        final rev = 20 * d.toInt();
        dispRev += rev;
        zRev += rev;
      }

      // Non-zakat patients
      for (final doc in (results[1] as QuerySnapshot).docs) {
        nz++;
        final d = (doc.data() as Map<String, dynamic>?)?['daysOfMedicine'] as num? ?? 1;
        final rev = 100 * d.toInt();
        dispRev += rev;
        nzRev += rev;
      }

      // GMWF patients
      gm = (results[2] as QuerySnapshot).size;

      // Dasterkhwaan tokens
      das = (results[3] as QuerySnapshot).size;

      // Dispensed patients
      dispensed = (results[4] as QuerySnapshot).size;
    } catch (_) {}

    // Fallback: check branches/$bId/entries collection if serials subcollection was empty
    if (z == 0 && nz == 0 && gm == 0) {
      try {
        final entriesSnap = await FirebaseFirestore.instance
            .collection('branches').doc(bId).collection('entries')
            .where('dateKey', isEqualTo: dateKeyYmd)
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in entriesSnap.docs) {
          final data = doc.data();
          final status = data['status']?.toString().toLowerCase();
          if (status == 'deleted' || status == 'void' || status == 'cancelled') continue;
          final cat = (data['category'] ?? data['queueType'] ?? data['type'] ?? 'zakat').toString().toLowerCase();
          final d = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
          if (cat.contains('non')) {
            nz++;
            final rev = 100 * d;
            dispRev += rev;
            nzRev += rev;
          } else if (cat.contains('gmwf')) {
            gm++;
          } else {
            z++;
            final rev = 20 * d;
            dispRev += rev;
            zRev += rev;
          }
        }
      } catch (_) {}
    }

    // 3. Employee attendance (rough count)
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('branchId', isEqualTo: bId)
          .get()
          .timeout(const Duration(seconds: 4));
      empAtt = userSnap.docs.length;
    } catch (_) {}

    return BranchStats(
      zakat: z,
      nonZakat: nz,
      gmwf: gm,
      dispensed: dispensed,
      prescribed: 0,
      dasterkhwaan: das,
      dasterkhwaanServed: 0,
      donations: donTotal,
      dispensaryRevenue: dispRev,
      zakatRevenue: zRev,
      nonZakatRevenue: nzRev,
      gmwfRevenue: gmRev,
      employeeAttendance: empAtt,
    );
  } catch (_) {
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
    List<String> ids) async {
  if (ids.isEmpty) return {};
  final yesterday = DateTime.now().subtract(const Duration(days: 1));

  final todayResults = await Future.wait(ids.map((id) => fetchLocalBranchStats(id, DateTime.now())));
  final yestResults = await Future.wait(ids.map((id) => fetchLocalBranchStats(id, yesterday)));

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
}

Future<KarachiCampBreakdown> fetchKarachiCampBreakdown([DateTime? date]) async {
  _localStatsTTLCache.clear();
  final targetDate = date ?? DateTime.now();
  final ymd = DateFormat('yyyy-MM-dd').format(targetDate);
  final dmyy = DateFormat('ddMMyy').format(targetDate);

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

  // 1. Local entries across all possible Hive keys
  try {
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final box = Hive.box(LocalStorageService.entriesBox);
      for (final k in box.keys) {
        final val = box.get(k);
        if (val is Map) {
          final e = Map<String, dynamic>.from(val);
          final b = (e['branchId'] ?? '').toString().toLowerCase().trim();
          final kStr = k.toString().toLowerCase();
          if (b.isEmpty || b == 'all' || b.contains('karachi') || b.contains('haji') || b.contains('kapaya') || b.contains('saddar') ||
              kStr.contains('karachi') || kStr.contains('haji') || kStr.contains('kapaya') || kStr.contains('saddar')) {
            addEntryIfValid(e, k);
          }
        }
      }
    }
  } catch (_) {}

  // 2. Cloud entries fallback only if local entries were not found
  if (entryMap.isEmpty) {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc('karachi')
          .collection('entries')
          .where('dateKey', isEqualTo: ymd)
          .limit(500)
          .get()
          .timeout(const Duration(seconds: 4));

      for (final doc in snap.docs) {
        addEntryIfValid(doc.data(), doc.id);
      }
    } catch (_) {}
  }

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

    final sTag = e['session']?.toString().toLowerCase().trim();
    bool isEvening = sTag == 'evening';
    if (sTag == null || sTag.isEmpty) {
      final rawTime = e['timestamp'] ?? e['createdAt'] ?? e['date'];
      if (rawTime != null) {
        try {
          final dt = DateTime.parse(rawTime.toString());
          isEvening = dt.hour >= 14;
        } catch (_) {
          isEvening = false;
        }
      }
    }

    final cat = (e['category'] ?? e['queueType'] ?? e['type'] ?? '').toString().toLowerCase().trim();
    final isZakat = cat.contains('zakat') && !cat.contains('non');
    final isNonZakat = cat.contains('non-zakat') || cat.contains('nonzakat') || cat.contains('non_zakat');

    final feeVal = e['fee'] ?? e['tokenFee'] ?? e['amount'] ?? e['price'] ?? e['dispensaryRevenue'];
    int eRev = 0;
    if (feeVal != null && (feeVal is num || double.tryParse(feeVal.toString()) != null)) {
      eRev = (feeVal is num ? feeVal.toInt() : double.tryParse(feeVal.toString())?.toInt() ?? 0);
    } else {
      final daysRaw = e['daysOfMedicine'] ?? 1;
      final days = (daysRaw is num ? daysRaw.toInt() : int.tryParse(daysRaw.toString()) ?? 1);
      if (isZakat) eRev = 20 * days;
      else if (isNonZakat) eRev = 100 * days;
      else eRev = 20 * days; // Default Karachi token fee
    }

    if (isExplicitHaji) {
      hajiRev += eRev;
      if (isEvening) {
        if (isZakat) hajiEZ++; else if (isNonZakat) hajiENZ++; else hajiEGM++;
      } else {
        if (isZakat) hajiMZ++; else if (isNonZakat) hajiMNZ++; else hajiMGM++;
      }
    } else {
      // All other Karachi patient data attributes to Saddar (Kapaya) Camp
      kapayaRev += eRev;
      if (isEvening) {
        if (isZakat) kapayaEZ++; else if (isNonZakat) kapayaENZ++; else kapayaEGM++;
      } else {
        if (isZakat) kapayaMZ++; else if (isNonZakat) kapayaMNZ++; else kapayaMGM++;
      }
    }
  }

  final hajiZ = hajiMZ + hajiEZ;
  final hajiNZ = hajiMNZ + hajiENZ;
  final hajiGM = hajiMGM + hajiEGM;

  final kapayaZ = kapayaMZ + kapayaEZ;
  final kapayaNZ = kapayaMNZ + kapayaENZ;
  final kapayaGM = kapayaMGM + kapayaEGM;

  return KarachiCampBreakdown(
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
    final box = Hive.box(LocalStorageService.branchesBox);
    final cached = box.get('branch:${branchId.toLowerCase().trim()}');
    if (cached is Map) {
      return (cached['name'] as String?) ?? branchId;
    }
    if (branchId.isEmpty) return 'Global';
    return branchId[0].toUpperCase() + branchId.substring(1);
  }

  static List<RecentActivity> getRecentActivity({String? branchId, int limit = 20}) {
    final list = <RecentActivity>[];
    final targetBranch = (branchId ?? '').toLowerCase().trim();
    
    // 1. Fetch local donations
    if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
      final donBox = Hive.box(DonationsLocalStorage.donationsBox);
      for (final key in donBox.keys) {
        final raw = donBox.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
        if (targetBranch.isNotEmpty && targetBranch != 'all' && targetBranch != 'global' && !_isMatchingBranch(bId, targetBranch)) continue;

        final dtStr = data['timestamp'] ?? data['lastUpdatedAt'] ?? data['date'];
        DateTime dt = DateTime.now();
        if (dtStr != null) {
          dt = DateTime.tryParse(dtStr.toString()) ?? DateTime.now();
        }
        
        final donor = data['donorName']?.toString() ?? 'Walk-in Donor';
        final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final rcpt = data['receiptNo']?.toString() ?? '';
        
        list.add(RecentActivity(
          id: 'don_${data['localId'] ?? key}',
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
    }

    // 2. Fetch local dispensary token / patient registrations
    if (Hive.isBoxOpen(LocalStorageService.dispensaryBox)) {
      final dispBox = Hive.box(LocalStorageService.dispensaryBox);
      for (final key in dispBox.keys) {
        final raw = dispBox.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
        if (targetBranch.isNotEmpty && targetBranch != 'all' && targetBranch != 'global' && !_isMatchingBranch(bId, targetBranch)) continue;

        final dtStr = data['createdAt'] ?? data['timestamp'] ?? data['date'];
        DateTime dt = DateTime.now();
        if (dtStr != null) {
          dt = DateTime.tryParse(dtStr.toString()) ?? DateTime.now();
        }

        final serial = data['serial']?.toString() ?? key.toString();
        final pName = data['patientName']?.toString() ?? data['name']?.toString() ?? 'Patient';
        final qType = (data['queueType'] ?? data['category'] ?? 'zakat').toString().toUpperCase();
        final status = data['status']?.toString() ?? 'issued';

        list.add(RecentActivity(
          id: 'disp_${data['id'] ?? key}',
          title: 'Patient Token #$serial',
          subtitle: 'Patient: $pName ($qType)',
          timestamp: dt,
          type: 'token',
          branchId: bId,
          branchName: resolveBranchName(bId),
          status: status,
        ));
      }
    }

    // 3. Fetch local token entries box
    if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      for (final key in entriesBox.keys) {
        final raw = entriesBox.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
        if (targetBranch.isNotEmpty && targetBranch != 'all' && targetBranch != 'global' && !_isMatchingBranch(bId, targetBranch)) continue;

        final dtStr = data['createdAt'] ?? data['timestamp'];
        DateTime dt = DateTime.now();
        if (dtStr != null) {
          dt = DateTime.tryParse(dtStr.toString()) ?? DateTime.now();
        }

        final serial = data['serial']?.toString() ?? '';
        final pName = data['patientName']?.toString() ?? 'Unknown Patient';
        final qType = (data['queueType'] as String? ?? 'zakat').toUpperCase();
        final status = data['status']?.toString() ?? 'issued';

        list.add(RecentActivity(
          id: 'tok_${data['id'] ?? key}',
          title: 'Token #$serial Issued',
          subtitle: 'Patient: $pName ($qType)',
          timestamp: dt,
          type: 'token',
          branchId: bId,
          branchName: resolveBranchName(bId),
          status: status,
        ));
      }
    }

    // Sort descending by timestamp
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
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
        final entriesSnap = await FirebaseFirestore.instance
            .collectionGroup('entries')
            .limit(limit)
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in entriesSnap.docs) {
          final data = doc.data();
          final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
          if (branchId != null && bId != branchId.toLowerCase().trim() && branchId != 'all') continue;

          final dtStr = data['createdAt'] ?? data['timestamp'];
          DateTime dt = DateTime.now();
          if (dtStr != null) {
            dt = DateTime.tryParse(dtStr.toString()) ?? DateTime.now();
          }

          final serial = data['serial']?.toString() ?? doc.id;
          final pName = data['patientName']?.toString() ?? 'Unknown Patient';
          final qType = (data['queueType'] as String? ?? 'zakat').toUpperCase();
          final status = data['status']?.toString() ?? 'issued';

          list.add(RecentActivity(
            id: 'tok_${doc.id}',
            title: 'Token #$serial Issued',
            subtitle: 'Patient: $pName ($qType)',
            timestamp: dt,
            type: 'token',
            branchId: bId,
            branchName: resolveBranchName(bId),
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

  static List<String> getAllBranchIds() {
    final Set<String> idsSet = {'karachi', 'sialkot', 'gujrat', 'jalalpur_jattan', 'rawalpindi'};
    void addBranchId(String raw) {
      final norm = raw.toLowerCase().trim();
      if (norm.isEmpty || norm == 'all' || norm == 'unknown') return;
      if (norm.contains('karachi') || norm.contains('haji') || norm.contains('kapaya') || norm.contains('saddar')) {
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

Future<List<HomeLineChartPoint>> fetchChartPoints(List<String> branchIds, {int weeks = 5}) async {
  if (branchIds.isEmpty) return [];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final weekFutures = List.generate(weeks, (i) async {
    final endOfWeek = today.subtract(Duration(days: (weeks - 1 - i) * 7));
    final startOfWeek = endOfWeek.subtract(const Duration(days: 6));

    final dayFutures = List.generate(7, (d) async {
      final date = startOfWeek.add(Duration(days: d));
      final results = await Future.wait(branchIds.map((id) => fetchHistoricalDayStats(id, date)));
      final combined = combineBranchStats(results);

      int presentEmployees = 0;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      for (final id in branchIds) {
        try {
          final atts = FinanceLocalStorage.getAttendanceForDate(id, dateStr);
          for (final att in atts) {
            if (att['status'] == 'present') presentEmployees++;
          }
        } catch (_) {}
      }

      return _DayPointData(
        revenue: combined.dispensaryRevenue,
        donations: combined.donations,
        tokens: combined.zakat + combined.nonZakat + combined.gmwf + combined.dasterkhwaan,
        employeesPresent: presentEmployees,
      );
    });

    final daysData = await Future.wait(dayFutures);

    int totalRevenue = 0, totalDonations = 0, totalTokens = 0, totalEmployeesPresent = 0;
    for (final dd in daysData) {
      totalRevenue += dd.revenue;
      totalDonations += dd.donations;
      totalTokens += dd.tokens;
      totalEmployeesPresent += dd.employeesPresent;
    }

    return HomeLineChartPoint(
      date: endOfWeek,
      patientsRevenue: totalRevenue,
      donations: totalDonations,
      tokens: totalTokens,
      employeesPresent: (totalEmployeesPresent / 7).round(),
    );
  });

  return await Future.wait(weekFutures);
}

Future<List<HomeLineChartPoint>> fetchLocalChartPoints(List<String> branchIds, {int weeks = 5}) async {
  if (branchIds.isEmpty) return [];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final List<HomeLineChartPoint> points = [];

  for (int i = 0; i < weeks; i++) {
    final endOfWeek = today.subtract(Duration(days: (weeks - 1 - i) * 7));
    final startOfWeek = endOfWeek.subtract(const Duration(days: 6));

    int totalRevenue = 0, totalDonations = 0, totalTokens = 0, totalEmployeesPresent = 0;

    for (int d = 0; d < 7; d++) {
      final date = startOfWeek.add(Duration(days: d));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      for (final id in branchIds) {
        final stats = await fetchLocalBranchStats(id, date);
        totalRevenue += stats.dispensaryRevenue;
        totalDonations += stats.donations;
        totalTokens += stats.zakat + stats.nonZakat + stats.gmwf + stats.dasterkhwaan;

        try {
          final atts = FinanceLocalStorage.getAttendanceForDate(id, dateStr);
          for (final att in atts) {
            if (att['status'] == 'present') totalEmployeesPresent++;
          }
        } catch (_) {}
      }
    }

    points.add(HomeLineChartPoint(
      date: endOfWeek,
      patientsRevenue: totalRevenue,
      donations: totalDonations,
      tokens: totalTokens,
      employeesPresent: (totalEmployeesPresent / 7).round(),
    ));
  }

  return points;
}

class _DayPointData {
  final int revenue;
  final int donations;
  final int tokens;
  final int employeesPresent;
  const _DayPointData({required this.revenue, required this.donations, required this.tokens, required this.employeesPresent});
}