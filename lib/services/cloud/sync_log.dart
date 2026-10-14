import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persistent upload log (`gmwf_sync.log`, next to gmwf_perf.log).
///
/// Release builds print nothing anywhere, so without this file there is no way to tell
/// at a clinic why data did not reach Firestore. Lines are buffered and appended every
/// few seconds; the file rolls over to `gmwf_sync.log.1` at 2 MB.
class SyncLog {
  SyncLog._();

  static const int _maxBytes = 2 * 1024 * 1024;
  static final List<String> _buffer = [];
  static Timer? _flushTimer;
  static File? _file;
  static bool _flushing = false;

  static void write(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    debugPrint('[SyncLog] $message');
    _buffer.add(line);
    if (_buffer.length > 2000) _buffer.removeRange(0, _buffer.length - 2000);
    _flushTimer ??= Timer(const Duration(seconds: 3), _flush);
  }

  static Future<void> _flush() async {
    _flushTimer = null;
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;
    final lines = List<String>.of(_buffer);
    _buffer.clear();
    try {
      final file = _file ??= File(p.join((await getApplicationSupportDirectory()).path, 'gmwf_sync.log'));
      if (await file.exists() && await file.length() > _maxBytes) {
        final old = File('${file.path}.1');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
        _file = File(file.path);
      }
      await _file!.writeAsString('${lines.join('\n')}\n', mode: FileMode.append);
    } catch (_) {
      // No file system (tests) or the log is locked: the lines were still printed.
    } finally {
      _flushing = false;
    }
  }
}
