import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'local_storage_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _dailyTokenTimer;
  Timer? _periodicSyncTimer;
  bool _isUploading = false;
  String? _currentBranchId;

  void start(String branchId) {
    print("SyncService started for branch: $branchId");
    _currentBranchId = branchId;

    LocalStorageService.forceDeduplicatePatients();

    triggerUpload();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      print("Connectivity changed → online: $isOnline");
      if (isOnline) {
        triggerUpload();
      }
    });

    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      print("Periodic sync timer fired (every 60s)");
      triggerUpload();
    });

    _setupDailyTokenRefresh(branchId);
  }

  void _setupDailyTokenRefresh(String branchId) {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 5);
    var duration = nextMidnight.difference(now);

    if (duration.isNegative) {
      duration += const Duration(days: 1);
    }

    _dailyTokenTimer?.cancel();
    _dailyTokenTimer = Timer(duration, () async {
      print("Daily token refresh timer fired");
      await LocalStorageService.downloadTodayTokens(branchId);
      _setupDailyTokenRefresh(branchId);
    });
  }

  Future<void> triggerUpload() async {
    if (_currentBranchId == null) {
      print("triggerUpload SKIPPED → no currentBranchId set");
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity.any((r) => r != ConnectivityResult.none);

    print("triggerUpload() called | branch: $_currentBranchId | online: $isOnline | _isUploading: $_isUploading | queue size: ${Hive.box(LocalStorageService.syncBox).length}");

    if (isOnline && !_isUploading) {
      print("→ starting _uploadPending()");
      await _uploadPending();

      try {
        print("Post-upload refresh started...");
        await LocalStorageService.downloadTodayTokens(_currentBranchId!);
        await LocalStorageService.downloadInventory(_currentBranchId!);
        await LocalStorageService.refreshPrescriptions(_currentBranchId!);
        print("Post-sync refresh completed (tokens + inventory + prescriptions)");
      } catch (e) {
        print("Refresh after upload failed: $e");
      }
    } else {
      print("triggerUpload SKIPPED → ${!isOnline ? 'offline' : 'already uploading'}");
    }
  }

  Future<void> _uploadPending() async {
    if (_isUploading || _currentBranchId == null) {
      print("_uploadPending SKIPPED → already uploading or no branchId");
      return;
    }

    _isUploading = true;
    print("=== Starting sync loop ===");

    try {
      final queueBox = Hive.box(LocalStorageService.syncBox);
      if (queueBox.isEmpty) {
        print("Sync queue empty - nothing to upload");
        return;
      }

      print("Processing ${queueBox.length} queued items");

      final sortedKeys = queueBox.keys.toList()
        ..sort((a, b) {
          final ta = DateTime.tryParse(queueBox.get(a)?['createdAt'] ?? '2000-01-01T00:00:00Z') ?? DateTime(2000);
          final tb = DateTime.tryParse(queueBox.get(b)?['createdAt'] ?? '2000-01-01T00:00:00Z') ?? DateTime(2000);
          return ta.compareTo(tb);
        });

      for (final key in sortedKeys) {
        final raw = queueBox.get(key);
        if (raw == null || raw is! Map) {
          print("Invalid queue item $key → deleting");
          await queueBox.delete(key);
          continue;
        }

        final action = Map<String, dynamic>.from(raw);
        final type = action['type'] as String? ?? 'unknown';
        final attempts = (action['attempts'] as int?) ?? 0;

        print("Processing $key | type: $type | attempts: $attempts");

        if (attempts >= 5) {
          print("Giving up on $key ($type) after $attempts attempts → deleting");
          await queueBox.delete(key);
          continue;
        }

        try {
          final branchId = (action['branchId'] as String?) ?? _currentBranchId!;

          if (type == 'save_entry') {
            final dateKey = action['dateKey'] as String?;
            final queueType = action['queueType'] as String?;
            final serial = action['serial'] as String?;
            final data = Map<String, dynamic>.from(action['data'] ?? {});

            if (dateKey == null || queueType == null || serial == null) {
              throw Exception('Missing dateKey, queueType, or serial in save_entry');
            }

            print("Uploading token: $serial ($dateKey/$queueType)");

            await _db
                .collection('branches')
                .doc(branchId)
                .collection('serials')
                .doc(dateKey)
                .collection(queueType)
                .doc(serial)
                .set(data, SetOptions(merge: true));

            final serialNumber = int.tryParse(serial.split('-').last);
            if (serialNumber != null) {
              await _db
                  .collection('branches')
                  .doc(branchId)
                  .collection('serials')
                  .doc(dateKey)
                  .set({'lastSerialNumber': serialNumber}, SetOptions(merge: true));
            }

            print("SUCCESS: Uploaded token → $serial ($dateKey/$queueType)");
          }
          
          else if (type == 'save_prescription') {
            final serial = action['serial'] as String?;
            final data = Map<String, dynamic>.from(action['data'] ?? {});

            if (serial == null) {
              throw Exception('Missing serial in save_prescription');
            }

            String? patientCnic = data['patientCnic']?.toString() ??
                                 data['cnic']?.toString() ??
                                 data['patientCNIC']?.toString();

            if (patientCnic == null || patientCnic.trim().isEmpty) {
              print("WARNING: No CNIC in prescription data - using fallback");
              patientCnic = 'unknown_$serial';
            }

            final cleanCnic = patientCnic.trim().replaceAll('-', '').replaceAll(' ', '');

            print("Uploading prescription: serial=$serial, cnic=$cleanCnic");

            await _db
                .collection('branches')
                .doc(branchId)
                .collection('prescriptions')
                .doc(cleanCnic)
                .collection('prescriptions')
                .doc(serial)
                .set(data, SetOptions(merge: true));

            print("SUCCESS: Uploaded prescription → $serial (CNIC: $cleanCnic)");
          }
          
          else if (type == 'update_serial_status') {
            final serial = action['serial'] as String?;
            final data = Map<String, dynamic>.from(action['data'] ?? {});

            if (serial == null) throw Exception('Missing serial in update_serial_status');

            final entryKey = '$branchId-$serial';
            final localEntry = Hive.box(LocalStorageService.entriesBox).get(entryKey);
            final dateKey = localEntry?['dateKey'] ?? LocalStorageService.getTodayDateKey();
            final queueType = localEntry?['queueType'] ?? 'zakat';

            print("Updating serial status: $serial ($dateKey/$queueType)");

            await _db
                .collection('branches')
                .doc(branchId)
                .collection('serials')
                .doc(dateKey)
                .collection(queueType)
                .doc(serial)
                .update(data);

            print("SUCCESS: Updated serial status → $serial ($dateKey/$queueType)");
          } 
          
          else if (type == 'save_dispensary_record') {
            final dateKey = action['dateKey'] as String?;
            final serial = action['serial'] as String?;
            final data = Map<String, dynamic>.from(action['data'] ?? {});

            if (dateKey == null || serial == null) {
              throw Exception('Missing dateKey or serial in save_dispensary_record');
            }

            print("Uploading dispensary record: $serial ($dateKey)");

            await _db
                .collection('branches')
                .doc(branchId)
                .collection('dispensary_records')
                .doc('$dateKey-$serial')
                .set(data, SetOptions(merge: true));

            print("SUCCESS: Uploaded dispensary record → $serial ($dateKey)");
          } 
          
          else {
            print("Unknown sync type '$type' → skipping");
          }

          await queueBox.delete(key);
          print("✅ Sync item $key completed and removed from queue");
          
        } catch (e, stack) {
          print('UPLOAD FAILED for $type (key: $key)');
          print('attempt ${attempts + 1}/5');
          print('error: $e');

          action['attempts'] = attempts + 1;
          action['lastAttempt'] = DateTime.now().toUtc().toIso8601String();
          action['lastError'] = e.toString().substring(0, e.toString().length.clamp(0, 400));

          await queueBox.put(key, action);

          await Future.delayed(Duration(seconds: 2 * (attempts + 1)));
        }

        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (fatal) {
      print("FATAL sync loop error: $fatal");
    } finally {
      _isUploading = false;
      print("=== Sync loop finished | Remaining in queue: ${Hive.box(LocalStorageService.syncBox).length} ===");
    }
  }

  Future<void> syncTodayOnly(String branchId) async {
    await LocalStorageService.downloadTodayTokens(branchId);
    await LocalStorageService.refreshPrescriptions(branchId);
    print('Today-only sync completed for branch $branchId (tokens + prescriptions refreshed)');
  }

  Future<void> initialFullDownload(String branchId) async {
    final settings = Hive.box('app_settings');
    final key = 'initial_download_done_$branchId';

    if (settings.get(key, defaultValue: false)) {
      await LocalStorageService.downloadTodayTokens(branchId);
      await LocalStorageService.refreshPrescriptions(branchId);
      return;
    }

    try {
      print('Starting initial full download for branch: $branchId');

      final patientsSnap = await _db
          .collection('branches')
          .doc(branchId)
          .collection('patients')
          .get();

      for (final doc in patientsSnap.docs) {
        await LocalStorageService.saveLocalPatient(doc.data());
      }
      print('Downloaded ${patientsSnap.docs.length} patients');

      await LocalStorageService.downloadTodayTokens(branchId);
      print('Downloaded today tokens only');

      print("Downloading ALL historical prescriptions...");
      int totalPrescriptions = 0;

      final cnicDocsSnap = await _db
          .collection('branches')
          .doc(branchId)
          .collection('prescriptions')
          .get();

      print("Found ${cnicDocsSnap.docs.length} CNIC/patientId documents under prescriptions");

      for (final cnicDoc in cnicDocsSnap.docs) {
        final cnicOrPatientId = cnicDoc.id;

        final presSnap = await _db
            .collection('branches')
            .doc(branchId)
            .collection('prescriptions')
            .doc(cnicOrPatientId)
            .collection('prescriptions')
            .get();

        for (final presDoc in presSnap.docs) {
          final data = presDoc.data();
          data['id'] = presDoc.id;
          data['patientCnic'] = cnicOrPatientId;
          await LocalStorageService.saveLocalPrescription(data);
          totalPrescriptions++;
        }

        print('Downloaded ${presSnap.docs.length} prescriptions for CNIC/patientId: $cnicOrPatientId');
      }

      print('Total prescriptions downloaded: $totalPrescriptions');

      await LocalStorageService.downloadInventory(branchId);

      await settings.put(key, true);
      print('Initial full download completed for branch $branchId');
    } catch (e, stack) {
      print('Initial download failed: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> downloadAllHistoricalTokens(String branchId) async {
    try {
      final entriesSnap = await _db
          .collection('branches')
          .doc(branchId)
          .collection('serials')
          .get();

      for (final dateDoc in entriesSnap.docs) {
        final dateKey = dateDoc.id;
        for (final queueType in ['zakat', 'non-zakat', 'gmwf']) {
          final queueSnap = await _db
              .collection('branches')
              .doc(branchId)
              .collection('serials')
              .doc(dateKey)
              .collection(queueType)
              .get();

          for (final entryDoc in queueSnap.docs) {
            final data = entryDoc.data();
            data['queueType'] = queueType;
            data['dateKey'] = dateKey;
            await LocalStorageService.saveEntryLocal(branchId, entryDoc.id, data);
          }
        }
      }
      print('Downloaded all historical tokens for branch $branchId');
    } catch (e) {
      print('Error downloading historical tokens: $e');
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
    print("SyncService disposed");
  }
}