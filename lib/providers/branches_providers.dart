// lib/providers/branches_providers.dart
//
// Traditional Riverpod providers (no code-generation) for the Branches screen.
// Each provider is intentionally narrow: it manages one piece of state so that
// only the widgets that depend on it rebuild when it changes.

import 'dart:async';
import 'dart:io' as io;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/local_storage_service.dart';
import '../services/serials_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Branches list – streams all branches from Firestore.
//    If a specific branchId is provided (supervisor mode) it filters to that one.
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the optional branchId for single-branch (supervisor) mode.
/// Set this from the widget before watching [branchesListProvider].
final singleBranchIdProvider = StateProvider<String?>((ref) => null);

/// Holds the active branchId tab selected externally (e.g. from Dashboard performance table).
final selectedBranchTabIdProvider = StateProvider<String?>((ref) => null);

/// Streams the list of branches as [{id, name}] maps, sorted by name.
final branchesListProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final singleId = ref.watch(singleBranchIdProvider);
  final Query<Map<String, dynamic>> query = singleId != null
      ? FirebaseFirestore.instance
          .collection('branches')
          .where(FieldPath.documentId, isEqualTo: singleId)
      : FirebaseFirestore.instance.collection('branches');

  return query.snapshots().map((snap) {
    final list = snap.docs.map((doc) {
      final data = doc.data();
      return <String, dynamic>{
        'id': doc.id,
        'name': data['name'] as String? ?? doc.id,
      };
    }).toList();
    list.sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));
    return list;
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. Date range filter
// ─────────────────────────────────────────────────────────────────────────────

class DateRange {
  final DateTime? start;
  final DateTime? end;
  const DateRange({this.start, this.end});
  bool get isToday => start == null && end == null;
  DateRange copyWith({DateTime? start, DateTime? end}) =>
      DateRange(start: start ?? this.start, end: end ?? this.end);
}

final branchDateRangeProvider =
    StateProvider<DateRange>((ref) => const DateRange());

// ─────────────────────────────────────────────────────────────────────────────
// 3. Dispensary-list filter chips
// ─────────────────────────────────────────────────────────────────────────────

/// Selected type filter: null = All, 'zakat', 'non-zakat', 'gmwf'
final branchTypeFilterProvider = StateProvider<String?>((ref) => null);

/// Selected sub-dispensary facility filter: null = All, 'kapayya', 'haji_camp'
final branchSubDispensaryFilterProvider = StateProvider<String?>((ref) => null);

/// Selected shift filter: null = All, 'day', 'night'
final branchShiftFilterProvider = StateProvider<String?>((ref) => null);

final branchMultiDayFilterProvider = StateProvider<bool>((ref) => false);

final branchMultiVisitFilterProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────────────────────
// 4. Reverted-patient IDs  (patients whose frequent-flag has been dismissed)
// ─────────────────────────────────────────────────────────────────────────────

final revertedPatientIdsProvider =
    StateProvider<Set<String>>((ref) => const {});

// ─────────────────────────────────────────────────────────────────────────────
// 5. Per-branch dispensary data + sync/error state
//
//    We use a Notifier family so each branch has its own isolated state.
//    The notifier owns the full load + background-sync pipeline so branches.dart
//    never needs to touch ValueNotifier maps or StreamSubscription bookkeeping.
// ─────────────────────────────────────────────────────────────────────────────

class DispensaryState {
  final List<Map<String, dynamic>> records;
  final bool isSyncing;
  final String? error;

  const DispensaryState({
    this.records = const [],
    this.isSyncing = false,
    this.error,
  });

  DispensaryState copyWith({
    List<Map<String, dynamic>>? records,
    bool? isSyncing,
    String? error,
    bool clearError = false,
  }) =>
      DispensaryState(
        records: records ?? this.records,
        isSyncing: isSyncing ?? this.isSyncing,
        error: clearError ? null : (error ?? this.error),
      );
}

class DispensaryNotifier
    extends AutoDisposeFamilyNotifier<DispensaryState, String> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _todaySubscription;
  String? _subscribedTodayKey;

  // The branchId is available as `arg` from the family provider, normalized to lowercase.
  String get branchId => arg.toLowerCase().trim();

  @override
  DispensaryState build(String arg) {
    ref.onDispose(() {
      _todaySubscription?.cancel();
    });

    final dateRange = ref.watch(branchDateRangeProvider);
    final DateTime effectiveStart;
    final DateTime effectiveEnd;
    if (dateRange.start != null && dateRange.end != null) {
      effectiveStart = dateRange.start!;
      effectiveEnd = dateRange.end!.add(const Duration(days: 1));
    } else {
      final now = DateTime.now();
      effectiveStart = DateTime(now.year, now.month, now.day);
      effectiveEnd = DateTime(now.year, now.month, now.day + 1);
    }

    Future.microtask(() => load(effectiveStart, effectiveEnd));
    return const DispensaryState(isSyncing: true);
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> load(DateTime start, DateTime end) async {
    state = state.copyWith(isSyncing: true, clearError: true, records: []);

    final days = _dateStrings(start, end);
    final todayKey = DateFormat('ddMMyy').format(DateTime.now());

    final initialList = <Map<String, dynamic>>[];
    final missingDays = <String>[];

    for (final day in days) {
      if (day == todayKey) {
        missingDays.add(day);
        continue;
      }
      final cached =
          LocalStorageService.getBranchDayCache(branchId, day, 'dispensary');
      if (cached != null) {
        initialList.addAll(cached);
      } else {
        missingDays.add(day);
      }
    }

    // Emit cached data immediately so the UI is not blank while we fetch
    state = state.copyWith(records: List.from(initialList));

    if (missingDays.isEmpty) {
      state = state.copyWith(isSyncing: false);
      await _computeVisitsAndEmit(initialList);
      return;
    }

    await _runBackgroundSync(missingDays, todayKey, initialList);
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  Future<void> _runBackgroundSync(
    List<String> missingDays,
    String todayKey,
    List<Map<String, dynamic>> currentList,
  ) async {
    try {
      final hasToday = missingDays.contains(todayKey);
      final pastMissing = missingDays.where((d) => d != todayKey).toList();

      if (hasToday) {
        await _setupTodayListener(todayKey, currentList);
      } else {
        _todaySubscription?.cancel();
        _subscribedTodayKey = null;
      }

      if (pastMissing.isNotEmpty) {
        // Fetch raw docs for all past missing days in parallel
        final Map<String, List<Map<String, dynamic>>> rawDocsMap = {};
        await Future.wait(pastMissing.map((day) async {
          try {
            final docs = await _fetchDispensaryDocsForDay(day);
            for (final d in docs) {
              d['_syncDayKey'] = day;
            }
            rawDocsMap[day] = docs;
          } catch (e) {
            state = state.copyWith(
                error: 'Failed to fetch raw docs for day $day: $e');
          }
        }));

        final allRawDocs = rawDocsMap.values.expand((l) => l).toList();

        List<Map<String, dynamic>> enrichedAll;
        try {
          enrichedAll =
              await LocalStorageService.enrichRawDocs(branchId, allRawDocs);
        } catch (_) {
          enrichedAll = _fallbackEnrich(allRawDocs);
        }

        final displayFormat = DateFormat('dd MMM yyyy');
        final enrichedByDay = <String, List<Map<String, dynamic>>>{};
        for (final d in enrichedAll) {
          final day = d['_syncDayKey'] as String? ?? todayKey;
          d.remove('_syncDayKey');
          d['dispenseDate'] = displayFormat
              .format(_parseDispensedAt(d['dispensedAt'], day));
          d['type'] = _resolveType(d);
          enrichedByDay.putIfAbsent(day, () => []).add(d);
        }

        for (final day in pastMissing) {
          final dayEnriched = enrichedByDay[day] ?? [];
          await LocalStorageService.putBranchDayCache(
              branchId, day, 'dispensary', dayEnriched);
          currentList.addAll(dayEnriched);
        }

        await _computeVisitsAndEmit(currentList);
      }
    } catch (e) {
      state = state.copyWith(error: 'Background sync failed: $e');
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  Future<void> _setupTodayListener(
      String todayKey, List<Map<String, dynamic>> currentList) async {
    // One-shot fetch first to populate immediately
    await _fetchAndMergeToday(todayKey, currentList);

    if (_subscribedTodayKey == todayKey) return; // already subscribed

    _todaySubscription?.cancel();
    _subscribedTodayKey = todayKey;

    _todaySubscription = FirebaseFirestore.instance
        .collection('branches/$branchId/dispensary/$todayKey/$todayKey')
        .snapshots()
        .listen((snap) async {
      try {
        final rawDocs = await _fetchDispensaryDocsForDay(todayKey);
        List<Map<String, dynamic>> enrichedToday;
        try {
          enrichedToday =
              await LocalStorageService.enrichRawDocs(branchId, rawDocs);
        } catch (_) {
          enrichedToday = _fallbackEnrich(rawDocs);
        }

        final displayFormat = DateFormat('dd MMM yyyy');
        final todayDisplayStr = displayFormat
            .format(LocalStorageService.parseDdMMyy(todayKey));
        for (final d in enrichedToday) {
          d['dispenseDate'] = todayDisplayStr;
          d['type'] = _resolveType(d);
        }

        final merged = List<Map<String, dynamic>>.from(state.records);
        merged.removeWhere((item) => item['dispenseDate'] == todayDisplayStr);
        merged.addAll(enrichedToday);
        await _computeVisitsAndEmit(merged);
      } catch (e, stack) {
        print('[DispensaryNotifier] today listener error: $e');
        try {
          final file = io.File('e:/GMWF/gmwf/debug_branches.txt');
          await file.writeAsString('\n=== ERROR IN today listener ===\n$e\n$stack\n', mode: io.FileMode.append);
        } catch (_) {}
      }
    }, onError: (err, stack) {
      print('[DispensaryNotifier] today stream error: $err');
      try {
        final file = io.File('e:/GMWF/gmwf/debug_branches.txt');
        file.writeAsStringSync('\n=== ERROR IN today stream onError ===\n$err\n$stack\n', mode: io.FileMode.append);
      } catch (_) {}
    });
  }

  Future<void> _fetchAndMergeToday(
      String todayKey, List<Map<String, dynamic>> currentList) async {
    try {
      final rawDocs = await _fetchDispensaryDocsForDay(todayKey);

      List<Map<String, dynamic>> enrichedToday;
      try {
        enrichedToday =
            await LocalStorageService.enrichRawDocs(branchId, rawDocs);
      } catch (_) {
        enrichedToday = _fallbackEnrich(rawDocs);
      }

      final displayFormat = DateFormat('dd MMM yyyy');
      final todayDisplayStr =
          displayFormat.format(LocalStorageService.parseDdMMyy(todayKey));
      for (final d in enrichedToday) {
        d['dispenseDate'] = todayDisplayStr;
        d['type'] = _resolveType(d);
      }

      currentList.removeWhere((item) => item['dispenseDate'] == todayDisplayStr);
      currentList.addAll(enrichedToday);
      await _computeVisitsAndEmit(currentList);
    } catch (e, stack) {
      print('[DispensaryNotifier] _fetchAndMergeToday error: $e');
    }
  }

  Future<void> _computeVisitsAndEmit(
      List<Map<String, dynamic>> list) async {
    try {
      final visitCountMap = <String, int>{};

      // When no date filter — compute visit count over rolling 7-day window
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final visitStart = today.subtract(const Duration(days: 7));
      final visitDays =
          _dateStrings(visitStart, today.add(const Duration(days: 1)));

      final dayDocsList = await Future.wait(visitDays.map((day) async {
        final cached =
            LocalStorageService.getBranchDayCache(branchId, day, 'dispensary');
        return cached ?? await _fetchDispensaryDocsCached(day);
      }));

      for (final dayDocs in dayDocsList) {
        for (final doc in dayDocs) {
          final pid = _resolvePatientId(doc);
          if (pid.isEmpty) continue;
          visitCountMap.update(pid, (v) => v + 1, ifAbsent: () => 1);
        }
      }

      for (final e in list) {
        final pid = e['patientId']?.toString() ?? '';
        e['totalVisits'] = visitCountMap[pid] ?? 0;
      }

      state = state.copyWith(records: List.from(list));
    } catch (e, stack) {
      print('[DispensaryNotifier] _computeVisitsAndEmit error: $e');
      try {
        final file = io.File('e:/GMWF/gmwf/debug_branches.txt');
        await file.writeAsString('\n=== ERROR IN _computeVisitsAndEmit ===\n$e\n$stack\n', mode: io.FileMode.append);
      } catch (_) {}
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDispensaryDocsCached(
      String dayKey) async {
    try {
      final cached =
          LocalStorageService.getBranchDayCache(branchId, dayKey, 'dispensary');
      if (cached != null) return cached;
      final docs = await _fetchDispensaryDocsForDay(dayKey);
      await LocalStorageService.putBranchDayCache(
          branchId, dayKey, 'dispensary', docs);
      return docs;
    } catch (e, stack) {
      print('[DispensaryNotifier] _fetchDispensaryDocsCached error: $e');
      try {
        final file = io.File('e:/GMWF/gmwf/debug_branches.txt');
        await file.writeAsString('\n=== ERROR IN _fetchDispensaryDocsCached ===\n$e\n$stack\n', mode: io.FileMode.append);
      } catch (_) {}
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDispensaryDocsForDay(
      String dayKey) async {
    final Map<String, Map<String, dynamic>> combined = {};

    // 1. Try Firestore dispensary collection
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$dayKey/$dayKey')
          .get()
          .timeout(const Duration(seconds: 4));
      for (final doc in snap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['id'] = doc.id;
        final s = (d['serial'] ?? doc.id).toString().trim().toLowerCase();
        if (s.isNotEmpty) combined[s] = d;
      }
    } catch (_) {}

    // 2. Try Firestore serials collections if needed
    try {
      final queues = ['zakat', 'non-zakat', 'gmwf'];
      final snaps = await Future.wait(queues.map((q) => FirebaseFirestore.instance
          .collection('branches/$branchId/serials/$dayKey/$q')
          .where('dispenseStatus', isEqualTo: 'dispensed')
          .get()
          .timeout(const Duration(seconds: 3)))).catchError((_) => <QuerySnapshot<Map<String, dynamic>>>[]);
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final d = Map<String, dynamic>.from(doc.data());
          d['id'] = doc.id;
          final s = (d['serial'] ?? doc.id).toString().trim().toLowerCase();
          if (s.isNotEmpty && !combined.containsKey(s)) combined[s] = d;
        }
      }
    } catch (_) {}

    // 3. Try Local Storage (dispensaryBox & entriesBox)
    try {
      if (Hive.isBoxOpen(LocalStorageService.dispensaryBox)) {
        final dBox = Hive.box(LocalStorageService.dispensaryBox);
        for (final k in dBox.keys) {
          final val = dBox.get(k);
          if (val is Map) {
            final d = Map<String, dynamic>.from(val);
            final b = (d['branchId'] ?? '').toString().toLowerCase().trim();
            final dk = (d['dateKey'] ?? d['date'] ?? '').toString().trim();
            if ((b == branchId || b.isEmpty) && (dk == dayKey || dk.isEmpty)) {
              final s = (d['serial'] ?? d['id'] ?? k).toString().trim().toLowerCase();
              if (s.isNotEmpty && !combined.containsKey(s)) combined[s] = d;
            }
          }
        }
      }
    } catch (_) {}

    try {
      if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
        final eBox = Hive.box(LocalStorageService.entriesBox);
        for (final k in eBox.keys) {
          final val = eBox.get(k);
          if (val is Map) {
            final d = Map<String, dynamic>.from(val);
            final b = (d['branchId'] ?? '').toString().toLowerCase().trim();
            final dk = (d['dateKey'] ?? '').toString().trim();
            final status = (d['dispenseStatus'] ?? d['status'] ?? '').toString().toLowerCase().trim();
            if ((b == branchId || b.isEmpty) && dk == dayKey && (status == 'dispensed' || status == 'completed')) {
              final s = (d['serial'] ?? d['id'] ?? k).toString().trim().toLowerCase();
              final parts = s.split('-');
              final canonical = parts.length > 2 ? '${parts[1]}-${parts[2]}' : (parts.length > 1 ? '${parts[0]}-${parts[1]}' : s);
              if (!combined.containsKey(s) && !combined.containsKey(canonical)) {
                combined[canonical] = d;
              }
            }
          }
        }
      }
    } catch (_) {}

    return combined.values.toList();
  }

  // ── Static utility helpers ──────────────────────────────────────────────────

  static List<String> _dateStrings(DateTime start, DateTime end) {
    final df = DateFormat('ddMMyy');
    final days = <String>[];
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      days.add(df.format(d));
    }
    return days;
  }

  static DateTime _parseDispensedAt(dynamic raw, String dateKeyFallback) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String && raw.isNotEmpty) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    try {
      return LocalStorageService.parseDdMMyy(dateKeyFallback);
    } catch (_) {
      return DateTime.now();
    }
  }

  static String _resolvePatientId(Map<String, dynamic> data) {
    for (final key in ['patientId', 'id', 'uid']) {
      final v = data[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _resolveType(Map<String, dynamic> data) {
    final raw =
        (data['queueType'] ?? data['type'] ?? '').toString().toLowerCase().trim();
    switch (raw) {
      case 'zakat':
        return 'zakat';
      case 'non-zakat':
        return 'non-zakat';
      case 'gmwf':
        return 'gmwf';
      default:
        return 'Unknown';
    }
  }

  static List<Map<String, dynamic>> _fallbackEnrich(
      List<Map<String, dynamic>> rawDocs) {
    String firstNonEmpty(List<dynamic> candidates) {
      for (final c in candidates) {
        final s = c?.toString().trim() ?? '';
        if (s.isNotEmpty && s != 'null' && s != 'N/A') return s;
      }
      return '';
    }

    return rawDocs.map((d) => {
          ...d,
          'name': firstNonEmpty(
              [d['patientName'], d['name'], 'Unknown']),
          'phone': d['phone']?.toString() ?? 'N/A',
          'age': d['age']?.toString() ??
              d['patientAge']?.toString() ??
              'N/A',
          'gender': d['gender']?.toString() ??
              d['patientGender']?.toString() ??
              'N/A',
          'displayCnic': firstNonEmpty([
            d['patientCnic'],
            d['cnic'],
            d['guardianCnic'],
            'N/A',
          ]),
          'isChild':
              (d['guardianCnic'] ?? '').toString().isNotEmpty &&
                  (d['patientCnic'] ?? d['cnic'] ?? '').toString().isEmpty,
          'doctorName': firstNonEmpty(
              [d['doctorName'], d['prescribedBy'], 'Unknown']),
          'dispenserName': firstNonEmpty(
              [d['dispenserName'], d['dispensedBy'], 'Unknown']),
          'tokenBy': firstNonEmpty(
              [d['createdByName'], d['tokenBy'], d['createdBy'], 'Unknown']),
          'daysOfMedicine':
              (d['daysOfMedicine'] as num?)?.toInt() ?? 1,
          'frequentFlag': d['frequentFlag'] ?? false,
        }).toList();
  }
}

/// Family provider: one [DispensaryNotifier] per branchId.
final dispensaryProvider = AutoDisposeNotifierProviderFamily<DispensaryNotifier,
    DispensaryState, String>(DispensaryNotifier.new);

/// Streams the serials count summary for a given branchId, automatically
/// reacting to date range, sub-dispensary, and shift changes.
final serialsSummaryProvider = StreamProvider.family<Map<String, int>, String>((ref, branchId) {
  final dateRange = ref.watch(branchDateRangeProvider);
  final subFilter = ref.watch(branchSubDispensaryFilterProvider);
  final shiftFilter = ref.watch(branchShiftFilterProvider);
  
  // Calculate effectiveStart and effectiveEnd
  final DateTime effectiveStart;
  final DateTime effectiveEnd;
  if (dateRange.start != null && dateRange.end != null) {
    effectiveStart = dateRange.start!;
    effectiveEnd = dateRange.end!.add(const Duration(days: 1));
  } else {
    final now = DateTime.now();
    effectiveStart = DateTime(now.year, now.month, now.day);
    effectiveEnd = DateTime(now.year, now.month, now.day + 1);
  }
  
  return serialsCountStream(
    branchId, 
    effectiveStart, 
    effectiveEnd, 
    subDispensary: subFilter,
    shift: shiftFilter,
  );
});

/// Streams the full breakdown matrix (Saddar vs Haji Camp, Day vs Night) for executive comparison.
final facilityShiftBreakdownProvider = StreamProvider.family<Map<String, Map<String, int>>, String>((ref, branchId) {
  final dateRange = ref.watch(branchDateRangeProvider);
  final DateTime effectiveStart;
  final DateTime effectiveEnd;
  if (dateRange.start != null && dateRange.end != null) {
    effectiveStart = dateRange.start!;
    effectiveEnd = dateRange.end!.add(const Duration(days: 1));
  } else {
    final now = DateTime.now();
    effectiveStart = DateTime(now.year, now.month, now.day);
    effectiveEnd = DateTime(now.year, now.month, now.day + 1);
  }

  return facilityShiftBreakdownStream(branchId, effectiveStart, effectiveEnd);
});
