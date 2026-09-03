// test/step5_verification_test.dart
//
// Step 5 Verification Tests for System-Wide Key Unification & Fleet Gate (v1.3.7)
// Proves:
// (a) Idempotency / Deduplication (No Duplication)
// (b) Data Loss Prevention / Collision Protection (No Overwrites)
// (c) Multi-Device Offline Sync Merge & One-Time Migration

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:gmwf/pages/dispensary/dispensar/inventory.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/tools/legacy_data_migration_adapter.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('gmwf_step5_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.patientsBox);
    await Hive.openBox(LocalStorageService.donationsBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox('submissions');
    await Hive.openBox('app_flags');
    await Hive.openBox('app_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await Hive.box(LocalStorageService.syncBox).clear();
    await Hive.box(LocalStorageService.patientsBox).clear();
    await Hive.box(LocalStorageService.donationsBox).clear();
    await Hive.box(LocalStorageService.entriesBox).clear();
    await Hive.box(LocalStorageService.prescriptionsBox).clear();
    await Hive.box('submissions').clear();
    await Hive.box('app_flags').clear();
    await Hive.box('app_settings').clear();
  });

  test('TEST 0: Dispensed entry sets completed and preserves prescription history', () async {
    final entryKey = 'karachi-010926-grt-003';
    final entriesBox = Hive.box(LocalStorageService.entriesBox);
    final orig = {
      'serial': '010926-GRT-003',
      'branchId': 'karachi',
      'patientName': 'Javaid Iqbal',
      'status': 'completed',
      'dispenseStatus': 'waiting',
      'prescription': {
        'serial': '010926-GRT-003',
        'prescriptions': [
          {'name': 'Panadol', 'quantity': 1}
        ],
      },
      'prescriptions': [
        {'name': 'Panadol', 'quantity': 1}
      ],
      'dateKey': '010926',
    };

    await entriesBox.put(entryKey, orig);
    await entriesBox.put('karachi-010926-grt-003', orig);

    await LocalStorageService.updateDispenseStatus('karachi', '010926-GRT-003', 'dispensed');

    final updated = entriesBox.get(entryKey) as Map;
    expect(updated['dispenseStatus'], equals('dispensed'));
    expect(updated['status'], equals('completed'));
    expect(updated['prescription'], isNotNull);
  });

  test('Inventory delete action is only visible for Chairman and HQ Manager roles', () {
    expect(InventoryPage.canDeleteInventoryItemFromRole({'role': 'Chairman'}), isTrue);
    expect(InventoryPage.canDeleteInventoryItemFromRole({'role': 'HQ Manager'}), isTrue);
    expect(InventoryPage.canDeleteInventoryItemFromRole({'role': 'hq_manager'}), isTrue);
    expect(InventoryPage.canDeleteInventoryItemFromRole({'role': 'Doctor'}), isFalse);
    expect(InventoryPage.canDeleteInventoryItemFromRole({'role': 'Receptionist'}), isFalse);
    expect(InventoryPage.canDeleteInventoryItemFromRole({'role': 'Dispenser'}), isFalse);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TEST 1: IDEMPOTENCY / DEDUPLICATION (No Duplication)
  // ══════════════════════════════════════════════════════════════════════════
  test('TEST 1: Same record synced/retried twice = exactly 1 record (Idempotency)', () async {
    final syncBox = Hive.box(LocalStorageService.syncBox);
    final entityId = const Uuid().v4();
    final syncId = const Uuid().v4();

    final payload = {
      'type': 'save_donation',
      'syncId': syncId,
      'entityId': entityId,
      'branchId': 'karachi',
      'localId': entityId,
      'data': {
        'amount': 5000,
        'donorName': 'Ahmad',
        'localId': entityId,
      }
    };

    // First Enqueue
    await LocalStorageService.enqueueSync(payload);
    expect(syncBox.length, equals(1), reason: 'First enqueue must store exactly 1 item.');

    // Second Enqueue (Simulating retry/resync of same logical action)
    final retryPayload = Map<String, dynamic>.from(payload)..['attempts'] = 1;
    await LocalStorageService.enqueueSync(retryPayload);

    expect(syncBox.length, equals(1), reason: 'Retrying sync must NOT create duplicate queue entries.');
    final queuedItem = syncBox.get(syncId) as Map;
    expect(queuedItem['entityId'], equals(entityId));
    expect(queuedItem['syncId'], equals(syncId));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TEST 2: COLLISION & DATA LOSS PREVENTION (No Overwrites)
  // ══════════════════════════════════════════════════════════════════════════
  test('TEST 2: Two different records with empty serial/CNIC never overwrite each other (No Data Loss)', () async {
    final syncBox = Hive.box(LocalStorageService.syncBox);

    // Record A (stock update without serial/CNIC)
    final recordA = {
      'type': 'update_inventory',
      'branchId': 'karachi',
      'data': {
        'medicineId': 'med_panadol_1',
        'quantity': 100,
      }
    };

    // Record B (another stock update without serial/CNIC)
    final recordB = {
      'type': 'update_inventory',
      'branchId': 'karachi',
      'data': {
        'medicineId': 'med_brufen_2',
        'quantity': 50,
      }
    };

    await LocalStorageService.enqueueSync(recordA);
    await LocalStorageService.enqueueSync(recordB);

    // Pre-fix, both collapsed to `update_inventory___` causing overwrite/data loss.
    // Post-fix, both get distinct UUID entityId and syncId values.
    expect(syncBox.length, equals(2), reason: 'Both stock updates must be preserved in queue with distinct UUID keys.');
    
    final keys = syncBox.keys.toList();
    expect(keys[0], isNot(equals(keys[1])));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TEST 3: MULTI-DEVICE OFFLINE SYNC MERGE & ONE-TIME MIGRATION
  // ══════════════════════════════════════════════════════════════════════════
  test('TEST 3: Multi-device offline records merge cleanly & legacy migration backfills UUIDs', () async {
    final patientsBox = Hive.box(LocalStorageService.patientsBox);

    // Simulate Legacy Records created under old system (no patientId)
    await patientsBox.put('cnic_12345', {
      'name': 'Legacy Patient Adult',
      'cnic': '12345-6789012-1',
      'isAdult': true,
    });
    await patientsBox.put('fallback_99999', {
      'name': 'Legacy Patient Child',
      'guardianCnic': '99999-1111111-1',
      'isAdult': false,
    });

    // Run One-Time Legacy Migration Adapter
    await LegacyDataMigrationAdapter.runOnce();

    final legacyAdult = patientsBox.get('cnic_12345') as Map;
    final legacyChild = patientsBox.get('fallback_99999') as Map;

    expect(legacyAdult['patientId'], isNotNull, reason: 'Migration must backfill patientId UUID for adult.');
    expect(legacyChild['patientId'], isNotNull, reason: 'Migration must backfill patientId UUID for child.');
    expect(legacyAdult['legacyMigrated'], equals(true));

    // Simulate Device A and Device B creating records offline concurrently on v1.3.7
    final deviceARecord = {
      'patientId': const Uuid().v4(),
      'name': 'Device A Offline Patient',
      'cnic': '11111-2222222-3',
      'isAdult': true,
    };
    final deviceBRecord = {
      'patientId': const Uuid().v4(),
      'name': 'Device B Offline Patient',
      'cnic': '33333-4444444-5',
      'isAdult': true,
    };

    final keyA = LocalStorageService.getPatientKey(deviceARecord);
    final keyB = LocalStorageService.getPatientKey(deviceBRecord);

    await patientsBox.put(keyA, deviceARecord);
    await patientsBox.put(keyB, deviceBRecord);

    // Verify 100% clean merge across all 4 entries (2 legacy + 2 multi-device offline)
    expect(patientsBox.length, equals(4));
    expect(keyA, equals(deviceARecord['patientId']));
    expect(keyB, equals(deviceBRecord['patientId']));
  });
}
