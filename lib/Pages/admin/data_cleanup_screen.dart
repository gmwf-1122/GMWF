import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/colors.dart';

class DataCleanupScreen extends StatefulWidget {
  const DataCleanupScreen({super.key});

  @override
  State<DataCleanupScreen> createState() => _DataCleanupScreenState();
}

class _DataCleanupScreenState extends State<DataCleanupScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  bool _isProcessing = false;
  List<String> _logs = [];
  double _progress = 0.0;
  String _currentBranch = "";

  // ─── Logging ────────────────────────────────────────────────────────────────

  void _log(String msg) {
    if (mounted) {
      setState(() => _logs.insert(0, msg));
    }
  }

  // ─── Entry point ────────────────────────────────────────────────────────────

  Future<void> _startCleanup() async {
    setState(() {
      _isProcessing = true;
      _logs = ["🚀 Starting global scan across all patients..."];
      _progress = 0.0;
    });

    try {
      // 1. Fetch ALL patients from EVERYWHERE (collectionGroup)
      _log("📦 Fetching all patient records (global scan)...");
      
      List<DocumentSnapshot> allDocs = [];

      try {
        final querySnap = await _fs.collectionGroup('patients').get();
        allDocs = querySnap.docs;
      } catch (e) {
        if (e.toString().contains('failed-precondition')) {
          _log("⚠️ Global patients index missing. Falling back to branch-by-branch scan...");
          // Manual fallback: Iterate branches
          final branches = await _fs.collection('branches').get();
          for (var b in branches.docs) {
            final pSnap = await b.reference.collection('patients').get();
            allDocs.addAll(pSnap.docs);
          }
          // Also check top-level if it exists
          try {
            final tSnap = await _fs.collection('patients').get();
            allDocs.addAll(tSnap.docs);
          } catch (_) {}
        } else {
          rethrow;
        }
      }

      _log("🔎 Found ${allDocs.length} total records across all collections.");

      // 2. Group by (branchId + canonicalKey)
      final Map<String, List<DocumentSnapshot>> groups = {};
      for (final doc in allDocs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final branchId = data['branchId']?.toString() ?? 'unknown';
        final key = _canonicalKey(data, doc.id);
        final compositeKey = "${branchId}_$key";
        groups.putIfAbsent(compositeKey, () => []).add(doc);
      }

      // 3. Identify what needs fixing
      // - Multiple docs for same key -> MERGE
      // - Single doc with wrong ID -> FIX (MOVE)
      // - Single doc with correct ID -> IGNORE
      final Map<String, List<DocumentSnapshot>> toProcess = {};
      int ignoredCount = 0;

      groups.forEach((compKey, docs) {
        final data = docs.first.data() as Map<String, dynamic>;
        final canonicalId = _canonicalKey(data, docs.first.id);
        
        bool needsFix = false;
        if (docs.length > 1) {
          needsFix = true; // Duplicates
        } else {
          final doc = docs.first;
          // If ID is not canonical OR it's in the global collection (needs moving to branch)
          if (doc.id != canonicalId || doc.reference.path.startsWith('patients/')) {
            needsFix = true;
          }
        }

        if (needsFix) {
          toProcess[compKey] = docs;
        } else {
          ignoredCount++;
        }
      });

      _log("✅ Scan complete. Ignoring $ignoredCount correct records.");
      _log("🛠️  Processing ${toProcess.length} group(s) that need fixing...");

      int done = 0;
      final total = toProcess.length;

      for (final entry in toProcess.entries) {
        final docs = entry.value;
        final data = docs.first.data() as Map<String, dynamic>;
        final branchId = data['branchId']?.toString() ?? 'unknown';
        
        setState(() {
          _currentBranch = branchId;
          _progress = total > 0 ? done / total : 1.0;
        });

        await _performMerge(branchId, docs);
        done++;
      }

      setState(() {
        _progress = 1.0;
        _isProcessing = false;
      });
      _log("✨ ALL RECORDS PROCESSED SUCCESSFULLY!");
    } catch (e, st) {
      _log("❌ Fatal error: $e");
      _log("   $st");
      setState(() => _isProcessing = false);
    }
  }

  // ─── Branch processing ──────────────────────────────────────────────────────

  Future<void> _processBranch(String branchId) async {
    final patientsRef =
        _fs.collection('branches').doc(branchId).collection('patients');
    final allPatients = await patientsRef.get();

    // Group by canonical key
    final Map<String, List<DocumentSnapshot>> groups = {};
    for (final doc in allPatients.docs) {
      final key = _canonicalKey(doc.data(), doc.id);
      groups.putIfAbsent(key, () => []).add(doc);
    }

    // Only process groups that actually have duplicates
    final dupeGroups = groups.entries.where((e) => e.value.length > 1).toList();
    _log("   Found ${dupeGroups.length} duplicate group(s) in $branchId");

    for (final entry in dupeGroups) {
      await _performMerge(branchId, entry.value);
    }
  }

  // ─── Canonical key ──────────────────────────────────────────────────────────
  // Always strips CNIC to raw digits so "34201-0106660-0" == "3420101066600"
  // which is also the doc ID format that PatientRegisterPage writes.

  String _canonicalKey(Map<String, dynamic> data, String docId) {
    final cnic  = _stripCnic(data['cnic']?.toString() ?? '');
    final gCnic = _stripCnic(data['guardianCnic']?.toString() ?? '');
    final name  = _normName(data['name']?.toString() ?? '');

    if (cnic.isNotEmpty) return cnic;
    if (gCnic.isNotEmpty && name.isNotEmpty) return '${gCnic}_$name';
    // Last resort: normalise the doc ID itself
    final strippedId = _stripCnic(docId);
    return strippedId.isNotEmpty ? strippedId : docId;
  }

  /// Removes dashes, spaces, and leading/trailing whitespace from a CNIC string.
  String _stripCnic(String raw) =>
      raw.replaceAll(RegExp(r'[-\s]'), '').trim();

  String _normName(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  // ─── Score ──────────────────────────────────────────────────────────────────
  // Counts non-null, non-empty, non-"null" fields as a richness proxy.
  // Prefer the document whose ID is already the stripped (registration) form —
  // that is the authoritative record created by PatientRegisterPage.

  int _scoreDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Bonus: if the doc ID is already a pure-digit CNIC (the registration form),
    // treat it as inherently more authoritative by adding a large base score.
    final idIsStripped = RegExp(r'^\d{13}$').hasMatch(doc.id);
    final base = idIsStripped ? 1000 : 0;

    return base + data.values.where((v) {
      if (v == null) return false;
      final s = v.toString().trim();
      return s.isNotEmpty && s.toLowerCase() != 'null' && s != 'N/A';
    }).length;
  }

  // ─── Merge ──────────────────────────────────────────────────────────────────

  Future<void> _performMerge(
      String branchId, List<DocumentSnapshot> docs) async {
    if (docs.isEmpty) return;

    // 1. Elect master: registration doc (pure-digit ID) in the correct branch wins.
    //    Prefer documents that are already in branches/{branchId}/patients.
    final master = docs.reduce((a, b) {
      final scoreA = _scoreDoc(a);
      final scoreB = _scoreDoc(b);
      return scoreA >= scoreB ? a : b;
    });
    
    final masterData = master.data() as Map<String, dynamic>? ?? {};
    final canonicalId = _canonicalKey(masterData, master.id);
    final masterName = masterData['name'] ?? 'Unknown';

    // Check if master itself needs to be moved to a new document (rename)
    bool renamingMaster = master.id != canonicalId || master.reference.path.startsWith('patients/');

    _log("💡 ${renamingMaster ? 'Fixing' : 'Merging'} record for: $masterName (canonical → $canonicalId)");

    // 2. Enrich data
    final Map<String, dynamic> merged = Map<String, dynamic>.from(masterData);
    for (final doc in docs) {
      if (doc.id == master.id) continue;
      final data = doc.data() as Map<String, dynamic>? ?? {};
      data.forEach((key, incoming) {
        if (!merged.containsKey(key) || _isMissingValue(merged[key])) {
          if (!_isMissingValue(incoming)) {
            merged[key] = incoming;
          }
        }
        if (merged[key] is Timestamp && incoming is Timestamp) {
          if ((incoming).compareTo(merged[key] as Timestamp) > 0) {
            merged[key] = incoming;
          }
        }
      });
    }

    // 3. Normalise ID fields
    merged['cnic']      = canonicalId;
    merged['patientId'] = canonicalId;
    merged['branchId']  = branchId;

    // 4. Determine final reference
    final finalRef = _fs.collection('branches').doc(branchId).collection('patients').doc(canonicalId);

    // 5. Write to final doc
    await finalRef.set(merged, SetOptions(merge: true));
    if (finalRef.id != master.id || finalRef.path != master.reference.path) {
       _log("   ✅ Created/Enriched $canonicalId");
    } else {
       _log("   ✅ Master enriched in place");
    }

    // 6. Migrate references from ALL docs in group (including master if it was renamed)
    for (final doc in docs) {
      if (doc.reference.path == finalRef.path) continue; // Skip the one we just wrote
      
      _log("   🔄 Absorbing ${doc.id}...");
      
      // Update sub-collections
      await _migratePrescriptions(branchId, doc.id, canonicalId);
      await _fastUpdatePatientRefs(branchId: branchId, fromId: doc.id, toId: canonicalId);

      // Delete old doc
      await doc.reference.delete();
      _log("      🗑️ Deleted ${doc.id}");
    }
  }

  // ─── Missing-value helper ────────────────────────────────────────────────────
  // Returns true if a value should be considered absent (null, empty, "null", "N/A").

  bool _isMissingValue(dynamic v) {
    if (v == null) return true;
    final s = v.toString().trim();
    return s.isEmpty || s.toLowerCase() == 'null' || s == 'N/A';
  }

  // ─── Prescriptions migration ─────────────────────────────────────────────────
  // Path: branches/{b}/prescriptions/{patientId}/prescriptions/{visitId}

  Future<void> _migratePrescriptions(
      String branchId, String fromId, String toId) async {
    final fromCol = _fs
        .collection('branches').doc(branchId)
        .collection('prescriptions').doc(fromId)
        .collection('prescriptions');
    final toCol = _fs
        .collection('branches').doc(branchId)
        .collection('prescriptions').doc(toId)
        .collection('prescriptions');

    final snap = await fromCol.get();
    if (snap.docs.isEmpty) return;

    _log("      📋 Moving ${snap.docs.length} prescription(s)...");
    for (final p in snap.docs) {
      // Merge into destination (don't overwrite if a same-ID visit already exists)
      await toCol.doc(p.id).set(p.data(), SetOptions(merge: true));
      await p.reference.delete();
    }

    // Delete the now-empty phantom parent doc if it happens to exist
    final fromParent = _fs
        .collection('branches').doc(branchId)
        .collection('prescriptions').doc(fromId);
    final parentSnap = await fromParent.get();
    if (parentSnap.exists) await fromParent.delete();
  }

  /// Ultra-fast reference updater using collectionGroup.
  /// Scans all related sub-collections for any mention of the old ID and updates to new.
  Future<void> _fastUpdatePatientRefs({
    required String branchId,
    required String fromId,
    required String toId,
  }) async {
    final strippedFrom = _stripCnic(fromId);
    final oldValues = <String>{
      fromId,
      strippedFrom,
      _formatCnic(strippedFrom),
    }.where((s) => s.isNotEmpty).toList();

    final targets = ['zakat', 'non-zakat', 'gmwf', 'credits', 'emergency', 'dispensary'];
    final fields  = ['patientId', 'cnic', 'patientCnic'];

    for (final col in targets) {
      for (final field in fields) {
        try {
          final snap = await _fs.collectionGroup(col)
              .where(field, whereIn: oldValues)
              .get();

          for (final doc in snap.docs) {
            final docData = doc.data() as Map<String, dynamic>;
            if (docData['branchId'] != null && docData['branchId'] != branchId) continue;
            await doc.reference.update({field: toId});
            _log("         🔧 Repointed ${doc.id} in ${col}");
          }
        } catch (e) {
          if (e.toString().contains('failed-precondition')) {
            _log("      ⚠️ Missing index for $col.$field. Falling back to deep scan...");
            _log("      🔗 TIP: Check terminal/console for the index creation link to enable fast mode!");
            await _slowUpdatePatientRefsFallback(branchId, col, oldValues, toId);
          } else {
            _log("      ❌ Error updating refs in $col: $e");
          }
        }
      }
    }
  }

  /// Deep scan fallback for when collectionGroup indexes are missing.
  /// Iterates through dates and categories manually for a specific branch.
  Future<void> _slowUpdatePatientRefsFallback(
    String branchId,
    String collection,
    List<String> oldValues,
    String toId,
  ) async {
    // Only search in serials and dispensary for this branch
    for (final rootCol in ['serials', 'dispensary']) {
      final root = _fs.collection('branches').doc(branchId).collection(rootCol);
      final dateDocs = await root.get();

      for (final dateDoc in dateDocs.docs) {
        // Check date-level collection (e.g. branches/X/serials/220524/220524)
        await _patchSubCollectionFallback(dateDoc.reference.collection(dateDoc.id), oldValues, toId);
        
        // Check category collections
        const categories = ['zakat', 'non-zakat', 'gmwf', 'credits', 'emergency'];
        for (final cat in categories) {
          await _patchSubCollectionFallback(dateDoc.reference.collection(cat), oldValues, toId);
        }
      }
    }
  }

  Future<void> _patchSubCollectionFallback(
    CollectionReference sub,
    List<String> oldValues,
    String toId,
  ) async {
    final fields = ['patientId', 'cnic', 'patientCnic'];
    for (final field in fields) {
      for (final oldVal in oldValues) {
        final matches = await sub.where(field, isEqualTo: oldVal).get();
        for (final doc in matches.docs) {
          await doc.reference.update({field: toId});
          _log("         🔧 Repointed ${doc.id} (fallback)");
        }
      }
    }
  }

  /// Returns a dash-formatted CNIC string from a stripped one, e.g.
  /// "3420101066600" → "34201-0106660-0"
  /// Only used when searching for OLD formatted references left in serials/dispensary.
  String _formatCnic(String stripped) {
    final digits = stripped.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 13) {
      return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-${digits.substring(12)}';
    }
    return stripped;
  }

  // ─── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        title: const Text(
          "Data Integrity & Cleanup",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 24),
            if (_isProcessing) ...[
              Text(
                "Processing: $_currentBranch",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppColors.gray200,
                color: AppColors.primary,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 24),
            ],
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gray200),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    Color textColor = AppColors.gray800;
                    if (log.contains("❌")) textColor = Colors.red;
                    if (log.contains("✨")) textColor = Colors.green;
                    if (log.contains("🔧")) textColor = Colors.orange.shade700;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startCleanup,
              icon: const Icon(Icons.cleaning_services),
              label: Text(
                _isProcessing ? "Cleaning..." : "Start Deep Deduplication",
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              "Performs a global scan across all branches and collections. "
              "Identifies duplicates to merge and single patients with non-canonical IDs (e.g. formatted CNICs) to fix. "
              "Correctly saved single patients are ignored. "
              "Prescriptions, serials, and dispensary records are re-pointed using high-speed global queries. "
              "CNIC and ID normalization is enforced across all linked documents.",
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}