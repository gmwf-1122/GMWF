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

  /// Called only when compactMode = true (doctor screen inline panel)
  final void Function(Map<String, dynamic>)? onRepeatLast;

  /// When true: compact card design, no repeat button (used inside DoctorScreen inline panel)
  /// When false (default): full card design, no repeat button either
  ///   — repeat is only shown on the dedicated PatientHistoryPage
  final bool compactMode;

  const PatientHistoryPanel({
    super.key,
    required this.branchId,
    this.patientData,
    this.patientCnic,
    this.onRepeatLast,
    this.compactMode = false,
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
  String _requestedPatientId = '';
  Map<String, dynamic>? _patientData;

  @override
  void initState() {
    super.initState();
    _fetchPatientData().then((_) => _loadHistory());
  }

  @override
  void didUpdateWidget(covariant PatientHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newId = _getPatientIdentifier();
    if (newId != _requestedPatientId) {
      _fetchPatientData().then((_) => _loadHistory());
    }
  }

  String _getPatientIdentifier() {
    if (widget.patientCnic != null) return widget.patientCnic!;
    if (widget.patientData?['patientId'] != null) return widget.patientData!['patientId'];
    if (widget.patientData?['cnic'] != null) return widget.patientData!['cnic'];
    if (widget.patientData?['patientCnic'] != null) return widget.patientData!['patientCnic'];
    if (widget.patientData?['guardianCnic'] != null) return widget.patientData!['guardianCnic'];
    return '';
  }

  Future<void> _fetchPatientData() async {
    final patientId = _getPatientIdentifier();
    if (patientId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId.toLowerCase())
          .collection('patients')
          .doc(patientId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (doc.exists) {
        setState(() {
          _patientData = doc.data();
        });
      }
    } catch (e) {
      debugPrint('[PatientHistory] Error fetching patient data: $e');
    }
  }

  List<String> _getPossibleIdentifiers() {
    final ids = <String>{};

    if (_patientData != null) {
      final cnic = _patientData!['cnic']?.toString().trim() ?? '';
      final guardianCnic = _patientData!['guardianCnic']?.toString().trim() ?? '';
      if (cnic.isNotEmpty) ids.add(cnic);
      if (guardianCnic.isNotEmpty) ids.add(guardianCnic);
    }

    final patientId = _getPatientIdentifier();
    if (patientId.trim().isNotEmpty) ids.add(patientId);

    return ids.toList();
  }

  Future<void> _loadHistory() async {
    final possibleIds = _getPossibleIdentifiers();
    if (possibleIds.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    _requestedPatientId = _getPatientIdentifier();
    if (mounted) setState(() { _isLoading = true; _entries = []; });

    debugPrint('[PatientHistory] Looking for prescriptions under parent IDs: $possibleIds');

    final List<_HistoryEntry> found = [];
    final Set<String> seenSerials = {};

    // Step 1: Hive local cache
    try {
      final box = Hive.box(LocalStorageService.prescriptionsBox);
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        final entry = _HistoryEntry.fromMap(data, source: 'Hive Cache');
        if (entry != null && !seenSerials.contains(entry.serial)) {
          found.add(entry);
          seenSerials.add(entry.serial);
        }
      }
    } catch (e) {
      debugPrint('[PatientHistory] Hive scan error: $e');
    }

    // Step 2: Firestore prescriptions/{id}/prescriptions
    try {
      for (final id in possibleIds) {
        if (id.isEmpty) continue;
        debugPrint('[PatientHistory] Checking parent: $id');

        final query = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId.toLowerCase())
            .collection('prescriptions')
            .doc(id)
            .collection('prescriptions')
            .orderBy('createdAt', descending: true)
            .get()
            .timeout(const Duration(seconds: 15));

        debugPrint('[PatientHistory] Found ${query.docs.length} prescriptions under $id');

        for (final doc in query.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['serial'] ??= doc.id;

          final entry = _HistoryEntry.fromMap(data, source: 'Prescriptions');
          if (entry != null && !seenSerials.contains(entry.serial)) {
            found.add(entry);
            seenSerials.add(entry.serial);
            try {
              Hive.box(LocalStorageService.prescriptionsBox)
                  .put('${id}_${entry.serial}', data);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[PatientHistory] Firestore prescriptions error: $e');
    }

    if (mounted) {
      found.sort((a, b) => b.date.compareTo(a.date));
      debugPrint('[PatientHistory] Total entries found: ${found.length}');
      setState(() { _entries = found; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = widget.patientData?['name']?.toString() ??
        _patientData?['name']?.toString() ??
        widget.patientCnic ??
        'Patient';
    final patientId = _getPatientIdentifier();

    if (patientId.isEmpty) {
      return const Center(
        child: Text('Select a patient to view history',
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }

    // ── COMPACT MODE: only show the single latest visit card ────────────────
    if (widget.compactMode) {
      return _buildCompactLatestVisit(patientName, patientId);
    }

    // ── FULL MODE: scrollable list (patient_detail_screen) ──────────────────
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
                          fontSize: 16, fontWeight: FontWeight.bold, color: _teal)),
                  Text(patientId,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_outlined, size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            'No prescription history found\nfor $patientName',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500], fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) => _HistoryCard(
                        entry: _entries[i],
                        isLatest: i == 0,
                        onRepeatLast: null, // no repeat in detail screen
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildCompactLatestVisit(String patientName, String patientId) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }

    final totalVisits = _entries.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ───────────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.history_edu_rounded, color: _teal, size: 17),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Last Visit',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: _teal),
              ),
            ),
            if (totalVisits > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _teal.withOpacity(0.3)),
                ),
                child: Text(
                  '$totalVisits visit${totalVisits == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: _teal),
                ),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _isLoading ? null : _loadHistory,
              child: Icon(Icons.refresh_rounded, color: _teal, size: 17),
            ),
          ]),
          const SizedBox(height: 8),

          if (_entries.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              child: Column(children: [
                Icon(Icons.assignment_outlined, size: 36, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('No visit history yet',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ]),
            )
          else
            _CompactLatestCard(
              entry: _entries.first,
              onRepeat: widget.onRepeatLast,
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEDICATED FULL-PAGE HISTORY — opened from DoctorScreen's history button
// ═══════════════════════════════════════════════════════════════════════════════

class PatientHistoryPage extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic> patientData;
  final void Function(Map<String, dynamic>)? onRepeatLast;

  const PatientHistoryPage({
    super.key,
    required this.branchId,
    required this.patientData,
    this.onRepeatLast,
  });

  @override
  State<PatientHistoryPage> createState() => _PatientHistoryPageState();
}

class _PatientHistoryPageState extends State<PatientHistoryPage> {
  static const Color _teal = Color(0xFF00695C);

  List<_HistoryEntry> _entries = [];
  bool _isLoading = true;
  Map<String, dynamic>? _patientData;

  @override
  void initState() {
    super.initState();
    _fetchAndLoad();
  }

  String _getPatientIdentifier() {
    final d = widget.patientData;
    if (d['patientId'] != null) return d['patientId'].toString();
    if (d['cnic'] != null) return d['cnic'].toString();
    if (d['patientCnic'] != null) return d['patientCnic'].toString();
    if (d['guardianCnic'] != null) return d['guardianCnic'].toString();
    return '';
  }

  Future<void> _fetchAndLoad() async {
    if (mounted) setState(() => _isLoading = true);

    final patientId = _getPatientIdentifier();
    if (patientId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Fetch full patient doc
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId.toLowerCase())
          .collection('patients')
          .doc(patientId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (doc.exists && mounted) setState(() => _patientData = doc.data());
    } catch (_) {}

    final ids = <String>{};
    if (_patientData != null) {
      final cnic = _patientData!['cnic']?.toString().trim() ?? '';
      final gCnic = _patientData!['guardianCnic']?.toString().trim() ?? '';
      if (cnic.isNotEmpty) ids.add(cnic);
      if (gCnic.isNotEmpty) ids.add(gCnic);
    }
    ids.add(patientId);

    final List<_HistoryEntry> found = [];
    final Set<String> seenSerials = {};

    // Hive
    try {
      final box = Hive.box(LocalStorageService.prescriptionsBox);
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        final entry = _HistoryEntry.fromMap(data, source: 'Hive Cache');
        if (entry != null && !seenSerials.contains(entry.serial)) {
          found.add(entry);
          seenSerials.add(entry.serial);
        }
      }
    } catch (_) {}

    // Firestore
    for (final id in ids) {
      if (id.isEmpty) continue;
      try {
        final query = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId.toLowerCase())
            .collection('prescriptions')
            .doc(id)
            .collection('prescriptions')
            .orderBy('createdAt', descending: true)
            .get()
            .timeout(const Duration(seconds: 15));

        for (final doc in query.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data['serial'] ??= doc.id;
          final entry = _HistoryEntry.fromMap(data, source: 'Prescriptions');
          if (entry != null && !seenSerials.contains(entry.serial)) {
            found.add(entry);
            seenSerials.add(entry.serial);
            try {
              Hive.box(LocalStorageService.prescriptionsBox)
                  .put('${id}_${entry.serial}', data);
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[PatientHistoryPage] Firestore error for $id: $e');
      }
    }

    if (mounted) {
      found.sort((a, b) => b.date.compareTo(a.date));
      setState(() { _entries = found; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.patientData['name']?.toString() ??
        _patientData?['name']?.toString() ??
        'Patient';
    final id = _getPatientIdentifier();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(id, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchAndLoad,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _entries.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 14),
                    Text('No visit history found for $name',
                        style: TextStyle(color: Colors.grey[500], fontSize: 15),
                        textAlign: TextAlign.center),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) => _HistoryCard(
                    entry: _entries[i],
                    isLatest: i == 0,
                    // Repeat button only on the first/latest card in the full page
                    onRepeatLast: (i == 0 && widget.onRepeatLast != null)
                        ? (raw) {
                            widget.onRepeatLast!(raw);
                            Navigator.pop(context);
                          }
                        : null,
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT LATEST CARD — shows only the most recent visit inside DoctorScreen
// Clear labeled sections, repeat button, tight but readable layout
// ═══════════════════════════════════════════════════════════════════════════════

class _CompactLatestCard extends StatelessWidget {
  final _HistoryEntry entry;
  final void Function(Map<String, dynamic>)? onRepeat;
  static const Color _teal = Color(0xFF00695C);

  const _CompactLatestCard({required this.entry, this.onRepeat});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final dateStr = DateFormat('d MMM yyyy  •  hh:mm a').format(e.date);
    final oralMeds = e.medicines.where((m) => !m.isInjectable).toList();
    final injectables = e.medicines.where((m) => m.isInjectable).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _teal.withOpacity(0.25), width: 1.2),
        boxShadow: [
          BoxShadow(color: _teal.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Teal header: date + doctor ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _teal,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_month_rounded, color: Colors.white70, size: 13),
            const SizedBox(width: 5),
            Expanded(
              child: Text(dateStr,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
            if (e.doctorName.isNotEmpty)
              Row(children: [
                const Icon(Icons.person_outline_rounded, color: Colors.white60, size: 13),
                const SizedBox(width: 4),
                Text(e.doctorName,
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
          ]),
        ),

        // ── Body ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Condition — clearly labeled
            if (e.complaint.isNotEmpty) ...[
              _label('Condition'),
              const SizedBox(height: 3),
              Text(e.complaint,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
            ],

            // Diagnosis — same plain style as condition
            if (e.diagnosis.isNotEmpty) ...[
              _label('Diagnosis'),
              const SizedBox(height: 3),
              Text(e.diagnosis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
            ],

            // Vitals row
            if (e.vitals.isNotEmpty) ...[
              _label('Vitals'),
              const SizedBox(height: 4),
              Wrap(spacing: 5, runSpacing: 5, children: [
                if (e.vitals['bp'] != null)
                  _vitalChip('BP', e.vitals['bp'].toString(), const Color(0xFFE91E63)),
                if (e.vitals['temp'] != null)
                  _vitalChip('Temp', '${e.vitals['temp']}${e.vitals['tempUnit'] ?? ''}',
                      Colors.orange.shade700),
                if (e.vitals['sugar'] != null)
                  _vitalChip('Sugar', e.vitals['sugar'].toString(), Colors.purple),
                if (e.vitals['weight'] != null)
                  _vitalChip('Wt', '${e.vitals['weight']} kg', Colors.teal),
              ]),
              const SizedBox(height: 8),
            ],

            // Medicines
            if (oralMeds.isNotEmpty) ...[
              _label('Medicines'),
              const SizedBox(height: 4),
              ...oralMeds.map((m) => _medTile(m, isInj: false)),
              const SizedBox(height: 4),
            ],

            // Injectables
            if (injectables.isNotEmpty) ...[
              _label('Injectables'),
              const SizedBox(height: 4),
              ...injectables.map((m) => _medTile(m, isInj: true)),
              const SizedBox(height: 4),
            ],

            // Lab tests
            if (e.labTests.isNotEmpty) ...[
              _label('Lab Tests'),
              const SizedBox(height: 4),
              Wrap(spacing: 5, runSpacing: 5,
                  children: e.labTests.map((t) => _labChip(t)).toList()),
              const SizedBox(height: 4),
            ],

            // Repeat button
            if (onRepeat != null) ...[
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => onRepeat!(e.raw),
                  icon: const Icon(Icons.repeat_rounded, size: 15),
                  label: const Text('Repeat This Prescription',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: _teal,
            letterSpacing: 0.8),
      );

  Widget _vitalChip(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                  text: '$label  ',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: color.withOpacity(0.75))),
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      );

  Widget _labChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
      );

  Widget _medTile(_MedEntry med, {required bool isInj}) {
    final parts = <String>[];
    if (med.dosage.isNotEmpty) parts.add(med.dosage);
    if (med.frequency.isNotEmpty) parts.add(med.frequency);
    if (med.timing.isNotEmpty) parts.add(med.timing);
    if (!isInj && med.meal.isNotEmpty) parts.add(med.meal);

    final badgeColor = isInj ? const Color(0xFF1565C0) : _teal;
    final badge = isInj ? 'Inj' : (med.abbrev.length > 3 ? med.abbrev.substring(0, 3) : med.abbrev.isNotEmpty ? med.abbrev : 'Med');

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isInj ? const Color(0xFFE3F2FD) : _teal.withOpacity(0.04),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: isInj ? const Color(0xFF90CAF9) : _teal.withOpacity(0.15)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: badgeColor, borderRadius: BorderRadius.circular(5)),
          child: Text(badge,
              style: const TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(med.name,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (parts.isNotEmpty)
              Text(parts.join(' · '),
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FULL CARD — used in PatientHistoryPage and patient_detail_screen
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryCard extends StatelessWidget {
  final _HistoryEntry entry;
  final bool isLatest;
  final void Function(Map<String, dynamic>)? onRepeatLast;

  const _HistoryCard({
    required this.entry,
    this.isLatest = false,
    this.onRepeatLast,
  });

  static const Color _teal = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final dateStr = DateFormat('d MMM yyyy').format(e.date);
    final timeStr = DateFormat('hh:mm a').format(e.date);
    final oralMeds = e.medicines.where((m) => !m.isInjectable).toList();
    final injectables = e.medicines.where((m) => m.isInjectable).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isLatest ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _teal,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.calendar_today, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(dateStr,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      const Icon(Icons.access_time, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(timeStr,
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Serial: ${e.serial}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                if (isLatest)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration:
                        BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: const Text('LATEST',
                        style: TextStyle(color: _teal, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: e.sourceColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white54),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(e.sourceIcon, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(e.source,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                  ]),
                ),
              ]),
            ]),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (e.doctorName.isNotEmpty) ...[
                Row(children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(e.doctorName,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                ]),
                const SizedBox(height: 12),
              ],
              if (e.complaint.isNotEmpty) ...[
                _buildSectionTitle('Condition', Icons.medical_services_outlined),
                const SizedBox(height: 6),
                Text(e.complaint, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                const SizedBox(height: 12),
              ],
              if (e.diagnosis.isNotEmpty) ...[
                _buildSectionTitle('Diagnosis', Icons.assignment_outlined),
                const SizedBox(height: 6),
                Text(e.diagnosis, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                const SizedBox(height: 12),
              ],
              if (e.vitals.isNotEmpty) ...[
                _buildSectionTitle('Vitals', Icons.favorite_outline),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (e.vitals['bp'] != null)
                    _buildVitalChip('BP', e.vitals['bp'].toString(), Colors.pink),
                  if (e.vitals['temp'] != null)
                    _buildVitalChip(
                        'Temp', '${e.vitals['temp']} ${e.vitals['tempUnit'] ?? ''}', Colors.orange),
                  if (e.vitals['sugar'] != null)
                    _buildVitalChip('Sugar', e.vitals['sugar'].toString(), Colors.purple),
                  if (e.vitals['weight'] != null)
                    _buildVitalChip('Weight', e.vitals['weight'].toString(), Colors.teal),
                ]),
                const SizedBox(height: 12),
              ],
              if (oralMeds.isNotEmpty) ...[
                _buildSectionTitle('Medicines', Icons.medication),
                const SizedBox(height: 8),
                ...oralMeds.map((m) => _buildMedicineRow(m)),
                const SizedBox(height: 12),
              ],
              if (injectables.isNotEmpty) ...[
                _buildSectionTitle('Injectables', Icons.vaccines_outlined),
                const SizedBox(height: 8),
                ...injectables.map((m) => _buildInjectableRow(m)),
                const SizedBox(height: 12),
              ],
              if (e.labTests.isNotEmpty) ...[
                _buildSectionTitle('Lab Tests', Icons.biotech),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: e.labTests
                      .map((t) => Chip(
                            label: Text(t, style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.orange.shade50,
                            side: BorderSide(color: Colors.orange.shade300),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
              ],
              if (onRepeatLast != null) ...[
                const Divider(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => onRepeatLast!(entry.raw),
                    icon: const Icon(Icons.repeat, size: 18),
                    label: const Text('Repeat This Prescription'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: _teal),
      const SizedBox(width: 6),
      Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _teal)),
    ]);
  }

  Widget _buildVitalChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _buildMedicineRow(_MedEntry med) {
    final parts = <String>[];
    if (med.dosage.isNotEmpty) parts.add(med.dosage);
    if (med.frequency.isNotEmpty) parts.add(med.frequency);
    if (med.timing.isNotEmpty) parts.add(med.timing);
    if (med.meal.isNotEmpty) parts.add(med.meal);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _teal.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _teal.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(6)),
            child: Text(med.abbrev.isNotEmpty ? med.abbrev : 'Med',
                style: const TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(med.name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
          ),
        ]),
        if (parts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(parts.join(' • '),
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ]),
    );
  }

  Widget _buildInjectableRow(_MedEntry med) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
          child: const Icon(Icons.vaccines, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(med.name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
            Text('Quantity: ${med.quantity}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryEntry {
  final String serial;
  final DateTime date;
  final String diagnosis;
  final String complaint;
  final String doctorName;
  final List<_MedEntry> medicines;
  final List<String> labTests;
  final Map<String, dynamic> vitals;
  final Map<String, dynamic> raw;
  final String source;

  const _HistoryEntry({
    required this.serial,
    required this.date,
    required this.diagnosis,
    required this.complaint,
    required this.doctorName,
    required this.medicines,
    required this.labTests,
    required this.vitals,
    required this.raw,
    required this.source,
  });

  static _HistoryEntry? fromMap(Map<String, dynamic> data, {required String source}) {
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
        try { date = DateTime.parse(rawTs); } catch (_) {}
      }
    }

    final meds = <_MedEntry>[];
    final rawMeds = data['prescriptions'];
    if (rawMeds is List) {
      for (final m in rawMeds) {
        if (m is! Map) continue;
        meds.add(_MedEntry(
          name: m['name']?.toString() ?? m['displayName']?.toString() ?? '',
          type: m['type']?.toString() ?? '',
          timing: m['timing']?.toString() ?? '',
          meal: m['meal']?.toString() ?? '',
          dosage: m['dosage']?.toString() ?? m['dose']?.toString() ?? '',
          quantity: (m['quantity'] as num?)?.toInt() ?? 1,
          frequency: m['frequency']?.toString() ?? '',
        ));
      }
    }

    final labs = <String>[];
    final rawLabs = data['labResults'];
    if (rawLabs is List) {
      for (final l in rawLabs) {
        final name = (l is Map ? (l['name'] ?? l['testName']) : l)?.toString().trim() ?? '';
        if (name.isNotEmpty) labs.add(name);
      }
    }

    final vitals = (data['vitals'] as Map?)?.cast<String, dynamic>() ?? {};

    return _HistoryEntry(
      serial: serial,
      date: date,
      diagnosis: data['diagnosis']?.toString() ?? '',
      complaint: (data['complaint'] ?? data['condition'] ?? '').toString(),
      doctorName: (data['doctorName'] ?? data['prescribedBy'] ?? '').toString(),
      medicines: meds,
      labTests: labs,
      vitals: vitals,
      raw: data,
      source: source,
    );
  }

  Color get sourceColor {
    if (source.contains('Hive')) return Colors.blue;
    if (source.contains('Prescriptions')) return Colors.green;
    return Colors.grey;
  }

  IconData get sourceIcon {
    if (source.contains('Hive')) return Icons.storage;
    if (source.contains('Prescriptions')) return Icons.description;
    return Icons.cloud;
  }
}

class _MedEntry {
  final String name, type, timing, meal, dosage, frequency;
  final int quantity;

  const _MedEntry({
    required this.name,
    required this.type,
    required this.timing,
    required this.meal,
    required this.dosage,
    required this.quantity,
    required this.frequency,
  });

  bool get isInjectable {
    final t = type.toLowerCase();
    return t.contains('injection') ||
        t.contains('drip') ||
        t.contains('syringe') ||
        t.contains('nebulization');
  }

  String get abbrev {
    final t = type.toLowerCase();
    if (t.contains('syrup')) return 'Syrup';
    if (t.contains('injection')) return 'Inj.';
    if (t.contains('tablet')) return 'Tab.';
    if (t.contains('capsule')) return 'Cap.';
    if (t.contains('drip')) return 'Drip';
    return '';
  }

  String get displayName =>
      abbrev.isNotEmpty && !name.toLowerCase().startsWith(abbrev.toLowerCase())
          ? '$abbrev $name'
          : name;
}