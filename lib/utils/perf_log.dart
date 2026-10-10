// lib/utils/perf_log.dart
//
// Release builds have no console, so the freeze/lag diagnostics ([UiStall], [Perf]) are also
// appended to <app support>/gmwf_perf.log. Open it after a test session to see exactly what was
// slow. Buffered, size-capped, and never throws.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PerfLog {
  PerfLog._();

  static final List<String> _buffer = [];
  static Timer? _flushTimer;
  static File? _file;
  static bool _failed = false;

  static void write(String line) {
    if (kIsWeb || _failed) return;
    _buffer.add('[${DateTime.now().toIso8601String()}] $line');
    if (_buffer.length > 400) _buffer.removeRange(0, _buffer.length - 400);
    _flushTimer ??= Timer(const Duration(seconds: 2), _flush);
  }

  static Future<void> _flush() async {
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final lines = List<String>.from(_buffer);
    _buffer.clear();
    try {
      if (_file == null) {
        final dir = await getApplicationSupportDirectory();
        _file = File(p.join(dir.path, 'gmwf_perf.log'));
      }
      final f = _file!;
      if (await f.exists() && await f.length() > 1024 * 1024) {
        await f.writeAsString('--- log rotated ---\n');
      }
      await f.writeAsString('${lines.join('\n')}\n', mode: FileMode.append, flush: true);
    } catch (_) {
      _failed = true;
    }
  }
}
