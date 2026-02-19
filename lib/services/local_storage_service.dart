// lib/services/local_storage_service.dart
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class LocalStorageService {
  static const String usersBox = 'local_users';
  static const String patientsBox = 'local_patients';
  static const String entriesBox = 'local_entries';
  static const String syncBox = 'sync_queue';
  static const String prescriptionsBox = 'local_prescriptions';
  static const String stockBox = 'local_stock_items';
  static const String branchesBox = 'local_branches';
  static const String dispensaryBox = 'local_dispensary';

  static Future<void> init() async {
    print("[LocalStorageService.init] Opening all required Hive boxes...");

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
    ]);

    print("[LocalStorageService.init] All Hive boxes opened successfully.");
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
    ]);
    print("[LocalStorageService] All local data cleared.");
  }

  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
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
        if (key == 'dob') {
          result['age'] = calculateAgeFromDob(dt);
        }
      } else if (value is Map) {
        result[key] = sanitize(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((e) => sanitizeValue(e)).toList();
      } else {
        result[key] = value;
      }
    });

    if (data['dob'] != null) {
      result['age'] = calculateAgeFromDob(data['dob']);
    }

    return result;
  }

  static dynamic sanitizeValue(dynamic item) {
    if (item is Timestamp || item is DateTime) return _toDateTime(item).toIso8601String();
    if (item is Map) return sanitize(Map<String, dynamic>.from(item));
    return item;
  }

  static String _normalizeName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String getPatientKey(Map<String, dynamic> patient) {
    final isAdult = patient['isAdult'] as bool? ?? true;
    final cnic = (patient['cnic'] as String?)?.replaceAll('-', '').trim();
    final guardianCnic = (patient['guardianCnic'] as String?)?.replaceAll('-', '').trim();
    final name = (patient['name'] as String?)?.trim() ?? '';

    if (isAdult && cnic != null && cnic.isNotEmpty) {
      return cnic;
    }
    if (!isAdult && guardianCnic != null && guardianCnic.isNotEmpty && name.isNotEmpty) {
      return '${guardianCnic}_child_${_normalizeName(name)}';
    }

    final fallbackId = patient['patientId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    return 'fallback_$fallbackId';
  }

  static String getTodayDateKey() {
    return DateFormat('ddMMyy').format(DateTime.now());
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static Future<void> enqueueSync(Map<String, dynamic> action) async {
    final box = Hive.box(syncBox);
    final key = 'sync_${DateTime.now().millisecondsSinceEpoch}_${action['type'] ?? 'unknown'}';

    final enriched = {
      ...action,
      'attempts': 0,
      'createdAt': _nowIso(),
      'lastAttempt': null,
      'lastError': null,
      'status': 'pending',
    };

    final sanitized = sanitize(enriched);
    await box.put(key, sanitized);

    print('''
ENQUEUED TO SYNC QUEUE
Type: ${action['type'] ?? 'unknown'}
Key: $key
Queue size now: ${box.length}
Data: $sanitized
''');
  }

  static Map<String, Map<String, dynamic>> getAllSync() {
    final box = Hive.box(syncBox);
    final items = Map.fromEntries(box.keys.map((k) {
      final v = box.get(k);
      if (v == null || v is! Map) return MapEntry(k.toString(), <String, dynamic>{});
      return MapEntry(k.toString(), Map<String, dynamic>.from(v));
    }));
    print("getAllSync: Retrieved ${items.length} items from queue");
    return items;
  }

  static Future<void> removeSyncKey(String key) async {
    await Hive.box(syncBox).delete(key);
    print("Removed sync item: $key | Remaining: ${Hive.box(syncBox).length}");
  }

  static Future<void> seedLocalAdmins() async {
    final box = Hive.box(usersBox);
    
    Future<void> seedOne(String email, String password, String role, String branchId) async {
      final key = 'user:$email';
      if (!box.containsKey(key)) {
        await box.put(key, {
          'email': email,
          'username': role == 'server' ? 'server' : (role == 'chairman' ? 'chairman' : 'admin'),
          'passwordHash': hashPassword(password),
          'role': role,
          'uid': 'local-${email.replaceAll('@', '_').replaceAll('.', '_')}',
          'branchId': branchId,
          'branchName': role == 'server' ? 'Server' : (role == 'chairman' ? 'Chairman' : 'HQ'),
          'createdAt': DateTime.now().toIso8601String(),
        });
        print('✅ Seeded user: $email with role: $role');
      }
    }

    await seedOne('admin@gmd.com', 'Admin@123', 'admin', 'all');
    await seedOne('server@gmd.com', 'Server@123', 'server', 'sialkot');
  }

  static Future<void> forceDeduplicatePatients() async {
    final box = Hive.box(patientsBox);
    final flagsBox = Hive.box('app_flags');
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

    final entriesBoxInstance = Hive.box(entriesBox);
    for (final entry in uniquePatients.entries) {
      final newKey = entry.key;
      var patient = entry.value;
      patient = sanitize(patient);
      patient['patientId'] = newKey;
      await box.put(newKey, patient);

      final oldKeys = keyToOldKeys[newKey]!;
      for (final tokenKey in entriesBoxInstance.keys.toList()) {
        final tokenVal = entriesBoxInstance.get(tokenKey);
        if (tokenVal is Map && oldKeys.contains(tokenVal['patientId'])) {
          final updatedToken = Map<String, dynamic>.from(tokenVal);
          updatedToken['patientId'] = newKey;
          await entriesBoxInstance.put(tokenKey, updatedToken);
        }
      }

      for (final oldKey in oldKeys) {
        if (oldKey != newKey) {
          await box.delete(oldKey);
        }
      }
    }

    await flagsBox.put('patients_deduplicated_v2', true);
    print('Patient deduplication completed');
  }

  static Future<void> saveLocalUser(Map<String, dynamic> user) async {
    if (user['email'] == null) return;
    final box = Hive.box(usersBox);
    final sanitized = sanitize(user);
    await box.put('user:${sanitized['email']}', sanitized);
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
      if (val is Map && val['uid'] == uid) {
        return Map<String, dynamic>.from(val);
      }
    }
    return null;
  }

  static Future<void> deleteLocalUser(String email) async {
    await Hive.box(usersBox).delete('user:$email');
  }

  static Future<void> saveLocalPatient(Map<String, dynamic> patient) async {
    final box = Hive.box(patientsBox);
    var sanitized = sanitize(patient);
    final key = getPatientKey(sanitized);
    sanitized['patientId'] = key;
    await box.put(key, sanitized);
    print("Saved patient locally with key: $key");
  }

  static Future<void> saveAllLocalPatients(List<Map<String, dynamic>> patients) async {
    final box = Hive.box(patientsBox);
    final Map<String, Map<String, dynamic>> updates = {};

    for (final patient in patients) {
      try {
        var sanitized = sanitize(patient);
        final key = getPatientKey(sanitized);
        sanitized['patientId'] = key;
        updates[key] = sanitized;
      } catch (e) {
        print('Skipped invalid patient: $e');
      }
    }
    await box.putAll(updates);
    print("Saved ${updates.length} patients locally");
  }

  static Future<void> saveAllLocalStockItems(List<Map<String, dynamic>> items) async {
    final box = Hive.box(stockBox);
    await box.clear();
    final Map<String, Map<String, dynamic>> stockMap = {
      for (var item in items) 'stock:${item['id']}': item
    };
    await box.putAll(stockMap);
    print("Saved ${items.length} stock items locally");
  }

  static Future<void> saveLocalStockItem(Map<String, dynamic> stockItem) async {
    final id = stockItem['id']?.toString();
    if (id == null) return;
    final sanitized = sanitize(stockItem);
    await Hive.box(stockBox).put('stock:$id', sanitized);
    print("Saved stock item locally: $id");
  }

  static Future<void> deleteLocalStockItem(String id) async {
    await Hive.box(stockBox).delete('stock:$id');
  }

  static Map<String, dynamic>? getLocalPatientByCnic(String cnic) {
    final normalized = cnic.replaceAll('-', '').trim();
    final box = Hive.box(patientsBox);

    var patient = box.get(normalized);
    if (patient != null) return Map<String, dynamic>.from(patient as Map);

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
    print("Retrieved ${patients.length} local patients");
    return patients;
  }

  static List<Map<String, dynamic>> searchPatientsByCnicOrGuardian(String input, {String? branchId}) {
    final normalized = input.replaceAll('-', '').trim().toLowerCase();
    var patients = getAllLocalPatients(branchId: branchId);

    return patients.where((p) {
      final cnic = (p['cnic'] as String?)?.replaceAll('-', '').trim().toLowerCase() ?? '';
      final guardian = (p['guardianCnic'] as String?)?.replaceAll('-', '').trim().toLowerCase() ?? '';
      final phone = (p['phone'] as String?)?.replaceAll(RegExp(r'\D'), '') ?? '';

      return cnic.contains(normalized) ||
             guardian.contains(normalized) ||
             phone.contains(normalized.replaceAll(RegExp(r'\D'), ''));
    }).toList();
  }

  static Future<void> deleteLocalPatient(String patientId) async {
    await Hive.box(patientsBox).delete(patientId);
  }

  static Future<void> saveEntryLocal(String branchId, String serial, Map<String, dynamic> entryData) async {
    final key = '$branchId-$serial';
    var sanitized = sanitize(entryData);
    final todayKey = getTodayDateKey();
    sanitized['dateKey'] = todayKey;
    sanitized['datePart'] = todayKey;
    sanitized['branchId'] = branchId;
    if (sanitized['timestamp'] != null) {
      sanitized['timestamp'] = _toDateTime(sanitized['timestamp']).toIso8601String();
    }
    if (sanitized['createdAt'] != null) {
      sanitized['createdAt'] = _toDateTime(sanitized['createdAt']).toIso8601String();
    }
    await Hive.box(entriesBox).put(key, sanitized);
    print('LOCAL SAVE: Token $serial saved with dateKey $todayKey, queueType: ${sanitized['queueType']}');
  }

  static List<Map<String, dynamic>> getLocalEntries(String branchId) {
    return Hive.box(entriesBox)
        .keys
        .where((k) => k.toString().startsWith('$branchId-'))
        .map((k) => Map<String, dynamic>.from(Hive.box(entriesBox).get(k) as Map))
        .toList();
  }

  static Future<void> deleteLocalEntry(String branchId, String serial) async {
    await Hive.box(entriesBox).delete('$branchId-$serial');
  }

  static Future<void> saveLocalPrescription(Map<String, dynamic> prescription) async {
    final serialRaw = prescription['serial']?.toString() ?? prescription['id']?.toString();
    final serial = serialRaw?.trim();

    if (serial == null || serial.isEmpty) {
      print("WARNING: Cannot save prescription — missing serial/id");
      return;
    }

    final cnicCandidates = [
      'patientCnic',
      'cnic',
      'patientCNIC',
      'guardianCnic',
      'patient_cnic',
      'guardian_cnic',
      'cnic_number'
    ];

    String? cnicRaw;
    for (final field in cnicCandidates) {
      cnicRaw = prescription[field]?.toString();
      if (cnicRaw != null && cnicRaw.trim().isNotEmpty && cnicRaw != '00000-0000000-0') {
        break;
      }
    }

    if (cnicRaw == null || cnicRaw.trim().isEmpty || cnicRaw == '00000-0000000-0') {
      cnicRaw = 'unknown_cnic_${DateTime.now().millisecondsSinceEpoch}';
      print("WARNING: No valid CNIC found in prescription data! Using fallback: $cnicRaw");
    }

    final cleanCnic = cnicRaw.trim().replaceAll('-', '').replaceAll(' ', '');
    final key = '${cleanCnic}_$serial';

    var sanitized = sanitize(prescription);
    sanitized['patientCnic'] = cleanCnic;
    sanitized['cnic'] = cleanCnic;
    sanitized['serial'] = serial;

    if (sanitized['createdAt'] is DateTime) {
      sanitized['createdAt'] = (sanitized['createdAt'] as DateTime).toIso8601String();
    }
    if (sanitized['updatedAt'] is DateTime) {
      sanitized['updatedAt'] = (sanitized['updatedAt'] as DateTime).toIso8601String();
    }

    await Hive.box(prescriptionsBox).put(key, sanitized);
    print("PRESCRIPTION SAVED LOCALLY → key: '$key' (cnic: $cleanCnic, serial: $serial)");
  }

  static Map<String, dynamic>? getLocalPrescription(String serial) {
    final box = Hive.box(prescriptionsBox);
    final cleanSerial = serial.trim();

    print("getLocalPrescription: Looking for serial '$cleanSerial' (box size: ${box.length})");

    var data = box.get(cleanSerial);
    if (data != null && data is Map) {
      print("Found by direct key: '$cleanSerial'");
      return Map<String, dynamic>.from(data);
    }

    for (var key in box.keys) {
      if (key is String && key.endsWith('_$cleanSerial')) {
        data = box.get(key);
        if (data != null && data is Map) {
          print("Found by composite key (ends with): '$key'");
          return Map<String, dynamic>.from(data);
        }
      }
    }

    for (var key in box.keys) {
      if (key is String && key.contains(cleanSerial)) {
        data = box.get(key);
        if (data != null && data is Map) {
          print("Found by key containing serial: '$key'");
          return Map<String, dynamic>.from(data);
        }
      }
    }

    for (var key in box.keys) {
      data = box.get(key);
      if (data != null && data is Map) {
        final savedSerial = data['serial']?.toString()?.trim();
        if (savedSerial == cleanSerial) {
          print("Found by value scan - key: '$key', saved serial: '$savedSerial'");
          return Map<String, dynamic>.from(data);
        }
      }
    }

    print("!!! NO PRESCRIPTION FOUND for serial '$cleanSerial' after all strategies !!!");
    if (box.length > 0) {
      print("Existing keys in prescriptions box: ${box.keys.take(10).toList()} ${box.length > 10 ? '(+${box.length - 10} more)' : ''}");
    } else {
      print("Prescriptions box is EMPTY!");
    }

    return null;
  }

  static Map<String, dynamic>? getLocalPrescriptionByCnic(String cnic) {
    final box = Hive.box(prescriptionsBox);
    if (!box.isOpen) {
      debugPrint('Prescriptions box not open!');
      return null;
    }

    var cleanCnic = cnic.trim().replaceAll('-', '').replaceAll(' ', '');
    cleanCnic = cleanCnic.replaceAll(RegExp(r'^0+'), '');

    debugPrint("getLocalPrescriptionByCnic: Searching for '$cnic' → cleaned: '$cleanCnic'");

    for (var value in box.values) {
      final presc = Map<String, dynamic>.from(value as Map);

      final prescCnicRaw = presc['patientCnic']?.toString() ??
                           presc['cnic']?.toString() ??
                           presc['patientCNIC']?.toString() ??
                           presc['guardianCnic']?.toString() ??
                           '';

      var prescCnic = prescCnicRaw.trim().replaceAll('-', '').replaceAll(' ', '');
      prescCnic = prescCnic.replaceAll(RegExp(r'^0+'), '');

      if (prescCnic == cleanCnic ||
          prescCnic.contains(cleanCnic) ||
          cleanCnic.contains(prescCnic) ||
          prescCnic == cleanCnic.replaceAll('0', '')) {
        debugPrint("Found by CNIC! Serial: ${presc['serial'] ?? 'unknown'} | Matched: '$prescCnic'");
        return presc;
      }
    }

    debugPrint("No prescription found for CNIC variations of '$cnic'");
    return null;
  }

  static List<Map<String, dynamic>> getAllLocalPrescriptions() {
    final list = Hive.box(prescriptionsBox)
        .values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    print("Retrieved ${list.length} local prescriptions total");
    return list;
  }

  static List<Map<String, dynamic>> getBranchPrescriptions(String branchId) {
    final list = getAllLocalPrescriptions()
        .where((p) => p['branchId'] == branchId)
        .toList();
    print("Filtered ${list.length} prescriptions for branch $branchId");
    return list;
  }

  static Future<void> deleteLocalPrescription(String serial) async {
    final box = Hive.box(prescriptionsBox);
    for (var key in box.keys.toList()) {
      if (key is String && key.contains(serial)) {
        await box.delete(key);
        print("Deleted local prescription containing serial $serial (key: $key)");
      }
    }
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
    print("Retrieved ${items.length} local stock items");
    return items;
  }

  static Future<void> saveLocalBranch(Map<String, dynamic> branch) async {
    final id = branch['id']?.toString();
    if (id == null) return;
    final sanitized = sanitize(branch);
    await Hive.box(branchesBox).put('branch:$id', sanitized);
  }

  static Future<void> deleteLocalBranch(String id) async {
    await Hive.box(branchesBox).delete('branch:$id');
  }

  static Future<void> downloadAllPatients(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .get();

      final List<Map<String, dynamic>> patients = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['patientId'] = doc.id;
        data['branchId'] = branchId;
        patients.add(data);
      }
      await saveAllLocalPatients(patients);
      print('Downloaded ${patients.length} patients');
    } catch (e) {
      print('Error downloading patients: $e');
    }
  }

  static Future<void> downloadTodayTokens(String branchId) async {
    final today = getTodayDateKey();
    print('DOWNLOAD TOKENS: Date $today, Branch $branchId');

    try {
      final serialsRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('serials')
          .doc(today);

      final dateDoc = await serialsRef.get();
      if (!dateDoc.exists) {
        print('No tokens document for today ($today) — will be created on upload');
        return;
      }

      final queueTypes = ['zakat', 'non-zakat', 'gmwf'];
      int totalCount = 0;

      for (final type in queueTypes) {
        final snap = await serialsRef.collection(type).get();
        for (var doc in snap.docs) {
          final data = doc.data();
          data['serial'] = doc.id;
          data['dateKey'] = today;
          data['branchId'] = branchId;
          data['queueType'] = type;
          await saveEntryLocal(branchId, doc.id, data);
          totalCount++;
        }
        print('Downloaded ${snap.docs.length} $type tokens');
      }

      print('DOWNLOAD SUCCESS: $totalCount tokens for today ($today)');
    } catch (e, stack) {
      print('DOWNLOAD ERROR: $e');
      print(stack);
    }
  }

  static Future<void> downloadInventory(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('inventory')
          .get();

      final List<Map<String, dynamic>> items = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['branchId'] = branchId;
        items.add(data);
      }

      await saveAllLocalStockItems(items);
      print('SUCCESS: Downloaded ${items.length} inventory items');
    } catch (e) {
      print('Error downloading inventory: $e');
    }
  }

  static Future<void> downloadPatientHistory(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('prescriptions')
          .get();

      final List<Map<String, dynamic>> prescriptions = [];

      print("Firestore prescriptions collection has ${snapshot.docs.length} patient/CNICS");

      for (var patientDoc in snapshot.docs) {
        final patientCnic = patientDoc.id;
        print("→ Fetching prescriptions for CNIC/patient: $patientCnic");

        final prescSubSnapshot = await patientDoc.reference.collection('prescriptions').get();

        print("  → Found ${prescSubSnapshot.docs.length} prescriptions");

        for (var prescDoc in prescSubSnapshot.docs) {
          final data = prescDoc.data();
          data['id'] = prescDoc.id;
          data['serial'] = prescDoc.id;
          data['patientCnic'] = patientCnic;
          data['branchId'] = branchId;
          prescriptions.add(data);
        }
      }

      await Hive.box(prescriptionsBox).clear();
      final Map<String, Map<String, dynamic>> prescMap = {
        for (var p in prescriptions)
          '${p['patientCnic']}-${p['serial']}': p
      };
      await Hive.box(prescriptionsBox).putAll(prescMap);

      print('Downloaded ${prescriptions.length} patient prescriptions and saved locally');
    } catch (e, stack) {
      print('Error downloading patient history: $e');
      print(stack);
    }
  }

  static Future<void> refreshPrescriptions(String branchId) async {
    await downloadPatientHistory(branchId);
    print('Refreshed prescriptions from server');
  }

  static Future<void> fullDownloadOnce(String branchId) async {
    await downloadAllPatients(branchId);
    await downloadInventory(branchId);
    await downloadPatientHistory(branchId);
    await downloadTodayTokens(branchId);
  }
}