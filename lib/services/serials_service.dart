import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:hive/hive.dart';

List<String> _dateStrings(DateTime start, DateTime end) {
  final df   = DateFormat('ddMMyy');
  final days = <String>[];
  for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
    days.add(df.format(d));
  }
  return days;
}

Future<Map<String, int>> _getDailySerialsSummary(String branchId, String ds, String todayKey) async {
  final normBranchId = branchId.toLowerCase().trim();
  final cacheKey = 'v1|$normBranchId|$ds|serials_summary';
  
  if (ds != todayKey) {
    try {
      if (!Hive.isBoxOpen('branch_data_cache')) {
        await Hive.openBox('branch_data_cache');
      }
      final box = Hive.box('branch_data_cache');
      final cached = box.get(cacheKey);
      if (cached is Map) {
        return Map<String, int>.from(cached.cast<String, int>());
      }
    } catch (_) {}
  }
  
  // Fetch from Firestore
  int pending = 0;
  int dispensed = 0;
  int zakatCount = 0;
  int nonZakatCount = 0;
  int gmwfCount = 0;
  int zakatRevenue = 0;
  int nonZakatRevenue = 0;
  int prescWaiting = 0;
  int prescPrescribed = 0;
  int dispPending = 0;
  int dispDispensed = 0;
  
  final queues = ['zakat', 'non-zakat', 'gmwf'];
  final futures = queues.map((q) => FirebaseFirestore.instance
      .collection('branches/$normBranchId/serials/$ds/$q')
      .get());
      
  final snaps = await Future.wait(futures);
  for (int i = 0; i < 3; i++) {
    final q = queues[i];
    final snap = snaps[i];
    final count = snap.size;
    if (q == 'zakat') zakatCount += count;
    if (q == 'non-zakat') nonZakatCount += count;
    if (q == 'gmwf') gmwfCount += count;
    
    for (final doc in snap.docs) {
      final data = doc.data();
      final daysOfMedicine = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
      if (q == 'zakat') {
        zakatRevenue += 20 * daysOfMedicine;
      } else if (q == 'non-zakat') {
        nonZakatRevenue += 100 * daysOfMedicine;
      }
      
      final status = (data['status'] ?? '').toString().toLowerCase().trim();
      final dispenseStatus = (data['dispenseStatus'] ?? '').toString().toLowerCase().trim();
      
      if (status == 'completed') {
        dispensed++;
        prescPrescribed++;
        if (dispenseStatus == 'dispensed') {
          dispDispensed++;
        } else {
          dispPending++;
        }
      } else {
        pending++;
        prescWaiting++;
      }
    }
  }
  
  final daySummary = {
    'v1': zakatCount,
    'v1_sub': zakatRevenue,
    'v2': nonZakatCount,
    'v2_sub': nonZakatRevenue,
    'v3': gmwfCount,
    'v3_sub': 0,
    'total': zakatCount + nonZakatCount + gmwfCount,
    'revenue': zakatRevenue + nonZakatRevenue,
    'pending': pending,
    'dispensed': dispensed,
    'presc_waiting': prescWaiting,
    'presc_prescribed': prescPrescribed,
    'disp_pending': dispPending,
    'disp_dispensed': dispDispensed,
  };
  
  if (ds != todayKey) {
    try {
      if (!Hive.isBoxOpen('branch_data_cache')) {
        await Hive.openBox('branch_data_cache');
      }
      final box = Hive.box('branch_data_cache');
      await box.put(cacheKey, daySummary);
    } catch (_) {}
  }
  
  return daySummary;
}

Stream<Map<String, int>> serialsCountStream(String branchId, DateTime start, DateTime end) {
  final normBranchId = branchId.toLowerCase().trim();
  final days = _dateStrings(start, end);
  final todayKey = DateFormat('ddMMyy').format(DateTime.now());
  
  final hasToday = days.contains(todayKey);
  final pastDays = days.where((d) => d != todayKey).toList();
  
  // Get past days' total static summary sequentially to avoid saturating Firestore
  final Future<Map<String, int>> pastSummaryFuture = () async {
    final summaries = <Map<String, int>>[];
    for (final ds in pastDays) {
      final s = await _getDailySerialsSummary(normBranchId, ds, todayKey);
      summaries.add(s);
    }
    final merged = <String, int>{};
    for (final summary in summaries) {
      summary.forEach((key, val) {
        merged[key] = (merged[key] ?? 0) + val;
      });
    }
    return merged;
  }();

  if (!hasToday) {
    // If today is not in the range, it's completely static!
    return Stream.fromFuture(pastSummaryFuture).asBroadcastStream();
  }

  // If today is in the range, we listen to today's Firestore collections in real-time
  final queues = ['zakat', 'non-zakat', 'gmwf'];
  final todayStreams = queues.map((q) => FirebaseFirestore.instance
      .collection('branches/$normBranchId/serials/$todayKey/$q')
      .snapshots());

  return Rx.combineLatest2<List<QuerySnapshot>, Map<String, int>, Map<String, int>>(
    Rx.combineLatestList(todayStreams),
    Stream.fromFuture(pastSummaryFuture),
    (todaySnaps, pastSummary) {
      int pending = pastSummary['pending'] ?? 0;
      int dispensed = pastSummary['dispensed'] ?? 0;
      int zakatCount = pastSummary['v1'] ?? 0;
      int nonZakatCount = pastSummary['v2'] ?? 0;
      int gmwfCount = pastSummary['v3'] ?? 0;
      int zakatRevenue = pastSummary['v1_sub'] ?? 0;
      int nonZakatRevenue = pastSummary['v2_sub'] ?? 0;

      int prescWaiting = pastSummary['presc_waiting'] ?? 0;
      int prescPrescribed = pastSummary['presc_prescribed'] ?? 0;
      int dispPending = pastSummary['disp_pending'] ?? 0;
      int dispDispensed = pastSummary['disp_dispensed'] ?? 0;

      for (int i = 0; i < 3; i++) {
        final q = queues[i];
        final snap = todaySnaps[i];
        final count = snap.size;
        if (q == 'zakat') zakatCount += count;
        if (q == 'non-zakat') nonZakatCount += count;
        if (q == 'gmwf') gmwfCount += count;

        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final daysOfMedicine = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
          if (q == 'zakat') {
            zakatRevenue += 20 * daysOfMedicine;
          } else if (q == 'non-zakat') {
            nonZakatRevenue += 100 * daysOfMedicine;
          }

          final status = (data['status'] ?? '').toString().toLowerCase().trim();
          final dispenseStatus = (data['dispenseStatus'] ?? '').toString().toLowerCase().trim();

          if (status == 'completed') {
            dispensed++;
            prescPrescribed++;
            if (dispenseStatus == 'dispensed') {
              dispDispensed++;
            } else {
              dispPending++;
            }
          } else {
            pending++;
            prescWaiting++;
          }
        }
      }

      final total = zakatCount + nonZakatCount + gmwfCount;
      return {
        'v1': zakatCount,
        'v1_sub': zakatRevenue,
        'v2': nonZakatCount,
        'v2_sub': nonZakatRevenue,
        'v3': gmwfCount,
        'v3_sub': 0,
        'total': total,
        'revenue': zakatRevenue + nonZakatRevenue,
        'pending': pending,
        'dispensed': dispensed,
        'presc_waiting': prescWaiting,
        'presc_prescribed': prescPrescribed,
        'disp_pending': dispPending,
        'disp_dispensed': dispDispensed,
      };
    },
  ).asBroadcastStream();
}

Future<Map<String, int>> serialsCountFuture(String branchId, DateTime start, DateTime end) async {
  final normBranchId = branchId.toLowerCase().trim();
  final days = _dateStrings(start, end);
  final todayKey = DateFormat('ddMMyy').format(DateTime.now());
  
  final daySummaries = <Map<String, int>>[];
  for (final ds in days) {
    final s = await _getDailySerialsSummary(normBranchId, ds, todayKey);
    daySummaries.add(s);
  }
  
  final merged = <String, int>{};
  for (final summary in daySummaries) {
    summary.forEach((key, val) {
      merged[key] = (merged[key] ?? 0) + val;
    });
  }
  return merged;
}
