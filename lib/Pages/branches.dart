// lib/pages/branches.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import 'dispensary/dispensar/inventory.dart';
import 'assets.dart';
import 'branches_register.dart';

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
  final Future<Map<String, int>> dataFuture;
  final IconData titleIcon;
  final SummaryCardVariant variant;
  final bool showRevenue;
  final Map<String, IconData> valueIcons;
  final Map<String, String> valueLabels;

  const PatientSummaryCard({
    super.key,
    required this.title,
    required this.dataFuture,
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

    return FutureBuilder<Map<String, int>>(
      future: dataFuture,
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
          minis.add(_mini(valueLabels[key]!, d[key] ?? 0, valueIcons[key] ?? Icons.help_outline));
        }
        minis.add(_mini("Total", d['total'] ?? 0, valueIcons['total'] ?? Icons.people));

        return _shell(
          fill: fill, t: t,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _header(),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: minis),
            const SizedBox(height: 12),
            Opacity(
              opacity: showRevenue ? 1.0 : 0.0,
              child: Row(children: [
                const Icon(Icons.attach_money, size: 15, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  "PKR ${NumberFormat('#,##0').format(revenue)}",
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ]),
            ),
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
          BoxShadow(color: fill.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6)),
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

  Widget _mini(String label, int value, IconData icon) => Expanded(
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

  const Branches({
    super.key,
    this.branchId,
    this.showRegisterButton = true,
    this.isManager = false,
  });

  @override
  State<Branches> createState() => _BranchesState();
}

class _BranchesState extends State<Branches> with AutomaticKeepAliveClientMixin {
  String? selectedTypeFilter;
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  final Set<String> _revertedPatientIds = {};

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

  Future<Map<String, int>> _tokensFuture(String branchId) async {
    try {
      final days   = _dateStrings(effectiveStart, effectiveEnd);
      final queues = ['zakat', 'non-zakat', 'gmwf'];
      final futures = <Future<AggregateQuerySnapshot>>[];
      for (final ds in days) {
        final base = FirebaseFirestore.instance
            .collection('branches').doc(branchId).collection('serials').doc(ds);
        for (final q in queues) futures.add(base.collection(q).count().get());
      }
      final results = await Future.wait(futures);
      int zakat = 0, nonZakat = 0, gmwf = 0;
      for (int i = 0; i < results.length; i++) {
        final cnt = results[i].count ?? 0;
        if (i % 3 == 0)      zakat    += cnt;
        else if (i % 3 == 1) nonZakat += cnt;
        else                 gmwf     += cnt;
      }
      return {
        'v1': zakat, 'v2': nonZakat, 'v3': gmwf,
        'total': zakat + nonZakat + gmwf,
        'revenue': zakat * 20 + nonZakat * 100,
      };
    } catch (_) { return {}; }
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
      final entries = <Map<String, dynamic>>[];
      for (final snap in allSnaps) {
        for (final doc in snap.docs) {
          final data   = doc.data() as Map<String, dynamic>;
          final serial = data['serial']?.toString().trim() ?? doc.id;
          if (serial.isEmpty) continue;
          final statusOnDoc = data['status']?.toString().toLowerCase().trim() ?? '';
          String rawCnic = '';
          for (final key in ['patientCnic', 'cnic', 'guardianCnic', 'patientCNIC', 'guardianCNIC']) {
            final v = data[key]?.toString().trim() ?? '';
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

  Future<Map<String, int>> _dispensaryCountFuture(String branchId) async {
    try {
      final days = _dateStrings(effectiveStart, effectiveEnd);
      final countFutures = days.map((ds) => FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$ds/$ds').count().get());
      final results = await Future.wait(countFutures);
      final count   = results.fold(0, (sum, r) => sum + (r.count ?? 0));
      return {'v1': 0, 'v2': count, 'total': count};
    } catch (_) { return {}; }
  }

  Future<int> _getTotalVisits(String branchId, List<String> possibleIds) async {
    if (possibleIds.isEmpty) return 0;
    try {
      final now   = DateTime.now();
      final start = DateTime(now.year, now.month, now.day - 90);
      final end   = DateTime(now.year, now.month, now.day + 1);
      final days  = _dateStrings(start, end);
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

      final serialToDoctor  = <String, String>{};
      final serialToTokenBy = <String, String>{};
      final presRoot = FirebaseFirestore.instance
          .collection('branches').doc(branchId).collection('prescriptions');
      final fallbackFutures = <Future>[];
      for (final item in rawList) {
        final serial = item['serial']?.toString() ?? '';
        if (serial.isEmpty) continue;
        final existingDoctor = _firstNonEmpty([item['doctorName'], item['prescribedBy'], item['updatedBy']]);
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
                  final doctor = _firstNonEmpty([
                    snap.data()?['doctorName'], snap.data()?['prescribedBy'], snap.data()?['updatedBy']
                  ]);
                  if (doctor.isNotEmpty) serialToDoctor[serial] = doctor;
                }
              }).catchError((_) {}),
            );
          }
        }
        final existingToken = _firstNonEmpty([item['createdByName'], item['tokenBy'], item['createdBy']]);
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
                    final tokenBy = _firstNonEmpty([
                      snap.data()?['createdByName'], snap.data()?['tokenBy'], snap.data()?['createdBy']
                    ]);
                    if (tokenBy.isNotEmpty) serialToTokenBy[serial] = tokenBy;
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

        // ── vitals map (nested) ───────────────────────────────────────────
        // age, gender and name can live either at the top level or inside
        // the vitals sub-map. We check both and take the first non-empty value.
        final vitals = data['vitals'] as Map<String, dynamic>? ?? {};

        final name = _firstNonEmpty([
          data['patientName'],
          data['name'],
          vitals['name'],          // vitals.name fallback
          p?['name'],
          'Unknown',
        ]);

        final phone = _firstNonEmpty([
          data['phone'],
          p?['phone'],
          'N/A',
        ]);

        final age = _firstNonEmpty([
          data['patientAge'],
          data['age'],
          vitals['age']?.toString(),   // vitals.age fallback
          p?['age']?.toString(),
          'N/A',
        ]);

        final gender = _firstNonEmpty([
          data['patientGender'],
          data['gender'],
          vitals['gender'],            // vitals.gender fallback
          p?['gender'],
          'N/A',
        ]);

        final bloodGroup = _firstNonEmpty([
          data['bloodGroup'],
          vitals['bloodGroup'],        // vitals.bloodGroup fallback
          p?['bloodGroup'],
          'N/A',
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
          final gcnic  = _firstNonEmpty([data['guardianCnic'], p?['guardianCnic']?.toString().trim()]);
          displayCnic  = gcnic.isNotEmpty ? gcnic : 'N/A';
          isChild      = true;
          if (gcnic.isNotEmpty) guardianName = guardianNames[gcnic];
        }

        final possibleIds = <String>{};
        if (pid.isNotEmpty) possibleIds.add(pid);
        if (directCnic.isNotEmpty && directCnic != 'N/A') possibleIds.add(directCnic);
        if (isChild && displayCnic != 'N/A') possibleIds.add(displayCnic);

        enriched.add({
          ...data,
          'name':          name,
          'phone':         phone,
          'age':           age,
          'gender':        gender,
          'bloodGroup':    bloodGroup,
          'displayCnic':   displayCnic,
          'isChild':       isChild,
          if (guardianName != null) 'guardianName': guardianName,
          'patientId':     pid,
          'possibleIds':   possibleIds.toList(),
          'doctorName':    _firstNonEmpty([data['doctorName'], data['prescribedBy'], data['updatedBy'], serialToDoctor[serial], 'Unknown']),
          'dispenserName': _firstNonEmpty([data['dispenserName'], data['dispensedBy'], 'Unknown']),
          'tokenBy':       _firstNonEmpty([data['createdByName'], data['tokenBy'], serialToTokenBy[serial], data['createdBy'], 'Unknown']),
          'frequentFlag':  p?['frequentFlag'] ?? false,
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
          content: Text('Failed to revert: $e'),
          backgroundColor: Colors.red,
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
            border: Border.all(color: isToday ? t.bgRule : t.accent.withOpacity(0.5)),
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
                  color: t.accent.withOpacity(0.7),
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
                  decoration: BoxDecoration(
                      color: t.bgRule, borderRadius: BorderRadius.circular(2))),
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
          color: selected ? chipColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? chipColor.withOpacity(0.5) : t.bgRule),
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

  Widget _infoRow(BuildContext context, IconData icon, String text, {String? copy}) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: t.textTertiary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: t.textPrimary))),
          if (copy != null && copy.isNotEmpty && copy != 'N/A')
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: copy));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Copied: $copy'),
                  backgroundColor: t.bgCard,
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
        border: Border.all(color: streakColor.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(color: streakColor.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: streakColor.withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${cp.streakDays} consecutive days — frequent patient alert',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: streakColor),
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
                            child: const Text('Revert',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _revertFrequentFlag(
                          branchId, p['patientId']?.toString() ?? '');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: streakColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: streakColor.withOpacity(0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.undo_rounded, size: 13, color: streakColor),
                      const SizedBox(width: 4),
                      Text('Revert',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: streakColor)),
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
                    color: streakColor, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(p['name'] ?? 'Unknown',
                    style: TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700, color: t.textPrimary))),
              ]),
              Divider(height: 14, color: t.bgRule),
              _infoRow(context, Icons.badge_rounded,
                  '${isChild ? "Guardian CNIC" : "CNIC"}: ${p['displayCnic'] ?? 'N/A'}',
                  copy: p['displayCnic']),
              _infoRow(context, Icons.phone_rounded,
                  'Phone: ${p['phone'] ?? 'N/A'}', copy: p['phone']),
              _infoRow(context, Icons.calendar_today_rounded,
                  'Last visit: ${p['dispenseDate'] ?? 'N/A'}'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchDetails(String branchName, String branchId) {
    final isSupervisor = widget.branchId != null;
    final t            = RoleThemeScope.dataOf(context);
    final isMobile     = MediaQuery.of(context).size.width < 700;

    return Container(
      color: t.bg,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 14 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ───────────────────────────────────────────────────
              if (isMobile) ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(branchName, style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: t.textPrimary)),
                    Text('Branch Performance', style: TextStyle(color: t.textTertiary, fontSize: 12)),
                  ])),
                  _dateRangeSelector(t, compact: true),
                ]),
                if (!isSupervisor) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _actionButton(t,
                        icon: Icons.inventory_rounded, label: "Inventory", color: t.nonZakat,
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => InventoryPage(
                              branchId: branchId,
                              isDispenser: false,
                            ))))),
                    const SizedBox(width: 10),
                    Expanded(child: _actionButton(t,
                        icon: Icons.account_balance_wallet_rounded, label: "Assets", color: t.gmwf,
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => AssetsPage(branchId: branchId, isAdmin: true))))),
                  ]),
                ],
              ] else ...[
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
                                  branchId: branchId,
                                  isDispenser: false,
                                )))),
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
              ],

              const SizedBox(height: 22),

              // ── Summary Cards ─────────────────────────────────────────────
              LayoutBuilder(builder: (context, constraints) {
                final tokFut   = _tokensFuture(branchId);
                final presFut  = _prescriptionsFuture(branchId);
                final dispCFut = _dispensaryCountFuture(branchId);

                if (constraints.maxWidth > 800) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: PatientSummaryCard(
                          title: "Tokens", dataFuture: tokFut,
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
                          title: "Prescriptions", dataFuture: presFut,
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
                          title: "Dispensary", dataFuture: dispCFut,
                          variant: SummaryCardVariant.dispensary,
                          titleIcon: Icons.local_pharmacy_rounded,
                          valueIcons: {
                            'v1': Icons.access_time_rounded, 'v2': Icons.done_all_rounded,
                            'total': Icons.local_pharmacy_rounded,
                          },
                          valueLabels: {'v1': 'Pending', 'v2': 'Dispensed'},
                        )),
                      ],
                    ),
                  );
                }

                return Column(children: [
                  PatientSummaryCard(
                    title: "Tokens", dataFuture: tokFut,
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
                    title: "Prescriptions", dataFuture: presFut,
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
                    title: "Dispensary", dataFuture: dispCFut,
                    variant: SummaryCardVariant.dispensary,
                    titleIcon: Icons.local_pharmacy_rounded,
                    valueIcons: {
                      'v1': Icons.access_time_rounded, 'v2': Icons.done_all_rounded,
                      'total': Icons.local_pharmacy_rounded,
                    },
                    valueLabels: {'v1': 'Pending', 'v2': 'Dispensed'},
                  ),
                ]);
              }),

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
                          color: const Color(0xFFFF6B35).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.35)),
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
                      const SizedBox(height: 12),
                      ...patients.map((cp) =>
                          _frequentPatientCard(context, cp, branchId, widget.isManager)),
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
                key: ValueKey('dispensed-$branchId-$selectedStartDate-$selectedEndDate-$selectedTypeFilter'),
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

                  final all      = snapshot.data!['dispensed'] as List<Map<String, dynamic>>;
                  final filtered = all.where((p) =>
                      selectedTypeFilter == null ||
                      p['type']?.toString().toLowerCase() == selectedTypeFilter).toList();

                  if (filtered.isEmpty) {
                    return Center(child: Text("No patients match the filter",
                        style: TextStyle(color: t.textTertiary)));
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final p       = filtered[i];
                      final isChild = p['isChild'] == true;
                      final pid     = p['patientId']?.toString() ?? '';
                      final possibleIds = (p['possibleIds'] as List?)?.cast<String>() ?? <String>[];

                      final isFrequent = !_revertedPatientIds.contains(pid) &&
                                         (p['frequentFlag'] == true);

                      Color typeColor;
                      if (p['type'] == 'zakat')          typeColor = t.zakat;
                      else if (p['type'] == 'non-zakat') typeColor = t.nonZakat;
                      else if (p['type'] == 'gmwf')      typeColor = t.gmwf;
                      else                               typeColor = t.textTertiary;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: t.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isFrequent
                                ? const Color(0xFFFF6B35).withOpacity(0.5)
                                : t.bgRule,
                            width: isFrequent ? 1.5 : 1,
                          ),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(isChild ? Icons.child_care_rounded : Icons.person_rounded,
                                color: typeColor, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(p['name'] ?? 'Unknown',
                                style: TextStyle(fontSize: 15,
                                    fontWeight: FontWeight.w700, color: t.textPrimary))),
                            if (isFrequent)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Tooltip(
                                  message: 'Frequent patient',
                                  child: const Text('🔥', style: TextStyle(fontSize: 14)),
                                ),
                              ),
                            FutureBuilder<int>(
                              future: _getTotalVisits(branchId, possibleIds),
                              builder: (context, visitSnap) {
                                if (visitSnap.connectionState == ConnectionState.waiting) {
                                  return const SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                  );
                                }
                                final totalVisits = visitSnap.data ?? 0;
                                if (totalVisits > 1) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        '$totalVisits visits',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: typeColor.withOpacity(0.3))),
                              child: p['type'] == 'gmwf'
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      Image.asset("assets/logo/gmwf.png", height: 10, width: 10),
                                      const SizedBox(width: 3),
                                      Text('GMWF', style: TextStyle(color: typeColor,
                                          fontWeight: FontWeight.w700, fontSize: 10)),
                                    ])
                                  : Text((p['type'] ?? 'Unknown').toUpperCase(),
                                      style: TextStyle(color: typeColor,
                                          fontWeight: FontWeight.w700, fontSize: 10)),
                            ),
                          ]),
                          Divider(height: 14, color: t.bgRule),
                          _infoRow(context, Icons.calendar_today_rounded, 'Date: ${p['dispenseDate'] ?? 'N/A'}'),
                          _infoRow(context, Icons.badge_rounded,
                              '${isChild ? "Guardian CNIC" : "CNIC"}: ${p['displayCnic'] ?? 'N/A'}',
                              copy: p['displayCnic']),
                          if (isChild)
                            _infoRow(context, Icons.family_restroom_rounded, 'Guardian: ${p['guardianName'] ?? 'N/A'}'),
                          _infoRow(context, Icons.phone_rounded, 'Phone: ${p['phone'] ?? 'N/A'}', copy: p['phone']),
                          _infoRow(context, Icons.cake_rounded, 'Age: ${p['age'] ?? 'N/A'} · Gender: ${p['gender'] ?? 'N/A'}'),
                          _infoRow(context, Icons.bloodtype_rounded, 'Blood Group: ${p['bloodGroup'] ?? 'N/A'}'),
                          _infoRow(context, Icons.medical_services_rounded, 'Prescribed by: ${p['doctorName'] ?? 'Unknown'}'),
                          _infoRow(context, Icons.confirmation_number_rounded, 'Token by: ${p['tokenBy'] ?? 'Unknown'}'),
                          _infoRow(context, Icons.local_pharmacy_rounded, 'Dispensed by: ${p['dispenserName'] ?? 'Unknown'}'),
                          _infoRow(context, Icons.tag_rounded, 'Serial: ${p['serial'] ?? 'N/A'}'),
                        ]),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(RoleThemeData t, {required IconData icon, required String label,
      required Color color, required VoidCallback onPressed}) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: color, size: 15),
      label: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1), elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10), side: BorderSide(color: color.withOpacity(0.3))),
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
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
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
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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
                              icon: Icon(Icons.add_business_rounded, size: 16, color: t.bgCard),
                              label: Text("New Branch", style: TextStyle(
                                  color: t.bgCard, fontWeight: FontWeight.w800, fontSize: 12)),
                              style: ElevatedButton.styleFrom(backgroundColor: t.accent, elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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
      style: ElevatedButton.styleFrom(backgroundColor: t.accent, elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      onPressed: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BranchesRegister())),
    );
  }
}