import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service managing per-user language preferences across GMWF (Madrassa, settings, and UI).
///
/// Features:
/// - Isolated per-account language: User A selecting Urdu will NOT turn User B into Urdu on the same device.
/// - Default Language: English ('en').
/// - Persistent: Survives app restarts and never resets automatically.
/// - Synchronized across Madrassa, main app settings, and Firestore profile.
class UserLanguageService {
  UserLanguageService._();

  /// Resolves a consistent, normalized identifier for the active account.
  static String getActiveUserKey([String? explicitUserKey]) {
    if (explicitUserKey != null && explicitUserKey.trim().isNotEmpty) {
      return explicitUserKey.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    }

    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final data = box.get('user_data') ?? box.get('currentUser') ?? box.get('user');
        if (data is Map) {
          final id = data['uid'] ?? data['id'] ?? data['username'] ?? data['userName'] ?? data['email'];
          if (id != null && id.toString().trim().isNotEmpty) {
            return id.toString().trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
          }
        }
        final activeUser = box.get('active_user_id') ?? box.get('last_username') ?? box.get('active_login_user');
        if (activeUser != null && activeUser.toString().trim().isNotEmpty) {
          return activeUser.toString().trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        }
      }
    } catch (_) {}

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.uid.isNotEmpty) {
        return user.uid.trim().toLowerCase();
      }
      if (user != null && user.email != null && user.email!.isNotEmpty) {
        return user.email!.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      }
    } catch (_) {}

    return 'default_guest';
  }

  /// Per-user Hive storage key for app language.
  static String getLanguageKey([String? explicitUserKey]) {
    final userKey = getActiveUserKey(explicitUserKey);
    return 'app_language_$userKey';
  }

  /// Per-user Hive storage key for Madrassa locale.
  static String getMadrassaKey([String? explicitUserKey]) {
    final userKey = getActiveUserKey(explicitUserKey);
    return 'madrassa_locale_$userKey';
  }

  /// Gets the language code for the specified or active user ('en' or 'ur').
  /// Default is ALWAYS `en` (English) if not explicitly set by this account.
  static String getLanguage([String? explicitUserKey, String defaultCode = 'en']) {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final langKey = getLanguageKey(explicitUserKey);
        final val = box.get(langKey)?.toString().trim().toLowerCase();
        if (val != null && (val == 'en' || val == 'ur')) {
          return val;
        }

        final madrassaVal = box.get(getMadrassaKey(explicitUserKey))?.toString().trim().toLowerCase();
        if (madrassaVal != null && (madrassaVal == 'en' || madrassaVal == 'ur')) {
          return madrassaVal;
        }
      }
    } catch (_) {}
    return defaultCode;
  }

  /// Sets the language code for the specified or active user.
  static Future<void> setLanguage(String code, {String? explicitUserKey}) async {
    final cleanCode = code.trim().toLowerCase() == 'ur' ? 'ur' : 'en';
    final userKey = getActiveUserKey(explicitUserKey);

    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        await box.put(getLanguageKey(userKey), cleanCode);
        await box.put(getMadrassaKey(userKey), cleanCode);
      }

      // Also persist to SharedPreferences under user-specific key
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('madrassa_locale_$userKey', cleanCode);
        await prefs.setString('madrassa_locale', cleanCode);
      } catch (_) {}

      // Background cloud sync
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'language': cleanCode,
          'madrassa_locale': cleanCode,
          'lastLanguageUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});
      }
    } catch (e) {
      debugPrint('[UserLanguageService] Error setting language: $e');
    }
  }

  /// Toggles language between 'en' and 'ur' for the active user.
  static Future<String> toggleLanguage({String? explicitUserKey}) async {
    final current = getLanguage(explicitUserKey);
    final next = current == 'en' ? 'ur' : 'en';
    await setLanguage(next, explicitUserKey: explicitUserKey);
    return next;
  }

  /// Listenable for language changes of the specified or active user.
  static ValueListenable<Box> listenable([String? explicitUserKey]) {
    final key = getLanguageKey(explicitUserKey);
    final madKey = getMadrassaKey(explicitUserKey);
    return Hive.box('app_settings').listenable(keys: [key, madKey]);
  }
}
