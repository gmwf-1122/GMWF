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
import '../widgets/dashboard_widgets.dart';
import 'local_storage_service.dart';
import 'donations_local_storage.dart';
import 'finance_local_storage.dart';
import '../pages/madrassa/utils/madrassa_local_storage.dart';

/// Indefinite cache for historical (non-today) BranchStats.
/// Keyed by "branchId|yyyy-MM-dd".
final Map<String, BranchStats> _historicalStatsCache = {};

String _dayKey(String branchId, DateTime day) =>
    '${branchId.toLowerCase().trim()}|${DateFormat('yyyy-MM-dd').format(day)}';

/// Computes branch statistics from local Hive data (local_entries, local_donations, and historical branch cache).
/// Falls back to Firestore only if local data is completely empty, with a short timeout.
Future<BranchStats> fetchLocalBranchStats(String branchId, DateTime date) async {
  final bId = branchId.toLowerCase().trim();
  final dateKeyYmd = DateFormat('yyyy-MM-dd').format(date);
  final dateKeyDmyy = DateFormat('ddMMyy').format(date);

  // 1. Calculate donations from DonationsLocalStorage
  int donTotal = 0;
  try {
    if (Hive.isBoxOpen(DonationsLocalStorage.donationsBox)) {
      final donBox = Hive.box(DonationsLocalStorage.donationsBox);
      for (final val in donBox.values) {
        if (val is Map) {
          final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
          final d = val['date']?.toString();
          if (b == bId && d == dateKeyYmd) {
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
      for (final val in box.values) {
        if (val is Map) {
          final b = (val['branchId'] as String? ?? '').toLowerCase().trim();
          final dk = val['dateKey']?.toString();
          if (b == bId && dk == dateKeyDmyy) {
            final type = val['queueType']?.toString().toLowerCase();
            final days = (val['daysOfMedicine'] as num?)?.toInt() ?? 1;
            final status = val['status']?.toString().toLowerCase();

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
            } else if (type == 'dasterkhwan') {
              das++;
            }

            if (status == 'dispensed' || status == 'completed') {
              dispensed++;
            }
          }
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

  // 3. Fallback to Firestore with a short timeout if local data yields empty stats
  if (z == 0 && nz == 0 && donTotal == 0) {
    try {
      final remoteStats = await fetchBranchStats(branchId, filter: DashboardFilter(
        timeRange: TimeRange.custom,
        customRange: DateTimeRange(start: date, end: date),
      )).timeout(const Duration(milliseconds: 1500));
      return BranchStats(
        zakat: remoteStats.zakat,
        nonZakat: remoteStats.nonZakat,
        gmwf: remoteStats.gmwf,
        dispensed: remoteStats.dispensed,
        prescribed: madrassaAttendance,
        dasterkhwaan: remoteStats.dasterkhwaan,
        dasterkhwaanServed: remoteStats.dasterkhwaanServed,
        donations: remoteStats.donations,
        dispensaryRevenue: remoteStats.dispensaryRevenue,
        zakatRevenue: remoteStats.zakatRevenue,
        nonZakatRevenue: remoteStats.nonZakatRevenue,
        gmwfRevenue: remoteStats.gmwfRevenue,
      );
    } catch (_) {
      // Ignore timeout/error and return whatever local metrics we gathered
    }
  }

  return BranchStats(
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
  );
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
  for (final r in results) {
    z += r.zakat; nz += r.nonZakat; gm += r.gmwf;
    das += r.dasterkhwaan; dasServed += r.dasterkhwaanServed;
    don += r.donations; disp += r.dispensed; presc += r.prescribed;
    dispRev += r.dispensaryRevenue;
    zRev += r.zakatRevenue; nzRev += r.nonZakatRevenue; gmRev += r.gmwfRevenue;
  }
  return BranchStats(
    zakat: z, nonZakat: nz, gmwf: gm,
    dasterkhwaan: das, dasterkhwaanServed: dasServed,
    donations: don, dispensed: disp, prescribed: presc,
    dispensaryRevenue: dispRev,
    zakatRevenue: zRev, nonZakatRevenue: nzRev, gmwfRevenue: gmRev,
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
    
    // 1. Fetch local donations
    final donBox = Hive.box(DonationsLocalStorage.donationsBox);
    for (final key in donBox.keys) {
      final raw = donBox.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
      if (branchId != null && bId != branchId.toLowerCase().trim()) continue;

      final dtStr = data['timestamp'] ?? data['lastUpdatedAt'] ?? data['date'];
      DateTime dt = DateTime.now();
      if (dtStr != null) {
        dt = DateTime.tryParse(dtStr.toString()) ?? DateTime.now();
      }
      
      final donor = data['donorName']?.toString() ?? 'Valued Donor';
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

    // 2. Fetch local token registrations
    final entriesBox = Hive.box(LocalStorageService.entriesBox);
    for (final key in entriesBox.keys) {
      final raw = entriesBox.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      final bId = (data['branchId'] as String? ?? '').toLowerCase().trim();
      if (branchId != null && bId != branchId.toLowerCase().trim()) continue;

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

    // Sort descending by timestamp
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  static List<String> getAllBranchIds() {
    final box = Hive.box(LocalStorageService.branchesBox);
    final ids = box.keys
        .where((k) => k.toString().startsWith('branch:'))
        .map((k) => k.toString().replaceFirst('branch:', '').toLowerCase().trim())
        .where((id) => id.isNotEmpty && id != 'all')
        .toList();
    if (ids.isEmpty) {
      return ['gujrat'];
    }
    return ids;
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

  final List<HomeLineChartPoint> points = [];

  for (int i = 0; i < weeks; i++) {
    final endOfWeek = today.subtract(Duration(days: (weeks - 1 - i) * 7));
    final startOfWeek = endOfWeek.subtract(const Duration(days: 6));

    int totalRevenue = 0;
    int totalDonations = 0;
    int totalTokens = 0;
    int totalEmployeesPresent = 0;

    for (int d = 0; d < 7; d++) {
      final date = startOfWeek.add(Duration(days: d));
      final results = await Future.wait(branchIds.map((id) => fetchHistoricalDayStats(id, date)));
      final combined = combineBranchStats(results);

      totalRevenue += combined.dispensaryRevenue;
      totalDonations += combined.donations;
      totalTokens += combined.zakat + combined.nonZakat + combined.gmwf + combined.dasterkhwaan;

      // Compute employees present for this date
      int presentEmployees = 0;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      for (final id in branchIds) {
        try {
          final atts = FinanceLocalStorage.getAttendanceForDate(id, dateStr);
          for (final att in atts) {
            if (att['status'] == 'present') {
              presentEmployees++;
            }
          }
        } catch (_) {}
      }
      totalEmployeesPresent += presentEmployees;
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