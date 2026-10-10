import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_purge_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('purgePhantomUnknownTokens purges synthetic tokens and keeps genuine patients', () async {
    final eBox = Hive.box(LocalStorageService.entriesBox);
    final today = LocalStorageService.getTodayDateKey();

    // 1. Genuine patient #1
    await eBox.put('$today-SADD-001', {
      'serial': '$today-SADD-001',
      'dateKey': today,
      'patientName': 'Muhammad Ali',
      'patientCnic': '4210112345671',
      'dispensaryTag': 'SADD',
      'status': 'completed',
    });

    // 2. Genuine patient #2
    await eBox.put('$today-SADD-002', {
      'serial': '$today-SADD-002',
      'dateKey': today,
      'patientName': 'Fatima Bibi',
      'patientCnic': '4210176543212',
      'dispensaryTag': 'SADD',
      'status': 'completed',
    });

    // 3. Phantom synthetic entries (like #100, #101)
    await eBox.put('$today-SADD-100', {
      'serial': '$today-SADD-100',
      'dateKey': today,
      'patientName': 'Unknown Patient',
      'patientCnic': 'unknown_cnic_1791359728673',
      'dispensaryTag': 'SADD',
      'status': 'completed',
    });
    await eBox.put('$today-SADD-101', {
      'serial': '$today-SADD-101',
      'dateKey': today,
      'patientName': 'Unknown Patient',
      'patientCnic': 'unknown_cnic_1791359728999',
      'dispensaryTag': 'SADD',
      'status': 'completed',
    });

    expect(eBox.length, equals(4));

    // Run purge
    final purged = await LocalStorageService.purgePhantomUnknownTokens('karachi');
    expect(purged, equals(2));
    expect(eBox.length, equals(2));

    // Genuine patients remain
    expect(eBox.get('$today-SADD-001')['patientName'], equals('Muhammad Ali'));
    expect(eBox.get('$today-SADD-002')['patientName'], equals('Fatima Bibi'));

    // Phantoms are gone
    expect(eBox.get('$today-SADD-100'), isNull);
    expect(eBox.get('$today-SADD-101'), isNull);

    // Counter reset
    final counterBox = Hive.box('app_settings');
    final counterVal = counterBox.get('counter_karachi_${today}_SADD');
    expect(counterVal, equals(2));
  });
}
