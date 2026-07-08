import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/donations_local_storage.dart';
import 'package:gmwf/pages/madrassa/utils/madrassa_local_storage.dart';
import 'package:gmwf/services/finance_local_storage.dart';
import 'package:gmwf/services/finance_loans_storage.dart';
import 'package:gmwf/services/permission_service.dart';
import 'package:gmwf/services/offline_auth_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isUploading = false;
  String? _currentBranchId;
  List<String> _authorizedBranches = [];
  String? _currentUserRole;

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
    // 30-minute periodic sync — reduced from 15 min to halve quota usage.
    // Finance bulk downloads run separately via triggerFinanceRefresh().
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      triggerUpload();
    });

    triggerUpload();
    Logger().d("SyncService started for branch: $branchId");
  }

  void updateAuthorizedBranches(List<String> branchIds) {
    _authorizedBranches = branchIds;
    Logger().d("SyncService: Updated authorized branches: $branchIds");
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
        Logger().d('[SyncService] 📥 Backfill: queued $queued pending donations for upload');
      }
    } catch (e) {
      Logger().d('[SyncService] _enqueueMissingDonations error: $e');
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

  Future<void> triggerUpload({bool force = false}) async {
    if (_currentBranchId == null) return;

    bool isOnline = true;
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final connectivity = await Connectivity().checkConnectivity();
        isOnline = connectivity.any((r) => r != ConnectivityResult.none);
      }
    } catch (_) {
      isOnline = true;
    }

    if (isOnline && !_isUploading) {
      if (_currentUserRole == null) {
        try {
          final userData = await OfflineAuthService.getCachedUserData();
          if (userData != null) {
            _currentUserRole = userData['role'] as String?;
          }
        } catch (_) {}
      }

      await _uploadPending();

      final remainingQueue = Hive.box(LocalStorageService.syncBox).length;
      if (remainingQueue == 0) {
        try {
          final branchesToSync = <String>{};
          if (_currentBranchId != null) branchesToSync.add(_currentBranchId!);
          if (_authorizedBranches.isNotEmpty) branchesToSync.addAll(_authorizedBranches);

          final settings = Hive.box('app_settings');
          for (final bId in branchesToSync) {
            final lastRefreshStr = settings.get('last_refresh_$bId') as String?;
            final lastRefresh = lastRefreshStr != null ? DateTime.tryParse(lastRefreshStr) : null;
            final now = DateTime.now();
            // Cooldown raised to 30 min to match the periodic timer and avoid
            // back-to-back downloads on rapid connectivity-change events.
            if (force || lastRefresh == null || now.difference(lastRefresh) > const Duration(minutes: 30)) {
              await settings.put('last_refresh_$bId', now.toIso8601String());
              await _refreshDataForBranch(bId);
            } else {
              Logger().d("[SyncService] Skipping automatic refresh for branch $bId (cooldown active)");
            }
          }
        } catch (e) {
          Logger().d("Refresh after upload failed: $e");
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

      final role = _currentUserRole;

      // Only download donations if the user has donations permission
      final hasDonationsPerm = role == null ||
          PermissionService().hasPermission(role, AppPermission.viewDonations) ||
          PermissionService().hasPermission(role, AppPermission.manageDonations);
      if (hasDonationsPerm) {
        await DonationsLocalStorage.downloadAllDonations(branchId);
        await DonationsLocalStorage.downloadDonors(branchId);
      }

      // Only download Madrassa data if the user has madrassa permissions
      final hasMadrassaPerm = role == null ||
          PermissionService().hasPermission(role, AppPermission.manageMadrassa) ||
          PermissionService().hasPermission(role, AppPermission.manageMadrassaAdmin);
      if (hasMadrassaPerm) {
        await MadrassaLocalStorage.downloadStudents(branchId);
        await MadrassaLocalStorage.downloadLogsForMonth(branchId, DateTime.now().year, DateTime.now().month);
        await MadrassaLocalStorage.downloadHolidays(branchId);
      }

      // Finance bulk downloads (heavy collectionGroup scans) are intentionally
      // excluded from the periodic sync cycle. Call triggerFinanceRefresh()
      // explicitly when the Finance page is opened.
    } catch (e) {
      Logger().d("[SyncService] Error refreshing branch $branchId: $e");
    }
  }

  /// Call this when the Finance module is opened by the user.
  /// Respects the same TTL guards as FinanceLocalStorage so it won't hammer
  /// Firestore if the page is opened multiple times within the cooldown window.
  Future<void> triggerFinanceRefresh({bool force = false}) async {
    final branchId = _currentBranchId;
    if (branchId == null) return;

    final role = _currentUserRole;
    final hasFinancePerm = role == null ||
        PermissionService().hasPermission(role, AppPermission.manageFinance);
    if (!hasFinancePerm) return;

    Logger().d('[SyncService] triggerFinanceRefresh for $branchId (force=$force)');
    try {
      await FinanceLocalStorage.downloadEmployees(branchId);
      await FinanceLocalStorage.downloadSalaryHistory(branchId, force: force);
      await FinanceLocalStorage.downloadAttendance(branchId, force: force);
      await FinanceLocalStorage.downloadSalaryLedger(branchId);
      await FinanceLocalStorage.downloadFinanceSettings(branchId);
      await FinanceLocalStorage.downloadTransfers(branchId, force: force);
      await FinanceLocalStorage.downloadAuditLogs(branchId, force: force);
      await FinanceLocalStorage.downloadFinanceHolidays(branchId);
      await FinanceLocalStorage.downloadLoans(branchId);
    } catch (e) {
      Logger().d('[SyncService] triggerFinanceRefresh error: $e');
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
              final docRef = _db.collection('branches').doc(branchId).collection('inventory').doc(medicineId);
              await _db.runTransaction((transaction) async {
                final snapshot = await transaction.get(docRef);
                if (snapshot.exists) {
                  final current = (snapshot.data()?['quantity'] as num?)?.toDouble() ?? 0.0;
                  final updated = (current + delta).clamp(0.0, double.infinity);
                  transaction.update(docRef, {'quantity': updated});
                }
              });
            }
          }
          else if (type == 'add_inventory_stock') {
            final medicineId = action['medicineId']?.toString().trim();
            final qty = (action['quantity'] as num?)?.toInt() ?? 0;
            if (medicineId != null && qty > 0) {
              await _db.collection('branches').doc(branchId).collection('inventory').doc(medicineId).update({'quantity': FieldValue.increment(qty)});
              await _db.collection('branches').doc(branchId).collection('inventory_log').add({
                'action': 'add_stock',
                'medicineId': medicineId,
                'medicineName': action['medicineName'] ?? '',
                'quantityAdded': qty,
                'performedBy': action['performedBy'] ?? '',
                'performedByName': action['performedByName'] ?? '',
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
              'action': 'medicine_registered_directly',
              'medicineName': data['name'],
              'docId': docId,
              'quantityAdded': (data['quantity'] as num?)?.toInt() ?? 0,
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
                if (hiveKey != null) await DonationsLocalStorage.mergeRemoteDonation(hiveKey, stableId, remoteDoc.data() ?? {});
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
                await DonationsLocalStorage.mergeRemoteDonor(donorId, remoteDoc.data() ?? {});
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
                await DonationsLocalStorage.mergeRemoteDonor(donorId, remoteDoc.data() ?? {});
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
                final hiveKey = (action['hiveKey'] as String?) ?? DonationsLocalStorage.getBox().keys.firstWhere(
                  (k) => k.toString().endsWith(firestoreId),
                  orElse: () => '',
                ).toString();
                if (hiveKey.isNotEmpty) {
                  await DonationsLocalStorage.mergeRemoteDonation(hiveKey, firestoreId, remoteDoc.data() ?? {});
                }
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
          else if (type == 'save_employee') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final localId = action['localId']?.toString() ?? data['localId']?.toString();
            final bId = action['branchId']?.toString() ?? data['branchId']?.toString() ?? branchId;
            if (localId == null || localId.isEmpty) throw Exception('Missing localId');

            for (final f in ['dob', 'cnicExpiry', 'joiningDate', 'exitDate']) {
              if (data[f] is String) {
                try {
                  data[f] = Timestamp.fromDate(DateTime.parse(data[f] as String));
                } catch (_) {}
              }
            }
            if (data['createdAt'] is String) {
              try {
                data['createdAt'] = Timestamp.fromDate(DateTime.parse(data['createdAt'] as String));
              } catch (_) {}
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            await _db.collection('branches').doc(bId).collection('employees').doc(localId).set(fsData, SetOptions(merge: true));
            
            final box = Hive.box(LocalStorageService.employeesBox);
            final localRecord = box.get(localId);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = localId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(localId, updated);
            }
          }
          else if (type == 'delete_employee') {
            final localId = action['localId']?.toString();
            final bId = action['branchId']?.toString() ?? branchId;
            if (localId == null || localId.isEmpty) throw Exception('Missing localId');

            await _db.collection('branches').doc(bId).collection('employees').doc(localId).delete();
          }
          else if (type == 'save_salary_history') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final employeeId = action['employeeId']?.toString();
            final historyId = action['historyId']?.toString();
            final bId = action['branchId']?.toString() ?? branchId;
            if (employeeId == null || historyId == null) throw Exception('Missing keys');

            if (data['effectiveDate'] is String) {
              try {
                data['effectiveDate'] = Timestamp.fromDate(DateTime.parse(data['effectiveDate'] as String));
              } catch (_) {}
            }
            if (data['createdAt'] is String) {
              try {
                data['createdAt'] = Timestamp.fromDate(DateTime.parse(data['createdAt'] as String));
              } catch (_) {}
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            await _db.collection('branches').doc(bId).collection('employees').doc(employeeId).collection('salary_history').doc(historyId).set(fsData, SetOptions(merge: true));

            final box = Hive.box(LocalStorageService.salaryHistoryBox);
            final key = '${employeeId}_$historyId';
            final localRecord = box.get(key);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = historyId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(key, updated);
            }
          }
          else if (type == 'save_attendance_record') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final dateStr = action['date']?.toString();
            final employeeId = action['employeeId']?.toString();
            final bId = action['branchId']?.toString() ?? branchId;
            if (dateStr == null || employeeId == null) throw Exception('Missing date/employeeId');

            if (data['markedAt'] is String) {
              try {
                data['markedAt'] = Timestamp.fromDate(DateTime.parse(data['markedAt'] as String));
              } catch (_) {}
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            await _db.collection('branches').doc(bId).collection('employee_attendance').doc(dateStr).collection('records').doc(employeeId).set(fsData, SetOptions(merge: true));

            final box = Hive.box(LocalStorageService.attendanceBox);
            final key = '${employeeId}_$dateStr';
            final localRecord = box.get(key);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = employeeId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(key, updated);
            }
          }
          else if (type == 'save_salary_ledger') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final recordId = action['recordId']?.toString();
            final bId = action['branchId']?.toString() ?? branchId;
            if (recordId == null) throw Exception('Missing recordId');

            for (final f in ['date', 'createdAt', 'voidedAt']) {
              if (data[f] is String) {
                try {
                  data[f] = Timestamp.fromDate(DateTime.parse(data[f] as String));
                } catch (_) {}
              }
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            final employeeDocRef = _db.collection('branches').doc(bId).collection('employees').doc(data['employeeId'] as String);
            final ledgerDocRef = _db.collection('branches').doc(bId).collection('employee_salaries').doc(recordId);

            await _db.runTransaction((transaction) async {
              transaction.set(ledgerDocRef, fsData, SetOptions(merge: true));
              
              final type = data['type']?.toString();
              final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
              final isVoided = data['isVoided'] == true;
              
              double delta = 0.0;
              if (type == 'advance_payment') {
                delta = isVoided ? -amount : amount;
              } else if (type == 'payout') {
                final recovery = (data['advanceDeductions'] as num?)?.toDouble() ?? 0.0;
                delta = isVoided ? recovery : -recovery;
              }

              if (delta != 0) {
                transaction.update(employeeDocRef, {'currentAdvanceBalance': FieldValue.increment(delta)});
              }
            });

            final box = Hive.box(LocalStorageService.salaryLedgerBox);
            final localRecord = box.get(recordId);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = recordId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(recordId, updated);
            }
          }
          else if (type == 'save_finance_settings') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final bId = action['branchId']?.toString() ?? branchId;

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            await _db.collection('branches').doc(bId).collection('settings').doc('workSchedule').set(fsData, SetOptions(merge: true));

            final box = Hive.box(LocalStorageService.financeSettingsBox);
            final localRecord = box.get(bId);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(bId, updated);
            }
          }
          else if (type == 'save_branch_transfer') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final transferId = action['transferId']?.toString();
            final employeeId = action['employeeId']?.toString();
            final fromBranch = action['fromBranchId']?.toString();
            final toBranch = action['toBranchId']?.toString();

            if (transferId == null || employeeId == null || fromBranch == null || toBranch == null) {
              throw Exception('Missing transfer arguments');
            }

            if (data['effectiveDate'] is String) {
              try {
                data['effectiveDate'] = Timestamp.fromDate(DateTime.parse(data['effectiveDate'] as String));
              } catch (_) {}
            }
            if (data['createdAt'] is String) {
              try {
                data['createdAt'] = Timestamp.fromDate(DateTime.parse(data['createdAt'] as String));
              } catch (_) {}
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');

            final fromEmpRef = _db.collection('branches').doc(fromBranch).collection('employees').doc(employeeId);
            final toEmpRef = _db.collection('branches').doc(toBranch).collection('employees').doc(employeeId);
            final transferRef = _db.collection('branches').doc(toBranch).collection('employees').doc(employeeId).collection('branch_transfers').doc(transferId);

            await _db.runTransaction((transaction) async {
              final snapshot = await transaction.get(fromEmpRef);
              if (snapshot.exists) {
                final empData = Map<String, dynamic>.from(snapshot.data() ?? {});
                empData['branchId'] = toBranch;
                
                transaction.set(toEmpRef, empData, SetOptions(merge: true));
                transaction.delete(fromEmpRef);
                transaction.set(transferRef, fsData, SetOptions(merge: true));
              }
            });

            final box = Hive.box(LocalStorageService.branchTransfersBox);
            final localRecord = box.get(transferId);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = transferId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(transferId, updated);
            }
          }
          else if (type == 'save_finance_holiday') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final holidayId = action['holidayId']?.toString();
            final bId = action['branchId']?.toString() ?? branchId;
            if (holidayId == null) throw Exception('Missing holidayId');

            if (data['date'] is String) {
              try {
                data['date'] = Timestamp.fromDate(DateTime.parse(data['date'] as String));
              } catch (_) {}
            }
            if (data['updatedAt'] is String) {
              try {
                data['updatedAt'] = Timestamp.fromDate(DateTime.parse(data['updatedAt'] as String));
              } catch (_) {}
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            await _db.collection('branches').doc(bId).collection('finance_holidays').doc(holidayId).set(fsData, SetOptions(merge: true));

            final box = Hive.box(LocalStorageService.financeHolidaysBox);
            final key = '${bId.toLowerCase().trim()}__hol__$holidayId';
            final localRecord = box.get(key);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = holidayId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(key, updated);
            }
          }
          else if (type == 'delete_finance_holiday') {
            final holidayId = action['holidayId']?.toString();
            final bId = action['branchId']?.toString() ?? branchId;
            if (holidayId == null) throw Exception('Missing holidayId');

            await _db.collection('branches').doc(bId).collection('finance_holidays').doc(holidayId).delete();
          }
          else if (type == 'save_finance_loan') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final loanId = action['loanId']?.toString();
            final bId = action['branchId']?.toString() ?? branchId;
            if (loanId == null) throw Exception('Missing loanId');

            for (final f in ['dateIssued', 'closedAt', 'createdAt', 'updatedAt']) {
              if (data[f] is String) {
                try {
                  data[f] = Timestamp.fromDate(DateTime.parse(data[f] as String));
                } catch (_) {}
              }
            }

            if (data['payments'] is List) {
              final paymentsList = List<dynamic>.from(data['payments'] as List);
              final convertedPayments = <Map<String, dynamic>>[];
              for (final p in paymentsList) {
                if (p is Map) {
                  final pMap = Map<String, dynamic>.from(p);
                  for (final f in ['date', 'createdAt', 'voidedAt']) {
                    if (pMap[f] is String) {
                      try {
                        pMap[f] = Timestamp.fromDate(DateTime.parse(pMap[f] as String));
                      } catch (_) {}
                    }
                  }
                  convertedPayments.add(pMap);
                }
              }
              data['payments'] = convertedPayments;
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            await _db.collection('branches').doc(bId).collection('finance_loans').doc(loanId).set(fsData, SetOptions(merge: true));

            final box = Hive.box(LocalStorageService.financeLoansBox);
            final localRecord = box.get(loanId);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = loanId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(loanId, updated);
            }
          }
          else if (type == 'save_audit_log') {
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            final logId = data['id']?.toString() ?? action['localId']?.toString();
            final bId = action['branchId']?.toString() ?? data['branchContext']?.toString() ?? branchId;
            if (logId == null) throw Exception('Missing logId');

            for (final f in ['timestamp', 'updatedAt']) {
              if (data[f] is String) {
                try {
                  data[f] = Timestamp.fromDate(DateTime.parse(data[f] as String));
                } catch (_) {}
              }
            }

            final fsData = Map<String, dynamic>.from(data)..remove('syncStatus');
            
            // Mirror to branch collection and global_audit_logs collection
            await _db.collection('branches').doc(bId).collection('audit_logs').doc(logId).set(fsData, SetOptions(merge: true));
            await _db.collection('global_audit_logs').doc(logId).set(fsData, SetOptions(merge: true));

            final box = Hive.box(LocalStorageService.auditLogsBox);
            final localRecord = box.get(logId);
            if (localRecord is Map) {
              final updated = Map<String, dynamic>.from(localRecord)
                ..['syncStatus'] = 'synced'
                ..['remoteId'] = logId
                ..['lastSyncedAt'] = DateTime.now().toUtc().toIso8601String();
              await box.put(logId, updated);
            }
          }
          else if (type == 'save_madrassa_log') {
            final dateKey = action['dateKey'] as String?;
            final data = Map<String, dynamic>.from(action['data'] ?? {});
            if (dateKey == null) throw Exception('Missing dateKey');
            await _db.collection('branches').doc(branchId).collection('madrassa_daily_logs').doc(dateKey).set(data, SetOptions(merge: true));
          }
          else if (type == 'update_madrassa_student') {
            final studentId = action['studentId'] as String?;
            final currentLines = action['currentLines'] as int?;
            if (studentId == null || currentLines == null) throw Exception('Missing studentId/currentLines');
            await _db.collection('branches').doc(branchId).collection('madrassa_students').doc(studentId).update({
              'currentLines': currentLines,
              'lastUpdatedAt': FieldValue.serverTimestamp(),
            });
          }

          await queueBox.delete(key);
        } catch (e, stackTrace) {
          action['attempts'] = attempts + 1;
          await queueBox.put(key, action);
          Logger().d("[SyncService] ❌ Upload failed for key: $key (type: $type, attempt: ${attempts + 1}). Error: $e");
          debugPrint(stackTrace.toString());
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (fatal) {
      Logger().d("FATAL sync: $fatal");
    } finally {
      _isUploading = false;
    }
  }

  Future<void> syncUnsyncedPatients(String branchId) async {
    await triggerUpload();
  }

  Future<void> syncTodayOnly(String branchId) async {
    final normBranchId = branchId.toLowerCase().trim();
    await LocalStorageService.downloadTodayTokens(normBranchId);
    await DonationsLocalStorage.downloadAllDonations(normBranchId);
  }

  Future<void> initialFullDownload(String branchId) async {
    final normBranchId = branchId.toLowerCase().trim();
    final settings = Hive.box('app_settings');
    final key      = 'initial_download_done_$normBranchId';
    if (settings.get(key, defaultValue: false)) {
      await syncTodayOnly(normBranchId);
      return;
    }
    try {
      final patientsSnap = await _db.collection('branches').doc(normBranchId).collection('patients').get();
      final List<Map<String, dynamic>> patientsList = [];
      for (final doc in patientsSnap.docs) {
        final d = doc.data();
        d['patientId'] = doc.id;
        d['branchId'] = normBranchId;
        patientsList.add(d);
      }
      await LocalStorageService.saveAllLocalPatients(patientsList);

      await LocalStorageService.downloadTodayTokens(normBranchId);
      await LocalStorageService.downloadInventory(normBranchId);
      await DonationsLocalStorage.downloadAllDonations(normBranchId);
      await DonationsLocalStorage.downloadDonors(normBranchId);
      await FinanceLocalStorage.downloadAllFinanceData(normBranchId);
      await FinanceLoansStorage.migrateLegacyAdvancesToLoans(performedBy: 'System');
      await settings.put(key, true);
    } catch (e) {
      Logger().d('Initial download failed: $e');
    }
  }

  Future<void> forceFullRefresh(String branchId) async {
    final normBranchId = branchId.toLowerCase().trim();
    final settings = Hive.box('app_settings');
    await settings.delete('initial_download_done_$normBranchId');
    await initialFullDownload(normBranchId);
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