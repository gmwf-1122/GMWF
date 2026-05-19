// lib/services/offline_auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Offline authentication service.
///
/// Credentials are stored per-user so that multiple users can log in on the
/// same device. The last successful login is also remembered so the username
/// field can be pre-filled.
class OfflineAuthService {
  static const String _keyHasLoggedIn   = 'has_logged_in';
  static const String _keyLastUsername  = 'last_username';
  static const String _keyLastLoginTime = 'last_login_time';

  // Per-user keys — include the (lowercased) username/email in the key name.
  static String _pwKey(String u)   => 'pw__${u.trim().toLowerCase()}';
  static String _dataKey(String u) => 'ud__${u.trim().toLowerCase()}';

  // ✅ FIX: Added resetOnError + IOSOptions for better cross-platform reliability.
  // resetOnError: true ensures keystore corruption (common after OS updates) 
  // doesn't permanently block storage — it resets and allows fresh writes.
  //
  // ✅ FIX (Windows Guest Accounts): On Windows, DPAPI (used by flutter_secure_storage
  // for encryption) can hang indefinitely on restricted/guest accounts because it
  // requires a fully-accessible user profile. We use useBackwardCompatibility: true
  // which falls back to a non-DPAPI path on Windows so guest accounts are not blocked.
  static final _secure = FlutterSecureStorage(
    aOptions: const AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true, // Recover from keystore corruption
    ),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock, // Accessible after first unlock
    ),
    // useBackwardCompatibility skips DPAPI encryption on Windows,
    // preventing indefinite hangs on guest/restricted accounts.
    wOptions: const WindowsOptions(useBackwardCompatibility: true),
  );

  // ── Safe timeout wrapper for all secure storage operations ───────────────
  // On Windows guest accounts, DPAPI calls can hang forever instead of throwing.
  // This wrapper ensures we always get a result within 5 seconds.
  static Future<String?> _secureRead(String key) async {
    try {
      return await _secure.read(key: key)
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('[OfflineAuth] ⚠️ Secure storage read timed out for key: $key (guest account DPAPI restriction)');
        return null;
      });
    } catch (e) {
      debugPrint('[OfflineAuth] ⚠️ Secure storage read error for key $key: $e');
      return null;
    }
  }

  static Future<void> _secureWrite(String key, String value) async {
    try {
      await _secure.write(key: key, value: value)
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('[OfflineAuth] ⚠️ Secure storage write timed out for key: $key');
      });
    } catch (e) {
      debugPrint('[OfflineAuth] ⚠️ Secure storage write error for key $key: $e');
    }
  }

  // ── Save credentials after a successful login ────────────────────────────
  /// Returns true if credentials were saved and verified successfully.
  /// Returns false on failure (does NOT throw — caller can handle gracefully).
  static Future<bool> saveCredentials({
    required String usernameOrEmail,
    required String password,
    required Map<String, dynamic> userData,
  }) async {
    final key = usernameOrEmail.trim().toLowerCase();
    debugPrint('[OfflineAuth] Saving credentials for: $key');

    try {
      // Write password
      await _secureWrite(_pwKey(key), password);

      // Verify password write
      final savedPw = await _secureRead(_pwKey(key));
      if (savedPw != password) {
        debugPrint('[OfflineAuth] ❌ Password verification failed — storage may be unavailable');
        return false;
      }
      debugPrint('[OfflineAuth] Password saved and verified');

      // Write user data blob
      await _secureWrite(_dataKey(key), jsonEncode(userData));

      // Verify data write
      final savedData = await _secureRead(_dataKey(key));
      if (savedData == null) {
        debugPrint('[OfflineAuth] ❌ User data verification failed — storage may be unavailable');
        return false;
      }

      // Update shared prefs — always overwrite with the CURRENT user
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHasLoggedIn, true);
      await prefs.setString(_keyLastUsername, key);
      await prefs.setString(_keyLastLoginTime, DateTime.now().toIso8601String());

      debugPrint('[OfflineAuth] ✅ Credentials saved and verified for $key');
      return true;
    } catch (e) {
      // ✅ FIX: Return false instead of rethrowing — the caller should
      // show a warning but NOT block the user from logging in online.
      debugPrint('[OfflineAuth] ❌ Save failed: $e');
      return false;
    }
  }

  // ── Verify credentials (returns user data map or null) ───────────────────
  static Future<Map<String, dynamic>?> verifyOfflineCredentials({
    required String usernameOrEmail,
    required String password,
  }) async {
    final key = usernameOrEmail.trim().toLowerCase();
    debugPrint('[OfflineAuth] Verifying credentials for: $key');

    try {
      // Look up this specific user's credentials directly — do NOT rely on
      // the global _keyHasLoggedIn flag, which only tells us SOMEONE logged in.
      final cachedPw   = await _secureRead(_pwKey(key));
      final cachedData = await _secureRead(_dataKey(key));

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

  // ── Get the last-used username for pre-filling the login field ───────────
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
  // Accepts an optional explicit username so callers can look up any user,
  // not just whoever was last.
  static Future<Map<String, dynamic>?> getCachedUserData({String? usernameOrEmail}) async {
    try {
      String? key = usernameOrEmail?.trim().toLowerCase();

      if (key == null || key.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        key = prefs.getString(_keyLastUsername);
      }

      if (key == null) return null;

      final raw = await _secureRead(_dataKey(key));
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[OfflineAuth] getCachedUserData error: $e');
      return null;
    }
  }

  // ── Update the cached password (called after a successful password change) ─
  static Future<bool> updateCachedPassword(String newPassword, {String? usernameOrEmail}) async {
    try {
      String? key = usernameOrEmail?.trim().toLowerCase();

      if (key == null || key.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        key = prefs.getString(_keyLastUsername);
      }

      if (key == null) {
        debugPrint('[OfflineAuth] updateCachedPassword: no key found');
        return false;
      }

      await _secureWrite(_pwKey(key), newPassword);

      // Verify
      final saved = await _secureRead(_pwKey(key));
      if (saved != newPassword) {
        debugPrint('[OfflineAuth] ❌ Password update verification failed');
        return false;
      }

      debugPrint('[OfflineAuth] ✅ Password updated for $key');
      return true;
    } catch (e) {
      debugPrint('[OfflineAuth] updateCachedPassword error: $e');
      return false;
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
      final pw  = await _secureRead(_pwKey(key));
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

  // ── Debug helper — call this after login to confirm storage is working ────
  static Future<void> debugDumpStoredKeys() async {
    try {
      final all = await _secure.readAll();
      debugPrint('[OfflineAuth] === Stored keys (${all.length}) ===');
      for (final e in all.entries) {
        final preview = e.value.length > 30
            ? '[${e.value.length} chars]'
            : e.value;
        debugPrint('  ${e.key} = $preview');
      }
    } catch (e) {
      debugPrint('[OfflineAuth] debugDumpStoredKeys error: $e');
    }
  }
}
