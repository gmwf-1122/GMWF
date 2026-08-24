// lib/pages/dispensary/doctor/patient_history.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/camp_session_service.dart';

// Alias kept for backwards compatibility with existing call sites
typedef PatientHistory = PatientHistoryPanel;

// ═══════════════════════════════════════════════════════════════════════════════
// HYBRID ID UTILITIES
// ═══════════════════════════════════════════════════════════════════════════════

class _IdHelper {
  static Set<String> variants(String id) {
    final clean = id.trim();
    if (clean.isEmpty) return {};
    final noHyphens  = clean.replaceAll('-', '');
    final digitsOnly = clean.replaceAll(RegExp(r'\D'), '');
    return {clean, noHyphens, if (digitsOnly.isNotEmpty) digitsOnly};
  }

  static List<String> expand(Iterable<String> ids) {
    final result = <String>{};
    for (final id in ids) {
      result.addAll(variants(id));
    }
    return result.where((s) => s.isNotEmpty).toList();
  }

  static bool matches(String candidate, Iterable<String> searchIds) {
    final c = candidate.trim();
    if (c.isEmpty) return false;
    final expandedSearch = expand(searchIds);
    for (final v in variants(c)) {
      if (expandedSearch.contains(v)) return true;
    }
    return false;
  }

  static List<List<T>> chunk<T>(List<T> list, int size) {
    final result = <List<T>>[];
    for (int i = 0; i < list.length; i += size) {
      result.add(list.sublist(i, (i + size).clamp(0, list.length)));
    }
    return result;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PATIENT IDENTITY
// A stable value object that captures everything we know about a patient.
// Two _PatientIdentity objects are equal iff they represent the same patient.
// ═══════════════════════════════════════════════════════════════════════════════

class _PatientIdentity {
  final String patientId;
  final String cnic;
  final String guardianCnic;
  final String name;       // needed to distinguish children of the same guardian
  final bool   isAdult;

  const _PatientIdentity({
    required this.patientId,
    required this.cnic,
    required this.guardianCnic,
    required this.name,
    required this.isAdult,
  });

  factory _PatientIdentity.fromMap(Map<String, dynamic>? data, String? rawCnic) {
    if (data == null && (rawCnic == null || rawCnic.isEmpty)) {
      return const _PatientIdentity(
          patientId: '', cnic: '', guardianCnic: '', name: '', isAdult: true);
    }
    final d = data ?? {};
    String pid      = (d['patientId'] ?? d['id'] ?? '').toString().trim();
    String cnic     = (d['cnic'] ?? d['patientCnic'] ?? rawCnic ?? '').toString().trim();
    String guardian = (d['guardianCnic'] ?? '').toString().trim();
    String name     = (d['name'] ?? d['patientName'] ?? '').toString().trim();
    bool isAdult    = d['isAdult'] as bool? ?? cnic.isNotEmpty;

    // Normalise — strip hyphens for comparison
    cnic     = cnic.replaceAll('-', '');
    guardian = guardian.replaceAll('-', '');

    return _PatientIdentity(
      patientId:    pid,
      cnic:         cnic,
      guardianCnic: guardian,
      name:         name.toLowerCase(),
      isAdult:      isAdult,
    );
  }

  /// A stable string key that uniquely identifies this patient.
  /// For adults   → their own CNIC (or patientId as fallback).
  /// For children → guardianCnic + normalised name (siblings have different names).
  String get key {
    if (cnic.isNotEmpty && isAdult) return cnic;
    if (!isAdult && guardianCnic.isNotEmpty && name.isNotEmpty) {
      return '${guardianCnic}_child_${name.replaceAll(RegExp(r'[^a-z0-9]'), '')}';
    }
    if (patientId.isNotEmpty) return patientId;
    if (cnic.isNotEmpty) return cnic;
    return '';
  }

  bool get isEmpty => key.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is _PatientIdentity && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;

  /// Returns identifiers to use when querying Firestore / Hive.
  /// For adults   → own CNIC variants.
  /// For children → guardian CNIC variants only (Firestore docs use guardianCnic).
  /// Name-based filtering happens in Dart after fetching.
  List<String> get searchIds {
    final ids = <String>{};
    if (cnic.isNotEmpty)        ids.addAll(_IdHelper.variants(cnic));
    if (patientId.isNotEmpty)   ids.addAll(_IdHelper.variants(patientId));
    if (guardianCnic.isNotEmpty) ids.addAll(_IdHelper.variants(guardianCnic));
    return ids.where((s) => s.isNotEmpty).toList();
  }

  /// For child patients: whether a doc's patientName matches this child.
  bool docBelongsToThisChild(Map<String, dynamic> doc) {
    if (isAdult) return true; // adults — no name check needed
    if (name.isEmpty) return true; // no name stored — can't filter, show all
    final docName = (doc['patientName'] ?? doc['name'] ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final myName = name.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return docName == myName || docName.contains(myName) || myName.contains(docName);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class PatientHistoryPanel extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? patientData;
  final String? patientCnic;
  final void Function(Map<String, dynamic>)? onRepeatLast;
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

  List<_HistoryEntry> _entries   = [];
  bool                _isLoading = false;

  // FIX-4: cancellation token — incremented every time a new load starts.
  // The async load captures the token at start; if the token changes by the
  // time it wants to call setState, it knows it has been superseded and bails.
  int _loadToken = 0;

  // The identity of the patient whose data is currently displayed (or loading).
  _PatientIdentity _currentIdentity = const _PatientIdentity(
      patientId: '', cnic: '', guardianCnic: '', name: '', isAdult: true);

  @override
  void initState() {
    super.initState();
    _kickOffLoad();
  }

  @override
  void didUpdateWidget(covariant PatientHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // FIX-2: compare full identity objects, not just a single ID string
    final newIdentity = _PatientIdentity.fromMap(widget.patientData, widget.patientCnic);
    if (newIdentity != _currentIdentity) {
      _kickOffLoad();
    }
  }

  /// FIX-1: Synchronously clears stale data BEFORE starting the async load.
  void _kickOffLoad() {
    final identity = _PatientIdentity.fromMap(widget.patientData, widget.patientCnic);

    // Immediately wipe the old patient's data so it is never shown for the
    // new patient, even for a single frame.
    setState(() {
      _currentIdentity = identity;
      _entries         = [];
      _isLoading       = !identity.isEmpty;
    });

    if (!identity.isEmpty) {
      _loadHistory(identity);
    }
  }

  Future<void> _loadHistory(_PatientIdentity identity) async {
    // FIX-4: grab a token; if it changes we've been superseded
    final token = ++_loadToken;

    debugPrint('[PatientHistory] Loading history for: ${identity.key}');

    // Optionally enrich identity from Firestore patient doc
    Map<String, dynamic>? firestorePatient;
    for (final variant in _IdHelper.variants(
        identity.patientId.isNotEmpty ? identity.patientId : identity.cnic)) {
      if (variant.isEmpty) continue;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId.toLowerCase())
            .collection('patients')
            .doc(variant)
            .get()
            .timeout(const Duration(seconds: 8));
        if (doc.exists) { firestorePatient = doc.data(); break; }
      } catch (_) {}
    }

    // Build enriched identity with any extra IDs from Firestore
    final enrichedData = {
      ...?widget.patientData,
      ...?firestorePatient,
    };
    final enriched = _PatientIdentity.fromMap(enrichedData, widget.patientCnic);

    if (_loadToken != token) return; // superseded

    final List<_HistoryEntry> found    = [];
    final Set<String>         seen     = {};
    final searchIds                    = enriched.searchIds;

    debugPrint('[PatientHistory] Search IDs: $searchIds');

    // ── Step 1: Hive local_prescriptions ─────────────────────────────────────
    try {
      final box = Hive.box(LocalStorageService.prescriptionsBox);
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);

        bool belongs = false;
        for (final field in ['patientId', 'cnic', 'patientCnic', 'guardianCnic']) {
          final v = data[field]?.toString().trim() ?? '';
          if (v.isNotEmpty && _IdHelper.matches(v, searchIds)) {
            belongs = true;
            break;
          }
        }
        if (!belongs) continue;
        // FIX-3: for children, require name match to avoid sibling bleed
        if (!enriched.docBelongsToThisChild(data)) continue;

        final entry = _HistoryEntry.fromMap(data, source: 'Hive Cache');
        if (entry != null && seen.add(entry.serial)) found.add(entry);
      }
    } catch (e) {
      debugPrint('[PatientHistory] Hive scan error: $e');
    }

    if (_loadToken != token) return;

    // ── Step 2: Firestore prescriptions/{id}/prescriptions ───────────────────
    for (final id in searchIds) {
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
            .timeout(const Duration(seconds: 12));

        debugPrint('[PatientHistory] Prescriptions[$id]: ${query.docs.length} docs');

        for (final doc in query.docs) {
          if (_loadToken != token) return;
          final data = Map<String, dynamic>.from(doc.data());
          data['serial'] ??= doc.id;
          // FIX-3: name check for children
          if (!enriched.docBelongsToThisChild(data)) continue;

          final entry = _HistoryEntry.fromMap(data, source: 'Prescriptions');
          if (entry != null && seen.add(entry.serial)) {
            found.add(entry);
            try {
              Hive.box(LocalStorageService.reportsCacheBox)
                  .put('legacy_${id}_${entry.serial}', data);
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[PatientHistory] Prescriptions[$id] error: $e');
      }
    }

    if (_loadToken != token) return;

    // ── Step 3: Firestore dispensary ──────────────────────────────────────────
    try {
      final dispensaryRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId.toLowerCase())
          .collection('dispensary');

      final dateDocs = await dispensaryRef
          .get()
          .timeout(const Duration(seconds: 12));

      final chunks = _IdHelper.chunk(searchIds, 10);

      for (final dateDoc in dateDocs.docs) {
        if (_loadToken != token) return;
        final dateKey = dateDoc.id;

        for (final chunk in chunks) {
          for (final field in ['patientId', 'patientCnic', 'cnic']) {
            try {
              final q = await dispensaryRef
                  .doc(dateKey)
                  .collection(dateKey)
                  .where(field, whereIn: chunk)
                  .get()
                  .timeout(const Duration(seconds: 12));

              _addDispensaryDocs(q.docs, found, seen, enriched);
            } catch (e) {
              debugPrint('[PatientHistory] Dispensary $dateKey.$field error: $e');
            }
            if (_loadToken != token) return;
          }
        }
      }
    } catch (e) {
      debugPrint('[PatientHistory] Dispensary block error: $e');
    }

    if (_loadToken != token) return;

    found.sort((a, b) => b.date.compareTo(a.date));
    debugPrint('[PatientHistory] Total entries: ${found.length}');

    if (mounted && _loadToken == token) {
      setState(() {
        _entries   = found;
        _isLoading = false;
      });
    }
  }

  void _addDispensaryDocs(
    List<QueryDocumentSnapshot> docs,
    List<_HistoryEntry> found,
    Set<String> seen,
    _PatientIdentity identity,
  ) {
    for (final doc in docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);

      if (data['prescription'] is Map) {
        final nested = Map<String, dynamic>.from(data['prescription'] as Map);
        for (final key in nested.keys) {
          data.putIfAbsent(key, () => nested[key]);
        }
      }

      data['serial'] ??= data['id'] ?? doc.id;

      // FIX-3: name check for children
      if (!identity.docBelongsToThisChild(data)) continue;

      final entry = _HistoryEntry.fromMap(data, source: 'Dispensary');
      if (entry != null && seen.add(entry.serial)) {
        found.add(entry);
        try {
          Hive.box(LocalStorageService.reportsCacheBox)
              .put('disp_${entry.serial}', data);
        } catch (_) {}
      }
    }
  }

  void _reload() => _kickOffLoad();

  @override
  Widget build(BuildContext context) {
    if (_currentIdentity.isEmpty) {
      return const Center(
        child: Text('Select a patient to view history',
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }

    final patientName = widget.patientData?['name']?.toString() ??
        widget.patientCnic ?? 'Patient';

    if (widget.compactMode) {
      return _buildCompactLatestVisit(patientName);
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
                          fontSize: 16, fontWeight: FontWeight.bold, color: _teal)),
                  Text(_currentIdentity.key,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: _teal, size: 20),
              tooltip: 'Reload history',
              onPressed: _isLoading ? null : _reload,
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
                        isLatest: i == 0,
                        onRepeatLast: null,
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildCompactLatestVisit(String patientName) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.history_edu_rounded, color: _teal, size: 17),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Last Visit',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: _teal)),
            ),
            if (!_isLoading && _entries.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _teal.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${_entries.length} visit${_entries.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: _teal),
                ),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _isLoading ? null : _reload,
              child: const Icon(Icons.refresh_rounded, color: _teal, size: 17),
            ),
          ]),
          const SizedBox(height: 8),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
              ),
            )
          else if (_entries.isEmpty)
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
// DEDICATED FULL-PAGE HISTORY
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

  List<_HistoryEntry> _entries   = [];
  bool                _isLoading = true;
  int                 _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token    = ++_loadToken;
    final identity = _PatientIdentity.fromMap(widget.patientData, null);

    if (mounted) setState(() { _entries = []; _isLoading = true; });

    if (identity.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Enrich from Firestore
    Map<String, dynamic>? fsPatient;
    for (final variant in _IdHelper.variants(
        identity.patientId.isNotEmpty ? identity.patientId : identity.cnic)) {
      if (variant.isEmpty) continue;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId.toLowerCase())
            .collection('patients')
            .doc(variant)
            .get()
            .timeout(const Duration(seconds: 8));
        if (doc.exists) { fsPatient = doc.data(); break; }
      } catch (_) {}
    }

    final enriched    = _PatientIdentity.fromMap({...widget.patientData, ...?fsPatient}, null);
    final searchIds   = enriched.searchIds;
    final List<_HistoryEntry> found = [];
    final Set<String> seen = {};

    // Hive
    try {
      final box = Hive.box(LocalStorageService.prescriptionsBox);
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        bool belongs = false;
        for (final field in ['patientId', 'cnic', 'patientCnic', 'guardianCnic']) {
          final v = data[field]?.toString().trim() ?? '';
          if (v.isNotEmpty && _IdHelper.matches(v, searchIds)) { belongs = true; break; }
        }
        if (!belongs || !enriched.docBelongsToThisChild(data)) continue;
        final entry = _HistoryEntry.fromMap(data, source: 'Hive Cache');
        if (entry != null && seen.add(entry.serial)) found.add(entry);
      }
    } catch (_) {}

    if (_loadToken != token) return;

    // Legacy prescriptions path
    for (final id in searchIds) {
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
            .timeout(const Duration(seconds: 12));
        for (final doc in query.docs) {
          if (_loadToken != token) return;
          final data = Map<String, dynamic>.from(doc.data());
          data['serial'] ??= doc.id;
          if (!enriched.docBelongsToThisChild(data)) continue;
          final entry = _HistoryEntry.fromMap(data, source: 'Prescriptions');
          if (entry != null && seen.add(entry.serial)) {
            found.add(entry);
            try { Hive.box(LocalStorageService.reportsCacheBox).put('legacy_${id}_${entry.serial}', data); } catch (_) {}
          }
        }
      } catch (e) { debugPrint('[PatientHistoryPage] $id error: $e'); }
    }

    if (_loadToken != token) return;

    // Dispensary
    try {
      final dispensaryRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId.toLowerCase())
          .collection('dispensary');
      final dateDocs = await dispensaryRef.get().timeout(const Duration(seconds: 12));
      final chunks   = _IdHelper.chunk(searchIds, 10);

      for (final dateDoc in dateDocs.docs) {
        if (_loadToken != token) return;
        final dateKey = dateDoc.id;
        for (final chunk in chunks) {
          for (final field in ['patientId', 'patientCnic', 'cnic']) {
            try {
              final q = await dispensaryRef
                  .doc(dateKey).collection(dateKey)
                  .where(field, whereIn: chunk)
                  .get()
                  .timeout(const Duration(seconds: 12));
              _addDispensaryDocs(q.docs, found, seen, enriched);
            } catch (e) { debugPrint('[PatientHistoryPage] $dateKey.$field: $e'); }
            if (_loadToken != token) return;
          }
        }
      }
    } catch (e) { debugPrint('[PatientHistoryPage] Dispensary: $e'); }

    if (_loadToken != token) return;

    found.sort((a, b) => b.date.compareTo(a.date));
    if (mounted && _loadToken == token) setState(() { _entries = found; _isLoading = false; });
  }

  void _addDispensaryDocs(
    List<QueryDocumentSnapshot> docs,
    List<_HistoryEntry> found,
    Set<String> seen,
    _PatientIdentity identity,
  ) {
    for (final doc in docs) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      if (data['prescription'] is Map) {
        final nested = Map<String, dynamic>.from(data['prescription'] as Map);
        for (final key in nested.keys) {
          data.putIfAbsent(key, () => nested[key]);
        }
      }
      data['serial'] ??= data['id'] ?? doc.id;
      if (!identity.docBelongsToThisChild(data)) continue;
      final entry = _HistoryEntry.fromMap(data, source: 'Dispensary');
      if (entry != null && seen.add(entry.serial)) {
        found.add(entry);
        try { Hive.box(LocalStorageService.reportsCacheBox).put('disp_${entry.serial}', data); } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.patientData['name']?.toString() ?? 'Patient';
    final id   = _PatientIdentity.fromMap(widget.patientData, null).key;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(id, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _entries.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 14),
                  Text('No visit history found for $name',
                      style: TextStyle(color: Colors.grey[500], fontSize: 15),
                      textAlign: TextAlign.center),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) => _HistoryCard(
                    entry: _entries[i],
                    isLatest: i == 0,
                    onRepeatLast: (i == 0 && widget.onRepeatLast != null)
                        ? (raw) { widget.onRepeatLast!(raw); Navigator.pop(context); }
                        : null,
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT LATEST CARD  (unchanged UI, just wired to fixed data)
// ═══════════════════════════════════════════════════════════════════════════════

class _CompactLatestCard extends StatelessWidget {
  final _HistoryEntry entry;
  final void Function(Map<String, dynamic>)? onRepeat;
  static const Color _teal = Color(0xFF00695C);

  const _CompactLatestCard({required this.entry, this.onRepeat});

  bool _getIsDark(BuildContext context) {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final dark = Hive.box('app_settings').get('is_dark_mode');
        if (dark != null) return dark == true;
      }
    } catch (_) {}
    return Theme.of(context).brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _getIsDark(context);
    final e       = entry;
    final dateStr = DateFormat('d MMM yyyy  •  hh:mm a').format(e.date);
    final oralMeds     = e.medicines.where((m) => !m.isInjectable).toList();
    final injectables  = e.medicines.where((m) => m.isInjectable).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : _teal.withValues(alpha: 0.25), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.07), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            color: _teal,
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Colors.white70, size: 13),
                  const SizedBox(width: 5),
                  Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
              if (e.doctorName.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_outline_rounded, color: Colors.white60, size: 13),
                    const SizedBox(width: 4),
                    Text(e.doctorName, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              if (e.campName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.white, size: 11),
                      const SizedBox(width: 3),
                      Text(e.campName, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                child: Text('${e.days} Days', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              if (e.isVitalsOnly) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.amber.shade800, borderRadius: BorderRadius.circular(4)),
                  child: const Text('🩺 Vitals Only', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (e.complaint.isNotEmpty) ...[
              _label('Condition', isDark), const SizedBox(height: 3),
              Text(e.complaint,
                  style: TextStyle(fontSize: 12.5, color: isDark ? const Color(0xFFE2E8F0) : Colors.black87),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
            ],
            if (e.diagnosis.isNotEmpty) ...[
              _label('Diagnosis', isDark), const SizedBox(height: 3),
              Text(e.diagnosis,
                  style: TextStyle(fontSize: 12.5, color: isDark ? const Color(0xFFE2E8F0) : Colors.black87),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
            ],
            if (e.vitals.isNotEmpty) ...[
              _label('Vitals', isDark), const SizedBox(height: 4),
              _buildCompactVitalsDisplay(e.vitals, isDark),
              const SizedBox(height: 8),
            ],
            if (oralMeds.isNotEmpty) ...[
              _label('Medicines', isDark), const SizedBox(height: 4),
              ...oralMeds.map((m) => _medTile(m, isInj: false, isDark: isDark)),
              const SizedBox(height: 4),
            ],
            if (injectables.isNotEmpty) ...[
              _label('Injectables', isDark), const SizedBox(height: 4),
              ...injectables.map((m) => _medTile(m, isInj: true, isDark: isDark)),
              const SizedBox(height: 4),
            ],
            if (e.labTests.isNotEmpty) ...[
              _label(e.raw['isPhysiotherapist'] == true ? 'Physiotherapies' : 'Lab Tests', isDark), const SizedBox(height: 4),
              Wrap(spacing: 5, runSpacing: 5,
                  children: e.labTests.map((t) => _labChip(t, isDark)).toList()),
              const SizedBox(height: 4),
            ],
            if (onRepeat != null) ...[
              const SizedBox(height: 6), Divider(height: 1, color: isDark ? const Color(0xFF334155) : Colors.grey.shade200), const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => onRepeat!(e.raw),
                  icon: const Icon(Icons.repeat_rounded, size: 15),
                  label: const Text('Repeat This Prescription',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10), elevation: 0,
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

  Widget _buildCompactVitalsDisplay(Map<String, dynamic> vitals, bool isDark) {
    final recVitals = (vitals['receptionistVitals'] is Map)
        ? Map<String, dynamic>.from(vitals['receptionistVitals'])
        : <String, dynamic>{};
    final docVitals = (vitals['doctorVitals'] is Map)
        ? Map<String, dynamic>.from(vitals['doctorVitals'])
        : <String, dynamic>{};

    final hasDocEdit = docVitals.isNotEmpty;

    if (hasDocEdit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('REC VITALS (${recVitals['addedBy'] ?? 'Receptionist'}):',
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: isDark ? Colors.blue.shade300 : Colors.blue.shade800, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 3),
          Wrap(spacing: 5, runSpacing: 4, children: [
            if (recVitals['bp'] != null && recVitals['bp'] != 'N/A') _vitalChip('BP', recVitals['bp'].toString(), Colors.blue.shade700),
            if (recVitals['temp'] != null && recVitals['temp'] != 'N/A') _vitalChip('Temp', '${recVitals['temp']}°C', Colors.orange.shade700),
            if (recVitals['sugar'] != null && recVitals['sugar'].toString().isNotEmpty) _vitalChip('Sugar', recVitals['sugar'].toString(), Colors.purple),
            if (recVitals['weight'] != null && recVitals['weight'] != 'N/A') _vitalChip('Wt', '${recVitals['weight']} kg', Colors.teal),
          ]),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('DOC VITALS EDITED (${docVitals['updatedBy'] ?? 'Doctor'}):',
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: isDark ? Colors.amber.shade300 : Colors.amber.shade900, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 3),
          Wrap(spacing: 5, runSpacing: 4, children: [
            if (docVitals['bp'] != null && docVitals['bp'] != 'N/A') _vitalChip('BP', docVitals['bp'].toString(), const Color(0xFFE91E63)),
            if (docVitals['temp'] != null && docVitals['temp'] != 'N/A') _vitalChip('Temp', '${docVitals['temp']}°C', Colors.orange.shade700),
            if (docVitals['sugar'] != null && docVitals['sugar'].toString().isNotEmpty) _vitalChip('Sugar', docVitals['sugar'].toString(), Colors.purple),
            if (docVitals['weight'] != null && docVitals['weight'] != 'N/A') _vitalChip('Wt', '${docVitals['weight']} kg', Colors.teal),
          ]),
        ],
      );
    }

    return Wrap(spacing: 5, runSpacing: 5, children: [
      if (vitals['bp'] != null && vitals['bp'] != 'N/A') _vitalChip('BP', vitals['bp'].toString(), const Color(0xFFE91E63)),
      if (vitals['temp'] != null && vitals['temp'] != 'N/A') _vitalChip('Temp', '${vitals['temp']}${vitals['tempUnit'] ?? ''}', Colors.orange.shade700),
      if (vitals['sugar'] != null && vitals['sugar'].toString().isNotEmpty) _vitalChip('Sugar', vitals['sugar'].toString(), Colors.purple),
      if (vitals['weight'] != null && vitals['weight'] != 'N/A') _vitalChip('Wt', '${vitals['weight']} kg', Colors.teal),
    ]);
  }

  Widget _label(String text, bool isDark) => Text(text.toUpperCase(),
      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFF2DD4BF) : _teal, letterSpacing: 0.8));

  Widget _vitalChip(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: '$label  ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.85))),
        TextSpan(text: value,     style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,  color: color)),
      ])));

  Widget _labChip(String text, bool isDark) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF451A03) : Colors.orange.shade50, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF9A3412) : Colors.orange.shade300),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFFDBA74) : Colors.orange.shade800, fontWeight: FontWeight.w600)));

  Widget _medTile(_MedEntry med, {required bool isInj, required bool isDark}) {
    final parts     = <String>[];
    if (med.dosage.isNotEmpty)    parts.add(med.dosage);
    if (med.frequency.isNotEmpty) parts.add(med.frequency);
    if (med.timing.isNotEmpty)    parts.add(med.timing);
    if (!isInj && med.meal.isNotEmpty) parts.add(med.meal);

    final badgeColor = isInj ? const Color(0xFF1565C0) : _teal;
    final badge = isInj ? 'Inj' :
        (med.abbrev.length > 3 ? med.abbrev.substring(0, 3) :
         med.abbrev.isNotEmpty ? med.abbrev : 'Med');

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isInj
            ? (isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.25) : const Color(0xFFE3F2FD))
            : (isDark ? const Color(0xFF1E293B) : _teal.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: isDark
                ? const Color(0xFF334155)
                : (isInj ? const Color(0xFF90CAF9) : _teal.withValues(alpha: 0.15))),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(5)),
          child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(med.name,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (parts.isNotEmpty)
            Text(parts.join(' · '),
                style: TextStyle(fontSize: 10.5, color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600]),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FULL HISTORY CARD  (unchanged UI)
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryCard extends StatelessWidget {
  final _HistoryEntry entry;
  final bool isLatest;
  final void Function(Map<String, dynamic>)? onRepeatLast;

  const _HistoryCard({required this.entry, this.isLatest = false, this.onRepeatLast});

  static const Color _teal = Color(0xFF00695C);

  @override
  Widget build(BuildContext context) {
    final e        = entry;
    final dateStr  = DateFormat('d MMM yyyy').format(e.date);
    final timeStr  = DateFormat('hh:mm a').format(e.date);
    final oralMeds    = e.medicines.where((m) => !m.isInjectable).toList();
    final injectables = e.medicines.where((m) => m.isInjectable).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isLatest ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _teal,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.white, size: 14),
                    Text(dateStr, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 2),
                    const Icon(Icons.access_time, color: Colors.white70, size: 14),
                    Text(timeStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                      child: Text('${e.days} Days', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Serial: ${e.serial}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
              if (isLatest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: const Text('LATEST', style: TextStyle(color: _teal, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: e.sourceColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white54),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(e.sourceIcon, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(e.source, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (e.isVitalsOnly) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monitor_heart_outlined, color: Colors.orange.shade900, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Vitals Inspection Only Visit',
                      style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
            if (e.doctorName.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.person, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(e.doctorName,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700])),
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
              _buildFullVitalsDisplay(e.vitals),
              const SizedBox(height: 12),
            ],
            if (oralMeds.isNotEmpty) ...[
              _buildSectionTitle('Medicines', Icons.medication),
              const SizedBox(height: 8),
              ...oralMeds.map(_buildMedicineRow),
              const SizedBox(height: 12),
            ],
            if (injectables.isNotEmpty) ...[
              _buildSectionTitle('Injectables', Icons.vaccines_outlined),
              const SizedBox(height: 8),
              ...injectables.map(_buildInjectableRow),
              const SizedBox(height: 12),
            ],
            if (e.labTests.isNotEmpty) ...[
              _buildSectionTitle(
                  e.raw['isPhysiotherapist'] == true ? 'Physiotherapies' : 'Lab Tests',
                  e.raw['isPhysiotherapist'] == true ? Icons.accessibility : Icons.biotech),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6,
                  children: e.labTests.map((t) => Chip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    backgroundColor: Colors.orange.shade50,
                    side: BorderSide(color: Colors.orange.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  )).toList()),
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
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildSectionTitle(String title, IconData icon) => Row(children: [
        Icon(icon, size: 16, color: _teal),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _teal)),
      ]);

  Widget _buildVitalChip(String label, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        Text(value,      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,  color: color)),
      ]));

  Widget _buildMedicineRow(_MedEntry med) {
    final parts = <String>[];
    if (med.dosage.isNotEmpty)    parts.add(med.dosage);
    if (med.frequency.isNotEmpty) parts.add(med.frequency);
    if (med.timing.isNotEmpty)    parts.add(med.timing);
    if (med.meal.isNotEmpty)      parts.add(med.meal);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _teal.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(6)),
            child: Text(med.abbrev.isNotEmpty ? med.abbrev : 'Med',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(med.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87))),
        ]),
        if (parts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(parts.join(' • '), style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ]),
    );
  }

  Widget _buildFullVitalsDisplay(Map<String, dynamic> vitals) {
    final recVitals = (vitals['receptionistVitals'] is Map)
        ? Map<String, dynamic>.from(vitals['receptionistVitals'])
        : <String, dynamic>{};
    final docVitals = (vitals['doctorVitals'] is Map)
        ? Map<String, dynamic>.from(vitals['doctorVitals'])
        : <String, dynamic>{};

    final hasDocEdit = docVitals.isNotEmpty;

    if (hasDocEdit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.support_agent, size: 13, color: Colors.blue),
                const SizedBox(width: 4),
                Text('Added by Receptionist (${recVitals['addedBy'] ?? 'Receptionist'})',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (recVitals['bp'] != null && recVitals['bp'] != 'N/A') _buildVitalChip('BP', recVitals['bp'].toString(), Colors.blue),
            if (recVitals['temp'] != null && recVitals['temp'] != 'N/A') _buildVitalChip('Temp', '${recVitals['temp']}°C', Colors.orange),
            if (recVitals['sugar'] != null && recVitals['sugar'].toString().isNotEmpty) _buildVitalChip('Sugar', recVitals['sugar'].toString(), Colors.purple),
            if (recVitals['weight'] != null && recVitals['weight'] != 'N/A') _buildVitalChip('Weight', '${recVitals['weight']} kg', Colors.teal),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.medical_services, size: 13, color: Colors.amber),
                const SizedBox(width: 4),
                Text('Updated by Doctor (${docVitals['updatedBy'] ?? 'Doctor'})',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (docVitals['bp'] != null && docVitals['bp'] != 'N/A') _buildVitalChip('BP', docVitals['bp'].toString(), Colors.pink),
            if (docVitals['temp'] != null && docVitals['temp'] != 'N/A') _buildVitalChip('Temp', '${docVitals['temp']}°C', Colors.orange),
            if (docVitals['sugar'] != null && docVitals['sugar'].toString().isNotEmpty) _buildVitalChip('Sugar', docVitals['sugar'].toString(), Colors.purple),
            if (docVitals['weight'] != null && docVitals['weight'] != 'N/A') _buildVitalChip('Weight', '${docVitals['weight']} kg', Colors.teal),
          ]),
        ],
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (vitals['bp'] != null && vitals['bp'] != 'N/A') _buildVitalChip('BP', vitals['bp'].toString(), Colors.pink),
      if (vitals['temp'] != null && vitals['temp'] != 'N/A') _buildVitalChip('Temp', '${vitals['temp']} ${vitals['tempUnit'] ?? ''}', Colors.orange),
      if (vitals['sugar'] != null && vitals['sugar'].toString().isNotEmpty) _buildVitalChip('Sugar', vitals['sugar'].toString(), Colors.purple),
      if (vitals['weight'] != null && vitals['weight'] != 'N/A') _buildVitalChip('Weight', '${vitals['weight']} kg', Colors.teal),
    ]);
  }

  Widget _buildInjectableRow(_MedEntry med) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
          child: const Icon(Icons.vaccines, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(med.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
          Text('Quantity: ${med.quantity}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ])),
      ]));
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS  (unchanged)
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryEntry {
  final String serial, diagnosis, complaint, doctorName, source, campId, campName;
  final DateTime date;
  final List<_MedEntry> medicines;
  final List<String> labTests;
  final Map<String, dynamic> vitals, raw;
  final int days;
  final bool isVitalsOnly;

  const _HistoryEntry({
    required this.serial, required this.date, required this.diagnosis,
    required this.complaint, required this.doctorName, required this.medicines,
    required this.labTests, required this.vitals, required this.raw,
    required this.source, required this.days,
    required this.campId, required this.campName,
    required this.isVitalsOnly,
  });

  static _HistoryEntry? fromMap(Map<String, dynamic> data, {required String source}) {
    final serial = (data['serial'] ?? data['id'] ?? '').toString().trim();
    if (serial.isEmpty) return null;

    final cId = (data['dispensaryId'] ?? data['campId'] ?? data['branchCamp'] ?? '').toString().trim();
    final rawCampName = (data['campName'] ?? '').toString().trim();
    final cName = rawCampName.isNotEmpty
        ? rawCampName
        : (cId.isNotEmpty
            ? CampSessionService.getCampLabel(cId)
            : (data['branchName'] ?? data['branchId'] ?? '').toString().trim());

    DateTime date = DateTime(2000);
    final rawTs = data['createdAt'] ?? data['completedAt'] ?? data['dispensedAt'];
    if (rawTs is Timestamp)       { date = rawTs.toDate(); }
    else if (rawTs is String && rawTs.isNotEmpty) {
      try { date = DateTime.parse(rawTs); } catch (_) {}
    }
    if (date.year == 2000) {
      final dk = data['dateKey']?.toString() ?? data['date']?.toString() ?? '';
      if (dk.length == 6) {
        try {
          date = DateTime(2000 + int.parse(dk.substring(4, 6)),
                          int.parse(dk.substring(2, 4)),
                          int.parse(dk.substring(0, 2)));
        } catch (_) {}
      }
    }
    if (date.year == 2000) {
      try {
        final ds = serial.split('-')[0];
        if (ds.length == 6) {
          date = DateTime(2000 + int.parse(ds.substring(4, 6)),
                          int.parse(ds.substring(2, 4)),
                          int.parse(ds.substring(0, 2)));
        }
      } catch (_) {}
    }

    final meds = <_MedEntry>[];
    final rawMeds = data['prescriptions'] ?? data['medicines'];
    if (rawMeds is List) {
      for (final m in rawMeds) {
        if (m is! Map) continue;
        meds.add(_MedEntry(
          name:      m['name']?.toString() ?? m['displayName']?.toString() ?? '',
          type:      m['type']?.toString() ?? '',
          timing:    m['timing']?.toString() ?? '',
          meal:      m['meal']?.toString() ?? '',
          dosage:    m['dosage']?.toString() ?? m['dose']?.toString() ?? '',
          quantity:  (m['quantity'] is num ? (m['quantity'] as num).toInt() : int.tryParse(m['quantity']?.toString() ?? '') ?? 1),
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

    final rawVitals = data['vitals'] ?? data['receptionistVitals'];
    Map<String, dynamic> extractedVitals = rawVitals is Map
        ? Map<String, dynamic>.from(rawVitals)
        : (data['bp'] != null || data['temp'] != null || data['weight'] != null || data['sugar'] != null)
            ? {
                if (data['bp'] != null) 'bp': data['bp'],
                if (data['temp'] != null) 'temp': data['temp'],
                if (data['weight'] != null) 'weight': data['weight'],
                if (data['sugar'] != null) 'sugar': data['sugar'],
              }
            : {};

    if (extractedVitals.isEmpty) {
      try {
        if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
          final entriesBox = Hive.box(LocalStorageService.entriesBox);
          for (final k in entriesBox.keys) {
            if (k.toString().toLowerCase().contains(serial.toLowerCase())) {
              final entryMap = entriesBox.get(k);
              if (entryMap is Map) {
                final ev = entryMap['vitals'] ?? entryMap['receptionistVitals'];
                if (ev is Map && ev.isNotEmpty) {
                  extractedVitals = Map<String, dynamic>.from(ev);
                  break;
                } else if (entryMap['bp'] != null || entryMap['temp'] != null || entryMap['sugar'] != null || entryMap['weight'] != null) {
                  extractedVitals = {
                    if (entryMap['bp'] != null) 'bp': entryMap['bp'],
                    if (entryMap['temp'] != null) 'temp': entryMap['temp'],
                    if (entryMap['weight'] != null) 'weight': entryMap['weight'],
                    if (entryMap['sugar'] != null) 'sugar': entryMap['sugar'],
                  };
                  break;
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    final isVitalsOnly = data['isVitalsOnly'] == true ||
        data['vitalsOnly'] == true ||
        (data['visitReason']?.toString().toLowerCase().contains('vitals') == true);

    return _HistoryEntry(
      serial:    serial,
      date:      date,
      diagnosis: data['diagnosis']?.toString() ?? '',
      complaint: (data['complaint'] ?? data['condition'] ?? '').toString(),
      doctorName:(data['doctorName'] ?? data['prescribedBy'] ?? '').toString(),
      medicines: meds,
      labTests:  labs,
      vitals:    extractedVitals,
      raw:       data,
      source:    source,
      days:      (data['daysOfMedicine'] is num ? (data['daysOfMedicine'] as num).toInt() : int.tryParse(data['daysOfMedicine']?.toString() ?? '') ?? 1),
      campId:    cId,
      campName:  cName,
      isVitalsOnly: isVitalsOnly,
    );
  }

  Color get sourceColor {
    if (source.contains('Hive'))         return Colors.blue;
    if (source.contains('Dispensary'))   return Colors.teal;
    if (source.contains('Prescriptions')) return Colors.green;
    return Colors.grey;
  }

  IconData get sourceIcon {
    if (source.contains('Hive'))          return Icons.storage;
    if (source.contains('Dispensary'))    return Icons.local_pharmacy;
    if (source.contains('Prescriptions')) return Icons.description;
    return Icons.cloud;
  }
}

class _MedEntry {
  final String name, type, timing, meal, dosage, frequency;
  final int quantity;

  const _MedEntry({
    required this.name, required this.type, required this.timing,
    required this.meal, required this.dosage, required this.quantity,
    required this.frequency,
  });

  bool get isInjectable {
    final t = type.toLowerCase();
    return t.contains('injection') || t.contains('drip') ||
        t.contains('syringe') || t.contains('nebulization');
  }

  String get abbrev {
    final t = type.toLowerCase();
    if (t.contains('syrup'))     return 'Syrup';
    if (t.contains('injection')) return 'Inj.';
    if (t.contains('tablet'))    return 'Tab.';
    if (t.contains('capsule'))   return 'Cap.';
    if (t.contains('drip'))      return 'Drip';
    return '';
  }
}
