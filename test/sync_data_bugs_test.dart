import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/queue_self_healing_service.dart';
import 'package:gmwf/services/sync_service.dart';

/// Regression tests for the 2026-10-17 data bugs: token dateKeys rewritten to ISO,
/// phantom prune deleting dispense updates, and food tokens counted twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_sync_bugs_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Map<String, dynamic> serialAction(String type, {String? dateKey, String serial = 'GRT-150926-007'}) => {
        'type': type,
        'branchId': 'gujrat',
        'campId': 'main',
        'serial': serial,
        if (dateKey != null) 'dateKey': dateKey,
        'data': {'serial': serial, 'branchId': 'gujrat', 'campId': 'main'},
      };

  group('healAction dateKey', () {
    test('keeps a valid ddMMyy key on every serial type', () {
      for (final type in ['save_entry', 'save_prescription', 'update_serial_status']) {
        final a = serialAction(type, dateKey: '150926');
        QueueSelfHealingService.healAction(a, fallbackBranch: 'gujrat');
        expect(a['dateKey'], '150926', reason: type);
      }
    });

    test('derives a missing serial dateKey from the serial', () {
      final a = serialAction('update_serial_status');
      QueueSelfHealingService.healAction(a, fallbackBranch: 'gujrat');
      expect(a['dateKey'], '150926');
      expect((a['data'] as Map)['dateKey'], '150926');
    });

    test('reads datePart before deciding a key is missing', () {
      final a = serialAction('save_entry', serial: 'TEMP-ABC')..['datePart'] = '140926';
      QueueSelfHealingService.healAction(a, fallbackBranch: 'gujrat');
      expect(a['dateKey'], isNull); // executor reads datePart; nothing overwrites it
      expect(a['datePart'], '140926');
    });

    test('repairs an ISO key an older healer wrote onto a serial action', () {
      final a = serialAction('save_entry', dateKey: '2026-10-17');
      QueueSelfHealingService.healAction(a, fallbackBranch: 'gujrat');
      expect(a['dateKey'], '150926');
    });

    test('falls back to today ddMMyy when the serial has no date', () {
      final a = serialAction('save_entry', serial: 'TEMP-ABC');
      QueueSelfHealingService.healAction(a, fallbackBranch: 'gujrat');
      expect(a['dateKey'], DateFormat('ddMMyy').format(DateTime.now()));
    });

    test('leaves non-serial keys alone and only fills a missing one', () {
      final iso = {'type': 'save_dasterkhwan_tokens', 'branchId': 'gujrat', 'dateKey': '2026-09-15', 'data': {}};
      QueueSelfHealingService.healAction(iso, fallbackBranch: 'gujrat');
      expect(iso['dateKey'], '2026-09-15');

      final month = {'type': 'save_madrassa_fee', 'branchId': 'gujrat', 'dateKey': '2026-09', 'data': {}};
      QueueSelfHealingService.healAction(month, fallbackBranch: 'gujrat');
      expect(month['dateKey'], '2026-09');

      final missing = {'type': 'save_expense', 'branchId': 'gujrat', 'data': {}};
      QueueSelfHealingService.healAction(missing, fallbackBranch: 'gujrat');
      expect(missing['dateKey'], DateTime.now().toIso8601String().substring(0, 10));
    });

    test('renames legacy save_kitchen_serve_log items to the handled type', () {
      final a = {
        'type': 'save_kitchen_serve_log',
        'branchId': 'gujrat',
        'dateKey': '2026-09-15',
        'data': {'tokenId': 'dst_gujrat_2026-09-15_3', 'session': 'lunch'},
      };
      expect(QueueSelfHealingService.healAction(a, fallbackBranch: 'gujrat'), isTrue);
      expect(a['type'], 'serve_dasterkhwan_token');
      expect(a['dateKey'], '2026-09-15');
    });

    test('date key validators', () {
      expect(QueueSelfHealingService.isDdMMyyKey('150926'), isTrue);
      expect(QueueSelfHealingService.isDdMMyyKey('991326'), isFalse);
      expect(QueueSelfHealingService.isDdMMyyKey('2026-09-15'), isFalse);
      expect(QueueSelfHealingService.isIsoDateKey('2026-09-15'), isTrue);
      expect(QueueSelfHealingService.isIsoDateKey('150926'), isFalse);
    });
  });

  group('isPhantomQueuedEntry', () {
    test('never prunes standalone dispense / prescription updates', () {
      expect(
        LocalStorageService.isPhantomQueuedEntry({
          'type': 'update_serial_status',
          'serial': 'GRT-150926-007',
          'data': {'dispenseStatus': 'dispensed', 'status': 'completed'},
        }),
        isFalse,
      );
      expect(
        LocalStorageService.isPhantomQueuedEntry({
          'type': 'update_serial_status',
          'serial': 'GRT-150926-007',
          'data': {'patientCnic': 'unknown_cnic_1', 'patientName': 'Unknown Patient'},
        }),
        isFalse,
      );
      expect(
        LocalStorageService.isPhantomQueuedEntry({
          'type': 'save_prescription',
          'serial': 'GRT-150926-007',
          'data': {'patientCnic': 'unknown_cnic_1'},
        }),
        isFalse,
      );
    });

    test('needs an explicit unknown_cnic_ CNIC, not just an empty one', () {
      expect(
        LocalStorageService.isPhantomQueuedEntry({
          'type': 'save_entry',
          'serial': 'GRT-150926-007',
          'data': {'serial': 'GRT-150926-007'},
        }),
        isFalse,
      );
    });

    test('keeps unknown-CNIC entries that carry real work or a real name', () {
      for (final extra in <Map<String, dynamic>>[
        {'status': 'waiting'},
        {'dispenseStatus': 'dispensed'},
        {'prescription': {'medicines': []}},
        {'patientName': 'Muhammad Ali'},
      ]) {
        expect(
          LocalStorageService.isPhantomQueuedEntry({
            'type': 'save_entry',
            'data': {'patientCnic': 'unknown_cnic_1', ...extra},
          }),
          isFalse,
          reason: '$extra',
        );
      }
    });

    test('prunes a bare unknown_cnic_ save_entry', () {
      expect(
        LocalStorageService.isPhantomQueuedEntry({
          'type': 'save_entry',
          'serial': 'GRT-150926-100',
          'data': {'patientCnic': 'unknown_cnic_1791359728673', 'patientName': 'Unknown Patient'},
        }),
        isTrue,
      );
    });

    test('purgeBloatedSyncQueue keeps a standalone dispense update', () async {
      final box = await Hive.openBox(LocalStorageService.syncBox);
      await box.put('dispense', {
        'type': 'update_serial_status',
        'branchId': 'gujrat',
        'serial': 'GRT-150926-007',
        'dateKey': '150926',
        'data': {'dispenseStatus': 'dispensed', 'status': 'completed'},
      });
      await box.put('phantom', {
        'type': 'save_entry',
        'branchId': 'gujrat',
        'serial': 'GRT-150926-100',
        'data': {'patientCnic': 'unknown_cnic_1', 'patientName': 'Unknown Patient'},
      });
      await LocalStorageService.purgeBloatedSyncQueue(force: true);
      expect(box.get('dispense'), isNotNull);
      expect(box.get('phantom'), isNull);
    });
  });

  group('food token ownership', () {
    Map<String, dynamic> token(String id, {String? origin, bool lan = false, bool synced = false}) => {
          'id': id,
          'number': 1,
          'branchId': 'gujrat',
          'dateKey': '2026-09-15',
          if (origin != null) 'originDevice': origin,
          if (lan) 'lanReceived': true,
          'syncStatus': synced ? 'synced' : 'pending',
          'synced': synced,
        };

    test('only the issuing PC owns a token', () {
      expect(SyncService.isFoodTokenOwnedHere(token('a', origin: 'dev_me'), 'dev_me'), isTrue);
      expect(SyncService.isFoodTokenOwnedHere(token('a', origin: 'dev_other'), 'dev_me'), isFalse);
      expect(SyncService.isFoodTokenOwnedHere(token('a', lan: true), 'dev_me'), isFalse);
      expect(SyncService.isFoodTokenOwnedHere(token('a'), 'dev_me'), isTrue); // legacy local
    });

    test('backfill skips synced, foreign, LAN and already-queued tokens', () {
      final picked = SyncService.selectFoodTokensToUpload(
        [
          token('mine', origin: 'dev_me'),
          token('queued', origin: 'dev_me'),
          token('done', origin: 'dev_me', synced: true),
          token('foreign', origin: 'dev_other'),
          token('lan', lan: true),
        ],
        deviceId: 'dev_me',
        queuedActions: [
          {
            'type': 'save_dasterkhwan_tokens',
            'batchId': 'dst_batch_gujrat_2026-09-15_1_1_123',
            'data': {
              'tokens': [
                {'id': 'queued'},
              ],
            },
          },
        ],
      );
      expect(picked.map((t) => t['id']), ['mine']);
    });
  });
}
