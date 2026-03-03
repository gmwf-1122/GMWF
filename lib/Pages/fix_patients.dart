// lib/pages/fix_patients.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/local_storage_service.dart' as lss;
import '../services/sync_service.dart';

class FixPatientsScreen extends StatefulWidget {
  final String branchId;

  const FixPatientsScreen({super.key, required this.branchId});

  @override
  State<FixPatientsScreen> createState() => _FixPatientsScreenState();
}

class _FixPatientsScreenState extends State<FixPatientsScreen> {
  bool isRunning = false;
  bool isMigrating = false;
  bool isClearingLocal = false;
  bool isMerging = false;

  // Patient fix stats
  int totalPatients = 0;
  int processed = 0;
  int globalAdults = 0;
  int globalChildren = 0;
  int globalNeedsReview = 0;
  int globalMissingIsAdult = 0;

  Map<String, Map<String, int>> branchStats = {};
  Map<String, String> branchNames = {};
  List<QueryDocumentSnapshot> allPatients = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Merge stats
  int mergeScanned = 0;
  int mergePrescToSerial = 0;   // Pass 1: prescriptions → serials
  int mergeDispToSerial = 0;    // Pass 2: dispensary (old flat) → serials
  int mergeSerialToSerial = 0;  // Pass 3: flat top-level → nested map
  int mergeSkipped = 0;
  int mergeFailed = 0;
  String mergeStatus = '';

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String? _extractDateKey(String serial) {
    final parts = serial.split('-');
    if (parts.length >= 2 && parts[0].length == 6) return parts[0];
    return null;
  }

  Future<DocumentReference?> _findSerialRef(
      String dateKey, String serial) async {
    for (final qt in ['zakat', 'non-zakat', 'gmwf']) {
      try {
        final ref = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('serials')
            .doc(dateKey)
            .collection(qt)
            .doc(serial);
        final snap = await ref.get();
        if (snap.exists) return ref;
      } catch (_) {}
    }
    return null;
  }

  /// Builds a clean, normalised prescription map from whatever source doc we have.
  Map<String, dynamic> _buildPrescriptionMap(
      Map<String, dynamic> source, String serial) {
    return {
      'serial': serial,
      'id': serial,
      if (source['branchId'] != null) 'branchId': source['branchId'],
      if (source['cnic'] != null) 'cnic': source['cnic'],
      if (source['patientCnic'] != null) 'patientCnic': source['patientCnic'],
      if (source['patientName'] != null) 'patientName': source['patientName'],
      if (source['patientAge'] != null) 'patientAge': source['patientAge'],
      if (source['patientGender'] != null) 'patientGender': source['patientGender'],
      if (source['complaint'] != null) 'complaint': source['complaint'],
      if (source['condition'] != null) 'condition': source['condition'],
      if (source['diagnosis'] != null) 'diagnosis': source['diagnosis'],
      if (source['prescriptions'] != null) 'prescriptions': source['prescriptions'],
      if (source['labResults'] != null) 'labResults': source['labResults'],
      if (source['vitals'] != null) 'vitals': source['vitals'],
      if (source['doctorId'] != null) 'doctorId': source['doctorId'],
      if (source['doctorName'] != null) 'doctorName': source['doctorName'],
      if (source['createdAt'] != null) 'createdAt': source['createdAt'],
      if (source['completedAt'] != null) 'completedAt': source['completedAt'],
      if (source['updatedAt'] != null) 'updatedAt': source['updatedAt'],
      if (source['status'] != null) 'status': source['status'],
      if (source['queueType'] != null) 'queueType': source['queueType'],
      if (source['dateKey'] != null) 'dateKey': source['dateKey'],
    };
  }

  bool _serialIsDispensed(Map<String, dynamic> d) =>
      (d['status'] as String?) == 'dispensed' ||
      (d['dispenseStatus'] as String?) == 'dispensed';

  bool _hasCompletePrescriptionMap(Map<String, dynamic> d) {
    final existing = d['prescription'];
    if (existing is! Map) return false;
    final presc = existing['prescriptions'];
    return presc is List && (presc as List).isNotEmpty;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN MERGE — 3 passes
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runMerge({required bool dryRun}) async {
    if (isMerging) return;
    setState(() {
      isMerging = true;
      mergeScanned = mergePrescToSerial = mergeDispToSerial =
          mergeSerialToSerial = mergeSkipped = mergeFailed = 0;
      mergeStatus = 'Starting…';
    });

    final branchRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId);

    try {
      // ── PASS 1 ───────────────────────────────────────────────────────────
      // prescriptions/{cnic}/prescriptions/{serial}  →  serials/{date}/{qt}/{serial}
      setState(() => mergeStatus = 'Pass 1: scanning prescriptions collection…');

      final cnicDocs = await branchRef.collection('prescriptions').get();

      for (final cnicDoc in cnicDocs.docs) {
        final prescDocs =
            await cnicDoc.reference.collection('prescriptions').get();

        for (final prescDoc in prescDocs.docs) {
          mergeScanned++;
          _tick();

          final data = Map<String, dynamic>.from(prescDoc.data());
          final serial =
              (data['serial'] as String?)?.trim() ?? prescDoc.id.trim();
          final dateKey = _extractDateKey(serial);
          if (dateKey == null) { mergeSkipped++; continue; }

          final serialRef = await _findSerialRef(dateKey, serial);
          if (serialRef == null) { mergeSkipped++; continue; }

          final serialSnap = await serialRef.get();
          final serialData =
              Map<String, dynamic>.from(serialSnap.data() as Map? ?? {});

          if (_hasCompletePrescriptionMap(serialData)) {
            mergeSkipped++;
            continue;
          }

          final prescMap = _buildPrescriptionMap(data, serial);
          final update = <String, dynamic>{
            'prescription': prescMap,
            'prescriptionId': serial,
            if (data['diagnosis'] != null) 'diagnosis': data['diagnosis'],
            if (data['complaint'] != null) 'complaint': data['complaint'],
            if (data['condition'] != null) 'condition': data['condition'],
            if (data['prescriptions'] != null) 'prescriptions': data['prescriptions'],
            if (data['labResults'] != null) 'labResults': data['labResults'],
            if (data['doctorId'] != null) 'doctorId': data['doctorId'],
            if (data['doctorName'] != null) 'doctorName': data['doctorName'],
            if (data['patientName'] != null) 'patientName': data['patientName'],
            if (data['patientAge'] != null) 'patientAge': data['patientAge'],
            if (data['patientGender'] != null) 'patientGender': data['patientGender'],
            // only bring vitals across if serial has none
            if (data['vitals'] != null && serialData['vitals'] == null)
              'vitals': data['vitals'],
            // never downgrade a dispensed serial
            if (data['status'] != null && !_serialIsDispensed(serialData))
              'status': data['status'],
            '_mergedFromPrescriptions': true,
            '_mergedAt': FieldValue.serverTimestamp(),
          };

          mergePrescToSerial++;
          if (!dryRun) {
            try {
              await serialRef.update(update);
            } catch (e) {
              debugPrint('[Merge P1] $serial: $e');
              mergeFailed++;
              mergePrescToSerial--;
            }
          }
        }
      }

      // ── PASS 2 ───────────────────────────────────────────────────────────
      // dispensary/{dateKey}/{dateKey}/{serial}  →  serials
      // Old schema: prescriptions stored flat at top level of dispensary doc.
      setState(
          () => mergeStatus = 'Pass 2: scanning dispensary collection…');

      final dispensaryDates =
          await branchRef.collection('dispensary').get();

      for (final dateDoc in dispensaryDates.docs) {
        final dateKey = dateDoc.id; // e.g. "010126"
        QuerySnapshot? records;
        try {
          // Sub-collection name mirrors the date key
          records = await dateDoc.reference.collection(dateKey).get();
        } catch (_) {
          continue;
        }

        for (final dispDoc in records.docs) {
          mergeScanned++;
          _tick();

          final data = Map<String, dynamic>.from(
  dispDoc.data() as Map<String, dynamic>? ?? {},
);
          final serial =
              (data['serial'] as String?)?.trim() ?? dispDoc.id.trim();

          final serialRef = await _findSerialRef(dateKey, serial);
          if (serialRef == null) { mergeSkipped++; continue; }

          final serialSnap = await serialRef.get();
          final serialData =
              Map<String, dynamic>.from(serialSnap.data() as Map? ?? {});

          if (_hasCompletePrescriptionMap(serialData)) {
            mergeSkipped++;
            continue;
          }

          // Old dispensary docs: prescriptions[] lives at the TOP level.
          // Check that it's actually there before bothering.
          final hasPrescriptions = data['prescriptions'] is List &&
              (data['prescriptions'] as List).isNotEmpty;
          if (!hasPrescriptions) { mergeSkipped++; continue; }

          final prescMap = _buildPrescriptionMap(data, serial);
          final update = <String, dynamic>{
            'prescription': prescMap,
            'prescriptionId': serial,
            if (data['diagnosis'] != null && serialData['diagnosis'] == null)
              'diagnosis': data['diagnosis'],
            if (data['complaint'] != null && serialData['complaint'] == null)
              'complaint': data['complaint'],
            if (data['prescriptions'] != null && serialData['prescriptions'] == null)
              'prescriptions': data['prescriptions'],
            if (data['labResults'] != null && serialData['labResults'] == null)
              'labResults': data['labResults'],
            if (data['doctorId'] != null && serialData['doctorId'] == null)
              'doctorId': data['doctorId'],
            if (data['doctorName'] != null && serialData['doctorName'] == null)
              'doctorName': data['doctorName'],
            if (data['patientName'] != null && serialData['patientName'] == null)
              'patientName': data['patientName'],
            if (data['vitals'] != null && serialData['vitals'] == null)
              'vitals': data['vitals'],
            '_mergedFromDispensary': true,
            '_mergedAt': FieldValue.serverTimestamp(),
          };

          mergeDispToSerial++;
          if (!dryRun) {
            try {
              await serialRef.update(update);
            } catch (e) {
              debugPrint('[Merge P2] $serial: $e');
              mergeFailed++;
              mergeDispToSerial--;
            }
          }
        }
      }

      // ── PASS 3 ───────────────────────────────────────────────────────────
      // Serials that already have a flat top-level prescriptions[] (written
      // by an old doctor screen) but no nested prescription map.
      setState(() =>
          mergeStatus = 'Pass 3: wrapping flat serials into nested map…');

      final serialDates = await branchRef.collection('serials').get();

      for (final dateDoc in serialDates.docs) {
        for (final qt in ['zakat', 'non-zakat', 'gmwf']) {
          QuerySnapshot? qtDocs;
          try {
            qtDocs = await dateDoc.reference.collection(qt).get();
          } catch (_) {
            continue;
          }

          for (final serialDoc in qtDocs.docs) {
            mergeScanned++;
            _tick();

            final data =
                Map<String, dynamic>.from(serialDoc.data() as Map? ?? {});
            final serial =
                (data['serial'] as String?)?.trim() ?? serialDoc.id.trim();

            final hasFlatPrescriptions = data['prescriptions'] is List &&
                (data['prescriptions'] as List).isNotEmpty;
            if (!hasFlatPrescriptions || _hasCompletePrescriptionMap(data)) {
              mergeSkipped++;
              continue;
            }

            final prescMap = _buildPrescriptionMap(data, serial);
            final update = <String, dynamic>{
              'prescription': prescMap,
              'prescriptionId': serial,
              '_mergedFlatToNested': true,
              '_mergedAt': FieldValue.serverTimestamp(),
            };

            mergeSerialToSerial++;
            if (!dryRun) {
              try {
                await serialDoc.reference.update(update);
              } catch (e) {
                debugPrint('[Merge P3] $serial: $e');
                mergeFailed++;
                mergeSerialToSerial--;
              }
            }
          }
        }
      }

      // ── Done ─────────────────────────────────────────────────────────────
      setState(() {
        mergeStatus = dryRun
            ? '✅ Dry run complete — no data was written.'
            : '✅ All done!';
        isMerging = false;
      });

      if (mounted) {
        final total =
            mergePrescToSerial + mergeDispToSerial + mergeSerialToSerial;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${dryRun ? 'Would fix' : 'Fixed'} $total docs '
            '(Pass1: $mergePrescToSerial, Pass2: $mergeDispToSerial, '
            'Pass3: $mergeSerialToSerial). '
            'Skipped (already ok): $mergeSkipped. Errors: $mergeFailed.',
          ),
          backgroundColor: dryRun ? Colors.blue : Colors.green,
          duration: const Duration(seconds: 10),
        ));
      }
    } catch (e, stack) {
      debugPrint('[Merge] $e\n$stack');
      if (mounted) {
        setState(() {
          mergeStatus = '❌ Error: $e';
          isMerging = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Repair failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ));
      }
    }
  }

  void _tick() {
    setState(() {
      mergeStatus =
          'Scanned $mergeScanned  |  '
          'P1: $mergePrescToSerial  P2: $mergeDispToSerial  '
          'P3: $mergeSerialToSerial  |  '
          'skipped: $mergeSkipped  errors: $mergeFailed';
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Existing patient-fix logic
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _processData({required bool doUpdate}) async {
    setState(() {
      isRunning = true;
      totalPatients = processed = globalAdults = globalChildren =
          globalNeedsReview = 0;
      globalMissingIsAdult = 0;
      branchStats.clear();
      branchNames.clear();
      allPatients.clear();
    });

    final branchesSnap =
        await FirebaseFirestore.instance.collection('branches').get();
    for (var doc in branchesSnap.docs) {
      branchNames[doc.id] = (doc.data()['name'] as String?) ?? doc.id;
    }
    branchNames['unknown'] = 'Unknown / Missing BranchId';

    final patientsSnap =
        await FirebaseFirestore.instance.collection('patients').get();
    totalPatients = patientsSnap.docs.length;
    allPatients = patientsSnap.docs;

    if (totalPatients == 0) {
      setState(() => isRunning = false);
      return;
    }

    WriteBatch? batch;
    int batchCount = 0;

    for (var doc in patientsSnap.docs) {
      final data = doc.data();
      final String? rawBranchId = data['branchId'] as String?;
      final String branchId =
          rawBranchId?.trim().isNotEmpty == true ? rawBranchId! : 'unknown';

      final String? cnic = data['cnic'] as String?;
      final String? guardianCnic = data['guardianCnic'] as String?;
      final bool? existingIsAdult = data['isAdult'] as bool?;

      final bool hasOwnCnic = cnic != null && cnic.trim().isNotEmpty;
      final bool isAdult = hasOwnCnic;
      final bool needsReview =
          !isAdult && (guardianCnic == null || guardianCnic.trim().isEmpty);

      if (existingIsAdult == null) globalMissingIsAdult++;
      if (isAdult) {
        globalAdults++;
      } else {
        globalChildren++;
        if (needsReview) globalNeedsReview++;
      }

      final stats = branchStats.putIfAbsent(branchId, () => {
        'total': 0, 'adults': 0, 'children': 0,
        'needsReview': 0, 'missingIsAdult': 0,
      });
      stats['total'] = (stats['total'] ?? 0) + 1;
      if (isAdult) {
        stats['adults'] = (stats['adults'] ?? 0) + 1;
      } else {
        stats['children'] = (stats['children'] ?? 0) + 1;
        if (needsReview)
          stats['needsReview'] = (stats['needsReview'] ?? 0) + 1;
      }
      if (existingIsAdult == null)
        stats['missingIsAdult'] = (stats['missingIsAdult'] ?? 0) + 1;

      processed++;
      setState(() {});

      if (doUpdate) {
        final updates = <String, dynamic>{
          'isAdult': isAdult,
          'needsReview': needsReview,
        };
        if (isAdult) updates['guardianCnic'] = null;

        batch ??= FirebaseFirestore.instance.batch();
        batch.update(doc.reference, updates);
        batchCount++;

        if (batchCount >= 500) {
          await batch.commit();
          batch = null;
          batchCount = 0;
        }
      }
    }

    if (doUpdate && batch != null && batchCount > 0) await batch.commit();
    setState(() => isRunning = false);
  }

  Future<void> _clearLocalAndRefresh() async {
    final ok = await _confirm(
      title: 'Clear All Local Data?',
      body: 'This will:\n'
          '• Delete ALL local patients, tokens, stock, etc.\n'
          '• Re-download fresh data from server\n'
          '• Permanently remove all duplicates\n\n'
          'This action cannot be undone.',
      confirmLabel: 'Yes, Clear Everything',
      confirmColor: Colors.red,
    );
    if (!ok) return;

    setState(() => isClearingLocal = true);
    try {
      await lss.LocalStorageService.clearAllData();
      await lss.LocalStorageService.fullDownloadOnce('all');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Success! All local data cleared and fresh data downloaded.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 8),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ));
      }
    } finally {
      if (mounted) setState(() => isClearingLocal = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Computed
  // ─────────────────────────────────────────────────────────────────────────

  bool get _anyBusy =>
      isRunning || isMigrating || isClearingLocal || isMerging;

  List<Map<String, dynamic>> get sortedBranchList {
    return branchStats.entries
        .map((e) => {
              'branchId': e.key,
              'branchName': branchNames[e.key] ?? e.key,
              'total': e.value['total'] ?? 0,
              'adults': e.value['adults'] ?? 0,
              'children': e.value['children'] ?? 0,
              'needsReview': e.value['needsReview'] ?? 0,
              'missingIsAdult': e.value['missingIsAdult'] ?? 0,
            })
        .toList()
      ..sort((a, b) => (a['branchName'] as String)
          .compareTo(b['branchName'] as String));
  }

  List<QueryDocumentSnapshot> get filteredPatients {
    if (_searchQuery.isEmpty) return allPatients;
    final q = _searchQuery.toLowerCase();
    return allPatients.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      return ((d['name'] as String?)?.toLowerCase().contains(q) ?? false) ||
          ((d['cnic'] as String?)?.toLowerCase().contains(q) ?? false) ||
          ((d['guardianCnic'] as String?)?.toLowerCase().contains(q) ??
              false) ||
          ((d['phone'] as String?)?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool hasData = allPatients.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fix & Review Patients'),
        backgroundColor: const Color(0xFF006D5B),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Patient Data Tool',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '• Has any CNIC → Adult\n'
                    '• No CNIC → True Child\n'
                    '• Child without guardian CNIC → Needs Review',
                    style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[700],
                        height: 1.4),
                  ),
                  const SizedBox(height: 24),

                  // ── REPAIR TOOL ────────────────────────────────────────
                  Card(
                    elevation: 6,
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: const [
                            Icon(Icons.build_circle,
                                size: 32, color: Colors.blue),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Repair Prescription Data',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _PassRow(
                                  icon: Icons.looks_one,
                                  color: Colors.green,
                                  title: 'Pass 1 — prescriptions collection',
                                  body:
                                      'prescriptions/{cnic}/prescriptions/{serial}\n'
                                      '→ copies full doctor data into matching serial doc',
                                ),
                                SizedBox(height: 10),
                                _PassRow(
                                  icon: Icons.looks_two,
                                  color: Colors.teal,
                                  title: 'Pass 2 — old dispensary docs',
                                  body:
                                      'dispensary/{date}/{date}/{serial} (flat schema)\n'
                                      '→ pulls prescriptions stored flat in old dispensary records',
                                ),
                                SizedBox(height: 10),
                                _PassRow(
                                  icon: Icons.looks_3,
                                  color: Colors.indigo,
                                  title: 'Pass 3 — flat serials',
                                  body:
                                      'serials with top-level prescriptions[] but no nested map\n'
                                      '→ wraps them into the standard prescription map',
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Safe: never overwrites a complete existing map, '
                                  'never touches dispensed status, uses update() not set().',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Live stats
                          if (mergeScanned > 0 || mergeStatus.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(mergeStatus,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.blue)),
                                  const Divider(height: 16),
                                  _buildStatRow(
                                      'Total docs scanned', mergeScanned),
                                  _buildStatRow(
                                      'Pass 1: prescriptions → serial',
                                      mergePrescToSerial,
                                      color: Colors.green,
                                      bold: true),
                                  _buildStatRow(
                                      'Pass 2: dispensary → serial',
                                      mergeDispToSerial,
                                      color: Colors.teal,
                                      bold: true),
                                  _buildStatRow(
                                      'Pass 3: flat → nested',
                                      mergeSerialToSerial,
                                      color: Colors.indigo,
                                      bold: true),
                                  _buildStatRow(
                                      'Already complete (skipped)',
                                      mergeSkipped,
                                      color: Colors.grey),
                                  _buildStatRow('Write errors', mergeFailed,
                                      color: Colors.red,
                                      bold: mergeFailed > 0),
                                ],
                              ),
                            ),

                          if (isMerging)
                            const Column(children: [
                              LinearProgressIndicator(),
                              SizedBox(height: 8),
                              Text(
                                  'Running… may take a while for large datasets.'),
                            ])
                          else
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _anyBusy
                                      ? null
                                      : () => _runMerge(dryRun: true),
                                  icon: const Icon(Icons.preview,
                                      color: Colors.blue),
                                  label: const Text('Dry Run (count only)',
                                      style:
                                          TextStyle(color: Colors.blue)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Colors.blue),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _anyBusy
                                      ? null
                                      : () async {
                                          final ok = await _confirm(
                                            title: 'Run Repair?',
                                            body:
                                                'This will write prescription data into matching '
                                                'serial docs in Firestore.\n\n'
                                                'Run Dry Run first to preview counts.\n'
                                                'Existing complete data will NOT be overwritten.',
                                            confirmLabel: 'Yes, Repair',
                                            confirmColor: Colors.blue,
                                          );
                                          if (ok)
                                            _runMerge(dryRun: false);
                                        },
                                  icon: const Icon(Icons.build_circle,
                                      color: Colors.white),
                                  label: const Text('Run Repair',
                                      style: TextStyle(
                                          color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[700],
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 14),
                                    elevation: 4,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── CLEAR LOCAL ────────────────────────────────────────
                  Card(
                    elevation: 6,
                    color: Colors.red[50],
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          const Text('Clear All Local Data',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          const SizedBox(height: 8),
                          const Text(
                            'Permanently deletes all local patients, tokens, stock, etc.\n'
                            'Then re-downloads fresh data from server.\n'
                            'Use this to fix duplicates once and for all.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 16),
                          if (isClearingLocal)
                            const Column(children: [
                              CircularProgressIndicator(color: Colors.red),
                              SizedBox(height: 12),
                              Text('Clearing and re-downloading...'),
                            ])
                          else
                            ElevatedButton.icon(
                              onPressed: _anyBusy
                                  ? null
                                  : _clearLocalAndRefresh,
                              icon: const Icon(Icons.delete_forever,
                                  color: Colors.white),
                              label: const Text(
                                  'Clear Local & Re-Download'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 16),
                                elevation: 4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── GLOBAL SUMMARY ─────────────────────────────────────
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Global Summary',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const Divider(),
                          _buildStatRow('Total Patients', totalPatients),
                          _buildStatRow(
                              'Adults (has own CNIC)', globalAdults,
                              color: Colors.blue),
                          _buildStatRow(
                              'True Children (no CNIC)', globalChildren,
                              color: Colors.purple),
                          _buildStatRow('Needs Review', globalNeedsReview,
                              color: Colors.red, bold: true),
                          _buildStatRow('Missing isAdult Field',
                              globalMissingIsAdult,
                              color: Colors.orange[800], bold: true),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: totalPatients > 0
                                ? processed / totalPatients
                                : 0,
                            minHeight: 10,
                          ),
                          const SizedBox(height: 8),
                          Text('Processed: $processed / $totalPatients',
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Text('Branch-wise Summary',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 180,
                    child: hasData
                        ? ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: sortedBranchList.length,
                            itemBuilder: (_, i) {
                              final b = sortedBranchList[i];
                              final hasIssues = b['needsReview'] > 0 ||
                                  b['branchId'] == 'unknown' ||
                                  b['missingIsAdult'] > 0;
                              return SizedBox(
                                width: 240,
                                child: Card(
                                  color:
                                      hasIssues ? Colors.red[50] : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(b['branchName'],
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.bold,
                                                color:
                                                    b['branchId'] ==
                                                            'unknown'
                                                        ? Colors
                                                            .orange[800]
                                                        : const Color(
                                                            0xFF006D5B))),
                                        if (b['branchId'] == 'unknown')
                                          const Text('Missing branchId',
                                              style: TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 12)),
                                        const SizedBox(height: 8),
                                        _buildStatRow(
                                            'Total', b['total']),
                                        _buildStatRow(
                                            'Adults', b['adults'],
                                            color: Colors.blue),
                                        _buildStatRow(
                                            'Children', b['children'],
                                            color: Colors.purple),
                                        _buildStatRow(
                                            'Review', b['needsReview'],
                                            color: Colors.red,
                                            bold: true),
                                        _buildStatRow('Missing isAdult',
                                            b['missingIsAdult'],
                                            color: Colors.orange[800],
                                            bold: true),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : const Center(child: Text('No data yet')),
                  ),

                  const SizedBox(height: 24),

                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText:
                          'Search by Name, CNIC, Guardian CNIC, Phone',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.toLowerCase()),
                    enabled: hasData,
                  ),

                  const SizedBox(height: 16),
                  const Text('All Patients',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),

                  hasData
                      ? ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredPatients.length,
                          itemBuilder: (_, index) {
                            final doc = filteredPatients[index];
                            final data =
                                doc.data() as Map<String, dynamic>;
                            final patientId = doc.id;
                            final cnic =
                                (data['cnic'] as String?)?.trim();
                            final guardianCnic =
                                (data['guardianCnic'] as String?)
                                    ?.trim();
                            final hasCnic =
                                cnic != null && cnic.isNotEmpty;
                            final needsReview =
                                data['needsReview'] == true;
                            final missingIsAdult =
                                (data['isAdult'] as bool?) == null;
                            final cnicIsPatientId =
                                patientId == cnic && cnic != null;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4),
                              color: needsReview
                                  ? Colors.red[50]
                                  : missingIsAdult
                                      ? Colors.yellow[50]
                                      : null,
                              child: ListTile(
                                title: Text(
                                    (data['name'] as String?) ??
                                        'No Name',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (cnic != null && cnic.isNotEmpty)
                                      Text(
                                          'CNIC: $cnic${cnicIsPatientId ? ' (Used as ID)' : ''}'),
                                    if (guardianCnic != null &&
                                        guardianCnic.isNotEmpty)
                                      Text(
                                          'Guardian CNIC: $guardianCnic',
                                          style: const TextStyle(
                                              color: Colors.green)),
                                    if (!hasCnic)
                                      const Text(
                                          'No Own CNIC → True Child',
                                          style: TextStyle(
                                              color: Colors.purple)),
                                    if (data['phone'] != null)
                                      Text('Phone: ${data['phone']}'),
                                    const SizedBox(height: 4),
                                    Wrap(spacing: 8, children: [
                                      Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.person,
                                                size: 16,
                                                color: hasCnic
                                                    ? Colors.blue
                                                    : Colors.purple),
                                            const SizedBox(width: 4),
                                            Text(
                                                hasCnic
                                                    ? 'Adult'
                                                    : 'Child',
                                                style: TextStyle(
                                                    color: hasCnic
                                                        ? Colors.blue
                                                        : Colors
                                                            .purple)),
                                          ]),
                                      if (needsReview)
                                        const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.warning,
                                                  size: 16,
                                                  color: Colors.red),
                                              SizedBox(width: 4),
                                              Text('Needs Review',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ]),
                                      if (missingIsAdult)
                                        const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.help_outline,
                                                  size: 16,
                                                  color: Colors.orange),
                                              SizedBox(width: 4),
                                              Text('Missing isAdult',
                                                  style: TextStyle(
                                                      color: Colors.orange,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold)),
                                            ]),
                                      if (cnicIsPatientId)
                                        const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.key,
                                                  size: 16,
                                                  color: Colors.orange),
                                              SizedBox(width: 4),
                                              Text('CNIC = ID',
                                                  style: TextStyle(
                                                      color:
                                                          Colors.orange)),
                                            ]),
                                    ]),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'No data loaded yet.\n'
                              'Press "Dry Run" below to scan all patients.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18, color: Colors.grey),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),

          // ── BOTTOM BAR ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10)
              ],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _anyBusy
                        ? null
                        : () => _processData(doUpdate: false),
                    icon: const Icon(Icons.visibility),
                    label: const Text('Dry Run (Scan Only)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _anyBusy
                        ? null
                        : () => _processData(doUpdate: true),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Fix Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_anyBusy)
            const LinearProgressIndicator(
                minHeight: 4, backgroundColor: Colors.transparent),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Small helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    Color confirmColor = Colors.blue,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget _buildStatRow(String label, int value,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          const Spacer(),
          Text(
            value.toString(),
            style: TextStyle(
                fontSize: 16,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color),
          ),
        ],
      ),
    );
  }
}

// ── Small display widget used inside the repair card ──────────────────────

class _PassRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _PassRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 13)),
              Text(body,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black87, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}