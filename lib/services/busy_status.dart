// lib/services/busy_status.dart
//
// App-wide "what is the app doing right now" status, so a busy screen never looks frozen
// without explanation.
//
// Why this exists: when the Dart UI thread is busy, Flutter cannot paint anything, so a
// spinner shown *during* a heavy step never appears. The fix is to announce the task first,
// let one frame paint the status, and only then start the work. `BusyStatus.run` does that.
//
//   await BusyStatus.run('Preparing your workspace', () => heavyWork(), blocking: true);
//
//   final t = BusyStatus.begin('Syncing records', background: true);
//   t.update('Syncing patients');
//   t.end();
//
// The overlay that renders these lives in widgets/busy_status_host.dart.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class BusyTask {
  BusyTask._(this.id, this.message, this.detail, this.blocking, this.background, {Duration timeout = const Duration(seconds: 40)})
      : startedAt = DateTime.now() {
    if (blocking) {
      _timeoutTimer = Timer(timeout, () {
        if (!_ended) {
          debugPrint('[BusyTask] ⚠️ Blocking task "$message" exceeded overall time limit (${timeout.inSeconds}s). Auto-dismissing to prevent screen lock.');
          end();
        }
      });
    }
  }

  final int id;
  String message;
  String? detail;
  final bool blocking;
  final bool background;
  final DateTime startedAt;
  bool _ended = false;
  Timer? _timeoutTimer;

  /// Change the text shown for this task (e.g. move to the next step).
  void update(String message, {String? detail}) {
    if (_ended) return;
    this.message = message;
    this.detail = detail;
    BusyStatus._notify();
  }

  void end() {
    if (_ended) return;
    _ended = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    BusyStatus._remove(this);
  }
}

/// A short "it took a while, but we're back" note shown after a freeze.
class BusyNotice {
  BusyNotice(this.message) : at = DateTime.now();
  final String message;
  final DateTime at;
}

class BusyStatus {
  BusyStatus._();

  static int _nextId = 0;
  static final List<BusyTask> _tasks = [];

  /// Bumped whenever tasks change; the overlay listens to this.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Latest post-freeze notice (null when none showing).
  static final ValueNotifier<BusyNotice?> notice = ValueNotifier<BusyNotice?>(null);
  static Timer? _noticeTimer;

  static List<BusyTask> get tasks => List.unmodifiable(_tasks);

  /// The task to show: blocking first, then foreground, then background; newest wins.
  static BusyTask? get current {
    if (_tasks.isEmpty) return null;
    BusyTask? pick(bool Function(BusyTask) test) {
      for (var i = _tasks.length - 1; i >= 0; i--) {
        if (test(_tasks[i])) return _tasks[i];
      }
      return null;
    }

    return pick((t) => t.blocking) ?? pick((t) => !t.background) ?? _tasks.last;
  }

  static bool get hasBlocking => _tasks.any((t) => t.blocking);

  /// Dismiss all active busy statuses and overlays immediately.
  static void dismissAll() {
    for (final task in List<BusyTask>.from(_tasks)) {
      task.end();
    }
    _tasks.clear();
    _notify();
  }

  /// Start showing a status. Call [BusyTask.end] when done (use try/finally).
  ///
  /// [blocking] dims the screen and shows a centred card (use for steps the user must wait
  /// for, like opening their workspace). [background] shows a small, quiet pill for work the
  /// user can ignore (like syncing).
  static BusyTask begin(
    String message, {
    String? detail,
    bool blocking = false,
    bool background = false,
    Duration timeout = const Duration(seconds: 40),
  }) {
    final task = BusyTask._(_nextId++, message, detail, blocking, background, timeout: timeout);
    _tasks.add(task);
    _notify();
    return task;
  }

  /// Show [message], wait for it to be painted, run [work], then clear the status.
  static Future<T> run<T>(
    String message,
    Future<T> Function() work, {
    String? detail,
    bool blocking = false,
    bool background = false,
  }) async {
    final task = begin(message, detail: detail, blocking: blocking, background: background);
    try {
      await waitForPaint();
      return await work();
    } finally {
      task.end();
    }
  }

  /// Wait until the next frame has been drawn, so a status set just before is visible
  /// before heavy work starts. Times out quickly if no frame is scheduled (e.g. minimised).
  static Future<void> waitForPaint() async {
    try {
      final binding = SchedulerBinding.instance;
      binding.scheduleFrame();
      await binding.endOfFrame.timeout(const Duration(milliseconds: 120));
    } catch (_) {
      // No frame (window hidden, tests) — just continue.
    }
  }

  /// Called by UiStallMonitor after the UI thread was blocked for a noticeable time.
  /// Tells the user the app is responsive again so a freeze never goes unexplained.
  static void reportRecovered(int blockedMs, String? lastStep) {
    if (blockedMs < 1500) return;
    final secs = (blockedMs / 1000).toStringAsFixed(blockedMs < 10000 ? 1 : 0);
    final what = friendlyStep(lastStep);
    final message = what == null
        ? 'Sorry for the wait — the app was busy for $secs s. Everything is working again.'
        : 'Sorry for the wait — $what took $secs s. Everything is working again.';
    _noticeTimer?.cancel();
    notice.value = BusyNotice(message);
    _noticeTimer = Timer(const Duration(seconds: 5), () => notice.value = null);
  }

  static void dismissNotice() {
    _noticeTimer?.cancel();
    notice.value = null;
  }

  /// Turn an internal breadcrumb (e.g. "sync: _enqueueMissingPatients") into plain words.
  static String? friendlyStep(String? crumb) {
    if (crumb == null || crumb.isEmpty) return null;
    final c = crumb.toLowerCase();
    if (c.contains('patients')) return 'syncing patient records';
    if (c.contains('entries') || c.contains('token')) return 'syncing tokens';
    if (c.contains('donation')) return 'syncing donations';
    if (c.contains('food')) return 'syncing food records';
    if (c.contains('employee')) return 'syncing staff records';
    if (c.contains('attendance') || c.contains('zkteco')) return 'reading attendance data';
    if (c.contains('madrassa')) return 'syncing madrassa records';
    if (c.contains('school')) return 'syncing school records';
    if (c.contains('users')) return 'syncing user accounts';
    if (c.contains('upload')) return 'uploading changes';
    if (c.contains('initforroles') || c.contains('open box')) return 'loading your data';
    if (c.contains('login')) return 'signing in';
    if (c.contains('tab')) return 'opening the screen';
    if (c.contains('push') || c.contains('pop')) return 'opening the screen';
    if (c.contains('server')) return 'the local server';
    if (c.contains('lan in')) return 'receiving updates from the network';
    return null;
  }

  static void _remove(BusyTask task) {
    _tasks.remove(task);
    _notify();
  }

  static void _notify() {
    // Defer if we're mid-build to avoid "setState during build" errors.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => revision.value++);
    } else {
      revision.value++;
    }
  }
}
