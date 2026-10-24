import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/pages/dispensary/dispensar/dispense_queue.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/services/local_storage_service.dart';

/// A token shows only on the date in its serial: 241026M-SADD-005 belongs to 24 Oct 2026 and
/// must not show on 23 or 25 Oct, however recently it was created or replayed from an outbox.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_token_date_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(LocalStorageService.entriesBox);
    await Hive.openBox(LocalStorageService.prescriptionsBox);
    await Hive.openBox(LocalStorageService.dispensaryBox);
    await Hive.openBox('app_settings');
    await Hive.openBox('app_flags');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('tokenDateKey', () {
    test('serial date decides, even when created minutes ago', () {
      final replayed = {
        'serial': '231026E-SADD-003',
        'dateKey': '231026',
        'status': 'waiting',
        'createdAt': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      };
      expect(CampSessionService.tokenDateKey(replayed), '231026');
      expect(CampSessionService.isTokenOnDate(replayed, '241026'), isFalse);
      expect(CampSessionService.isTokenOnDate(replayed, '231026'), isTrue);
    });

    test('serial date wins over a wrong stored dateKey', () {
      final e = {'serial': '241026M-SADD-005', 'dateKey': '251026'};
      expect(CampSessionService.tokenDateKey(e), '241026');
      expect(CampSessionService.isTokenOnDate(e, '251026'), isFalse);
    });

    test('letterless v1.6.1 and branch-prefixed serials', () {
      expect(CampSessionService.tokenDateKey({'serial': '241026-SKT-001'}), '241026');
      expect(CampSessionService.tokenDateKey({'serial': 'gujrat-241026M-GRT-001'}), '241026');
    });

    test('falls back to dateKey, then creation time', () {
      expect(CampSessionService.tokenDateKey({'serial': '005', 'dateKey': '241026'}), '241026');
      final created = DateTime(2026, 10, 24, 10, 30);
      expect(
        CampSessionService.tokenDateKey({'serial': '005', 'createdAt': created.toIso8601String()}),
        CampSessionService.resolveShiftAndDateKey(created).dateKey,
      );
      expect(CampSessionService.tokenDateKey({'serial': '005'}), '');
    });
  });

  test('dispense queue never lists yesterday\'s tokens', () async {
    final today = CampSessionService.resolveShiftAndDateKey(null, 'gujrat').dateKey;
    final yesterdayDt = DateTime.now().subtract(const Duration(days: 1));
    final yesterday = CampSessionService.resolveShiftAndDateKey(yesterdayDt, 'gujrat').dateKey;
    final box = Hive.box(LocalStorageService.entriesBox);
    Map<String, dynamic> entry(String dk, String name) => {
          'serial': '${dk}M-GRT-005',
          'branchId': 'gujrat',
          'dateKey': dk,
          'session': 'morning',
          'patientName': name,
          'patientCnic': '3520112345678',
          'status': 'completed',
          // Recent createdAt: what the old 24-hour carry-over let through.
          'createdAt': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
          'prescription': {
            'medicines': [
              {'name': '$name Med', 'quantity': 10}
            ],
          },
        };
    await box.put('gujrat-${yesterday}M-GRT-005', entry(yesterday, 'Yesterday Patient'));
    await box.put('gujrat-${today}M-GRT-005', entry(today, 'Today Patient'));

    expect(
      DispenseQueue.isEffectivelyToday(entry(yesterday, 'x'), today, '', 'gujrat'),
      isFalse,
    );
    expect(DispenseQueue.isEffectivelyToday(entry(today, 'x'), today, '', 'gujrat'), isTrue);
  });
}
