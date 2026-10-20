// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/services/quota_service.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MockFirebasePlatform extends FirebasePlatform {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    return FirebaseAppPlatform(name, const FirebaseOptions(
      apiKey: 'test_api_key',
      appId: 'test_app_id',
      messagingSenderId: 'test_sender',
      projectId: 'gmwf-test',
    ));
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    return app(name ?? defaultFirebaseAppName);
  }

  @override
  List<FirebaseAppPlatform> get apps => [app()];
}

class SimpleMockResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String responseBody;

  SimpleMockResponse(this.statusCode, this.responseBody);

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream.value(utf8.encode(responseBody)).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SimpleMockRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final List<int> _body = [];
  final Future<HttpClientResponse> Function(Uri uri, String body) onSend;

  SimpleMockRequest(this.uri, this.onSend);

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  void add(List<int> data) {
    _body.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() {
    return onSend(uri, utf8.decode(_body));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SimpleMockClient implements HttpClient {
  final Future<HttpClientResponse> Function(Uri uri, String body) onSend;
  SimpleMockClient(this.onSend);

  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 30);

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return SimpleMockRequest(url, onSend);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final recordedWrites = <Map<String, dynamic>>[];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('round2_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.syncBox);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox('dead_letter_queue');
    await Hive.openBox('app_flags');
    await Hive.openBox('settings');
    await Hive.openBox('outbox_messages');

    FirebasePlatform.instance = MockFirebasePlatform();
    await Firebase.initializeApp();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  SimpleMockClient createMockClient() {
    return SimpleMockClient((uri, body) async {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['writes'] is List) {
          for (final w in json['writes'] as List) {
            recordedWrites.add(w as Map<String, dynamic>);
          }
        }
      } catch (_) {}
      return SimpleMockResponse(200, jsonEncode({'commitTime': '2026-10-16T12:00:00Z'}));
    });
  }

  group('T6.1 Past-date token upload test', () {
    test('Past-date token uploads to dateKey doc, removes queue item, and stamps cloudSyncedAt', () async {
      recordedWrites.clear();
      final syncBox = Hive.box(LocalStorageService.syncBox);
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      await syncBox.clear();
      await entriesBox.clear();

      const branch = 'gujrat';
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final dateKey = DateFormat('yyyy-MM-dd').format(yesterday);
      const serial = 'G101';
      const queueType = 'zakat';
      final entryKey = '$branch-$serial';

      final campDocKey = CampSessionService.getCampDateDocId(
        branchId: branch,
        dateKey: dateKey,
        serial: serial,
      );

      // 1. Local entry
      await entriesBox.put(entryKey, {
        'serial': serial,
        'dateKey': dateKey,
        'branchId': branch,
        'queueType': queueType,
        'patientName': 'Yesterday Patient',
        'synced': false,
        'pendingSync': true,
        'syncStatus': 'pending',
      });

      // 2. Queue item enqueued yesterday
      final syncKey = 'sync_serial_${branch}_$serial';
      await syncBox.put(syncKey, {
        'type': 'save_entry',
        'branchId': branch,
        'dateKey': dateKey,
        'serial': serial,
        'queueType': queueType,
        'enqueuedAt': yesterday.toIso8601String(),
        'data': {
          'serial': serial,
          'dateKey': dateKey,
          'branchId': branch,
          'queueType': queueType,
          'patientName': 'Yesterday Patient',
        },
      });

      final client = createMockClient();
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload();
      }, createHttpClient: (ctx) => client);

      expect(recordedWrites.isNotEmpty, isTrue, reason: 'A write should have been committed');
      final writeDoc = recordedWrites.first['update']?['name'] as String?;
      expect(writeDoc, contains('branches/$branch/serials/$campDocKey/$queueType/$serial'));
      expect(syncBox.isEmpty, isTrue, reason: 'Queue item should be removed after upload');

      final updatedLocal = entriesBox.get(entryKey) as Map?;
      expect(updatedLocal, isNotNull);
      expect(updatedLocal?['cloudSyncedAt'], isNotNull, reason: 'Local entry must have cloudSyncedAt');
      expect(updatedLocal?['synced'], isTrue);
      expect(updatedLocal?['pendingSync'], isFalse);
    });
  });

  group('T6.2 Graduated pause and budget deferral', () {
    test('Graduated pause step progression and cap at nextDailyReset', () {
      QuotaService.recordSuccess();
      final base = DateTime.utc(2026, 10, 10, 12);

      // Progression: 2, 5, 15, 30, 60, stays at 60
      final expectedMinutes = [2, 5, 15, 30, 60, 60];
      for (var i = 0; i < expectedMinutes.length; i++) {
        QuotaService.pauseUntilDailyReset(now: base);
        expect(QuotaService.currentStepMinutes, expectedMinutes[i], reason: 'Step ${i + 1} should be ${expectedMinutes[i]}m');
        QuotaService.clearDailyResetPause();
      }

      // Record success resets step count to 0
      QuotaService.pauseUntilDailyReset(now: base);
      expect(QuotaService.pauseStepCount, greaterThan(0));
      QuotaService.recordSuccess();
      expect(QuotaService.pauseStepCount, 0);

      // Cap at nextDailyReset
      final nearReset = DateTime.utc(2026, 10, 11, 6, 55);
      final resetUtc = QuotaService.nextDailyReset(nearReset);
      for (var i = 0; i < 4; i++) {
        QuotaService.pauseUntilDailyReset(now: nearReset);
        QuotaService.clearDailyResetPause();
      }
      QuotaService.pauseUntilDailyReset(now: nearReset);
      expect(QuotaService.dailyResetPauseUntilAt(nearReset), resetUtc);
      QuotaService.recordSuccess();
    });

    test('Backlog budget deferral: item stays queued, attempts unchanged, nextRetryAt set; force bypasses', () async {
      recordedWrites.clear();
      final syncBox = Hive.box(LocalStorageService.syncBox);
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      await syncBox.clear();
      await entriesBox.clear();

      QuotaService.recordSuccess();
      Hive.box('app_flags').put('quota_backlog_daily_budget', '1');
      QuotaService.recordWrites(1, backlog: true);
      expect(QuotaService.backlogBudgetAvailable, isFalse);

      // Backlog item from two months ago
      const branch = 'gujrat';
      const oldDateKey = '2026-08-01';
      const serial = 'BK99';
      const queueType = 'zakat';
      final syncKey = 'sync_serial_${branch}_$serial';

      await syncBox.put(syncKey, {
        'type': 'save_entry',
        'branchId': branch,
        'dateKey': oldDateKey,
        'serial': serial,
        'queueType': queueType,
        'attempts': 0,
        'data': {
          'serial': serial,
          'dateKey': oldDateKey,
          'branchId': branch,
          'queueType': queueType,
          'patientName': 'Backlog Patient',
        },
      });

      final client = createMockClient();
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload();
      }, createHttpClient: (ctx) => client);

      // Backlog item must be deferred because backlog budget is exhausted
      expect(recordedWrites.isEmpty, isTrue, reason: 'No writes should be sent for deferred backlog item');
      final queuedItem = syncBox.get(syncKey) as Map?;
      expect(queuedItem, isNotNull, reason: 'Deferred backlog item must stay queued');
      expect(queuedItem?['attempts'], 0, reason: 'Deferred item attempts must remain 0');
      expect(queuedItem?['nextRetryAt'], isNotNull, reason: 'Deferred item must have nextRetryAt set');
      expect(queuedItem?['nextRetryAt'], contains(QuotaService.nextDailyReset().toLocal().year.toString()));

      // Manual force bypasses the backlog budget
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload(force: true);
      }, createHttpClient: (ctx) => client);

      expect(recordedWrites.isNotEmpty, isTrue, reason: 'Manual force must bypass budget and write');
      expect(syncBox.containsKey(syncKey), isFalse, reason: 'Item should be uploaded and removed from queue');
    });
  });

  group('T6.3 Urgent trigger observable behavior', () {
    test('Urgent trigger does NOT clear quota pause and sends no writes while paused', () async {
      recordedWrites.clear();
      final syncBox = Hive.box(LocalStorageService.syncBox);
      await syncBox.clear();

      // Pause for quota
      QuotaService.pauseUntilDailyReset(reason: '429 Quota Exhausted');
      expect(QuotaService.isPausedForDailyReset, isTrue);

      const branch = 'gujrat';
      const serial = 'URG01';
      final syncKey = 'sync_serial_${branch}_$serial';
      await syncBox.put(syncKey, {
        'type': 'save_entry',
        'branchId': branch,
        'dateKey': '2026-10-16',
        'serial': serial,
        'queueType': 'zakat',
        'data': {
          'serial': serial,
          'dateKey': '2026-10-16',
          'branchId': branch,
          'queueType': 'zakat',
          'patientName': 'Urgent Patient',
        },
      });

      final client = createMockClient();
      // Trigger upload with urgent: true
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload(urgent: true);
      }, createHttpClient: (ctx) => client);

      // Observable behavior: pause is NOT cleared, and no writes were sent
      expect(QuotaService.isPausedForDailyReset, isTrue, reason: 'Urgent trigger must NOT clear daily quota pause');
      expect(recordedWrites.isEmpty, isTrue, reason: 'No writes may be sent while paused for quota');
      expect(syncBox.containsKey(syncKey), isTrue, reason: 'Item must remain in queue while paused');

      // Manual force: clears pause and sends write
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload(force: true);
      }, createHttpClient: (ctx) => client);

      expect(QuotaService.isPausedForDailyReset, isFalse, reason: 'Manual force must clear quota pause');
      expect(recordedWrites.isNotEmpty, isTrue, reason: 'Manual force sends the upload');
      expect(syncBox.isEmpty, isTrue, reason: 'Queue item removed on successful upload');
    });
  });

  group('T6.4 Request status uploads (2026-10-18)', () {
    String? fieldOf(Map<String, dynamic> write, String name) =>
        ((write['update']?['fields'] as Map?)?[name] as Map?)?['stringValue'] as String?;

    test('a queued approval uploads approved to the request doc', () async {
      QuotaService.resetState();
      recordedWrites.clear();
      final syncBox = Hive.box(LocalStorageService.syncBox);
      await syncBox.clear();

      // Exactly what the Requests page queues. enqueueSync overwrites 'status' with the queue
      // state, and the collection field used to send it to a writer that wrote nothing.
      await LocalStorageService.enqueueSync({
        'type': 'update_request_status',
        'requestId': 'req_t64',
        'id': 'req_t64',
        'status': 'approved',
        'requestStatus': 'approved',
        'collection': 'edit_requests',
        'branchId': 'gujrat',
        'reviewedBy': 'phone-user',
      });

      final client = createMockClient();
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload(force: true);
      }, createHttpClient: (ctx) => client);

      final write = recordedWrites.firstWhere(
        (w) => (w['update']?['name'] as String? ?? '').endsWith('branches/gujrat/edit_requests/req_t64'),
        orElse: () => <String, dynamic>{},
      );
      expect(write, isNotEmpty, reason: 'The decision must be written to the request doc');
      expect(fieldOf(write, 'status'), 'approved');
      expect(syncBox.isEmpty, isTrue);
    });

    test('an old status item without a decision never uploads pending', () async {
      QuotaService.resetState();
      recordedWrites.clear();
      final syncBox = Hive.box(LocalStorageService.syncBox);
      await syncBox.clear();

      await LocalStorageService.enqueueSync({
        'type': 'update_request_status',
        'requestId': 'req_old',
        'status': 'approved', // overwritten to 'pending' by enqueueSync; no requestStatus
        'collection': 'edit_requests',
        'branchId': 'gujrat',
      });

      final client = createMockClient();
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload(force: true);
      }, createHttpClient: (ctx) => client);

      final reverted = recordedWrites.where((w) =>
          (w['update']?['name'] as String? ?? '').endsWith('edit_requests/req_old'));
      expect(reverted, isEmpty, reason: 'Nothing may be written without a decision');
      expect(syncBox.isEmpty, isTrue, reason: 'The item is dropped, not retried forever');
    });
  });

  group('T6.5 Writes the LAN server uploads for dispensary desks', () {
    Future<void> runUpload() async {
      final client = createMockClient();
      await HttpOverrides.runZoned(() async {
        await SyncService().triggerUpload(force: true);
      }, createHttpClient: (ctx) => client);
    }

    test('a relayed desk write lands on its document with server time', () async {
      QuotaService.resetState();
      recordedWrites.clear();
      final syncBox = Hive.box(LocalStorageService.syncBox);
      await syncBox.clear();
      // What server.dart queues when a desk sends LanFirestoreGate.relayWrite.
      await syncBox.put('sync_relay_1', {
        'type': 'relay_cloud_write',
        'branchId': 'gujrat',
        'data': {
          'id': 'branches/gujrat/notifications/n1',
          'path': 'branches/gujrat/notifications/n1',
          'merge': true,
          'delete': false,
          'serverTimeKeys': ['timestamp'],
          'fields': {'title': 'Supervisor Alert', 'seen': false},
        },
        'createdAt': DateTime.now().toIso8601String(),
        'attempts': 0,
        'status': 'pending',
      });
      await runUpload();

      final write = recordedWrites.firstWhere(
        (w) => (w['update']?['name'] as String? ?? '').endsWith('branches/gujrat/notifications/n1'),
        orElse: () => <String, dynamic>{},
      );
      expect(write, isNotEmpty);
      expect((write['update']['fields'] as Map)['title'], {'stringValue': 'Supervisor Alert'});
      final transforms = (write['updateTransforms'] as List?) ?? const [];
      expect(transforms.any((t) => t['fieldPath'] == 'timestamp' && t['setToServerValue'] == 'REQUEST_TIME'), isTrue);
      expect(syncBox.isEmpty, isTrue);
    });

    test('a forwarded doctor template goes to doctor_templates, not sync_records', () async {
      QuotaService.resetState();
      recordedWrites.clear();
      final syncBox = Hive.box(LocalStorageService.syncBox);
      await syncBox.clear();
      await syncBox.put('sync_tpl_1', {
        'type': 'save_prescription_template',
        'branchId': 'gujrat',
        'data': {'id': 'tpl1', 'doctorId': 'doc9', 'name': 'Fever'},
        'createdAt': DateTime.now().toIso8601String(),
        'attempts': 0,
        'status': 'pending',
      });
      await runUpload();

      final names = recordedWrites.map((w) => (w['update']?['name'] ?? w['delete'] ?? '') as String).toList();
      expect(names.any((n) => n.endsWith('branches/gujrat/doctor_templates/tpl1')), isTrue);
      expect(names.any((n) => n.endsWith('users/doc9/doctor_templates/tpl1')), isTrue);
      expect(names.any((n) => n.contains('sync_records')), isFalse);
    });
  });
}
