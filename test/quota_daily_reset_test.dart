import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gmwf/services/quota_service.dart';

void main() {
  group('nextDailyReset (midnight America/Los_Angeles)', () {
    test('summer (PDT, UTC-7)', () {
      expect(QuotaService.nextDailyReset(DateTime.utc(2026, 10, 10, 12)), DateTime.utc(2026, 10, 11, 7));
    });
    test('early UTC morning is still the previous Pacific day', () {
      expect(QuotaService.nextDailyReset(DateTime.utc(2026, 10, 10, 5)), DateTime.utc(2026, 10, 10, 7));
    });
    test('winter (PST, UTC-8)', () {
      expect(QuotaService.nextDailyReset(DateTime.utc(2026, 1, 15, 20)), DateTime.utc(2026, 1, 16, 8));
    });
  });

  group('quota pause and budgets', () {
    late Directory dir;
    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('quota_test');
      Hive.init(dir.path);
      await Hive.openBox('app_flags');
    });
    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('no artificial limit: writes allowed until Firestore itself refuses', () {
      QuotaService.resetState();
      expect(QuotaService.isPausedForDailyReset, isFalse);
      expect(QuotaService.canWrite(), isTrue);
      // A read hitting a quota error is informational only.
      QuotaService.recordQuotaExceeded(reason: 'read quota');
      expect(QuotaService.isPausedForDailyReset, isFalse);
      // Cloud reads are never blocked.
      expect(QuotaService.isQuotaExhausted, isFalse);
    });

    test('a refused write pauses uploads until the reset; manual sync lifts it', () {
      QuotaService.pauseUntilDailyReset(reason: '429');
      expect(QuotaService.isPausedForDailyReset, isTrue);
      expect(QuotaService.canWrite(), isFalse);
      expect(QuotaService.dailyResetPauseUntil, QuotaService.nextDailyReset());
      expect(QuotaService.isQuotaExhaustedNotifier.value, isTrue);

      QuotaService.resetState();
      expect(QuotaService.isPausedForDailyReset, isFalse);
      expect(QuotaService.isQuotaExhaustedNotifier.value, isFalse);
    });

    test('an accepted write clears a stale pause', () {
      QuotaService.pauseUntilDailyReset();
      QuotaService.recordSuccess();
      expect(QuotaService.isPausedForDailyReset, isFalse);
    });

    test('backlog uses only its daily share; live writes are not limited', () {
      Hive.box('app_flags').put('quota_backlog_daily_budget', '5');
      final startTotal = QuotaService.dailyWriteCount;
      QuotaService.recordWrites(4, backlog: true);
      expect(QuotaService.backlogBudgetAvailable, isTrue);
      QuotaService.recordWrites(1, backlog: true);
      expect(QuotaService.backlogBudgetAvailable, isFalse);
      QuotaService.recordWrites(100);
      expect(QuotaService.dailyWriteCount, startTotal + 105);
      expect(QuotaService.canWrite(), isTrue);
      // 0 = unlimited (e.g. on the Blaze plan)
      Hive.box('app_flags').put('quota_backlog_daily_budget', '0');
      expect(QuotaService.backlogBudgetAvailable, isTrue);
    });
  });
}
