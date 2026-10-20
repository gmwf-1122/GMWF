import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Firestore write-quota state for this PC.
///
/// There are no artificial limits on live work. Uploads pause only when Firestore itself
/// answers "quota used up" (RESOURCE_EXHAUSTED / HTTP 429 — the Spark plan's 20k writes a
/// day for the whole project). Firestore would reject every write until its daily reset
/// anyway, so the pause just stops sending; everything stays queued in Hive and resumes
/// on its own at the reset (midnight US-Pacific = about noon in Pakistan).
///
/// Older backlog (records re-queued by the backfill sweeps) only uses a per-PC daily
/// share ([backlogDailyBudget]), so a large backlog never eats the quota that today's
/// tokens, prescriptions and donations need. Set `quota_backlog_daily_budget` in the
/// `app_flags` box to change it (0 = unlimited, e.g. on the Blaze plan).
class QuotaService {
  static final QuotaService _instance = QuotaService._internal();
  factory QuotaService() => _instance;
  QuotaService._internal();

  static final ValueNotifier<bool> isQuotaExhaustedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> quotaExhaustedReasonNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<DateTime?> quotaExhaustedTimestampNotifier = ValueNotifier<DateTime?>(null);

  /// Cloud reads are never blocked: write-quota exhaustion does not stop reads, and the
  /// read paths that check this must keep working.
  static bool get isQuotaExhausted => false;

  static const int _defaultBacklogDailyBudget = 3000;
  static const String _writeCountKey = 'quota_daily_writes';
  static const String _backlogCountKey = 'quota_daily_backlog_writes';
  static const String _writeDateKey = 'quota_daily_date';
  static const String _resetPauseKey = 'quota_reset_pause_until';
  static const String _backlogBudgetKey = 'quota_backlog_daily_budget';

  /// Per-PC daily share for backlog uploads. 0 means unlimited.
  static int get backlogDailyBudget {
    final v = int.tryParse(_getFlag(_backlogBudgetKey) ?? '');
    return v ?? _defaultBacklogDailyBudget;
  }

  /// The Firestore quota day this moment belongs to (its US-Pacific date).
  static String _quotaDay() =>
      nextDailyReset().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);

  /// Records [count] successful cloud writes for today ([backlog] = sent for a backlog item).
  static void recordWrites(int count, {bool backlog = false}) {
    try {
      final day = _quotaDay();
      final sameDay = _getFlag(_writeDateKey) == day;
      final total = sameDay ? (int.tryParse(_getFlag(_writeCountKey) ?? '0') ?? 0) : 0;
      final back = sameDay ? (int.tryParse(_getFlag(_backlogCountKey) ?? '0') ?? 0) : 0;
      _setFlag(_writeDateKey, day);
      _setFlag(_writeCountKey, '${total + count}');
      _setFlag(_backlogCountKey, '${back + (backlog ? count : 0)}');
    } catch (_) {}
  }

  /// This device's successful cloud writes in the current Firestore quota day.
  static int get dailyWriteCount => _todayCount(_writeCountKey);

  /// Of [dailyWriteCount], the writes made for backlog items.
  static int get dailyBacklogWriteCount => _todayCount(_backlogCountKey);

  static int _todayCount(String key) {
    try {
      if (_getFlag(_writeDateKey) != _quotaDay()) return 0;
      return int.tryParse(_getFlag(key) ?? '0') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// True while backlog items may still use today's share.
  static bool get backlogBudgetAvailable {
    final budget = backlogDailyBudget;
    return budget <= 0 || dailyBacklogWriteCount < budget;
  }

  /// False only while Firestore has reported the daily write quota as used up.
  static bool canWrite({int count = 1, bool isPriority = false}) => !isPausedForDailyReset;

  /// Check if an exception/error is a Firebase quota exhaustion error
  static bool isQuotaError(dynamic error) {
    if (error == null) return false;
    final errStr = error.toString().toLowerCase();
    return errStr.contains('resource-exhausted') ||
        errStr.contains('quota-exceeded') ||
        errStr.contains('resource_exhausted') ||
        errStr.contains('quota exceeded') ||
        errStr.contains('over quota') ||
        errStr.contains('quota limit') ||
        errStr.contains('usage limit');
  }

  static const List<int> pauseStepsMinutes = [2, 5, 15, 30, 60];
  static const String _pauseStepCountKey = 'quota_pause_step_count';

  /// Number of consecutive refusals recorded.
  static int get pauseStepCount {
    try {
      return int.tryParse(_getFlag(_pauseStepCountKey) ?? '0') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// The step duration (in minutes) of the current or most recent pause.
  static int get currentStepMinutes {
    final count = pauseStepCount;
    if (count <= 0) return pauseStepsMinutes.first;
    final idx = count - 1;
    if (idx < pauseStepsMinutes.length) {
      return pauseStepsMinutes[idx];
    }
    return pauseStepsMinutes.last;
  }

  /// Informational: a read or other non-upload call hit a quota error. Uploads are only
  /// paused by [pauseUntilDailyReset], when a write itself is refused.
  static void recordQuotaExceeded({String? reason, dynamic error}) {
    final effectiveReason = reason ?? (error != null ? error.toString() : 'Firestore notice');
    debugPrint('[QuotaService] Notice: $effectiveReason');
  }

  /// A write was accepted, so any stored pause is stale and refusal count resets.
  static void recordSuccess() {
    if (isPausedForDailyReset) clearDailyResetPause();
    if (pauseStepCount > 0) {
      _setFlag(_pauseStepCountKey, '0');
    }
  }

  // ── Daily quota pause (Spark plan) ───────────────────────────────────────
  /// Next Firestore daily-quota reset: midnight America/Los_Angeles, in UTC.
  static DateTime nextDailyReset([DateTime? nowUtc]) {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    DateTime nthSunday(int year, int month, int n) {
      var d = DateTime.utc(year, month, 1);
      while (d.weekday != DateTime.sunday) {
        d = d.add(const Duration(days: 1));
      }
      return d.add(Duration(days: 7 * (n - 1)));
    }
    // US daylight saving: 2nd Sunday of March 02:00 PST → 1st Sunday of November 02:00 PDT.
    final dstStart = nthSunday(now.year, 3, 2).add(const Duration(hours: 10));
    final dstEnd = nthSunday(now.year, 11, 1).add(const Duration(hours: 9));
    final offsetHours = (now.isAfter(dstStart) && now.isBefore(dstEnd)) ? 7 : 8;
    final pacific = now.subtract(Duration(hours: offsetHours));
    return DateTime.utc(pacific.year, pacific.month, pacific.day + 1).add(Duration(hours: offsetHours));
  }

  /// Firestore refused a write for quota: pause until min(nextDailyReset(), now + step).
  /// Step follows consecutive refusals: 2, 5, 15, 30, 60 minutes, then stays at 60.
  static void pauseUntilDailyReset({String? reason, DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final count = pauseStepCount;
    final stepMinutes = (count < pauseStepsMinutes.length)
        ? pauseStepsMinutes[count]
        : pauseStepsMinutes.last;
    _setFlag(_pauseStepCountKey, '${count + 1}');

    final resetUtc = nextDailyReset(currentTime.toUtc());
    final candidateUntil = currentTime.toUtc().add(Duration(minutes: stepMinutes));
    final until = candidateUntil.isBefore(resetUtc) ? candidateUntil : resetUtc;

    _setFlag(_resetPauseKey, until.toIso8601String());
    _pauseUntilMemo = until;
    isQuotaExhaustedNotifier.value = true;
    final localRetry = until.toLocal();
    final timeStr = "${localRetry.hour.toString().padLeft(2, '0')}:${localRetry.minute.toString().padLeft(2, '0')}:${localRetry.second.toString().padLeft(2, '0')}";
    quotaExhaustedReasonNotifier.value = reason != null
        ? '$reason (retrying at $timeStr)'
        : 'Firestore daily write quota used up (retrying at $timeStr)';
    quotaExhaustedTimestampNotifier.value = currentTime;
    debugPrint('[QuotaService] ⛔ Daily write quota exceeded (step $stepMinutes m) — uploads paused until $localRetry');
  }

  static DateTime? _pauseUntilMemo;

  /// When the current pause ends (UTC), or null when uploads are not paused.
  static DateTime? dailyResetPauseUntilAt([DateTime? nowUtc]) {
    final rawStr = _getFlag(_resetPauseKey);
    final until = _pauseUntilMemo ?? (rawStr != null ? DateTime.tryParse(rawStr) : null);
    if (until == null) return null;
    final now = (nowUtc ?? DateTime.now()).toUtc();
    if (!now.isBefore(until)) {
      clearDailyResetPause();
      return null;
    }
    return until;
  }

  /// When the current pause ends (UTC), or null when uploads are not paused.
  static DateTime? get dailyResetPauseUntil => dailyResetPauseUntilAt();

  static bool isPausedForDailyResetAt([DateTime? nowUtc]) => dailyResetPauseUntilAt(nowUtc) != null;

  static bool get isPausedForDailyReset => isPausedForDailyResetAt();

  /// Lifts the pause (pause duration elapsed, a write succeeded, or a manual "Sync now").
  /// Note: Step counter is NOT reset here; it resets only on recordSuccess().
  static void clearDailyResetPause() {
    _pauseUntilMemo = null;
    _setFlag(_resetPauseKey, null);
    _setFlag('quota_paused_until', null); // legacy key from older versions
    isQuotaExhaustedNotifier.value = false;
    quotaExhaustedReasonNotifier.value = null;
    quotaExhaustedTimestampNotifier.value = null;
  }

  /// Manual recovery ("Sync now", app start): try Firestore again right away. If the
  /// quota is still used up, the first write refused pauses uploads again.
  static void resetState() {
    clearDailyResetPause();
  }

  // ── Hive helpers ─────────────────────────────────────────────────────────
  static String? _getFlag(String key) {
    try {
      if (!Hive.isBoxOpen('app_flags')) return null;
      return Hive.box('app_flags').get(key)?.toString();
    } catch (_) {
      return null;
    }
  }

  static void _setFlag(String key, String? value) {
    try {
      if (!Hive.isBoxOpen('app_flags')) return;
      if (value == null) {
        Hive.box('app_flags').delete(key);
      } else {
        Hive.box('app_flags').put(key, value);
      }
    } catch (_) {}
  }
}
