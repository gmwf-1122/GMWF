// lib/utils/base64_image_cache.dart
//
// Profile photos are stored as base64 text inside the records. Decoding one with
// `MemoryImage(base64Decode(s))` inside build() decoded it again on every rebuild, and the
// new MemoryImage (new bytes) missed Flutter's image cache, so the picture was also
// re-decoded and re-uploaded to the GPU each time — on the UI thread, for every row.

import 'dart:convert';

import 'package:flutter/painting.dart';

class Base64ImageCache {
  Base64ImageCache._();

  static const int _maxEntries = 200;
  static final Map<int, MemoryImage> _cache = {};

  /// One shared [MemoryImage] per distinct base64 string (an optional `data:...;base64,`
  /// prefix and whitespace are ignored). Throws [FormatException] for invalid base64, like
  /// base64Decode.
  static MemoryImage of(String base64Text) {
    final key = Object.hash(base64Text.length, base64Text.hashCode);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recently used last
      return hit;
    }
    var s = base64Text;
    final comma = s.indexOf(',');
    if (s.startsWith('data:') && comma > 0) s = s.substring(comma + 1);
    final image = MemoryImage(base64Decode(s.replaceAll(RegExp(r'\s+'), '')));
    _cache[key] = image;
    if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
    return image;
  }
}
