class NotificationDeduper {
  static final Map<String, DateTime> _lastShown = <String, DateTime>{};

  static bool shouldShow(String key, {Duration window = const Duration(minutes: 30)}) {
    final now = DateTime.now();
    final last = _lastShown[key];

    if (last != null && now.difference(last) < window) {
      return false;
    }

    _lastShown[key] = now;
    return true;
  }

  static void clear(String key) {
    _lastShown.remove(key);
  }

  static void clearAll() {
    _lastShown.clear();
  }
}
