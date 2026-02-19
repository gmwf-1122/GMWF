// lib/services/offline_auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Offline authentication service.
///
/// Credentials are stored per-user so that multiple users can log in on the
/// same device.  The last successful login is also remembered so the username
/// field can be pre-filled.
class OfflineAuthService {
  static const String _keyHasLoggedIn   = 'has_logged_in';
  static const String _keyLastUsername  = 'last_username';
  static const String _keyLastLoginTime = 'last_login_time';

  // Per-user keys — include the (lowercased) username/email in the key name.
  static String _pwKey(String u)   => 'pw__${u.trim().toLowerCase()}';
  static String _dataKey(String u) => 'ud__${u.trim().toLowerCase()}';

  static const _secure = FlutterSecureStorage(
    // Use DataProtection on iOS / AES encryption on Android
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Save credentials after a successful login ─────────────────────────────
  static Future<void> saveCredentials({
    required String usernameOrEmail,
    required String password,
    required Map<String, dynamic> userData,
  }) async {
    final key = usernameOrEmail.trim().toLowerCase();
    debugPrint('[OfflineAuth] Saving credentials for: $key');

    try {
      // Per-user password
      await _secure.write(key: _pwKey(key), value: password);

      // Verify it was stored
      final saved = await _secure.read(key: _pwKey(key));
      if (saved != password) {
        throw Exception('Password verification failed after save');
      }
      debugPrint('[OfflineAuth] Password saved and verified');

      // Per-user data blob
      await _secure.write(key: _dataKey(key), value: jsonEncode(userData));

      // Global "has logged in" flag + last username (for pre-fill)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHasLoggedIn, true);
      await prefs.setString(_keyLastUsername, key);
      await prefs.setString(_keyLastLoginTime, DateTime.now().toIso8601String());

      debugPrint('[OfflineAuth] ✅ Credentials saved for $key');
    } catch (e) {
      debugPrint('[OfflineAuth] ❌ Save failed: $e');
      rethrow;
    }
  }

  // ── Verify credentials (returns user data map or null) ────────────────────
  static Future<Map<String, dynamic>?> verifyOfflineCredentials({
    required String usernameOrEmail,
    required String password,
  }) async {
    final key = usernameOrEmail.trim().toLowerCase();
    debugPrint('[OfflineAuth] Verifying credentials for: $key');

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_keyHasLoggedIn) ?? false)) {
        debugPrint('[OfflineAuth] No previous login recorded');
        return null;
      }

      final cachedPw   = await _secure.read(key: _pwKey(key));
      final cachedData = await _secure.read(key: _dataKey(key));

      if (cachedPw == null || cachedData == null) {
        debugPrint('[OfflineAuth] No cached credentials found for $key');
        return null;
      }

      if (password != cachedPw) {
        debugPrint('[OfflineAuth] Password mismatch for $key');
        return null;
      }

      final userData = jsonDecode(cachedData) as Map<String, dynamic>;
      debugPrint('[OfflineAuth] ✅ Verified: $key → role=${userData['role']}');
      return userData;
    } catch (e) {
      debugPrint('[OfflineAuth] ❌ Verify error: $e');
      return null;
    }
  }

  // ── Get the last-used username for pre-filling the login field ────────────
  static Future<String?> getCachedUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_keyHasLoggedIn) ?? false)) return null;
      return prefs.getString(_keyLastUsername);
    } catch (e) {
      debugPrint('[OfflineAuth] getCachedUsername error: $e');
      return null;
    }
  }

  // ── Get cached user data for the last-logged-in user ─────────────────────
  static Future<Map<String, dynamic>?> getCachedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUser = prefs.getString(_keyLastUsername);
      if (lastUser == null) return null;

      final raw = await _secure.read(key: _dataKey(lastUser));
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[OfflineAuth] getCachedUserData error: $e');
      return null;
    }
  }

  // ── Update the cached password (called after a password change) ───────────
  static Future<void> updateCachedPassword(String newPassword) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUser = prefs.getString(_keyLastUsername);
      if (lastUser == null) return;

      await _secure.write(key: _pwKey(lastUser), value: newPassword);

      // Verify
      final saved = await _secure.read(key: _pwKey(lastUser));
      if (saved != newPassword) {
        throw Exception('Password update verification failed');
      }
      debugPrint('[OfflineAuth] ✅ Password updated for $lastUser');
    } catch (e) {
      debugPrint('[OfflineAuth] updateCachedPassword error: $e');
      rethrow;
    }
  }

  // ── Misc helpers ──────────────────────────────────────────────────────────
  static Future<bool> hasLoggedInBefore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyHasLoggedIn) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<DateTime?> getLastLoginTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_keyLastLoginTime);
      return s != null ? DateTime.parse(s) : null;
    } catch (_) {
      return null;
    }
  }

  /// Checks whether credentials for a specific user have been cached.
  static Future<bool> hasCachedCredentialsFor(String usernameOrEmail) async {
    try {
      final key = usernameOrEmail.trim().toLowerCase();
      final pw = await _secure.read(key: _pwKey(key));
      return pw != null && pw.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Clear ALL cached credentials (full logout / reset).
  static Future<void> clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyHasLoggedIn);
      await prefs.remove(_keyLastUsername);
      await prefs.remove(_keyLastLoginTime);
      await _secure.deleteAll();
      debugPrint('[OfflineAuth] ✅ All credentials cleared');
    } catch (e) {
      debugPrint('[OfflineAuth] clearCredentials error: $e');
      rethrow;
    }
  }

  static Future<bool> areCredentialsExpired({int maxDays = 30}) async {
    final lastLogin = await getLastLoginTime();
    if (lastLogin == null) return true;
    return DateTime.now().difference(lastLogin).inDays > maxDays;
  }
}