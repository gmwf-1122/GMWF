// lib/pages/dispensary/dispensar/dispense_queue.dart
//
// The dispenser's queue rules in one place: which of today's entries are in the
// dispense queue, how they are ordered (pending → on hold → dispensed, smallest
// token first), and which patient to load next. Used by the Dispenser's
// PatientList and by the Hybrid Pharmacy tab so the two never disagree.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/serials_service.dart';

class DispenseQueue {
  DispenseQueue._();

  static bool isOnHold(Map<String, dynamic> e) {
    final ds = (e['dispenseStatus'] ?? '').toString().toLowerCase();
    return ds == 'on_hold' || ds == 'hold';
  }

  static bool isDispensed(Map<String, dynamic> e) {
    return (e['dispenseStatus'] ?? '').toString().toLowerCase() == 'dispensed';
  }

  /// Whether the entry belongs to today's shift date. A token shows only on the date in its
  /// serial: with the old 24-hour carry-over, yesterday's tokens sat in today's list and a
  /// search for a slip's number could open yesterday's token and its medicines.
  static bool isEffectivelyToday(
    Map<String, dynamic> e,
    String currentTodayKey,
    String todayIso,
    String branchId,
  ) =>
      CampSessionService.isTokenOnDate(e, currentTodayKey, branchId);

  static Map<String, dynamic> _userData() {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final data = box.get('user_data') ?? box.get('currentUser');
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (_) {}
    return {};
  }

  /// The dispense queue for [branchId], ordered pending → on hold → dispensed
  /// (each by token number). [filter] is 'all', 'pending' or 'dispensed';
  /// [sessionFilter] is 'all', 'auto' or a shift name; [campFilter] is the
  /// selected camp ('all' for none).
  static List<Map<String, dynamic>> compute({
    required String branchId,
    String sessionFilter = 'all',
    String campFilter = 'all',
    String searchQuery = '',
    bool newestFirst = false,
    String filter = 'all',
  }) {
    final todayKey = CampSessionService.resolveShiftAndDateKey(null, branchId).dateKey;
    final hasMultiCamps = CampSessionService.hasCampsForBranch(branchId);
    final userData = _userData();
    final allowedSessions = CampSessionService.getAllowedSessions(branchId, userData: userData);
    final scheduledCamps = CampSessionService.getMatchingScheduledCamps(userData);
    final effectiveCamp = hasMultiCamps
        ? ((campFilter.isNotEmpty && campFilter != 'all')
            ? campFilter
            : (scheduledCamps.isNotEmpty
                ? scheduledCamps.first
                : CampSessionService.getActiveCamp(branchId)))
        : null;

    final allList = List<Map<String, dynamic>>.from(LocalStorageService.getLocalEntries(branchId));
    final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());

    var all = allList.where((e) {
      final serial = (e['serial'] ?? e['id'] ?? '').toString().trim();

      if (!CampSessionService.isSerialMatchingBranch(serial, branchId)) {
        return false;
      }

      if (!isEffectivelyToday(e, todayKey, todayIso, branchId)) return false;

      final presc = (e['prescription'] is Map && (e['prescription'] as Map).isNotEmpty)
          ? Map<String, dynamic>.from(e['prescription'] as Map)
          : (serial.isNotEmpty && Hive.isBoxOpen(LocalStorageService.prescriptionsBox)
              ? (() {
                  final pBox = Hive.box(LocalStorageService.prescriptionsBox);
                  final raw = pBox.get(serial) ?? pBox.get(serial.toLowerCase()) ?? pBox.get(serial.toUpperCase());
                  return raw is Map ? Map<String, dynamic>.from(raw) : null;
                })()
              : null);
      final status = (e['status'] ?? '').toString().toLowerCase();
      final isDisp = (e['dispenseStatus'] ?? '').toString().toLowerCase() == 'dispensed' || status == 'dispensed';
      final hasPresc = presc != null && (
        (presc['prescriptions'] is List && (presc['prescriptions'] as List).isNotEmpty) ||
        (presc['medicines'] is List && (presc['medicines'] as List).isNotEmpty) ||
        (presc['isVitalsOnly'] == true && presc['completedAt'] != null)
      );

      var name = (e['patientName'] ?? e['name'] ?? '').toString().trim().toLowerCase();
      var cnic = (e['patientCnic'] ?? e['cnic'] ?? e['guardianCnic'] ?? '').toString().trim();

      // Fall back to prescription details if entry name/cnic is missing
      if ((name.isEmpty || name == 'unknown patient' || name == 'unknown') && presc != null) {
        final prName = (presc['patientName'] ?? presc['name'])?.toString().trim();
        if (prName != null && prName.isNotEmpty && prName.toLowerCase() != 'unknown' && prName.toLowerCase() != 'unknown patient') {
          name = prName.toLowerCase();
          e['patientName'] = prName;
        }
        final prCnic = (presc['patientCnic'] ?? presc['cnic'] ?? presc['guardianCnic'])?.toString().trim();
        if (prCnic != null && prCnic.isNotEmpty) {
          cnic = prCnic;
          e['cnic'] = prCnic;
        }
      }

      if ((name.isEmpty || name == 'unknown patient' || name == 'unknown') && cnic.isEmpty) {
        if (serial.isNotEmpty && Hive.isBoxOpen(LocalStorageService.entriesBox)) {
          final box = Hive.box(LocalStorageService.entriesBox);
          final raw = box.get('$branchId-$serial') ?? box.get(serial) ?? box.get(serial.toUpperCase());
          if (raw is Map) {
            final rName = (raw['patientName'] ?? raw['name'] ?? '').toString().trim();
            final rCnic = (raw['patientCnic'] ?? raw['cnic'] ?? raw['guardianCnic'] ?? '').toString().trim();
            if (rName.isNotEmpty && rName.toLowerCase() != 'unknown' && rName.toLowerCase() != 'unknown patient') {
              name = rName.toLowerCase();
              e['patientName'] = rName;
            }
            if (rCnic.isNotEmpty) {
              cnic = rCnic;
              e['cnic'] = rCnic;
            }
          }
        }
        if ((name.isEmpty || name == 'unknown patient' || name == 'unknown') && cnic.isEmpty) {
          // If token has prescription or completed status, NEVER hide it from dispenser!
          if (hasPresc || status == 'completed' || status == 'dispensed' || isDisp) {
            name = 'token #$serial';
            e['patientName'] = 'Token #$serial';
          } else {
            return false;
          }
        }
      }

      // Camp matching in multi-camp branches
      if (hasMultiCamps && effectiveCamp != null && effectiveCamp.isNotEmpty && effectiveCamp != 'all') {
        final matches = CampSessionService.matchesCamp(
          selectedCamp: effectiveCamp,
          dispensaryId: e['dispensaryId']?.toString(),
          campId: e['campId']?.toString(),
          dispensaryTag: e['dispensaryTag']?.toString(),
          serial: serial,
        );
        if (!matches) return false;
      }

      return (status == 'completed' || status == 'dispensed' || status == 'prescribed' || isDisp || hasPresc);
    }).toList();

    // Deduplicate by normalized serial (stripping branch prefix so 'branch-001' and '001' never appear as two patients)
    final Map<String, Map<String, dynamic>> uniqueBySerial = {};
    for (final e in all) {
      String s = (e['serial'] ?? e['id'] ?? '').toString().trim().toUpperCase();
      final branchPrefix = '${branchId.trim().toUpperCase()}-';
      if (s.startsWith(branchPrefix)) {
        s = s.substring(branchPrefix.length);
      }
      if (s.isEmpty) continue;
      if (!uniqueBySerial.containsKey(s)) {
        uniqueBySerial[s] = Map<String, dynamic>.from(e);
      } else {
        final target = uniqueBySerial[s]!;
        e.forEach((k, v) {
          if (v != null && v != '' && v != 'unknown') {
            final old = target[k];
            if (old == null || old == '' || old == 'unknown') {
              target[k] = v;
            }
          }
        });

        // Always prioritize newer prescription data from doctor
        final inRx = e['prescription'];
        final exRx = target['prescription'];
        if (inRx is Map && inRx.isNotEmpty) {
          if (exRx is! Map || exRx.isEmpty) {
            target['prescription'] = inRx;
          } else {
            final inTime = DateTime.tryParse(inRx['updatedAt']?.toString() ?? inRx['completedAt']?.toString() ?? e['completedAt']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
            final exTime = DateTime.tryParse(exRx['updatedAt']?.toString() ?? exRx['completedAt']?.toString() ?? target['completedAt']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
            if (inTime >= exTime) {
              target['prescription'] = inRx;
            }
          }
        }

        final inCompleted = e['status'] == 'completed' || e['status'] == 'dispensed';
        final exCompleted = target['status'] == 'completed' || target['status'] == 'dispensed';
        if (inCompleted && !exCompleted) {
          target['status'] = e['status'];
          if (e['completedAt'] != null) target['completedAt'] = e['completedAt'];
          if (e['doctorName'] != null) target['doctorName'] = e['doctorName'];
          if (e['doctorId'] != null) target['doctorId'] = e['doctorId'];
        }

        final eDisp = (e['dispenseStatus'] ?? e['status'] ?? '').toString().toLowerCase();
        final tDisp = (target['dispenseStatus'] ?? target['status'] ?? '').toString().toLowerCase();
        if (eDisp == 'dispensed' || tDisp == 'dispensed') {
          target['dispenseStatus'] = 'dispensed';
          target['status'] = 'completed';
        }
      }
    }
    all = uniqueBySerial.values.toList();

    final currentRealShift = CampSessionService.getCurrentSession(null, branchId);
    final targetShift = sessionFilter == 'auto' ? currentRealShift : sessionFilter;

    // Strictly isolate to the active session
    if (targetShift != 'all') {
      all = all.where((entry) {
        String resolved = (entry['session'] ?? entry['shift'] ?? entry['campSession'] ?? entry['slot'] ?? '').toString().toLowerCase().trim();

        // Only infer session from createdAt if explicit session is missing/unknown
        if (resolved.isEmpty || resolved == 'unknown' || resolved == 'all' || resolved == 'auto') {
          final rawTime = entry['createdAt'] ?? entry['time'] ?? entry['timestamp'] ?? entry['date'];
          if (rawTime != null) {
            DateTime? dt;
            if (rawTime is Timestamp) {
              dt = rawTime.toDate().toLocal();
            } else if (rawTime is DateTime) {
              dt = rawTime.toLocal();
            } else {
              dt = DateTime.tryParse(rawTime.toString())?.toLocal();
            }
            if (dt != null) {
              final hasNight = allowedSessions.contains('night');
              if (dt.hour >= 6 && dt.hour < 14) {
                resolved = 'morning';
              } else if (dt.hour >= 14 && (dt.hour < 22 || !hasNight)) {
                resolved = 'evening';
              } else if (hasNight && (dt.hour >= 22 || dt.hour < 6)) {
                resolved = 'night';
              } else {
                resolved = CampSessionService.getCurrentSession(dt, branchId);
              }
            }
          }
        }

        if (sessionFilter == 'auto') {
          return true;
        }

        if (resolved.isNotEmpty) {
          return resolved == targetShift;
        }
        return true;
      }).toList();
    }

    // Search query filter
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      all = all.where((e) {
        final s = (e['serial'] ?? e['id'] ?? '').toString().toLowerCase();
        final n = (e['patientName'] ?? e['name'] ?? '').toString().toLowerCase();
        final c = (e['patientCnic'] ?? e['cnic'] ?? e['guardianCnic'] ?? '').toString().toLowerCase();
        final phone = (e['phone'] ?? '').toString().toLowerCase();
        return s.contains(q) || n.contains(q) || c.contains(q) || phone.contains(q);
      }).toList();
    }

    final pending   = <Map<String, dynamic>>[];
    final onHold    = <Map<String, dynamic>>[];
    final dispensed = <Map<String, dynamic>>[];

    for (final e in all) {
      String ds = (e['dispenseStatus'] ?? '').toString().toLowerCase();
      final st = (e['status'] ?? '').toString().toLowerCase();

      if (ds != 'dispensed' && st != 'dispensed') {
        final s = (e['serial'] ?? e['id'] ?? '').toString().trim();
        final dKey = (e['dateKey'] ?? todayKey).toString().trim();
        if (s.isNotEmpty && Hive.isBoxOpen(LocalStorageService.dispensaryBox)) {
          final dBox = Hive.box(LocalStorageService.dispensaryBox);
          final dispRec = dBox.get('${branchId}_${dKey}_$s') ??
              dBox.get('$branchId-$s') ??
              dBox.get(s);
          if (dispRec is Map) {
            final recStatus = (dispRec['dispenseStatus'] ?? dispRec['status'] ?? '').toString().toLowerCase();
            if (recStatus == 'dispensed' || recStatus == 'completed') {
              ds = 'dispensed';
              e['dispenseStatus'] = 'dispensed';
            }
          }
        }
      }

      if (ds == 'dispensed' || st == 'dispensed') {
        dispensed.add(e);
      } else if (ds == 'on_hold' || ds == 'hold') {
        onHold.add(e);
      } else {
        pending.add(e);
      }
    }

    pending.sort((a, b) => compareTokens(a, b, newestFirst: newestFirst));
    onHold.sort((a, b) => compareTokens(a, b, newestFirst: newestFirst));
    dispensed.sort((a, b) => compareTokens(a, b, newestFirst: newestFirst));

    if (filter == 'pending') {
      return [...pending, ...onHold];
    } else if (filter == 'dispensed') {
      return dispensed;
    }
    return [...pending, ...onHold, ...dispensed];
  }

  /// Never undo a dispense: when a (replayed or stale) prescription/entry event is
  /// merged into an entry, carry over the dispensed state from any existing copy of
  /// that token so it cannot flip back to "waiting to dispense".
  static void keepDispensedState(Map<String, dynamic> updated, Iterable<dynamic> existingCopies) {
    for (final c in existingCopies) {
      if (c is Map && (c['dispenseStatus'] ?? '').toString().toLowerCase() == 'dispensed') {
        for (final k in const ['dispenseStatus', 'dispensedAt', 'dispensedBy', 'dispenserName']) {
          if (c[k] != null) updated[k] = c[k];
        }
        return;
      }
    }
  }

  /// Token-number order (then creation time).
  static int compareTokens(Map<String, dynamic> a, Map<String, dynamic> b, {bool newestFirst = false}) {
    final numA = parseSequenceFromSerial((a['serial'] ?? a['id'] ?? '').toString());
    final numB = parseSequenceFromSerial((b['serial'] ?? b['id'] ?? '').toString());
    if (numA != numB) {
      return newestFirst ? numB.compareTo(numA) : numA.compareTo(numB);
    }
    final dtA = a['createdAt']?.toString() ?? '';
    final dtB = b['createdAt']?.toString() ?? '';
    return newestFirst ? dtB.compareTo(dtA) : dtA.compareTo(dtB);
  }

  /// Patients still to dispense (not dispensed, not on hold), in queue order.
  static List<Map<String, dynamic>> activePending(List<Map<String, dynamic>> queue) =>
      queue.where((p) => !isDispensed(p) && !isOnHold(p)).toList();

  /// Who the dispense form should show: keeps [currentSerial] while it is still
  /// waiting (never switches away mid-dispense), otherwise the next in line;
  /// null when nobody is waiting. [skipSerial] is left out (e.g. the patient just
  /// dispensed, before the queue has caught up).
  static Map<String, dynamic>? pickNext(
    List<Map<String, dynamic>> queue, {
    String? currentSerial,
    String? skipSerial,
  }) {
    final skip = skipSerial?.trim().toUpperCase() ?? '';
    final pending = activePending(queue)
        .where((p) => skip.isEmpty || (p['serial']?.toString().trim().toUpperCase() ?? '') != skip)
        .toList();
    if (pending.isEmpty) return null;
    final cur = currentSerial?.trim() ?? '';
    if (cur.isNotEmpty) {
      for (final p in pending) {
        if ((p['serial']?.toString() ?? '') == cur) return p;
      }
    }
    return pending.first;
  }
}
