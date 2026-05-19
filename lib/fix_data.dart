import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';

import 'dart:io';

void main() async {
  final logFile = File('cleanup_log.txt');
  final sink = logFile.openWrite();
  
  void log(String msg) {
    print(msg);
    sink.writeln(msg);
  }

  try {
    WidgetsFlutterBinding.ensureInitialized();
    log("🔌 Initializing Firebase...");
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
    // ==========================================
    // LIVE MERGE IS ENABLED
    const bool dryRun = false; 
    // ==========================================

    log("🚀 [LIVE MERGE] Starting full database cleanup...");
    
    final helper = FirestoreCleanupHelper(dryRun: dryRun, log: log);
    await helper.startCleanup();
    
    log("\n✨ ALL DATA MERGED SUCCESSFULLY! Your Firestore is now clean.");
  } catch (e, stack) {
    log("❌ FATAL ERROR: $e");
    log(stack.toString());
  } finally {
    await sink.close();
  }
}

class FirestoreCleanupHelper {
  final bool dryRun;
  final Function(String) log;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  FirestoreCleanupHelper({required this.dryRun, required this.log});

  Future<void> startCleanup() async {
    final branches = await _fs.collection('branches').get();
    for (var branch in branches.docs) {
      log("\n📍 Branch: ${branch.id}");
      await _processBranch(branch.id);
    }
  }

  Future<void> _processBranch(String branchId) async {
    final patientsRef = _fs.collection('branches').doc(branchId).collection('patients');
    final allPatients = await patientsRef.get();
    
    Map<String, List<DocumentSnapshot>> identityGroups = {};

    for (var doc in allPatients.docs) {
      final data = doc.data();
      final key = _generateCanonicalKey(data, doc.id);
      identityGroups.putIfAbsent(key, () => []).add(doc);
    }

    for (var group in identityGroups.entries) {
      if (group.value.length > 1) {
        await _performDeepMerge(branchId, group.key, group.value);
      }
    }
  }

  String _generateCanonicalKey(Map<String, dynamic> data, String docId) {
    final cnic = (data['cnic'] ?? '').toString().replaceAll('-', '').trim();
    final gCnic = (data['guardianCnic'] ?? '').toString().replaceAll('-', '').trim();
    final name = (data['name'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (cnic.isNotEmpty) return cnic;
    if (gCnic.isNotEmpty && name.isNotEmpty) return "${gCnic}_$name";
    return docId;
  }

  Future<void> _performDeepMerge(String bId, String targetId, List<DocumentSnapshot> docs) async {
    final masterDoc = docs.firstWhere((d) => d.id == targetId, orElse: () => docs.first);
    log("💡 Found duplicate for: ${(masterDoc.data() as Map)['name']} -> Master ID: $targetId");

    for (var duplicate in docs) {
      if (duplicate.id == masterDoc.id) continue;
      log("   🔄 Moving data from [${duplicate.id}] to [$targetId]...");
      
      if (!dryRun) {
        // Move Global Prescriptions
        await _moveHistory(
          _fs.collection('branches').doc(bId).collection('prescriptions').doc(duplicate.id).collection('prescriptions'),
          _fs.collection('branches').doc(bId).collection('prescriptions').doc(targetId).collection('prescriptions')
        );

        // Update Tokens (Serials) and Dispensary records
        await _updateRefs(bId, 'serials', duplicate.id, targetId);
        await _updateRefs(bId, 'dispensary', duplicate.id, targetId);

        // Finally delete the old patient profile
        await duplicate.reference.delete();
        log("      🗑️ Duplicate ID [${duplicate.id}] deleted.");
      } else {
        log("      [PREVIEW] Would merge ${duplicate.id} into $targetId");
      }
    }
  }

  Future<void> _moveHistory(CollectionReference source, CollectionReference target) async {
    final docs = await source.get();
    for (var doc in docs.docs) {
      await target.doc(doc.id).set(doc.data(), SetOptions(merge: true));
      await doc.reference.delete();
    }
  }

  Future<void> _updateRefs(String bId, String col, String oldId, String newId) async {
    final root = _fs.collection('branches').doc(bId).collection(col);
    final dates = await root.get();
    for (var dateDoc in dates.docs) {
      final sub = dateDoc.reference.collection(dateDoc.id);
      for (var f in ['patientId', 'patientCnic', 'cnic']) {
        final records = await sub.where(f, isEqualTo: oldId).get();
        for (var rec in records.docs) {
          await rec.reference.update({f: newId});
        }
      }
    }
  }
}
