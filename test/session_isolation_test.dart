import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';

/// Morning and evening tokens share numbers (181026M-SADD-005 / 181026E-SADD-005). A lookup
/// for the evening token must never return the morning token's entry or prescription.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_session_isolation_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Map<String, dynamic> morningEntry() => {
        'serial': '181026M-SADD-005',
        'branchId': 'gujrat',
        'dateKey': '181026',
        'session': 'morning',
        'patientName': 'Morning Patient',
        'status': 'completed',
        'prescription': {
          'medicines': [
            {'name': 'Morning Med', 'quantity': 10}
          ],
        },
      };

  test('getLocalEntry does not fall back to another session', () async {
    final box = Hive.box(LocalStorageService.entriesBox);
    await box.put('gujrat-181026M-SADD-005', morningEntry());

    expect(LocalStorageService.getLocalEntry('gujrat', '181026E-SADD-005'), isNull);
    expect(LocalStorageService.getLocalEntry('gujrat', '181026M-SADD-005')?['patientName'], 'Morning Patient');
  });

  test('getLocalEntry uses a letterless v1.6.1 record only for its own session', () async {
    final box = Hive.box(LocalStorageService.entriesBox);
    await box.put('gujrat-181026-SADD-007', {
      'serial': '181026-SADD-007',
      'dateKey': '181026',
      'session': 'morning',
      'patientName': 'Old Morning Patient',
    });
    await box.put('gujrat-181026-SADD-008', {
      'serial': '181026-SADD-008',
      'dateKey': '181026',
      'patientName': 'Old Patient, session unknown',
    });

    expect(LocalStorageService.getLocalEntry('gujrat', '181026M-SADD-007')?['patientName'], 'Old Morning Patient');
    expect(LocalStorageService.getLocalEntry('gujrat', '181026E-SADD-007'), isNull);
    expect(LocalStorageService.getLocalEntry('gujrat', '181026E-SADD-008'), isNull);
    // A letterless lookup (old caller) still finds the record.
    expect(LocalStorageService.getLocalEntry('gujrat', '181026-SADD-008'), isNotNull);
  });

  test('getLocalPrescription does not return the morning prescription for an evening token', () async {
    final box = Hive.box(LocalStorageService.entriesBox);
    await box.put('gujrat-181026M-SADD-005', morningEntry());
    await Hive.box(LocalStorageService.prescriptionsBox).put('181026M-SADD-005', {
      'serial': '181026M-SADD-005',
      'dateKey': '181026',
      'medicines': [
        {'name': 'Morning Med', 'quantity': 10}
      ],
    });

    expect(LocalStorageService.getLocalPrescription('181026E-SADD-005', branchId: 'gujrat'), isNull);
  });

  test('isLetterlessRecordInSession', () {
    expect(LocalStorageService.isLetterlessRecordInSession({'session': 'evening'}, 'E'), isTrue);
    expect(LocalStorageService.isLetterlessRecordInSession({'session': 'morning'}, 'E'), isFalse);
    expect(LocalStorageService.isLetterlessRecordInSession({'sessionLetter': 'e'}, 'E'), isTrue);
    expect(LocalStorageService.isLetterlessRecordInSession({}, 'M'), isFalse);
  });
}
