import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------------------
  // USERS
  // ---------------------------
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first.data();
    }
    return null;
  }

  /// Users by branch (subcollection)
  Stream<List<Map<String, dynamic>>> streamUsersByBranch(String branchId) {
    return _db
        .collection('branches')
        .doc(branchId)
        .collection('users')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Global users (all branches)
  Stream<List<Map<String, dynamic>>> streamAllUsers() {
    return _db
        .collection('users')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // ---------------------------
  // BRANCHES
  // ---------------------------
  Future<void> ensureBranchExists(String branchId, String branchName) async {
    final ref = _db.collection('branches').doc(branchId);
    await ref.set({
      'id': branchId,
      'name': branchName,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> streamBranches() {
    return _db
        .collection('branches')
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
