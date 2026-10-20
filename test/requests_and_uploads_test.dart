import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/services/donation_box_storage.dart';
import 'package:gmwf/pages/madrassa/utils/madrassa_local_storage.dart';

/// Regression tests for 2026-10-18: decided requests turning pending again, madrassa fee
/// months dropped by the queue cleanup, donation backfill, box ids and LAN fee copies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_requests_uploads_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('decided requests stay decided', () {
    test('isDecidedRequestStatus', () {
      expect(LocalStorageService.isDecidedRequestStatus('approved'), isTrue);
      expect(LocalStorageService.isDecidedRequestStatus('Rejected'), isTrue);
      expect(LocalStorageService.isDecidedRequestStatus('acknowledged'), isTrue);
      expect(LocalStorageService.isDecidedRequestStatus('pending'), isFalse);
      expect(LocalStorageService.isDecidedRequestStatus(null), isFalse);
    });

    test('a pending upload takes the local decision', () {
      final data = {'status': 'pending', 'patientName': 'A'};
      final changed = SyncService.applyDecidedRequestStatus(data,
          local: {'status': 'approved', 'doctorReason': 'ok', 'reviewedAt': '2026-10-18T10:00:00'});
      expect(changed, isTrue);
      expect(data['status'], 'approved');
      expect(data['doctorReason'], 'ok');
      expect(data['patientName'], 'A');
    });

    test('a pending upload leaves a decided cloud doc alone', () {
      final data = {'status': 'pending', 'reviewedAt': null, 'decision': null, 'patientName': 'A'};
      final changed = SyncService.applyDecidedRequestStatus(data, cloud: {'status': 'rejected'});
      expect(changed, isTrue);
      expect(data.containsKey('status'), isFalse);
      expect(data.containsKey('reviewedAt'), isFalse);
      expect(data.containsKey('decision'), isFalse);
      expect(data['patientName'], 'A');
    });

    test('a pending upload of an undecided request is unchanged', () {
      final data = {'status': 'pending'};
      expect(SyncService.applyDecidedRequestStatus(data, local: {'status': 'pending'}, cloud: {'status': 'pending'}), isFalse);
      expect(SyncService.applyDecidedRequestStatus(data, cloud: null), isFalse);
      expect(data['status'], 'pending');
    });

    test('a decision upload is never touched', () {
      final data = {'status': 'approved'};
      expect(SyncService.applyDecidedRequestStatus(data, cloud: {'status': 'rejected'}), isFalse);
      expect(data['status'], 'approved');
    });

    test('markLocalRequestDecided updates the copy and clears the doctor list entry', () async {
      final box = await Hive.openBox('local_edit_requests');
      await box.put('r1', {'id': 'r1', 'status': 'pending', 'patientName': 'A'});
      await Hive.box('app_settings').put('pending_exception_r1', {'id': 'r1'});

      await LocalStorageService.markLocalRequestDecided('r1', 'rejected', fields: {'doctorReason': 'no'});

      expect(box.get('r1')['status'], 'rejected');
      expect(box.get('r1')['doctorReason'], 'no');
      expect(box.get('r1')['patientName'], 'A');
      expect(Hive.box('app_settings').get('pending_exception_r1'), isNull);
      expect(LocalStorageService.isLocalRequestDecided('r1'), isTrue);
    });

    test('an acknowledged restock request is not turned back to pending', () async {
      await LocalStorageService.saveRestockRequest('gujrat', {'id': 'rs1', 'status': 'pending'});
      await LocalStorageService.markLocalRequestDecided('rs1', 'acknowledged');
      await LocalStorageService.saveRestockRequest('gujrat', {'id': 'rs1', 'status': 'pending', 'medicineName': 'X'});

      final saved = Hive.box(LocalStorageService.restockRequestsBox).get('rs1');
      expect(saved['status'], 'acknowledged');
      expect(saved['medicineName'], 'X');
    });

    test('saveRestockRequest stores a request carrying serverTimestamp', () async {
      await LocalStorageService.saveRestockRequest('gujrat', {
        'id': 'rs2',
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      expect(Hive.box(LocalStorageService.restockRequestsBox).get('rs2'), isNotNull);
    });
  });

  group('madrassa fee payments', () {
    test('queue cleanup keeps two months of the same student', () async {
      final box = await Hive.openBox(LocalStorageService.syncBox);
      for (final m in [9, 10]) {
        await box.put('fee_$m', {
          'type': 'save_madrassa_fee_payment',
          'branchId': 'gujrat',
          'id': '2026_${m}_s1',
          'studentId': 's1',
          'year': 2026,
          'month': m,
          'data': {'id': '2026_${m}_s1', 'studentId': 's1', 'amountPaid': 500},
        });
      }
      await LocalStorageService.purgeBloatedSyncQueue(force: true);
      expect(box.get('fee_9'), isNotNull);
      expect(box.get('fee_10'), isNotNull);
    });

    test('a LAN copy is cached as sent and never replaces a newer record', () async {
      await MadrassaLocalStorage.cacheFeePayment('gujrat', {
        'studentId': 's1', 'year': 2026, 'month': 10,
        'paymentMethod': 'Bank', 'receiptId': 'R-9', 'lastUpdatedAt': '2026-10-18T10:00:00',
      });
      await MadrassaLocalStorage.cacheFeePayment('gujrat', {
        'studentId': 's1', 'year': 2026, 'month': 10,
        'paymentMethod': 'Cash', 'receiptId': '', 'lastUpdatedAt': '2026-10-18T09:00:00',
      });
      final fees = Hive.box(LocalStorageService.madrassaFeesBox);
      final rec = fees.values.cast<Map>().single;
      expect(rec['paymentMethod'], 'Bank');
      expect(rec['receiptId'], 'R-9');
      // Caching never queues an upload (the paying PC uploads it).
      expect(Hive.isBoxOpen(LocalStorageService.syncBox) ? Hive.box(LocalStorageService.syncBox).length : 0, 0);
    });
  });

  group('donations', () {
    test('backfill picks this PC\'s unsynced donations only', () {
      const me = 'pc-1';
      expect(SyncService.needsDonationBackfill({'syncStatus': 'pending', 'firestoreId': 'R1_x', 'originDevice': me}, me), isTrue);
      expect(SyncService.needsDonationBackfill({'syncStatus': 'pending', 'firestoreId': 'R1_x', 'originDevice': 'pc-2'}, me), isFalse);
      expect(SyncService.needsDonationBackfill({'syncStatus': 'pending', 'firestoreId': 'R1_x', 'lanReceived': true}, me), isFalse);
      expect(SyncService.needsDonationBackfill({'syncStatus': 'synced', 'originDevice': me}, me), isFalse);
      expect(SyncService.needsDonationBackfill({'syncStatus': 'deleted', 'originDevice': me}, me), isFalse);
      // Older records without originDevice keep the old rule.
      expect(SyncService.needsDonationBackfill({'syncStatus': 'pending'}, me), isTrue);
      expect(SyncService.needsDonationBackfill({'syncStatus': 'pending', 'firestoreId': 'R1_x'}, me), isFalse);
    });

    test('box keys are not prefixed twice', () {
      expect(DonationBoxStorage.localKeyFor('gujrat', 'box', 'gujrat_box_abc'), 'gujrat_box_abc');
      expect(DonationBoxStorage.localKeyFor('gujrat', 'box', '17'), 'gujrat_box_17');
      expect(DonationBoxStorage.localKeyFor('gujrat', 'opening', 'gujrat_opening_x'), 'gujrat_opening_x');
    });

    test('a downloaded box uploads to its cloud doc id', () async {
      final box = await Hive.openBox(DonationBoxStorage.boxesBoxName);
      await box.put('gujrat_box_17', {'boxNumber': '17', 'firestoreId': '17'});
      await box.put('gujrat_box_new', {'boxNumber': '18'});
      expect(DonationBoxStorage.boxCloudDocId('gujrat_box_17'), '17');
      expect(DonationBoxStorage.boxCloudDocId('gujrat_box_new'), 'gujrat_box_new');
    });
  });
}
