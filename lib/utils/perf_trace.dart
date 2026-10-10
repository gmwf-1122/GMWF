// lib/utils/perf_trace.dart
//
// Tiny timing helper for hunting UI freezes. Prints "[Perf] <label> took N ms" only when the
// work exceeded [thresholdMs], and leaves a breadcrumb for the UI-stall monitor either way.

import 'package:flutter/foundation.dart';

import 'perf_log.dart';
import 'ui_stall_monitor.dart';

class PerfTrace {
  PerfTrace._();

  static T measure<T>(String label, T Function() body, {int thresholdMs = 40}) {
    UiStallMonitor.mark(label);
    final sw = Stopwatch()..start();
    try {
      return body();
    } finally {
      sw.stop();
      if (sw.elapsedMilliseconds >= thresholdMs) {
        debugPrint('[Perf] $label took ${sw.elapsedMilliseconds} ms');
        PerfLog.write('[Perf] $label took ${sw.elapsedMilliseconds} ms');
      }
    }
  }

  static Future<T> measureAsync<T>(String label, Future<T> Function() body, {int thresholdMs = 100}) async {
    UiStallMonitor.mark(label);
    final sw = Stopwatch()..start();
    try {
      return await body();
    } finally {
      sw.stop();
      if (sw.elapsedMilliseconds >= thresholdMs) {
        debugPrint('[Perf] $label took ${sw.elapsedMilliseconds} ms (async total)');
        PerfLog.write('[Perf] $label took ${sw.elapsedMilliseconds} ms (async total)');
      }
    }
  }
}
