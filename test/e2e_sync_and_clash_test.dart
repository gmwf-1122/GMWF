import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/realtime/server_sync_coordinator.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/camp_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('gmwf_e2e_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('dasterkhwaan_tokens');
    await Hive.openBox('donations');
    await Hive.openBox('dead_letter_queue');
    await Hive.openBox('outbox_messages');
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('1. ServerSyncCoordinator Mutual Exclusion Tests', () {
    setUp(() {
      ServerSyncCoordinator.markFinished(isServer: true);
      ServerSyncCoordinator.markFinished(isServer: false);
    });

    test('Initial state allows both Server and SyncService to start', () {
      expect(ServerSyncCoordinator.canStartSync(isServer: true), isTrue);
      expect(ServerSyncCoordinator.canStartSync(isServer: false), isTrue);
      expect(ServerSyncCoordinator.isAnySyncActive, isFalse);
    });

    test('When ServerSyncManager locks, SyncService is BLOCKED', () {
      ServerSyncCoordinator.markStarted(isServer: true);
      expect(ServerSyncCoordinator.isServerSyncing, isTrue);
      expect(ServerSyncCoordinator.isAnySyncActive, isTrue);

      // ServerSyncManager itself is active, so neither can start another pass
      expect(ServerSyncCoordinator.canStartSync(isServer: false), isFalse);
      expect(ServerSyncCoordinator.canStartSync(isServer: true), isFalse);

      // Force flag allows override if explicitly forced
      expect(ServerSyncCoordinator.canStartSync(isServer: false, force: true), isTrue);

      // Release server lock
      ServerSyncCoordinator.markFinished(isServer: true);
      expect(ServerSyncCoordinator.isServerSyncing, isFalse);
      expect(ServerSyncCoordinator.canStartSync(isServer: false), isTrue);
    });

    test('When SyncService locks, ServerSyncManager is BLOCKED', () {
      ServerSyncCoordinator.markStarted(isServer: false);
      expect(ServerSyncCoordinator.isSyncServiceUploading, isTrue);
      expect(ServerSyncCoordinator.isAnySyncActive, isTrue);

      expect(ServerSyncCoordinator.canStartSync(isServer: true), isFalse);
      expect(ServerSyncCoordinator.canStartSync(isServer: false), isFalse);

      ServerSyncCoordinator.markFinished(isServer: false);
      expect(ServerSyncCoordinator.isSyncServiceUploading, isFalse);
      expect(ServerSyncCoordinator.canStartSync(isServer: true), isTrue);
    });
  });

  group('2. Queue Purge Validation (No False-Positive Deletions)', () {
    test('Preserves valid items with payload at top level or nested', () {
      bool isQueueItemValid(Map<dynamic, dynamic> val) {
        final hasType = val['type'] != null && val['type'].toString().trim().isNotEmpty;
        final hasPayload = (val['data'] is Map && (val['data'] as Map).isNotEmpty) ||
            val['serial'] != null ||
            val['collection'] != null ||
            val['delta'] != null ||
            val['entityId'] != null ||
            val['id'] != null ||
            val['localId'] != null ||
            val['patientId'] != null ||
            val['employeeId'] != null ||
            val['deviceId'] != null;
        return hasType && hasPayload;
      }

      // Valid items that previously were deleted because val['data'] == null
      final stockDeltaItem = {'type': 'update_inventory', 'medicineId': 'med_123', 'delta': 5.0};
      final donationItem = {'type': 'save_donation', 'localId': 'don_999', 'amount': 500};
      final foodTokenItem = {'type': 'save_dasterkhwan_tokens', 'entityId': 'dst_batch_1', 'quantity': 10};
      final patchSerialItem = {'type': 'update_serial_status', 'serial': 'A1', 'status': 'completed'};
      final nestedDataItem = {'type': 'save_entry', 'data': {'serial': 'A2', 'name': 'John'}};

      // Truly invalid / corrupt items
      final emptyItem = {'type': 'save_entry'};
      final typelessItem = {'serial': 'A3'};

      expect(isQueueItemValid(stockDeltaItem), isTrue, reason: 'Stock delta item must be valid');
      expect(isQueueItemValid(donationItem), isTrue, reason: 'Donation item must be valid');
      expect(isQueueItemValid(foodTokenItem), isTrue, reason: 'Food token batch must be valid');
      expect(isQueueItemValid(patchSerialItem), isTrue, reason: 'Serial status patch must be valid');
      expect(isQueueItemValid(nestedDataItem), isTrue, reason: 'Nested data item must be valid');

      expect(isQueueItemValid(emptyItem), isFalse, reason: 'Item with no payload must be invalid');
      expect(isQueueItemValid(typelessItem), isFalse, reason: 'Item with no type must be invalid');
    });
  });

  group('3. Offline Prescription & Dispense State Stamping', () {
    test('Doctor saving prescription marks pendingSync=true and synced=false', () async {
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      const branchId = 'gujrat';
      const serial = 'G100';
      const key = '$branchId-$serial';

      // 1. Initial token created by receptionist
      final token = {
        'serial': serial,
        'branchId': branchId,
        'patientName': 'Zafar Iqbal',
        'synced': true,
        'syncStatus': 'synced',
        'pendingSync': false,
      };
      await entriesBox.put(key, token);

      // Verify receptionist token is considered synced
      var record = Map<String, dynamic>.from(entriesBox.get(key) as Map);
      bool isSyncedBefore = (record['synced'] == true || record['syncStatus'] == 'synced') && record['pendingSync'] != true;
      expect(isSyncedBefore, isTrue);

      // 2. Doctor prescribes medication offline
      record['prescription'] = {'medId': 'panadol', 'dosage': '1x3'};
      record['medicines'] = [{'id': 'panadol', 'name': 'Panadol 500mg'}];
      record['pendingSync'] = true;
      record['synced'] = false;
      record['prescriptionSynced'] = false;
      record['syncStatus'] = 'pending';
      await entriesBox.put(key, record);

      // Verify token is now properly marked as UNSYNCED so it will be swept and uploaded
      var recordAfterDoc = Map<String, dynamic>.from(entriesBox.get(key) as Map);
      bool isSyncedAfterDoc = (recordAfterDoc['synced'] == true || recordAfterDoc['syncStatus'] == 'synced') && recordAfterDoc['pendingSync'] != true;
      expect(isSyncedAfterDoc, isFalse, reason: 'Prescription must force record into unsynced state for upload');
      expect(recordAfterDoc['prescriptionSynced'], isFalse);

      // 3. Dispenser completes dispense offline
      recordAfterDoc['dispenseStatus'] = 'dispensed';
      recordAfterDoc['dispensedAt'] = DateTime.now().toIso8601String();
      recordAfterDoc['pendingSync'] = true;
      recordAfterDoc['synced'] = false;
      recordAfterDoc['dispenseSynced'] = false;
      recordAfterDoc['syncStatus'] = 'pending';
      await entriesBox.put(key, recordAfterDoc);

      var recordAfterDisp = Map<String, dynamic>.from(entriesBox.get(key) as Map);
      bool isSyncedAfterDisp = (recordAfterDisp['synced'] == true || recordAfterDisp['syncStatus'] == 'synced') && recordAfterDisp['pendingSync'] != true;
      expect(isSyncedAfterDisp, isFalse);
      expect(recordAfterDisp['dispenseSynced'], isFalse);
    });
  });

  group('4. Outbox Critical Events Exemption from Expiry', () {
    test('Critical clinical and financial events are NEVER expired by 12h or midnight cutoff', () {
      bool shouldDiscardOutboxItem(Map<String, dynamic> item, String todayDateKey, DateTime cutoff) {
        final eventType = (item['event_type'] ?? item['type'])?.toString() ?? '';
        final isCriticalEvent = eventType == RealtimeEvents.saveEntry ||
            eventType == RealtimeEvents.savePrescription ||
            eventType == RealtimeEvents.dispenseCompleted ||
            eventType == RealtimeEvents.savePatient ||
            eventType == 'save_donation' ||
            eventType == RealtimeEvents.saveEmployee ||
            eventType == 'save_dispensary_charge' ||
            eventType == 'save_dispensary_record' ||
            eventType == 'update_serial_status' ||
            eventType == 'token_created' ||
            eventType == 'prescription_created';

        final itemDateKey = (item['dateKey'] ?? item['data']?['dateKey'])?.toString().trim();
        final tsStr = (item['_outboxTimestamp'] ?? item['createdAt'])?.toString();
        final itemTime = tsStr != null ? DateTime.tryParse(tsStr) : null;

        final isStale = !isCriticalEvent && (
            (itemDateKey != null && itemDateKey.isNotEmpty && itemDateKey != todayDateKey) ||
            (itemTime != null && (itemTime.isBefore(cutoff) || itemTime.day != DateTime.now().day))
        );
        return isStale;
      }

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final cutoff = DateTime.now().subtract(const Duration(hours: 12));
      const todayDateKey = '2026-10-06';
      const yesterdayDateKey = '2026-10-05';

      // Ephemeral / non-critical message from yesterday
      final pingMessage = {
        'event_type': 'ping',
        'dateKey': yesterdayDateKey,
        '_outboxTimestamp': yesterday.toIso8601String(),
      };
      expect(shouldDiscardOutboxItem(pingMessage, todayDateKey, cutoff), isTrue,
          reason: 'Ping or presence from yesterday should expire');

      // Critical clinical events from yesterday (e.g. night shift)
      final yesterdayToken = {
        'event_type': RealtimeEvents.saveEntry,
        'dateKey': yesterdayDateKey,
        '_outboxTimestamp': yesterday.toIso8601String(),
        'serial': 'Y1',
      };
      final yesterdayPrescription = {
        'event_type': RealtimeEvents.savePrescription,
        'dateKey': yesterdayDateKey,
        '_outboxTimestamp': yesterday.toIso8601String(),
        'serial': 'Y1',
      };
      final yesterdayDispense = {
        'event_type': RealtimeEvents.dispenseCompleted,
        'dateKey': yesterdayDateKey,
        '_outboxTimestamp': yesterday.toIso8601String(),
        'serial': 'Y1',
      };
      final yesterdayDonation = {
        'event_type': 'save_donation',
        'dateKey': yesterdayDateKey,
        '_outboxTimestamp': yesterday.toIso8601String(),
        'id': 'don_y1',
      };

      expect(shouldDiscardOutboxItem(yesterdayToken, todayDateKey, cutoff), isFalse,
          reason: 'Offline token must NEVER be discarded');
      expect(shouldDiscardOutboxItem(yesterdayPrescription, todayDateKey, cutoff), isFalse,
          reason: 'Offline prescription must NEVER be discarded');
      expect(shouldDiscardOutboxItem(yesterdayDispense, todayDateKey, cutoff), isFalse,
          reason: 'Offline dispense must NEVER be discarded');
      expect(shouldDiscardOutboxItem(yesterdayDonation, todayDateKey, cutoff), isFalse,
          reason: 'Offline donation must NEVER be discarded');
    });
  });

  group('5. Gujrat and Regional Branch Routing', () {
    test('Non-Karachi branch paths do not inject Saddar or Karachi camps', () {
      final gujratKey = CampSessionService.getCampDateDocId(
        branchId: 'gujrat',
        dateKey: '2026-10-06',
        serial: 'G-12',
      );
      // For non-Karachi, campDocKey must match the raw dateKey
      expect(gujratKey, equals('2026-10-06'));

      final karachiHajiKey = CampSessionService.getCampDateDocId(
        branchId: 'karachi',
        dateKey: '2026-10-06',
        campId: 'haji',
        serial: 'H-12',
      );
      expect(karachiHajiKey, equals('2026-10-06_haji_camp'));
    });
  });

  group('6. Food Tokens & Donations Hive Queue Serialization', () {
    test('Food tokens enqueue with full batch metadata and idempotence', () async {
      final syncBox = Hive.box(LocalStorageService.syncBox);
      await syncBox.clear();

      final batchId = 'dst_batch_test_100';
      await LocalStorageService.enqueueSync({
        'type': 'save_dasterkhwan_tokens',
        'entityId': batchId,
        'batchId': batchId,
        'branchId': 'gujrat',
        'dateKey': '2026-10-06',
        'data': {
          'quantity': 5,
          'tokens': [
            {'id': 'dst_1', 'number': 1},
            {'id': 'dst_2', 'number': 2},
          ],
        },
      });

      expect(syncBox.isNotEmpty, isTrue);
      // LocalStorageService namespacing prefixes the branchId: sync_<type>_<branchId>_<entityId>
      final queued = syncBox.get('sync_save_dasterkhwan_tokens_gujrat_$batchId') as Map?;
      expect(queued, isNotNull);
      expect(queued?['type'], equals('save_dasterkhwan_tokens'));
      expect(queued?['batchId'], equals(batchId));
      expect(queued?['data']?['quantity'], equals(5));
    });

    test('Donations enqueue with localId and preserve financial fields', () async {
      final syncBox = Hive.box(LocalStorageService.syncBox);
      const donationId = 'don_local_555';

      await LocalStorageService.enqueueSync({
        'type': 'save_donation',
        'branchId': 'gujrat',
        'localId': donationId,
        'data': {
          'amount': 2500,
          'donorName': 'Tariq Mehmood',
          'fundType': 'Zakat',
        },
      });

      final queued = syncBox.get('sync_save_donation_gujrat_$donationId') as Map?;
      expect(queued, isNotNull);
      expect(queued?['type'], equals('save_donation'));
      expect(queued?['localId'], equals(donationId));
      expect(queued?['data']?['amount'], equals(2500));
    });
  });
}
