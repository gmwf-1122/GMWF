// lib/services/camp_session_service.dart

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class CampSessionService {
  static const String _activeCampKey = 'active_camp_id';

  static const Map<String, String> _knownLabels = {
    'saddar': 'Saddar Dispensary',
    'kapayya': 'Saddar Dispensary',
    'kapaya': 'Saddar Dispensary',
    'haji_camp': 'Haji Camp Dispensary',
  };

  /// Returns user-friendly label for a camp ID
  static String getCampLabel(String id) {
    final key = id.trim().toLowerCase();
    if (_knownLabels.containsKey(key)) return _knownLabels[key]!;
    return id.split('_').map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
  }

  /// Checks if a branch operates multi-camp facility sub-locations.
  static bool hasCampsForBranch(String? branchId) {
    if (branchId == null || branchId.trim().isEmpty) return false;
    final b = branchId.trim().toLowerCase();

    // Branches like Gujrat, Sialkot, Jalalpur Jattan, Rawalpindi do NOT operate camps
    const singleFacilityKeywords = [
      'gujrat',
      'sialkot',
      'jalalpur',
      'jattan',
      'rawalpindi',
      'pindi',
    ];
    for (final kw in singleFacilityKeywords) {
      if (b.contains(kw)) return false;
    }

    if (b == 'karachi') return true; // Primary multi-camp branch (Kapayya & Haji Camp)
    try {
      if (Hive.isBoxOpen('local_branches')) {
        final raw = Hive.box('local_branches').get('branch:$b');
        if (raw is Map && raw['dispensaries'] is List) {
          final list = raw['dispensaries'] as List;
          return list.length > 1;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Validates if a serial belongs to the specified branch.
  /// Prevents LAN broadcasts or stale Hive entries from other branches (e.g. 'kap')
  /// from leaking into this branch's queue.
  static bool isSerialMatchingBranch(String? serial, String? branchId) {
    if (serial == null || serial.trim().isEmpty) return true;
    if (branchId == null || branchId.trim().isEmpty) return true;
    final b = branchId.toLowerCase().trim();
    final s = serial.toUpperCase().trim();
    final parts = s.split('-');
    if (parts.length >= 2) {
      final tag = parts[1].toLowerCase();
      // Karianwala tag (KAP)
      if (tag == 'kap' && !b.contains('kap') && !b.contains('karianwala')) return false;
      // Jalalpur Jattan tags (JLJ / JPJ)
      if ((tag == 'jlj' || tag == 'jpj') && !b.contains('jalalpur') && !b.contains('jattan') && !b.contains('temp')) return false;
      // Gujrat tags (GRT / GJT)
      if ((tag == 'grt' || tag == 'gjt') && !b.contains('gujrat')) return false;
      // Sialkot tag (SKT)
      if (tag == 'skt' && !b.contains('sialkot')) return false;
      // Lahore tag (LHR)
      if (tag == 'lhr' && !b.contains('lahore')) return false;
      // Rawalpindi tags (RWP / PND)
      if ((tag == 'rwp' || tag == 'pnd') && !b.contains('rawalpindi') && !b.contains('pindi')) return false;
      // Karachi camp tags (SADD / SADDAR / HAJI / KAPAYYA)
      if ((tag == 'saddar' || tag == 'sadd' || tag == 'haji_camp' || tag == 'haji' || tag == 'kapayya') && !b.contains('karachi')) return false;
    }
    return true;
  }

  /// Get formatted display string combining Branch Name and Camp Name.
  /// If the branch does NOT operate multi-camp facilities, returns ONLY the branch name.
  static String getBranchAndCampDisplayName({
    required String branchName,
    String? branchId,
    String? campId,
  }) {
    if (branchId != null && !hasCampsForBranch(branchId)) {
      return branchName;
    }

    final effectiveCamp = (campId != null && campId.isNotEmpty && campId != 'all')
        ? campId
        : getActiveCamp();

    if (effectiveCamp == null || effectiveCamp.isEmpty || effectiveCamp == 'all') {
      return branchName;
    }
    final campName = getCampLabel(effectiveCamp);
    return '$branchName — $campName';
  }

  static const String _boundCampKey    = 'bound_dispensary_id';
  static const String _serverOffsetKey = 'server_offset_ms';

  /// Get authoritative time adjusted by server clock offset
  static DateTime getAuthoritativeTime() {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final offset = Hive.box('app_settings').get(_serverOffsetKey);
        if (offset is int && offset != 0) {
          return DateTime.now().add(Duration(milliseconds: offset));
        }
      }
    } catch (_) {}
    return DateTime.now();
  }

  /// Update server clock offset whenever cloud or LAN sync completes
  static Future<void> updateServerOffset(DateTime serverTime) async {
    try {
      final offset = serverTime.difference(DateTime.now()).inMilliseconds;
      if (Hive.isBoxOpen('app_settings')) {
        await Hive.box('app_settings').put(_serverOffsetKey, offset);
      }
    } catch (e) {
      debugPrint('[CampSessionService] Error updating server offset: $e');
    }
  }

  /// Get hardware device-desk bound dispensary ID
  static String? getBoundDispensaryId() {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final val = Hive.box('app_settings').get(_boundCampKey)?.toString().trim().toLowerCase();
        if (val != null && val.isNotEmpty && val != 'all') return val;
      }
    } catch (_) {}
    return null;
  }

  /// Bind hardware device to a specific dispensary desk
  static Future<void> setBoundDispensaryId(String? dispensaryId) async {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        if (dispensaryId == null || dispensaryId.trim().isEmpty) {
          await Hive.box('app_settings').delete(_boundCampKey);
        } else {
          await Hive.box('app_settings').put(_boundCampKey, dispensaryId.trim().toLowerCase());
        }
      }
    } catch (e) {
      debugPrint('[CampSessionService] Error setting bound dispensary: $e');
    }
  }

  /// Write-safe camp resolver. Unlike getActiveCamp(), this NEVER falls back
  /// to the mutable, session-wide active_camp_id — so it can't be silently
  /// changed out from under a write operation by another concurrently-open
  /// tab. Returns null (with a debug warning) if this desk has no hardware
  /// binding, rather than guessing.
  static String? requireBoundDispensaryId(String branchId) {
    final bound = getBoundDispensaryId();
    if (bound != null && bound.isNotEmpty) return bound;
    debugPrint(
      '[CampSessionService] ⚠️ requireBoundDispensaryId: no bound dispensary '
      'set for branch "$branchId". Refusing to fall back to the mutable '
      'session-wide active camp for a write operation.',
    );
    return null;
  }

  /// Canonical single source of truth resolver for Shift and DateKey.
  /// Enforces that Night shifts (22:00 to 06:00 crossing midnight) assign 00:00–05:59:59 tokens
  /// to yesterday's dateKey so a single continuous Night shift is never split across calendar dates.
  static ({String session, String dateKey}) resolveShiftAndDateKey([DateTime? time]) {
    final dt = time ?? getAuthoritativeTime();
    final hour = dt.hour;
    final formatter = DateFormat('ddMMyy');

    if (hour >= 6 && hour < 14) {
      return (session: 'morning', dateKey: formatter.format(dt));
    } else if (hour >= 14 && hour < 22) {
      return (session: 'evening', dateKey: formatter.format(dt));
    } else {
      // Night shift: 22:00 to 05:59:59
      if (hour < 6) {
        // Between 00:00 and 05:59:59 — Night shift started yesterday evening!
        final yesterday = dt.subtract(const Duration(days: 1));
        return (session: 'night', dateKey: formatter.format(yesterday));
      } else {
        // Between 22:00 and 23:59:59 — Night shift started today!
        return (session: 'night', dateKey: formatter.format(dt));
      }
    }
  }

  /// Returns 'morning' (06:00 to 14:00), 'evening' (14:00 to 22:00), or 'night' (22:00 to 06:00) for a given DateTime or current local time.
  static String getCurrentSession([DateTime? time]) {
    return resolveShiftAndDateKey(time).session;
  }

  /// Returns the Firestore `serials` date document ID.
  /// For multi-camp branches like Karachi:
  /// - Saddar: '${dateKey}_saddar'
  /// - Haji Camp: '${dateKey}_haji'
  /// For single-camp branches: '${dateKey}'
  static String getCampDateDocId({
    required String branchId,
    required String dateKey,
    String? campId,
    String? dispensaryTag,
    String? serial,
  }) {
    final b = branchId.toLowerCase().trim();
    if (!hasCampsForBranch(b)) return dateKey;

    final ser = (serial ?? '').toUpperCase();
    final tag = (dispensaryTag ?? '').toUpperCase();
    final c = (campId ?? '').toLowerCase();

    if (ser.contains('-HAJI-') || ser.contains('-HC-') || tag == 'HAJI' || tag == 'HC' || c.contains('haji')) {
      return '${dateKey}_haji';
    }
    return '${dateKey}_saddar';
  }

  /// Returns all active Firestore date document IDs for a given dateKey.
  /// For multi-camp branches: ['${dateKey}_saddar', '${dateKey}_haji', dateKey] (includes legacy dateKey).
  /// For single-camp branches: [dateKey].
  static List<String> getAllCampDateDocIds({
    required String branchId,
    required String dateKey,
    String? selectedCamp,
  }) {
    final b = branchId.toLowerCase().trim();
    if (!hasCampsForBranch(b)) return [dateKey];

    final sel = (selectedCamp ?? '').toLowerCase().trim();
    if (sel == 'saddar' || sel == 'kapayya' || sel == 'kap') {
      return ['${dateKey}_saddar', dateKey];
    } else if (sel == 'haji_camp' || sel == 'haji' || sel == 'hc') {
      return ['${dateKey}_haji', dateKey];
    }
    return ['${dateKey}_saddar', '${dateKey}_haji', dateKey];
  }

  /// Returns the Firestore collection name for inventory.
  /// For multi-camp branches like Karachi:
  /// - Saddar: 'inventory_saddar'
  /// - Haji Camp: 'inventory_haji'
  /// For single-camp branches: 'inventory'
  static String getCampInventoryPath({
    required String branchId,
    String? campId,
    String? dispensaryTag,
    String? serial,
  }) {
    final b = branchId.toLowerCase().trim();
    if (!hasCampsForBranch(b)) return 'inventory';

    final ser = (serial ?? '').toUpperCase();
    final tag = (dispensaryTag ?? '').toUpperCase();
    final c = (campId ?? '').toLowerCase();

    if (ser.contains('-HAJI-') || ser.contains('-HC-') || tag == 'HAJI' || tag == 'HC' || c.contains('haji')) {
      return 'inventory_haji';
    }
    return 'inventory_saddar';
  }

  /// Returns all active Firestore inventory collection names for a given branch.
  static List<String> getAllCampInventoryPaths({
    required String branchId,
    String? selectedCamp,
  }) {
    final b = branchId.toLowerCase().trim();
    if (!hasCampsForBranch(b)) return ['inventory'];

    final sel = (selectedCamp ?? '').toLowerCase().trim();
    if (sel == 'saddar' || sel == 'kapayya' || sel == 'kap') {
      return ['inventory_saddar', 'inventory'];
    } else if (sel == 'haji_camp' || sel == 'haji' || sel == 'hc') {
      return ['inventory_haji', 'inventory'];
    }
    return ['inventory_saddar', 'inventory_haji', 'inventory'];
  }

  /// Validates keyword tag uniqueness when creating/editing a dispensary.
  static bool validateDispensaryTagUniqueness(
    List<Map<String, dynamic>> existingDispensaries,
    String tag, {
    String? excludeId,
  }) {
    final normNew = tag.trim().toUpperCase();
    if (normNew.isEmpty) return false;
    for (final d in existingDispensaries) {
      final id = d['id']?.toString();
      if (excludeId != null && id == excludeId) continue;
      final existingTag = (d['dispensaryTag'] ?? getDispensaryKeyword(id)).toString().toUpperCase();
      if (existingTag == normNew) return false; // Collision!
    }
    return true;
  }

  /// Returns the currently active selected camp ID for this session from Hive.
  /// Falls back to assigned camp from user profile if active_camp_id is not set.
  /// Returns null for branches that do NOT operate multi-camp facilities.
  static String? getActiveCamp([String? branchId]) {
    try {
      final effBranch = branchId ?? (() {
        if (Hive.isBoxOpen('app_settings')) {
          final box = Hive.box('app_settings');
          final uData = box.get('user_data') ?? box.get('currentUser');
          if (uData is Map) {
            final b = (uData['branchId'] ?? uData['branch'] ?? uData['selectedBranchId'])?.toString();
            if (b != null && b.isNotEmpty) return b;
          }
          final cb = box.get('current_branch_id')?.toString();
          if (cb != null && cb.isNotEmpty) return cb;
        }
        return null;
      })();

      if (effBranch != null && !hasCampsForBranch(effBranch)) {
        return null;
      }

      final bound = getBoundDispensaryId();
      if (bound != null && bound.isNotEmpty) {
        return bound; // Priority 1: Fixed hardware desk binding
      }

      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final uData = box.get('user_data') ?? box.get('currentUser');
        List<String> userAssigned = [];
        if (uData is Map) {
          userAssigned = getAssignedCamps(Map<String, dynamic>.from(uData));
        }
        if (userAssigned.isEmpty) {
          userAssigned = getAssignedCampsFromHive();
        }

        final manualVal = box.get(_activeCampKey)?.toString().trim().toLowerCase();
        if (manualVal != null && manualVal.isNotEmpty && manualVal != 'all') {
          // Enforce that cached active_camp_id MUST be assigned to current user
          if (userAssigned.isEmpty || userAssigned.contains(manualVal)) {
            return manualVal;
          }
        }

        if (uData is Map) {
          final userMap = Map<String, dynamic>.from(uData);
          final matching = getMatchingScheduledCamps(userMap);
          if (matching.length == 1) {
            return matching.first;
          }

          if (userAssigned.isNotEmpty) {
            return userAssigned.first;
          }
        }
      }

      final assigned = getAssignedCampsFromHive();
      if (assigned.isNotEmpty) {
        return assigned.first;
      }
    } catch (e) {
      debugPrint('[CampSessionService] Error getting active camp: $e');
    }
    return null;
  }

  /// Safely extracts the dateKey from a serial (handles both X-ddmmyy-TAG-SEQ and ddmmyy-TAG-SEQ).
  static String getDateKeyFromSerial(String serial) {
    final s = serial.trim();
    if (s.isEmpty) return '';
    final parts = s.split('-');
    if (parts.isEmpty) return '';
    if (parts[0].toUpperCase() == 'X') {
      return parts.length > 1 ? parts[1] : '';
    }
    return parts[0];
  }

  /// Returns a clean short keyword tag for token serial prefixes (e.g. 'SKT', 'LHR', 'RWP', 'GRT', 'JLJ', 'SADD', 'HAJI', 'KAP')
  static String getDispensaryKeyword(String? id, {String? branchId}) {
    final effectiveCamp = (id != null && id.trim().isNotEmpty && id.trim().toLowerCase() != 'all')
        ? id.trim().toLowerCase()
        : getActiveCamp();

    // 1. Camp level checks first (e.g. for Karachi multi-camp)
    if (effectiveCamp != null && effectiveCamp.isNotEmpty) {
      if (effectiveCamp.contains('saddar') || effectiveCamp.contains('sadd') || effectiveCamp.contains('kapayya') || effectiveCamp.contains('kap')) return 'SADD';
      if (effectiveCamp.contains('haji')) return 'HAJI';
    }

    // 2. Branch level tags for single-facility branches or general branch tokens
    final b = (branchId ?? effectiveCamp ?? '').trim().toLowerCase();
    if (b.contains('sialkot') || b == 'skt') return 'SKT';
    if (b.contains('lahore') || b == 'lhr') return 'LHR';
    if (b.contains('rawalpindi') || b.contains('pindi') || b == 'rwp' || b == 'pnd') return 'RWP';
    if (b.contains('gujrat') || b == 'grt' || b == 'gjt') return 'GRT';
    if (b.contains('jalalpur') || b.contains('jattan') || b == 'jlj' || b == 'jpj') return 'JLJ';
    if (b.contains('karianwala') || b == 'kap') return 'KAP';
    if (b.contains('karachi')) return 'SADD';

    if (effectiveCamp != null && effectiveCamp.isNotEmpty) {
      final parts = effectiveCamp.split(RegExp(r'[^a-z0-9]')).where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        if (parts.length == 1) {
          final s = parts.first.toUpperCase();
          return s.length > 4 ? s.substring(0, 4) : s;
        }
        return parts.map((p) => p[0].toUpperCase()).join();
      }
    }

    return 'DISP';
  }

  /// Unified camp matching for filtering tokens, queues, and summaries across the entire app
  static bool matchesCamp({
    required String selectedCamp,
    String? dispensaryId,
    String? campId,
    String? dispensaryTag,
    String? serial,
  }) {
    final sel = selectedCamp.trim().toLowerCase();
    if (sel == 'all' || sel.isEmpty) return true;

    final isSaddar = sel.contains('saddar') || sel.contains('sadd') || sel.contains('kap');
    final isHaji = sel.contains('haji');

    final dId = (dispensaryId ?? '').trim().toLowerCase();
    final cId = (campId ?? '').trim().toLowerCase();
    final tag = (dispensaryTag ?? '').trim().toUpperCase();
    final ser = (serial ?? '').trim().toUpperCase();

    // 1. Immutable Serial / Tag Check (Highest Priority — never overridden by host PC activeCamp)
    final isExplicitSaddar = ser.contains('-SADD-') || ser.contains('-KAP-') || ser.contains('-KAPAYYA-') || tag == 'SADD' || tag == 'KAP' || tag == 'SADDAR' || tag == 'KAPAYYA';
    final isExplicitHaji   = ser.contains('-HAJI-') || ser.contains('-HAJ-') || ser.contains('-HC-') || tag == 'HAJI' || tag == 'HC' || tag == 'HAJICAMP';

    if (isExplicitSaddar) {
      return isSaddar;
    }
    if (isExplicitHaji) {
      return isHaji;
    }

    // 2. Secondary fallback by dispensaryId / campId
    final isHajiToken = dId.contains('haji') || cId.contains('haji');
    final isSaddarToken = dId.contains('sadd') || dId.contains('kap') || cId.contains('sadd') || cId.contains('kap');

    if (isSaddar) {
      if (isHajiToken) return false;
      return true; // Any token not explicitly tagged as Haji belongs to Saddar / General
    }

    if (isHaji) {
      if (isSaddarToken) return false;
      return isHajiToken;
    }

    // Generic fallback for any other camp ID
    final normSel = sel.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normD = dId.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normC = cId.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normD.isNotEmpty && (normD == normSel || normD.contains(normSel) || normSel.contains(normD))) return true;
    if (normC.isNotEmpty && (normC == normSel || normC.contains(normSel) || normSel.contains(normC))) return true;

    // Serial prefix fallback
    final tagFromSel = getDispensaryKeyword(selectedCamp).toUpperCase();
    if (tagFromSel.isNotEmpty && ser.contains('-$tagFromSel-')) return true;

    return false;
  }

  /// List of all known camps in the system.
  static const List<Map<String, String>> allCampsList = [
    {'id': 'saddar', 'label': 'Saddar Dispensary'},
    {'id': 'haji_camp', 'label': 'Haji Camp Dispensary'},
  ];

  /// Returns available camp options for the current user/context.
  /// Higher-level users (Admins, Global Admins, Supervisors, HQ Managers) get all camps.
  static List<Map<String, String>> getAvailableCampOptions([Map<String, dynamic>? userData]) {
    final assigned = getAssignedCampsFromHive();

    bool isHigherLevel = false;
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final uData = userData ?? box.get('user_data') ?? box.get('currentUser');
        if (uData is Map) {
          final role = (uData['role'] ?? uData['userRole'] ?? '').toString().toLowerCase();
          if (role.contains('admin') || role.contains('supervisor') || role.contains('manager') || role.contains('chairman')) {
            isHigherLevel = true;
          }
        }
      }
    } catch (_) {}

    if (isHigherLevel || assigned.length > 1 || assigned.isEmpty) {
      return allCampsList;
    }

    final filtered = allCampsList.where((c) => assigned.contains(c['id'])).toList();
    return filtered.isNotEmpty ? filtered : allCampsList;
  }

  /// Returns whether the user has only 1 camp and 1 session (or is single-context),
  /// so they should NEVER be prompted with confirmation dialogs or camp selectors.
  static bool isSingleContextUser({String? branchId}) {
    final effBranch = branchId ?? (() {
      try {
        if (Hive.isBoxOpen('app_settings')) {
          final box = Hive.box('app_settings');
          final uData = box.get('user_data') ?? box.get('currentUser');
          if (uData is Map) {
            final b = (uData['branchId'] ?? uData['branch'] ?? uData['selectedBranchId'])?.toString();
            if (b != null && b.isNotEmpty) return b;
          }
          final cb = box.get('current_branch_id')?.toString();
          if (cb != null && cb.isNotEmpty) return cb;
        }
      } catch (_) {}
      return null;
    })();

    if (effBranch != null && !hasCampsForBranch(effBranch)) {
      return true; // Non-multi-camp branch
    }

    if (getBoundDispensaryId() != null) {
      return true; // Fixed hardware desk binding
    }

    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final uData = box.get('user_data') ?? box.get('currentUser');
        if (uData is Map) {
          final userMap = Map<String, dynamic>.from(uData);
          final assignedCamps = getAssignedCamps(userMap);
          final allowedSessions = getUserAllowedSessions(userMap);

          // If user only has 1 assigned camp
          if (assignedCamps.length == 1) {
            return true;
          }

          // If user has <= 1 assigned camp and <= 1 session
          if (assignedCamps.length <= 1 && allowedSessions.length <= 1) {
            return true;
          }

          // If user's matching scheduled camps is 1 and allowed sessions <= 1
          final matching = getMatchingScheduledCamps(userMap);
          if (matching.length == 1 && allowedSessions.length <= 1) {
            return true;
          }
        }
      }
    } catch (_) {}

    final assigned = getAssignedCampsFromHive();
    if (assigned.length <= 1) {
      return true;
    }

    return false;
  }

  static final ValueNotifier<String?> activeCampNotifier = ValueNotifier<String?>(null);

  /// Store the active camp ID into Hive app_settings for this session.
  static Future<void> setActiveCamp(String campId) async {
    try {
      final norm = campId.trim().toLowerCase();
      final box = Hive.isBoxOpen('app_settings')
          ? Hive.box('app_settings')
          : await Hive.openBox('app_settings');
      await box.put(_activeCampKey, norm);
      activeCampNotifier.value = norm;
    } catch (e) {
      debugPrint('[CampSessionService] Error setting active camp: $e');
    }
  }

  /// Clear active camp ID on logout or switch.
  static Future<void> clearActiveCamp() async {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        await Hive.box('app_settings').delete(_activeCampKey);
      }
      activeCampNotifier.value = null;
    } catch (e) {
      debugPrint('[CampSessionService] Error clearing active camp: $e');
    }
  }

  /// Extract all assigned dispensary IDs for a given user data map.
  static List<String> getAssignedCamps(Map<String, dynamic> userData) {
    final List<String> result = [];

    // Check dispensaryIds list first
    if (userData['dispensaryIds'] is List) {
      final rawList = userData['dispensaryIds'] as List;
      for (final item in rawList) {
        final str = item.toString().trim().toLowerCase();
        if (str.isNotEmpty && str != 'all' && !result.contains(str)) {
          result.add(str);
        }
      }
    }

    // Fallback to legacy single dispensaryId
    if (result.isEmpty && userData['dispensaryId'] != null) {
      final str = userData['dispensaryId'].toString().trim().toLowerCase();
      if (str.isNotEmpty && str != 'all') {
        result.add(str);
      }
    }

    // Fallback to campSchedule if dispensaryIds/dispensaryId are empty
    if (result.isEmpty && userData['campSchedule'] is List) {
      final list = userData['campSchedule'] as List;
      for (final item in list) {
        if (item is Map && item['campId'] != null) {
          final str = item['campId'].toString().trim().toLowerCase();
          if (str.isNotEmpty && str != 'all' && !result.contains(str)) {
            result.add(str);
          }
        }
      }
    }

    // Fallback to alternate key names
    if (result.isEmpty) {
      for (final key in ['dispensary', 'camp', 'camps', 'facility', 'facilityId', 'branchCamp']) {
        final val = userData[key];
        if (val is List) {
          for (final item in val) {
            final str = item.toString().trim().toLowerCase();
            if (str.isNotEmpty && str != 'all' && !result.contains(str)) {
              result.add(str);
            }
          }
        } else if (val != null) {
          final str = val.toString().trim().toLowerCase();
          if (str.isNotEmpty && str != 'all' && !result.contains(str)) {
            result.add(str);
          }
        }
      }
    }

    return result;
  }

  /// Retrieves assigned camps by searching all available Hive storage locations.
  static List<String> getAssignedCampsFromHive() {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final uData = box.get('user_data') ?? box.get('currentUser') ?? box.get('active_user');
        if (uData is Map) {
          final assigned = getAssignedCamps(Map<String, dynamic>.from(uData));
          if (assigned.isNotEmpty) return assigned;
        }
      }
    } catch (e) {
      debugPrint('[CampSessionService] app_settings read error: $e');
    }

    try {
      if (Hive.isBoxOpen('local_users')) {
        final box = Hive.box('local_users');
        for (final key in box.keys) {
          try {
            final val = box.get(key);
            if (val is Map) {
              final assigned = getAssignedCamps(Map<String, dynamic>.from(val));
              if (assigned.isNotEmpty) return assigned;
            }
          } catch (_) {
            // Ignore un-adapted Hive objects
          }
        }
      }
    } catch (e) {
      debugPrint('[CampSessionService] local_users read error: $e');
    }

    return [];
  }

  /// Extracts allowed sessions for a user (defaults to ['all'] for admins/supervisors/unrestricted).
  static List<String> getUserAllowedSessions(Map<String, dynamic> userData) {
    final List<String> sessions = [];

    // Check explicit allowedSessions list
    if (userData['allowedSessions'] is List) {
      for (final item in userData['allowedSessions'] as List) {
        final str = item.toString().trim().toLowerCase();
        if (str.isNotEmpty && !sessions.contains(str)) {
          sessions.add(str);
        }
      }
    }

    // Infer from campSchedule if allowedSessions is not explicitly set
    if (sessions.isEmpty && userData['campSchedule'] is List) {
      for (final item in userData['campSchedule'] as List) {
        if (item is Map && item['session'] != null) {
          final s = item['session'].toString().trim().toLowerCase();
          if (s.isNotEmpty && !sessions.contains(s)) {
            sessions.add(s);
          }
        }
      }
    }

    // Role-based un-restriction
    final role = (userData['role'] ?? userData['userRole'] ?? '').toString().toLowerCase();
    if (sessions.isEmpty || sessions.contains('all') ||
        role.contains('admin') || role.contains('supervisor') || role.contains('manager') || role.contains('chairman')) {
      return ['all'];
    }

    return sessions;
  }

  /// Get all camps scheduled for the active session (morning, evening, night).
  static List<String> getMatchingScheduledCamps(Map<String, dynamic> userData) {
    final List<String> matching = [];
    try {
      final scheduleRaw = userData['campSchedule'];
      if (scheduleRaw is! List || scheduleRaw.isEmpty) return matching;

      final currentShift = getCurrentSession();

      for (final entry in scheduleRaw) {
        if (entry is! Map) continue;
        final campId = entry['campId']?.toString().trim().toLowerCase();
        if (campId == null || campId.isEmpty) continue;

        final session = entry['session']?.toString().trim().toLowerCase();
        
        // Priority 1: Direct Session Matching (morning / evening / night / all)
        if (session != null && session.isNotEmpty) {
          if ((session == 'all' || session == currentShift) && !matching.contains(campId)) {
            matching.add(campId);
            continue;
          }
        }

        // Priority 2: Legacy fallback to start/end clock times if session not tagged
        final startStr = entry['startTime']?.toString().trim();
        final endStr   = entry['endTime']?.toString().trim();

        if (startStr != null && endStr != null) {
          final now = getAuthoritativeTime();
          final nowMinutes = now.hour * 60 + now.minute;
          final startMinutes = _parseMinutes(startStr);
          final endMinutes   = _parseMinutes(endStr);

          if (startMinutes != null && endMinutes != null) {
            bool matches = false;
            if (startMinutes <= endMinutes) {
              matches = nowMinutes >= startMinutes && nowMinutes < endMinutes;
            } else {
              matches = nowMinutes >= startMinutes || nowMinutes < endMinutes;
            }

            if (matches && !matching.contains(campId)) {
              matching.add(campId);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CampSessionService] Error resolving schedule: $e');
    }
    return matching;
  }

  /// Resolves the active camp or determines if manual selection is required.
  static String? resolveActiveCamp(Map<String, dynamic> userData) {
    final matchingSchedules = getMatchingScheduledCamps(userData);

    if (matchingSchedules.length == 1) {
      return matchingSchedules.first;
    }

    final hiveActive = getActiveCamp();
    final assigned = getAssignedCamps(userData);

    if (matchingSchedules.length > 1) {
      if (hiveActive != null && matchingSchedules.contains(hiveActive)) {
        return hiveActive;
      }
      return matchingSchedules.first;
    }

    if (hiveActive != null && (assigned.isEmpty || assigned.contains(hiveActive))) {
      return hiveActive;
    }

    return assigned.isNotEmpty ? assigned.first : null;
  }

  static int? _parseMinutes(String timeStr) {
    try {
      final str = timeStr.trim().toUpperCase();
      final isPm = str.contains('PM');
      final isAm = str.contains('AM');

      final cleanStr = str.replaceAll(RegExp(r'[^\d:]'), '');
      final parts = cleanStr.split(':');
      if (parts.length >= 2) {
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);

        if (isPm && h < 12) h += 12;
        if (isAm && h == 12) h = 0;

        return h * 60 + m;
      }
    } catch (_) {}
    return null;
  }
}