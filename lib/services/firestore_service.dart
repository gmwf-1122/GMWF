import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/patient.dart';
import '../models/token.dart';
import 'local_storage_service.dart';
import 'sync_service.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    return DateTime.now();
  }

  Future<bool> _isFirestoreAvailable() async {
    if (!Platform.isWindows) return true;
    try {
      await _db.collection('_ping').limit(1).get();
      return true;
    } catch (_) {
      return false;
    }
  }

Future<void> savePatient({
  required String branchId,
  required String patientId,
  required Map<String, dynamic> patientData,
}) async {
  if (branchId.trim().isEmpty || patientId.trim().isEmpty) {
    print("ERROR: savePatient → branchId or patientId empty");
    return;
  }

  final data = Map<String, dynamic>.from(patientData);
  data['branchId'] = branchId;
  data['patientId'] = patientId;
  data.remove('id');

  if (data['dob'] is String) {
    try {
      data['dob'] = Timestamp.fromDate(DateTime.parse(data['dob']));
    } catch (e) {
      print('Invalid DOB format: ${data['dob']} → $e');
    }
  } else if (data['dob'] is DateTime) {
    data['dob'] = Timestamp.fromDate(data['dob']);
  }

  print('Saving patient locally → patientId: $patientId | Name: ${data['name'] ?? 'unknown'}');

  await LocalStorageService.saveLocalPatient(data);

  RealtimeManager().sendMessage(
    RealtimeEvents.payload(
      type: RealtimeEvents.savePatient,
      data: {
        'branchId': branchId,
        'patientId': patientId,
        'data': data,
      },
    ),
  );

  final action = {
    'type': 'save_patient',
    'branchId': branchId,
    'patientId': patientId,
    'data': data,
  };

  await LocalStorageService.enqueueSync(action);

  print("Patient enqueued → $patientId | queue size now: ${Hive.box(LocalStorageService.syncBox).length}");

  SyncService().triggerUpload();
  print("triggerUpload called after patient enqueue");
}

Future<void> saveEntry({
  required String branchId,
  required String patientId,
  required Map<String, dynamic> vitals,
}) async {
  if (branchId.trim().isEmpty || patientId.trim().isEmpty) {
    print('ERROR: Cannot save entry — branchId or patientId empty');
    return;
  }

  final dateKey = DateFormat('ddMMyy').format(DateTime.now());
  final serial = await _generateNextSerial(branchId, dateKey);

  final now = DateTime.now();

  String queueType = 'zakat';
  String patientName = 'Unknown Patient';
  String patientCnic = '';
  String guardianCnic = '';

  try {
    final patientData = Hive.box(LocalStorageService.patientsBox).get(patientId);
    if (patientData is Map) {
      final status = (patientData['status'] as String?)?.toLowerCase().trim() ?? 'zakat';
      patientName = (patientData['name'] as String?)?.trim() ?? 'Unknown Patient';
      patientCnic = (patientData['cnic'] as String?)?.trim() ?? '';
      guardianCnic = (patientData['guardianCnic'] as String?)?.trim() ?? '';

      if (status.contains('non-zakat') || status == 'non zakat') {
        queueType = 'non-zakat';
      } else if (status.contains('gmwf') || status == 'gm wf') {
        queueType = 'gmwf';
      }
    }
  } catch (e) {
    print('Could not fetch patient from Hive for $patientId: $e');
  }

  if (patientCnic.isEmpty && guardianCnic.isEmpty && patientName == 'Unknown Patient') {
    try {
      final patientDoc = await _db
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .doc(patientId)
          .get();

      if (patientDoc.exists) {
        final data = patientDoc.data()!;
        patientName = data['name']?.toString().trim() ?? 'Unknown Patient';
        patientCnic = data['cnic']?.toString().trim() ?? '';
        guardianCnic = data['guardianCnic']?.toString().trim() ?? '';
      }
    } catch (e) {
      print('Firestore fallback for patient $patientId failed: $e');
    }
  }

  final data = {
    'serial': serial,
    'patientId': patientId,
    'patientName': patientName,
    'patientCnic': patientCnic,
    'guardianCnic': guardianCnic,
    'branchId': branchId,
    'vitals': vitals,
    'dateKey': dateKey,
    'queueType': queueType,        // FIX 1: added to data map so sync_service can read queueType as fallback
    'timestamp': now.toIso8601String(),
    'createdAt': now.toIso8601String(),
    'status': 'waiting',
  };

  print('Saving entry locally → Serial: $serial | Patient: $patientName | CNIC: $patientCnic | Guardian CNIC: $guardianCnic');

  await LocalStorageService.saveEntryLocal(branchId, serial, data);

  RealtimeManager().sendMessage(
    RealtimeEvents.payload(
      type: RealtimeEvents.saveEntry,
      data: {
        'branchId': branchId,
        'datePart': dateKey,
        'queueType': queueType,
        'serial': serial,
        'data': data,
      },
    ),
  );

  // FIX 2: was 'datePart' — sync_service._uploadPending() reads 'dateKey'
  final action = {
    'type': 'save_entry',
    'branchId': branchId,
    'dateKey': dateKey,
    'queueType': queueType,
    'serial': serial,
    'data': data,
  };

  await LocalStorageService.enqueueSync(action);

  print("Entry enqueued → serial: $serial | queue size: ${Hive.box(LocalStorageService.syncBox).length}");

  SyncService().triggerUpload();
  print("triggerUpload called after entry enqueue");
}

  Future<String> _generateNextSerial(String branchId, String dateKey) async {
    final localCount = LocalStorageService.getLocalEntries(branchId)
        .where((e) => (e['dateKey'] as String?) == dateKey)
        .length;

    final nextNumber = localCount + 1;
    return '$dateKey-${nextNumber.toString().padLeft(3, '0')}';
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    if (!await _isFirestoreAvailable()) {
      return LocalStorageService.getLocalUserByEmail(email);
    }

    final q = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;

    final data = q.docs.first.data();
    if (data['createdAt'] is Timestamp) data['createdAt'] = _toDateTime(data['createdAt']);
    if (data['updatedAt'] is Timestamp) data['updatedAt'] = _toDateTime(data['updatedAt']);
    return data;
  }

  Future<Map<String, dynamic>?> getPatientByCnic(String cnic) async {
    if (cnic.trim().isEmpty) return null;

    if (!await _isFirestoreAvailable()) {
      return LocalStorageService.getLocalPatientByCnic(cnic);
    }

    final doc = await _db.collection('patients').doc(cnic).get();
    if (!doc.exists) return null;

    final data = doc.data()!;
    if (data['dob'] != null) data['dob'] = _toDateTime(data['dob']);
    return data;
  }

  Stream<List<Map<String, dynamic>>> streamPatientsByBranch(String branchId) async* {
    if (!await _isFirestoreAvailable()) {
      yield LocalStorageService.getAllLocalPatients(branchId: branchId);
      return;
    }

    yield* _db
        .collection('branches')
        .doc(branchId)
        .collection('patients')
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              if (data['dob'] != null) data['dob'] = _toDateTime(data['dob']);
              return data;
            }).toList());
  }

  Future<List<Patient>> getAllPatientsForBranch(String branchId) async {
    if (!await _isFirestoreAvailable()) {
      return LocalStorageService.getAllLocalPatients(branchId: branchId)
          .map((map) => Patient.fromMap(map))
          .toList();
    }

    final snapshot = await _db
        .collection('branches')
        .doc(branchId)
        .collection('patients')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      if (data['dob'] != null) data['dob'] = _toDateTime(data['dob']);
      return Patient.fromMap(data);
    }).toList();
  }

  Future<List<Token>> getTodayTokensForBranch(String branchId) async {
    final String todayKey = DateFormat('ddMMyy').format(DateTime.now());

    if (!await _isFirestoreAvailable()) {
      return LocalStorageService.getLocalEntries(branchId)
          .where((e) => (e['dateKey'] as String?) == todayKey)
          .map((map) => Token.fromMap(map))
          .toList();
    }

    final snapshot = await _db
        .collection('branches')
        .doc(branchId)
        .collection('serials')
        .doc(todayKey)
        .collection('zakat')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      if (data['timestamp'] != null) data['timestamp'] = _toDateTime(data['timestamp']);
      return Token.fromMap(data);
    }).toList();
  }

  Stream<List<Map<String, dynamic>>> streamEntriesByBranch(String branchId) async* {
    if (!await _isFirestoreAvailable()) {
      yield LocalStorageService.getLocalEntries(branchId);
      return;
    }

    yield* _db
        .collection('branches')
        .doc(branchId)
        .collection('serials')
        .snapshots()
        .map((s) => s.docs.map((d) {
              final data = d.data();
              if (data['timestamp'] != null) data['timestamp'] = _toDateTime(data['timestamp']);
              return data;
            }).toList());
  }

  Future<void> savePrescription({
    required String branchId,
    required Map<String, dynamic> prescriptionData,
  }) async {
    final id = prescriptionData['id']?.toString()?.trim();
    if (id == null || id.isEmpty) {
      print('ERROR: Cannot save prescription — missing or empty ID');
      return;
    }

    final sanitized = LocalStorageService.sanitize(prescriptionData);

    print('Saving prescription locally → ID: $id');

    await LocalStorageService.saveLocalPrescription(sanitized);

    RealtimeManager().sendMessage(
      RealtimeEvents.payload(
        type: RealtimeEvents.savePrescription,
        data: {
          'branchId': branchId,
          'serial': id,
          'data': sanitized,
        },
      ),
    );

    await LocalStorageService.enqueueSync({
      'type': 'save_prescription',
      'branchId': branchId,
      'serial': id,
      'data': sanitized,
    });

    print('Prescription enqueued → ID: $id');

    SyncService().triggerUpload();
  }
}