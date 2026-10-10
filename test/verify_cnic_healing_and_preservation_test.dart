import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gmwf_cnic_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(LocalStorageService.patientsBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('healAndRestorePatientCnics restores genuine CNICs for patients with corrupted unknown_cnic tokens', () async {
    final pBox = Hive.box(LocalStorageService.patientsBox);
    final eBox = Hive.box(LocalStorageService.entriesBox);

    // Register genuine patients in patientsBox
    await pBox.put('4210100000011', {
      'name': 'Test Patient A',
      'cnic': '42101-0000001-1',
      'id': '4210100000011',
      'phone': '03000000001',
    });

    await pBox.put('4210100000022', {
      'name': 'Test Patient B',
      'cnic': '42101-0000002-2',
      'id': '4210100000022',
    });

    await pBox.put('4210100000033', {
      'name': 'Test Patient C',
      'cnic': '42101-0000003-3',
      'id': '4210100000033',
    });

    await pBox.put('4210100000044_child_sara', {
      'name': 'Sara',
      'guardianCnic': '42101-0000004-4',
      'id': '4210100000044_child_sara',
    });

    await pBox.put('4210100000055', {
      'name': 'Kiran Das',
      'cnic': '42101-0000005-5',
      'id': '4210100000055',
    });

    // Simulate corrupted tokens in entriesBox (like in the screenshot)
    await eBox.put('karachi-071026-SADD-009', {
      'serial': '071026-SADD-009',
      'patientName': 'Test Patient A',
      'patientCnic': 'unknown_cnic_1791364760984',
      'cnic': 'unknown_cnic_1791364760984',
      'prescription': {
        'patientName': 'Test Patient A',
        'patientCnic': 'unknown_cnic_1791364760984',
      },
    });

    await eBox.put('karachi-071026-SADD-015', {
      'serial': '071026-SADD-015',
      'patientName': 'Test Patient B',
      'patientCnic': 'unknown_cnic_1791364770856',
      'cnic': 'unknown_cnic_1791364770856',
    });

    await eBox.put('karachi-071026-SADD-061', {
      'serial': '071026-SADD-061',
      'patientName': 'Sara',
      'patientCnic': 'unknown_cnic_1791361110403',
      'cnic': 'unknown_cnic_1791361110403',
    });

    await eBox.put('karachi-071026-SADD-010', {
      'serial': '071026-SADD-010',
      'patientName': 'Keeran',
      'patientCnic': 'unknown_cnic_1791364760987',
      'cnic': 'unknown_cnic_1791364760987',
    });

    await eBox.put('karachi-071026-SADD-076', {
      'serial': '071026-SADD-076',
      'patientName': 'Test Patient C',
      'patientCnic': '',
      'cnic': '-',
    });

    // Execute healing
    final healedCount = await LocalStorageService.healAndRestorePatientCnics();
    expect(healedCount, greaterThanOrEqualTo(5));

    // Verify Patient A's real CNIC restored
    final fakhriya = Map<String, dynamic>.from(eBox.get('karachi-071026-SADD-009'));
    expect(fakhriya['patientCnic'], '42101-0000001-1');
    expect(fakhriya['cnic'], '42101-0000001-1');
    expect(fakhriya['prescription']['patientCnic'], '42101-0000001-1');

    // Verify Patient B's real CNIC restored
    final mansha = Map<String, dynamic>.from(eBox.get('karachi-071026-SADD-015'));
    expect(mansha['patientCnic'], '42101-0000002-2');
    expect(mansha['cnic'], '42101-0000002-2');

    // Verify Sara's real guardian CNIC restored
    final dua = Map<String, dynamic>.from(eBox.get('karachi-071026-SADD-061'));
    expect(dua['patientCnic'], '42101-0000004-4');
    expect(dua['guardianCnic'], '42101-0000004-4');

    // Verify Keeran's real CNIC restored
    final jeevan = Map<String, dynamic>.from(eBox.get('karachi-071026-SADD-010'));
    expect(jeevan['patientCnic'], '42101-0000005-5');

    // Verify Patient C's real CNIC restored
    final farooq = Map<String, dynamic>.from(eBox.get('karachi-071026-SADD-076'));
    expect(farooq['patientCnic'], '42101-0000003-3');
  });

  test('saveLocalPrescription NEVER overwrites an existing legitimate CNIC with synthetic fallback', () async {
    final eBox = Hive.box(LocalStorageService.entriesBox);

    // Initial valid token issued at desk
    await eBox.put('karachi-071026-SADD-005', {
      'serial': '071026-SADD-005',
      'branchId': 'karachi',
      'patientName': 'Test Patient',
      'patientCnic': '42301-1234567-1',
      'cnic': '42301-1234567-1',
      'status': 'waiting',
    });

    // Doctor prescribes, but prescription map has NO CNIC field
    await LocalStorageService.saveLocalPrescription({
      'serial': '071026-SADD-005',
      'branchId': 'karachi',
      'patientName': 'Test Patient',
      'doctorName': 'Dr. Test',
      'medicines': [{'name': 'Panadol', 'quantity': 10}],
      // Notice: NO cnic, patientCnic is omitted!
    });

    final updated = Map<String, dynamic>.from(eBox.get('karachi-071026-SADD-005'));
    // Must STILL have the real CNIC, NOT unknown_cnic_!
    expect(updated['patientCnic'], '42301-1234567-1');
    expect(updated['cnic'], '42301-1234567-1');
    expect(updated['prescription']['patientCnic'], '42301-1234567-1');
    expect(updated['status'], 'completed');
  });
}
