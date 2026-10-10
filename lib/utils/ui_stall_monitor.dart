// lib/utils/ui_stall_monitor.dart
//
// Diagnostic for the Windows "(Not Responding)" freezes.
//
// Two signals, printed only when something is actually wrong:
//   1. EVENT LOOP STALL  - a 250 ms timer that fires more than 700 ms late means the Dart UI
//      isolate was busy (synchronous work) for that long. The most recent breadcrumbs
//      (UiStallMonitor.mark) say what was started just before.
//   2. SLOW FRAME        - a frame whose build or raster time exceeds 250 ms.
//
// Breadcrumbs are one-line labels dropped at the start of heavy operations.

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'perf_log.dart';

class UiStallMonitor {
  UiStallMonitor._();

  static final List<String> _crumbs = [];
  static Timer? _timer;
  static DateTime _last = DateTime.now();
  static bool _started = false;

  /// Record what is about to run (keeps the last 8).
  static void mark(String label) {
    _crumbs.add('${DateTime.now().toIso8601String().substring(11, 23)} $label');
    if (_crumbs.length > 8) _crumbs.removeAt(0);
  }

  static void start() {
    if (_started || kIsWeb) return;
    _started = true;
    _last = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = DateTime.now();
      final lateMs = now.difference(_last).inMilliseconds - 250;
      _last = now;
      if (lateMs > 300) {
        final msg = '[UiStall] UI thread blocked for ~${lateMs + 250} ms. Recent steps: ${_crumbs.join(" | ")}';
        debugPrint(msg);
        PerfLog.write(msg);
      }
    });
    SchedulerBinding.instance.addTimingsCallback((List<ui.FrameTiming> timings) {
      for (final t in timings) {
        final build = t.buildDuration.inMilliseconds;
        final raster = t.rasterDuration.inMilliseconds;
        if (build > 120 || raster > 120) {
          final msg = '[UiStall] Slow frame: build $build ms, raster $raster ms. Recent steps: ${_crumbs.join(" | ")}';
          debugPrint(msg);
          PerfLog.write(msg);
        }
      }
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }
}
