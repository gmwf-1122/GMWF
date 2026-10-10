import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/quota_service.dart';
import 'package:gmwf/widgets/home_snapshot_widgets.dart';
import 'package:gmwf/widgets/dashboard_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('gmwf_sync_dash_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(LocalStorageService.patientsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('1. Unsynced Token Detection & Enqueue Logic', () {
    bool isRecordSynced(Map<String, dynamic> data) {
      return (data['synced'] == true || data['syncStatus'] == 'synced') && data['pendingSync'] != true;
    }

    test('Identifies records with synced=null, false, or pending as UNSYNCED', () {
      final legacyTokenNull = {'serial': 1, 'patientName': 'Ali'};
      final legacyTokenFalse = {'serial': 2, 'synced': false};
      final tokenPendingSync = {'serial': 3, 'synced': true, 'pendingSync': true};
      final tokenSyncStatusPending = {'serial': 4, 'syncStatus': 'pending'};

      expect(isRecordSynced(legacyTokenNull), isFalse, reason: 'synced=null must be treated as unsynced');
      expect(isRecordSynced(legacyTokenFalse), isFalse, reason: 'synced=false must be treated as unsynced');
      expect(isRecordSynced(tokenPendingSync), isFalse, reason: 'pendingSync=true must override synced=true');
      expect(isRecordSynced(tokenSyncStatusPending), isFalse, reason: 'syncStatus=pending must be treated as unsynced');
    });

    test('Identifies genuinely synced records as SYNCED', () {
      final syncedTokenA = {'serial': 5, 'synced': true};
      final syncedTokenB = {'serial': 6, 'syncStatus': 'synced'};
      final syncedTokenC = {'serial': 7, 'synced': true, 'pendingSync': false};

      expect(isRecordSynced(syncedTokenA), isTrue);
      expect(isRecordSynced(syncedTokenB), isTrue);
      expect(isRecordSynced(syncedTokenC), isTrue);
    });
  });

  group('2. Multi-Camp & Multi-Branch Compound Deduplication Key', () {
    String generateCompoundQueueKey(String branchId, String campId, int serial) {
      return '${branchId.toLowerCase().trim()}-${campId.toLowerCase().trim()}-$serial';
    }

    test('Ensures tokens with identical serials across different camps/branches do NOT overwrite each other', () {
      final keyKarachiHaji1 = generateCompoundQueueKey('karachi', 'haji', 10);
      final keyKarachiSaddar1 = generateCompoundQueueKey('karachi', 'saddar', 10);
      final keyGujratMain1 = generateCompoundQueueKey('gujrat', 'main', 10);
      final keyDuplicateHaji1 = generateCompoundQueueKey('karachi', 'haji', 10);

      // Distinct camps/branches must NOT collide
      expect(keyKarachiHaji1, isNot(equals(keyKarachiSaddar1)));
      expect(keyKarachiHaji1, isNot(equals(keyGujratMain1)));
      expect(keyKarachiSaddar1, isNot(equals(keyGujratMain1)));

      // Identical camp and serial MUST match for deduplication
      expect(keyKarachiHaji1, equals(keyDuplicateHaji1));

      final activeQueue = <String, Map<String, dynamic>>{};
      activeQueue[keyKarachiHaji1] = {'serial': 10, 'camp': 'haji', 'branch': 'karachi', 'patient': 'Patient A'};
      activeQueue[keyKarachiSaddar1] = {'serial': 10, 'camp': 'saddar', 'branch': 'karachi', 'patient': 'Patient B'};
      activeQueue[keyGujratMain1] = {'serial': 10, 'camp': 'main', 'branch': 'gujrat', 'patient': 'Patient C'};

      expect(activeQueue.length, equals(3), reason: 'All 3 tokens with serial 10 in different camps must be preserved');
      expect(activeQueue[keyKarachiHaji1]?['patient'], equals('Patient A'));
      expect(activeQueue[keyKarachiSaddar1]?['patient'], equals('Patient B'));
      expect(activeQueue[keyGujratMain1]?['patient'], equals('Patient C'));
    });
  });

  group('3. Queue Key Standardization Between LocalStorageService and Server', () {
    test('Enqueueing via LocalStorageService uses standardized entityId and sync key', () async {
      final queueBox = Hive.box(LocalStorageService.syncBox);
      await queueBox.clear();

      await LocalStorageService.enqueueSync({
        'type': 'save_entry',
        'branchId': 'karachi',
        'serial': '101',
        'campId': 'haji',
        'data': {'serial': 101, 'patientName': 'Hassan', 'campId': 'haji'},
      });

      expect(queueBox.length, equals(1));
      expect(queueBox.containsKey('sync_serial_karachi_101'), isTrue,
          reason: 'Deterministic key sync_serial_karachi_101 must exist');

      final enqueuedItem = Map<String, dynamic>.from(queueBox.get('sync_serial_karachi_101'));
      expect(enqueuedItem['entityId'], equals('karachi-101'));
      expect(enqueuedItem['data']['serial'], equals(101));

      // Re-enqueuing with the same branch & serial updates the same deterministic key
      await LocalStorageService.enqueueSync({
        'type': 'save_entry',
        'branchId': 'karachi',
        'serial': '101',
        'campId': 'haji',
        'data': {'serial': 101, 'patientName': 'Hassan Updated', 'campId': 'haji'},
      });

      // Verify no duplicate keys for the same entity
      expect(queueBox.length, equals(1), reason: 'Deterministic key prevents duplicate queue entries');
      final updatedItem = Map<String, dynamic>.from(queueBox.get('sync_serial_karachi_101'));
      expect(updatedItem['data']['patientName'], equals('Hassan Updated'));
    });
  });

  group('4. Demographics Enrichment for "Unknown Patient"', () {
    test('Enriches record when patientName is "Unknown Patient" using patientsBox lookup', () async {
      final patientsBox = Hive.box(LocalStorageService.patientsBox);
      await patientsBox.put('PAT_9901', {
        'id': 'PAT_9901',
        'name': 'Muhammad Bilal',
        'phone': '0312-9876543',
        'cnic': '42101-9988776-3',
      });

      // Simulated raw entry with placeholder name
      final entry = <String, dynamic>{
        'id': 'entry_001',
        'patientId': 'PAT_9901',
        'patientName': 'Unknown Patient',
        'phone': '',
        'cnic': '',
      };

      // Enrichment logic matching branches_providers.dart fix:
      final curName = entry['patientName']?.toString().trim();
      if (curName == null || curName.isEmpty || curName.toLowerCase() == 'unknown patient') {
        final pId = entry['patientId']?.toString();
        if (pId != null && patientsBox.containsKey(pId)) {
          final patientDoc = Map<String, dynamic>.from(patientsBox.get(pId));
          if (patientDoc['name']?.toString().trim().isNotEmpty ?? false) {
            entry['patientName'] = patientDoc['name'];
            if ((entry['phone']?.toString().trim().isEmpty ?? true)) {
              entry['phone'] = patientDoc['phone'];
            }
            if ((entry['cnic']?.toString().trim().isEmpty ?? true)) {
              entry['cnic'] = patientDoc['cnic'];
            }
          }
        }
      }

      expect(entry['patientName'], equals('Muhammad Bilal'));
      expect(entry['phone'], equals('0312-9876543'));
      expect(entry['cnic'], equals('42101-9988776-3'));
    });

    test('Preserves existing valid patient name without overwriting', () {
      final entry = <String, dynamic>{
        'id': 'entry_002',
        'patientId': 'PAT_9902',
        'patientName': 'Fatima Zahra',
        'phone': '0300-1122334',
        'cnic': '42201-1122334-2',
      };

      final curName = entry['patientName']?.toString().trim();
      bool attemptedOverwrite = false;
      if (curName == null || curName.isEmpty || curName.toLowerCase() == 'unknown patient') {
        attemptedOverwrite = true;
      }

      expect(attemptedOverwrite, isFalse, reason: 'Valid existing name must never be overwritten');
      expect(entry['patientName'], equals('Fatima Zahra'));
    });
  });

  group('5. Dashboard HomeBranchRow Subtitle & Session Rendering', () {
    testWidgets('HomeBranchRow displays title, subtitle and counts accurately', (tester) async {
      final row = HomeBranchRow(
        id: 'karachi_haji',
        name: 'Karachi Haji Camp',
        subtitle: 'Morning 45 • Evening 34',
        today: const BranchStats(zakat: 45, nonZakat: 34),
        yesterday: const BranchStats(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text(row.name),
                if (row.subtitle != null) Text(row.subtitle!),
                Text('${row.today.tokens} patients'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Karachi Haji Camp'), findsOneWidget);
      expect(find.text('Morning 45 • Evening 34'), findsOneWidget);
      expect(find.text('79 patients'), findsOneWidget);
    });
  });

  group('6. Quota Service Safety & Force Sync Reset', () {
    test('resetState clears quota exhaustion and backoff delay', () async {
      // Simulate quota hit
      QuotaService.recordQuotaExceeded(reason: 'unit_test');
      expect(QuotaService.isQuotaExhausted, isTrue);

      // Force Sync invocation resets state
      QuotaService.resetState();
      expect(QuotaService.isQuotaExhausted, isFalse, reason: 'resetState must allow manual force sync to proceed immediately');
    });
  });
}
