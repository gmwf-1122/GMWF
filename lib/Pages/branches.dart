// lib/pages/branches.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../widgets/dashboard_widgets.dart';

import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import 'dispensary/dispensar/inventory.dart';
import 'assets.dart';
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
  try { return DateFormat('ddMMyy').parse(dateKeyFallback); }
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

  const PatientSummaryCard({
    super.key,
    required this.title,
    required this.dataStream,
    required this.titleIcon,
    required this.variant,
    this.showRevenue = false,
    required this.valueIcons,
    required this.valueLabels,
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
                    const Text("Today's Revenue",
                        style: TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w600)),
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
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: fill.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
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

class Branches extends StatefulWidget {
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
  State<Branches> createState() => _BranchesState();
}

class _BranchesState extends State<Branches> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _mobileTabController;
  String? selectedTypeFilter;
  bool filterMultiDay   = false;
  bool filterMultiVisit = false;
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  final Set<String> _revertedPatientIds = {};

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _mobileTabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  DateTime get effectiveStart {
    if (selectedStartDate != null && selectedEndDate != null) return selectedStartDate!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get effectiveEnd {
    if (selectedStartDate != null && selectedEndDate != null)
      return selectedEndDate!.add(const Duration(days: 1));
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  // ── Data fetchers ─────────────────────────────────────────────────────────

  /// Tokens summary — revenue = base price × daysOfMedicine per token.
  /// Zakat: PKR 20/day, Non-zakat: PKR 100/day, GMWF: PKR 0.
  Stream<Map<String, int>> _tokensStream(String branchId) {
    return streamBranchStats(branchId, filter: _resolveFilter()).map((s) => {
      'v1': s.zakat,
      'v1_sub': s.zakatRevenue,
      'v2': s.nonZakat,
      'v2_sub': s.nonZakatRevenue,
      'v3': s.gmwf,
      'v3_sub': s.gmwfRevenue,
      'total': s.tokens,
      'revenue': s.dispensaryRevenue,
    });
  }

  DashboardFilter _resolveFilter() {
    if (selectedStartDate == null) {
      return const DashboardFilter(timeRange: TimeRange.today);
    }
    return DashboardFilter(
      timeRange: TimeRange.custom,
      customRange: DateTimeRange(
        start: selectedStartDate!,
        end: selectedEndDate ?? selectedStartDate!,
      ),
    );
  }


  Stream<Map<String, int>> _prescriptionsStream(String branchId) {
    try {
      final days = _dateStrings(effectiveStart, effectiveEnd);
      if (days.length > 2) {
        return Stream.fromFuture(_prescriptionsFuture(branchId));
      }

      final queues = ['zakat', 'non-zakat', 'gmwf'];
      final streams = <Stream<QuerySnapshot>>[];
      for (final ds in days) {
        final base = FirebaseFirestore.instance
            .collection('branches').doc(branchId).collection('serials').doc(ds);
        for (final q in queues) {
          streams.add(base.collection(q).snapshots());
        }
      }

      return Rx.combineLatestList(streams).map((snaps) {
        int total = 0;
        int prescribed = 0;
        for (final snap in snaps) {
          total += snap.size;
          for (final doc in snap.docs) {
             final data = doc.data() as Map<String, dynamic>;
             if (data['status'] == 'completed') prescribed++;
          }
        }
        return {'v1': total - prescribed, 'v2': prescribed, 'total': total};
      });
    } catch (e) {
      return Stream.value({'v1': 0, 'v2': 0, 'total': 0});
    }
  }

  Future<Map<String, int>> _prescriptionsFuture(String branchId) async {
    try {
      final days   = _dateStrings(effectiveStart, effectiveEnd);
      final queues = ['zakat', 'non-zakat', 'gmwf'];
      final snapFutures = <Future<QuerySnapshot>>[];
      for (final ds in days) {
        final base = FirebaseFirestore.instance
            .collection('branches').doc(branchId).collection('serials').doc(ds);
        for (final q in queues) snapFutures.add(base.collection(q).get());
      }
      final allSnaps = await Future.wait(snapFutures);
      final entries  = <Map<String, dynamic>>[];
      for (final snap in allSnaps) {
        for (final doc in snap.docs) {
          final data   = doc.data() as Map<String, dynamic>;
          final serial = data['serial']?.toString().trim() ?? doc.id;
          if (serial.isEmpty) continue;
          final statusOnDoc = data['status']?.toString().toLowerCase().trim() ?? '';
          String rawCnic = '';
          for (final key in ['patientCnic', 'cnic', 'guardianCnic', 'patientCNIC', 'guardianCNIC']) {
            final v       = data[key]?.toString().trim() ?? '';
            final stripped = v.replaceAll('-', '').replaceAll(' ', '');
            if (stripped.isNotEmpty && stripped != '0000000000000') { rawCnic = v; break; }
          }
          entries.add({
            'serial': serial, 'cnicRaw': rawCnic,
            'cnicStripped': rawCnic.replaceAll('-', '').replaceAll(' ', ''),
            'statusOnDoc': statusOnDoc,
          });
        }
      }
      final total = entries.length;
      if (total == 0) return {'v1': 0, 'v2': 0, 'total': 0};
      final presRoot = FirebaseFirestore.instance
          .collection('branches').doc(branchId).collection('prescriptions');
      final checkFutures = entries.map((e) async {
        if (e['statusOnDoc'] == 'completed') return true;
        final serial       = e['serial'] as String;
        final cnicRaw      = e['cnicRaw'] as String;
        final cnicStripped = e['cnicStripped'] as String;
        if (cnicRaw.isEmpty) return false;
        final candidateCnics = <String>{};
        if (cnicRaw.isNotEmpty) candidateCnics.add(cnicRaw);
        if (cnicStripped.isNotEmpty && cnicStripped != cnicRaw) candidateCnics.add(cnicStripped);
        for (final cnic in candidateCnics) {
          final snap = await presRoot.doc(cnic).collection('prescriptions').doc(serial).get();
          if (snap.exists) return true;
        }
        return false;
      }).toList();
      final results    = await Future.wait(checkFutures);
      final prescribed = results.where((r) => r).length;
      return {'v1': total - prescribed, 'v2': prescribed, 'total': total};
    } catch (e) { return {'v1': 0, 'v2': 0, 'total': 0}; }
  }

  Stream<Map<String, int>> _dispensaryCountStream(String branchId) {
    try {
      final days = _dateStrings(effectiveStart, effectiveEnd);
      // Stream version simply returns zeros for now if too many days, or listens to the latest day
      // To properly stream a complex count logic like this, we'd need multiple snapshot listeners combined.
      // For the most important 'Today' updates, we use snapshots.
      if (days.length > 1) {
        // Fallback for custom range to avoid massive listener count
        return Stream.fromFuture(_dispensaryCountFuture(branchId));
      }

      final ds = days.first;
      final queues = ['zakat', 'non-zakat', 'gmwf'];
      
      final dispStream = FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$ds/$ds')
          .snapshots();

      final serialStreams = queues.map((q) => FirebaseFirestore.instance
          .collection('branches/$branchId/serials/$ds/$q')
          .where('status', isEqualTo: 'completed')
          .snapshots()).toList();

      return Rx.combineLatest2(dispStream, Rx.combineLatestList(serialStreams), (dispSnap, serialSnaps) {
        final dispensedCount = dispSnap.size;
        final completedSerials = <String>{};
        for (final snap in (serialSnaps as List<QuerySnapshot>)) {
           for (final doc in snap.docs) {
             final data = doc.data() as Map<String, dynamic>;
             final serial = (data['serial'] ?? doc.id).toString().trim();
             if (serial.isNotEmpty) completedSerials.add(serial);
           }
        }
        
        final dispensedSerials = <String>{};
        for (final doc in dispSnap.docs) {
           final data = doc.data() as Map<String, dynamic>;
           final serial = (data['serial'] ?? '').toString().trim();
           if (serial.isNotEmpty) dispensedSerials.add(serial);
        }

        int pendingCount = completedSerials.length - dispensedSerials.length;
        if (pendingCount < 0) pendingCount = 0;

        return {
          'v1': pendingCount,
          'v2': dispensedCount,
          'total': pendingCount + dispensedCount,
        };
      });
    } catch (e) {
      return Stream.value({'v1': 0, 'v2': 0, 'total': 0});
    }
  }

  Future<Map<String, int>> _dispensaryCountFuture(String branchId) async {
    try {
      final days = _dateStrings(effectiveStart, effectiveEnd);
      final queues = ['zakat', 'non-zakat', 'gmwf'];

      int dispensedCount = 0;
      int pendingCount = 0;

      // ── 1. Count Dispensed Patients ──────────────────────────────────────
      final dispFutures = days.map((ds) => FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$ds/$ds')
          .count()
          .get());

      final dispResults = await Future.wait(dispFutures);
      dispensedCount = dispResults.fold(0, (sum, r) => sum + (r.count ?? 0));

      // ── 2. Count Completed Prescriptions (Pending for Dispensing) ────────
      final completedPresFutures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

      for (final ds in days) {
        final base = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(ds);

        for (final q in queues) {
          completedPresFutures.add(
            base.collection(q)
                .where('status', isEqualTo: 'completed')
                .get(),
          );
        }
      }

      final completedSnaps = await Future.wait(completedPresFutures);
      final Set<String> completedSerials = {};

      for (final snap in completedSnaps) {
        for (final doc in snap.docs) {
          final data = doc.data();
          final serial = (data['serial'] ?? doc.id).toString().trim();
          if (serial.isNotEmpty) {
            completedSerials.add(serial);
          }
        }
      }

      // ── 3. Remove already Dispensed Serials ──────────────────────────────
      if (completedSerials.isNotEmpty) {
        final dispensedSerials = <String>{};

        for (final ds in days) {
          try {
            final dispSnap = await FirebaseFirestore.instance
                .collection('branches/$branchId/dispensary/$ds/$ds')
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 4));

            for (final doc in dispSnap.docs) {
              final data = doc.data();
              final serial = (data['serial'] ?? '').toString().trim();
              if (serial.isNotEmpty) {
                dispensedSerials.add(serial);
              }
            }
          } catch (_) {
            continue;
          }
        }

        pendingCount = completedSerials.length - dispensedSerials.length;
        if (pendingCount < 0) pendingCount = 0;
      }

      return {
        'v1': pendingCount,
        'v2': dispensedCount,
        'total': pendingCount + dispensedCount,
      };
    } catch (e) {
      debugPrint('[Branches] _dispensaryCountFuture error: $e');
      return {'v1': 0, 'v2': 0, 'total': 0};
    }
  }

  Future<int> _getTotalVisits(String branchId, List<String> possibleIds) async {
    if (possibleIds.isEmpty) return 0;
    try {
      DateTime visitStart;
      DateTime visitEnd;

      if (selectedStartDate == null && selectedEndDate == null) {
        final now = DateTime.now();
        visitEnd   = DateTime(now.year, now.month, now.day + 1);
        visitStart = DateTime(now.year, now.month, now.day - 7);
      } else {
        visitStart = effectiveStart;
        visitEnd   = effectiveEnd;
      }

      final days = _dateStrings(visitStart, visitEnd);
      final Set<String> uniqueSerials = {};

      for (final dk in days) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('branches/$branchId/dispensary/$dk/$dk')
              .get()
              .timeout(const Duration(seconds: 3));
          for (final doc in snap.docs) {
            final data = doc.data();
            final pid  = _resolvePatientId(data);
            if (possibleIds.contains(pid)) {
              final serial = data['serial']?.toString() ?? '';
              if (serial.isNotEmpty) uniqueSerials.add(serial);
            }
          }
        } catch (_) { continue; }
      }
      return uniqueSerials.length;
    } catch (e) {
      debugPrint('[Branches] _getTotalVisits error: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>> _dispensaryFuture(String branchId) async {
    try {
      final days          = _dateStrings(effectiveStart, effectiveEnd);
      final displayFormat = DateFormat('dd MMM yyyy');
      final dispFutures   = days.map((ds) => FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$ds/$ds').get()
          .then((snap) => MapEntry(ds, snap)));
      final dispEntries = await Future.wait(dispFutures);
      final rawList = <Map<String, dynamic>>[];
      for (final entry in dispEntries) {
        for (final doc in entry.value.docs) {
          final data   = Map<String, dynamic>.from(doc.data());
          final serial = data['serial']?.toString() ?? '';
          if (serial.isEmpty) continue;
          data['dispenseDate'] =
              displayFormat.format(_parseDispensedAt(data['dispensedAt'], entry.key));
          data['type'] = _resolveType(data);
          rawList.add(data);
        }
      }
      if (rawList.isEmpty) {
        return {'v1': 0, 'v2': 0, 'total': 0, 'dispensed': <Map<String, dynamic>>[]};
      }

      // ── Fetch prescription metadata (doctor, tokenBy, daysOfMedicine) ────
      final serialToDoctor  = <String, String>{};
      final serialToTokenBy = <String, String>{};
      final serialToDays    = <String, int>{};
      final presRoot = FirebaseFirestore.instance
          .collection('branches').doc(branchId).collection('prescriptions');
      final fallbackFutures = <Future>[];
      for (final item in rawList) {
        final serial = item['serial']?.toString() ?? '';
        if (serial.isEmpty) continue;

        final days = (item['daysOfMedicine'] as num?)?.toInt() ?? 1;
        if (days > 1) serialToDays[serial] = days;

        final existingDoctor = _firstNonEmpty(
            [item['doctorName'], item['prescribedBy'], item['updatedBy']]);
        if (existingDoctor.isEmpty) {
          final cnicCandidates = <String>{};
          for (final f in ['patientCnic', 'cnic', 'guardianCnic']) {
            final raw = item[f]?.toString().trim() ?? '';
            if (raw.isNotEmpty) {
              cnicCandidates.add(raw);
              final stripped = raw.replaceAll('-', '').replaceAll(' ', '');
              if (stripped.isNotEmpty && stripped != '0000000000000') cnicCandidates.add(stripped);
            }
          }
          for (final cnic in cnicCandidates) {
            fallbackFutures.add(
              presRoot.doc(cnic).collection('prescriptions').doc(serial).get().then((snap) {
                if (snap.exists) {
                  final d      = snap.data()!;
                  final doctor = _firstNonEmpty([d['doctorName'], d['prescribedBy'], d['updatedBy']]);
                  if (doctor.isNotEmpty) serialToDoctor[serial] = doctor;
                  if (!serialToDays.containsKey(serial)) {
                    final pd = (d['daysOfMedicine'] as num?)?.toInt() ?? 1;
                    if (pd > 1) serialToDays[serial] = pd;
                  }
                }
              }).catchError((_) {}),
            );
          }
        }
        final existingToken = _firstNonEmpty(
            [item['createdByName'], item['tokenBy'], item['createdBy']]);
        if (existingToken.isEmpty) {
          final dateKey = item['dateKey']?.toString() ?? '';
          if (dateKey.isNotEmpty) {
            for (final q in ['zakat', 'non-zakat', 'gmwf']) {
              fallbackFutures.add(
                FirebaseFirestore.instance
                    .collection('branches').doc(branchId)
                    .collection('serials').doc(dateKey).collection(q).doc(serial).get()
                    .then((snap) {
                  if (snap.exists) {
                    final sd      = snap.data()!;
                    final tokenBy = _firstNonEmpty(
                        [sd['createdByName'], sd['tokenBy'], sd['createdBy']]);
                    if (tokenBy.isNotEmpty) serialToTokenBy[serial] = tokenBy;
                    if (!serialToDays.containsKey(serial)) {
                      final pd = (sd['daysOfMedicine'] as num?)?.toInt() ?? 1;
                      if (pd > 1) serialToDays[serial] = pd;
                    }
                  }
                }).catchError((_) {}),
              );
            }
          }
        }
      }
      await Future.wait(fallbackFutures);

      final uniquePatientIds =
          rawList.map((d) => _resolvePatientId(d)).where((id) => id.isNotEmpty).toSet();
      Map<String, Map<String, dynamic>> patientMap = {};
      if (uniquePatientIds.isNotEmpty) {
        final patientFutures = uniquePatientIds.map((pid) => FirebaseFirestore.instance
            .collection('branches/$branchId/patients').doc(pid).get()
            .then((snap) => MapEntry(pid, snap)));
        final patientEntries = await Future.wait(patientFutures);
        patientMap = {for (final e in patientEntries) if (e.value.exists) e.key: e.value.data()!};
      }

      final guardianCnics = <String>{};
      for (final p in patientMap.values) {
        final cnic = p['cnic']?.toString().trim() ?? '';
        if (cnic.isEmpty) {
          final gcnic = p['guardianCnic']?.toString().trim() ?? '';
          if (gcnic.isNotEmpty) guardianCnics.add(gcnic);
        }
      }
      final Map<String, String> guardianNames = {};
      if (guardianCnics.isNotEmpty) {
        final chunks = <List<String>>[];
        final list   = guardianCnics.toList();
        for (int i = 0; i < list.length; i += 30) {
          chunks.add(list.sublist(i, (i + 30).clamp(0, list.length)));
        }
        final guardianFutures = chunks.map((chunk) => FirebaseFirestore.instance
            .collection('branches/$branchId/patients')
            .where('cnic', whereIn: chunk).get());
        final guardianSnaps = await Future.wait(guardianFutures);
        for (final snap in guardianSnaps) {
          for (final doc in snap.docs) {
            final cnic = doc['cnic']?.toString().trim() ?? '';
            if (cnic.isNotEmpty) guardianNames[cnic] = doc['name'] ?? 'N/A';
          }
        }
      }

      final enriched = <Map<String, dynamic>>[];
      for (final data in rawList) {
        final pid    = _resolvePatientId(data);
        final p      = pid.isNotEmpty ? patientMap[pid] : null;
        final serial = data['serial']?.toString() ?? '';

        final vitals = data['vitals'] as Map<String, dynamic>? ?? {};

        final name = _firstNonEmpty([
          data['patientName'], data['name'], vitals['name'], p?['name'], 'Unknown',
        ]);
        final phone = _firstNonEmpty([data['phone'], p?['phone'], 'N/A']);
        final age   = _firstNonEmpty([
          data['patientAge'], data['age'], vitals['age']?.toString(), p?['age']?.toString(), 'N/A',
        ]);
        final gender = _firstNonEmpty([
          data['patientGender'], data['gender'], vitals['gender'], p?['gender'], 'N/A',
        ]);
        final bloodGroup = _firstNonEmpty([
          data['bloodGroup'], vitals['bloodGroup'], p?['bloodGroup'], 'N/A',
        ]);

        String  displayCnic = 'N/A';
        bool    isChild     = false;
        String? guardianName;
        final directCnic = _firstNonEmpty(
            [data['patientCnic'], data['cnic'], p?['cnic']?.toString().trim()]);
        if (directCnic.isNotEmpty && directCnic != 'N/A' && directCnic != '0000000000000') {
          displayCnic = directCnic;
          isChild     = false;
        } else {
          final gcnic = _firstNonEmpty([data['guardianCnic'], p?['guardianCnic']?.toString().trim()]);
          displayCnic = gcnic.isNotEmpty ? gcnic : 'N/A';
          isChild     = true;
          if (gcnic.isNotEmpty) guardianName = guardianNames[gcnic];
        }

        final possibleIds = <String>{};
        if (pid.isNotEmpty) possibleIds.add(pid);
        if (directCnic.isNotEmpty && directCnic != 'N/A') possibleIds.add(directCnic);
        if (isChild && displayCnic != 'N/A') possibleIds.add(displayCnic);

        final medicDays = serialToDays[serial] ?? 1;

        final type = _resolveType(data);
        int tokenAmount = 0;
        if (type == 'zakat')     tokenAmount = 20  * medicDays;
        if (type == 'non-zakat') tokenAmount = 100 * medicDays;

        enriched.add({
          ...data,
          'name':           name,
          'phone':          phone,
          'age':            age,
          'gender':         gender,
          'bloodGroup':     bloodGroup,
          'displayCnic':    displayCnic,
          'isChild':        isChild,
          if (guardianName != null) 'guardianName': guardianName,
          'patientId':      pid,
          'possibleIds':    possibleIds.toList(),
          'doctorName':     _firstNonEmpty([
            data['doctorName'], data['prescribedBy'], data['updatedBy'],
            serialToDoctor[serial], 'Unknown',
          ]),
          'dispenserName':  _firstNonEmpty([data['dispenserName'], data['dispensedBy'], 'Unknown']),
          'tokenBy':        _firstNonEmpty([
            data['createdByName'], data['tokenBy'], serialToTokenBy[serial],
            data['createdBy'], 'Unknown',
          ]),
          'frequentFlag':   p?['frequentFlag'] ?? false,
          'daysOfMedicine': medicDays,
          'tokenAmount':    tokenAmount,
        });
      }
      return {'v1': 0, 'v2': enriched.length, 'total': enriched.length, 'dispensed': enriched};
    } catch (e) {
      debugPrint('[Branches] _dispensaryFuture error: $e');
      return {'v1': 0, 'v2': 0, 'total': 0, 'dispensed': <Map<String, dynamic>>[]};
    }
  }

  // ── Consecutive patient checker ───────────────────────────────────────────
  Future<List<_ConsecutivePatient>> _consecutivePatientsFuture(String branchId) async {
    try {
      final now    = DateTime.now();
      final today  = DateTime(now.year, now.month, now.day);
      final df     = DateFormat('ddMMyy');

      final windowDays = List.generate(7, (i) => today.subtract(Duration(days: i)));
      final windowKeys = windowDays.map(df.format).toList();

      final snapFutures = windowKeys.map((dk) => FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$dk/$dk').get()
          .then((snap) => MapEntry(dk, snap))
          .catchError((_) => MapEntry(dk, null as QuerySnapshot?)));

      final entries = await Future.wait(snapFutures);

      final Map<String, Set<DateTime>> attendanceMap = {};
      for (final entry in entries) {
        final snap = entry.value;
        if (snap == null) continue;
        final dt = df.parse(entry.key);
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final pid  = _resolvePatientId(data);
          if (pid.isEmpty) continue;
          attendanceMap.putIfAbsent(pid, () => {}).add(dt);
        }
      }

      final result        = <_ConsecutivePatient>[];
      final displayFormat = DateFormat('dd MMM yyyy');

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
        if (streak < 6) continue;
        if (_revertedPatientIds.contains(pid)) continue;

        Map<String, dynamic> patientData = {};
        try {
          final patSnap = await FirebaseFirestore.instance
              .collection('branches/$branchId/patients').doc(pid).get();
          if (patSnap.exists) patientData = patSnap.data()!;
        } catch (_) {}

        if (patientData['frequentFlag'] == false) continue;

        Map<String, dynamic>? latestDispensary;
        for (final e in entries) {
          if (e.value == null) continue;
          for (final doc in e.value!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            if (_resolvePatientId(d) == pid) {
              latestDispensary = Map<String, dynamic>.from(d);
              latestDispensary!['dispenseDate'] =
                  displayFormat.format(df.parse(e.key));
              break;
            }
          }
          if (latestDispensary != null) break;
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
          streakDays: streak,
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
    try {
      await FirebaseFirestore.instance
          .collection('branches/$branchId/patients')
          .doc(patientId)
          .set({'frequentFlag': false}, SetOptions(merge: true));
      setState(() => _revertedPatientIds.add(patientId));
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

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty && s != 'N/A' && s != 'null') return s;
    }
    return '';
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

  // ── Date range selector ───────────────────────────────────────────────────

  Widget _dateRangeSelector(RoleThemeData t, {bool compact = false}) {
    final isToday = selectedStartDate == null && selectedEndDate == null;
    if (compact) {
      return GestureDetector(
        onTap: () => _showDateRangeBottomSheet(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: t.bgCardAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isToday ? t.bgRule : t.accent.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.date_range_rounded, size: 16, color: isToday ? t.textTertiary : t.accent),
            const SizedBox(width: 6),
            Text(
              isToday
                  ? 'Today'
                  : '${DateFormat('d MMM').format(selectedStartDate!)} – ${DateFormat('d MMM').format(selectedEndDate!)}',
              style: TextStyle(
                  fontSize: 12,
                  color: isToday ? t.textTertiary : t.accent,
                  fontWeight: FontWeight.w600),
            ),
            if (!isToday) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() { selectedStartDate = null; selectedEndDate = null; }),
                child: Icon(Icons.close_rounded, size: 14, color: t.danger),
              ),
            ],
          ]),
        ),
      );
    }

    return Wrap(
      spacing: 8, runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text("From:", style: TextStyle(fontWeight: FontWeight.w600, color: t.textSecondary)),
        _datePicker(t, selectedStartDate,
            (d) => setState(() => selectedStartDate = d), DateTime(2024), DateTime.now()),
        Text("To:", style: TextStyle(fontWeight: FontWeight.w600, color: t.textSecondary)),
        _datePicker(t, selectedEndDate,
            (d) => setState(() => selectedEndDate = d),
            selectedStartDate ?? DateTime(2024), DateTime.now()),
        ElevatedButton(
          onPressed: () => setState(() {}),
          style: ElevatedButton.styleFrom(
              backgroundColor: t.accent, foregroundColor: t.bgCard,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        if (!isToday)
          IconButton(
              icon: Icon(Icons.clear, color: t.danger, size: 20),
              onPressed: () => setState(() { selectedStartDate = null; selectedEndDate = null; }))
        else
          Text("(Today)",
              style: TextStyle(
                  color: t.accent.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                  fontSize: 12)),
      ],
    );
  }

  Widget _datePicker(RoleThemeData t, DateTime? value, Function(DateTime) onPick,
      DateTime first, DateTime last) {
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: first,
              lastDate: last);
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.bgCardAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.bgRule),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              value != null ? DateFormat('dd MMM yyyy').format(value) : "Select date",
              style: TextStyle(
                  color: value != null ? t.textPrimary : t.textTertiary, fontSize: 13),
            ),
            Icon(Icons.calendar_today, size: 14, color: t.textTertiary),
          ]),
        ),
      ),
    );
  }

  void _showDateRangeBottomSheet(RoleThemeData t) {
    DateTime? tempStart = selectedStartDate;
    DateTime? tempEnd   = selectedEndDate;
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: t.bgRule, borderRadius: BorderRadius.circular(2))),
            ]),
            const SizedBox(height: 16),
            Text('Select Date Range',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: t.textPrimary)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('From', style: TextStyle(fontSize: 12, color: t.textTertiary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final p = await showDatePicker(context: context,
                        initialDate: tempStart ?? DateTime.now(),
                        firstDate: DateTime(2024), lastDate: DateTime.now());
                    if (p != null) setS(() => tempStart = p);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(color: t.bgCardAlt,
                        borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                    child: Row(children: [
                      Icon(Icons.calendar_today, size: 14, color: t.textTertiary),
                      const SizedBox(width: 8),
                      Text(tempStart != null ? DateFormat('d MMM yyyy').format(tempStart!) : 'Select',
                          style: TextStyle(fontSize: 13,
                              color: tempStart != null ? t.textPrimary : t.textTertiary)),
                    ]),
                  ),
                ),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('To', style: TextStyle(fontSize: 12, color: t.textTertiary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final p = await showDatePicker(context: context,
                        initialDate: tempEnd ?? DateTime.now(),
                        firstDate: tempStart ?? DateTime(2024), lastDate: DateTime.now());
                    if (p != null) setS(() => tempEnd = p);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(color: t.bgCardAlt,
                        borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                    child: Row(children: [
                      Icon(Icons.calendar_today, size: 14, color: t.textTertiary),
                      const SizedBox(width: 8),
                      Text(tempEnd != null ? DateFormat('d MMM yyyy').format(tempEnd!) : 'Select',
                          style: TextStyle(fontSize: 13,
                              color: tempEnd != null ? t.textPrimary : t.textTertiary)),
                    ]),
                  ),
                ),
              ])),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: () {
                  setState(() { selectedStartDate = null; selectedEndDate = null; });
                  Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: t.bgRule))),
                child: Text('Reset', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                onPressed: () {
                  setState(() { selectedStartDate = tempStart; selectedEndDate = tempEnd; });
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: t.accent, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w700)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  Widget _typeFilter(RoleThemeData t) {
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
          active: filterMultiDay,
          onTap: () => setState(() => filterMultiDay = !filterMultiDay),
        ),
        const SizedBox(width: 6),
        _toggleChip(
          t,
          label: "2+ Visits",
          icon: Icons.repeat_rounded,
          color: Colors.blue,
          active: filterMultiVisit,
          onTap: () => setState(() => filterMultiVisit = !filterMultiVisit),
        ),
      ]),
    );
  }

  Widget _filterChip(RoleThemeData t, String label, String? type) {
    final selected = selectedTypeFilter == type;
    Color chipColor;
    if (type == 'zakat')          chipColor = t.zakat;
    else if (type == 'non-zakat') chipColor = t.nonZakat;
    else if (type == 'gmwf')      chipColor = t.gmwf;
    else                          chipColor = t.accent;

    return GestureDetector(
      onTap: () => setState(() => selectedTypeFilter = selected ? null : type),
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

  Widget _buildBranchDetails(String branchName, String branchId) {
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
      final isDesktop = crossAxisCount > 1;
      final double horizontalPadding = isMobile ? 28.0 : 56.0;
      final double availableWidth = width - horizontalPadding;

      final tokStream  = _tokensStream(branchId);
      final presStream = _prescriptionsStream(branchId);
      final dispStream = _dispensaryCountStream(branchId);

      if (isMobile) {
        return Scaffold(
          backgroundColor: t.bg,
          appBar: AppBar(
            backgroundColor: t.bgCard,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(branchName, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                Text('Branch Performance', style: TextStyle(color: t.textTertiary, fontSize: 11)),
              ],
            ),
            actions: [
              _dateRangeSelector(t, compact: true),
              const SizedBox(width: 8),
            ],
            bottom: TabBar(
              controller: _mobileTabController,
              labelColor: t.accent,
              unselectedLabelColor: t.textTertiary,
              indicatorColor: t.accent,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              tabs: const [
                Tab(text: "Overview"),
                Tab(text: "Patient Log"),
                Tab(text: "Flags"),
              ],
            ),
          ),
          body: TabBarView(
            controller: _mobileTabController,
            children: [
              // Tab 1: Overview
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSupervisor) ...[
                      Row(children: [
                        Expanded(child: _actionButton(t,
                            icon: Icons.inventory_rounded, label: "Inventory", color: t.nonZakat,
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => InventoryPage(
                                  branchId: branchId, isDispenser: false))))),
                        const SizedBox(width: 10),
                        Expanded(child: _actionButton(t,
                            icon: Icons.account_balance_wallet_rounded, label: "Assets", color: t.gmwf,
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => AssetsPage(branchId: branchId, isAdmin: true))))),
                      ]),
                      const SizedBox(height: 16),
                    ],
                    _buildSummaryCardsMobile(tokStream, presStream, dispStream),
                    const SizedBox(height: 24),
                    _buildActiveFiltersMobile(t),
                  ],
                ),
              ),
              // Tab 2: Patient Log
              _buildPatientLogTab(branchId, t),
              // Tab 3: Flags
              _buildFlagsTab(branchId, t),
            ],
          ),
        );
      }

      return Container(
        color: t.bg,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 14 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // ── Header ────────────────────────────────────────────────────
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(branchName, style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w900, color: t.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Branch Performance', style: TextStyle(color: t.textTertiary, fontSize: 13)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (!isSupervisor)
                    Row(children: [
                      _actionButton(t, icon: Icons.inventory_rounded,
                          label: "Inventory", color: t.nonZakat,
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => InventoryPage(
                                branchId: branchId, isDispenser: false)))),
                      const SizedBox(width: 10),
                      _actionButton(t, icon: Icons.account_balance_wallet_rounded,
                          label: "Assets", color: t.gmwf,
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => AssetsPage(branchId: branchId, isAdmin: true)))),
                    ]),
                  const SizedBox(height: 12),
                  _dateRangeSelector(t),
                ]),
              ]),

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
              FutureBuilder<List<_ConsecutivePatient>>(
                key: ValueKey('consecutive-$branchId-${_revertedPatientIds.length}'),
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
              ),

              // ── Dispensed Patients ────────────────────────────────────────
              Text("Dispensed Patients", style: TextStyle(
                  fontSize: isMobile ? 17 : 20,
                  fontWeight: FontWeight.w800, color: t.textPrimary)),
              const SizedBox(height: 10),
              _typeFilter(t),
              const SizedBox(height: 16),

              FutureBuilder<Map<String, dynamic>>(
                key: ValueKey('dispensed-$branchId-$selectedStartDate-$selectedEndDate-$selectedTypeFilter-$filterMultiDay-$filterMultiVisit'),
                future: _dispensaryFuture(branchId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: t.accent)));
                  }
                  if (snapshot.hasError || !snapshot.hasData ||
                      (snapshot.data!['dispensed'] as List).isEmpty) {
                    return Container(padding: const EdgeInsets.all(40),
                        child: Center(child: Text("No dispensed records found",
                            style: TextStyle(color: t.textTertiary))));
                  }

                  final all = snapshot.data!['dispensed'] as List<Map<String, dynamic>>;

                  // Apply type + multi-day filters synchronously
                  final filtered = all.where((p) {
                    if (selectedTypeFilter != null &&
                        p['type']?.toString().toLowerCase() != selectedTypeFilter) {
                      return false;
                    }
                    if (filterMultiDay) {
                      final days = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
                      if (days <= 1) return false;
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Text("No patients match the filter",
                          style: TextStyle(color: t.textTertiary)),
                    ));
                  }

                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: filtered.map((p) {
                      final isChild     = p['isChild'] == true;
                      final pid         = p['patientId']?.toString() ?? '';
                      final possibleIds = (p['possibleIds'] as List?)?.cast<String>() ?? <String>[];
                      final isFrequent  = !_revertedPatientIds.contains(pid) &&
                                          (p['frequentFlag'] == true);
                      final medicDays   = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
                      final tokenAmount = (p['tokenAmount'] as num?)?.toInt() ?? 0;

                      Color typeColor;
                      if (p['type'] == 'zakat')          typeColor = t.zakat;
                      else if (p['type'] == 'non-zakat') typeColor = t.nonZakat;
                      else if (p['type'] == 'gmwf')      typeColor = t.gmwf;
                      else                               typeColor = t.textTertiary;

                      return SizedBox(
                        width: (availableWidth - (14 * (crossAxisCount - 1))) / crossAxisCount,
                        child: FutureBuilder<int>(
                          future: _getTotalVisits(branchId, possibleIds),
                          builder: (context, visitSnap) {
                            final totalVisits = visitSnap.data ?? 0;

                            if (filterMultiVisit &&
                                visitSnap.connectionState == ConnectionState.done &&
                                totalVisits <= 1) {
                              return const SizedBox.shrink();
                            }

                            return Container(
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
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            );
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    });
  }

  Widget _actionButton(RoleThemeData t, {required IconData icon, required String label,
      required Color color, required VoidCallback onPressed}) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: color, size: 15),
      label: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1), elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      onPressed: onPressed,
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

    return Scaffold(
      backgroundColor: t.bg,
      body: StreamBuilder<QuerySnapshot>(
        stream: widget.branchId != null
            ? FirebaseFirestore.instance.collection('branches').where(FieldPath.documentId, isEqualTo: widget.branchId).snapshots()
            : FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: t.accent));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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

          final branches = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            final name = data?['name'] as String? ?? doc.id;
            return MapEntry(name, doc.id);
          }).toList()..sort((a, b) => a.key.compareTo(b.key));

          return DefaultTabController(
            length: branches.length,
            child: Column(children: [
              if (branches.length > 1)
                Container(
                  color: t.bgCard,
                  child: Row(children: [
                  Expanded(child: TabBar(
                    isScrollable: true,
                    labelColor: t.accent,
                    unselectedLabelColor: t.textTertiary,
                    indicatorColor: t.accent,
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    unselectedLabelStyle:
                        const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                    tabs: branches.map((e) => Tab(text: e.key)).toList(),
                  )),
                  if (widget.showRegisterButton)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: isMobile
                          ? IconButton(
                              icon: Icon(Icons.add_business_rounded, color: t.accent, size: 22),
                              onPressed: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const BranchesRegister())),
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
                                  MaterialPageRoute(builder: (_) => const BranchesRegister())),
                            ),
                    ),
                ]),
              ),
              Expanded(child: TabBarView(
                children: branches.map((e) => _buildBranchDetails(e.key, e.value)).toList(),
              )),
            ]),
          );
        },
      ),
    );
  }

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
          context, MaterialPageRoute(builder: (_) => const BranchesRegister())),
    );
  }

  Widget _buildSummaryCardsMobile(Stream<Map<String, int>> tok, Stream<Map<String, int>> pres, Stream<Map<String, int>> disp) {
    return Column(children: [
      PatientSummaryCard(
        title: "Tokens", dataStream: tok,
        variant: SummaryCardVariant.tokens,
        titleIcon: Icons.people_alt_rounded, showRevenue: true,
        valueIcons: {
          'v1': Icons.favorite_rounded, 'v2': Icons.group_rounded,
          'v3': Icons.handshake_rounded, 'total': Icons.people_alt_rounded,
        },
        valueLabels: {'v1': 'Zakat', 'v2': 'Non-Zakat', 'v3': 'GMWF'},
      ),
      const SizedBox(height: 12),
      PatientSummaryCard(
        title: "Prescriptions", dataStream: pres,
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
        title: "Dispensary", dataStream: disp,
        variant: SummaryCardVariant.dispensary,
        titleIcon: Icons.local_pharmacy_rounded,
        valueIcons: {
          'v1': Icons.access_time_rounded, 'v2': Icons.done_all_rounded,
          'total': Icons.local_pharmacy_rounded,
        },
        valueLabels: {'v1': 'Pending', 'v2': 'Dispensed'},
      ),
    ]);
  }

  Widget _buildActiveFiltersMobile(RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.filter_list_rounded, color: t.accent, size: 18),
            const SizedBox(width: 8),
            Text("Active Filters", style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _filterChipMobile("Start: ${DateFormat('dd MMM').format(effectiveStart)}", t),
            _filterChipMobile("End: ${DateFormat('dd MMM').format(effectiveEnd)}", t),
            if (selectedTypeFilter != null) _filterChipMobile("Type: $selectedTypeFilter", t),
          ]),
        ],
      ),
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
          FutureBuilder<Map<String, dynamic>>(
            key: ValueKey('dispensed-$branchId-$selectedStartDate-$selectedEndDate-$selectedTypeFilter-$filterMultiDay-$filterMultiVisit'),
            future: _dispensaryFuture(branchId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return Center(child: Padding(padding: const EdgeInsets.all(40), child: CircularProgressIndicator(color: t.accent)));
              if (!snapshot.hasData || (snapshot.data!['dispensed'] as List).isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No records found", style: TextStyle(color: t.textTertiary))));

              final all = snapshot.data!['dispensed'] as List<Map<String, dynamic>>;
              final filtered = all.where((p) {
                if (selectedTypeFilter != null && p['type']?.toString().toLowerCase() != selectedTypeFilter) return false;
                if (filterMultiDay) {
                  final days = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
                  if (days <= 1) return false;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text("No matches", style: TextStyle(color: t.textTertiary))));

              return Column(
                children: filtered.map((p) {
                  final pid = p['patientId']?.toString() ?? '';
                  final isFrequent = !_revertedPatientIds.contains(pid) && (p['frequentFlag'] == true);
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
            },
          ),
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