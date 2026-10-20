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

    test('a refused write pauses uploads; manual sync lifts it', () {
      QuotaService.recordSuccess(); // clean start
      QuotaService.pauseUntilDailyReset(reason: '429');
      expect(QuotaService.isPausedForDailyReset, isTrue);
      expect(QuotaService.canWrite(), isFalse);
      expect(QuotaService.dailyResetPauseUntil, isNotNull);
      expect(QuotaService.isQuotaExhaustedNotifier.value, isTrue);

      QuotaService.resetState();
      expect(QuotaService.isPausedForDailyReset, isFalse);
      expect(QuotaService.isQuotaExhaustedNotifier.value, isFalse);
    });

    test('graduated pause step progression (2, 5, 15, 30, 60, 60)', () {
      QuotaService.recordSuccess();
      final base = DateTime.utc(2026, 10, 10, 12); // well before next reset (which is 11th 07:00 UTC)

      // Step 1: 2 min
      QuotaService.pauseUntilDailyReset(now: base);
      expect(QuotaService.pauseStepCount, 1);
      expect(QuotaService.currentStepMinutes, 2);
      expect(QuotaService.dailyResetPauseUntilAt(base), base.add(const Duration(minutes: 2)));
      QuotaService.clearDailyResetPause();

      // Step 2: 5 min
      QuotaService.pauseUntilDailyReset(now: base);
      expect(QuotaService.pauseStepCount, 2);
      expect(QuotaService.currentStepMinutes, 5);
      expect(QuotaService.dailyResetPauseUntilAt(base), base.add(const Duration(minutes: 5)));
      QuotaService.clearDailyResetPause();

      // Step 3: 15 min
      QuotaService.pauseUntilDailyReset(now: base);
      expect(QuotaService.pauseStepCount, 3);
      expect(QuotaService.currentStepMinutes, 15);
      expect(QuotaService.dailyResetPauseUntilAt(base), base.add(const Duration(minutes: 15)));
      QuotaService.clearDailyResetPause();

      // Step 4: 30 min
      QuotaService.pauseUntilDailyReset(now: base);
      expect(QuotaService.pauseStepCount, 4);
      expect(QuotaService.currentStepMinutes, 30);
      expect(QuotaService.dailyResetPauseUntilAt(base), base.add(const Duration(minutes: 30)));
      QuotaService.clearDailyResetPause();

      // Step 5: 60 min
      QuotaService.pauseUntilDailyReset(now: base);
      expect(QuotaService.pauseStepCount, 5);
      expect(QuotaService.currentStepMinutes, 60);
      expect(QuotaService.dailyResetPauseUntilAt(base), base.add(const Duration(minutes: 60)));
      QuotaService.clearDailyResetPause();

      // Step 6: stays at 60 min
      QuotaService.pauseUntilDailyReset(now: base);
      expect(QuotaService.pauseStepCount, 6);
      expect(QuotaService.currentStepMinutes, 60);
      expect(QuotaService.dailyResetPauseUntilAt(base), base.add(const Duration(minutes: 60)));
    });

    test('graduated pause capped at nextDailyReset', () {
      QuotaService.recordSuccess();
      // 5 minutes before midnight Pacific (next reset is 07:00 UTC)
      final nearReset = DateTime.utc(2026, 10, 11, 6, 55);
      final resetUtc = QuotaService.nextDailyReset(nearReset);

      // Force high step (e.g. 60m)
      for (var i = 0; i < 4; i++) {
        QuotaService.pauseUntilDailyReset(now: nearReset);
        QuotaService.clearDailyResetPause();
      }
      QuotaService.pauseUntilDailyReset(now: nearReset);
      // next step would be 60m (07:55 UTC), but capped at resetUtc (07:00 UTC)
      expect(QuotaService.dailyResetPauseUntilAt(nearReset), resetUtc);
    });

    test('an accepted write clears a stale pause and resets step count', () {
      QuotaService.pauseUntilDailyReset();
      expect(QuotaService.pauseStepCount, greaterThan(0));
      QuotaService.recordSuccess();
      expect(QuotaService.isPausedForDailyReset, isFalse);
      expect(QuotaService.pauseStepCount, 0);
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
