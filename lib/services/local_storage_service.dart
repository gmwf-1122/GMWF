// lib/services/local_storage_service.dart
//
// ONLY CHANGE vs original:
//   init() now also opens 'local_donations' and 'local_credit_ledger' boxes
//   so DonationsLocalStorage.init() doesn't need a separate call in main().
//   Everything else is character-for-character identical to the original.

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class LocalStorageService {
  static const String usersBox         = 'local_users';
  static const String patientsBox      = 'local_patients';
  static const String entriesBox       = 'local_entries';
  static const String syncBox          = 'sync_queue';
  static const String prescriptionsBox = 'local_prescriptions';
  static const String stockBox         = 'local_stock_items';
  static const String branchesBox      = 'local_branches';
  static const String dispensaryBox    = 'local_dispensary';

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    debugPrint('[LocalStorageService.init] Opening all required Hive boxes...');
    await Future.wait([
      Hive.openBox(usersBox),
      Hive.openBox(patientsBox),
      Hive.openBox(entriesBox),
      Hive.openBox(syncBox),
      Hive.openBox(prescriptionsBox),
      Hive.openBox(stockBox),
      Hive.openBox(branchesBox),
      Hive.openBox(dispensaryBox),
      Hive.openBox('app_settings'),
      Hive.openBox('app_flags'),
      // ── NEW: donation boxes (owned by DonationsLocalStorage) ──────────────
      Hive.openBox('local_donations'),
      Hive.openBox('local_credit_ledger'),
      // ─────────────────────────────────────────────────────────────────────
    ]);
    debugPrint('[LocalStorageService.init] All Hive boxes opened successfully.');
  }

  static Future<void> clearAllData() async {
    await Future.wait([
      Hive.box(usersBox).clear(),
      Hive.box(patientsBox).clear(),
      Hive.box(entriesBox).clear(),
      Hive.box(syncBox).clear(),
      Hive.box(prescriptionsBox).clear(),
      Hive.box(stockBox).clear(),
      Hive.box(branchesBox).clear(),
      Hive.box(dispensaryBox).clear(),
      Hive.box('app_settings').clear(),
      Hive.box('app_flags').clear(),
      // ── NEW ───────────────────────────────────────────────────────────────
      Hive.box('local_donations').clear(),
      Hive.box('local_credit_ledger').clear(),
      // ─────────────────────────────────────────────────────────────────────
    ]);
    debugPrint('[LocalStorageService] All local data cleared.');
  }

  // ── Everything below is IDENTICAL to the original ─────────────────────────

  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try { return DateTime.parse(value); } catch (_) {}
    }
    return DateTime.now();
  }

  static int calculateAgeFromDob(dynamic dobValue) {
    if (dobValue == null) return 0;
    final DateTime birthDate = _toDateTime(dobValue);
    final DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age >= 0 ? age : 0;
  }

  static Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    data.forEach((key, value) {
      if (value == null) {
        result[key] = null;
      } else if (value is Timestamp || value is DateTime) {
        final dt = _toDateTime(value);
        result[key] = dt.toIso8601String();
        if (key == 'dob') result['age'] = calculateAgeFromDob(dt);
      } else if (value.runtimeType.toString().contains('FieldValue')) {
        debugPrint('[sanitize] Dropped FieldValue for key: $key');
      } else if (value is Map) {
        result[key] = sanitize(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((e) => sanitizeValue(e)).toList();
      } else {
        result[key] = value;
      }
    });
    if (data['dob'] != null) result['age'] = calculateAgeFromDob(data['dob']);
    return result;
  }

  static dynamic sanitizeValue(dynamic item) {
    if (item is Timestamp || item is DateTime) return _toDateTime(item).toIso8601String();
    if (item is Map) return sanitize(Map<String, dynamic>.from(item));
    return item;
  }

  static String _normalizeName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String getPatientKey(Map<String, dynamic> patient) {
    final isAdult      = patient['isAdult'] as bool? ?? true;
    final cnic         = (patient['cnic'] as String?)?.replaceAll('-', '').trim();
    final guardianCnic = (patient['guardianCnic'] as String?)?.replaceAll('-', '').trim();
    final name         = (patient['name'] as String?)?.trim() ?? '';

    if (isAdult && cnic != null && cnic.isNotEmpty) return cnic;
    if (!isAdult && guardianCnic != null && guardianCnic.isNotEmpty && name.isNotEmpty) {
      return '${guardianCnic}_child_${_normalizeName(name)}';
    }
    final fallback = patient['patientId']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return 'fallback_$fallback';
  }

  static String getTodayDateKey() => DateFormat('ddMMyy').format(DateTime.now());

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static Future<void> enqueueSync(Map<String, dynamic> action) async {
    final box = Hive.box(syncBox);
    final key = 'sync_${DateTime.now().millisecondsSinceEpoch}_${action['type'] ?? 'unknown'}';
    final enriched = {
      ...action,
      'attempts':    0,
      'createdAt':   _nowIso(),
      'lastAttempt': null,
      'lastError':   null,
      'status':      'pending',
    };
    await box.put(key, sanitize(enriched));
    debugPrint('[SyncQueue] Enqueued: ${action['type']} | key: $key | total: ${box.length}');
  }

  static Map<String, Map<String, dynamic>> getAllSync() {
    final box = Hive.box(syncBox);
    return Map.fromEntries(box.keys.map((k) {
      final v = box.get(k);
      if (v == null || v is! Map) return MapEntry(k.toString(), <String, dynamic>{});
      return MapEntry(k.toString(), Map<String, dynamic>.from(v));
    }));
  }

  static Future<void> removeSyncKey(String key) async {
    await Hive.box(syncBox).delete(key);
  }

  static Future<void> seedLocalAdmins() async {
    final box = Hive.box(usersBox);

    Future<void> seedOne(String email, String password, String role, String branchId) async {
      final key = 'user:$email';
      if (!box.containsKey(key)) {
        await box.put(key, {
          'email':        email,
          'username':     role == 'server' ? 'server' : (role == 'chairman' ? 'chairman' : 'admin'),
          'passwordHash': hashPassword(password),
          'role':         role,
          'uid':          'local-${email.replaceAll('@', '_').replaceAll('.', '_')}',
          'branchId':     branchId,
          'branchName':   role == 'server' ? 'Server' : (role == 'chairman' ? 'Chairman' : 'HQ'),
          'createdAt':    DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Seeded user: $email with role: $role');
      }
    }

    await seedOne('admin@gmd.com',  'Admin@123',  'admin',  'all');
    await seedOne('server@gmd.com', 'Server@123', 'server', 'sialkot');
  }

  static Future<void> forceDeduplicatePatients() async {
    final box       = Hive.box(patientsBox);
    final flagsBox  = Hive.box('app_flags');
    if (flagsBox.get('patients_deduplicated_v2') == true) return;

    final Map<String, Map<String, dynamic>> uniquePatients = {};
    final Map<String, List<String>> keyToOldKeys = {};

    for (final oldKey in box.keys.toList()) {
      final val = box.get(oldKey);
      if (val is! Map) continue;
      final patient = Map<String, dynamic>.from(val);
      try {
        final newKey = getPatientKey(patient);
        if (!uniquePatients.containsKey(newKey)) {
          uniquePatients[newKey] = patient;
        } else {
          uniquePatients[newKey]!.addAll(patient);
        }
        keyToOldKeys.putIfAbsent(newKey, () => []).add(oldKey.toString());
      } catch (_) {
        continue;
      }
    }

    final eBox = Hive.box(entriesBox);
    for (final entry in uniquePatients.entries) {
      final newKey = entry.key;
      var patient  = sanitize(entry.value);
      patient['patientId'] = newKey;
      await box.put(newKey, patient);

      final oldKeys = keyToOldKeys[newKey]!;
      for (final tokenKey in eBox.keys.toList()) {
        final tokenVal = eBox.get(tokenKey);
        if (tokenVal is Map && oldKeys.contains(tokenVal['patientId'])) {
          final upd = Map<String, dynamic>.from(tokenVal);
          upd['patientId'] = newKey;
          await eBox.put(tokenKey, upd);
        }
      }

      for (final oldKey in oldKeys) {
        if (oldKey != newKey) await box.delete(oldKey);
      }
    }

    await flagsBox.put('patients_deduplicated_v2', true);
    debugPrint('[LocalStorage] Patient deduplication completed');
  }

  static Future<void> saveLocalUser(Map<String, dynamic> user) async {
    if (user['email'] == null) return;
    final sanitized = sanitize(user);
    await Hive.box(usersBox).put('user:${sanitized['email']}', sanitized);
  }

  static Map<String, dynamic>? getLocalUserByEmail(String email) {
    final val = Hive.box(usersBox).get('user:$email');
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static Map<String, dynamic>? getLocalUserByUid(String uid) {
    final box = Hive.box(usersBox);
    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map && val['uid'] == uid) return Map<String, dynamic>.from(val);
    }
    return null;
  }

  static Future<void> deleteLocalUser(String email) async {
    await Hive.box(usersBox).delete('user:$email');
  }

  static Future<void> saveLocalPatient(Map<String, dynamic> patient) async {
    var sanitized = sanitize(patient);
    final key     = getPatientKey(sanitized);
    sanitized['patientId'] = key;
    await Hive.box(patientsBox).put(key, sanitized);
    debugPrint('[LocalStorage] Patient saved: $key');
  }

  static Future<void> saveAllLocalPatients(List<Map<String, dynamic>> patients) async {
    final box     = Hive.box(patientsBox);
    final updates = <String, Map<String, dynamic>>{};
    for (final patient in patients) {
      try {
        var s = sanitize(patient);
        final key = getPatientKey(s);
        s['patientId'] = key;
        updates[key] = s;
      } catch (e) {
        debugPrint('[LocalStorage] Skipped invalid patient: $e');
      }
    }
    await box.putAll(updates);
    debugPrint('[LocalStorage] Saved ${updates.length} patients');
  }

  static Map<String, dynamic>? getLocalPatientByCnic(String cnic) {
    final normalized = cnic.replaceAll('-', '').trim();
    final box = Hive.box(patientsBox);

    final direct = box.get(normalized);
    if (direct != null) return Map<String, dynamic>.from(direct as Map);

    for (final key in box.keys) {
      if (key is String && key.startsWith('${normalized}_child_')) {
        final val = box.get(key);
        if (val is Map) return Map<String, dynamic>.from(val);
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> getAllLocalPatients({String? branchId}) {
    var patients = Hive.box(patientsBox)
        .values
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    if (branchId != null) {
      patients = patients.where((p) => p['branchId'] == branchId).toList();
    }
    return patients;
  }

  static List<Map<String, dynamic>> searchPatientsByCnicOrGuardian(
      String input, {String? branchId}) {
    final normalized = input.replaceAll('-', '').trim().toLowerCase();
    return getAllLocalPatients(branchId: branchId).where((p) {
      final cnic     = (p['cnic'] as String?)?.replaceAll('-', '').trim().toLowerCase() ?? '';
      final guardian = (p['guardianCnic'] as String?)?.replaceAll('-', '').trim().toLowerCase() ?? '';
      final phone    = (p['phone'] as String?)?.replaceAll(RegExp(r'\D'), '') ?? '';
      return cnic.contains(normalized) ||
             guardian.contains(normalized) ||
             phone.contains(normalized.replaceAll(RegExp(r'\D'), ''));
    }).toList();
  }

  static Future<void> deleteLocalPatient(String patientId) async {
    await Hive.box(patientsBox).delete(patientId);
  }

  static Future<void> saveEntryLocal(
      String branchId, String serial, Map<String, dynamic> entryData) async {
    final key       = '$branchId-$serial';
    var sanitized   = sanitize(entryData);
    final todayKey  = getTodayDateKey();

    sanitized['dateKey']   = sanitized['dateKey'] ?? todayKey;
    sanitized['branchId']  = branchId;
    sanitized['serial']    = serial;

    if (sanitized['timestamp'] != null) {
      sanitized['timestamp'] = _toDateTime(sanitized['timestamp']).toIso8601String();
    }
    if (sanitized['createdAt'] != null) {
      sanitized['createdAt'] = _toDateTime(sanitized['createdAt']).toIso8601String();
    }

    await Hive.box(entriesBox).put(key, sanitized);
    debugPrint('[LocalStorage] Entry saved: $key | queueType: ${sanitized['queueType']}');
  }

  static List<Map<String, dynamic>> getLocalEntries(String branchId) {
    final box = Hive.box(entriesBox);
    return box.keys
        .where((k) => k.toString().startsWith('$branchId-'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();
  }

  static Map<String, dynamic>? getLocalEntry(String branchId, String serial) {
    final val = Hive.box(entriesBox).get('$branchId-$serial');
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static Future<void> updateLocalEntryField(
      String branchId, String serial, Map<String, dynamic> fields) async {
    final key = '$branchId-$serial';
    final box = Hive.box(entriesBox);
    final raw = box.get(key);
    if (raw == null) {
      debugPrint('[LocalStorage] updateLocalEntryField: entry not found → $key');
      return;
    }
    final updated = Map<String, dynamic>.from(raw as Map)..addAll(sanitize(fields));
    await box.put(key, updated);
    debugPrint('[LocalStorage] Entry field-updated: $key | fields: ${fields.keys.join(', ')}');
  }

  static Future<void> deleteLocalEntry(String branchId, String serial) async {
    await Hive.box(entriesBox).delete('$branchId-$serial');
  }

  static Future<void> saveLocalPrescription(Map<String, dynamic> prescription) async {
    final serialRaw = prescription['serial']?.toString() ??
        prescription['id']?.toString();
    final serial = serialRaw?.trim();

    if (serial == null || serial.isEmpty) {
      debugPrint('[LocalStorage] WARNING: Cannot save prescription — missing serial/id');
      return;
    }

    const cnicFields = [
      'patientCnic', 'cnic', 'patientCNIC', 'guardianCnic',
      'patient_cnic', 'guardian_cnic', 'cnic_number',
    ];
    String? cnicRaw;
    for (final field in cnicFields) {
      final v = prescription[field]?.toString();
      if (v != null && v.trim().isNotEmpty && v != '00000-0000000-0') {
        cnicRaw = v;
        break;
      }
    }
    if (cnicRaw == null || cnicRaw.trim().isEmpty || cnicRaw == '00000-0000000-0') {
      cnicRaw = 'unknown_cnic_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('[LocalStorage] WARNING: No valid CNIC in prescription — using: $cnicRaw');
    }

    final cleanCnic = cnicRaw.trim().replaceAll('-', '').replaceAll(' ', '');
    final key = '${cleanCnic}_$serial';

    var sanitized = sanitize(prescription);
    sanitized['patientCnic'] = cleanCnic;
    sanitized['cnic']        = cleanCnic;
    sanitized['serial']      = serial;

    await Hive.box(prescriptionsBox).put(key, sanitized);
    debugPrint('[LocalStorage] Prescription saved → key: $key');
  }

  static Map<String, dynamic>? getLocalPrescription(String serial) {
    final box         = Hive.box(prescriptionsBox);
    final cleanSerial = serial.trim();

    debugPrint('[LocalStorage] getLocalPrescription: looking for "$cleanSerial" '
        '(box size: ${box.length})');

    final direct = box.get(cleanSerial);
    if (direct != null && direct is Map) {
      return Map<String, dynamic>.from(direct);
    }

    for (final key in box.keys) {
      if (key is String && key.endsWith('_$cleanSerial')) {
        final data = box.get(key);
        if (data != null && data is Map) return Map<String, dynamic>.from(data);
      }
    }

    for (final key in box.keys) {
      if (key is String && key.contains(cleanSerial)) {
        final data = box.get(key);
        if (data != null && data is Map) return Map<String, dynamic>.from(data);
      }
    }

    for (final key in box.keys) {
      final data = box.get(key);
      if (data != null && data is Map) {
        final saved = data['serial']?.toString()?.trim();
        if (saved == cleanSerial) return Map<String, dynamic>.from(data);
      }
    }

    debugPrint('[LocalStorage] No prescription found for serial "$cleanSerial"');
    if (box.isNotEmpty) {
      debugPrint('  Existing keys: ${box.keys.take(5).toList()}'
          '${box.length > 5 ? " (+${box.length - 5} more)" : ""}');
    }
    return null;
  }

  static Map<String, dynamic>? getLocalPrescriptionByCnic(String cnic) {
    final box = Hive.box(prescriptionsBox);
    if (!box.isOpen) { debugPrint('[LocalStorage] prescriptionsBox not open!'); return null; }

    var cleanCnic = cnic.trim().replaceAll('-', '').replaceAll(' ', '');
    cleanCnic = cleanCnic.replaceAll(RegExp(r'^0+'), '');

    for (final value in box.values) {
      final presc = Map<String, dynamic>.from(value as Map);
      final raw   = presc['patientCnic']?.toString() ??
                    presc['cnic']?.toString() ??
                    presc['guardianCnic']?.toString() ?? '';
      var pc = raw.trim().replaceAll('-', '').replaceAll(' ', '');
      pc = pc.replaceAll(RegExp(r'^0+'), '');
      if (pc == cleanCnic || pc.contains(cleanCnic) || cleanCnic.contains(pc)) {
        return presc;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> getAllLocalPrescriptions() {
    return Hive.box(prescriptionsBox)
        .values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  static List<Map<String, dynamic>> getBranchPrescriptions(String branchId) {
    return getAllLocalPrescriptions()
        .where((p) => p['branchId'] == branchId)
        .toList();
  }

  static Future<void> deleteLocalPrescription(String serial) async {
    final box = Hive.box(prescriptionsBox);
    for (final key in box.keys.toList()) {
      if (key is String && key.contains(serial)) {
        await box.delete(key);
        debugPrint('[LocalStorage] Deleted prescription key: $key');
      }
    }
  }

  static Future<void> saveAllLocalStockItems(List<Map<String, dynamic>> items) async {
    final box = Hive.box(stockBox);
    await box.clear();
    await box.putAll({
      for (final item in items) 'stock:${item['id']}': item,
    });
    debugPrint('[LocalStorage] Saved ${items.length} stock items');
  }

  static Future<void> saveLocalStockItem(Map<String, dynamic> stockItem) async {
    final id = stockItem['id']?.toString();
    if (id == null) return;
    await Hive.box(stockBox).put('stock:$id', sanitize(stockItem));
  }

  static Future<void> deleteLocalStockItem(String id) async {
    await Hive.box(stockBox).delete('stock:$id');
  }

  static List<Map<String, dynamic>> getAllLocalStockItems({String? branchId}) {
    var items = Hive.box(stockBox)
        .values
        .whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    if (branchId != null) {
      items = items.where((i) => i['branchId'] == branchId).toList();
    }
    return items;
  }

  static Future<void> saveLocalDispensaryRecord(Map<String, dynamic> record) async {
    final branchId = record['branchId']?.toString() ?? '';
    final serial   = record['serial']?.toString() ?? '';
    final dateKey  = record['dateKey']?.toString() ?? getTodayDateKey();

    if (branchId.isEmpty || serial.isEmpty) {
      debugPrint('[LocalStorage] saveLocalDispensaryRecord: missing branchId or serial');
      return;
    }

    final key = '${branchId}_${dateKey}_$serial';
    await Hive.box(dispensaryBox).put(key, sanitize(record));
    debugPrint('[LocalStorage] Dispensary record saved: $key');
  }

  static Map<String, dynamic>? getLocalDispensaryRecord(
      String branchId, String serial, {String? dateKey}) {
    final dk  = dateKey ?? getTodayDateKey();
    final key = '${branchId}_${dk}_$serial';
    final val = Hive.box(dispensaryBox).get(key);
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static List<Map<String, dynamic>> getLocalDispensaryRecords(
      String branchId, {String? dateKey}) {
    final dk     = dateKey ?? getTodayDateKey();
    final prefix = '${branchId}_${dk}_';
    return Hive.box(dispensaryBox)
        .keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => Map<String, dynamic>.from(Hive.box(dispensaryBox).get(k) as Map))
        .toList();
  }

  static Future<void> saveLocalBranch(Map<String, dynamic> branch) async {
    final id = branch['id']?.toString();
    if (id == null) return;
    await Hive.box(branchesBox).put('branch:$id', sanitize(branch));
  }

  static Future<void> deleteLocalBranch(String id) async {
    await Hive.box(branchesBox).delete('branch:$id');
  }

  static Future<void> downloadAllPatients(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches').doc(branchId)
          .collection('patients').get();

      final patients = snapshot.docs.map((doc) {
        final d = doc.data();
        d['patientId'] = doc.id;
        d['branchId']  = branchId;
        return d;
      }).toList();

      await saveAllLocalPatients(patients);
      debugPrint('[LocalStorage] Downloaded ${patients.length} patients');
    } catch (e) {
      debugPrint('[LocalStorage] downloadAllPatients error: $e');
    }
  }

  static Future<void> downloadTodayTokens(String branchId) async {
    final today = getTodayDateKey();
    debugPrint('[LocalStorage] downloadTodayTokens: date=$today branch=$branchId');

    try {
      final serialsRef = FirebaseFirestore.instance
          .collection('branches').doc(branchId)
          .collection('serials').doc(today);

      final dateDoc = await serialsRef.get();
      if (!dateDoc.exists) {
        debugPrint('[LocalStorage] No serials doc for today ($today)');
        return;
      }

      int total = 0;
      for (final type in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await serialsRef.collection(type).get();
        for (final doc in snap.docs) {
          final d = doc.data();
          d['serial']    = doc.id;
          d['dateKey']   = today;
          d['branchId']  = branchId;
          d['queueType'] = type;
          await saveEntryLocal(branchId, doc.id, d);
          total++;
        }
        debugPrint('[LocalStorage] Downloaded ${snap.docs.length} $type tokens');
      }
      debugPrint('[LocalStorage] Total today tokens downloaded: $total');
    } catch (e, stack) {
      debugPrint('[LocalStorage] downloadTodayTokens error: $e\n$stack');
    }
  }

  static Future<void> downloadInventory(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches').doc(branchId)
          .collection('inventory').get();

      final items = snapshot.docs.map((doc) {
        final d = doc.data();
        d['id']       = doc.id;
        d['branchId'] = branchId;
        return d;
      }).toList();

      await saveAllLocalStockItems(items);
      debugPrint('[LocalStorage] Downloaded ${items.length} inventory items');
    } catch (e) {
      debugPrint('[LocalStorage] downloadInventory error: $e');
    }
  }

  static Future<void> downloadPatientHistory(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches').doc(branchId)
          .collection('prescriptions').get();

      debugPrint('[LocalStorage] downloadPatientHistory: '
          '${snapshot.docs.length} CNIC docs found');

      final prescMap = <String, Map<String, dynamic>>{};

      for (final patientDoc in snapshot.docs) {
        final patientCnic = patientDoc.id;
        final subSnap = await patientDoc.reference.collection('prescriptions').get();

        for (final prescDoc in subSnap.docs) {
          final d = prescDoc.data();
          d['id']          = prescDoc.id;
          d['serial']      = prescDoc.id;
          d['patientCnic'] = patientCnic;
          d['cnic']        = patientCnic;
          d['branchId']    = branchId;

          final key = '${patientCnic}_${prescDoc.id}';
          prescMap[key] = sanitize(d);
        }
      }

      await Hive.box(prescriptionsBox).clear();
      await Hive.box(prescriptionsBox).putAll(prescMap);

      debugPrint('[LocalStorage] downloadPatientHistory: saved ${prescMap.length} prescriptions');
    } catch (e, stack) {
      debugPrint('[LocalStorage] downloadPatientHistory error: $e\n$stack');
      debugPrint(stack.toString());
    }
  }

  static Future<void> refreshPrescriptions(String branchId) async {
    await downloadPatientHistory(branchId);
    debugPrint('[LocalStorage] Prescriptions refreshed from Firestore');
  }

  static Future<void> fullDownloadOnce(String branchId) async {
    await downloadAllPatients(branchId);
    await downloadInventory(branchId);
    await downloadPatientHistory(branchId);
    await downloadTodayTokens(branchId);
  }
}