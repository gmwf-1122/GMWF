import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/donations_local_storage.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isUploading = false;
  String? _currentBranchId;
  List<String> _authorizedBranches = [];

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _dailyTokenTimer;
  Timer? _periodicSyncTimer;

  void start(String branchId, {List<String>? authorizedBranches}) {
    _currentBranchId = branchId;
    _authorizedBranches = authorizedBranches ?? [];
    
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        triggerUpload();
      }
    });

    _setupDailyTokenRefresh(branchId);
    
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      triggerUpload();
    });

    triggerUpload();
    print("SyncService started for branch: $branchId");
  }

  void updateAuthorizedBranches(List<String> branchIds) {
    _authorizedBranches = branchIds;
    print("SyncService: Updated authorized branches: $branchIds");
    triggerUpload();
  }

  Future<void> _enqueueMissingDonations(String branchId) async {
    try {
      final donationsBox = Hive.box(DonationsLocalStorage.donationsBox);
      final syncBox      = Hive.box(LocalStorageService.syncBox);
      
      final alreadyQueued = syncBox.values
          .where((v) => v['type'] == 'save_donation')
          .map((v) => v['localId']?.toString())
          .toSet();

      int queued = 0;
      for (final key in donationsBox.keys) {
        final keyStr = key.toString();
        final raw = donationsBox.get(key);
        if (raw == null || raw is! Map) continue;

        final data = Map<String, dynamic>.from(raw);
        if (data['syncStatus'] != 'pending') continue;

        final localId = data['localId']?.toString();
        if (localId == null || localId.isEmpty) continue;
        if (alreadyQueued.contains(localId)) continue;

        await LocalStorageService.enqueueSync({
          'type': 'save_donation',
          'branchId': branchId,
          'localId': localId,
          'hiveKey': keyStr,
          'data': data,
        });
        queued++;
      }
      
      if (queued > 0) {
        print('[SyncService] 📥 Backfill: queued $queued pending donations for upload');
      }
    } catch (e) {
      print('[SyncService] _enqueueMissingDonations error: $e');
    }
  }

  void _setupDailyTokenRefresh(String branchId) {
    final now          = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 5);
    var duration       = nextMidnight.difference(now);
    if (duration.isNegative) duration += const Duration(days: 1);

    _dailyTokenTimer?.cancel();
    _dailyTokenTimer = Timer(duration, () async {
      await LocalStorageService.downloadTodayTokens(branchId);
      _setupDailyTokenRefresh(branchId);
    });
  }

  Future<void> triggerUpload() async {
    if (_currentBranchId == null) return;

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline     = connectivity.any((r) => r != ConnectivityResult.none);

    if (isOnline && !_isUploading) {
      await _uploadPending();

      final remainingQueue = Hive.box(LocalStorageService.syncBox).length;
      if (remainingQueue == 0) {
        try {
          final branchesToSync = <String>{};
          if (_currentBranchId != null) branchesToSync.add(_currentBranchId!);
          if (_authorizedBranches.isNotEmpty) branchesToSync.addAll(_authorizedBranches);

          for (final bId in branchesToSync) {
            await _refreshDataForBranch(bId);
          }
        } catch (e) {
          print("Refresh after upload failed: $e");
        }
      }
    }
  }

  Future<void> _refreshDataForBranch(String branchId) async {
    try {
      await LocalStorageService.downloadTodayTokens(branchId);
      await LocalStorageService.downloadInventory(branchId);
      await LocalStorageService.refreshPrescriptions(branchId);
      await LocalStorageService.downloadMedicineRestrictions(branchId);
      await DonationsLocalStorage.downloadAllDonations(branchId);
      await DonationsLocalStorage.downloadDonors(branchId);
    } catch (e) {
      print("[SyncService] Error refreshing branch $branchId: $e");
    }
  }

  Future<void> _uploadPending() async {
    if (_isUploading || _currentBranchId == null) return;
    _isUploading = true;

    try {
      final queueBox = Hive.box(LocalStorageService.syncBox);
      if (queueBox.isEmpty) return;

      final sortedKeys = queueBox.keys.toList()
        ..sort((a, b) {
          final ta = DateTime.tryParse(queueBox.get(a)?['createdAt'] ?? '2000-01-01T00:00:00Z') ?? DateTime(2000);
          final tb = DateTime.tryParse(queueBox.get(b)?['createdAt'] ?? '2000-01-01T00:00:00Z') ?? DateTime(2000);
          return ta.compareTo(tb);
        });

      for (final key in sortedKeys) {
        final raw = queueBox.get(key);
        if (raw == null || raw is! Map) {
          await queueBox.delete(key);
          continue;
        }

        final action   = Map<String, dynamic>.from(raw);
        final type     = action['type'] as String? ?? 'unknown';
        final attempts = (action['attempts'] as int?) ?? 0;

        if (attempts >= 5) {
          if (type == 'save_donation' || type == 'update_donation' || type == 'delete_donation' || type == 'save_bank_slip') {
            action['attempts'] = 0;
            await queueBox.put(key, action);
            continue;
          } else {
            await queueBox.delete(key);
            continue;
          }
        }

        try {
          final branchId = (action['branchId'] as String?) ?? _currentBranchId!;

          if (type == 'save_patient') {
            final data      = Map<String, dynamic>.from(action['data'] ?? {});
            final patientId = (action['patientId'] ?? data['patientId'])?.toString();
            final bId       = (action['branchId'] ?? data['branchId'] ?? branchId).toString();
            if (patientId == null || patientId.isEmpty) throw Exception('Missing patientId');

            if (data['dob'] is String) {
              try {
                data['dob'] = Timestamp.fromDate(DateTime.parse(data['dob'] as String));
              } catch (_) {}
            }
            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus')..remove('hiveKey');
            await _db.collection('branches').doc(bId).collection('patients').doc(patientId).set(fsData, SetOptions(merge: true));
            await Hive.box('app_flags').put('patient_synced_$patientId', true);
          }
          else if (type == 'save_entry') {
            final data    = Map<String, dynamic>.from(action['data'] ?? {});
            final dateKey = (action['dateKey'] ?? action['datePart'] ?? data['dateKey'])?.toString();
            final serial  = (action['serial'] ?? data['serial'])?.toString();
            if (dateKey == null || serial == null) throw Exception('Missing dateKey/serial');
            final queueType = resolveQueueType((action['queueType'] ?? data['queueType'])?.toString());
            await _db.collection('branches').doc(branchId).collection('serials').doc(dateKey).collection(queueType).doc(serial).set(data, SetOptions(merge: true));
          }
          else if (type == 'save_prescription') {
            final serial = action['serial'] as String?;
            final data   = Map<String, dynamic>.from(action['data'] ?? {});
            if (serial == null) throw Exception('Missing serial');
            final patientCnic = (data['patientCnic'] ?? data['cnic'] ?? data['patientCNIC'] ?? 'unknown_$serial').toString().trim().replaceAll('-', '').replaceAll(' ', '');
            await _db.collection('branches').doc(branchId).collection('prescriptions').doc(patientCnic).collection('prescriptions').doc(serial).set(data, SetOptions(merge: true));
            
            final queueType = resolveQueueType(action['queueType']?.toString() ?? Hive.box(LocalStorageService.entriesBox).get('$branchId-$serial')?['queueType']?.toString());
            final dateKey   = action['dateKey']?.toString() ?? Hive.box(LocalStorageService.entriesBox).get('$branchId-$serial')?['dateKey']?.toString() ?? LocalStorageService.getTodayDateKey();
            await _db.collection('branches').doc(branchId).collection('serials').doc(dateKey).collection(queueType).doc(serial).set({'status': 'completed', 'completedAt': data['completedAt'] ?? DateTime.now().toUtc().toIso8601String()}, SetOptions(merge: true));
          }
          else if (type == 'update_serial_status') {
            final serial = action['serial'] as String?;
            final data   = Map<String, dynamic>.from(action['data'] ?? {});
            if (serial == null) throw Exception('Missing serial');
            final entryKey = '$branchId-$serial';
            final localEntry = Hive.box(LocalStorageService.entriesBox).get(entryKey);
            final queueType = resolveQueueType(action['queueType']?.toString() ?? localEntry?['queueType']?.toString());
            final dateKey   = action['dateKey']?.toString() ?? localEntry?['dateKey']?.toString() ?? LocalStorageService.getTodayDateKey();
            await _db.collection('branches').doc(branchId).collection('serials').doc(dateKey).collection(queueType).doc(serial).set(data, SetOptions(merge: true));
          }
          else if (type == 'save_dispensary_record') {
            final dateKey = action['dateKey'] as String?;
            final serial  = action['serial'] as String?;
            final data    = Map<String, dynamic>.from(action['data'] ?? {});
            if (dateKey == null || serial == null) throw Exception('Missing dateKey/serial');
            final queueType = resolveQueueType((action['queueType'] ?? data['queueType'])?.toString());
            await _db.collection('branches').doc(branchId).collection('dispensary').doc(dateKey).collection(dateKey).doc(serial).set({...data, 'queueType': queueType}, SetOptions(merge: true));
          }
          else if (type == 'save_dispensary_charge') {
            final data    = Map<String, dynamic>.from(action['data'] ?? {});
            final serial  = (action['serial'] ?? data['serial'])?.toString();
            final dateKey = (action['dateKey'] ?? data['dateKey'])?.toString() ?? LocalStorageService.getTodayDateKey();
            if (serial == null || serial.isEmpty) throw Exception('Missing serial');
            final queueType = resolveQueueType((action['queueType'] ?? data['queueType'])?.toString());
            await _db.collection('branches').doc(branchId).collection('dispensary_charges').doc(dateKey).collection('charges').doc(serial).set({...data, 'queueType': queueType}, SetOptions(merge: true));
            await _db.collection('branches').doc(branchId).collection('serials').doc(dateKey).collection(queueType).doc(serial).set({'daysOfMedicine': (data['daysOfMedicine'] as num?)?.toInt() ?? 1}, SetOptions(merge: true));
          }
          else if (type == 'update_inventory') {
            final medicineId = (action['medicineId'] ?? (action['data'] as Map?)?['medicineId'])?.toString().trim();
            final delta = (action['delta'] ?? (action['data'] as Map?)?['delta'] as num?)?.toDouble() ?? 0.0;
            if (medicineId != null && delta != 0) {
              await _db.collection('branches').doc(branchId).collection('inventory').doc(medicineId).update({'quantity': FieldValue.increment(delta)});
            }
          }
          else if (type == 'add_inventory_stock') {
            final medicineId = action['medicineId']?.toString().trim();
            final qty = (action['quantity'] as num?)?.toInt() ?? 0;
            if (medicineId != null && qty > 0) {
              await _db.collection('branches').doc(branchId).collection('inventory').doc(medicineId).update({'quantity': FieldValue.increment(qty)});
              await _db.collection('branches').doc(branchId).collection('inventory_log').add({
                'action': 'add_stock', 'medicineId': medicineId, 'quantityAdded': qty,
                'performedBy': action['performedBy'] ?? '', 'performedByName': action['performedByName'] ?? '',
                'timestamp': FieldValue.serverTimestamp(),
              });
            }
          }
          else if (type == 'register_medicine') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final docId = data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
            final fsData = Map<String, dynamic>.from(data)..remove('id')..remove('syncStatus');
            await _db.collection('branches').doc(branchId).collection('inventory').doc(docId).set(fsData, SetOptions(merge: true));
            await _db.collection('branches').doc(branchId).collection('inventory_log').add({
              'action': 'medicine_registered_directly', 'medicineName': data['name'], 'docId': docId,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
          else if (type == 'save_donation') {
            final data    = Map<String, dynamic>.from(action['data'] ?? {});
            final hiveKey = action['hiveKey'] as String?;
            final stableId = (data['firestoreId'] as String?)?.isNotEmpty == true ? data['firestoreId'] as String : (action['localId']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString());
            final docRef = _db.collection('branches').doc(branchId).collection('donations').doc(stableId);

            final remoteDoc = await docRef.get();
            if (remoteDoc.exists) {
              final remoteUpdate = remoteDoc.data()?['lastUpdatedAt'] as String?;
              final localUpdate  = data['lastUpdatedAt'] as String?;
              if (remoteUpdate != null && localUpdate != null && DateTime.parse(remoteUpdate).isAfter(DateTime.parse(localUpdate))) {
                if (hiveKey != null) await DonationsLocalStorage.markDonationSynced(hiveKey, stableId);
                await queueBox.delete(key);
                continue;
              }
            }
            final fsData = Map<String, dynamic>.from(data)..remove('hiveKey')..remove('syncStatus')..remove('firestoreId');
            await docRef.set(fsData, SetOptions(merge: true));
            if (hiveKey != null) await DonationsLocalStorage.markDonationSynced(hiveKey, docRef.id);
          }
          else if (type == 'save_audit_log') {
            final data      = Map<String, dynamic>.from(action['data'] ?? {});
            final logId     = data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
            final logBranch = action['branchId'] as String? ?? branchId;
            data['branchId'] ??= logBranch;
            final batch = _db.batch();
            batch.set(_db.collection('branches').doc(logBranch).collection('audit_logs').doc(logId), data, SetOptions(merge: true));
            batch.set(_db.collection('global_audit_logs').doc(logId), data, SetOptions(merge: true));
            await batch.commit();
          }
          else if (type == 'save_donor') {
            final data    = Map<String, dynamic>.from(action['data'] ?? {});
            final donorId = action['donorId'] as String?;
            if (donorId == null || data.isEmpty) throw Exception('Missing donorId');
            final docRef = _db.collection('donors').doc(donorId);
            final remoteDoc = await docRef.get();
            if (remoteDoc.exists) {
              final remoteUpdate = remoteDoc.data()?['lastUpdatedAt'] as String?;
              final localUpdate  = data['lastUpdatedAt'] as String?;
              if (remoteUpdate != null && localUpdate != null && DateTime.parse(remoteUpdate).isAfter(DateTime.parse(localUpdate))) {
                await queueBox.delete(key);
                continue;
              }
            }
            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus')..remove('isEdited');
            await docRef.set(fsData, SetOptions(merge: true));
          }
          else if (type == 'save_donor_branch') {
            final data    = Map<String, dynamic>.from(action['data'] ?? {});
            final donorId = action['donorId'] as String?;
            final bId     = (action['branchId'] as String?) ?? branchId;
            if (donorId == null || data.isEmpty) throw Exception('Missing donorId');
            final docRef = _db.collection('branches').doc(bId).collection('donors').doc(donorId);
            final remoteDoc = await docRef.get();
            if (remoteDoc.exists) {
              final remoteUpdate = remoteDoc.data()?['lastUpdatedAt'] as String?;
              final localUpdate  = data['lastUpdatedAt'] as String?;
              if (remoteUpdate != null && localUpdate != null && DateTime.parse(remoteUpdate).isAfter(DateTime.parse(localUpdate))) {
                await queueBox.delete(key);
                continue;
              }
            }
            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus')..remove('isEdited');
            await docRef.set(fsData, SetOptions(merge: true));
          }
          else if (type == 'update_donation') {
            final firestoreId = action['firestoreId'] as String?;
            final fields      = Map<String, dynamic>.from(action['fields'] ?? {});
            if (firestoreId == null) throw Exception('Missing firestoreId');
            final docRef = _db.collection('branches').doc(branchId).collection('donations').doc(firestoreId);
            final remoteDoc = await docRef.get();
            if (remoteDoc.exists) {
              final remoteUpdate = remoteDoc.data()?['lastUpdatedAt'] as String?;
              final localUpdate  = fields['lastUpdatedAt'] as String?;
              if (remoteUpdate != null && localUpdate != null && DateTime.parse(remoteUpdate).isAfter(DateTime.parse(localUpdate))) {
                await queueBox.delete(key);
                continue;
              }
            }
            final fsFields = Map<String, dynamic>.from(fields)..remove('hiveKey')..remove('syncStatus')..remove('firestoreId');
            await docRef.update(fsFields);
          }
          else if (type == 'delete_donation') {
            final firestoreId = action['firestoreId'] as String?;
            if (firestoreId != null) await _db.collection('branches').doc(branchId).collection('donations').doc(firestoreId).delete();
          }
          else if (type == 'delete_donor') {
            final donorId = action['donorId'] as String?;
            if (donorId != null) await _db.collection('donors').doc(donorId).delete();
          }
          else if (type == 'delete_donor_branch') {
            final donorId = action['donorId'] as String?;
            final bId     = action['branchId'] as String?;
            if (donorId != null && bId != null) await _db.collection('branches').doc(bId).collection('donors').doc(donorId).delete();
          }
          else if (type == 'save_bank_slip') {
            final data   = Map<String, dynamic>.from(action['data'] ?? {});
            final slipId = action['slipId'] as String?;
            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            final docRef = _db.collection('branches').doc(branchId).collection('bank_slips').doc(slipId);
            await docRef.set(fsData, SetOptions(merge: true));
            if (slipId != null) await DonationsLocalStorage.markBankSlipSynced(slipId, docRef.id);
          }

          await queueBox.delete(key);
        } catch (e) {
          action['attempts'] = attempts + 1;
          await queueBox.put(key, action);
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (fatal) {
      print("FATAL sync: $fatal");
    } finally {
      _isUploading = false;
    }
  }

  Future<void> syncUnsyncedPatients(String branchId) async {
    await triggerUpload();
  }

  Future<void> syncTodayOnly(String branchId) async {
    await LocalStorageService.downloadTodayTokens(branchId);
    await DonationsLocalStorage.downloadAllDonations(branchId);
  }

  Future<void> initialFullDownload(String branchId) async {
    final settings = Hive.box('app_settings');
    final key      = 'initial_download_done_$branchId';
    if (settings.get(key, defaultValue: false)) {
      await syncTodayOnly(branchId);
      return;
    }
    try {
      final patientsSnap = await _db.collection('branches').doc(branchId).collection('patients').get();
      for (final doc in patientsSnap.docs) {
        final d = doc.data();
        d['patientId'] = doc.id; d['branchId'] = branchId;
        await LocalStorageService.saveLocalPatient(d);
      }
      await LocalStorageService.downloadTodayTokens(branchId);
      await LocalStorageService.downloadInventory(branchId);
      await DonationsLocalStorage.downloadAllDonations(branchId);
      await DonationsLocalStorage.downloadDonors(branchId);
      await settings.put(key, true);
    } catch (e) {
      print('Initial download failed: $e');
    }
  }

  Future<void> forceFullRefresh(String branchId) async {
    final settings = Hive.box('app_settings');
    await settings.delete('initial_download_done_$branchId');
    await initialFullDownload(branchId);
    await triggerUpload();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _dailyTokenTimer?.cancel();
    _periodicSyncTimer?.cancel();
  }

  String resolveQueueType(String? raw) {
    if (raw == null) return 'zakat';
    final r = raw.toLowerCase().trim();
    if (r.contains('non') || r.contains('general')) return 'non-zakat';
    if (r.contains('gmwf')) return 'gmwf';
    return 'zakat';
  }
}