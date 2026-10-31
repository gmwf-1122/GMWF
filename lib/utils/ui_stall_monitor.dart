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
import 'package:flutter/widgets.dart';

import 'perf_log.dart';
import '../services/busy_status.dart';

class UiStallMonitor {
  UiStallMonitor._();

  static final List<String> _crumbs = [];
  static Timer? _timer;
  static DateTime _last = DateTime.now();
  static DateTime _lastMarkAt = DateTime.now();
  static String? _lastLabel;
  static int _repeat = 0;
  static bool _started = false;

  /// The route on top (set by the navigator observer), to name the screen in stall reports:
  /// routes are mostly unnamed MaterialPageRoutes, so the log could not say which screen
  /// kept building for 400 ms per frame.
  static Route<dynamic>? topRoute;
  static DateTime _lastScreenLookup = DateTime.fromMillisecondsSinceEpoch(0);
  static String _lastScreen = '?';

  /// The first app-level widget types of the top route's page (cached for 5 s).
  static String _currentScreen() {
    final now = DateTime.now();
    if (now.difference(_lastScreenLookup) < const Duration(seconds: 5)) return _lastScreen;
    _lastScreenLookup = now;
    try {
      final route = topRoute;
      final ctx = route is ModalRoute ? route.subtreeContext : null;
      if (ctx == null) return _lastScreen = route?.runtimeType.toString() ?? '?';
      final names = <String>[];
      void visit(Element e, int depth) {
        if (names.length >= 4 || depth > 40) return;
        final t = e.widget.runtimeType.toString();
        if (!t.startsWith('_') && !_frameworkWidgets.contains(t.split('<').first)) names.add(t);
        e.visitChildElements((c) => visit(c, depth + 1));
      }
      (ctx as Element).visitChildElements((c) => visit(c, 0));
      return _lastScreen = names.isEmpty ? route.runtimeType.toString() : names.join(' > ');
    } catch (_) {
      return _lastScreen;
    }
  }

  static const Set<String> _frameworkWidgets = {
    'Semantics', 'Builder', 'KeyedSubtree', 'RepaintBoundary', 'Actions', 'Focus', 'FocusScope',
    'PrimaryScrollController', 'Material', 'AnimatedBuilder', 'ListenableBuilder', 'Listener',
    'MouseRegion', 'IgnorePointer', 'Offstage', 'TickerMode', 'PageStorage', 'Directionality',
    'MediaQuery', 'DefaultTextStyle', 'AnimatedDefaultTextStyle', 'NotificationListener', 'Shortcuts',
    'DecoratedBox', 'Container', 'Padding', 'Align', 'Center', 'SizedBox', 'ConstrainedBox',
    'LimitedBox', 'ColoredBox', 'ClipRect', 'ClipRRect', 'Stack', 'Column', 'Row', 'Flex',
    'Expanded', 'Flexible', 'Positioned', 'FadeTransition', 'SlideTransition', 'ScaleTransition',
    'DualTransitionBuilder', 'Theme', 'AnimatedTheme', 'IconTheme', 'Scaffold', 'ScaffoldMessenger',
    'SafeArea', 'Opacity', 'CustomPaint', 'LayoutBuilder', 'ValueListenableBuilder', 'StreamBuilder',
    'FutureBuilder', 'Consumer', 'ProviderScope', 'UncontrolledProviderScope', 'PopScope',
    'BlurOnDialogPageTransition', 'FractionalTranslation', 'Transform', 'GestureDetector',
    'RawGestureDetector', 'Hero', 'Title', 'Overlay', 'CallbackShortcuts', 'ExcludeSemantics',
    'MergeSemantics', 'BackdropFilter', 'ImageFiltered', 'ShaderMask', 'PhysicalModel',
    'AnimatedPhysicalModel', 'AnimatedContainer', 'AnimatedOpacity', 'AnimatedSwitcher',
  };

  /// Record what is about to run (keeps the last 16; a label repeated back to back is
  /// counted instead of pushing the other steps out).
  static void mark(String label) {
    final now = DateTime.now();
    _lastMarkAt = now;
    final stamp = now.toIso8601String().substring(11, 23);
    if (label == _lastLabel && _crumbs.isNotEmpty) {
      _repeat++;
      _crumbs[_crumbs.length - 1] = '$stamp $label (x${_repeat + 1})';
      return;
    }
    _lastLabel = label;
    _repeat = 0;
    _crumbs.add('$stamp $label');
    if (_crumbs.length > 16) _crumbs.removeAt(0);
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
        // A very long gap after minutes without any activity is usually Windows sleeping or
        // throttling the app (screen off, standby), not the app hanging.
        final idleBefore = now.difference(_lastMarkAt).inSeconds - (lateMs + 250) ~/ 1000;
        final likelySleep = lateMs > 60000 && idleBefore > 120;
        final msg = '[UiStall] UI thread blocked for ~${lateMs + 250} ms'
            '${likelySleep ? ' (probably Windows sleep/standby: no activity for ${idleBefore ~/ 60} min before)' : ''}'
            '. Recent steps: ${_crumbs.join(" | ")}';
        debugPrint(msg);
        PerfLog.write(msg);
        // Let the user know what held things up and that the app is responsive again.
        if (!likelySleep) BusyStatus.reportRecovered(lateMs + 250, _lastLabel);
      }
    });
    SchedulerBinding.instance.addTimingsCallback((List<ui.FrameTiming> timings) {
      for (final t in timings) {
        final build = t.buildDuration.inMilliseconds;
        final raster = t.rasterDuration.inMilliseconds;
        if (build > 120 || raster > 120) {
          final msg = '[UiStall] Slow frame: build $build ms, raster $raster ms. Screen: ${_currentScreen()}. '
              'Recent steps: ${_crumbs.join(" | ")}';
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
