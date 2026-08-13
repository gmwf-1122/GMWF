// lib/services/camp_session_service.dart

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class CampSessionService {
  static const String _activeCampKey = 'active_camp_id';

  static const Map<String, String> _knownLabels = {
    'kapayya': 'Kapayya Dispensary',
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

  /// Get the currently active selected camp ID for this session from Hive.
  /// Falls back to assigned camp from user profile if active_camp_id is not set.
  static String? getActiveCamp() {
    try {
      final bound = getBoundDispensaryId();
      if (bound != null && bound.isNotEmpty) {
        return bound; // Priority 1: Fixed hardware desk binding
      }

      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final manualVal = box.get(_activeCampKey)?.toString().trim().toLowerCase();
        if (manualVal != null && manualVal.isNotEmpty && manualVal != 'all') {
          return manualVal;
        }

        final uData = box.get('user_data') ?? box.get('currentUser');
        if (uData is Map) {
          final userMap = Map<String, dynamic>.from(uData);
          final matching = getMatchingScheduledCamps(userMap);
          if (matching.length == 1) {
            return matching.first;
          }

          final assigned = getAssignedCamps(userMap);
          if (assigned.contains('haji_camp') && assigned.contains('kapayya')) {
            return getCurrentSession() == 'evening' ? 'haji_camp' : 'kapayya';
          }
        }
      }

      final assigned = getAssignedCampsFromHive();
      if (assigned.contains('haji_camp') && assigned.contains('kapayya')) {
        return getCurrentSession() == 'evening' ? 'haji_camp' : 'kapayya';
      }

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

  /// Returns a clean short keyword tag for token serial prefixes (e.g. 'KAP', 'HAJI', 'DISP1')
  static String getDispensaryKeyword(String? id) {
    final effective = (id != null && id.trim().isNotEmpty && id.trim().toLowerCase() != 'all')
        ? id.trim().toLowerCase()
        : (getActiveCamp() ?? 'disp');

    if (effective.contains('kapayya') || effective.contains('kap')) return 'KAP';
    if (effective.contains('haji')) return 'HAJI';
    final parts = effective.split(RegExp(r'[^a-z0-9]')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'DISP';
    if (parts.length == 1) {
      final s = parts.first.toUpperCase();
      return s.length > 4 ? s.substring(0, 4) : s;
    }
    return parts.map((p) => p[0].toUpperCase()).join();
  }

  /// List of all known camps in the system.
  static const List<Map<String, String>> allCampsList = [
    {'id': 'kapayya', 'label': 'Kapayya Dispensary'},
    {'id': 'haji_camp', 'label': 'Haji Camp Dispensary'},
  ];

  /// Returns available camp options for the current user/context.
  /// Higher-level users (Admins, Global Admins, Supervisors, HQ Managers, Doctors) get all camps.
  static List<Map<String, String>> getAvailableCampOptions([Map<String, dynamic>? userData]) {
    final assigned = getAssignedCampsFromHive();

    bool isHigherLevel = false;
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final uData = userData ?? box.get('user_data') ?? box.get('currentUser');
        if (uData is Map) {
          final role = (uData['role'] ?? uData['userRole'] ?? '').toString().toLowerCase();
          if (role.contains('admin') || role.contains('supervisor') || role.contains('manager') || role.contains('chairman') || role.contains('doctor')) {
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

  /// Get all camps scheduled for the current time or session.
  static List<String> getMatchingScheduledCamps(Map<String, dynamic> userData) {
    final List<String> matching = [];
    try {
      final scheduleRaw = userData['campSchedule'];
      if (scheduleRaw is! List || scheduleRaw.isEmpty) return matching;

      final currentShift = getCurrentSession();
      final now = getAuthoritativeTime();
      final nowMinutes = now.hour * 60 + now.minute;

      for (final entry in scheduleRaw) {
        if (entry is! Map) continue;
        final campId = entry['campId']?.toString().trim().toLowerCase();
        if (campId == null || campId.isEmpty) continue;

        final session = entry['session']?.toString().trim().toLowerCase();
        if (session != null && session.isNotEmpty) {
          if ((session == 'all' || session == currentShift) && !matching.contains(campId)) {
            matching.add(campId);
            continue;
          }
        }

        final startStr = entry['startTime']?.toString().trim();
        final endStr = entry['endTime']?.toString().trim();

        if (startStr != null && endStr != null) {
          final startMinutes = _parseMinutes(startStr);
          final endMinutes = _parseMinutes(endStr);

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
      return null;
    }

    if (hiveActive != null && (assigned.isEmpty || assigned.contains(hiveActive))) {
      return hiveActive;
    }

    return null;
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
