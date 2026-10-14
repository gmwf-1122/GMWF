import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Service managing user-specific dispensary preferences.
///
/// Features:
/// - Isolated per-account preferences: Each user account maintains its own independent
///   layout and timing display choices on the same local device without cross-contamination.
/// - Default Layout: Normal hybrid separate tabs (false).
/// - Default Timing: Urdu text display (true).
/// - Persistent: Once set, the preference survives app restarts and never resets automatically.
/// - Cloud-synced: Silently syncs to Firestore user document when online.
class DispensaryPreferencesService {
  DispensaryPreferencesService._();

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

  /// Per-user storage key for All-in-One vs Separate tabs layout.
  static String getHybridAllInOneKey([String? explicitUserKey]) {
    final userKey = getActiveUserKey(explicitUserKey);
    return 'hybrid_all_in_one_$userKey';
  }

  /// Per-user storage key for Urdu vs Compact 1+1+1 medicine timing format.
  static String getShowUrduTimingKey([String? explicitUserKey]) {
    final userKey = getActiveUserKey(explicitUserKey);
    return 'show_urdu_timing_$userKey';
  }

  // ── Layout Preference (Default: false = Normal Separate Tabs) ─────────────

  /// Returns whether All-in-One layout is enabled for the specified or active user.
  /// Default is ALWAYS `false` (the normal hybrid separate tabs).
  static bool isHybridAllInOne([String? explicitUserKey]) {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final key = getHybridAllInOneKey(explicitUserKey);
        final val = box.get(key);
        if (val is bool) return val;
      }
    } catch (_) {}
    return false;
  }

  /// Persists layout preference for the specified or active user.
  static Future<void> setHybridAllInOne(bool value, {String? explicitUserKey}) async {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final key = getHybridAllInOneKey(explicitUserKey);
        await box.put(key, value);
      }

      // Background cloud sync
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'dispensaryHybridAllInOne': value,
          'lastPreferenceUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});
      }
    } catch (e) {
      debugPrint('[DispensaryPreferencesService] Error setting hybrid layout: $e');
    }
  }

  /// Toggles layout preference and returns the newly active setting.
  static Future<bool> toggleHybridAllInOne({String? explicitUserKey}) async {
    final current = isHybridAllInOne(explicitUserKey);
    final next = !current;
    await setHybridAllInOne(next, explicitUserKey: explicitUserKey);
    return next;
  }

  /// Listenable for layout changes of the specified or active user.
  static ValueListenable<Box> hybridAllInOneListenable([String? explicitUserKey]) {
    final key = getHybridAllInOneKey(explicitUserKey);
    return Hive.box('app_settings').listenable(keys: [key]);
  }

  // ── Timing Format Preference (Default: true = Urdu Text) ──────────────────

  /// Returns whether Urdu timing text is enabled for the specified or active user.
  /// Default is ALWAYS `true` (Urdu text: صبح / شام / کھانے کے بعد).
  static bool isShowUrduTiming([String? explicitUserKey]) {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final key = getShowUrduTimingKey(explicitUserKey);
        final val = box.get(key);
        if (val is bool) return val;
      }
    } catch (_) {}
    return true;
  }

  /// Persists medicine timing format preference for the specified or active user.
  static Future<void> setShowUrduTiming(bool value, {String? explicitUserKey}) async {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final key = getShowUrduTimingKey(explicitUserKey);
        await box.put(key, value);
        // Same account, resolved from the session: keep both keys identical so screens that
        // don't know the user id read the same preference.
        final activeKey = getShowUrduTimingKey();
        if (activeKey != key) await box.put(activeKey, value);
      }

      // Background cloud sync
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'dispensaryShowUrduTiming': value,
          'lastPreferenceUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});
      }
    } catch (e) {
      debugPrint('[DispensaryPreferencesService] Error setting timing format: $e');
    }
  }

  /// Toggles medicine timing format and returns the newly active setting.
  static Future<bool> toggleShowUrduTiming({String? explicitUserKey}) async {
    final current = isShowUrduTiming(explicitUserKey);
    final next = !current;
    await setShowUrduTiming(next, explicitUserKey: explicitUserKey);
    return next;
  }

  /// Listenable for timing format changes of the specified or active user.
  static ValueListenable<Box> showUrduTimingListenable([String? explicitUserKey]) {
    final key = getShowUrduTimingKey(explicitUserKey);
    return Hive.box('app_settings').listenable(keys: [key]);
  }

  // ── Pharmacy 3-Pane Placement Preference ─────────────────────────────────

  /// Supported pane placement layouts.
  static const String paneLayoutTokensReceptionDispense = 'tokens_reception_dispense';
  static const String paneLayoutTokensDispenseReception = 'tokens_dispense_reception';
  static const String paneLayoutReceptionTokensDispense = 'reception_tokens_dispense';
  static const String paneLayoutReceptionDispenseTokens = 'reception_dispense_tokens';
  static const String paneLayoutDispenseTokensReception = 'dispense_tokens_reception';
  static const String paneLayoutDispenseReceptionTokens = 'dispense_reception_tokens';

  static const List<Map<String, String>> availablePaneLayouts = [
    {
      'id': paneLayoutTokensReceptionDispense,
      'title': 'List · Token · Dispense (Default)',
      'subtitle': 'Tokens on left, Register/Vitals in middle, Dispense on right',
    },
    {
      'id': paneLayoutTokensDispenseReception,
      'title': 'List · Dispense · Token',
      'subtitle': 'Tokens on left, Dispense in middle, Register/Vitals on right',
    },
    {
      'id': paneLayoutReceptionTokensDispense,
      'title': 'Token · List · Dispense',
      'subtitle': 'Register/Vitals on left, Tokens in middle, Dispense on right',
    },
    {
      'id': paneLayoutReceptionDispenseTokens,
      'title': 'Token · Dispense · List',
      'subtitle': 'Register/Vitals on left, Dispense in middle, Tokens on right',
    },
    {
      'id': paneLayoutDispenseTokensReception,
      'title': 'Dispense · List · Token',
      'subtitle': 'Dispense on left, Tokens in middle, Register/Vitals on right',
    },
    {
      'id': paneLayoutDispenseReceptionTokens,
      'title': 'Dispense · Token · List',
      'subtitle': 'Dispense on left, Register/Vitals in middle, Tokens on right',
    },
  ];

  /// Per-user storage key for pharmacy pane order.
  static String getPharmacyPaneOrderKey([String? explicitUserKey]) {
    final userKey = getActiveUserKey(explicitUserKey);
    return 'pharmacy_pane_order_$userKey';
  }

  /// Returns the current pane order id for the specified or active user.
  /// Default: 'tokens_reception_dispense'
  static String getPharmacyPaneOrder([String? explicitUserKey]) {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final key = getPharmacyPaneOrderKey(explicitUserKey);
        final val = box.get(key);
        if (val is String && val.trim().isNotEmpty) return val.trim();
      }
    } catch (_) {}
    return paneLayoutTokensReceptionDispense;
  }

  /// Returns the 3 pane identifiers in ordered sequence: ['tokens', 'reception', 'dispense'], etc.
  static List<String> getPharmacyPanes([String? explicitUserKey]) {
    final order = getPharmacyPaneOrder(explicitUserKey);
    switch (order) {
      case paneLayoutTokensDispenseReception:
        return ['tokens', 'dispense', 'reception'];
      case paneLayoutReceptionTokensDispense:
        return ['reception', 'tokens', 'dispense'];
      case paneLayoutReceptionDispenseTokens:
        return ['reception', 'dispense', 'tokens'];
      case paneLayoutDispenseTokensReception:
        return ['dispense', 'tokens', 'reception'];
      case paneLayoutDispenseReceptionTokens:
        return ['dispense', 'reception', 'tokens'];
      case paneLayoutTokensReceptionDispense:
      default:
        return ['tokens', 'reception', 'dispense'];
    }
  }

  /// Persists pharmacy pane placement preference for the user.
  static Future<void> setPharmacyPaneOrder(String order, {String? explicitUserKey}) async {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final key = getPharmacyPaneOrderKey(explicitUserKey);
        await box.put(key, order);
      }

      // Background cloud sync
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'dispensaryPharmacyPaneOrder': order,
          'lastPreferenceUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});
      }
    } catch (e) {
      debugPrint('[DispensaryPreferencesService] Error setting pane order: $e');
    }
  }

  /// Cycles to the next pane layout and returns the newly active layout id.
  static Future<String> cyclePharmacyPaneOrder({String? explicitUserKey}) async {
    final current = getPharmacyPaneOrder(explicitUserKey);
    final idx = availablePaneLayouts.indexWhere((l) => l['id'] == current);
    final nextIdx = (idx + 1) % availablePaneLayouts.length;
    final nextId = availablePaneLayouts[nextIdx]['id']!;
    await setPharmacyPaneOrder(nextId, explicitUserKey: explicitUserKey);
    return nextId;
  }

  /// Listenable for pane order changes.
  static ValueListenable<Box> pharmacyPaneOrderListenable([String? explicitUserKey]) {
    final key = getPharmacyPaneOrderKey(explicitUserKey);
    return Hive.box('app_settings').listenable(keys: [key]);
  }
}
