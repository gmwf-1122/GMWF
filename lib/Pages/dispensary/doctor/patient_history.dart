// lib/pages/dispensary/doctor/patient_history.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../services/local_storage_service.dart';

// Alias — doctor_screen.dart uses PatientHistory(patientData: ...)
// patient_detail_screen.dart uses PatientHistory(patientCnic: ...)
typedef PatientHistory = PatientHistoryPanel;

class PatientHistoryPanel extends StatefulWidget {
  final String branchId;

  /// Used by doctor_screen.dart
  final Map<String, dynamic>? patientData;

  /// Used by patient_detail_screen.dart
  final String? patientCnic;

  /// Used by patient_detail_screen.dart
  final void Function(Map<String, dynamic>)? onRepeatLast;

  const PatientHistoryPanel({
    super.key,
    required this.branchId,
    this.patientData,
    this.patientCnic,
    this.onRepeatLast,
  }) : assert(
            patientData != null || patientCnic != null,
            'Provide patientData or patientCnic');

  @override
  State<PatientHistoryPanel> createState() => _PatientHistoryPanelState();
}

class _PatientHistoryPanelState extends State<PatientHistoryPanel> {
  static const Color _teal = Color(0xFF00695C);

  List<_HistoryEntry> _entries = [];
  bool _isLoading = false;
  String _requestedCnic = '';
  String? _targetPatientId;

  Map<String, dynamic>? get _effectiveData =>
      widget.patientData ??
      (widget.patientCnic != null
          ? {'patientCnic': widget.patientCnic}
          : null);

  String _resolveCnic(Map<String, dynamic>? data) {
    if (data != null) {
      for (final f in ['cnic', 'patientCnic', 'patientId', 'guardianCnic']) {
        final raw = data[f]?.toString().trim() ?? '';
        final v = raw.replaceAll(RegExp(r'[-\s]'), '').toLowerCase();
        if (v.length >= 5 && v != '0000000000000') return v;
      }
    }
    if (widget.patientCnic != null) {
      return widget.patientCnic!
          .trim()
          .replaceAll(RegExp(r'[-\s]'), '')
          .toLowerCase();
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant PatientHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCnic = _resolveCnic(_effectiveData);
    if (newCnic != _requestedCnic) _loadHistory();
  }

  Future<void> _loadHistory() async {
    final cnic = _resolveCnic(_effectiveData);
    final effectiveData = _effectiveData;

    // Prefer a stable per-patient identifier when available (e.g. child keys
    // that include guardian CNIC + child name). This lets multiple children
    // under the same guardian CNIC have independent visit histories instead
    // of one merged family history.
    final rawPatientId = effectiveData?['patientId']?.toString().trim();
    _targetPatientId =
        rawPatientId != null && rawPatientId.isNotEmpty ? rawPatientId : null;

    if (cnic.isEmpty) {
      if (mounted) {
        setState(() {
          _entries = [];
          _requestedCnic = '';
        });
      }
      return;
    }

    _requestedCnic = cnic;
    if (mounted)
      setState(() {
        _isLoading = true;
        _entries = [];
      });

    final List<_HistoryEntry> found = [];

    // Step 1: Hive
    try {
      final box = Hive.box(LocalStorageService.prescriptionsBox);
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);

        // If we know the specific patientId we care about, prefer that over
        // pure CNIC matching so siblings sharing a guardian CNIC do not
        // share one combined history.
        final docPatientId = data['patientId']?.toString().trim();
        if (_targetPatientId != null) {
          if (docPatientId == null ||
              docPatientId.isEmpty ||
              docPatientId != _targetPatientId) {
            continue;
          }
        } else {
          final docCnic = _resolveCnic(data);
          if (docCnic.isEmpty || docCnic != cnic) continue;
        }

        final entry = _HistoryEntry.fromMap(data);
        if (entry != null && !found.any((e) => e.serial == entry.serial)) {
          found.add(entry);
        }
      }
    } catch (e) {
      debugPrint('[PatientHistory] Hive scan error: $e');
    }

    // Step 2: Firestore prescriptions/{cnic}/prescriptions
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(cnic)
          .collection('prescriptions')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final docPatientId = data['patientId']?.toString().trim();

        if (_targetPatientId != null &&
            (docPatientId == null ||
             docPatientId.isEmpty ||
             docPatientId != _targetPatientId)) {
          // This prescription belongs to a different child under the same
          // guardian CNIC — ignore for this patient's personal history.
          continue;
        }

        data['serial'] ??= doc.id;
        final entry = _HistoryEntry.fromMap(data);
        if (entry != null && !found.any((e) => e.serial == entry.serial)) {
          found.add(entry);
          try {
            Hive.box(LocalStorageService.prescriptionsBox)
                .put('${cnic}_${entry.serial}', data);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[PatientHistory] Firestore prescriptions/$cnic error: $e');
    }

    // Step 3: Firestore serials scan
    try {
      final datesSnap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .get();

      for (final dateDoc in datesSnap.docs) {
        for (final qt in ['zakat', 'non-zakat', 'gmwf']) {
          QuerySnapshot qtSnap;
          try {
            qtSnap = await dateDoc.reference
                .collection(qt)
                .where('patientCnic', isEqualTo: cnic)
                .get();
          } catch (_) {
            continue;
          }

          for (final serialDoc in qtSnap.docs) {
            if (_requestedCnic != cnic) return;

            // FIX: data() returns Map? — null-check required
            final rawData = serialDoc.data();
            if (rawData == null) continue;
            final data = Map<String, dynamic>.from(rawData as Map);

            final embedded = data['prescription'];
            final source =
                (embedded is Map && (embedded['prescriptions'] is List))
                    ? Map<String, dynamic>.from(embedded)
                    : data;
            source['serial'] ??= serialDoc.id;

            final sourcePatientId =
                source['patientId']?.toString().trim();
            if (_targetPatientId != null &&
                (sourcePatientId == null ||
                 sourcePatientId.isEmpty ||
                 sourcePatientId != _targetPatientId)) {
              // Serial belongs to another child that shares the same CNIC
              // or guardian CNIC; skip it for this patient's history.
              continue;
            }

            final entry = _HistoryEntry.fromMap(source);
            if (entry != null &&
                !found.any((e) => e.serial == entry.serial)) {
              found.add(entry);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[PatientHistory] Firestore serials scan error: $e');
    }

    if (_requestedCnic != cnic) return;
    found.sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _entries = found;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patientData?['name']?.toString() ??
        widget.patientData?['patientName']?.toString() ??
        widget.patientCnic ??
        'Patient';
    final cnic = _resolveCnic(_effectiveData);

    if (cnic.isEmpty) {
      return const Center(
        child: Text('Select a patient to view history',
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            const Icon(Icons.history, color: _teal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('History — $patientName',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _teal)),
                  Text(cnic,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: _teal, size: 20),
              tooltip: 'Reload history',
              onPressed: _isLoading ? null : _loadHistory,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: _teal))
              : _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_outlined,
                              size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            'No prescription history found\nfor $patientName',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) => _HistoryCard(
                        entry: _entries[i],
                        onRepeatLast: i == 0 ? widget.onRepeatLast : null,
                      ),
                    ),
        ),
      ],
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────────────────

class _HistoryEntry {
  final String serial;
  final DateTime date;
  final String diagnosis;
  final String complaint;
  final String doctorName;
  final List<_MedEntry> medicines;
  final List<String> labTests;
  final Map<String, dynamic> raw;

  const _HistoryEntry({
    required this.serial,
    required this.date,
    required this.diagnosis,
    required this.complaint,
    required this.doctorName,
    required this.medicines,
    required this.labTests,
    required this.raw,
  });

  static _HistoryEntry? fromMap(Map<String, dynamic> data) {
    final serial = (data['serial'] ?? data['id'] ?? '').toString().trim();
    if (serial.isEmpty) return null;

    DateTime date = DateTime(2000);
    try {
      final dateStr = serial.split('-')[0];
      if (dateStr.length == 6) {
        final d = int.parse(dateStr.substring(0, 2));
        final m = int.parse(dateStr.substring(2, 4));
        final y = 2000 + int.parse(dateStr.substring(4, 6));
        date = DateTime(y, m, d);
      }
    } catch (_) {}

    if (date.year == 2000) {
      final rawTs = data['createdAt'] ?? data['completedAt'];
      if (rawTs is Timestamp) {
        date = rawTs.toDate();
      } else if (rawTs is String) {
        try {
          date = DateTime.parse(rawTs);
        } catch (_) {}
      }
    }

    final meds = <_MedEntry>[];
    final rawMeds = data['prescriptions'];
    if (rawMeds is List) {
      for (final m in rawMeds) {
        if (m is! Map) continue;
        meds.add(_MedEntry(
          name: m['name']?.toString() ?? '',
          type: m['type']?.toString() ?? '',
          timing: m['timing']?.toString() ?? '',
          meal: m['meal']?.toString() ?? '',
          dosage: m['dosage']?.toString() ?? '',
          quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        ));
      }
    }

    final labs = <String>[];
    final rawLabs = data['labResults'];
    if (rawLabs is List) {
      for (final l in rawLabs) {
        final name =
            (l is Map ? l['name'] : l)?.toString().trim() ?? '';
        if (name.isNotEmpty) labs.add(name);
      }
    }

    return _HistoryEntry(
      serial: serial,
      date: date,
      diagnosis: data['diagnosis']?.toString() ?? '',
      complaint:
          (data['complaint'] ?? data['condition'] ?? '').toString(),
      doctorName:
          (data['doctorName'] ?? data['prescribedBy'] ?? '').toString(),
      medicines: meds,
      labTests: labs,
      raw: data,
    );
  }
}

class _MedEntry {
  final String name, type, timing, meal, dosage;
  final int quantity;

  const _MedEntry({
    required this.name,
    required this.type,
    required this.timing,
    required this.meal,
    required this.dosage,
    required this.quantity,
  });

  String get abbrev {
    final t = type.toLowerCase();
    if (t.contains('syrup')) return 'syp.';
    if (t.contains('injection')) return 'inj.';
    if (t.contains('tablet')) return 'tab.';
    if (t.contains('capsule')) return 'cap.';
    if (t.contains('drip')) return 'drip.';
    return '';
  }

  String get displayName =>
      abbrev.isNotEmpty && !name.toLowerCase().startsWith(abbrev)
          ? '$abbrev $name'
          : name;
}

// ── Card ───────────────────────────────────────────────────────────────────────

class _HistoryCard extends StatefulWidget {
  final _HistoryEntry entry;
  final void Function(Map<String, dynamic>)? onRepeatLast;

  const _HistoryCard({required this.entry, this.onRepeatLast});

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _expanded = false;
  static const Color _teal = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final dateStr = DateFormat('d MMM yyyy').format(e.date);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _teal.withOpacity(0.25)),
                    ),
                    child: Text(dateStr,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _teal)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.diagnosis.isNotEmpty)
                            Text(e.diagnosis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          if (e.complaint.isNotEmpty)
                            Text(e.complaint,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600])),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              ...e.medicines.take(4).map((m) =>
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          _teal.withOpacity(0.08),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(m.name,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: _teal)),
                                  )),
                              if (e.medicines.length > 4)
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                      '+${e.medicines.length - 4} more',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey)),
                                ),
                            ],
                          ),
                        ]),
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.onRepeatLast != null)
                      IconButton(
                        icon: const Icon(Icons.repeat,
                            size: 18, color: _teal),
                        tooltip: 'Repeat prescription',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () =>
                            widget.onRepeatLast!(e.raw),
                      ),
                    const SizedBox(width: 4),
                    Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.grey[400]),
                  ]),
                ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.person_pin,
                        size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      e.doctorName.isNotEmpty
                          ? e.doctorName
                          : 'Unknown Doctor',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600]),
                    ),
                    const Spacer(),
                    Text(e.serial,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
                  ]),
                  const SizedBox(height: 10),
                  if (e.medicines.isNotEmpty) ...[
                    _sectionLabel(
                        'Medicines', Icons.medication_outlined),
                    const SizedBox(height: 6),
                    ...e.medicines.map((m) => _MedRow(med: m)),
                    const SizedBox(height: 8),
                  ],
                  if (e.labTests.isNotEmpty) ...[
                    _sectionLabel('Lab Tests', Icons.biotech),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: e.labTests
                          .map((t) => Chip(
                                label: Text(t,
                                    style: const TextStyle(
                                        fontSize: 11)),
                                backgroundColor:
                                    Colors.orange.shade50,
                                side: BorderSide(
                                    color:
                                        Colors.orange.shade200),
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 4),
                                materialTapTargetSize:
                                    MaterialTapTargetSize
                                        .shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],
                ]),
          ),
        ],
      ]),
    );
  }

  Widget _sectionLabel(String title, IconData icon) =>
      Row(children: [
        Icon(icon, size: 13, color: _teal),
        const SizedBox(width: 4),
        Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _teal)),
      ]);
}

class _MedRow extends StatelessWidget {
  final _MedEntry med;

  const _MedRow({required this.med});

  static const Color _teal = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    final parts = med.timing.split('+');
    final m = parts.isNotEmpty ? parts[0] : '0';
    final e = parts.length > 1 ? parts[1] : '0';
    final n = parts.length > 2 ? parts[2] : '0';
    final isInj = med.type.toLowerCase().contains('injection') ||
        med.type.toLowerCase().contains('inj');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
                flex: 3,
                child: Text(med.displayName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600))),
            if (isInj)
              _pill('×${med.quantity}', Colors.orange.shade100,
                  Colors.orange.shade700)
            else ...[
              _pill('$m–$e–$n', _teal.withOpacity(0.1), _teal),
              const SizedBox(width: 4),
              if (med.meal.isNotEmpty)
                _pill(med.meal, Colors.grey.shade100,
                    Colors.grey.shade600),
              if (med.dosage.isNotEmpty) ...[
                const SizedBox(width: 4),
                _pill(med.dosage, Colors.purple.shade50,
                    Colors.purple.shade400),
              ],
            ],
          ]),
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg)),
      );
}