// lib/services/local_storage_service.dart
//
// CHANGES IN THIS VERSION:
//   FIX 1: searchPatientsByCnicOrGuardian() now also matches by patient name
//           (minimum 3 chars). This catches cases where the CNIC/phone search
//           fails because the patient's own CNIC was not stored (child patients
//           registered only with a guardian CNIC).
//   FIX 2: saveLocalPatient() now calls flush() after put() so the write is
//           durably committed before ValueListenableBuilder rebuilds the UI.
//   FIX 3: saveAllLocalPatients() also calls flush() after putAll() for the
//           same reason — bulk downloads now immediately reflect in the UI.
//   FIX 4: downloadTodayTokens() now CLEARS today's Hive entries for the
//           branch before re-downloading from Firestore. This is the critical
//           fix for reversed tokens that were deleted from Firestore still
//           showing in the UI — the old version only added/updated entries and
//           never removed ones that no longer exist in Firestore.
//
// ─── BUG FIX (sync revert) ────────────────────────────────────────────────
//   FIX-SYNC-3: downloadTodayTokens() Step 4 merge logic now protects ALL
//               terminal local states, not just status == 'completed'.
//
// ─── NEW ──────────────────────────────────────────────────────────────────
//   saveLocalInventoryItem(): Saves a single inventory item (keyed by
//     medicineId) to the stock box.
//
// ─── MEDICINE RESTRICTION FIRESTORE FIX ──────────────────────────────────
//   saveMedicineRestriction() now enqueues a 'save_medicine_restriction'
//   sync op so the restriction is written to Firestore and available to
//   internet-only terminals (not just LAN-connected ones).
//
//   downloadMedicineRestrictions() — new method that pulls active
//   restrictions from Firestore into local Hive. Called on startup,
//   after every upload cycle, and by the receptionist before the block
//   check so internet-only devices always have current data.
//
//   fullDownloadOnce() now includes downloadMedicineRestrictions().

import 'dart:convert';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class LocalStorageService {
  // ── Box names ──────────────────────────────────────────────────────────────
  static const String usersBox         = 'local_users';
  static const String patientsBox      = 'local_patients';
  static const String entriesBox       = 'local_entries';
  static const String syncBox          = 'sync_queue';
  static const String prescriptionsBox = 'local_prescriptions';
  static const String stockBox         = 'local_stock_items';
  static const String branchesBox      = 'local_branches';
  static const String dispensaryBox    = 'local_dispensary';
  static const String medicineRestrictionsBox = 'local_medicine_restrictions';
  static const String donationsBox     = 'local_donations';
  static const String creditsBox       = 'local_credit_ledger';

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Safely opens a Hive box, deleting it from disk and recreating it if
  /// an "unknown typeId" error occurs (legacy/corrupted data).
  static Future<Box<T>> openBoxSafe<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } catch (e) {
      debugPrint('[LocalStorageService] openBoxSafe error for "$name": $e');
      final err = e.toString();
      // If we see "unknown typeId" or "register an adapter", the box contains 
      // data we can no longer read. We must reset it to allow app startup.
      if (err.contains('typeId') || err.contains('adapter') || err.contains('Adapter')) {
        debugPrint('[LocalStorageService] Resetting corrupted box "$name"...');
        await Hive.deleteBoxFromDisk(name);
        return await Hive.openBox<T>(name);
      }
      rethrow;
    }
  }

  static Future<void> init() async {
    debugPrint('[LocalStorageService.init] Opening all Hive boxes...');
    final boxNames = [
      usersBox,
      patientsBox,
      entriesBox,
      syncBox,
      prescriptionsBox,
      stockBox,
      branchesBox,
      dispensaryBox,
      donationsBox,
      creditsBox,
      medicineRestrictionsBox,
      'app_settings',
      'app_flags',
    ];

    for (final name in boxNames) {
      await openBoxSafe(name);
    }
    debugPrint('[LocalStorageService.init] All Hive boxes opened safely.');
  }


  static Future<void> clearAllData() async {
    final boxNames = [
      usersBox, patientsBox, entriesBox, syncBox, prescriptionsBox,
      stockBox, branchesBox, dispensaryBox, donationsBox, creditsBox,
      medicineRestrictionsBox, 'app_settings', 'app_flags',
      'local_submissions', 'server_sync_queue', 'local_edit_requests',
      'server_sync_failed'
    ];

    for (final name in boxNames) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).close();
      }
      await Hive.deleteBoxFromDisk(name);
    }
    debugPrint('[LocalStorage] All local data wiped from disk.');
  }


  // ════════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ════════════════════════════════════════════════════════════════════════════

  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static DateTime _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime)  return value;
    if (value is String) {
      try { return DateTime.parse(value); } catch (_) {}
    }
    return DateTime.now();
  }

  static int calculateAgeFromDob(dynamic dobValue) {
    if (dobValue == null) return 0;
    final DateTime birthDate = _toDateTime(dobValue);
    final DateTime today     = DateTime.now();
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
    if (item is Timestamp || item is DateTime)
      return _toDateTime(item).toIso8601String();
    if (item is Map) return sanitize(Map<String, dynamic>.from(item));
    return item;
  }

  static String getTodayDateKey() => DateFormat('ddMMyy').format(DateTime.now());

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static String _newLocalId() =>
      DateTime.now().millisecondsSinceEpoch.toString();

  // ════════════════════════════════════════════════════════════════════════════
  // SYNC QUEUE
  // ════════════════════════════════════════════════════════════════════════════

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

  // ════════════════════════════════════════════════════════════════════════════
  // RECEIPT SEQUENCE
  // ════════════════════════════════════════════════════════════════════════════

  static Future<String> nextReceiptNumber(String branchId) async {
    final dateKey = DateFormat('ddMMyy').format(DateTime.now());

    try {
      final ref = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('meta')
          .doc('receipt_seq');

      int seq = 1;

      if (Platform.isWindows) {
        debugPrint('[LS.nextReceiptNumber] Windows: Using stable get/set approach...');
        final snap = await ref.get().timeout(const Duration(seconds: 3));
        if (snap.exists) {
          seq = ((snap.data()?[dateKey] as int?) ?? 0) + 1;
        }
        await ref.set({dateKey: seq}, SetOptions(merge: true))
            .timeout(const Duration(seconds: 3));
      } else {
        debugPrint('[LS.nextReceiptNumber] Attempting Firestore Transaction...');
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(ref);
          seq = snap.exists ? ((snap.data()?[dateKey] as int?) ?? 0) + 1 : 1;
          tx.set(ref, {dateKey: seq}, SetOptions(merge: true));
        }).timeout(const Duration(seconds: 5));
      }

      debugPrint('[LS.nextReceiptNumber] Online sequence: $seq');
      return buildReceiptNumber(branchId, seq);
    } catch (e) {
      debugPrint('[LS.nextReceiptNumber] Falling back to local: $e');
      final box     = Hive.box('app_settings');
      final seqKey  = 'local_seq_${branchId}_$dateKey';
      final current = (box.get(seqKey) as int?) ?? 0;
      final next    = current + 1;
      await box.put(seqKey, next);
      return '${buildReceiptNumber(branchId, next)}-L';
    }
  }

  static String buildReceiptNumber(String branchId, int seq) {
    final code    = _branchCode(branchId);
    final dateStr = DateFormat('ddMMyy').format(DateTime.now());
    final seqStr  = seq.toString().padLeft(3, '0');
    return '$code-$dateStr-$seqStr';
  }

  static String _branchCode(String branchId) {
    final id = branchId.toLowerCase().trim();
    if (id.contains('gujrat'))                                    return 'grt';
    if (id.contains('jalalpurjattan') || id.contains('jalalpur')) return 'jpt';
    if (id.contains('karachi-1') || id == 'karachi1')             return 'khi1';
    if (id.contains('karachi-2') || id == 'karachi2')             return 'khi2';
    if (id.contains('rawalpindi'))                                return 'rwp';
    if (id.contains('sialkot'))                                   return 'skt';
    if (id.contains('lahore') || id == 'lhr')                     return 'lhr';
    return id.length >= 3 ? id.substring(0, 3) : id;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DONATIONS — local read/write
  // ════════════════════════════════════════════════════════════════════════════

  static String _donationKey(String branchId, String date, String localId) =>
      '${branchId}__${date}__$localId';

  static Future<String> saveDonation({
    required String branchId,
    required Map<String, dynamic> data,
  }) async {
    final localId = _newLocalId();
    final date    = (data['date'] as String?) ??
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    final key     = _donationKey(branchId, date, localId);

    final record = Map<String, dynamic>.from(data);
    record['localId']     = localId;
    record['hiveKey']     = key;
    record['branchId']    = branchId;
    record['syncStatus']  = 'pending';
    record['firestoreId'] = null;

    final sanitized = sanitize(record);
    await Hive.box(donationsBox).put(key, sanitized);
    debugPrint('[LS] Donation saved locally → $key');

    await enqueueSync({
      'type':     'save_donation',
      'branchId': branchId,
      'localId':  localId,
      'hiveKey':  key,
      'data':     sanitized,
    });

    return key;
  }

  static Future<void> markDonationSynced(
      String hiveKey, String firestoreId) async {
    final box = Hive.box(donationsBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..['firestoreId'] = firestoreId
      ..['syncStatus']  = 'synced';
    await box.put(hiveKey, updated);
    debugPrint('[LS] Donation synced → $hiveKey → fs:$firestoreId');
  }

  static List<Map<String, dynamic>> getDonations(String branchId) {
    final prefix = '${branchId}__';
    final box    = Hive.box(donationsBox);
    return box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList()
      ..sort((a, b) {
          final at = (a['timestamp'] as String?) ?? '';
          final bt = (b['timestamp'] as String?) ?? '';
          return bt.compareTo(at);
        });
  }

  static Stream<List<Map<String, dynamic>>> streamDonations(
      String branchId) async* {
    yield getDonations(branchId);
    await for (final _ in Hive.box(donationsBox).watch()) {
      yield getDonations(branchId);
    }
  }

  static Future<void> deleteDonation(String hiveKey, String branchId) async {
    final box = Hive.box(donationsBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;

    final fsId = (raw as Map)['firestoreId']?.toString();
    await box.delete(hiveKey);

    if (fsId != null && fsId.isNotEmpty) {
      await enqueueSync({
        'type':        'delete_donation',
        'branchId':    branchId,
        'firestoreId': fsId,
      });
    }
  }

  static Future<void> downloadDonations(String branchId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final snap  = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('donations')
          .where('date', isEqualTo: today)
          .get();

      final box = Hive.box(donationsBox);
      for (final doc in snap.docs) {
        if (doc.id == 'credit_ledger') continue;
        final d       = doc.data();
        final date    = (d['date'] as String?) ?? today;
        final localId = (d['localId'] as String?) ?? doc.id;
        final key     = _donationKey(branchId, date, localId);

        final existing = box.get(key);
        if (existing == null) {
          await box.put(key, sanitize({
            ...d,
            'firestoreId': doc.id,
            'localId':     localId,
            'hiveKey':     key,
            'syncStatus':  'synced',
          }));
        } else {
          final ex = Map<String, dynamic>.from(existing as Map);
          if (ex['syncStatus'] != 'pending') {
            ex['firestoreId'] = doc.id;
            ex['syncStatus']  = 'synced';
            await box.put(key, ex);
          }
        }
      }
      debugPrint('[LS] Downloaded ${snap.docs.length} donations for $today');
    } catch (e) {
      debugPrint('[LS] downloadDonations error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CREDIT LEDGER — local read/write
  // ════════════════════════════════════════════════════════════════════════════

  static String _creditKey(String branchId, String localId) =>
      '${branchId}__credit__$localId';

  static Future<String> saveCreditEntry({
    required String branchId,
    required Map<String, dynamic> data,
  }) async {
    final localId = _newLocalId();
    final key     = _creditKey(branchId, localId);

    final record = Map<String, dynamic>.from(data);
    record['localId']     = localId;
    record['hiveKey']     = key;
    record['branchId']    = branchId;
    record['syncStatus']  = 'pending';
    record['firestoreId'] = null;

    final sanitized = sanitize(record);
    await Hive.box(creditsBox).put(key, sanitized);
    debugPrint('[LS] Credit saved locally → $key | '
        '${data['fromRole']} → ${data['toRole']} | PKR ${data['amount']}');

    await enqueueSync({
      'type':     'save_credit_entry',
      'branchId': branchId,
      'localId':  localId,
      'hiveKey':  key,
      'data':     sanitized,
    });

    return key;
  }

  static Future<void> markCreditSynced(
      String hiveKey, String firestoreId) async {
    final box = Hive.box(creditsBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..['firestoreId'] = firestoreId
      ..['syncStatus']  = 'synced';
    await box.put(hiveKey, updated);
    debugPrint('[LS] Credit synced → $hiveKey → fs:$firestoreId');
  }

  static Future<void> updateCreditStatus(
    String hiveKey, {
    required String status,
    required String actorUsername,
    required String branchId,
    String? rejectionReason,
  }) async {
    final box = Hive.box(creditsBox);
    final raw = box.get(hiveKey);
    if (raw == null) {
      debugPrint('[LS] updateCreditStatus: key not found → $hiveKey');
      return;
    }

    final isApproval = status == 'approved';
    final fields = <String, dynamic>{
      'status': status,
      if (isApproval)  'approvedBy': actorUsername,
      if (isApproval)  'approvedAt': _nowIso(),
      if (!isApproval) 'rejectedBy': actorUsername,
      if (!isApproval) 'rejectedAt': _nowIso(),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
    };

    final updated = Map<String, dynamic>.from(raw as Map)..addAll(fields);
    await box.put(hiveKey, updated);
    debugPrint('[LS] Credit status updated → $hiveKey → $status');

    final fsId = (raw as Map)['firestoreId']?.toString();
    if (fsId != null && fsId.isNotEmpty) {
      await enqueueSync({
        'type':        'update_credit_status',
        'branchId':    branchId,
        'firestoreId': fsId,
        'fields':      fields,
      });
    } else {
      await enqueueSync({
        'type':     'save_credit_entry',
        'branchId': branchId,
        'localId':  (updated['localId'] as String?) ?? hiveKey,
        'hiveKey':  hiveKey,
        'data':     updated,
      });
    }
  }

  static List<Map<String, dynamic>> getCredits({
    required String branchId,
    String? toRole,
    String? fromUserId,
    String? status,
  }) {
    final prefix = '${branchId}__credit__';
    final box    = Hive.box(creditsBox);

    var list = box.keys
        .where((k) => k.toString().startsWith(prefix))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();

    if (toRole     != null) list = list.where((e) => e['toRole']     == toRole).toList();
    if (fromUserId != null) list = list.where((e) => e['fromUserId'] == fromUserId).toList();
    if (status     != null) list = list.where((e) => e['status']     == status).toList();

    list.sort((a, b) {
      final at = (a['timestamp'] as String?) ?? '';
      final bt = (b['timestamp'] as String?) ?? '';
      return bt.compareTo(at);
    });
    return list;
  }

  static Stream<List<Map<String, dynamic>>> streamCredits({
    required String branchId,
    String? toRole,
    String? fromUserId,
    String? status,
  }) async* {
    yield getCredits(
        branchId: branchId, toRole: toRole,
        fromUserId: fromUserId, status: status);
    await for (final _ in Hive.box(creditsBox).watch()) {
      yield getCredits(
          branchId: branchId, toRole: toRole,
          fromUserId: fromUserId, status: status);
    }
  }

  static Future<void> downloadCredits(String branchId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('creditLedger')
          .get();

      final box = Hive.box(creditsBox);
      for (final doc in snap.docs) {
        final d       = doc.data();
        final localId = (d['localId'] as String?) ?? doc.id;
        final key     = _creditKey(branchId, localId);

        final existing = box.get(key);
        if (existing == null) {
          await box.put(key, sanitize({
            ...d,
            'firestoreId': doc.id,
            'localId':     localId,
            'hiveKey':     key,
            'syncStatus':  'synced',
          }));
        } else {
          final ex = Map<String, dynamic>.from(existing as Map);
          if (ex['syncStatus'] != 'pending') {
            ex['firestoreId'] = doc.id;
            ex['syncStatus']  = 'synced';
            await box.put(key, ex);
          }
        }
      }
      debugPrint('[LS] Downloaded ${snap.docs.length} credit entries');
    } catch (e) {
      debugPrint('[LS] downloadCredits error: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FULL DOWNLOAD HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> fullDownloadOnce(String branchId) async {
    await downloadAllPatients(branchId);
    await downloadInventory(branchId);
    await refreshPrescriptions(branchId);
    await downloadTodayTokens(branchId);
    await downloadDonations(branchId);
    await downloadCredits(branchId);
    await downloadMedicineRestrictions(branchId); // ← ADDED: Firestore restriction sync
    debugPrint('[LS] fullDownloadOnce completed for branch: $branchId');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PATIENTS
  // ════════════════════════════════════════════════════════════════════════════

  static String _normalizeName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String getPatientKey(Map<String, dynamic> patient) {
    final isAdult      = patient['isAdult'] as bool? ?? true;
    final cnic         = (patient['cnic'] as String?)?.replaceAll('-', '').trim();
    final guardianCnic =
        (patient['guardianCnic'] as String?)?.replaceAll('-', '').trim();
    final name         = (patient['name'] as String?)?.trim() ?? '';

    if (isAdult && cnic != null && cnic.isNotEmpty) return cnic;
    if (!isAdult &&
        guardianCnic != null &&
        guardianCnic.isNotEmpty &&
        name.isNotEmpty) {
      return '${guardianCnic}_child_${_normalizeName(name)}';
    }
    final fallback = patient['patientId']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return 'fallback_$fallback';
  }

  static Future<void> seedLocalAdmins() async {
    final box = Hive.box(usersBox);

    Future<void> seedOne(String email, String password, String role,
        String branchId) async {
      final key = 'user:$email';
      if (!box.containsKey(key)) {
        await box.put(key, {
          'email':        email,
          'username':     role == 'server'
              ? 'server'
              : (role == 'chairman' ? 'chairman' : 'admin'),
          'passwordHash': hashPassword(password),
          'role':         role,
          'uid':          'local-${email.replaceAll('@', '_').replaceAll('.', '_')}',
          'branchId':     branchId,
          'branchName':   role == 'server'
              ? 'Server'
              : (role == 'chairman' ? 'Chairman' : 'HQ'),
          'createdAt':    DateTime.now().toIso8601String(),
        });
        debugPrint('Seeded user: $email');
      }
    }

    await seedOne('admin@gmd.com',  'Admin@123',  'admin',  'all');
    await seedOne('server@gmd.com', 'Server@123', 'server', 'sialkot');
  }

  static Future<void> forceDeduplicatePatients() async {
    final box      = Hive.box(patientsBox);
    final flagsBox = Hive.box('app_flags');
    if (flagsBox.get('patients_deduplicated_v2') == true) return;

    final Map<String, Map<String, dynamic>> uniquePatients = {};
    final Map<String, List<String>> keyToOldKeys           = {};

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
    var sanitized      = sanitize(patient);
    final key          = getPatientKey(sanitized);
    sanitized['patientId'] = key;
    final box = Hive.box(patientsBox);
    await box.put(key, sanitized);
    await box.flush();
  }

  static Future<void> saveAllLocalPatients(
      List<Map<String, dynamic>> patients) async {
    final box     = Hive.box(patientsBox);
    final updates = <String, Map<String, dynamic>>{};
    for (final patient in patients) {
      try {
        var s = sanitize(patient);
        final key  = getPatientKey(s);
        s['patientId'] = key;
        updates[key] = s;
      } catch (e) {
        debugPrint('[LocalStorage] Skipped invalid patient: $e');
      }
    }
    await box.putAll(updates);
    await box.flush();
  }

  static Map<String, dynamic>? getLocalPatientByCnic(String cnic) {
    final normalized = cnic.replaceAll('-', '').trim();
    final box        = Hive.box(patientsBox);
    final direct     = box.get(normalized);
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
      patients = patients
          .where((p) => p['branchId'] == branchId)
          .toList();
    }
    return patients;
  }

  static List<Map<String, dynamic>> searchPatientsByCnicOrGuardian(
      String input, {String? branchId}) {
    final normalized      = input.replaceAll('-', '').trim().toLowerCase();
    final normalizedPhone = normalized.replaceAll(RegExp(r'\D'), '');
    final normalizedName  = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');

    final all = getAllLocalPatients(branchId: branchId);
    final results = <Map<String, dynamic>>[];

    for (final p in all) {
      final cnic     = (p['cnic'] as String?)
              ?.replaceAll('-', '').trim().toLowerCase() ??
          '';
      final guardian = (p['guardianCnic'] as String?)
              ?.replaceAll('-', '').trim().toLowerCase() ??
          '';
      final phone    =
          (p['phone'] as String?)?.replaceAll(RegExp(r'\D'), '') ?? '';
      final name     = _normalizeName((p['name'] as String?) ?? '');

      bool match = false;
      if (cnic.isNotEmpty     && cnic.contains(normalized))     match = true;
      else if (guardian.isNotEmpty && guardian.contains(normalized)) match = true;
      else if (normalizedPhone.length >= 4 &&
          phone.isNotEmpty &&
          phone.contains(normalizedPhone)) match = true;
      else if (normalizedName.length >= 3 &&
          name.isNotEmpty &&
          name.contains(normalizedName)) match = true;

      if (match) {
        // Ensure patientId is present — critical for medicine restrictions
        if (p['patientId'] == null) {
          p['patientId'] = getPatientKey(p);
        }
        results.add(p);
      }
    }
    return results;
  }

  static Future<void> deleteLocalPatient(String patientId) async {
    await Hive.box(patientsBox).delete(patientId);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ENTRIES / TOKENS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveEntryLocal(
      String branchId, String serial, Map<String, dynamic> entryData) async {
    final key      = '$branchId-$serial';
    var sanitized  = sanitize(entryData);
    final todayKey = getTodayDateKey();
    sanitized['dateKey']  = sanitized['dateKey'] ?? todayKey;
    sanitized['branchId'] = branchId;
    sanitized['serial']   = serial;
    if (sanitized['timestamp'] != null) {
      sanitized['timestamp'] =
          _toDateTime(sanitized['timestamp']).toIso8601String();
    }
    if (sanitized['createdAt'] != null) {
      sanitized['createdAt'] =
          _toDateTime(sanitized['createdAt']).toIso8601String();
    }
    await Hive.box(entriesBox).put(key, sanitized);
  }

  static List<Map<String, dynamic>> getLocalEntries(String branchId) {
    final box = Hive.box(entriesBox);
    return box.keys
        .where((k) => k.toString().startsWith('$branchId-'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();
  }

  static Map<String, dynamic>? getLocalEntry(
      String branchId, String serial) {
    final val = Hive.box(entriesBox).get('$branchId-$serial');
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static Future<void> updateLocalEntryField(
      String branchId, String serial, Map<String, dynamic> fields) async {
    final key = '$branchId-$serial';
    final box = Hive.box(entriesBox);
    final raw = box.get(key);
    if (raw == null) return;
    final updated = Map<String, dynamic>.from(raw as Map)
      ..addAll(sanitize(fields));
    await box.put(key, updated);
  }

  static Future<bool> deleteLocalEntry(String branchId, String tokenSerial) async {
    try {
      final box = Hive.box(entriesBox);
      if (!box.isOpen) return false;
      final keys = box.keys.toList();
      bool deleted = false;
      for (final key in keys) {
        final entry = box.get(key);
        if (entry == null) continue;
        final serial = entry['serial'] as String?;
        final entryBranch = entry['branchId'] as String?;
        if (serial == tokenSerial && entryBranch == branchId) {
          await box.delete(key);
          debugPrint('[LocalStorage] ✅ Deleted $tokenSerial (key: $key)');
          deleted = true;
          break;
        }
      }
      await box.flush();
      return deleted;
    } catch (e) {
      debugPrint('[LocalStorage] ❌ deleteLocalEntry error: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRESCRIPTIONS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveLocalPrescription(
      Map<String, dynamic> prescription) async {
    final serialRaw =
        prescription['serial']?.toString() ?? prescription['id']?.toString();
    final serial = serialRaw?.trim();
    if (serial == null || serial.isEmpty) return;

    const cnicFields = [
      'patientCnic', 'cnic', 'patientCNIC', 'guardianCnic',
      'patient_cnic', 'guardian_cnic', 'cnic_number'
    ];
    String? cnicRaw;
    for (final field in cnicFields) {
      final v = prescription[field]?.toString();
      if (v != null && v.trim().isNotEmpty && v != '00000-0000000-0') {
        cnicRaw = v;
        break;
      }
    }
    cnicRaw ??= 'unknown_cnic_${DateTime.now().millisecondsSinceEpoch}';

    final cleanCnic = cnicRaw.trim().replaceAll('-', '').replaceAll(' ', '');
    final key       = '${cleanCnic}_$serial';
    var sanitized   = sanitize(prescription);
    sanitized['patientCnic'] = cleanCnic;
    sanitized['cnic']        = cleanCnic;
    sanitized['serial']      = serial;
    await Hive.box(prescriptionsBox).put(key, sanitized);
  }

  static Map<String, dynamic>? getLocalPrescription(String serial) {
    final box         = Hive.box(prescriptionsBox);
    final cleanSerial = serial.trim();
    final direct      = box.get(cleanSerial);
    if (direct != null && direct is Map)
      return Map<String, dynamic>.from(direct);
    for (final key in box.keys) {
      if (key is String && key.endsWith('_$cleanSerial')) {
        final data = box.get(key);
        if (data != null && data is Map)
          return Map<String, dynamic>.from(data);
      }
    }
    for (final key in box.keys) {
      final data = box.get(key);
      if (data != null && data is Map) {
        if (data['serial']?.toString().trim() == cleanSerial) {
          return Map<String, dynamic>.from(data);
        }
      }
    }
    return null;
  }

  static Map<String, dynamic>? getLocalPrescriptionByCnic(String cnic) {
    final box = Hive.box(prescriptionsBox);
    if (!box.isOpen) return null;
    var cleanCnic = cnic.trim().replaceAll('-', '').replaceAll(' ', '');
    cleanCnic = cleanCnic.replaceAll(RegExp(r'^0+'), '');
    for (final value in box.values) {
      final presc = Map<String, dynamic>.from(value as Map);
      final raw   = presc['patientCnic']?.toString() ??
          presc['cnic']?.toString() ?? '';
      var pc = raw.trim().replaceAll('-', '').replaceAll(' ', '');
      pc = pc.replaceAll(RegExp(r'^0+'), '');
      if (pc == cleanCnic || pc.contains(cleanCnic) || cleanCnic.contains(pc))
        return presc;
    }
    return null;
  }

  static List<Map<String, dynamic>> getAllLocalPrescriptions() =>
      Hive.box(prescriptionsBox)
          .values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();

  static List<Map<String, dynamic>> getBranchPrescriptions(String branchId) =>
      getAllLocalPrescriptions()
          .where((p) => p['branchId'] == branchId)
          .toList();

  static Future<void> deleteLocalPrescription(String serial) async {
    final box = Hive.box(prescriptionsBox);
    for (final key in box.keys.toList()) {
      if (key is String && key.contains(serial)) await box.delete(key);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // STOCK
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveAllLocalStockItems(
      List<Map<String, dynamic>> items) async {
    final box = Hive.box(stockBox);
    await box.clear();
    await box.putAll(
        {for (final item in items) 'stock:${item['id']}': item});
  }

  static Future<void> saveLocalStockItem(
      Map<String, dynamic> stockItem) async {
    final id = stockItem['id']?.toString();
    if (id == null) return;
    await Hive.box(stockBox).put('stock:$id', sanitize(stockItem));
  }

  static void saveLocalInventoryItem(Map<String, dynamic> item) {
    final rawId = (item['id'] ?? item['medicineId'])?.toString()?.trim();
    if (rawId == null || rawId.isEmpty) return;
    final normalised = Map<String, dynamic>.from(item);
    normalised['id']         = rawId;
    normalised['medicineId'] = rawId;
    Hive.box(stockBox).put('stock:$rawId', sanitize(normalised));
  }

  static Map<String, dynamic>? getLocalInventoryItem(String id) {
    final val = Hive.box(stockBox).get('stock:$id');
    if (val == null) return null;
    return Map<String, dynamic>.from(val as Map);
  }

  static Future<void> updateLocalStockQuantity(String id, double delta) async {
    final box = Hive.box(stockBox);
    final key = 'stock:$id';
    final raw = box.get(key);
    if (raw == null) return;
    final item = Map<String, dynamic>.from(raw as Map);
    final currentQty = (item['quantity'] ?? 0) as num;
    item['quantity'] = currentQty + delta;
    item['updatedAt'] = DateTime.now().toIso8601String();
    await box.put(key, sanitize(item));
  }

  static Future<void> deleteLocalStockItem(String id) async =>
      Hive.box(stockBox).delete('stock:$id');

  static List<Map<String, dynamic>> getAllLocalStockItems(
      {String? branchId}) {
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

  // ════════════════════════════════════════════════════════════════════════════
  // DISPENSARY
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveLocalDispensaryRecord(
      Map<String, dynamic> record) async {
    final branchId = record['branchId']?.toString() ?? '';
    final serial   = record['serial']?.toString() ?? '';
    final dateKey  = record['dateKey']?.toString() ?? getTodayDateKey();
    if (branchId.isEmpty || serial.isEmpty) return;
    await Hive.box(dispensaryBox)
        .put('${branchId}_${dateKey}_$serial', sanitize(record));
  }

  static Map<String, dynamic>? getLocalDispensaryRecord(
      String branchId, String serial, {String? dateKey}) {
    final dk  = dateKey ?? getTodayDateKey();
    final val = Hive.box(dispensaryBox).get('${branchId}_${dk}_$serial');
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
        .map((k) => Map<String, dynamic>.from(
            Hive.box(dispensaryBox).get(k) as Map))
        .toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BRANCHES
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> saveLocalBranch(Map<String, dynamic> branch) async {
    final id = branch['id']?.toString();
    if (id == null) return;
    await Hive.box(branchesBox).put('branch:$id', sanitize(branch));
  }

  static Future<void> deleteLocalBranch(String id) async =>
      Hive.box(branchesBox).delete('branch:$id');

  // ════════════════════════════════════════════════════════════════════════════
  // FIRESTORE DOWNLOAD HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> downloadAllPatients(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .get();
      final patients = snapshot.docs.map((doc) {
        final d = doc.data();
        d['patientId'] = doc.id;
        d['branchId']  = branchId;
        return d;
      }).toList();
      await saveAllLocalPatients(patients);

      final flagsBox = Hive.box('app_flags');
      for (final doc in snapshot.docs) {
        await flagsBox.put('patient_synced_${doc.id}', true);
      }
    } catch (e) {
      debugPrint('[LocalStorage] downloadAllPatients error: $e');
    }
  }

  static Future<void> downloadTodayTokens(String branchId) async {
    final today = getTodayDateKey();
    final box   = Hive.box(entriesBox);

    try {
      final serialsRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('serials')
          .doc(today);

      final dateDoc = await serialsRef.get();
      if (!dateDoc.exists) {
        final todayKeys = box.keys
            .where((k) {
              final key = k.toString();
              if (!key.startsWith('$branchId-')) return false;
              final parts = key.substring('$branchId-'.length).split('-');
              return parts.isNotEmpty && parts[0] == today;
            })
            .toList();
        for (final k in todayKeys) await box.delete(k);
        await box.flush();
        return;
      }

      final Map<String, Map<String, dynamic>> freshEntries = {};
      for (final type in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await serialsRef.collection(type).get();
        for (final doc in snap.docs) {
          final d = Map<String, dynamic>.from(doc.data());
          d['serial']    = doc.id;
          d['dateKey']   = today;
          d['branchId']  = branchId;
          d['queueType'] = type;
          freshEntries['$branchId-${doc.id}'] = d;
        }
      }

      final todayHiveKeys = box.keys
          .where((k) {
            final key = k.toString();
            if (!key.startsWith('$branchId-')) return false;
            final suffix = key.substring('$branchId-'.length);
            final parts  = suffix.split('-');
            return parts.length >= 2 && parts[0] == today;
          })
          .toList();

      for (final k in todayHiveKeys) {
        if (!freshEntries.containsKey(k.toString())) await box.delete(k);
      }

      const terminalStatuses = ['completed', 'dispensed'];
      for (final entry in freshEntries.entries) {
        final hiveKey  = entry.key;
        final fresh    = entry.value;
        final existing = box.get(hiveKey);
        Map<String, dynamic> merged = sanitize(fresh);
        if (existing is Map) {
          final ex = Map<String, dynamic>.from(existing);
          final localStatus  = ex['status']?.toString() ?? '';
          final mergedStatus = merged['status']?.toString() ?? '';
          if (terminalStatuses.contains(localStatus) &&
              !terminalStatuses.contains(mergedStatus)) merged['status'] = localStatus;
          if (ex['dispenseStatus']?.toString() == 'dispensed') {
            merged['dispenseStatus'] = 'dispensed';
            if (ex['dispensedAt'] != null) merged['dispensedAt'] = ex['dispensedAt'];
            if (ex['dispensedBy'] != null) merged['dispensedBy'] = ex['dispensedBy'];
          }
          if (ex['prescription'] != null && merged['prescription'] == null) {
            merged['prescription']   = ex['prescription'];
            merged['prescriptionId'] = ex['prescriptionId'];
          }
          for (final field in ['dispenserName', 'completedAt']) {
            if (ex[field] != null && merged[field] == null) merged[field] = ex[field];
          }
        }
        await box.put(hiveKey, merged);
      }
      await box.flush();
    } catch (e) {
      debugPrint('[LocalStorage] downloadTodayTokens error: $e');
    }
  }

  static Future<void> downloadInventory(String branchId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('inventory')
          .get();
      final items = snapshot.docs.map((doc) {
        final d = doc.data();
        d['id'] = doc.id;
        d['branchId'] = branchId;
        return d;
      }).toList();
      await saveAllLocalStockItems(items);
    } catch (e) {
      debugPrint('[LocalStorage] downloadInventory error: $e');
    }
  }

  static Future<void> refreshPrescriptions(String branchId) async {
    try {
      final cnicDocs = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('prescriptions')
          .get();
      final prescMap = <String, Map<String, dynamic>>{};
      for (final cnicDoc in cnicDocs.docs) {
        final patientCnic = cnicDoc.id;
        final subSnap     = await cnicDoc.reference
            .collection('prescriptions')
            .get();
        for (final presDoc in subSnap.docs) {
          final d = presDoc.data();
          d['id'] = presDoc.id;
          d['serial']      = presDoc.id;
          d['patientCnic'] = patientCnic;
          d['cnic']        = patientCnic;
          d['branchId']    = branchId;
          prescMap['${patientCnic}_${presDoc.id}'] = sanitize(d);
        }
      }
      await Hive.box(prescriptionsBox).clear();
      await Hive.box(prescriptionsBox).putAll(prescMap);
    } catch (e) {
      debugPrint('[LocalStorage] refreshPrescriptions error: $e');
    }
  }

  // ── Medicine Restrictions (Multi-day tokens) ───────────────────────────────

  static String _cleanId(String id) => id.trim().replaceAll(RegExp(r'[-\s]'), '');

  /// Saves a medicine restriction locally AND enqueues it for Firestore sync.
  /// This ensures the restriction reaches internet-only terminals (not just
  /// LAN-connected ones). The Firestore collection is:
  ///   branches/{branchId}/medicine_restrictions/{cleanPatientId}
  static Future<void> saveMedicineRestriction({
    required String branchId,
    required String patientId,
    required int daysCovered,
  }) async {
    final cleanId = _cleanId(patientId);
    if (cleanId.isEmpty) return;

    final box  = Hive.box(medicineRestrictionsBox);
    final key  = '${branchId}_$cleanId';
    final now  = DateTime.now();

    // Day 1 = today (already issued). Block starts TOMORROW.
    // lastBlockedDay = issuedDate + (daysCovered - 1)
    // e.g. 3-day rx on Mon: lastBlockedDay = Wed. Thu is free.
    final issuedDate     = DateTime(now.year, now.month, now.day);
    final lastBlockedDay = issuedDate.add(Duration(days: daysCovered - 1));

    final record = <String, dynamic>{
      'patientId':      cleanId,
      'branchId':       branchId,
      'issuedAt':       now.toIso8601String(),
      'issuedDateOnly': issuedDate.toIso8601String(),
      'daysCovered':    daysCovered,
      'lastBlockedDay': lastBlockedDay.toIso8601String(),
    };

    await box.put(key, record);
    await box.flush();

    // ── FIRESTORE FIX: enqueue so internet-only terminals get the restriction
    await enqueueSync({
      'type':      'save_medicine_restriction',
      'branchId':  branchId,
      'patientId': cleanId,
      'data':      record,
    });

    debugPrint('[LSS] Restriction saved + enqueued for Firestore sync: $cleanId '
        'blocked until $lastBlockedDay ($daysCovered-day rx)');
  }

  /// Downloads active medicine restrictions from Firestore into local Hive.
  /// Called on startup, after every upload cycle, and by the receptionist
  /// right before the block check so internet-only devices are always current.
  static Future<void> downloadMedicineRestrictions(String branchId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('medicine_restrictions')
          .get();

      final box   = Hive.box(medicineRestrictionsBox);
      final today = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
      
      // ── FIRESTORE FIX: Keep track of IDs downloaded to clear stale ones ──
      final downloadedIds = <String>{};
      int loaded = 0;

      for (final doc in snap.docs) {
        final d              = Map<String, dynamic>.from(doc.data());
        final lastBlockedStr = d['lastBlockedDay'] as String?;

        // Skip already-expired restrictions — no point storing them
        if (lastBlockedStr != null) {
          final lb             = DateTime.parse(lastBlockedStr);
          final lastBlockedDay = DateTime(lb.year, lb.month, lb.day);
          if (today.isAfter(lastBlockedDay)) continue;
        }

        final patientId = doc.id;
        final hiveKey   = '${branchId}_$patientId';
        await box.put(hiveKey, d);
        downloadedIds.add(patientId);
        loaded++;
      }

      // Clear local entries for this branch that weren't in the Firestore set
      // This handles cases where an exception was approved and Firestore was cleared
      final prefix = '${branchId}_';
      final localKeysToClear = box.keys
          .where((k) => k.toString().startsWith(prefix))
          .map((k) => k.toString().replaceFirst(prefix, ''))
          .where((id) => !downloadedIds.contains(id))
          .toList();

      for (final id in localKeysToClear) {
        final key = '$prefix$id';
        await box.delete(key);
        debugPrint('[LSS] Cleared stale restriction (synced delete) for $id');
      }

      await box.flush();
      debugPrint('[LSS] Downloaded $loaded active medicine restrictions for $branchId. '
          'Cleared ${localKeysToClear.length} stale ones.');
    } catch (e) {
      debugPrint('[LSS] downloadMedicineRestrictions error: $e');
    }
  }

  static Map<String, dynamic>? getMedicineRestriction(String branchId, String patientId) {
    if (!Hive.isBoxOpen(medicineRestrictionsBox)) return null;
    final cleanId = _cleanId(patientId);
    final box = Hive.box(medicineRestrictionsBox);
    final key = '${branchId}_$cleanId';
    final data = box.get(key);
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<void> clearMedicineRestriction(String branchId, String patientId) async {
    final cleanId = _cleanId(patientId);
    final box = Hive.box(medicineRestrictionsBox);
    final key = '${branchId}_$cleanId';
    await box.delete(key);
    await box.flush();
    debugPrint('[LocalStorage] 🗑️ Medicine restriction cleared for $cleanId');
  }

  static Map<String, dynamic>? isPatientBlockedByMedicine(
      String branchId, String patientId) {
    final restriction = getMedicineRestriction(branchId, patientId);
    if (restriction == null) return null;

    final today = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);

    // ── NEW field path ──────────────────────────────────────────────
    final lastBlockedStr =
        restriction['lastBlockedDay'] as String?;

    if (lastBlockedStr != null) {
      final lastBlocked = DateTime.parse(lastBlockedStr);
      final lastBlockedDay =
          DateTime(lastBlocked.year, lastBlocked.month, lastBlocked.day);

      if (today.isAfter(lastBlockedDay)) {
        // Restriction expired — auto-clean
        clearMedicineRestriction(branchId, patientId);
        return null;
      }
      final todayOnly = DateTime(today.year, today.month, today.day);
      final diff = lastBlockedDay.difference(todayOnly).inDays;

      return {
        ...restriction,
        'remainingDays': diff,
        'isLastDay': diff == 0,
      };
    }

    // ── LEGACY fallback: old entries stored 'expiresAt' ────────────
    final expiresStr = restriction['expiresAt'] as String?;
    if (expiresStr == null) {
      clearMedicineRestriction(branchId, patientId);
      return null;
    }
    final expiresAt    = DateTime.parse(expiresStr);
    final expireDay    =
        DateTime(expiresAt.year, expiresAt.month, expiresAt.day)
        .subtract(const Duration(days: 1));

    if (today.isAfter(expireDay)) {
      clearMedicineRestriction(branchId, patientId);
      return null;
    }
    final remaining = expireDay.difference(today).inDays + 1;
    return {...restriction, 'remainingDays': remaining};
  }
}