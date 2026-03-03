// lib/pages/branches.dart
//
// DOCTOR NAME FIX:
//   Old fallback fetched doctorName from serial queue docs — those docs are
//   written by token_screen.dart and never contain doctorName.
//
//   New fallback fetches doctorName from prescription sub-docs:
//     branches/{branchId}/prescriptions/{cnic}/prescriptions/{serial}
//   which is where doctor_right_panel.dart actually saves it.
//
//   CNIC format fix: prescription doc IDs may be stored with OR without dashes
//   (e.g. "34201-7617693-7" vs "3420176176937"), so we try both variants.
//
//   tokenBy still comes from serial queue docs (correct — token_screen saves
//   createdByName there).
//
//   New records dispensed after the patient_form.dart fix already have all
//   fields written directly into the dispensary doc — no fallback needed.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import 'inventory_doc.dart';
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

/// Safely parse dispensedAt — patient_form saves it as ISO string,
/// but older records may have a Firestore Timestamp.
DateTime _parseDispensedAt(dynamic raw, String dateKeyFallback) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is String && raw.isNotEmpty) {
    try {
      return DateTime.parse(raw);
    } catch (_) {}
  }
  try {
    return DateFormat('ddMMyy').parse(dateKeyFallback);
  } catch (_) {
    return DateTime.now();
  }
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
      case SummaryCardVariant.tokens:
        return t.cardFillTokens;
      case SummaryCardVariant.prescriptions:
        return t.cardFillPrescriptions;
      case SummaryCardVariant.dispensary:
        return t.cardFillDispensary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t    = RoleThemeScope.dataOf(context);
    final fill = _fillColor(t);

    return FutureBuilder<Map<String, int>>(
      future: dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 180,
            child: Container(
              decoration: BoxDecoration(
                color: fill.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white54, strokeWidth: 2)),
            ),
          );
        }
        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.isEmpty) {
          return SizedBox(
              height: 180,
              child: Center(
                  child: Text("No data",
                      style: TextStyle(color: Colors.white54))));
        }

        final d       = snapshot.data!;
        final revenue = d['revenue'] ?? 0;
        final minis   = <Widget>[];
        for (final key in valueLabels.keys.where((k) => k.startsWith('v'))) {
          minis.add(_mini(valueLabels[key]!, d[key] ?? 0,
              valueIcons[key] ?? Icons.help_outline));
        }
        minis.add(
            _mini("Total", d['total'] ?? 0, valueIcons['total'] ?? Icons.people));

        return Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: fill,
          child: SizedBox(
            height: 180,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Icon(titleIcon, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ]),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: minis),
                  if (showRevenue)
                    Row(children: [
                      const Icon(Icons.attach_money,
                          size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Text("PKR ${NumberFormat('#,##0').format(revenue)}",
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mini(String label, int value, IconData icon) => Expanded(
        child: Column(children: [
          Icon(icon, size: 24, color: Colors.white),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
          Text("$value",
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Branches
// ─────────────────────────────────────────────────────────────────────────────

class Branches extends StatefulWidget {
  final String? branchId;
  final bool showRegisterButton;

  const Branches({super.key, this.branchId, this.showRegisterButton = true});

  @override
  State<Branches> createState() => _BranchesState();
}

class _BranchesState extends State<Branches>
    with AutomaticKeepAliveClientMixin {
  String? selectedTypeFilter;
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  @override
  bool get wantKeepAlive => true;

  DateTime get effectiveStart {
    if (selectedStartDate != null && selectedEndDate != null)
      return selectedStartDate!;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get effectiveEnd {
    if (selectedStartDate != null && selectedEndDate != null)
      return selectedEndDate!.add(const Duration(days: 1));
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  // ── Tokens ────────────────────────────────────────────────────────────────
  Future<Map<String, int>> _tokensFuture(String branchId) async {
    try {
      final days   = _dateStrings(effectiveStart, effectiveEnd);
      final queues = ['zakat', 'non-zakat', 'gmwf'];

      final futures = <Future<AggregateQuerySnapshot>>[];
      for (final ds in days) {
        final base = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(ds);
        for (final q in queues) {
          futures.add(base.collection(q).count().get());
        }
      }
      final results = await Future.wait(futures);

      int zakat = 0, nonZakat = 0, gmwf = 0;
      for (int i = 0; i < results.length; i++) {
        final queueIdx = i % 3;
        final cnt      = results[i].count ?? 0;
        if (queueIdx == 0)      zakat    += cnt;
        else if (queueIdx == 1) nonZakat += cnt;
        else                    gmwf     += cnt;
      }

      return {
        'v1': zakat,
        'v2': nonZakat,
        'v3': gmwf,
        'total': zakat + nonZakat + gmwf,
        'revenue': zakat * 20 + nonZakat * 100,
      };
    } catch (_) {
      return {};
    }
  }

  // ── Prescriptions ─────────────────────────────────────────────────────────
  Future<Map<String, int>> _prescriptionsFuture(String branchId) async {
    try {
      final days   = _dateStrings(effectiveStart, effectiveEnd);
      final queues = ['zakat', 'non-zakat', 'gmwf'];

      final snapFutures = <Future<QuerySnapshot>>[];
      for (final ds in days) {
        final base = FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(ds);
        for (final q in queues) {
          snapFutures.add(base.collection(q).get());
        }
      }
      final allSnaps = await Future.wait(snapFutures);

      final entries = <Map<String, dynamic>>[];
      for (final snap in allSnaps) {
        for (final doc in snap.docs) {
          final data        = doc.data() as Map<String, dynamic>;
          final serial      = data['serial']?.toString().trim() ?? doc.id;
          if (serial.isEmpty) continue;

          final statusOnDoc =
              data['status']?.toString().toLowerCase().trim() ?? '';

          String rawCnic = '';
          for (final key in [
            'patientCnic', 'cnic', 'guardianCnic',
            'patientCNIC', 'guardianCNIC',
          ]) {
            final v        = data[key]?.toString().trim() ?? '';
            final stripped = v.replaceAll('-', '').replaceAll(' ', '');
            if (stripped.isNotEmpty && stripped != '0000000000000') {
              rawCnic = v;
              break;
            }
          }

          entries.add({
            'serial':       serial,
            'cnicRaw':      rawCnic,
            'cnicStripped': rawCnic.replaceAll('-', '').replaceAll(' ', ''),
            'statusOnDoc':  statusOnDoc,
          });
        }
      }

      final total = entries.length;
      if (total == 0) return {'v1': 0, 'v2': 0, 'total': 0};

      final presRoot = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('prescriptions');

      final checkFutures = entries.map((e) async {
        if (e['statusOnDoc'] == 'completed') return true;

        final serial       = e['serial']       as String;
        final cnicRaw      = e['cnicRaw']      as String;
        final cnicStripped = e['cnicStripped'] as String;

        if (cnicRaw.isEmpty) return false;

        final candidateCnics = <String>{};
        if (cnicRaw.isNotEmpty)
          candidateCnics.add(cnicRaw);
        if (cnicStripped.isNotEmpty && cnicStripped != cnicRaw)
          candidateCnics.add(cnicStripped);

        for (final cnic in candidateCnics) {
          final snap = await presRoot
              .doc(cnic)
              .collection('prescriptions')
              .doc(serial)
              .get();
          if (snap.exists) return true;
        }
        return false;
      }).toList();

      final results    = await Future.wait(checkFutures);
      final prescribed = results.where((r) => r).length;

      return {
        'v1': total - prescribed,
        'v2': prescribed,
        'total': total,
      };
    } catch (e) {
      debugPrint('[Branches] _prescriptionsFuture error: $e');
      return {'v1': 0, 'v2': 0, 'total': 0};
    }
  }

  // ── Dispensary count (for summary card) ───────────────────────────────────
  Future<Map<String, int>> _dispensaryCountFuture(String branchId) async {
    try {
      final days         = _dateStrings(effectiveStart, effectiveEnd);
      final countFutures = days.map((ds) => FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$ds/$ds')
          .count()
          .get());
      final results = await Future.wait(countFutures);
      final count   = results.fold(0, (sum, r) => sum + (r.count ?? 0));
      return {'v1': 0, 'v2': count, 'total': count};
    } catch (_) {
      return {};
    }
  }

  // ── Dispensary full list (for patient cards) ───────────────────────────────
  Future<Map<String, dynamic>> _dispensaryFuture(String branchId) async {
    try {
      final days          = _dateStrings(effectiveStart, effectiveEnd);
      final displayFormat = DateFormat('dd MMM yyyy');

      // ── 1. Fetch all dispensary docs ──────────────────────────────────
      final dispFutures = days.map((ds) => FirebaseFirestore.instance
          .collection('branches/$branchId/dispensary/$ds/$ds')
          .get()
          .then((snap) => MapEntry(ds, snap)));
      final dispEntries = await Future.wait(dispFutures);

      final rawList = <Map<String, dynamic>>[];
      for (final entry in dispEntries) {
        final ds = entry.key;
        for (final doc in entry.value.docs) {
          final data   = Map<String, dynamic>.from(doc.data());
          final serial = data['serial']?.toString() ?? '';
          if (serial.isEmpty) continue;

          final dispensedDate = _parseDispensedAt(data['dispensedAt'], ds);
          data['dispenseDate'] = displayFormat.format(dispensedDate);
          data['type']         = _resolveType(data);

          rawList.add(data);
        }
      }

      if (rawList.isEmpty) {
        return {
          'v1': 0,
          'v2': 0,
          'total': 0,
          'dispensed': <Map<String, dynamic>>[],
        };
      }

      // ── 1b. Fallback name resolution for older dispensary records ─────
      //
      // New records (dispensed after the patient_form.dart fix) already have
      // doctorName, prescribedBy, tokenBy, and createdByName written directly
      // into the Firestore dispensary doc — no fallback needed for those.
      //
      // For OLD records missing these fields:
      //
      //   doctorName → fetch from prescription sub-doc:
      //     branches/{branchId}/prescriptions/{cnic}/prescriptions/{serial}
      //     (this is where doctor_right_panel.dart saves doctorName)
      //     NOTE: try CNIC both with dashes AND without dashes as doc ID.
      //
      //   tokenBy → fetch from serial queue docs:
      //     branches/{branchId}/serials/{dateKey}/{queue}/{serial}
      //     (this is where token_screen.dart saves createdByName)

      final serialToDoctor  = <String, String>{};
      final serialToTokenBy = <String, String>{};

      final presRoot = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('prescriptions');

      final fallbackFutures = <Future>[];

      for (final item in rawList) {
        final serial = item['serial']?.toString() ?? '';
        if (serial.isEmpty) continue;

        // ── Doctor name: fetch from prescription sub-doc ───────────────
        // Only do the fetch if the dispensary doc doesn't already have it.
        final existingDoctor = _firstNonEmpty([
          item['doctorName'],
          item['prescribedBy'],
          item['updatedBy'],
        ]);

        if (existingDoctor.isEmpty) {
          // Build CNIC candidate set — try raw (with dashes) + stripped (no dashes)
          // because doctor_right_panel may have saved the doc ID either way.
          final cnicCandidates = <String>{};
          for (final f in ['patientCnic', 'cnic', 'guardianCnic']) {
            final raw = item[f]?.toString().trim() ?? '';
            if (raw.isNotEmpty) {
              cnicCandidates.add(raw);
              final stripped = raw.replaceAll('-', '').replaceAll(' ', '');
              if (stripped.isNotEmpty && stripped != '0000000000000') {
                cnicCandidates.add(stripped);
              }
            }
          }

          for (final cnic in cnicCandidates) {
            fallbackFutures.add(
              presRoot
                  .doc(cnic)
                  .collection('prescriptions')
                  .doc(serial)
                  .get()
                  .then((snap) {
                    if (snap.exists) {
                      final doctor = _firstNonEmpty([
                        snap.data()?['doctorName'],
                        snap.data()?['prescribedBy'],
                        snap.data()?['updatedBy'],
                      ]);
                      if (doctor.isNotEmpty) serialToDoctor[serial] = doctor;
                    }
                  })
                  .catchError((_) {}),
            );
          }
        }

        // ── Token by: fetch from serial queue doc ─────────────────────
        // Only do the fetch if the dispensary doc doesn't already have it.
        final existingToken = _firstNonEmpty([
          item['createdByName'],
          item['tokenBy'],
          item['createdBy'],
        ]);

        if (existingToken.isEmpty) {
          final dateKey = item['dateKey']?.toString() ?? '';
          if (dateKey.isNotEmpty) {
            for (final q in ['zakat', 'non-zakat', 'gmwf']) {
              fallbackFutures.add(
                FirebaseFirestore.instance
                    .collection('branches')
                    .doc(branchId)
                    .collection('serials')
                    .doc(dateKey)
                    .collection(q)
                    .doc(serial)
                    .get()
                    .then((snap) {
                      if (snap.exists) {
                        final tokenBy = _firstNonEmpty([
                          snap.data()?['createdByName'],
                          snap.data()?['tokenBy'],
                          snap.data()?['createdBy'],
                        ]);
                        if (tokenBy.isNotEmpty)
                          serialToTokenBy[serial] = tokenBy;
                      }
                    })
                    .catchError((_) {}),
              );
            }
          }
        }
      }

      await Future.wait(fallbackFutures);

      // ── 2. Enrich with patient details ────────────────────────────────
      final uniquePatientIds = rawList
          .map((d) => _resolvePatientId(d))
          .where((id) => id.isNotEmpty)
          .toSet();

      Map<String, Map<String, dynamic>> patientMap = {};
      if (uniquePatientIds.isNotEmpty) {
        final patientFutures = uniquePatientIds.map((pid) => FirebaseFirestore
            .instance
            .collection('branches/$branchId/patients')
            .doc(pid)
            .get()
            .then((snap) => MapEntry(pid, snap)));
        final patientEntries = await Future.wait(patientFutures);
        patientMap = {
          for (final e in patientEntries)
            if (e.value.exists) e.key: e.value.data()!
        };
      }

      // ── 3. Guardian name lookup ───────────────────────────────────────
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
        final guardianFutures = chunks.map((chunk) => FirebaseFirestore
            .instance
            .collection('branches/$branchId/patients')
            .where('cnic', whereIn: chunk)
            .get());
        final guardianSnaps = await Future.wait(guardianFutures);
        for (final snap in guardianSnaps) {
          for (final doc in snap.docs) {
            final cnic = doc['cnic']?.toString().trim() ?? '';
            if (cnic.isNotEmpty) guardianNames[cnic] = doc['name'] ?? 'N/A';
          }
        }
      }

      // ── 4. Build enriched list ────────────────────────────────────────
      final enriched = <Map<String, dynamic>>[];
      for (final data in rawList) {
        final pid    = _resolvePatientId(data);
        final p      = pid.isNotEmpty ? patientMap[pid] : null;
        final serial = data['serial']?.toString() ?? '';

        final name = _firstNonEmpty([
          data['patientName'],
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
          p?['age']?.toString(),
          'N/A',
        ]);

        final gender = _firstNonEmpty([
          data['patientGender'],
          data['gender'],
          p?['gender'],
          'N/A',
        ]);

        final bloodGroup = _firstNonEmpty([
          data['bloodGroup'],
          p?['bloodGroup'],
          'N/A',
        ]);

        // ── CNIC resolution ───────────────────────────────────────────
        String  displayCnic = 'N/A';
        bool    isChild     = false;
        String? guardianName;

        final directCnic = _firstNonEmpty([
          data['patientCnic'],
          data['cnic'],
          p?['cnic']?.toString().trim(),
        ]);

        if (directCnic.isNotEmpty &&
            directCnic != 'N/A' &&
            directCnic != '0000000000000') {
          displayCnic = directCnic;
          isChild     = false;
        } else {
          final gcnic = _firstNonEmpty([
            data['guardianCnic'],
            p?['guardianCnic']?.toString().trim(),
          ]);
          displayCnic  = gcnic.isNotEmpty ? gcnic : 'N/A';
          isChild      = true;
          if (gcnic.isNotEmpty) guardianName = guardianNames[gcnic];
        }

        enriched.add({
          ...data,
          'name':        name,
          'phone':       phone,
          'age':         age,
          'gender':      gender,
          'bloodGroup':  bloodGroup,
          'displayCnic': displayCnic,
          'isChild':     isChild,
          if (guardianName != null) 'guardianName': guardianName,

          // ── Doctor name ──────────────────────────────────────────────
          // 1. Fields in dispensary doc (written by new patient_form)
          // 2. Fetched from prescription sub-doc (fallback for old records)
          // 3. 'Unknown' sentinel
          'doctorName': _firstNonEmpty([
            data['doctorName'],
            data['prescribedBy'],
            data['updatedBy'],
            serialToDoctor[serial],
            'Unknown',
          ]),

          // ── Dispenser name ───────────────────────────────────────────
          'dispenserName': _firstNonEmpty([
            data['dispenserName'],
            data['dispensedBy'],
            'Unknown',
          ]),

          // ── Token by ─────────────────────────────────────────────────
          // 1. Fields in dispensary doc (written by new patient_form)
          // 2. Fetched from serial queue doc (fallback for old records)
          // 3. Raw createdBy ID as last resort
          // 4. 'Unknown' sentinel
          'tokenBy': _firstNonEmpty([
            data['createdByName'],
            data['tokenBy'],
            serialToTokenBy[serial],
            data['createdBy'],
            'Unknown',
          ]),
        });
      }

      return {
        'v1': 0,
        'v2': enriched.length,
        'total': enriched.length,
        'dispensed': enriched,
      };
    } catch (e) {
      debugPrint('[Branches] _dispensaryFuture error: $e');
      return {
        'v1': 0,
        'v2': 0,
        'total': 0,
        'dispensed': <Map<String, dynamic>>[],
      };
    }
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
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
    final raw =
        (data['queueType'] ?? data['type'] ?? '').toString().toLowerCase().trim();
    switch (raw) {
      case 'zakat':     return 'zakat';
      case 'non-zakat': return 'non-zakat';
      case 'gmwf':      return 'gmwf';
      default:          return 'Unknown';
    }
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Widget _dateRangeSelector(RoleThemeData t) {
    final isToday = selectedStartDate == null && selectedEndDate == null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text("From:",
            style: TextStyle(
                fontWeight: FontWeight.w600, color: t.textSecondary)),
        SizedBox(
          width: 140,
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedStartDate ?? DateTime.now(),
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now());
              if (picked != null) setState(() => selectedStartDate = picked);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.bgCardAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.bgRule),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedStartDate != null
                          ? DateFormat('dd MMM yyyy').format(selectedStartDate!)
                          : "Select date",
                      style: TextStyle(
                          color: selectedStartDate != null
                              ? t.textPrimary
                              : t.textTertiary,
                          fontSize: 13),
                    ),
                    Icon(Icons.calendar_today,
                        size: 14, color: t.textTertiary),
                  ]),
            ),
          ),
        ),
        Text("To:",
            style: TextStyle(
                fontWeight: FontWeight.w600, color: t.textSecondary)),
        SizedBox(
          width: 140,
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedEndDate ?? DateTime.now(),
                  firstDate: selectedStartDate ?? DateTime(2024),
                  lastDate: DateTime.now());
              if (picked != null) setState(() => selectedEndDate = picked);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.bgCardAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.bgRule),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedEndDate != null
                          ? DateFormat('dd MMM yyyy').format(selectedEndDate!)
                          : "Select date",
                      style: TextStyle(
                          color: selectedEndDate != null
                              ? t.textPrimary
                              : t.textTertiary,
                          fontSize: 13),
                    ),
                    Icon(Icons.calendar_today,
                        size: 14, color: t.textTertiary),
                  ]),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => setState(() {}),
          style: ElevatedButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: t.bg,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text("Apply",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        if (!isToday)
          IconButton(
            icon: Icon(Icons.clear, color: t.danger, size: 20),
            onPressed: () => setState(() {
              selectedStartDate = null;
              selectedEndDate   = null;
            }),
          )
        else
          Text("(Today)",
              style: TextStyle(
                  color: t.accent.withOpacity(0.7),
                  fontStyle: FontStyle.italic,
                  fontSize: 12)),
      ],
    );
  }

  Widget _typeFilter(RoleThemeData t) {
    return Wrap(
      spacing: 8,
      children: [
        _filterChip(t, "All",       null),
        _filterChip(t, "Zakat",     "zakat"),
        _filterChip(t, "Non-Zakat", "non-zakat"),
        _filterChip(t, "GMWF",      "gmwf"),
      ],
    );
  }

  Widget _filterChip(RoleThemeData t, String label, String? type) {
    final selected = selectedTypeFilter == type;
    Color chipColor;
    if (type == 'zakat')          chipColor = t.zakat;
    else if (type == 'non-zakat') chipColor = t.nonZakat;
    else if (type == 'gmwf')      chipColor = t.gmwf;
    else                          chipColor = t.accent;

    return FilterChip(
      label: type == 'gmwf'
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Image.asset("assets/logo/gmwf.png", height: 14, width: 14),
              const SizedBox(width: 4),
              Text(label),
            ])
          : Text(label),
      selected: selected,
      onSelected: (sel) =>
          setState(() => selectedTypeFilter = sel ? type : null),
      selectedColor: chipColor.withOpacity(0.2),
      backgroundColor: t.bgCard,
      labelStyle: TextStyle(
        color: selected ? chipColor : t.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
      checkmarkColor: chipColor,
      side: BorderSide(
          color: selected ? chipColor.withOpacity(0.5) : t.bgRule),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text,
      {String? copy}) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.textTertiary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 14, color: t.textPrimary))),
          if (copy != null && copy.isNotEmpty && copy != 'N/A')
            IconButton(
              icon: Icon(Icons.content_copy, size: 16, color: t.textTertiary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copy));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Copied: $copy'),
                  backgroundColor: t.bgCard,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBranchDetails(String branchName, String branchId) {
    final isSupervisor = widget.branchId != null;
    final isWide       = MediaQuery.of(context).size.width > 900;
    final t            = RoleThemeScope.dataOf(context);

    return Container(
      color: t.bg,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isWide ? 32 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(branchName,
                          style: TextStyle(
                            fontSize: isWide ? 28 : 22,
                            fontWeight: FontWeight.w900,
                            color: t.textPrimary,
                          )),
                      const SizedBox(height: 4),
                      Text('Branch Performance',
                          style: TextStyle(
                              color: t.textTertiary, fontSize: 13)),
                    ]),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isSupervisor)
                        Row(
                          children: [
                            _actionButton(t,
                                icon: Icons.inventory_rounded,
                                label: "Inventory",
                                color: t.nonZakat,
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => InventoryDocPage(
                                            branchId: branchId)))),
                            const SizedBox(width: 10),
                            _actionButton(t,
                                icon: Icons.account_balance_wallet_rounded,
                                label: "Assets",
                                color: t.gmwf,
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => AssetsPage(
                                            branchId: branchId,
                                            isAdmin: true)))),
                          ],
                        ),
                      const SizedBox(height: 12),
                      _dateRangeSelector(t),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 28),

              LayoutBuilder(builder: (context, constraints) {
                final tokFut   = _tokensFuture(branchId);
                final presFut  = _prescriptionsFuture(branchId);
                final dispCFut = _dispensaryCountFuture(branchId);

                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: PatientSummaryCard(
                              title: "Tokens",
                              dataFuture: tokFut,
                              variant: SummaryCardVariant.tokens,
                              titleIcon: Icons.people_alt_rounded,
                              showRevenue: true,
                              valueIcons: {
                                'v1': Icons.favorite_rounded,
                                'v2': Icons.group_rounded,
                                'v3': Icons.handshake_rounded,
                                'total': Icons.people_alt_rounded,
                              },
                              valueLabels: {
                                'v1': 'Zakat',
                                'v2': 'Non-Zakat',
                                'v3': 'GMWF',
                              })),
                      const SizedBox(width: 16),
                      Expanded(
                          child: PatientSummaryCard(
                              title: "Prescriptions",
                              dataFuture: presFut,
                              variant: SummaryCardVariant.prescriptions,
                              titleIcon: Icons.medical_information_rounded,
                              valueIcons: {
                                'v1': Icons.timer_rounded,
                                'v2': Icons.check_circle_rounded,
                                'total': Icons.medical_information_rounded,
                              },
                              valueLabels: {
                                'v1': 'Waiting',
                                'v2': 'Prescribed',
                              })),
                      const SizedBox(width: 16),
                      Expanded(
                          child: PatientSummaryCard(
                              title: "Dispensary",
                              dataFuture: dispCFut,
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
                              })),
                    ],
                  );
                }

                return Column(children: [
                  PatientSummaryCard(
                      title: "Tokens",
                      dataFuture: tokFut,
                      variant: SummaryCardVariant.tokens,
                      titleIcon: Icons.people_alt_rounded,
                      showRevenue: true,
                      valueIcons: {
                        'v1': Icons.favorite_rounded,
                        'v2': Icons.group_rounded,
                        'v3': Icons.handshake_rounded,
                        'total': Icons.people_alt_rounded,
                      },
                      valueLabels: {
                        'v1': 'Zakat',
                        'v2': 'Non-Zakat',
                        'v3': 'GMWF',
                      }),
                  const SizedBox(height: 16),
                  PatientSummaryCard(
                      title: "Prescriptions",
                      dataFuture: presFut,
                      variant: SummaryCardVariant.prescriptions,
                      titleIcon: Icons.medical_information_rounded,
                      valueIcons: {
                        'v1': Icons.timer_rounded,
                        'v2': Icons.check_circle_rounded,
                        'total': Icons.medical_information_rounded,
                      },
                      valueLabels: {'v1': 'Waiting', 'v2': 'Prescribed'}),
                  const SizedBox(height: 16),
                  PatientSummaryCard(
                      title: "Dispensary",
                      dataFuture: dispCFut,
                      variant: SummaryCardVariant.dispensary,
                      titleIcon: Icons.local_pharmacy_rounded,
                      valueIcons: {
                        'v1': Icons.access_time_rounded,
                        'v2': Icons.done_all_rounded,
                        'total': Icons.local_pharmacy_rounded,
                      },
                      valueLabels: {'v1': 'Pending', 'v2': 'Dispensed'}),
                ]);
              }),

              const SizedBox(height: 36),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text("Dispensed Patients",
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: t.textPrimary)),
                  _typeFilter(t),
                ],
              ),

              const SizedBox(height: 20),

              FutureBuilder<Map<String, dynamic>>(
                key: ValueKey(
                    'dispensed-$branchId-$selectedStartDate-$selectedEndDate-$selectedTypeFilter'),
                future: _dispensaryFuture(branchId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(color: t.accent));
                  }
                  if (snapshot.hasError ||
                      !snapshot.hasData ||
                      (snapshot.data!['dispensed'] as List).isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                          child: Text("No dispensed records found",
                              style: TextStyle(color: t.textTertiary))),
                    );
                  }

                  final all = snapshot.data!['dispensed']
                      as List<Map<String, dynamic>>;
                  final filtered = all
                      .where((p) =>
                          selectedTypeFilter == null ||
                          p['type']?.toString().toLowerCase() ==
                              selectedTypeFilter)
                      .toList();

                  if (filtered.isEmpty) {
                    return Center(
                        child: Text("No patients match the filter",
                            style: TextStyle(color: t.textTertiary)));
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final p       = filtered[i];
                      final isChild = p['isChild'] == true;

                      Color typeColor;
                      if (p['type'] == 'zakat')          typeColor = t.zakat;
                      else if (p['type'] == 'non-zakat') typeColor = t.nonZakat;
                      else if (p['type'] == 'gmwf')      typeColor = t.gmwf;
                      else                               typeColor = t.textTertiary;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: t.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.bgRule),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(
                                  isChild
                                      ? Icons.child_care_rounded
                                      : Icons.person_rounded,
                                  color: typeColor,
                                  size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(p['name'] ?? 'Unknown',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: t.textPrimary))),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: typeColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: typeColor.withOpacity(0.3))),
                                child: p['type'] == 'gmwf'
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Image.asset(
                                              "assets/logo/gmwf.png",
                                              height: 12,
                                              width: 12),
                                          const SizedBox(width: 4),
                                          Text('GMWF',
                                              style: TextStyle(
                                                  color: typeColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11)),
                                        ])
                                    : Text(
                                        (p['type'] ?? 'Unknown').toUpperCase(),
                                        style: TextStyle(
                                            color: typeColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11)),
                              ),
                            ]),
                            Divider(height: 16, color: t.bgRule),
                            _infoRow(context, Icons.calendar_today_rounded,
                                'Date: ${p['dispenseDate'] ?? 'N/A'}'),
                            _infoRow(
                                context,
                                Icons.badge_rounded,
                                '${isChild ? "Guardian CNIC" : "CNIC"}: ${p['displayCnic'] ?? 'N/A'}',
                                copy: p['displayCnic']),
                            if (isChild)
                              _infoRow(
                                  context,
                                  Icons.family_restroom_rounded,
                                  'Guardian: ${p['guardianName'] ?? 'N/A'}'),
                            _infoRow(context, Icons.phone_rounded,
                                'Phone: ${p['phone'] ?? 'N/A'}',
                                copy: p['phone']),
                            _infoRow(context, Icons.cake_rounded,
                                'Age: ${p['age'] ?? 'N/A'} · Gender: ${p['gender'] ?? 'N/A'}'),
                            _infoRow(context, Icons.bloodtype_rounded,
                                'Blood Group: ${p['bloodGroup'] ?? 'N/A'}'),
                            _infoRow(context, Icons.medical_services_rounded,
                                'Prescribed by: ${p['doctorName'] ?? 'Unknown'}'),
                            _infoRow(
                                context,
                                Icons.confirmation_number_rounded,
                                'Token by: ${p['tokenBy'] ?? 'Unknown'}'),
                            _infoRow(context, Icons.local_pharmacy_rounded,
                                'Dispensed by: ${p['dispenserName'] ?? 'Unknown'}'),
                            _infoRow(context, Icons.tag_rounded,
                                'Serial: ${p['serial'] ?? 'N/A'}'),
                          ],
                        ),
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

  Widget _actionButton(RoleThemeData t,
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onPressed}) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: color, size: 16),
      label: Text(label,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        elevation: 0,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withOpacity(0.3))),
      ),
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t              = RoleThemeScope.dataOf(context);
    final isSupervisorMode = widget.branchId != null;

    if (isSupervisorMode) {
      final branchName = widget.branchId![0].toUpperCase() +
          widget.branchId!.substring(1).replaceAll('-', ' ');
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          title: Text("Branch: $branchName",
              style: TextStyle(
                  color: t.textPrimary, fontWeight: FontWeight.w800)),
          backgroundColor: t.bgCard,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: t.textPrimary),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: t.bgRule),
          ),
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
                Text("No branches found",
                    style: TextStyle(color: t.textTertiary, fontSize: 16)),
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
          }).toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          return DefaultTabController(
            length: branches.length,
            child: Column(
              children: [
                Container(
                  color: t.bgCard,
                  child: Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          isScrollable: true,
                          labelColor: t.accent,
                          unselectedLabelColor: t.textTertiary,
                          indicatorColor: t.accent,
                          indicatorWeight: 2,
                          labelStyle: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                          unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 13),
                          tabs:
                              branches.map((e) => Tab(text: e.key)).toList(),
                        ),
                      ),
                      if (widget.showRegisterButton) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.add_business_rounded,
                                size: 16, color: t.bg),
                            label: Text("New Branch",
                                style: TextStyle(
                                    color: t.bg,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.accent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const BranchesRegister())),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: branches
                        .map((e) => _buildBranchDetails(e.key, e.value))
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _registerBranchButton(BuildContext context, RoleThemeData t) {
    return ElevatedButton.icon(
      icon: Icon(Icons.add_business_rounded, color: t.bg),
      label: Text("Register New Branch",
          style: TextStyle(color: t.bg, fontWeight: FontWeight.w800)),
      style: ElevatedButton.styleFrom(
        backgroundColor: t.accent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const BranchesRegister())),
    );
  }
}