import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final meds = [
    {'name': 'Nimesulide', 'quantity': 2},
    {'name': 'Brufen', 'quantity': 3},
  ];
  final doctorRx = {
    'serial': '311026M-HAJI-023',
    'prescriptions': meds,
    'diagnosis': 'viral',
    'updatedAt': '2026-10-31T12:16:00',
    'completedAt': '2026-10-31T12:16:00',
  };

  group('preferredPrescription / mayReplacePrescription', () {
    test('a copy without medicines never replaces one with medicines, even if newer', () {
      final empty = {'serial': '311026M-HAJI-023', 'prescriptions': <dynamic>[], 'updatedAt': '2026-10-31T13:00:00'};
      expect(LocalStorageService.mayReplacePrescription(empty, doctorRx), isFalse);
      expect(LocalStorageService.preferredPrescription(empty, doctorRx)!['prescriptions'], meds);
    });

    test('an older copy does not replace a newer one', () {
      final older = {
        'serial': '311026M-HAJI-023',
        'prescriptions': [{'name': 'Panadol', 'quantity': 1}],
        'updatedAt': '2026-10-31T12:00:00',
      };
      expect(LocalStorageService.mayReplacePrescription(older, doctorRx), isFalse);
    });

    test("a newer edit with medicines replaces the doctor's earlier one", () {
      final newer = {
        'serial': '311026m-haji-023', // the doctor sends it lower-case
        'prescriptions': [...meds, {'name': 'Danzen DS', 'quantity': 2}],
        'updatedAt': '2026-10-31T12:30:00',
      };
      expect(LocalStorageService.mayReplacePrescription(newer, doctorRx), isTrue);
    });

    test('anything replaces nothing', () {
      expect(LocalStorageService.mayReplacePrescription(doctorRx, null), isTrue);
      expect(LocalStorageService.mayReplacePrescription(doctorRx, <String, dynamic>{}), isTrue);
    });
  });

  group('saveEntryLocal keeps the medicines', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('rx_precedence_');
      Hive.init(dir.path);
      for (final b in [
        LocalStorageService.entriesBox,
        LocalStorageService.prescriptionsBox,
        LocalStorageService.dispensaryBox,
        LocalStorageService.patientsBox,
        LocalStorageService.syncBox,
        'app_settings',
        'app_flags',
        'issued_token_keys',
      ]) {
        await Hive.openBox(b);
      }
    });

    tearDown(() async {
      await Hive.close();
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test("a re-sent token without the prescription does not erase the doctor's medicines", () async {
      const serial = '311026M-HAJI-023';
      final box = Hive.box(LocalStorageService.entriesBox);
      await box.put('karachi-$serial', {
        'serial': serial,
        'branchId': 'karachi',
        'dateKey': '311026',
        'patientName': 'Fizza',
        'patientCnic': '4200000000000',
        'status': 'completed',
        'prescription': doctorRx,
        'prescriptions': meds,
        'medicines': meds,
      });

      // The receptionist PC re-pushes its copy of the token on reconnect: no medicines, and an
      // embedded prescription that lost them.
      await LocalStorageService.saveEntryLocal('karachi', serial, {
        'serial': serial,
        'branchId': 'karachi',
        'dateKey': '311026',
        'patientName': 'Fizza',
        'patientCnic': '4200000000000',
        'status': 'completed',
        'prescription': {'serial': serial, 'diagnosis': 'viral', 'updatedAt': '2026-10-31T12:40:00'},
        'medicines': <dynamic>[],
      });

      final stored = box.get('karachi-$serial') as Map;
      final rx = stored['prescription'] as Map;
      expect(rx['prescriptions'], meds);
      expect(stored['medicines'], meds);
      expect(stored['prescriptions'], meds);
    });
  });
}
