// lib/pages/branches.dart

import 'dart:async';
import 'dart:io' as io;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../widgets/dashboard_widgets.dart';
import '../services/serials_service.dart';
import '../services/local_storage_service.dart';
import '../providers/branches_providers.dart';

import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import 'dispensary/dispensar/inventory.dart';
import 'office/finance_page.dart';
import 'branches_register.dart';
import 'dispensary/patient_detail_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

List<String> _dateStrings(DateTime start, DateTime end) {
  final df   = DateFormat('ddMMyy');
  final days = <String>[];
  for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
    days.add(df.format(d));
  }
  return days;
}

DateTime _parseDispensedAt(dynamic raw, String dateKeyFallback) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is String && raw.isNotEmpty) {
    try { return DateTime.parse(raw); } catch (_) {}
  }
  try { return LocalStorageService.parseDdMMyy(dateKeyFallback); }
  catch (_) { return DateTime.now(); }
}

// ─────────────────────────────────────────────────────────────────────────────
// PatientSummaryCard
// ─────────────────────────────────────────────────────────────────────────────

enum SummaryCardVariant { tokens, prescriptions, dispensary }

class PatientSummaryCard extends StatelessWidget {
  final String title;
  final Stream<Map<String, int>> dataStream;
  final IconData titleIcon;
  final SummaryCardVariant variant;
  final bool showRevenue;
  final Map<String, IconData> valueIcons;
  final Map<String, String> valueLabels;
  final bool isFiltered;

  const PatientSummaryCard({
    super.key,
    required this.title,
    required this.dataStream,
    required this.titleIcon,
    required this.variant,
    this.showRevenue = false,
    required this.valueIcons,
    required this.valueLabels,
    this.isFiltered = false,
  });

  Color _fillColor(RoleThemeData t) {
    switch (variant) {
      case SummaryCardVariant.tokens:        return t.cardFillTokens;
      case SummaryCardVariant.prescriptions: return t.cardFillPrescriptions;
      case SummaryCardVariant.dispensary:    return t.cardFillDispensary;
    }
  }

  Color _lighten(Color base, [double amount = 0.15]) {
    final hsl  = HSLColor.fromColor(base);
    final newL = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(newL).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final t    = RoleThemeScope.dataOf(context);
    final fill = _fillColor(t);

    return StreamBuilder<Map<String, int>>(
      stream: dataStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _shell(
            fill: fill, t: t,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _header(),
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
              ),
              const SizedBox(height: 12),
              const Opacity(opacity: 0.0, child: SizedBox(height: 18)),
            ]),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return _shell(
            fill: fill, t: t,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _header(),
              const SizedBox(height: 12),
              const Text("No data", style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 12),
              const Opacity(opacity: 0.0, child: SizedBox(height: 18)),
            ]),
          );
        }

        final d       = snapshot.data!;
        final revenue = d['revenue'] ?? 0;
        final minis   = <Widget>[];
        for (final key in valueLabels.keys.where((k) => k.startsWith('v'))) {
          minis.add(_mini(
            valueLabels[key]!, 
            d[key] ?? 0, 
            valueIcons[key] ?? Icons.help_outline,
            subValue: d['${key}_sub'],
          ));
        }
        minis.add(_mini(
          valueLabels['total'] ?? "Total", 
          d['total'] ?? 0, 
          valueIcons['total'] ?? Icons.people,
          subValue: showRevenue ? revenue : null,
        ));

        return _shell(
          fill: fill, t: t,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _header(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: minis,
            ),
            if (showRevenue && revenue > 0) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.payments_rounded, size: 13, color: Colors.white60),
                    const SizedBox(width: 6),
                    Text(isFiltered ? "Total Revenue" : "Today's Revenue",
                        style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w600)),
                  ]),
                  Text(
                    "PKR ${NumberFormat('#,##0').format(revenue)}",
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ],
          ]),
        );
      },
    );
  }

  Widget _shell({required Color fill, required RoleThemeData t, required Widget child}) {
    final highlight = _lighten(fill, 0.12);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [highlight, fill],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: fill.withValues(alpha: 0.2), 
            blurRadius: 16, 
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _header() => Row(children: [
    Icon(titleIcon, color: Colors.white, size: 20),
    const SizedBox(width: 10),
    Expanded(child: Text(title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
            color: Colors.white, letterSpacing: 0.3))),
  ]);

  Widget _mini(String label, int value, IconData icon, {int? subValue}) => Expanded(
    child: Column(children: [
      Icon(icon, size: 19, color: Colors.white60),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
      Text("$value", style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),

    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ConsecutivePatient
// ─────────────────────────────────────────────────────────────────────────────
class _ConsecutivePatient {
  final Map<String, dynamic> data;
  final int streakDays;
  final bool flagReverted;

  const _ConsecutivePatient({
    required this.data,
    required this.streakDays,
    this.flagReverted = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Branches
// ─────────────────────────────────────────────────────────────────────────────

class Branches extends ConsumerStatefulWidget {
  final String? branchId;
  final bool showRegisterButton;
  final bool isManager;
  final String? initialBranchId;

  const Branches({
    super.key,
    this.branchId,
    this.showRegisterButton = true,
    this.isManager = false,
    this.initialBranchId,
  });

  @override
  ConsumerState<Branches> createState() => _BranchesState();
}

class _BranchesState extends ConsumerState<Branches>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _mobileTabController;

  // Tracks which branch+dateRange key has already been triggered for loading
  // so we don't re-trigger the async load on every build.
  final Set<String> _loadedKeys = {};



  @override
  void didUpdateWidget(Branches oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      // Update the provider so branchesListProvider re-streams for the new id
      ref.read(singleBranchIdProvider.notifier).state = widget.branchId;
    }
  }

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 3, vsync: this);
    // Seed the single-branch filter into the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(singleBranchIdProvider.notifier).state = widget.branchId;
    });
  }

  @override
  void dispose() {
    _mobileTabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  DateTime get effectiveStart {
    final range = ref.read(branchDateRangeProvider);
    if (range.start != null && range.end != null) return range.start!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get effectiveEnd {
    final range = ref.read(branchDateRangeProvider);
    if (range.start != null && range.end != null) {
      return range.end!.add(const Duration(days: 1));
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  // ── Data fetchers ─────────────────────────────────────────────────────────

  /// Tokens summary — revenue = base price × daysOfMedicine per token.
  /// Zakat: PKR 20/day, Non-zakat: PKR 100/day, GMWF: PKR 0.
  Stream<Map<String, int>> _tokensStream(String branchId) {
    return ref.watch(serialsSummaryProvider(branchId).stream);
  }

  DashboardFilter _resolveFilter() {
    final range = ref.read(branchDateRangeProvider);
    if (range.start == null) {
      return const DashboardFilter(timeRange: TimeRange.today);
    }
    return DashboardFilter(
      timeRange: TimeRange.custom,
      customRange: DateTimeRange(
        start: range.start!,
        end: range.end ?? range.start!,
      ),
    );
  }

  Stream<Map<String, int>> _prescriptionsStream(String branchId) {
    return ref.watch(serialsSummaryProvider(branchId).stream).map((d) => {
      'v1': d['presc_waiting'] ?? 0,
      'v2': d['presc_prescribed'] ?? 0,
      'total': d['total'] ?? 0,
    });
  }

  Stream<Map<String, int>> _dispensaryCountStream(String branchId) {
    return ref.watch(serialsSummaryProvider(branchId).stream).map((d) => {
      'v1': d['disp_pending'] ?? 0,
      'v2': d['disp_dispensed'] ?? 0,
      'total': (d['disp_pending'] ?? 0) + (d['disp_dispensed'] ?? 0),
    });
  }



  Future<List<Map<String, dynamic>>> _waitingPatientsFuture(String branchId) async {
    final normBranchId = branchId.toLowerCase().trim();
    final days = _dateStrings(effectiveStart, effectiveEnd);
    final daysSet = days.toSet();
    final queues = ['zakat', 'non-zakat', 'gmwf'];
    final list = <Map<String, dynamic>>[];

    try {
      // Try high-performance collectionGroup query
      final snaps = await Future.wait([
        FirebaseFirestore.instance.collectionGroup('zakat').where('branchId', isEqualTo: normBranchId).get(),
        FirebaseFirestore.instance.collectionGroup('non-zakat').where('branchId', isEqualTo: normBranchId).get(),
        FirebaseFirestore.instance.collectionGroup('gmwf').where('branchId', isEqualTo: normBranchId).get(),
      ]);

      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final parts = doc.reference.path.split('/');
          if (parts.length >= 6) {
            final ds = parts[3];
            if (daysSet.contains(ds)) {
              final data = doc.data();
              final status = (data['status'] ?? '').toString().toLowerCase().trim();
              if (status == 'waiting' || status.isEmpty || status != 'completed') {
                list.add({
                  ...data,
                  'serial': data['serial'] ?? doc.id,
                  'type': data['queueType'] ?? _resolveType(data),
                });
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Branches] _waitingPatientsFuture collectionGroup error: $e. Falling back to parallel day queries.');
      list.clear();
      
      final allQueries = <Map<String, dynamic>>[];
      for (final ds in days) {
        for (final q in queues) {
          allQueries.add({
            'ds': ds,
            'q': q,
            'ref': FirebaseFirestore.instance.collection('branches/$normBranchId/serials/$ds/$q')
          });
        }
      }

      final snaps = <QuerySnapshot<Map<String, dynamic>>>[];
      const chunkSize = 40;
      for (int i = 0; i < allQueries.length; i += chunkSize) {
        final chunk = allQueries.sublist(i, (i + chunkSize).clamp(0, allQueries.length));
        final chunkFutures = chunk.map((item) => (item['ref'] as CollectionReference<Map<String, dynamic>>).get());
        final chunkSnaps = await Future.wait(chunkFutures);
        snaps.addAll(chunkSnaps);
      }

      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().toLowerCase().trim();
          if (status == 'waiting' || status.isEmpty || status != 'completed') {
            list.add({
              ...data,
              'serial': data['serial'] ?? doc.id,
              'type': data['queueType'] ?? _resolveType(data),
            });
          }
        }
      }
    }

    list.sort((a, b) {
      final ca = a['createdAt']?.toString() ?? '';
      final cb = b['createdAt']?.toString() ?? '';
      return ca.compareTo(cb);
    });
    return list;
  }

  Future<List<Map<String, dynamic>>> _fetchDispensaryDocsForDay(String branchId, String ds) async {
    final snap = await FirebaseFirestore.instance
        .collection('branches/$branchId/dispensary/$ds/$ds')
        .get();
    return snap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _enrichRawDocs(String branchId, List<Map<String, dynamic>> rawList) async {
    return LocalStorageService.enrichRawDocs(branchId, rawList);
  }

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty && s != 'null' && s != 'N/A') return s;
    }
    return '';
  }

  List<Map<String, dynamic>> _fallbackEnrich(List<Map<String, dynamic>> rawDocs) {
    return rawDocs.map((d) => {
      ...d,
      'name': _firstNonEmpty([d['patientName'], d['name'], 'Unknown']),
      'phone': d['phone']?.toString() ?? 'N/A',
      'age': d['age']?.toString() ?? d['patientAge']?.toString() ?? 'N/A',
      'gender': d['gender']?.toString() ?? d['patientGender']?.toString() ?? 'N/A',
      'displayCnic': _firstNonEmpty([d['patientCnic'], d['cnic'], d['guardianCnic'], 'N/A']),
      'isChild': (d['guardianCnic'] ?? '').toString().isNotEmpty && (d['patientCnic'] ?? d['cnic'] ?? '').toString().isEmpty,
      'doctorName': _firstNonEmpty([d['doctorName'], d['prescribedBy'], 'Unknown']),
      'dispenserName': _firstNonEmpty([d['dispenserName'], d['dispensedBy'], 'Unknown']),
      'tokenBy': _firstNonEmpty([d['createdByName'], d['tokenBy'], d['createdBy'], 'Unknown']),
      'daysOfMedicine': (d['daysOfMedicine'] as num?)?.toInt() ?? 1,
      'frequentFlag': d['frequentFlag'] ?? false,
    }).toList();
  }




  // ── Local cache helper (used by _consecutivePatientsFuture) ─────────────
  final Map<String, Future<List<Map<String, dynamic>>>> _inFlightCacheFutures = {};

  Future<List<Map<String, dynamic>>> _fetchDayCached({
    required String branchId,
    required String dayKey,
    required String type,
    required Future<List<Map<String, dynamic>>> Function() fetchSource,
  }) async {
    final todayKey = DateFormat('ddMMyy').format(DateTime.now());
    if (dayKey == todayKey) return await fetchSource();
    final cacheKey = '$branchId|$dayKey|$type';
    if (_inFlightCacheFutures.containsKey(cacheKey)) {
      return await _inFlightCacheFutures[cacheKey]!;
    }
    final cached = LocalStorageService.getBranchDayCache(branchId, dayKey, type);
    if (cached != null) return cached;
    final future = fetchSource().then((fresh) async {
      await LocalStorageService.putBranchDayCache(branchId, dayKey, type, fresh);
      _inFlightCacheFutures.remove(cacheKey);
      return fresh;
    }).catchError((e) {
      _inFlightCacheFutures.remove(cacheKey);
      throw e;
    });
    _inFlightCacheFutures[cacheKey] = future;
    return await future;
  }

  /// Convenience getter so legacy code can read the reverted set from Riverpod.
  Set<String> get _revertedPatientIds => ref.read(revertedPatientIdsProvider);

  Future<List<_ConsecutivePatient>> _consecutivePatientsFuture(String branchId) async {
    final normBranchId = branchId.toLowerCase().trim();
    try {
      final now    = DateTime.now();
      final today  = DateTime(now.year, now.month, now.day);
      final df     = DateFormat('ddMMyy');
      final windowDays = List.generate(7, (i) => today.subtract(Duration(days: i)));
      final windowKeys = windowDays.map(df.format).toList();

      final Map<String, Set<DateTime>> attendanceMap = {};
      for (final dk in windowKeys) {
        final dt = LocalStorageService.parseDdMMyy(dk);
        final dayDocs = await _fetchDayCached(
          branchId: normBranchId,
          dayKey: dk,
          type: 'dispensary',
          fetchSource: () => _fetchDispensaryDocsForDay(normBranchId, dk),
        );
        for (final data in dayDocs) {
          final pid = _resolvePatientId(data);
          if (pid.isEmpty) continue;
          attendanceMap.putIfAbsent(pid, () => {}).add(dt);
        }
      }

      final result        = <_ConsecutivePatient>[];
      final displayFormat = DateFormat('dd MMM yyyy');
      final candidatePids = <String>[];
      final pidToStreak   = <String, int>{};

      for (final entry in attendanceMap.entries) {
        final pid  = entry.key;
        final days = entry.value.toList()..sort((a, b) => b.compareTo(a));
        int streak       = 0;
        DateTime? cursor = today;
        for (final d in days) {
          if (cursor == null) break;
          if (d.isAtSameMomentAs(cursor) || d == cursor) {
            streak++;
            cursor = cursor.subtract(const Duration(days: 1));
          } else if (d.isBefore(cursor)) {
            break;
          }
        }
        if (streak >= 6 && !_revertedPatientIds.contains(pid)) {
          candidatePids.add(pid);
          pidToStreak[pid] = streak;
        }
      }

      if (candidatePids.isEmpty) return [];

      final patientSnaps = await Future.wait(
        candidatePids.map((pid) => FirebaseFirestore.instance
            .collection('branches/$normBranchId/patients')
            .doc(pid)
            .get()
            .then((snap) => MapEntry(pid, snap.data()))
            .catchError((_) => MapEntry(pid, null as Map<String, dynamic>?))
        )
      );
      final patientDataMap = Map.fromEntries(patientSnaps.where((e) => e.value != null));

      for (final pid in candidatePids) {
        final patientData = patientDataMap[pid] ?? {};
        if (patientData['frequentFlag'] == false) continue;
        Map<String, dynamic>? latestDispensary;
        for (final dk in windowKeys) {
          final dayDocs = await _fetchDayCached(
            branchId: normBranchId,
            dayKey: dk,
            type: 'dispensary',
            fetchSource: () => _fetchDispensaryDocsForDay(normBranchId, dk),
          );
          final match = dayDocs.firstWhere(
            (d) => _resolvePatientId(d) == pid,
            orElse: () => <String, dynamic>{},
          );
          if (match.isNotEmpty) {
            latestDispensary = Map<String, dynamic>.from(match);
            latestDispensary['dispenseDate'] =
                displayFormat.format(LocalStorageService.parseDdMMyy(dk));
            break;
          }
        }
        if (latestDispensary == null) continue;
        result.add(_ConsecutivePatient(
          data: {
            ...latestDispensary,
            'patientId': pid,
            'name': patientData['name'] ?? latestDispensary['patientName'] ?? 'Unknown',
            'phone': patientData['phone'] ?? latestDispensary['phone'] ?? 'N/A',
            'displayCnic': _firstNonEmpty([
              latestDispensary['patientCnic'], latestDispensary['cnic'],
              patientData['cnic']?.toString(),
              latestDispensary['guardianCnic'], patientData['guardianCnic']?.toString(),
            ]),
            'frequentFlag': patientData['frequentFlag'] ?? true,
          },
          streakDays: pidToStreak[pid]!,
        ));
      }
      result.sort((a, b) => b.streakDays.compareTo(a.streakDays));
      return result;
    } catch (e) {
      debugPrint('[Branches] _consecutivePatientsFuture error: $e');
      return [];
    }
  }

  Future<void> _revertFrequentFlag(String branchId, String patientId) async {
    final normBranchId = branchId.toLowerCase().trim();
    try {
      await FirebaseFirestore.instance
          .collection('branches/$normBranchId/patients')
          .doc(patientId)
          .set({'frequentFlag': false}, SetOptions(merge: true));
      // Update the provider set immutably
      final current = ref.read(revertedPatientIdsProvider);
      ref.read(revertedPatientIdsProvider.notifier).state =
          {...current, patientId};
    } catch (e) {
      debugPrint('[Branches] _revertFrequentFlag error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Failed to revert flag',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFF1C1C1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  String _resolvePatientId(Map<String, dynamic> data) {
    for (final key in ['patientId', 'id', 'uid']) {
      final v = data[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _resolveType(Map<String, dynamic> data) {
    final raw = (data['queueType'] ?? data['type'] ?? '').toString().toLowerCase().trim();
    switch (raw) {
      case 'zakat':     return 'zakat';
      case 'non-zakat': return 'non-zakat';
      case 'gmwf':      return 'gmwf';
      default:          return 'Unknown';
    }
  }

  // ── Date range selector ──────────────────────────────────────────────────

  /// Single pill-shaped trigger that opens the date picker sheet.
  /// Used in both compact (header toolbar) and full (tab body header) contexts.
  Widget _dateRangeSelector(RoleThemeData t, {bool compact = false}) {
    final range   = ref.watch(branchDateRangeProvider);
    final isToday = range.isToday;

    String label;
    if (isToday) {
      label = 'Today';
    } else if (range.start != null && range.end != null) {
      final s = range.start!;
      final e = range.end!;
      final same = s.year == e.year && s.month == e.month && s.day == e.day;
      if (same) {
        label = DateFormat('d MMM yyyy').format(s);
      } else {
        label = '${DateFormat('d MMM').format(s)} → ${DateFormat('d MMM').format(e)}';
      }
    } else {
      label = 'Select Range';
    }

    return GestureDetector(
      onTap: () => _showDateRangeBottomSheet(t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical:   compact ? 6  : 9),
        decoration: BoxDecoration(
          color: isToday
              ? t.bgCardAlt
              : t.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isToday ? t.bgRule : t.accent.withValues(alpha: 0.45),
            width: isToday ? 1 : 1.5,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isToday ? Icons.today_rounded : Icons.date_range_rounded,
            size: compact ? 13 : 15,
            color: isToday ? t.textTertiary : t.accent,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: isToday ? t.textSecondary : t.accent,
            ),
          ),
          if (!isToday) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => ref.read(branchDateRangeProvider.notifier).state =
                  const DateRange(),
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: t.danger.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded, size: 10, color: t.danger),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ignore: unused_element
  Widget _datePicker(RoleThemeData t, DateTime? value, Function(DateTime) onPick,
      DateTime first, DateTime last) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: first,
            lastDate: last);
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: t.bgCardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value != null ? t.accent.withValues(alpha: 0.4) : t.bgRule,
            width: value != null ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_month_rounded,
              size: 15,
              color: value != null ? t.accent : t.textTertiary),
          const SizedBox(width: 8),
          Text(
            value != null
                ? DateFormat('d MMM yyyy').format(value)
                : 'Pick date',
            style: TextStyle(
              fontSize: 13,
              fontWeight: value != null ? FontWeight.w700 : FontWeight.w400,
              color: value != null ? t.textPrimary : t.textTertiary,
            ),
          ),
        ]),
      ),
    );
  }

  void _showDateRangeBottomSheet(RoleThemeData t) {
    final currentRange = ref.read(branchDateRangeProvider);
    DateTime? tempStart = currentRange.start;
    DateTime? tempEnd   = currentRange.end;

    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final last7    = today.subtract(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);

    // Quick preset: label + start + end
    final presets = [
      ('Today',       today,       today),
      ('Yesterday',   yesterday,   yesterday),
      ('Last 7 Days', last7,       today),
      ('This Month',  monthStart,  today),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          bool isPreset(DateTime s, DateTime e) =>
              tempStart != null && tempEnd != null &&
              tempStart!.isAtSameMomentAs(s) && tempEnd!.isAtSameMomentAs(e);

          return Container(
            decoration: BoxDecoration(
              color: t.bgCard,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle ──────────────────────────────────────────
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: t.bgRule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Title ────────────────────────────────────────────────
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.date_range_rounded,
                        color: t.accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Filter by Date',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: t.textPrimary)),
                    Text('Select a range to filter records',
                        style: TextStyle(
                            fontSize: 11,
                            color: t.textTertiary)),
                  ]),
                ]),

                const SizedBox(height: 20),

                // ── Quick presets ─────────────────────────────────────────
                Text('Quick Select',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.textTertiary,
                        letterSpacing: 0.6)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: presets.map((p) {
                    final active = isPreset(p.$2, p.$3);
                    return GestureDetector(
                      onTap: () => setS(() {
                        tempStart = p.$2;
                        tempEnd   = p.$3;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? t.accent
                              : t.accent.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active
                                ? t.accent
                                : t.accent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(p.$1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: active ? Colors.white : t.accent,
                            )),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // ── Custom range From → To ────────────────────────────────
                Text('Custom Range',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.textTertiary,
                        letterSpacing: 0.6)),
                const SizedBox(height: 10),

                Row(children: [
                  // From
                  Expanded(
                    child: _datePickerTile(
                      t: t,
                      label: 'From',
                      value: tempStart,
                      icon: Icons.flight_takeoff_rounded,
                      accent: t.accent,
                      onTap: () async {
                        final p = await showDatePicker(
                          context: context,
                          initialDate: tempStart ?? today,
                          firstDate: DateTime(2024),
                          lastDate: today,
                        );
                        if (p != null) setS(() {
                          tempStart = p;
                          // Auto-clamp end if it's before new start
                          if (tempEnd != null && tempEnd!.isBefore(p)) {
                            tempEnd = p;
                          }
                        });
                      },
                    ),
                  ),

                  // Arrow connector
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(children: [
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: t.accent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.arrow_forward_rounded,
                            size: 14, color: t.accent),
                      ),
                    ]),
                  ),

                  // To
                  Expanded(
                    child: _datePickerTile(
                      t: t,
                      label: 'To',
                      value: tempEnd,
                      icon: Icons.flight_land_rounded,
                      accent: t.accent,
                      onTap: () async {
                        final p = await showDatePicker(
                          context: context,
                          initialDate: tempEnd ?? today,
                          firstDate: tempStart ?? DateTime(2024),
                          lastDate: today,
                        );
                        if (p != null) setS(() => tempEnd = p);
                      },
                    ),
                  ),
                ]),

                // Duration badge
                if (tempStart != null && tempEnd != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            () {
                              final diff = tempEnd!
                                  .difference(tempStart!).inDays + 1;
                              return diff == 1
                                  ? '1 day selected'
                                  : '$diff days selected';
                            }(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: t.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // ── Action buttons ────────────────────────────────────────
                Row(children: [
                  // Reset
                  TextButton(
                    onPressed: () {
                      ref.read(branchDateRangeProvider.notifier).state =
                          const DateRange();
                      Navigator.pop(ctx);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: t.bgRule),
                      ),
                    ),
                    child: Text('Reset',
                        style: TextStyle(
                            color: t.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  // Apply
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (tempStart != null || tempEnd != null) {
                          ref.read(branchDateRangeProvider.notifier).state =
                              DateRange(start: tempStart, end: tempEnd);
                        }
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              t.accent,
                              t.accent.withValues(alpha: 0.75),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('Apply Filter',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Individual date picker tile used inside the bottom sheet custom range row.
  Widget _datePickerTile({
    required RoleThemeData t,
    required String label,
    required DateTime? value,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.textTertiary,
                  letterSpacing: 0.4)),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: hasValue
                  ? accent.withValues(alpha: 0.07)
                  : t.bgCardAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasValue
                    ? accent.withValues(alpha: 0.45)
                    : t.bgRule,
                width: hasValue ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 16,
                    color: hasValue ? accent : t.textTertiary),
                const SizedBox(height: 6),
                Text(
                  hasValue
                      ? DateFormat('d MMM').format(value!)
                      : 'Pick',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: hasValue ? t.textPrimary : t.textTertiary,
                  ),
                ),
                if (hasValue)
                  Text(
                    DateFormat('yyyy').format(value!),
                    style: TextStyle(
                        fontSize: 10,
                        color: t.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // ── Filters ───────────────────────────────────────────────────────────────

  Widget _typeFilter(RoleThemeData t) {
    final multiDay   = ref.watch(branchMultiDayFilterProvider);
    final multiVisit = ref.watch(branchMultiVisitFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _filterChip(t, "All", null),
        const SizedBox(width: 6),
        _filterChip(t, "Zakat", "zakat"),
        const SizedBox(width: 6),
        _filterChip(t, "Non-Zakat", "non-zakat"),
        const SizedBox(width: 6),
        _filterChip(t, "GMWF", "gmwf"),
        const SizedBox(width: 6),
        _toggleChip(
          t,
          label: "Multi-day",
          icon: Icons.calendar_month_rounded,
          color: Colors.deepOrange,
          active: multiDay,
          onTap: () => ref.read(branchMultiDayFilterProvider.notifier).state =
              !multiDay,
        ),
        const SizedBox(width: 6),
        _toggleChip(
          t,
          label: "2+ Visits",
          icon: Icons.repeat_rounded,
          color: Colors.blue,
          active: multiVisit,
          onTap: () =>
              ref.read(branchMultiVisitFilterProvider.notifier).state =
                  !multiVisit,
        ),
      ]),
    );
  }

  Widget _filterChip(RoleThemeData t, String label, String? type) {
    final currentFilter = ref.watch(branchTypeFilterProvider);
    final selected = currentFilter == type;
    Color chipColor;
    if (type == 'zakat') {
      chipColor = t.zakat;
    } else if (type == 'non-zakat') chipColor = t.nonZakat;
    else if (type == 'gmwf')      chipColor = t.gmwf;
    else                          chipColor = t.accent;

    return GestureDetector(
      onTap: () => ref.read(branchTypeFilterProvider.notifier).state =
          selected ? null : type,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? chipColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? chipColor.withValues(alpha: 0.5) : t.bgRule),
        ),
        child: type == 'gmwf'
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Image.asset("assets/logo/gmwf.png", height: 12, width: 12),
                const SizedBox(width: 4),
                Text('GMWF', style: TextStyle(
                    color: selected ? chipColor : t.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
              ])
            : Text(label, style: TextStyle(
                color: selected ? chipColor : t.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
      ),
    );
  }

  Widget _toggleChip(
    RoleThemeData t, {
    required String label,
    required IconData icon,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color.withValues(alpha: 0.5) : t.bgRule),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? color : t.textSecondary),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
              color: active ? color : t.textSecondary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12)),
        ]),
      ),
    );
  }

  // ── Info row ──────────────────────────────────────────────────────────────

  Widget _infoRow(BuildContext context, IconData icon, String label, String value, {String? copy}) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: t.textTertiary),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 13, color: t.textSecondary, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, color: t.textPrimary, fontWeight: FontWeight.w700))),
          if (copy != null && copy.isNotEmpty && copy != 'N/A')
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: copy));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                    'Copied: $copy',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: const Color(0xFF1C1C1E),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.content_copy, size: 14, color: t.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  // ── Frequent patient card ─────────────────────────────────────────────────
  Widget _frequentPatientCard(
      BuildContext context, _ConsecutivePatient cp, String branchId, bool isManager) {
    final t       = RoleThemeScope.dataOf(context);
    final p       = cp.data;
    final isChild = p['isChild'] == true;
    const streakColor = Color(0xFFFF6B35);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: streakColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(color: streakColor.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: streakColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${cp.streakDays} consecutive days — frequent patient alert',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: streakColor),
              )),
              if (isManager)
                GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Revert Frequent Flag'),
                        content: Text(
                            'Remove the consecutive-patient alert for ${p['name']}? '
                            'This will clear the flag in Firestore.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: streakColor),
                            child: const Text('Revert', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _revertFrequentFlag(branchId, p['patientId']?.toString() ?? '');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: streakColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: streakColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.undo_rounded, size: 13, color: streakColor),
                      const SizedBox(width: 4),
                      Text('Revert',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: streakColor)),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(isChild ? Icons.child_care_rounded : Icons.person_rounded,
                    color: streakColor, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(p['name'] ?? 'Unknown',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary))),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(children: [
                  _infoRow(context, Icons.phone_rounded, 'Phone', p['phone'] ?? 'N/A'),
                  _infoRow(context, Icons.badge_rounded, isChild ? 'Guardian' : 'CNIC', p['displayCnic'] ?? 'N/A'),
                  _infoRow(context, Icons.calendar_today_rounded, 'Last Visit', p['dispenseDate'] ?? 'N/A'),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchDetails(String branchName, String originalBranchId) {
    final branchId = originalBranchId.toLowerCase().trim();
    
    () async {
      try {
        final branchesSnap = await FirebaseFirestore.instance.collection('branches').get();
        final buffer = StringBuffer();
        buffer.writeln('=== DIAGNOSTICS FOR BRANCHES ===');
        buffer.writeln('Selected branchId: $branchId');
        buffer.writeln('Original branchId: $originalBranchId');
        buffer.writeln('All Firestore Branch IDs: ${branchesSnap.docs.map((d) => d.id).toList()}');
        
        print('=== DIAGNOSTICS FOR BRANCHES ===');
        print('Selected branchId: $branchId');
        print('Original branchId: $originalBranchId');
        print('All Firestore Branch IDs: ${branchesSnap.docs.map((d) => d.id).toList()}');

        final days = ['010726', '020726', '030726', '040726', '050726', '060726', '070726'];
        for (final d in days) {
          final sL = await FirebaseFirestore.instance.collection('branches/sialkot/dispensary/$d/$d').get();
          final sU = await FirebaseFirestore.instance.collection('branches/Sialkot/dispensary/$d/$d').get();
          final sSkt = await FirebaseFirestore.instance.collection('branches/skt/dispensary/$d/$d').get();
          final sSktU = await FirebaseFirestore.instance.collection('branches/SKT/dispensary/$d/$d').get();
          
          buffer.writeln('Date $d: Lowercase = ${sL.docs.length}, Uppercase = ${sU.docs.length}, skt = ${sSkt.docs.length}, SKT = ${sSktU.docs.length}');
          print('Date $d: Lowercase = ${sL.docs.length}, Uppercase = ${sU.docs.length}, skt = ${sSkt.docs.length}, SKT = ${sSktU.docs.length}');
          
          final cached = LocalStorageService.getBranchDayCache('sialkot', d, 'dispensary');
          buffer.writeln('  Cache status: ${cached != null ? "${cached.length} items" : "NULL"}');
          print('  Cache status: ${cached != null ? "${cached.length} items" : "NULL"}');
          
          if (cached != null && cached.isEmpty) {
            final box = Hive.box(LocalStorageService.branchCacheBox);
            final key = LocalStorageService.branchCacheKey('sialkot', d, 'dispensary');
            await box.delete(key);
            print('DELETED empty cache for sialkot $d to force reload');
            buffer.writeln('  -> Deleted empty cache key to force reload');
          }

          if (sL.docs.isNotEmpty) {
            buffer.writeln('  Lower sample data: ${sL.docs.first.data()}');
          }
          if (sU.docs.isNotEmpty) {
            buffer.writeln('  Upper sample data: ${sU.docs.first.data()}');
          }
          if (sSkt.docs.isNotEmpty) {
            buffer.writeln('  skt sample data: ${sSkt.docs.first.data()}');
          }
          if (sSktU.docs.isNotEmpty) {
            buffer.writeln('  SKT sample data: ${sSktU.docs.first.data()}');
          }
        }

        final file = io.File('e:/GMWF/gmwf/debug_branches.txt');
        await file.writeAsString(buffer.toString());
      } catch (e, stack) {
        print('Error running diagnostics: $e');
        final file = io.File('e:/GMWF/gmwf/debug_branches.txt');
        await file.writeAsString('Error running diagnostics: $e\n$stack');
      }
    }();

    final dateKey = '$branchId|${effectiveStart.toIso8601String()}|${effectiveEnd.toIso8601String()}';
    if (!_loadedKeys.contains(dateKey)) {
      _loadedKeys.removeWhere((k) => k.startsWith('$branchId|'));
      _loadedKeys.add(dateKey);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(dispensaryProvider(branchId).notifier)
            .load(effectiveStart, effectiveEnd);
      });
    }


    final isSupervisor = widget.branchId != null;
    final t            = RoleThemeScope.dataOf(context);

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final int crossAxisCount;
      if (width < 600) {
        crossAxisCount = 1;
      } else if (width < 950) {
        crossAxisCount = 2;
      } else {
        crossAxisCount = 3;
      }
      
      final isMobile = width < 600;
      final double horizontalPadding = isMobile ? 28.0 : 56.0;
      final double availableWidth = width - horizontalPadding;

      final tokStream  = _tokensStream(branchId);
      final presStream = _prescriptionsStream(branchId);
      final dispStream = _dispensaryCountStream(branchId);

      return Container(
        color: t.bg,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 14 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // ── Header ────────────────────────────────────────────────────
              LayoutBuilder(
                builder: (context, headerConstraints) {
                  final isHeaderMobile = headerConstraints.maxWidth < 800;
                  
                  final titleSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branchName,
                        style: TextStyle(
                          fontSize: 28, 
                          fontWeight: FontWeight.w900, 
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Branch Performance', 
                        style: TextStyle(color: t.textTertiary, fontSize: 13),
                      ),
                    ],
                  );

                  final actionsSection = Column(
                    crossAxisAlignment: isHeaderMobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                    children: [
                      if (!isSupervisor) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _actionButton(
                              t,
                              icon: Icons.inventory_rounded,
                              label: "Inventory",
                              color: t.nonZakat,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InventoryPage(
                                    branchId: branchId,
                                    isDispenser: false,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _actionButton(
                              t,
                              icon: Icons.monetization_on_outlined,
                              label: "Finance",
                              color: t.gmwf,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FinancePage(
                                    branchId: branchId,
                                    isAdmin: true,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      _dateRangeSelector(t, compact: isHeaderMobile),
                    ],
                  );

                  if (isHeaderMobile) {
                     return Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         titleSection,
                         const SizedBox(height: 16),
                         actionsSection,
                       ],
                     );
                  } else {
                     return Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Expanded(child: titleSection),
                         const SizedBox(width: 16),
                         actionsSection,
                       ],
                     );
                  }
                },
              ),

              const SizedBox(height: 22),

              // ── Summary Cards ─────────────────────────────────────────────
              if (width > 800)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: PatientSummaryCard(
                        title: "Tokens", dataStream: tokStream,
                        variant: SummaryCardVariant.tokens,
                        titleIcon: Icons.people_alt_rounded, showRevenue: true,
                        valueIcons: {
                          'v1': Icons.favorite_rounded, 'v2': Icons.group_rounded,
                          'v3': Icons.handshake_rounded, 'total': Icons.people_alt_rounded,
                        },
                        valueLabels: {'v1': 'Zakat', 'v2': 'Non-Zakat', 'v3': 'GMWF'},
                        isFiltered: ref.read(branchDateRangeProvider).start != null,
                      )),
                      const SizedBox(width: 14),
                      Expanded(child: PatientSummaryCard(
                        title: "Prescriptions", dataStream: presStream,
                        variant: SummaryCardVariant.prescriptions,
                        titleIcon: Icons.medical_information_rounded,
                        valueIcons: {
                          'v1': Icons.timer_rounded, 'v2': Icons.check_circle_rounded,
                          'total': Icons.medical_information_rounded,
                        },
                        valueLabels: {'v1': 'Waiting', 'v2': 'Prescribed'},
                      )),
                      const SizedBox(width: 14),
                      Expanded(child: PatientSummaryCard(
                        title: "Dispensary",
                        dataStream: dispStream,
                        variant: SummaryCardVariant.dispensary,
                        titleIcon: Icons.local_pharmacy_rounded,
                        valueIcons: {
                          'v1': Icons.access_time_rounded,
                          'v2': Icons.done_all_rounded,
                          'total': Icons.local_pharmacy_rounded,
                        },
                        valueLabels: {
                          'v1': 'Pending',
                          'v2': 'Dispensed',
                        },
                      )),
                    ],
                  ),
                )
              else
                Column(children: [
                PatientSummaryCard(
                  title: "Tokens", dataStream: tokStream,
                  variant: SummaryCardVariant.tokens,
                  titleIcon: Icons.people_alt_rounded, showRevenue: true,
                  valueIcons: {
                    'v1': Icons.favorite_rounded, 'v2': Icons.group_rounded,
                    'v3': Icons.handshake_rounded, 'total': Icons.people_alt_rounded,
                  },
                  valueLabels: {'v1': 'Zakat', 'v2': 'Non-Zakat', 'v3': 'GMWF'},
                  isFiltered: ref.read(branchDateRangeProvider).start != null,
                ),
                const SizedBox(height: 12),
                PatientSummaryCard(
                  title: "Prescriptions", dataStream: presStream,
                  variant: SummaryCardVariant.prescriptions,
                  titleIcon: Icons.medical_information_rounded,
                  valueIcons: {
                    'v1': Icons.timer_rounded, 'v2': Icons.check_circle_rounded,
                    'total': Icons.medical_information_rounded,
                  },
                  valueLabels: {'v1': 'Waiting', 'v2': 'Prescribed'},
                ),
                const SizedBox(height: 12),
                PatientSummaryCard(
                  title: "Dispensary",
                  dataStream: dispStream,
                  variant: SummaryCardVariant.dispensary,
                  titleIcon: Icons.local_pharmacy_rounded,
                  valueIcons: {
                    'v1': Icons.access_time_rounded, 'v2': Icons.done_all_rounded,
                    'total': Icons.local_pharmacy_rounded,
                  },
                  valueLabels: {'v1': 'Pending', 'v2': 'Dispensed'},
                ),
              ]),

              const SizedBox(height: 28),

              // ── Frequent / Consecutive Patients Section ───────────────────
              Builder(builder: (context) {
                final revertedIds = ref.watch(revertedPatientIdsProvider);
                return FutureBuilder<List<_ConsecutivePatient>>(
                key: ValueKey('consecutive-$branchId-${revertedIds.length}'),
                future: _consecutivePatientsFuture(branchId),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final patients = snap.data ?? [];
                  if (patients.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.35)),
                        ),
                        child: Row(children: [
                          const Text('🔥', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Frequent Patients (6+ consecutive days)',
                                style: TextStyle(
                                    fontSize: isMobile ? 14 : 16,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFFF6B35))),
                            Text(
                              widget.isManager
                                  ? '${patients.length} patient${patients.length == 1 ? '' : 's'} flagged — tap Revert to dismiss'
                                  : '${patients.length} patient${patients.length == 1 ? '' : 's'} flagged',
                              style: TextStyle(fontSize: 11, color: t.textTertiary),
                            ),
                          ])),
                        ]),
                      ),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: patients.map((cp) => SizedBox(
                          width: (availableWidth - (14 * (crossAxisCount - 1))) / crossAxisCount,
                          child: _frequentPatientCard(context, cp, branchId, widget.isManager),
                        )).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              );
              }),  // end Builder for revertedIds

              // ── Patients Waiting for Prescription ──────────────────────────
              FutureBuilder<List<Map<String, dynamic>>>(
                key: ValueKey('waiting-$branchId-${ref.read(branchDateRangeProvider).start}-${ref.read(branchDateRangeProvider).end}'),
                future: _waitingPatientsFuture(branchId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final waiting = snapshot.data ?? [];
                  if (waiting.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Patients Waiting for Prescription (${waiting.length})", style: TextStyle(
                          fontSize: isMobile ? 17 : 20,
                          fontWeight: FontWeight.w800, color: t.textPrimary)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: waiting.map((p) {
                          final name = p['patientName'] ?? 'Unknown';
                          final serial = p['serial'] ?? 'N/A';
                          final type = p['queueType'] ?? 'zakat';
                          final cnic = p['patientCnic'] ?? p['cnic'] ?? p['guardianCnic'] ?? 'N/A';
                          final time = p['createdAt'] != null
                              ? DateFormat('hh:mm a').format(DateTime.parse(p['createdAt']))
                              : 'N/A';
                          Color typeColor = type == 'zakat' ? t.zakat : (type == 'non-zakat' ? t.nonZakat : t.gmwf);

                          return SizedBox(
                            width: (availableWidth - (14 * (crossAxisCount - 1))) / crossAxisCount,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: t.bgCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: t.bgRule),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(p['guardianCnic'] != null ? Icons.child_care_rounded : Icons.person_rounded, color: typeColor, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                      child: Text(type.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: typeColor)),
                                    ),
                                  ]),
                                  const SizedBox(height: 10),
                                  _infoRow(context, Icons.tag_rounded, 'Serial', serial),
                                  _infoRow(context, Icons.badge_rounded, p['guardianCnic'] != null ? 'Guardian' : 'CNIC', cnic),
                                  _infoRow(context, Icons.access_time_rounded, 'Check-in Time', time),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 28),
                    ],
                  );
                },
              ),

              // ── Dispensed Patients ────────────────────────────────────────
              Text("Dispensed Patients", style: TextStyle(
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w800, color: t.textPrimary)),
              const SizedBox(height: 10),
              _typeFilter(t),
              const SizedBox(height: 16),

              Consumer(builder: (context, ref, _) {
                final dispState = ref.watch(dispensaryProvider(branchId));
                final allList  = dispState.records;
                final syncing  = dispState.isSyncing;
                final error    = dispState.error;
                
                () async {
                  try {
                    final file = io.File('e:/GMWF/gmwf/debug_branches.txt');
                    await file.writeAsString(
                      '\n=== UI BUILD LOG ===\nbranchId: $branchId\nallList.length: ${allList.length}\nsyncing: $syncing\nerror: $error\n',
                      mode: io.FileMode.append,
                    );
                  } catch (_) {}
                }();
                {
                  {
                    {
                          final typeFilter  = ref.watch(branchTypeFilterProvider);
                  final multiDay2  = ref.watch(branchMultiDayFilterProvider);
                  final multiVisit2 = ref.watch(branchMultiVisitFilterProvider);
                  final filtered = allList.where((p) {
                            if (typeFilter != null &&
                                p['type']?.toString().toLowerCase() != typeFilter) {
                              return false;
                            }
                            if (multiDay2) {
                              final days = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
                              if (days <= 1) return false;
                            }
                            if (multiVisit2) {
                              final totalVisits = (p['totalVisits'] as num?)?.toInt() ?? 0;
                              if (totalVisits <= 1) return false;
                            }
                            return true;
                          }).toList();

                          if (allList.isEmpty && syncing) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: t.accent),
                                    const SizedBox(height: 12),
                                    Text("Syncing dispensary records...", style: TextStyle(color: t.textTertiary, fontSize: 13)),
                                  ],
                                ),
                              ),
                            );
                          }

                          Widget? headerWidget;
                          if (syncing) {
                            headerWidget = Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                                  ),
                                  const SizedBox(width: 8),
                                  Text("Syncing remaining days...", style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                ],
                              ),
                            );
                          } else if (error != null) {
                            headerWidget = Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 14, color: t.danger),
                                  const SizedBox(width: 6),
                                  Text(error, style: TextStyle(color: t.danger, fontSize: 11)),
                                ],
                              ),
                            );
                          }

                          if (filtered.isEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (headerWidget != null) headerWidget,
                                Container(
                                  padding: const EdgeInsets.all(40),
                                  child: Center(
                                    child: Text(
                                      allList.isEmpty ? "No dispensed records found" : "No patients match the filter",
                                      style: TextStyle(color: t.textTertiary),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (headerWidget != null) headerWidget,
                              Wrap(
                                spacing: 14,
                                runSpacing: 14,
                                children: filtered.map((p) {
                                  final isChild     = p['isChild'] == true;
                                  final pid         = p['patientId']?.toString() ?? '';
                                  final revertedIds2 = ref.watch(revertedPatientIdsProvider);
                                  final isFrequent  = !revertedIds2.contains(pid) &&
                                                      (p['frequentFlag'] == true);
                                  final medicDays   = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
                                  final tokenAmount = (p['tokenAmount'] as num?)?.toInt() ?? 0;

                                  Color typeColor;
                                  if (p['type'] == 'zakat') {
                                    typeColor = t.zakat;
                                  } else if (p['type'] == 'non-zakat') typeColor = t.nonZakat;
                                  else if (p['type'] == 'gmwf')      typeColor = t.gmwf;
                                  else                               typeColor = t.textTertiary;

                                  return SizedBox(
                                    width: (availableWidth - (14 * (crossAxisCount - 1))) / crossAxisCount,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: t.bgCard,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isFrequent
                                              ? const Color(0xFFFF6B35).withValues(alpha: 0.5)
                                              : t.bgRule,
                                          width: isFrequent ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                                            child: Row(children: [
                                              Icon(isChild ? Icons.child_care_rounded : Icons.person_rounded,
                                                  color: typeColor, size: 20),
                                              const SizedBox(width: 8),
                                              Expanded(child: Text(p['name'] ?? 'Unknown',
                                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 14,
                                                      fontWeight: FontWeight.w700, color: t.textPrimary))),

                                              if (isFrequent)
                                                const Padding(
                                                  padding: EdgeInsets.only(right: 6),
                                                  child: Text('🔥', style: TextStyle(fontSize: 14)),
                                                ),

                                              if (medicDays > 1)
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.deepOrange.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
                                                    ),
                                                    child: Text('$medicDays d',
                                                        style: const TextStyle(
                                                            fontSize: 9,
                                                            fontWeight: FontWeight.w700,
                                                            color: Colors.deepOrange)),
                                                  ),
                                                ),

                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                    color: typeColor.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: typeColor.withValues(alpha: 0.3))),
                                                child: Text((p['type'] ?? '??').toString().toUpperCase().substring(0, 1),
                                                    style: TextStyle(color: typeColor,
                                                        fontWeight: FontWeight.w800, fontSize: 9)),
                                              ),
                                            ]),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                            child: Divider(height: 14, color: t.bgRule),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                                            child: Column(
                                              children: [
                                                _infoRow(context, Icons.calendar_today_rounded, 'Date',
                                                    p['dispenseDate'] ?? 'N/A'),
                                                _infoRow(context, Icons.tag_rounded,
                                                    'Serial', p['serial'] ?? 'N/A',
                                                    copy: p['serial']?.toString()),
                                                _infoRow(context, Icons.badge_rounded,
                                                    isChild ? "Guardian" : "CNIC", p['displayCnic'] ?? 'N/A',
                                                    copy: p['displayCnic']?.toString()),
                                                if (isChild && p['guardianName'] != null)
                                                  _infoRow(context, Icons.family_restroom_rounded,
                                                      'Parent', p['guardianName']),
                                                _infoRow(context, Icons.phone_rounded,
                                                    'Phone', p['phone'] ?? 'N/A',
                                                    copy: p['phone']?.toString()),
                                                _infoRow(context, Icons.cake_rounded,
                                                    'Age', '${p['age'] ?? 'N/A'} yrs'),
                                                _infoRow(context, Icons.wc_rounded,
                                                    'Gender', p['gender'] ?? 'N/A'),
                                                if (p['bloodGroup'] != null && p['bloodGroup'] != 'N/A')
                                                  _infoRow(context, Icons.bloodtype_rounded,
                                                      'Blood', p['bloodGroup']),
                                                _infoRow(context, Icons.medical_services_rounded,
                                                    'Doctor', p['doctorName'] ?? 'Unknown'),
                                                _infoRow(context, Icons.confirmation_number_rounded,
                                                    'Token by', p['tokenBy'] ?? 'Unknown'),
                                                _infoRow(context, Icons.local_pharmacy_rounded,
                                                    'Disp', p['dispenserName'] ?? 'Unknown'),
                                                if (medicDays > 1)
                                                  _infoRow(context, Icons.calendar_month_rounded,
                                                      'Medicine', '$medicDays days'),
                                                if (tokenAmount > 0)
                                                  _infoRow(context, Icons.payments_rounded,
                                                      'Charged', 'PKR $tokenAmount'),
                                                const SizedBox(height: 12),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: ElevatedButton.icon(
                                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PatientDetailScreen(
                                                      patientId: pid,
                                                      isOnline: true,
                                                      localBox: Hive.box('local_patients'),
                                                      branchId: branchId,
                                                      doctorId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
                                                      isAdmin: true,
                                                    ))),
                                                    icon: const Icon(Icons.person_search_rounded, size: 15),
                                                    label: const Text('View Full Profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: typeColor, foregroundColor: Colors.white,
                                                      elevation: 0, padding: const EdgeInsets.symmetric(vertical: 10),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ]),
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          );
                        }
                      }
                    }
              }),
            ],
          ),
        ),
      ),
    );
    });
  }

  Widget _actionButton(RoleThemeData t, {required IconData icon, required String label,
      required Color color, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color, 
                fontSize: 12, 
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t                = RoleThemeScope.dataOf(context);
    final isSupervisorMode = widget.branchId != null;
    final isMobile         = MediaQuery.of(context).size.width < 600;

    if (isSupervisorMode) {
      final branchName = widget.branchId![0].toUpperCase() +
          widget.branchId!.substring(1).replaceAll('-', ' ');
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          title: Text("Branch: $branchName", style: TextStyle(
              color: t.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
          backgroundColor: t.bgCard,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: t.textPrimary),
          bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: t.bgRule)),
        ),
        body: _buildBranchDetails(branchName, widget.branchId!),
      );
    }

    final branchesAsync = ref.watch(branchesListProvider);

    return Scaffold(
      backgroundColor: t.bg,
      body: branchesAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: t.accent)),
        error: (e, _) => Center(
          child: Text('Error loading branches: $e',
              style: TextStyle(color: t.danger))),
        data: (branchMaps) {
          if (branchMaps.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.store_rounded, size: 48, color: t.bgRule),
                const SizedBox(height: 16),
                Text("No branches found", style: TextStyle(color: t.textTertiary, fontSize: 16)),
                if (widget.showRegisterButton) ...[
                  const SizedBox(height: 16),
                  _registerBranchButton(context, t),
                ],
              ]),
            );
          }

          final branches = branchMaps
              .map((m) => MapEntry(m['name'] as String, m['id'] as String))
              .toList();

          return DefaultTabController(
            length: branches.length,
            child: Column(children: [
              if (branches.length > 1)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.bgRule),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          isScrollable: true,
                          labelColor: t.accent,
                          unselectedLabelColor: t.textTertiary,
                          indicator: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                          tabs: branches.map((e) => Tab(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.store_rounded, size: 16),
                                  const SizedBox(width: 6),
                                  Text(e.key),
                                ],
                              ),
                            ),
                          )).toList(),
                        ),
                      ),
                      if (widget.showRegisterButton)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: isMobile
                              ? IconButton(
                                  icon: Icon(Icons.add_business_rounded, color: t.accent, size: 22),
                                  onPressed: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => BranchesRegister())),
                                  tooltip: 'New Branch',
                                )
                              : ElevatedButton.icon(
                                  icon: Icon(Icons.add_business_rounded,
                                      size: 16, color: t.bgCard),
                                  label: Text("New Branch", style: TextStyle(
                                      color: t.bgCard, fontWeight: FontWeight.w800, fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: t.accent, elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8))),
                                  onPressed: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => BranchesRegister())),
                                ),
                        ),
                    ],
                  ),
                ),
              Expanded(child: TabBarView(
                children: branches.map((e) => _buildBranchDetails(e.key, e.value)).toList(),
              )),
            ]),
          );
        },
      ),
    );
  } // end build

  Widget _registerBranchButton(BuildContext context, RoleThemeData t) {
    return ElevatedButton.icon(
      icon: Icon(Icons.add_business_rounded, color: t.bgCard),
      label: Text("Register New Branch",
          style: TextStyle(color: t.bgCard, fontWeight: FontWeight.w800)),
      style: ElevatedButton.styleFrom(
          backgroundColor: t.accent, elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      onPressed: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => BranchesRegister())),
    );
  }





  Widget _filterChipMobile(String label, RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: t.accent.withValues(alpha: 0.2))),
      child: Text(label, style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildPatientLogTab(String branchId, RoleThemeData t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Dispensed Patients", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.textPrimary)),
          const SizedBox(height: 12),
          _typeFilter(t),
          const SizedBox(height: 16),
          Consumer(builder: (context, ref, _) {
            final dispState = ref.watch(dispensaryProvider(branchId));
            final allList   = dispState.records;
            final typeF     = ref.watch(branchTypeFilterProvider);
            final mDay      = ref.watch(branchMultiDayFilterProvider);
            final mVisit    = ref.watch(branchMultiVisitFilterProvider);
            {
              final filtered = allList.where((p) {
                if (typeF != null && p['type']?.toString().toLowerCase() != typeF) return false;
                if (mDay) {
                  final days = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
                  if (days <= 1) return false;
                }
                if (mVisit) {
                  final totalVisits = (p['totalVisits'] as num?)?.toInt() ?? 0;
                  if (totalVisits <= 1) return false;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No matches", style: TextStyle(color: t.textTertiary))));

              return Column(
                children: filtered.map((p) {
                  final pid = p['patientId']?.toString() ?? '';
                  final revIds = ref.watch(revertedPatientIdsProvider);
                  final isFrequent = !revIds.contains(pid) && (p['frequentFlag'] == true);
                  final medicDays = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
                  final type = p['type']?.toString() ?? 'unknown';
                  Color typeColor = type == 'zakat' ? t.zakat : (type == 'non-zakat' ? t.nonZakat : (type == 'gmwf' ? t.gmwf : t.textTertiary));

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: t.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: isFrequent ? const Color(0xFFFF6B35).withValues(alpha: 0.5) : t.bgRule, width: isFrequent ? 1.5 : 1)),
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(p['isChild'] == true ? Icons.child_care_rounded : Icons.person_rounded, color: typeColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(p['name'] ?? 'Unknown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary))),
                          if (isFrequent) const Text('🔥', style: TextStyle(fontSize: 14)),
                          if (medicDays > 1) Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.deepOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Text('$medicDays d', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.deepOrange))),
                        ]),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          _infoRow(context, Icons.calendar_today_rounded, 'Date', p['dispenseDate'] ?? 'N/A'),
                          _infoRow(context, Icons.tag_rounded, 'Serial', p['serial'] ?? 'N/A'),
                          _infoRow(context, Icons.badge_rounded, p['isChild'] == true ? "Guardian" : "CNIC", p['displayCnic'] ?? 'N/A'),
                        ]),
                      ),
                    ]),
                  );
                }).toList(),
              );
            }
          }),
        ],
      ),
    );
  }

  Widget _buildFlagsTab(String branchId, RoleThemeData t) {
    return FutureBuilder<List<_ConsecutivePatient>>(
      future: _consecutivePatientsFuture(branchId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final patients = snap.data ?? [];
        if (patients.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.withValues(alpha: 0.3)), const SizedBox(height: 16), Text("No flagged patients", style: TextStyle(color: t.textTertiary))]));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: patients.length,
          itemBuilder: (context, i) => _frequentPatientCard(context, patients[i], branchId, widget.isManager),
        );
      },
    );
  }
}