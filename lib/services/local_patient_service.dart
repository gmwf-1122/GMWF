// lib/services/local_patient_service.dart
import '../models/patient.dart';
import 'local_storage_service.dart';

class LocalPatientService {
  static List<Patient> getAll({String? branchId}) {
    return LocalStorageService.getAllLocalPatients(branchId: branchId)
        .map(Patient.fromMap)
        .toList();
  }

  static Patient? getByCnic(String cnic, {String? branchId}) {
    final map = LocalStorageService.getLocalPatientByCnic(cnic);
    if (map == null) return null;
    if (branchId != null && map['branchId'] != branchId) return null;
    return Patient.fromMap(map);
  }

  static Future<void> save(Patient patient) async {
    await LocalStorageService.saveLocalPatient(patient.toMap());
  }
}