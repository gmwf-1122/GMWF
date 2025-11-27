// lib/services/firestore_service.dart
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'local_storage_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------------------
  // 🧠 Helper: Check Firestore ready
  // ---------------------------
  Future<bool> _isFirestoreAvailable() async {
    if (!Platform.isWindows) return true;
    try {
      // Run a lightweight query to confirm availability
      await _db.collection('ping').limit(1).get();
      return true;
    } catch (e) {
      print("⚠️ Firestore unavailable (Windows): $e");
      return false;
    }
  }

  // ---------------------------
  // USERS
  // ---------------------------

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    if (!await _isFirestoreAvailable()) return null;

    try {
      final query = await _db
          .collection('users')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }
    } catch (e, st) {
      print("⚠️ getUserByEmail error: $e\n$st");
    }
    return null;
  }

  /// Users by branch (subcollection)
  Stream<List<Map<String, dynamic>>> streamUsersByBranch(String branchId) {
    try {
      return _db
          .collection('branches')
          .doc(branchId)
          .collection('users')
          .snapshots()
          .handleError((e) {
        print("⚠️ streamUsersByBranch error: $e");
      }).map((snap) => snap.docs.map((d) => d.data()).toList());
    } catch (e, st) {
      print("⚠️ streamUsersByBranch failed: $e\n$st");
      // Return a safe empty stream to prevent crashes
      return Stream.value([]);
    }
  }

  /// Global users (all branches)
  Stream<List<Map<String, dynamic>>> streamAllUsers() {
    try {
      return _db.collection('users').snapshots().handleError((e) {
        print("⚠️ streamAllUsers error: $e");
      }).map((snap) => snap.docs.map((d) => d.data()).toList());
    } catch (e, st) {
      print("⚠️ streamAllUsers failed: $e\n$st");
      return Stream.value([]);
    }
  }

  // ---------------------------
  // BRANCHES
  // ---------------------------

  Future<void> ensureBranchExists(String branchId, String branchName) async {
    if (!await _isFirestoreAvailable()) {
      print("⚠️ Skipping branch creation — Firestore not ready on Windows");
      return;
    }

    try {
      final ref = _db.collection('branches').doc(branchId);
      await ref.set({
        'id': branchId,
        'name': branchName,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      print("⚠️ ensureBranchExists error: $e\n$st");
    }
  }

  Stream<List<Map<String, dynamic>>> streamBranches() {
    try {
      return _db.collection('branches').snapshots().handleError((e) {
        print("⚠️ streamBranches error: $e");
      }).map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    } catch (e, st) {
      print("⚠️ streamBranches failed: $e\n$st");
      return Stream.value([]);
    }
  }

  // ---------------------------
  // ENTRIES (Vitals, CNIC, etc.)
  // ---------------------------

  /// Save new entry: patient CNIC + vitals + auto serial (ddMMyy-001)
  Future<void> saveEntry({
    required String branchId,
    required String patientCnic,
    required Map<String, dynamic> vitals,
  }) async {
    try {
      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyy').format(now);
      final serial = await _generateNextSerial(branchId, dateKey);

      final entryData = {
        'serial': serial,
        'patientCnic': patientCnic,
        'vitals': vitals,
        'timestamp': FieldValue.serverTimestamp(),
        'dateKey': dateKey,
      };

      // 🔹 Firestore write — skip if on Windows
      final isFirestoreReady = await _isFirestoreAvailable();
      if (isFirestoreReady) {
        final branchRef = _db.collection('branches').doc(branchId);
        await branchRef.collection('entries').doc(serial).set(entryData);
        await _db.collection('entries').doc(serial).set(entryData);
      } else {
        print("💾 Firestore skipped (Windows/offline) — saving locally");
      }

      // 🔹 Always save locally
      await LocalStorageService.saveEntryLocal(branchId, serial, entryData);

      print("✅ Entry saved successfully: $serial");
    } catch (e, st) {
      print("⚠️ saveEntry error: $e\n$st");

      // Backup for later sync
      await LocalStorageService.enqueueSync({
        'type': 'save_entry',
        'branchId': branchId,
        'patientCnic': patientCnic,
        'vitals': vitals,
      });
    }
  }

  /// Generate next serial for entry: ddMMyy-001, ddMMyy-002, etc.
  Future<String> _generateNextSerial(String branchId, String dateKey) async {
    try {
      final isFirestoreReady = await _isFirestoreAvailable();
      if (!isFirestoreReady) {
        return "$dateKey-001";
      }

      final query = await _db
          .collection('branches')
          .doc(branchId)
          .collection('entries')
          .where('dateKey', isEqualTo: dateKey)
          .orderBy('serial', descending: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return "$dateKey-001";
      }

      final lastSerial = query.docs.first['serial'] ?? '';
      final parts = lastSerial.split('-');
      final lastNumber = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

      final newSerial = lastNumber + 1;
      return "$dateKey-${newSerial.toString().padLeft(3, '0')}";
    } catch (e, st) {
      print("⚠️ _generateNextSerial error: $e\n$st");
      return "$dateKey-001";
    }
  }
}
