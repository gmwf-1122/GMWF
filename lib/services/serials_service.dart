import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:hive/hive.dart';

import 'camp_session_service.dart';

List<String> _dateStrings(DateTime start, DateTime end) {
  final df   = DateFormat('ddMMyy');
  final days = <String>[];
  for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
    days.add(df.format(d));
  }
  return days;
}

/// Single source of truth sequence integer parser from serial string.
/// Extracts the numerical sequence number regardless of prefix or hyphen format.
int parseSequenceFromSerial(String serial) {
  final s = serial.trim();
  if (s.isEmpty) return 999999;
  final parts = s.split('-');

  // 1. If temp format: X-ddMMyy-TAG-SEQ (e.g. X-160826-HAJI-003)
  if (parts.length >= 4 && parts[0].toUpperCase() == 'X') {
    final cleanSeq = parts[3].replaceAll(RegExp(r'[^\d]'), '');
    final numVal = int.tryParse(cleanSeq);
    if (numVal != null && cleanSeq.length <= 4) return numVal;
  }

  // 2. If branch-prefixed format: branchId-ddMMyy-TAG-SEQ (e.g. jalalpur_jattan-160826-HAJI-003)
  if (parts.length >= 4) {
    final lastPart = parts.last.replaceAll(RegExp(r'[^\d]'), '');
    final numVal = int.tryParse(lastPart);
    if (numVal != null && lastPart.length <= 4) return numVal;
  }

  // 3. Standard token serial format: ddMMyy-TAG-SEQ (e.g. 160826-HAJI-003)
  if (parts.length == 3 && RegExp(r'^\d{6}$').hasMatch(parts[0])) {
    final cleanSeq = parts[2].replaceAll(RegExp(r'[^\d]'), '');
    final numVal = int.tryParse(cleanSeq);
    if (numVal != null && cleanSeq.length <= 4) return numVal;
  }

  // 4. Any token format where the LAST hyphenated part is a 1-4 digit sequence (e.g. 001 to 9999)
  if (parts.length >= 2) {
    final lastPart = parts.last.replaceAll(RegExp(r'[^\d]'), '');
    final numVal = int.tryParse(lastPart);
    if (numVal != null && lastPart.isNotEmpty && lastPart.length <= 4) return numVal;
  }

  return 999999;
}

/// Issues a serial number atomically using a Firestore Transaction on:
///   branches/{branchId}/counters/{dateKey}_{dispensaryTag}
/// Returns a Map with the assigned serial, dateKey, and entryData written.
///
/// FIX 4: Idempotency guard. If [tokenData] carries a 'localId' or
/// 'originalTempSerial' (both are stable, client-generated identifiers for
/// a single logical token), a companion collection
/// (counters/{dateKey}_{tag}/_issued/{id}) records the result the first
/// time that id is processed. Any later call with the same id — e.g. a
/// duplicate call that slipped past Fix 1's sync-queue dedup — replays the
/// stored result instead of incrementing the counter again, so the serial
/// sequence never jumps by more than 1 per real token.
Future<Map<String, dynamic>> issueAtomicSerialTransaction({
  required String branchId,
  required String dispensaryTag,
  required String queueType,
  required Map<String, dynamic> tokenData,
  DateTime? time,
}) async {
  final normBranch = branchId.toLowerCase().trim();
  final normTag = dispensaryTag.trim().toUpperCase();
  final shiftInfo = CampSessionService.resolveShiftAndDateKey(time);
  final dateKey = shiftInfo.dateKey;
  final session = shiftInfo.session;

  final counterRef = FirebaseFirestore.instance
      .collection('branches')
      .doc(normBranch)
      .collection('counters')
      .doc('${dateKey}_$normTag');

  final db = FirebaseFirestore.instance;

  // Stable idempotency id for this logical token, if the caller supplied one.
  final idempotencyId =
      (tokenData['localId'] ?? tokenData['originalTempSerial'])?.toString().trim();
  final issuedRef = (idempotencyId != null && idempotencyId.isNotEmpty)
      ? counterRef.collection('_issued').doc(idempotencyId)
      : null;

  return await db.runTransaction((transaction) async {
    // FIX 4: Replay-check BEFORE reading/incrementing the counter. All reads
    // in a Firestore transaction must happen before any writes, so this get()
    // is safe to run first regardless of whether we end up short-circuiting.
    if (issuedRef != null) {
      final issuedSnap = await transaction.get(issuedRef);
      if (issuedSnap.exists) {
        final data = issuedSnap.data();
        final storedResult = data?['result'];
        if (storedResult is Map) {
          debugPrint(
              '[serials_service] ♻️ Idempotent replay for localId/originalTempSerial="$idempotencyId" '
              '— returning previously-issued serial "${storedResult['serial']}" instead of incrementing again.');
          return Map<String, dynamic>.from(storedResult);
        }
      }
    }

    final counterSnap = await transaction.get(counterRef);
    int currentSeq = 0;
    if (counterSnap.exists) {
      currentSeq = (counterSnap.data()?['lastSeq'] as num?)?.toInt() ?? 0;
    }
    final newSeq = currentSeq + 1;
    final seqPadded = newSeq.toString().padLeft(newSeq > 999 ? 4 : 3, '0');
    final serial = '$dateKey-$normTag-$seqPadded';

    transaction.set(counterRef, {
      'lastSeq': newSeq,
      'dateKey': dateKey,
      'dispensaryTag': normTag,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final entryData = Map<String, dynamic>.from(tokenData);
    entryData['serial'] = serial;
    entryData['dateKey'] = dateKey;
    entryData['session'] = session;
    entryData['queueType'] = queueType;
    entryData['branchId'] = normBranch;

    final tokenRef = db
        .collection('branches')
        .doc(normBranch)
        .collection('serials')
        .doc(dateKey)
        .collection(queueType)
        .doc(serial);

    transaction.set(tokenRef, entryData, SetOptions(merge: true));

    final result = <String, dynamic>{
      'serial': serial,
      'dateKey': dateKey,
      'session': session,
      'seq': newSeq,
      'entryData': entryData,
    };

    // FIX 4: Record this id's result AFTER computing the serial, so a
    // subsequent duplicate call with the same localId/originalTempSerial
    // finds it and replays instead of re-incrementing.
    if (issuedRef != null) {
      transaction.set(issuedRef, {
        'result': result,
        'issuedAt': FieldValue.serverTimestamp(),
      });
    }

    return result;
  });
}

bool _matchesSubDispensary(Map<String, dynamic> data, String? subFilter, [String? docId]) {
  if (subFilter == null || subFilter.isEmpty || subFilter == 'all') return true;
  return CampSessionService.matchesCamp(
    selectedCamp: subFilter,
    dispensaryId: data['dispensaryId']?.toString(),
    campId: data['campId']?.toString(),
    dispensaryTag: data['dispensaryTag']?.toString(),
    serial: (data['serial'] ?? data['tokenSerial'] ?? data['id'] ?? data['tokenNumber'] ?? docId)?.toString(),
  );
}

bool _matchesShift(Map<String, dynamic> data, String? shiftFilter) {
  if (shiftFilter == null || shiftFilter.isEmpty || shiftFilter == 'all') return true;
  final normShift = shiftFilter.toLowerCase().trim();

  // 1. Check explicit session / shift / campSession / slot field
  final session = (data['session'] ?? data['shift'] ?? data['campSession'] ?? data['slot'] ?? '').toString().toLowerCase().trim();
  if (normShift == 'night') {
    if (session == 'night') return true;
    if (session == 'morning' || session == 'evening' || session == 'day') return false;
  } else if (normShift == 'day' || normShift == 'morning' || normShift == 'evening') {
    if (session == 'morning' || session == 'evening' || session == 'day') return true;
    if (session == 'night') return false;
  }

  // 2. Fallback to timestamp/hour
  DateTime? dt;
  final ts = data['createdAt'] ?? data['timestamp'] ?? data['time'] ?? data['dispensedAt'] ?? data['date'] ?? data['lastUpdatedAt'];
  if (ts is Timestamp) {
    dt = ts.toDate();
  } else if (ts is DateTime) {
    dt = ts;
  } else if (ts is String) {
    dt = DateTime.tryParse(ts);
  }

  if (dt != null) {
    final hour = dt.hour;
    final isNight = (hour >= 22 || hour < 6);
    if (normShift == 'night') return isNight;
    return !isNight; // Day shift (06:00 to 21:59)
  }

  // If no timestamp or session, default to day shift
  return normShift != 'night';
}

Future<Map<String, int>> _getDailySerialsSummary(String branchId, String ds, String todayKey, [String? subDispensary, String? shift]) async {
  final normBranchId = branchId.toLowerCase().trim();
  final subKey = (subDispensary != null && subDispensary.isNotEmpty && subDispensary != 'all') ? subDispensary.toLowerCase().trim() : 'all';
  final shiftKey = (shift != null && shift.isNotEmpty && shift != 'all') ? shift.toLowerCase().trim() : 'all';
  final cacheKey = 'v1|$normBranchId|$subKey|$shiftKey|$ds|serials_summary';
  
  if (ds != todayKey) {
    try {
      if (!Hive.isBoxOpen('branch_data_cache')) {
        await Hive.openBox('branch_data_cache');
      }
      final box = Hive.box('branch_data_cache');
      final cached = box.get(cacheKey) ?? (shiftKey == 'all' ? box.get('v1|$normBranchId|$subKey|$ds|serials_summary') : null);
      if (cached is Map) {
        return Map<String, int>.from(cached.cast<String, int>());
      }
    } catch (_) {}
  }
  
  // Fetch from Firestore
  int pending = 0;
  int dispensed = 0;
  int zakatRevenue = 0;
  int nonZakatRevenue = 0;
  int prescWaiting = 0;
  int prescPrescribed = 0;
  int dispPending = 0;
  int dispDispensed = 0;
  
  final queues = ['zakat', 'non-zakat', 'gmwf'];
  final dateDocs = CampSessionService.getAllCampDateDocIds(
    branchId: normBranchId,
    dateKey: ds,
    selectedCamp: subDispensary,
  );
  final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
  final queryQueues = <String>[];
  for (final docKey in dateDocs) {
    for (final q in queues) {
      futures.add(FirebaseFirestore.instance
          .collection('branches/$normBranchId/serials/$docKey/$q')
          .get());
      queryQueues.add(q);
    }
  }
      
  final snaps = await Future.wait(futures);

  final Map<String, Map<String, dynamic>> activeTokenMap = {};
  final Set<String> zakatSerials = {};
  final Set<String> nonZakatSerials = {};
  final Set<String> gmwfSerials = {};

  for (int i = 0; i < snaps.length; i++) {
    final q = queryQueues[i];
    final snap = snaps[i];
    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toLowerCase().trim();
      final syncStatus = (data['syncStatus'] ?? '').toString().toLowerCase().trim();
      final isDeleted = data['isDeleted'] == true || status == 'deleted' || syncStatus == 'deleted' || status == 'void' || status == 'cancelled';
      if (isDeleted) continue;

      if (!_matchesSubDispensary(data, subDispensary, doc.id)) continue;
      if (!_matchesShift(data, shift)) continue;

      final rawSerial = (data['serial'] ?? data['tokenSerial'] ?? data['id'] ?? data['tokenNumber'] ?? doc.id).toString();
      final cleanNum = int.tryParse(rawSerial.replaceAll(RegExp(r'[^0-9]'), ''));
      final prefix = q == 'non-zakat' ? 'NZ' : (q == 'zakat' ? 'Z' : 'G');
      final uniqueKey = (cleanNum != null && cleanNum > 0) ? '$prefix-${cleanNum % 1000}' : '${q}_${doc.id}';

      if (activeTokenMap.containsKey(uniqueKey)) continue;
      activeTokenMap[uniqueKey] = data;

      if (q == 'zakat') zakatSerials.add(uniqueKey);
      else if (q == 'non-zakat') nonZakatSerials.add(uniqueKey);
      else gmwfSerials.add(uniqueKey);

      final daysOfMedicine = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
      if (q == 'zakat') {
        zakatRevenue += 20 * daysOfMedicine;
      } else if (q == 'non-zakat') {
        nonZakatRevenue += 100 * daysOfMedicine;
      }
      
      final dispenseStatus = (data['dispenseStatus'] ?? '').toString().toLowerCase().trim();
      
      if (status == 'completed' || status == 'dispensed' || status == 'prescribed') {
        dispensed++;
        prescPrescribed++;
        if (dispenseStatus == 'dispensed' || status == 'dispensed') {
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

  final zakatCount = zakatSerials.length;
  final nonZakatCount = nonZakatSerials.length;
  final gmwfCount = gmwfSerials.length;
  
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

Stream<Map<String, int>> serialsCountStream(String branchId, DateTime start, DateTime end, {String? subDispensary, String? shift}) {
  final normBranchId = branchId.toLowerCase().trim();
  final subKey = (subDispensary != null && subDispensary.isNotEmpty && subDispensary != 'all') ? subDispensary.toLowerCase().trim() : 'all';
  final shiftKey = (shift != null && shift.isNotEmpty && shift != 'all') ? shift.toLowerCase().trim() : 'all';
  final days = _dateStrings(start, end);
  final todayKey = DateFormat('ddMMyy').format(DateTime.now());
  
  final hasToday = days.contains(todayKey);
  final pastDays = days.where((d) => d != todayKey).toList();

  // 1. Get initial cached summary from Hive immediately (0ms)
  Map<String, int>? initialCached;
  try {
    if (Hive.isBoxOpen('branch_data_cache')) {
      final box = Hive.box('branch_data_cache');
      final merged = <String, int>{};
      bool hasData = false;
      for (final ds in days) {
        final cacheKey = 'v1|$normBranchId|$subKey|$shiftKey|$ds|serials_summary';
        final cached = box.get(cacheKey) ?? (shiftKey == 'all' ? box.get('v1|$normBranchId|$subKey|$ds|serials_summary') : null);
        if (cached is Map) {
          hasData = true;
          cached.forEach((key, val) {
            if (val is num) {
              merged[key.toString()] = (merged[key.toString()] ?? 0) + val.toInt();
            }
          });
        }
      }
      if (hasData) {
        initialCached = merged;
      }
    }
  } catch (_) {}

  // 2. Fetch past days summaries in parallel
  final Future<Map<String, int>> pastSummaryFuture = () async {
    if (pastDays.isEmpty) return <String, int>{};
    final summaries = await Future.wait(
      pastDays.map((ds) => _getDailySerialsSummary(normBranchId, ds, todayKey, subDispensary, shift)),
    );
    final merged = <String, int>{};
    for (final summary in summaries) {
      summary.forEach((key, val) {
        merged[key] = (merged[key] ?? 0) + val;
      });
    }
    return merged;
  }();

  if (!hasToday) {
    var stream = Stream.fromFuture(pastSummaryFuture);
    if (initialCached != null) {
      stream = stream.startWith(initialCached);
    }
    return stream.asBroadcastStream();
  }

  // 3. Listen to today's queues in real-time
  final queues = ['zakat', 'non-zakat', 'gmwf'];
  final dateDocs = CampSessionService.getAllCampDateDocIds(
    branchId: normBranchId,
    dateKey: todayKey,
    selectedCamp: subDispensary,
  );
  final todayStreams = <Stream<QuerySnapshot>>[];
  final streamQueues = <String>[];
  for (final docKey in dateDocs) {
    for (final q in queues) {
      todayStreams.add(FirebaseFirestore.instance
          .collection('branches/$normBranchId/serials/$docKey/$q')
          .snapshots());
      streamQueues.add(q);
    }
  }

  var liveStream = Rx.combineLatest2<List<QuerySnapshot>, Map<String, int>, Map<String, int>>(
    Rx.combineLatestList(todayStreams),
    Stream.fromFuture(pastSummaryFuture).startWith(initialCached ?? <String, int>{}),
    (todaySnaps, pastSummary) {
      int pending = pastSummary['pending'] ?? 0;
      int dispensed = pastSummary['dispensed'] ?? 0;
      int zakatRevenue = pastSummary['v1_sub'] ?? 0;
      int nonZakatRevenue = pastSummary['v2_sub'] ?? 0;

      int prescWaiting = pastSummary['presc_waiting'] ?? 0;
      int prescPrescribed = pastSummary['presc_prescribed'] ?? 0;
      int dispPending = pastSummary['disp_pending'] ?? 0;
      int dispDispensed = pastSummary['disp_dispensed'] ?? 0;

      final Map<String, Map<String, dynamic>> activeTokenMap = {};
      final Set<String> zakatSerials = {};
      final Set<String> nonZakatSerials = {};
      final Set<String> gmwfSerials = {};

      int todayZakatRev = 0;
      int todayNonZakatRev = 0;
      int todayPending = 0;
      int todayDispensed = 0;
      int todayPrescWaiting = 0;
      int todayPrescPrescribed = 0;
      int todayDispPending = 0;
      int todayDispDispensed = 0;

      for (int i = 0; i < todaySnaps.length; i++) {
        final q = streamQueues[i];
        final snap = todaySnaps[i];

        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString().toLowerCase().trim();
          final syncStatus = (data['syncStatus'] ?? '').toString().toLowerCase().trim();
          final isDeleted = data['isDeleted'] == true || status == 'deleted' || syncStatus == 'deleted' || status == 'void' || status == 'cancelled';
          if (isDeleted) continue;

          if (!_matchesSubDispensary(data, subDispensary, doc.id)) continue;
          if (!_matchesShift(data, shift)) continue;

          final rawSerial = (data['serial'] ?? data['tokenSerial'] ?? data['id'] ?? data['tokenNumber'] ?? doc.id).toString();
          final cleanNum = int.tryParse(rawSerial.replaceAll(RegExp(r'[^0-9]'), ''));
          final prefix = q == 'non-zakat' ? 'NZ' : (q == 'zakat' ? 'Z' : 'G');
          final uniqueKey = (cleanNum != null && cleanNum > 0) ? '$prefix-${cleanNum % 1000}' : '${q}_${doc.id}';

          if (activeTokenMap.containsKey(uniqueKey)) continue;
          activeTokenMap[uniqueKey] = data;

          if (q == 'zakat') zakatSerials.add(uniqueKey);
          else if (q == 'non-zakat') nonZakatSerials.add(uniqueKey);
          else gmwfSerials.add(uniqueKey);

          final daysOfMedicine = (data['daysOfMedicine'] as num?)?.toInt() ?? 1;
          if (q == 'zakat') {
            todayZakatRev += 20 * daysOfMedicine;
          } else if (q == 'non-zakat') {
            todayNonZakatRev += 100 * daysOfMedicine;
          }

          final dispenseStatus = (data['dispenseStatus'] ?? '').toString().toLowerCase().trim();

          if (status == 'completed' || status == 'dispensed' || status == 'prescribed') {
            todayDispensed++;
            todayPrescPrescribed++;
            if (dispenseStatus == 'dispensed' || status == 'dispensed') {
              todayDispDispensed++;
            } else {
              todayDispPending++;
            }
          } else {
            todayPending++;
            todayPrescWaiting++;
          }
        }
      }

      final todaySummaryToCache = {
        'v1': zakatSerials.length,
        'v1_sub': todayZakatRev,
        'v2': nonZakatSerials.length,
        'v2_sub': todayNonZakatRev,
        'v3': gmwfSerials.length,
        'v3_sub': 0,
        'total': zakatSerials.length + nonZakatSerials.length + gmwfSerials.length,
        'revenue': todayZakatRev + todayNonZakatRev,
        'pending': todayPending,
        'dispensed': todayDispensed,
        'presc_waiting': todayPrescWaiting,
        'presc_prescribed': todayPrescPrescribed,
        'disp_pending': todayDispPending,
        'disp_dispensed': todayDispDispensed,
      };

      try {
        if (Hive.isBoxOpen('branch_data_cache')) {
          final box = Hive.box('branch_data_cache');
          box.put('v1|$normBranchId|$subKey|$shiftKey|$todayKey|serials_summary', todaySummaryToCache);
        }
      } catch (_) {}

      final zakatCount = (pastSummary['v1'] ?? 0) + zakatSerials.length;
      final nonZakatCount = (pastSummary['v2'] ?? 0) + nonZakatSerials.length;
      final gmwfCount = (pastSummary['v3'] ?? 0) + gmwfSerials.length;
      final total = zakatCount + nonZakatCount + gmwfCount;

      return {
        'v1': zakatCount,
        'v1_sub': zakatRevenue + todayZakatRev,
        'v2': nonZakatCount,
        'v2_sub': nonZakatRevenue + todayNonZakatRev,
        'v3': gmwfCount,
        'v3_sub': 0,
        'total': total,
        'revenue': zakatRevenue + nonZakatRevenue + todayZakatRev + todayNonZakatRev,
        'pending': pending + todayPending,
        'dispensed': dispensed + todayDispensed,
        'presc_waiting': prescWaiting + todayPrescWaiting,
        'presc_prescribed': prescPrescribed + todayPrescPrescribed,
        'disp_pending': dispPending + todayDispPending,
        'disp_dispensed': dispDispensed + todayDispDispensed,
      };
    },
  );

  if (initialCached != null) {
    liveStream = liveStream.startWith(initialCached);
  }

  return liveStream.asBroadcastStream();
}

Stream<Map<String, Map<String, int>>> facilityShiftBreakdownStream(String branchId, DateTime start, DateTime end) {
  final saddarMorning$ = serialsCountStream(branchId, start, end, subDispensary: 'saddar', shift: 'morning');
  final saddarEvening$ = serialsCountStream(branchId, start, end, subDispensary: 'saddar', shift: 'evening');
  final saddarNight$   = serialsCountStream(branchId, start, end, subDispensary: 'saddar', shift: 'night');

  final hajiMorning$   = serialsCountStream(branchId, start, end, subDispensary: 'haji_camp', shift: 'morning');
  final hajiEvening$   = serialsCountStream(branchId, start, end, subDispensary: 'haji_camp', shift: 'evening');
  final hajiNight$     = serialsCountStream(branchId, start, end, subDispensary: 'haji_camp', shift: 'night');

  final allMorning$    = serialsCountStream(branchId, start, end, subDispensary: 'all', shift: 'morning');
  final allEvening$    = serialsCountStream(branchId, start, end, subDispensary: 'all', shift: 'evening');
  final allNight$      = serialsCountStream(branchId, start, end, subDispensary: 'all', shift: 'night');

  return Rx.combineLatest9<Map<String, int>, Map<String, int>, Map<String, int>, Map<String, int>, Map<String, int>, Map<String, int>, Map<String, int>, Map<String, int>, Map<String, int>, Map<String, Map<String, int>>>(
    saddarMorning$,
    saddarEvening$,
    saddarNight$,
    hajiMorning$,
    hajiEvening$,
    hajiNight$,
    allMorning$,
    allEvening$,
    allNight$,
    (sMorn, sEve, sNight, hMorn, hEve, hNight, aMorn, aEve, aNight) {
      final sMornTotal = sMorn['total'] ?? 0;
      final sEveTotal = sEve['total'] ?? 0;
      final sNightTotal = sNight['total'] ?? 0;
      final sTotal = sMornTotal + sEveTotal + sNightTotal;

      final hMornTotal = hMorn['total'] ?? 0;
      final hEveTotal = hEve['total'] ?? 0;
      final hNightTotal = hNight['total'] ?? 0;
      final hTotal = hMornTotal + hEveTotal + hNightTotal;

      final sumMorn = sMornTotal + hMornTotal;
      final sumEve = sEveTotal + hEveTotal;
      final sumNight = sNightTotal + hNightTotal;

      final directMorn = aMorn['total'] ?? 0;
      final directEve = aEve['total'] ?? 0;
      final directNight = aNight['total'] ?? 0;

      final allMornTotal = directMorn > sumMorn ? directMorn : sumMorn;
      final allEveTotal = directEve > sumEve ? directEve : sumEve;
      final allNightTotal = directNight > sumNight ? directNight : sumNight;
      final allTotal = allMornTotal + allEveTotal + allNightTotal;

      return {
        'saddar': {
          'morning': sMornTotal,
          'evening': sEveTotal,
          'night': sNightTotal,
          'day': sMornTotal + sEveTotal,
          'total': sTotal,
        },
        'haji_camp': {
          'morning': hMornTotal,
          'evening': hEveTotal,
          'night': hNightTotal,
          'day': hMornTotal + hEveTotal,
          'total': hTotal,
        },
        'all': {
          'morning': allMornTotal,
          'evening': allEveTotal,
          'night': allNightTotal,
          'day': allMornTotal + allEveTotal,
          'total': allTotal,
        },
      };
    },
  ).asBroadcastStream();
}

Future<Map<String, int>> serialsCountFuture(String branchId, DateTime start, DateTime end) async {
  final normBranchId = branchId.toLowerCase().trim();
  final days = _dateStrings(start, end);
  final todayKey = DateFormat('ddMMyy').format(DateTime.now());
  
  final daySummaries = await Future.wait(
    days.map((ds) => _getDailySerialsSummary(normBranchId, ds, todayKey)),
  );
  
  final merged = <String, int>{};
  for (final summary in daySummaries) {
    summary.forEach((key, val) {
      merged[key] = (merged[key] ?? 0) + val;
    });
  }
  return merged;
}