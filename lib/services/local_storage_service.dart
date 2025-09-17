import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';

class LocalStorageService {
  static const String usersBox = 'local_users';
  static const String patientsBox = 'local_patients';
  static const String syncBox = 'sync_queue';

  /// Initialize Hive
  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      if (!Hive.isBoxOpen(usersBox)) Hive.openBox(usersBox),
      if (!Hive.isBoxOpen(patientsBox)) Hive.openBox(patientsBox),
      if (!Hive.isBoxOpen(syncBox)) Hive.openBox(syncBox),
    ]);
  }

  // ---------------------- PASSWORDS ----------------------
  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static bool verifyPassword(String password, String hash) =>
      hashPassword(password) == hash;

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

    await seedOne('admin@gmd.com', 'Admin@123', 'admin');
    await seedOne('supervisor@gmd.com', 'Supervisor@123', 'supervisor');
  }

  static Future<void> saveLocalUser(Map<String, dynamic> user) async {
    final box = Hive.box(usersBox);
    await box.put('user:${user['email']}', user);
  }

  static Map<String, dynamic>? getLocalUserByEmail(String email) {
    final val = Hive.box(usersBox).get('user:$email');
    return val == null ? null : Map<String, dynamic>.from(val as Map);
  }

  static Map<String, dynamic>? getLocalUserByUid(String uid) {
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

  static List<Map<String, dynamic>> getAllLocalUsers() => Hive.box(usersBox)
      .values
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();

  // ---------------------- SYNC QUEUE ----------------------
  static Future<void> enqueueSync(Map<String, dynamic> action) async {
    final box = Hive.box(syncBox);
    final idx = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(idx, action);
  }

  static Map<String, Map<String, dynamic>> getAllSync() {
    final box = Hive.box(syncBox);
    return Map.fromEntries(box.keys.map((k) {
      final v = box.get(k) as Map;
      return MapEntry(k.toString(), Map<String, dynamic>.from(v));
    }));
  }

  static Future<void> removeSyncKey(String key) async =>
      await Hive.box(syncBox).delete(key);
}
