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

  Stream<List<Map<String, dynamic>>> streamUsersByBranch(String branchId) {
    return _db
        .collection('users')
        .where('branchId', isEqualTo: branchId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  // ---------------------------
  // BRANCHES
  // ---------------------------
  Future<void> ensureBranchExists(String branchId, String branchName) async {
    final ref = _db.collection('branches').doc(branchId);
    await ref.set({
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

  // ---------------------------
  // PATIENTS
  // ---------------------------

  Future<void> addPatient(Map<String, dynamic> patientData) async {
    await _db.collection('patients').add({
      ...patientData,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> streamPatients(String branchId,
      {String? doctorId, List<String>? statuses}) {
    Query ref =
        _db.collection('patients').where('branchId', isEqualTo: branchId);

    if (doctorId != null) {
      ref = ref.where('assignedDoctorId', isEqualTo: doctorId);
    }

    if (statuses != null && statuses.isNotEmpty) {
      ref = ref.where('status', whereIn: statuses);
    }

    return ref.snapshots().map(
        (s) => s.docs.map((d) => d.data() as Map<String, dynamic>).toList());
  }

  // ---------------------------
  // PRESCRIPTIONS
  // ---------------------------

  Future<void> createPrescription(
    String branchId,
    String doctorId,
    String patientId,
    List<Map<String, dynamic>> items,
  ) async {
    final ref = _db.collection('prescriptions').doc();

    await _db.runTransaction((tx) async {
      int total = 0;
      List<Map<String, dynamic>> details = [];

      for (final it in items) {
        final invRef = _db
            .collection('branches')
            .doc(branchId)
            .collection('inventory')
            .doc(it['itemId']);

        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) throw Exception('Item not found');
        final invData = invSnap.data() as Map<String, dynamic>;
        final currentStock = invData['stock'] ?? 0;

        if (currentStock < it['qty']) {
          throw Exception('Not enough stock for ${invData['name']}');
        }

        final price = invData['price'] ?? 0;
        total += (price as int) * (it['qty'] as int);

        details.add({
          'itemId': it['itemId'],
          'name': invData['name'],
          'qty': it['qty'],
          'price': price,
        });

        tx.update(invRef, {'stock': currentStock - it['qty']});
      }

      tx.set(ref, {
        'patientId': patientId,
        'branchId': branchId,
        'doctorId': doctorId,
        'items': details,
        'total': total,
        'status': 'ready',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<Map<String, dynamic>>> streamPrescriptions(
      String branchId, String status) {
    return _db
        .collection('prescriptions')
        .where('branchId', isEqualTo: branchId)
        .where('status', isEqualTo: status)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  // ---------------------------
  // INVENTORY
  // ---------------------------

  Future<void> addOrUpdateInventoryItem(
      String branchId, String itemId, Map<String, dynamic> data) async {
    final ref = _db
        .collection('branches')
        .doc(branchId)
        .collection('inventory')
        .doc(itemId);
    await ref.set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> streamInventory(String branchId) {
    return _db
        .collection('branches')
        .doc(branchId)
        .collection('inventory')
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }
}
