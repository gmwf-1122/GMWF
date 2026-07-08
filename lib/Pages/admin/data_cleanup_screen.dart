import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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

  // Cache operating dates during a cleanup run to avoid redundant Firestore gets
  final Map<String, List<String>> _serialsDatesCache = {};
  final Map<String, List<String>> _dispensaryDatesCache = {};

  // Interactive manual cleanup state
  int _activeTab = 0; // 0 = Manual Review, 1 = Auto Cleanup Logs
  bool _isScanning = false;
  bool _hasScanned = false;
  
  // Letter (A-Z, #) -> GroupKey (branchId_canonicalKey) -> List of duplicate documents
  Map<String, Map<String, List<DocumentSnapshot>>> _duplicatesByLetter = {};
  String? _selectedLetter;
  // Selected master document ID for each duplicate group key
  final Map<String, String> _electedMasterIds = {};
  // Track which groups are currently being merged
  final Set<String> _mergingGroupKeys = {};
  // Track which groups have just been successfully merged
  final Set<String> _mergedGroupKeys = {};
  // Track which groups are animating out of the list
  final Set<String> _disappearingGroupKeys = {};

  // Prescription cleanup state
  bool _isScanningPrescriptions = false;
  bool _hasScannedPrescriptions = false;
  // Key -> details of each prescription document (status, docs, metadata)
  Map<String, Map<String, dynamic>> _prescriptionMigrationItems = {};
  // Track which prescription keys are currently being processed
  final Set<String> _processingPrescriptionKeys = {};

  Future<List<String>> _getSerialsDates(String branchId) async {
    if (_serialsDatesCache.containsKey(branchId)) {
      return _serialsDatesCache[branchId]!;
    }
    try {
      final snap = await _fs.collection('branches').doc(branchId).collection('serials').get();
      final dates = snap.docs.map((d) => d.id).toList();
      _serialsDatesCache[branchId] = dates;
      return dates;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _getDispensaryDates(String branchId) async {
    if (_dispensaryDatesCache.containsKey(branchId)) {
      return _dispensaryDatesCache[branchId]!;
    }
    try {
      final snap = await _fs.collection('branches').doc(branchId).collection('dispensary').get();
      final dates = snap.docs.map((d) => d.id).toList();
      _dispensaryDatesCache[branchId] = dates;
      return dates;
    } catch (_) {
      return [];
    }
  }

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
      _serialsDatesCache.clear();
      _dispensaryDatesCache.clear();
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
    if (gCnic.isNotEmpty && name.isNotEmpty) return '${gCnic}_child_$name';
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

    // Bonus: if the doc ID is already a pure-digit CNIC or canonical child ID,
    // treat it as inherently more authoritative by adding a large base score.
    final idIsAuthoritative = RegExp(r'^\d{13}$').hasMatch(doc.id) ||
        RegExp(r'^\d{13}_child_.+$').hasMatch(doc.id);
    final base = idIsAuthoritative ? 1000 : 0;

    return base + data.values.where((v) {
      if (v == null) return false;
      final s = v.toString().trim();
      return s.isNotEmpty && s.toLowerCase() != 'null' && s != 'N/A';
    }).length;
  }

  // ─── Merge ──────────────────────────────────────────────────────────────────

  Future<void> _performMerge(
      String branchId, List<DocumentSnapshot> docs, {DocumentSnapshot? electedMaster}) async {
    if (docs.isEmpty) return;

    // 1. Elect master: registration doc (pure-digit ID) in the correct branch wins.
    //    Prefer documents that are already in branches/{branchId}/patients.
    final master = electedMaster ?? docs.reduce((a, b) {
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

    // Collect all old IDs to repoint
    final List<String> oldIds = docs
        .where((d) => d.reference.path != finalRef.path)
        .map((d) => d.id)
        .toList();

    if (oldIds.isNotEmpty) {
      _log("   🔄 Migrating prescriptions and references for ${oldIds.length} duplicate IDs...");
      
      // Migrate prescriptions for all old IDs in parallel
      await Future.wait(oldIds.map((oldId) => _migratePrescriptions(branchId, oldId, canonicalId)));

      // Repoint references for all old IDs in a single scan run
      await _fastUpdatePatientRefs(branchId: branchId, fromIds: oldIds, toId: canonicalId);

      // Delete old docs
      for (final doc in docs) {
        if (doc.reference.path == finalRef.path) continue; // Skip the master we wrote
        await doc.reference.delete();
        _log("      🗑️ Deleted duplicate doc ${doc.id}");
      }
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

  Future<void> _fastUpdatePatientRefs({
    required String branchId,
    required List<String> fromIds,
    required String toId,
  }) async {
    final Set<String> oldValuesSet = {};
    for (final fromId in fromIds) {
      final strippedFrom = _stripCnic(fromId);
      if (fromId.isNotEmpty) oldValuesSet.add(fromId);
      if (strippedFrom.isNotEmpty) {
        oldValuesSet.add(strippedFrom);
        oldValuesSet.add(_formatCnic(strippedFrom));
      }
    }
    final oldValues = oldValuesSet.toList();
    if (oldValues.isEmpty) return;

    final targets = ['zakat', 'non-zakat', 'gmwf', 'credits', 'emergency'];
    final fields  = ['patientId', 'cnic', 'patientCnic'];

    // Chunk old values to satisfy Firestore's limit of 30 items for 'whereIn'
    final valueChunks = <List<String>>[];
    for (int i = 0; i < oldValues.length; i += 30) {
      valueChunks.add(oldValues.sublist(i, (i + 30).clamp(0, oldValues.length)));
    }

    // Check if collectionGroup index is available
    bool collectionGroupIndexAvailable = true;
    try {
      await _fs.collectionGroup('zakat').where('patientId', isEqualTo: 'dummy').limit(1).get();
    } catch (e) {
      if (e.toString().contains('failed-precondition')) {
        collectionGroupIndexAvailable = false;
      }
    }

    if (collectionGroupIndexAvailable) {
      _log("   ⚡ Using high-speed collectionGroup index...");
      for (final col in targets) {
        for (final field in fields) {
          for (final valChunk in valueChunks) {
            try {
              final snap = await _fs.collectionGroup(col)
                  .where(field, whereIn: valChunk)
                  .get();

              for (final doc in snap.docs) {
                final docData = doc.data();
                if (docData['branchId'] != null && docData['branchId'] != branchId) continue;
                await doc.reference.update({field: toId});
                _log("         🔧 Repointed ${doc.id} in $col");
              }
            } catch (e) {
              if (e.toString().contains('failed-precondition')) {
                _log("      ⚠️ Index check failed during execution. Reverting to fallback scan...");
                await _runUnifiedFallbackScan(branchId: branchId, oldValues: valChunk, toId: toId);
              } else {
                _log("      ❌ Error updating refs in $col: $e");
              }
            }
          }
        }
      }
    } else {
      for (final valChunk in valueChunks) {
        await _runUnifiedFallbackScan(branchId: branchId, oldValues: valChunk, toId: toId);
      }
    }

    // 2. Explicitly update dispensary collections since their leaf collection names are dynamic dateKeys
    try {
      _log("   📋 Checking dispensary visits history...");
      final dates = await _getDispensaryDates(branchId);
      final root = _fs.collection('branches').doc(branchId).collection('dispensary');
      
      final chunkSize = 5;
      for (int i = 0; i < dates.length; i += chunkSize) {
        final chunk = dates.sublist(i, (i + chunkSize).clamp(0, dates.length));
        
        setState(() {
          _currentBranch = "Dispensary: date ${i + 1} of ${dates.length}";
          _progress = i / dates.length;
        });

        await Future.wait(chunk.map((date) async {
          final subCol = root.doc(date).collection(date);
          final List<Future> repointFutures = [];
          for (final field in fields) {
            for (final valChunk in valueChunks) {
              repointFutures.add(() async {
                try {
                  final matches = await subCol.where(field, whereIn: valChunk).get();
                  for (final doc in matches.docs) {
                    await doc.reference.update({field: toId});
                    _log("         🔧 Repointed ${doc.id} in dispensary/$date");
                  }
                } catch (_) {
                  // Fallback to sequential if whereIn fails
                  for (final oldVal in valChunk) {
                    final matches = await subCol.where(field, isEqualTo: oldVal).get();
                    for (final doc in matches.docs) {
                      await doc.reference.update({field: toId});
                      _log("         🔧 Repointed ${doc.id} in dispensary/$date (fallback)");
                    }
                  }
                }
              }());
            }
          }
          await Future.wait(repointFutures);
        }));
      }
    } catch (e) {
      _log("      ❌ Error updating dispensary refs: $e");
    }
  }

  /// Unified fallback scan that scans the entire branch serials history exactly once
  /// and repoints references for all collections and fields in parallel.
  Future<void> _runUnifiedFallbackScan({
    required String branchId,
    required List<String> oldValues,
    required String toId,
  }) async {
    _log("      ⚠️ CollectionGroup indexes are missing. Running unified single-pass parallel fallback scan...");
    try {
      final dates = await _getSerialsDates(branchId);
      final root = _fs.collection('branches').doc(branchId).collection('serials');
      final targets = ['zakat', 'non-zakat', 'gmwf', 'credits', 'emergency'];
      final fields  = ['patientId', 'cnic', 'patientCnic'];

      final chunkSize = 5;
      for (int i = 0; i < dates.length; i += chunkSize) {
        final chunk = dates.sublist(i, (i + chunkSize).clamp(0, dates.length));
        
        setState(() {
          _currentBranch = "Serials: date ${i + 1} of ${dates.length}";
          _progress = i / dates.length;
        });

        await Future.wait(chunk.map((date) async {
          final dateDocRef = root.doc(date);
          final List<Future> repointFutures = [];
          
          for (final col in targets) {
            final subCol = dateDocRef.collection(col);
            for (final field in fields) {
              repointFutures.add(() async {
                try {
                  final matches = await subCol.where(field, whereIn: oldValues).get();
                  for (final doc in matches.docs) {
                    await doc.reference.update({field: toId});
                    _log("         🔧 Repointed ${doc.id} in serials/$date/$col");
                  }
                } catch (_) {
                  // Fallback to sequential if whereIn fails
                  for (final oldVal in oldValues) {
                    final matches = await subCol.where(field, isEqualTo: oldVal).get();
                    for (final doc in matches.docs) {
                      await doc.reference.update({field: toId});
                      _log("         🔧 Repointed ${doc.id} in serials/$date/$col (fallback)");
                    }
                  }
                }
              }());
            }
          }
          await Future.wait(repointFutures);
        }));
      }
      _log("      ✅ Unified fallback scan completed.");
    } catch (e) {
      _log("      ❌ Error in unified fallback scan: $e");
    }
  }

  Widget _buildMergeProgressPanel() {
    if (!_isProcessing && _mergingGroupKeys.isEmpty) return const SizedBox.shrink();

    final latestLog = _logs.isNotEmpty ? _logs.first : "Preparing merge...";
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.gray200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isProcessing ? "Performing Batch Merge..." : "Merging Selected Patient Group...",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy),
                ),
              ),
              Text(
                "${(_progress * 100).toStringAsFixed(0)}%",
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: AppColors.gray200,
            color: AppColors.primary,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Text(
            latestLog,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: latestLog.contains("❌") ? Colors.red : AppColors.gray600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
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

  // ─── Prescription Merge & Cleanup Logic ──────────────────────────────────────

  Future<DocumentSnapshot?> _locateSerialDoc({
    required String branchId,
    required String dateKey,
    required String serial,
    String? preferredQueueType,
  }) async {
    final types = ['zakat', 'non-zakat', 'gmwf', 'credits', 'emergency'];
    if (preferredQueueType != null && preferredQueueType.isNotEmpty) {
      types.remove(preferredQueueType);
      types.insert(0, preferredQueueType);
    }
    
    final results = await Future.wait(types.map((type) async {
      try {
        final ref = _fs
            .collection('branches').doc(branchId)
            .collection('serials').doc(dateKey)
            .collection(type).doc(serial);
        final snap = await ref.get();
        if (snap.exists) {
          return {'snap': snap, 'queueType': type};
        }
      } catch (_) {}
      return null;
    }));
    
    final matched = results.firstWhere((r) => r != null, orElse: () => null);
    if (matched != null) {
      return matched['snap'] as DocumentSnapshot;
    }
    return null;
  }

  Future<void> _scanPrescriptions() async {
    setState(() {
      _isScanningPrescriptions = true;
      _hasScannedPrescriptions = true;
      _prescriptionMigrationItems.clear();
      _logs = ["🔎 Scanning Firestore for prescription records..."];
      _progress = 0.0;
    });

    try {
      List<DocumentSnapshot> allDocs = [];

      try {
        final querySnap = await _fs.collectionGroup('prescriptions').get();
        allDocs = querySnap.docs;
      } catch (e) {
        if (e.toString().contains('failed-precondition')) {
          _log("⚠️ Global prescriptions index missing. Falling back to branch scan...");
          final branches = await _fs.collection('branches').get();
          for (var b in branches.docs) {
            final branchId = b.id;
            _log("📂 Scanning branch $branchId prescriptions...");
            final cnicDocs = await b.reference.collection('prescriptions').get();
            for (var cDoc in cnicDocs.docs) {
              final subSnap = await cDoc.reference.collection('prescriptions').get();
              allDocs.addAll(subSnap.docs);
            }
          }
        } else {
          rethrow;
        }
      }

      _log("🔎 Found ${allDocs.length} prescription documents.");
      
      final Map<String, Map<String, dynamic>> items = {};
      int done = 0;
      final total = allDocs.length;

      for (final doc in allDocs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final serial = doc.id;
        String branchId = data['branchId']?.toString() ?? '';
        String patientCnic = '';

        final parts = doc.reference.path.split('/');
        if (parts.length >= 6 && parts[0] == 'branches') {
          branchId = parts[1];
          patientCnic = parts[3];
        } else if (parts.length >= 4 && parts[0] == 'prescriptions') {
          patientCnic = parts[1];
        }

        if (patientCnic.isEmpty) {
          patientCnic = (data['patientCnic'] ?? data['cnic'] ?? '').toString();
        }
        if (branchId.isEmpty || branchId == 'unknown') {
          branchId = 'unknown';
        }
        
        patientCnic = patientCnic.replaceAll('-', '').replaceAll(' ', '').trim();
        final itemKey = "${branchId}_${patientCnic}_$serial";

        // Extract dateKey
        String dateKey = '';
        if (serial.contains('-')) {
          dateKey = serial.split('-')[0];
        }
        if (dateKey.isEmpty || dateKey.length != 6 || int.tryParse(dateKey) == null) {
          dateKey = data['dateKey']?.toString() ?? '';
        }
        if (dateKey.isEmpty) {
          final created = data['createdAt'];
          if (created is Timestamp) {
            dateKey = DateFormat('ddMMyy').format(created.toDate());
          } else if (created is String && created.isNotEmpty) {
            try {
              dateKey = DateFormat('ddMMyy').format(DateTime.parse(created));
            } catch (_) {}
          }
        }

        final preferredType = data['queueType']?.toString() ?? '';
        
        // Locate matching serial document in standard collections
        DocumentSnapshot? serialDoc;
        String resolvedQueue = preferredType;
        if (branchId != 'unknown' && dateKey.isNotEmpty) {
          serialDoc = await _locateSerialDoc(
            branchId: branchId,
            dateKey: dateKey,
            serial: serial,
            preferredQueueType: preferredType,
          );
          if (serialDoc != null) {
            final sPathParts = serialDoc.reference.path.split('/');
            if (sPathParts.length >= 5) {
              resolvedQueue = sPathParts[4];
            }
          }
        }

        final serialDocExists = serialDoc != null;
        String status = 'orphaned';
        if (serialDocExists) {
          final sData = serialDoc.data() as Map<String, dynamic>? ?? {};
          final hasPresc = sData['prescription'] != null;
          status = hasPresc ? 'already_merged' : 'needs_merge';
        }

        final serialDocPath = serialDocExists 
            ? serialDoc.reference.path 
            : "branches/$branchId/serials/$dateKey/${resolvedQueue.isEmpty ? 'zakat' : resolvedQueue}/$serial";

        items[itemKey] = {
          'key': itemKey,
          'branchId': branchId,
          'patientCnic': patientCnic,
          'serial': serial,
          'dateKey': dateKey,
          'queueType': resolvedQueue.isEmpty ? 'zakat' : resolvedQueue,
          'patientName': data['patientName'] ?? data['name'] ?? 'Unknown Patient',
          'createdAt': data['createdAt'],
          'medicines': data['prescriptions'] ?? [],
          'prescriptionDocPath': doc.reference.path,
          'prescriptionData': data,
          'serialDocPath': serialDocPath,
          'status': status,
          'serialDocExists': serialDocExists,
        };

        done++;
        setState(() {
          _progress = done / total;
        });
      }

      setState(() {
        _prescriptionMigrationItems = items;
        _isScanningPrescriptions = false;
      });
      _log("✨ Scan complete! Found ${items.length} prescriptions to check.");
    } catch (e, st) {
      _log("❌ Scan failed: $e");
      _log("   $st");
      setState(() {
        _isScanningPrescriptions = false;
        _hasScannedPrescriptions = false;
      });
    }
  }

  Future<void> _mergeAndCleanPrescription(String key, {required bool forceRecreateSerial}) async {
    final item = _prescriptionMigrationItems[key];
    if (item == null) return;

    setState(() {
      _processingPrescriptionKeys.add(key);
    });

    final branchId = item['branchId']?.toString() ?? '';
    final patientCnic = item['patientCnic']?.toString() ?? '';
    final serial = item['serial']?.toString() ?? '';
    final dateKey = item['dateKey']?.toString() ?? '';
    final queueType = item['queueType']?.toString() ?? 'zakat';
    final serialDocPath = item['serialDocPath']?.toString() ?? '';
    final prescriptionDocPath = item['prescriptionDocPath']?.toString() ?? '';
    final isOrphaned = item['status'] == 'orphaned';

    _log("⏳ Cleaning prescription $serial...");

    try {
      if (isOrphaned && forceRecreateSerial) {
        // Option 1: Re-create the missing serial document
        final serialData = {
          'serial': serial,
          'patientId': patientCnic,
          'cnic': patientCnic,
          'patientName': item['patientName'],
          'status': 'completed',
          'dispenseStatus': 'waiting',
          'queueType': queueType,
          'dateKey': dateKey,
          'branchId': branchId,
          'createdAt': item['createdAt'] ?? FieldValue.serverTimestamp(),
          'completedAt': item['createdAt'] ?? FieldValue.serverTimestamp(),
          'prescription': item['prescriptionData'],
        };
        await _fs.doc(serialDocPath).set(serialData, SetOptions(merge: true));
        _log("   ✅ Re-created missing serial visit entry: $serialDocPath");
      } else if (!isOrphaned) {
        // Merge prescription into existing serial doc
        await _fs.doc(serialDocPath).set({
          'prescription': item['prescriptionData'],
          'status': 'completed',
          'completedAt': item['prescriptionData']['completedAt'] ?? item['prescriptionData']['createdAt'] ?? FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _log("   ✅ Merged prescription into serial visit entry: $serialDocPath");
      }

      // Delete the redundant prescription document
      await _fs.doc(prescriptionDocPath).delete();
      _log("   🗑️ Deleted original prescription document: $prescriptionDocPath");

      setState(() {
        _prescriptionMigrationItems.remove(key);
        _processingPrescriptionKeys.remove(key);
      });
    } catch (e, st) {
      _log("❌ Failed to process prescription $serial: $e");
      _log("   $st");
      setState(() {
        _processingPrescriptionKeys.remove(key);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _mergeAndCleanAllPrescriptions() async {
    final pending = _prescriptionMigrationItems.entries
        .where((e) => !_processingPrescriptionKeys.contains(e.key))
        .toList();
    
    if (pending.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Bulk Merge & Clean Prescriptions"),
        content: Text("Are you sure you want to merge and delete all ${pending.length} prescription documents? "
            "Orphaned prescriptions (where no serial visit doc exists) will be automatically re-created inside their serials collection to preserve patient history."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Merge & Clean All"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _currentBranch = "Merging prescriptions...";
      _progress = 0.0;
    });

    int done = 0;
    final total = pending.length;

    for (final entry in pending) {
      final key = entry.key;
      setState(() {
        _progress = done / total;
      });

      await _mergeAndCleanPrescription(key, forceRecreateSerial: true);
      done++;
    }

    setState(() {
      _isProcessing = false;
      _progress = 1.0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bulk prescription cleanup completed!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ─── Interactive Deduplication Logic ────────────────────────────────────────

  Future<void> _scanForDuplicates() async {
    setState(() {
      _isScanning = true;
      _logs = ["🔎 Scanning for duplicate patient records..."];
      _duplicatesByLetter.clear();
      _electedMasterIds.clear();
      _progress = 0.0;
      _serialsDatesCache.clear();
      _dispensaryDatesCache.clear();
    });

    try {
      _log("📦 Fetching all patient records (global scan)...");
      List<DocumentSnapshot> allDocs = [];

      try {
        final querySnap = await _fs.collectionGroup('patients').get();
        allDocs = querySnap.docs;
      } catch (e) {
        if (e.toString().contains('failed-precondition')) {
          _log("⚠️ Global patients index missing. Falling back to branch-by-branch scan...");
          final branches = await _fs.collection('branches').get();
          for (var b in branches.docs) {
            final pSnap = await b.reference.collection('patients').get();
            allDocs.addAll(pSnap.docs);
          }
          try {
            final tSnap = await _fs.collection('patients').get();
            allDocs.addAll(tSnap.docs);
          } catch (_) {}
        } else {
          rethrow;
        }
      }

      _log("🔎 Found ${allDocs.length} total records across all collections.");

      // Group by (branchId + canonicalKey)
      final Map<String, List<DocumentSnapshot>> groups = {};
      for (final doc in allDocs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final branchId = data['branchId']?.toString() ?? 'unknown';
        final key = _canonicalKey(data, doc.id);
        final compositeKey = "${branchId}_$key";
        groups.putIfAbsent(compositeKey, () => []).add(doc);
      }

      // Identify duplicate groups (docs.length > 1)
      final Map<String, Map<String, List<DocumentSnapshot>>> duplicates = {};
      int dupeCount = 0;

      groups.forEach((compKey, docs) {
        if (docs.length > 1) {
          final data = docs.first.data() as Map<String, dynamic>? ?? {};
          final name = data['name']?.toString() ?? '';
          final letter = name.isNotEmpty ? name[0].toUpperCase() : '#';
          
          final keyLetter = RegExp(r'[A-Z]').hasMatch(letter) ? letter : '#';

          duplicates.putIfAbsent(keyLetter, () => {});
          duplicates[keyLetter]![compKey] = docs;

          // Elect default master (highest score)
          final master = docs.reduce((a, b) {
            final scoreA = _scoreDoc(a);
            final scoreB = _scoreDoc(b);
            return scoreA >= scoreB ? a : b;
          });
          _electedMasterIds[compKey] = master.id;

          dupeCount++;
        }
      });

      // Sort keys alphabetically
      final sortedLetters = duplicates.keys.toList()..sort();
      final Map<String, Map<String, List<DocumentSnapshot>>> sortedDuplicates = {};
      for (final letter in sortedLetters) {
        sortedDuplicates[letter] = duplicates[letter]!;
      }

      setState(() {
        _duplicatesByLetter = sortedDuplicates;
        _hasScanned = true;
        _isScanning = false;
        if (sortedLetters.isNotEmpty) {
          _selectedLetter = sortedLetters.first;
        } else {
          _selectedLetter = null;
        }
      });

      _log("✨ Scan complete! Found $dupeCount duplicate patient groups.");
    } catch (e, st) {
      _log("❌ Scan failed: $e");
      _log("   $st");
      setState(() {
        _isScanning = false;
        _hasScanned = false;
      });
    }
  }

  Future<void> _animateAndRemoveGroup({
    required String groupKey,
    required String letter,
    bool updateLetterSelection = true,
  }) async {
    setState(() {
      _mergedGroupKeys.add(groupKey);
    });

    // Wait to let user see the success state
    await Future.delayed(const Duration(milliseconds: 1500));

    // Start shrinking transition
    setState(() {
      _disappearingGroupKeys.add(groupKey);
    });

    // Wait for shrink animation to finish
    await Future.delayed(const Duration(milliseconds: 350));

    // Finally remove from list and clean up keys
    setState(() {
      _mergedGroupKeys.remove(groupKey);
      _disappearingGroupKeys.remove(groupKey);
      
      if (letter.isNotEmpty && _duplicatesByLetter.containsKey(letter)) {
        _duplicatesByLetter[letter]!.remove(groupKey);
        
        if (updateLetterSelection && _duplicatesByLetter[letter]!.isEmpty) {
          _duplicatesByLetter.remove(letter);
          
          final sortedLetters = _duplicatesByLetter.keys.toList()..sort();
          if (sortedLetters.isNotEmpty) {
            _selectedLetter = sortedLetters.first;
          } else {
            _selectedLetter = null;
          }
        }
      }
    });
  }

  Future<void> _mergeSingleGroup(String groupKey, String branchId, List<DocumentSnapshot> docs) async {
    final masterId = _electedMasterIds[groupKey];
    if (masterId == null) return;

    final masterDoc = docs.firstWhere((d) => d.id == masterId, orElse: () => docs.first);

    setState(() {
      _mergingGroupKeys.add(groupKey);
    });

    _log("⏳ Merging duplicate group $groupKey...");
    try {
      await _performMerge(branchId, docs, electedMaster: masterDoc);
      _log("✅ Successfully merged group $groupKey.");

      setState(() {
        _mergingGroupKeys.remove(groupKey);
      });
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Group merged successfully!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      await _animateAndRemoveGroup(
        groupKey: groupKey,
        letter: _selectedLetter ?? '',
        updateLetterSelection: true,
      );
    } catch (e, st) {
      _log("❌ Failed to merge group $groupKey: $e");
      _log("   $st");
      setState(() {
        _mergingGroupKeys.remove(groupKey);
        _mergedGroupKeys.remove(groupKey);
        _disappearingGroupKeys.remove(groupKey);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Merge failed: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _ignoreGroup(String groupKey) {
    setState(() {
      if (_selectedLetter != null && _duplicatesByLetter.containsKey(_selectedLetter)) {
        _duplicatesByLetter[_selectedLetter]!.remove(groupKey);
        
        if (_duplicatesByLetter[_selectedLetter]!.isEmpty) {
          _duplicatesByLetter.remove(_selectedLetter);
          
          final sortedLetters = _duplicatesByLetter.keys.toList()..sort();
          if (sortedLetters.isNotEmpty) {
            _selectedLetter = sortedLetters.first;
          } else {
            _selectedLetter = null;
          }
        }
      }
    });
  }

  Future<void> _mergeAllUnderSelectedLetter() async {
    final letter = _selectedLetter;
    if (letter == null) return;
    final groups = Map<String, List<DocumentSnapshot>>.from(_duplicatesByLetter[letter] ?? {});
    if (groups.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Merge All under '$letter'"),
        content: Text("Are you sure you want to merge all ${groups.length} duplicate groups under the letter '$letter' using the currently selected masters?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Merge All"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _currentBranch = "Merging letter $letter...";
      _progress = 0.0;
    });

    int done = 0;
    final total = groups.length;

    for (final entry in groups.entries) {
      final groupKey = entry.key;
      final docs = entry.value;
      final branchId = (docs.first.data() as Map<String, dynamic>? ?? {})['branchId']?.toString() ?? 'unknown';
      final masterId = _electedMasterIds[groupKey];
      final masterDoc = docs.firstWhere((d) => d.id == masterId, orElse: () => docs.first);

      setState(() {
        _progress = done / total;
      });

      try {
        setState(() {
          _mergingGroupKeys.add(groupKey);
        });

        await _performMerge(branchId, docs, electedMaster: masterDoc);
        
        setState(() {
          _mergingGroupKeys.remove(groupKey);
        });

        // Fire-and-forget the success transition so it happens asynchronously.
        // We set updateLetterSelection to true so that whichever animation finishes last shifts the tab.
        _animateAndRemoveGroup(
          groupKey: groupKey,
          letter: letter,
          updateLetterSelection: true,
        );
      } catch (e) {
        _log("❌ Failed bulk merge for group $groupKey: $e");
        setState(() {
          _mergingGroupKeys.remove(groupKey);
        });
      }
      done++;
    }

    setState(() {
      _isProcessing = false;
      _progress = 1.0;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Finished merging duplicates under letter '$letter'."),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  String _parseDate(dynamic raw, {String fmt = 'dd MMM yyyy'}) {
    if (raw == null) return 'N/A';
    try {
      if (raw is Timestamp) return DateFormat(fmt).format(raw.toDate());
      if (raw is String && raw.isNotEmpty) {
        return DateFormat(fmt).format(DateTime.parse(raw));
      }
    } catch (_) {}
    return 'N/A';
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Custom Tab Selector (Premium Aesthetics)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _activeTab == 0
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Manual Review (A-Z)",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _activeTab == 0 ? AppColors.primary : AppColors.gray600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _activeTab == 1
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Prescription Cleanups",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _activeTab == 1 ? AppColors.primary : AppColors.gray600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 2 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _activeTab == 2
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Automated Global Run",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _activeTab == 2 ? AppColors.primary : AppColors.gray600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: _activeTab == 0 
                ? _buildManualReviewTab() 
                : _activeTab == 1 
                    ? _buildPrescriptionCleanupsTab() 
                    : _buildAutomatedTab(),
          ),
          _buildMergeProgressPanel(),
        ],
      ),
    );
  }

  Widget _buildManualReviewTab() {
    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 20),
            const Text(
              "Scanning all patient documents...",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.gray800),
            ),
            const SizedBox(height: 8),
            Text(
              "This scans branches and local lists to build indexes.",
              style: TextStyle(fontSize: 13, color: AppColors.gray500),
            ),
          ],
        ),
      );
    }

    if (!_hasScanned) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.manage_search_rounded, size: 72, color: AppColors.primary.withValues(alpha: 0.8)),
            const SizedBox(height: 24),
            const Text(
              "Interactive Duplicate Resolution",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Text(
                "Scan the database to search for patients with duplicate accounts. "
                "You can inspect patient data side-by-side grouped by name (A to Z), "
                "elect which record is the correct version, and merge them cleanly.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.gray600, height: 1.5),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _scanForDuplicates,
              icon: const Icon(Icons.search),
              label: const Text("Scan Database for Duplicates"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      );
    }

    if (_duplicatesByLetter.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.done_all_rounded, size: 64, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              const Text(
                "No Duplicates Found!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              const Text(
                "Your patient database contains no duplicate profiles.",
                style: TextStyle(fontSize: 14, color: AppColors.gray600),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: _scanForDuplicates,
                icon: const Icon(Icons.refresh),
                label: const Text("Scan Again"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final letters = _duplicatesByLetter.keys.toList()..sort();
    final currentLetterGroups = _duplicatesByLetter[_selectedLetter] ?? {};

    int totalGroups = 0;
    int totalDocs = 0;
    _duplicatesByLetter.forEach((letter, groups) {
      totalGroups += groups.length;
      for (final docList in groups.values) {
        totalDocs += docList.length;
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A-Z Horizontal Chip Bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.gray200)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Select Patient First Letter:",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gray500),
                  ),
                  Text(
                    "Total Duplicates: $totalGroups groups ($totalDocs profiles)",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: letters.map((letter) {
                    final isSelected = _selectedLetter == letter;
                    final count = _duplicatesByLetter[letter]?.length ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedLetter = letter),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary : AppColors.gray100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppColors.primaryDark : AppColors.gray200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                letter,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : AppColors.gray800,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.white.withValues(alpha: 0.2) : AppColors.gray300,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  count.toString(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : AppColors.gray700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        // Letter header options
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Duplicates under '$_selectedLetter' (${currentLetterGroups.length} group(s))",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _mergeAllUnderSelectedLetter,
                icon: const Icon(Icons.merge_type_rounded, size: 18),
                label: Text("Merge All under '$_selectedLetter'"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),

        // Scrollable list of duplicate groups
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            itemCount: currentLetterGroups.length,
            itemBuilder: (context, index) {
              final groupKey = currentLetterGroups.keys.elementAt(index);
              final docs = currentLetterGroups[groupKey]!;
              return _buildDuplicateGroupCard(groupKey, docs);
            },
          ),
        ),
      ],
    );
  }
  Widget _buildDuplicateGroupCard(String groupKey, List<DocumentSnapshot> docs) {
    final firstDoc = docs.first;
    final firstData = firstDoc.data() as Map<String, dynamic>? ?? {};
    final patientName = firstData['name'] ?? 'Unknown';
    final branchId = firstData['branchId'] ?? 'unknown';
    final isMerging = _mergingGroupKeys.contains(groupKey);
    final isMerged = _mergedGroupKeys.contains(groupKey);
    final isDisappearing = _disappearingGroupKeys.contains(groupKey);

    return AnimatedSize(
      key: ValueKey("size_$groupKey"),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      clipBehavior: Clip.hardEdge,
      child: isDisappearing
          ? const SizedBox(height: 0, width: double.infinity)
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1.0,
                    child: child,
                  ),
                );
              },
              child: isMerged
                  ? Card(
                      key: ValueKey("merged_$groupKey"),
                      margin: const EdgeInsets.only(bottom: 24),
                      elevation: 0,
                      color: Colors.green.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.green.shade200, width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: Colors.green.shade700,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "$patientName Merged Successfully",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Database references and prescriptions updated live.",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Card(
                      key: ValueKey("normal_$groupKey"),
                      margin: const EdgeInsets.only(bottom: 24),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.gray200, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Group Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        patientName,
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.location_on_outlined, size: 14, color: AppColors.gray500),
                                          const SizedBox(width: 4),
                                          Text(
                                            "Branch: ${branchId.toUpperCase()}",
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray500),
                                          ),
                                          const SizedBox(width: 16),
                                          Icon(Icons.copy_all_outlined, size: 14, color: AppColors.gray500),
                                          const SizedBox(width: 4),
                                          Text(
                                            "${docs.length} Duplicate Records",
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray500),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: isMerging ? null : () => _ignoreGroup(groupKey),
                                  icon: const Icon(Icons.visibility_off_outlined, size: 16),
                                  label: const Text("Ignore Group"),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.gray500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: AppColors.gray200, height: 1),
                            const SizedBox(height: 16),

                            // Responsive Layout Builder using Wrap for side-by-side or multi-row card layouts
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final cardWidth = 280.0;
                                final singleCardFullWidth = constraints.maxWidth < cardWidth;
                                
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: docs.map((doc) {
                                    return SizedBox(
                                      width: singleCardFullWidth ? constraints.maxWidth : cardWidth,
                                      child: _buildDocDetailCard(groupKey, doc, docs),
                                    );
                                  }).toList(),
                                );
                              },
                            ),

                            const SizedBox(height: 20),
                            
                            // Resolve Actions row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (isMerging)
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "Merging records...",
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.gray600),
                                      ),
                                    ],
                                  )
                                else
                                  ElevatedButton.icon(
                                    onPressed: () => _mergeSingleGroup(groupKey, branchId, docs),
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text("Merge Group Now"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
    );
  }
  Widget _buildDocDetailCard(String groupKey, DocumentSnapshot doc, List<DocumentSnapshot> allDocs) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final selectedMasterId = _electedMasterIds[groupKey];
    final isSelected = selectedMasterId == doc.id;
    
    // Determine the recommended master
    final bestMaster = allDocs.reduce((a, b) {
      final scoreA = _scoreDoc(a);
      final scoreB = _scoreDoc(b);
      return scoreA >= scoreB ? a : b;
    });
    final isRecommended = bestMaster.id == doc.id;

    // Check if ID is authoritative (exactly 13 digit CNIC or child composite id)
    final idIsAuthoritative = RegExp(r'^\d{13}$').hasMatch(doc.id) || RegExp(r'^\d{13}_child_.+$').hasMatch(doc.id);

    final status = data['status']?.toString() ?? 'N/A';
    final docId = doc.id;
    final name = data['name']?.toString() ?? 'N/A';
    final cnic = data['cnic']?.toString() ?? 'N/A';
    final gCnic = data['guardianCnic']?.toString() ?? 'N/A';
    final phone = data['phone']?.toString() ?? 'N/A';
    final age = data['age']?.toString() ?? 'N/A';
    final gender = data['gender']?.toString() ?? 'N/A';
    final dob = _parseDate(data['dob']);
    final created = _parseDate(data['createdAt']);
    final score = _scoreDoc(doc);

    return InkWell(
      onTap: () => setState(() => _electedMasterIds[groupKey] = doc.id),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight.withValues(alpha: 0.5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.gray200,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Selection State & Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? AppColors.primary : AppColors.gray400,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isSelected ? "Keep as Master" : "Select Master",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? AppColors.primary : AppColors.gray600,
                      ),
                    ),
                  ],
                ),
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.amberLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      "RECOMMENDED",
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.amber),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Document ID Badge
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: idIsAuthoritative ? Colors.purple.shade50 : AppColors.gray100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: idIsAuthoritative ? Colors.purple.shade200 : AppColors.gray300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    idIsAuthoritative ? Icons.check_circle : Icons.help_outline,
                    size: 14,
                    color: idIsAuthoritative ? Colors.purple.shade700 : AppColors.gray500,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      docId,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: idIsAuthoritative ? Colors.purple.shade800 : AppColors.gray800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Properties list
            _buildPropRow("Name", name, isBold: true),
            _buildPropRow("CNIC", cnic),
            if (gCnic != 'N/A' && gCnic.isNotEmpty) _buildPropRow("Guard. CNIC", gCnic),
            _buildPropRow("Phone", phone),
            _buildPropRow("Age / Gender", "$age / $gender"),
            _buildPropRow("Date of Birth", dob),
            _buildPropRow("Joined", created),
            
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: _getStatusColor(status),
                    ),
                  ),
                ),
                
                // Richness Score
                Text(
                  "Data Score: $score",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.gray500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: AppColors.gray500, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.gray800,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'zakat':
        return const Color(0xFF1565C0);
      case 'non-zakat':
        return const Color(0xFF6A1B9A);
      case 'gmwf':
        return const Color(0xFF2E7D32);
      default:
        return AppColors.gray500;
    }
  }

  Widget _buildAutomatedTab() {
    return Padding(
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

  Widget _buildPrescriptionCleanupsTab() {
    if (_isScanningPrescriptions) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 20),
            const Text(
              "Scanning all prescription documents in Firestore...",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.gray800),
            ),
            const SizedBox(height: 8),
            Text(
              "Parsing paths, dates, and checking serial matches...",
              style: TextStyle(fontSize: 13, color: AppColors.gray500),
            ),
          ],
        ),
      );
    }

    if (!_hasScannedPrescriptions) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 72, color: AppColors.primary.withValues(alpha: 0.8)),
            const SizedBox(height: 24),
            const Text(
              "Prescription Data Cleanups",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Text(
                "Scan Firestore to identify older prescription documents. "
                "The tool will locate their corresponding daily serial entries, "
                "merge the prescription data inside them, and delete the redundant "
                "original collections one-by-one or in bulk.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.gray600, height: 1.5),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _scanPrescriptions,
              icon: const Icon(Icons.search),
              label: const Text("Scan Database for Prescriptions"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      );
    }

    if (_prescriptionMigrationItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.done_all_rounded, size: 64, color: Colors.green),
              ),
              const SizedBox(height: 24),
              const Text(
                "No Redundant Prescriptions Found!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.navy),
              ),
              const SizedBox(height: 8),
              const Text(
                "All prescription documents have been successfully merged or cleaned from Firestore.",
                style: TextStyle(fontSize: 14, color: AppColors.gray600),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: _scanPrescriptions,
                icon: const Icon(Icons.refresh),
                label: const Text("Scan Again"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = _prescriptionMigrationItems.values.toList();
    final zakatCount = items.where((i) => i['queueType'] == 'zakat').length;
    final nonZakatCount = items.where((i) => i['queueType'] == 'non-zakat').length;
    final otherCount = items.length - zakatCount - nonZakatCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Prescription Summary Panel
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.gray200)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Pending Cleanups: ${items.length} prescriptions",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Zakat: $zakatCount | Non-Zakat: $nonZakatCount | Others: $otherCount",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray500),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _mergeAndCleanAllPrescriptions,
                icon: const Icon(Icons.cleaning_services),
                label: const Text("Bulk Merge & Clean All"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),

        // Prescription list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildPrescriptionCard(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrescriptionCard(Map<String, dynamic> item) {
    final key = item['key'] as String;
    final patientName = item['patientName'] as String;
    final serial = item['serial'] as String;
    final branchId = item['branchId'] as String;
    final dateKey = item['dateKey'] as String;
    final queueType = item['queueType'] as String;
    final status = item['status'] as String;
    final medicines = item['medicines'] as List<dynamic>;
    final isProcessing = _processingPrescriptionKeys.contains(key);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (status == 'already_merged') {
      statusColor = Colors.green;
      statusLabel = "Already Merged (Clean)";
      statusIcon = Icons.check_circle_outline;
    } else if (status == 'needs_merge') {
      statusColor = Colors.orange;
      statusLabel = "Needs Merge";
      statusIcon = Icons.sync;
    } else {
      statusColor = Colors.red;
      statusLabel = "Orphaned (No Serial Visit)";
      statusIcon = Icons.warning_amber_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.gray200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row 1: Header info & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Branch: ${branchId.toUpperCase()} | Serial: $serial | Date: $dateKey | Queue: $queueType",
                        style: TextStyle(fontSize: 12, color: AppColors.gray600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: AppColors.gray200, height: 1),
            const SizedBox(height: 12),

            // Row 2: Medicines List
            const Text(
              "Prescribed Medicines:",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            if (medicines.isEmpty)
              const Text("No medicines in this prescription.", style: TextStyle(fontSize: 12, color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: medicines.map<Widget>((med) {
                  final name = med['name'] ?? 'Unknown Medicine';
                  final qty = med['quantity'] ?? 1;
                  return Chip(
                    label: Text("$name (x$qty)"),
                    backgroundColor: AppColors.gray100,
                    labelStyle: const TextStyle(fontSize: 11, color: AppColors.gray800),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),

            const SizedBox(height: 16),
            
            // Row 3: Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isProcessing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                else if (status == 'orphaned')
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _mergeAndCleanPrescription(key, forceRecreateSerial: false),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text("Delete Prescription Only"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => _mergeAndCleanPrescription(key, forceRecreateSerial: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("Re-create Serial & Clean"),
                      ),
                    ],
                  )
                else if (status == 'needs_merge')
                  ElevatedButton(
                    onPressed: () => _mergeAndCleanPrescription(key, forceRecreateSerial: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Merge & Clean"),
                  )
                else // already_merged
                  ElevatedButton(
                    onPressed: () => _mergeAndCleanPrescription(key, forceRecreateSerial: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Delete Prescription (Safe)"),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}