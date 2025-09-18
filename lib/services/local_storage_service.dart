import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocalStorageService {
  static const String usersBox = 'local_users';
  static const String patientsBox = 'local_patients';
  static const String syncBox = 'sync_queue';

  /// Initialize Hive
  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(usersBox)) await Hive.openBox(usersBox);
    if (!Hive.isBoxOpen(patientsBox)) await Hive.openBox(patientsBox);
    if (!Hive.isBoxOpen(syncBox)) await Hive.openBox(syncBox);
  }

  /// Clear all local cache (users, patients, sync)
  static Future<void> clear() async {
    if (Hive.isBoxOpen(usersBox)) await Hive.box(usersBox).clear();
    if (Hive.isBoxOpen(patientsBox)) await Hive.box(patientsBox).clear();
    if (Hive.isBoxOpen(syncBox)) await Hive.box(syncBox).clear();
  }

  // ---------------------- PASSWORDS ----------------------
  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static bool verifyPassword(String password, String? hash) {
    if (hash == null) return false;
    return hashPassword(password) == hash;
  }

  // ---------------------- HELPERS ----------------------
  /// Convert Firestore Timestamps/DateTimes and nested structures into
  /// plain Dart values Hive can store (strings, lists, maps).
  static Map<String, dynamic> _sanitize(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    data.forEach((key, value) {
      if (value == null) {
        result[key] = null;
      } else if (value is Timestamp) {
        result[key] = value.toDate().toIso8601String();
      } else if (value is DateTime) {
        result[key] = value.toIso8601String();
      } else if (value is Map) {
        // recursive sanitize
        result[key] = _sanitize(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((e) {
          if (e is Timestamp) return e.toDate().toIso8601String();
          if (e is DateTime) return e.toIso8601String();
          if (e is Map) return _sanitize(Map<String, dynamic>.from(e));
          return e;
        }).toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  // ---------------------- LOCAL USERS ----------------------
  static Future<void> seedLocalAdmins() async {
    final box = Hive.box(usersBox);

    Future<void> seedOne(String email, String password, String role) async {
      final key = 'user:$email';
      if (!box.containsKey(key)) {
        await box.put(key, {
          'email': email,
          'passwordHash': hashPassword(password),
          'role': role,
          'uid': 'local-${email.replaceAll('@', '_').replaceAll('.', '_')}',
          'branchId': 'all',
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    }

    // Only the predetermined admin is seeded (per your request)
    await seedOne('admin@gmd.com', 'Admin@123', 'admin');
  }

  static Future<void> saveLocalUser(Map<String, dynamic> user) async {
    if (user['email'] == null) return;
    final box = Hive.box(usersBox);
    final sanitized = _sanitize(user);
    await box.put('user:${sanitized['email']}', sanitized);
  }

  static Map<String, dynamic>? getLocalUserByEmail(String email) {
    if (!Hive.isBoxOpen(usersBox)) return null;
    final val = Hive.box(usersBox).get('user:$email');
    if (val == null) return null;
    try {
      return Map<String, dynamic>.from(val as Map);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? getLocalUserByUid(String uid) {
    if (!Hive.isBoxOpen(usersBox)) return null;
    final box = Hive.box(usersBox);
    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map && val['uid'] == uid) {
        return Map<String, dynamic>.from(val);
      }
    }
    return null;
  }

  static Future<void> deleteLocalUser(String email) async =>
      await Hive.box(usersBox).delete('user:$email');

  static List<Map<String, dynamic>> getAllLocalUsers() {
    if (!Hive.isBoxOpen(usersBox)) return [];
    return Hive.box(usersBox)
        .values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  // ---------------------- SYNC QUEUE ----------------------
  static Future<void> enqueueSync(Map<String, dynamic> action) async {
    final box = Hive.box(syncBox);
    final idx = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(idx, _sanitize(action));
  }

  static Map<String, Map<String, dynamic>> getAllSync() {
    if (!Hive.isBoxOpen(syncBox)) return {};
    final box = Hive.box(syncBox);
    return Map.fromEntries(box.keys.map((k) {
      final v = box.get(k) as Map;
      return MapEntry(k.toString(), Map<String, dynamic>.from(v));
    }));
  }

  static Future<void> removeSyncKey(String key) async =>
      await Hive.box(syncBox).delete(key);
}
