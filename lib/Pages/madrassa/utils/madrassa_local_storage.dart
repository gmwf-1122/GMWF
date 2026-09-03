import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../../../services/local_storage_service.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';
import '../../../services/zkteco_network_service.dart';

class MadrassaLocalStorage {
  static const String studentsBox = LocalStorageService.madrassaStudentsBox;
  static const String logsBox     = LocalStorageService.madrassaLogsBox;
  static const String holidaysBox = LocalStorageService.madrassaHolidaysBox;

  static Box _getStudentsBox() => Hive.box(studentsBox);
  static Box _getLogsBox()     => Hive.box(logsBox);
  static Box _getHolidaysBox() => Hive.box(holidaysBox);

  static const DeepCollectionEquality _deepEq = DeepCollectionEquality();

  // ── Sanitization helpers for Hive ───────────────────────────────────────────

  static Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((k, v) => out[k] = _val(v));
    return out;
  }

  static dynamic _val(dynamic v) {
    if (v == null)       return null;
    if (v is String)     return v;
    if (v is int)        return v;
    if (v is double)     return v;
    if (v is bool)       return v;
    if (v is DateTime)   return v.toIso8601String();
    if (v is Timestamp)  return v.toDate().toIso8601String();
    if (v is Map)        return _sanitize(Map<String, dynamic>.from(v));
    if (v is List)       return v.map(_val).toList();
    return null;
  }

  // ── Cache keys ─────────────────────────────────────────────────────────────

  static String _studentKey(String branchId, String studentId) =>
      '${branchId.toLowerCase().trim()}__std__$studentId';

  static String _logKey(String branchId, String dateKey) =>
      '${branchId.toLowerCase().trim()}__log__$dateKey';

  static String _holidayKey(String branchId, String dateKey) =>
      '${branchId.toLowerCase().trim()}__hol__$dateKey';

  // ── Students Cache ─────────────────────────────────────────────────────────

  static Future<void> cacheStudent(String branchId, String studentId, Map<String, dynamic> data) async {
    final key = _studentKey(branchId, studentId);
    final box = _getStudentsBox();
    final rawExisting = box.get(key);
    final merged = <String, dynamic>{
      if (rawExisting is Map) ...Map<String, dynamic>.from(rawExisting),
      ...data,
    };
    await box.put(key, _sanitize(merged));
    await box.flush();
  }

  /// Saves student locally in Hive immediately, writes to disk, routes over LAN WebSocket,
  /// enqueues for offline Firestore sync, and attempts background cloud write.
  static Future<String> saveStudentLocalAndSync({
    required String branchId,
    required String studentId,
    required Map<String, dynamic> data,
    bool isNew = false,
  }) async {
    final effectiveStudentId = studentId.isNotEmpty 
        ? studentId 
        : 'madrassa_std_${DateTime.now().millisecondsSinceEpoch}';
    final effectiveBranchId = branchId.toLowerCase().trim();

    final cleanData = Map<String, dynamic>.from(data);
    cleanData['id'] = effectiveStudentId;
    cleanData['branchId'] = effectiveBranchId;
    cleanData['lastUpdatedAt'] = DateTime.now().toIso8601String();

    // 1. Immediately cache in Hive and flush to disk
    await cacheStudent(effectiveBranchId, effectiveStudentId, cleanData);

    // 2. Assign PIN in ZKTeco Biometrics if entered
    final pin = cleanData['biometricPin']?.toString().trim();
    if (pin != null && pin.isNotEmpty) {
      try {
        await ZkTecoNetworkService.assignPinToEntity(
          entityId: effectiveStudentId,
          entityName: cleanData['name']?.toString() ?? '',
          entityType: 'madrassa_student',
          branchId: effectiveBranchId,
          customPin: pin,
        );
      } catch (e) {
        debugPrint('[MadrassaLocalStorage] PIN assign error: $e');
      }
    }

    // 3. Broadcast to LAN WebSocket
    try {
      final payload = RealtimeEvents.payload(
        type: RealtimeEvents.saveMadrassaStudent,
        data: {
          ...cleanData,
          'studentId': effectiveStudentId,
        },
        branchId: effectiveBranchId,
      );
      RealtimeManager().sendMessage(payload);
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] LAN broadcast error: $e');
    }

    // 4. Enqueue into LocalStorageService.syncBox for Firestore sync
    try {
      await LocalStorageService.enqueueSync({
        'type': 'save_madrassa_student',
        'branchId': effectiveBranchId,
        'studentId': effectiveStudentId,
        'data': cleanData,
        'isNew': isNew,
      });
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] enqueueSync error: $e');
    }

    // 5. Background direct write to Firestore if connection permits
    try {
      final fsData = Map<String, dynamic>.from(cleanData);
      if (fsData['joinDate'] is String) {
        final parsed = DateTime.tryParse(fsData['joinDate'] as String);
        if (parsed != null) fsData['joinDate'] = Timestamp.fromDate(parsed);
      }
      fsData['lastUpdatedAt'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(effectiveBranchId)
          .collection('madrassa_students')
          .doc(effectiveStudentId)
          .set(fsData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] Direct Firestore write offline/delayed: $e');
    }

    return effectiveStudentId;
  }

  /// Offboards a student: updates Hive immediately, unenrolls biometric PIN,
  /// revokes linked app login access, broadcasts via LAN and enqueues to Firestore.
  static Future<void> deleteOrOffboardStudentLocalAndSync({
    required String branchId,
    required String studentId,
    required String status,
    String? reason,
    DateTime? effectiveDate,
  }) async {
    final effectiveBranchId = branchId.toLowerCase().trim();
    final student = getStudentCached(effectiveBranchId, studentId) ?? {};
    final now = DateTime.now();

    student['status'] = status;
    student['batch'] = status;
    student['offboardedAt'] = (effectiveDate ?? now).toIso8601String();
    student['lastUpdatedAt'] = now.toIso8601String();

    final auditList = List<Map<String, dynamic>>.from(
      (student['auditLog'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );
    auditList.add({
      'status': status,
      'type': 'offboarding',
      'date': (effectiveDate ?? now).toIso8601String(),
      'reason': reason ?? 'Student offboarded ($status)',
    });
    student['auditLog'] = auditList;

    // 1. Immediately update Hive cache and flush
    await cacheStudent(effectiveBranchId, studentId, student);

    // 2. Unenroll biometric PIN from device
    try {
      await ZkTecoNetworkService.deleteBiometricCredential(studentId, branchId: effectiveBranchId);
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] deleteBiometricCredential error: $e');
    }

    // 3. Revoke App Access for student/guardian user account
    try {
      final guardianCnic = (student['guardianCnic'] ?? '').toString().trim();
      final studentCnic = (student['studentCnic'] ?? '').toString().trim();
      final phone = (student['contactPhone'] ?? student['phone'] ?? '').toString().trim();

      if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
        final usersBox = Hive.box(LocalStorageService.usersBox);
        for (final k in usersBox.keys) {
          final u = usersBox.get(k);
          if (u is Map) {
            final uCnic = (u['cnic'] ?? '').toString().trim();
            final uPhone = (u['phone'] ?? '').toString().trim();
            final uStudentIds = List<String>.from(u['studentIds'] ?? []);

            final matches = (guardianCnic.isNotEmpty && uCnic == guardianCnic) ||
                (studentCnic.isNotEmpty && uCnic == studentCnic) ||
                (phone.isNotEmpty && uPhone == phone) ||
                uStudentIds.contains(studentId);

            if (matches) {
              final updatedUser = Map<String, dynamic>.from(u);
              uStudentIds.remove(studentId);
              updatedUser['studentIds'] = uStudentIds;
              if (uStudentIds.isEmpty) {
                updatedUser['isActive'] = false;
                updatedUser['accountStatus'] = 'offboarded';
                updatedUser['isReadOnly'] = true;
                updatedUser['status'] = 'offboarded';
              }
              await usersBox.put(k, updatedUser);

              final uid = u['uid']?.toString() ?? k.toString();
              await FirebaseFirestore.instance.collection('users').doc(uid).set(
                {
                  'studentIds': FieldValue.arrayRemove([studentId]),
                  if (uStudentIds.isEmpty) ...{
                    'isActive': false,
                    'accountStatus': 'offboarded',
                    'isReadOnly': true,
                    'status': 'offboarded',
                  }
                },
                SetOptions(merge: true),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] Revoke app access error: $e');
    }

    // 4. Broadcast to LAN WebSocket
    try {
      final payload = RealtimeEvents.payload(
        type: RealtimeEvents.offboardMadrassaStudent,
        data: {
          'branchId': effectiveBranchId,
          'studentId': studentId,
          'status': status,
          'reason': reason,
          'effectiveDate': (effectiveDate ?? now).toIso8601String(),
        },
        branchId: effectiveBranchId,
      );
      RealtimeManager().sendMessage(payload);
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] LAN broadcast error: $e');
    }

    // 5. Enqueue for Firestore sync
    try {
      await LocalStorageService.enqueueSync({
        'type': 'delete_madrassa_student',
        'branchId': effectiveBranchId,
        'studentId': studentId,
        'status': status,
        'reason': reason,
        'effectiveDate': (effectiveDate ?? now).toIso8601String(),
        'data': student,
      });
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] enqueueSync error: $e');
    }

    // 6. Direct Firestore sync
    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(effectiveBranchId)
          .collection('madrassa_students')
          .doc(studentId)
          .set({
            'status': status,
            'batch': status,
            'lastUpdatedAt': FieldValue.serverTimestamp(),
            'auditLog': FieldValue.arrayUnion([
              {
                'status': status,
                'type': 'offboarding',
                'date': Timestamp.fromDate(effectiveDate ?? now),
                'reason': reason ?? 'Student offboarded ($status)',
              }
            ]),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] Direct Firestore offboard error: $e');
    }
  }

  static Map<String, dynamic>? getStudentCached(String branchId, String studentId) {
    final key = _studentKey(branchId, studentId);
    final box = _getStudentsBox();
    final raw = box.get(key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  static List<Map<String, dynamic>> getAllStudentsCached(String branchId) {
    final prefix = '${branchId.toLowerCase().trim()}__std__';
    final box = _getStudentsBox();
    return box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) {
          final raw = box.get(k);
          if (raw == null) return null;
          final m = Map<String, dynamic>.from(raw as Map);
          m['id'] = k.toString().split('__std__').last;
          return m;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  // Watching the whole box means ANY write to ANY student re-emits the full
  // list. distinct() (with a deep equality check) stops the stream from
  // pushing a new event - and therefore stops the UI from rebuilding the
  // whole list - unless the actual student data changed. This is what was
  // causing the daily log list to rebuild (and visually jump) on every
  // unrelated edit.
  static Stream<List<Map<String, dynamic>>> streamStudentsCached(String branchId) {
    Stream<List<Map<String, dynamic>>> source() async* {
      yield getAllStudentsCached(branchId);
      await for (final _ in _getStudentsBox().watch()) {
        yield getAllStudentsCached(branchId);
      }
    }
    return source().distinct((a, b) => _deepEq.equals(a, b));
  }

  static Future<void> downloadStudents(String branchId, {bool force = false}) async {
    try {
      final normBranch = branchId.toLowerCase().trim();
      final syncKey = 'madrassa_students_$normBranch';
      final lastSyncedTs = force ? null : LocalStorageService.getLastSyncedServerTimestamp(syncKey);

      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('branches')
          .doc(normBranch)
          .collection('madrassa_students');

      if (lastSyncedTs != null) {
        query = query.where('updatedAt', isGreaterThan: lastSyncedTs).orderBy('updatedAt', descending: false);
      }

      final snap = await query.get();
      final box = _getStudentsBox();
      String? maxServerTs = lastSyncedTs;
      final Map<String, dynamic> studentUpdates = {};

      for (final doc in snap.docs) {
        final data = doc.data();
        final key = _studentKey(normBranch, doc.id);
        studentUpdates[key] = _sanitize(data);

        final docTs = data['updatedAt']?.toString();
        if (docTs != null) {
          if (maxServerTs == null || docTs.compareTo(maxServerTs) > 0) {
            maxServerTs = docTs;
          }
        }
      }

      if (studentUpdates.isNotEmpty) {
        await box.putAll(studentUpdates);
      }
      if (maxServerTs != null) {
        await LocalStorageService.setLastSyncedServerTimestamp(syncKey, maxServerTs);
      }
      await box.flush();
      debugPrint('[MadrassaLocalStorage] Downloaded ${snap.docs.length} madrassa students (Delta)');
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] Error downloading students: $e');
    }
  }

  static List<Map<String, dynamic>> getStudentsForGuardian(String branchId, List<String> studentIds) {
    final List<Map<String, dynamic>> result = [];
    for (final id in studentIds) {
      final data = getStudentCached(branchId, id);
      if (data != null) {
        final m = Map<String, dynamic>.from(data);
        m['id'] = id;
        result.add(m);
      }
    }
    return result;
  }

  static Future<void> downloadStudentsForGuardian(String branchId, List<String> studentIds) async {
    if (studentIds.isEmpty) return;
    try {
      final Map<String, dynamic> updates = {};
      for (final id in studentIds) {
        final doc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('madrassa_students')
            .doc(id)
            .get();
        if (doc.exists && doc.data() != null) {
          final key = _studentKey(branchId, doc.id);
          updates[key] = _sanitize(doc.data()!);
        }
      }
      if (updates.isNotEmpty) {
        final box = _getStudentsBox();
        await box.putAll(updates);
        await box.flush();
      }
      debugPrint('[MadrassaLocalStorage] Downloaded ${updates.length} scoped guardian students.');
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] Error downloading scoped guardian students: $e');
    }
  }

  // ── Daily Logs Cache ───────────────────────────────────────────────────────

  static Map<String, dynamic>? getLogCached(String branchId, String dateKey) {
    final key = _logKey(branchId, dateKey);
    final box = _getLogsBox();
    final raw = box.get(key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  static Map<String, dynamic>? getDailyLogCached(String branchId, String dateKey) =>
      getLogCached(branchId, dateKey);

  static Future<void> cacheDailyLog(String branchId, String dateKey, Map<String, dynamic> data) async {
    final key = _logKey(branchId, dateKey);
    final box = _getLogsBox();
    await box.put(key, _sanitize(data));
    await box.flush();
  }

  // This one already watches a specific key, but still add distinct() so a
  // put() that writes back identical data (e.g. a no-op merge) doesn't
  // trigger a rebuild of every student card.
  static Stream<Map<String, dynamic>> streamLogCached(String branchId, String dateKey) {
    Stream<Map<String, dynamic>> source() async* {
      yield getLogCached(branchId, dateKey) ?? {};
      await for (final event in _getLogsBox().watch(key: _logKey(branchId, dateKey))) {
        yield (event.value != null) ? Map<String, dynamic>.from(event.value as Map) : {};
      }
    }
    return source().distinct((a, b) => _deepEq.equals(a, b));
  }

  static Future<void> saveLogRecordLocal({
    required String branchId,
    required String dateKey,
    required Map<String, dynamic> logData,
    required String editorName,
    required String editorRole,
  }) async {
    final key = _logKey(branchId, dateKey);
    final box = _getLogsBox();

    // Get current cache log or start empty
    final existing = getLogCached(branchId, dateKey) ?? {};
    final updated = Map<String, dynamic>.from(existing);

    // Merge changes
    logData.forEach((sId, data) {
      if (data is Map) {
        final existingStudentLog = updated[sId] is Map ? Map<String, dynamic>.from(updated[sId] as Map) : <String, dynamic>{};
        updated[sId] = {
          ...existingStudentLog,
          ...Map<String, dynamic>.from(data),
          'lastEditedBy': editorName,
          'lastEditedAt': DateTime.now().toIso8601String(),
        };

        // Also update local cached student's currentLines if updated
        if (data.containsKey('currentLines')) {
          final studentCache = getStudentCached(branchId, sId);
          if (studentCache != null) {
            studentCache['currentLines'] = data['currentLines'];
            cacheStudent(branchId, sId, studentCache);
          }
        }
      }
    });

    final sanitized = _sanitize(updated);
    await box.put(key, sanitized);
    await box.flush();

    // Enqueue sync action for the logs update
    await LocalStorageService.enqueueSync({
      'type': 'save_madrassa_log',
      'branchId': branchId,
      'dateKey': dateKey,
      'data': sanitized,
    });

    // Enqueue sync actions for changed students' currentLines
    logData.forEach((sId, data) {
      if (data is Map && data.containsKey('currentLines')) {
        LocalStorageService.enqueueSync({
          'type': 'update_madrassa_student',
          'branchId': branchId,
          'studentId': sId,
          'currentLines': data['currentLines'],
        });
      }
    });

    // Enqueue audit log
    await LocalStorageService.enqueueSync({
      'type': 'save_audit_log',
      'branchId': branchId,
      'data': {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'collection': 'madrassa_daily_logs',
        'documentId': dateKey,
        'action': 'update',
        'userId': editorName,
        'username': editorName,
        'timestamp': DateTime.now().toIso8601String(),
        'branchId': branchId,
        'branchName': branchId,
        'newData': sanitized,
        'reason': 'Local daily log edit',
      }
    });
  }

  static Future<void> downloadLogsForMonth(String branchId, int year, int month) async {
    try {
      final startStr = DateFormat('yyyy-MM-01').format(DateTime(year, month, 1));
      final endStr = DateFormat('yyyy-MM-dd').format(DateTime(year, month + 1, 0));

      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_daily_logs')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startStr)
          .where(FieldPath.documentId, isLessThanOrEqualTo: endStr)
          .get();

      final box = _getLogsBox();
      final Map<String, dynamic> logUpdates = {};
      for (final doc in snap.docs) {
        final key = _logKey(branchId, doc.id);
        
        // Merge cloud fields preserving local updates if local is newer (LWW conflict resolution)
        final existing = box.get(key) ?? logUpdates[key];
        if (existing == null) {
          logUpdates[key] = _sanitize(doc.data());
        } else {
          final exMap = Map<String, dynamic>.from(existing as Map);
          
          // Simple conflict resolution: if Firestore document has updates, we can merge them
          final Map<String, dynamic> merged = {...exMap, ...doc.data()};
          logUpdates[key] = _sanitize(merged);
        }
      }
      if (logUpdates.isNotEmpty) {
        await box.putAll(logUpdates);
      }
      await box.flush();
      debugPrint('[MadrassaLocalStorage] Downloaded ${snap.docs.length} daily log documents for $year-$month.');
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] Error downloading daily logs: $e');
    }
  }

  static List<Map<String, dynamic>> getLogsForMonthCached(String branchId, int year, int month) {
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';
    final prefix = '${branchId.toLowerCase().trim()}__log__$monthStr-';
    final box = _getLogsBox();
    return box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) {
          final raw = box.get(k);
          if (raw == null) return null;
          final m = Map<String, dynamic>.from(raw as Map);
          m['id'] = k.toString().split('__log__').last;
          return m;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  static List<Map<String, dynamic>> getAllLogsCached(String branchId) {
    final prefix = '${branchId.toLowerCase().trim()}__log__';
    final box = _getLogsBox();
    final list = box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) {
          final raw = box.get(k);
          if (raw == null) return null;
          final m = Map<String, dynamic>.from(raw as Map);
          m['id'] = k.toString().split('__log__').last;
          m['dateKey'] = k.toString().split('__log__').last;
          return m;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
    list.sort((a, b) => a['dateKey'].toString().compareTo(b['dateKey'].toString()));
    return list;
  }

  static Stream<List<Map<String, dynamic>>> streamLogsForMonthCached(String branchId, int year, int month) {
    Stream<List<Map<String, dynamic>>> source() async* {
      yield getLogsForMonthCached(branchId, year, month);
      await for (final _ in _getLogsBox().watch()) {
        yield getLogsForMonthCached(branchId, year, month);
      }
    }
    return source().distinct((a, b) => _deepEq.equals(a, b));
  }


  // ── Holidays Cache ─────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> getHolidaysCached(String branchId) {
    final prefix = '${branchId.toLowerCase().trim()}__hol__';
    final box = _getHolidaysBox();
    return box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) {
          final raw = box.get(k);
          if (raw == null) return null;
          final m = Map<String, dynamic>.from(raw as Map);
          m['id'] = k.toString().split('__hol__').last;
          return m;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> streamHolidaysCached(String branchId) {
    Stream<List<Map<String, dynamic>>> source() async* {
      yield getHolidaysCached(branchId);
      await for (final _ in _getHolidaysBox().watch()) {
        yield getHolidaysCached(branchId);
      }
    }
    return source().distinct((a, b) => _deepEq.equals(a, b));
  }

  static Future<void> downloadHolidays(String branchId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_holidays')
          .get();

      final box = _getHolidaysBox();
      final prefix = '${branchId.toLowerCase().trim()}__hol__';
      
      // Clear existing cached holidays for this branch first
      final keysToDelete = box.keys.where((k) => k.toString().startsWith(prefix)).toList();
      await box.deleteAll(keysToDelete);

      final Map<String, dynamic> holidayUpdates = {};
      for (final doc in snap.docs) {
        final key = '${prefix}${doc.id}';
        holidayUpdates[key] = _sanitize(doc.data());
      }
      if (holidayUpdates.isNotEmpty) {
        await box.putAll(holidayUpdates);
      }
      await box.flush();
      debugPrint('[MadrassaLocalStorage] Downloaded and cached ${snap.docs.length} holidays.');
    } catch (e) {
      debugPrint('[MadrassaLocalStorage] Error downloading holidays: $e');
    }
  }
}