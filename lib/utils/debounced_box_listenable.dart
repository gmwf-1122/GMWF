// lib/utils/debounced_box_listenable.dart
//
// Hive's `box.listenable()` notifies on EVERY put/delete. During a sync, a catch-up or a
// backfill the entries box changes hundreds of times within seconds, and each notification
// rebuilt the whole queue / token list (sort + build of every row) on the UI thread, which is
// what made the receptionist, doctor and dispenser screens lag and freeze.
//
// This wrapper delivers the first change immediately (so issuing a token still feels instant),
// then collapses any further changes within [cooldown] into one trailing notification.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DebouncedBoxListenable extends ChangeNotifier implements ValueListenable<Box> {
  final Box _box;
  final Duration cooldown;
  late final ValueListenable<Box> _source;
  Timer? _timer;
  bool _pending = false;
  bool _disposed = false;

  DebouncedBoxListenable(this._box, {this.cooldown = const Duration(milliseconds: 350)}) {
    _source = _box.listenable();
    _source.addListener(_onSourceChanged);
  }

  Box get box => _box;

  static final Map<String, DebouncedBoxListenable> _cache = {};

  /// One shared debounced listenable per box (rebuilds create no new listeners). If the box was
  /// closed and reopened, a fresh wrapper is created for the new instance.
  static DebouncedBoxListenable shared(Box box, {Duration cooldown = const Duration(milliseconds: 350)}) {
    final c = _cache[box.name];
    if (c != null && identical(c._box, box) && box.isOpen) return c;
    return _cache[box.name] = DebouncedBoxListenable(box, cooldown: cooldown);
  }

  @override
  Box get value => _box;

  void _onSourceChanged() {
    if (_disposed) return;
    if (_timer?.isActive ?? false) {
      _pending = true; // a notification is already scheduled for the end of the cooldown
      return;
    }
    notifyListeners(); // leading edge: respond right away
    _timer = Timer(cooldown, _onCooldownEnd);
  }

  void _onCooldownEnd() {
    if (_disposed) return;
    if (_pending) {
      _pending = false;
      notifyListeners(); // trailing edge: one rebuild for everything that changed meanwhile
      _timer = Timer(cooldown, _onCooldownEnd);
    } else {
      _timer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _source.removeListener(_onSourceChanged);
    super.dispose();
  }
}
