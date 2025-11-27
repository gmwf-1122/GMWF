// lib/services/sync_service.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_storage_service.dart';

/// Handles queued offline operations and pushes them to Firestore when online.
/// On Windows builds, syncing is disabled to prevent Firestore plugin crashes.
class SyncService {
  FirebaseFirestore? _firestore; // 🧩 Lazy-loaded instance
  StreamSubscription<dynamic>? _subscription;
  bool _isSyncing = false;

  FirebaseFirestore get firestore {
    _firestore ??= FirebaseFirestore.instance;
    return _firestore!;
  }

  /// Start monitoring connectivity and process queued items when online.
  void start() {
    try {
      // 🔒 Disable sync entirely on Windows to prevent native crash
      if (Platform.isWindows) {
        print(
            "🧩 SyncService disabled on Windows (Firestore not supported safely).");
        return;
      }

      final connectivity = Connectivity();
      final stream = connectivity.onConnectivityChanged;

      _subscription = stream.listen((dynamic result) {
        bool hasConnection = false;

        if (result is ConnectivityResult) {
          hasConnection = result != ConnectivityResult.none;
        } else if (result is List<ConnectivityResult>) {
          hasConnection = result.any((r) => r != ConnectivityResult.none);
        }

        if (hasConnection) {
          _syncQueued();
        }
      }) as StreamSubscription<dynamic>?;

      // Perform initial sync attempt on app start
      _syncQueued();
    } catch (e, st) {
      print("⚠️ SyncService.start() error: $e\n$st");
    }
  }

  /// Stop listening to connectivity changes
  void dispose() => _subscription?.cancel();

  /// Sync queued operations stored in LocalStorageService
  Future<void> _syncQueued() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      if (Platform.isWindows) {
        print("🪟 Skipping sync on Windows release to avoid Firestore crash.");
        return;
      }

      final queue = LocalStorageService.getAllSync();

      for (final entry in queue.entries) {
        final key = entry.key;
        final action = Map<String, dynamic>.from(entry.value);
        final type = (action['type']?.toString() ?? '').toLowerCase();

        try {
          switch (type) {
            case 'save_user':
              await _syncSaveUser(action);
              break;
            case 'delete_user':
              await _syncDeleteUser(action);
              break;
            case 'save_patient':
              await _syncSavePatient(action);
              break;
            case 'delete_patient':
              await _syncDeletePatient(action);
              break;
            default:
              print("⚠️ Unknown sync type: $type");
          }

          await LocalStorageService.removeSyncKey(key);
        } catch (e, st) {
          print("⚠️ Sync failed for key $key: $e\n$st");
        }

        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e, st) {
      print("⚠️ SyncService._syncQueued() crashed: $e\n$st");
    } finally {
      _isSyncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 User Sync Methods
  // ---------------------------------------------------------------------------

  Future<void> _syncSaveUser(Map<String, dynamic> action) async {
    final uid = action['uid']?.toString();
    final data = Map<String, dynamic>.from(action['data'] ?? {});
    if (uid == null || data.isEmpty) return;

    try {
      await firestore
          .collection('users')
          .doc(uid)
          .set(data, SetOptions(merge: true));

      final branchId = data['branchId']?.toString();
      if (branchId != null && branchId.isNotEmpty) {
        await firestore
            .collection('branches')
            .doc(branchId)
            .collection('users')
            .doc(uid)
            .set(data, SetOptions(merge: true));
      }

      print("✅ Synced user $uid");
    } catch (e, st) {
      print("⚠️ Failed to sync user $uid: $e\n$st");
      await LocalStorageService.enqueueSync({
        'type': 'save_user',
        'uid': uid,
        'data': data,
      });
    }
  }

  Future<void> _syncDeleteUser(Map<String, dynamic> action) async {
    final uid = action['uid']?.toString();
    final branchId = action['branchId']?.toString();
    if (uid == null) return;

    try {
      await firestore.collection('users').doc(uid).delete();

      if (branchId != null && branchId.isNotEmpty) {
        await firestore
            .collection('branches')
            .doc(branchId)
            .collection('users')
            .doc(uid)
            .delete();
      }

      print("🗑️ Deleted user $uid");
    } catch (e, st) {
      print("⚠️ Failed to delete user $uid: $e\n$st");
      await LocalStorageService.enqueueSync({
        'type': 'delete_user',
        'uid': uid,
        'branchId': branchId,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 🔹 Patient Sync Methods
  // ---------------------------------------------------------------------------

  Future<void> _syncSavePatient(Map<String, dynamic> action) async {
    final cnic = action['cnic']?.toString();
    final branchId = action['branchId']?.toString();
    final data = Map<String, dynamic>.from(action['data'] ?? {});
    if (cnic == null || branchId == null || data.isEmpty) return;

    try {
      final branchRef = firestore.collection('branches').doc(branchId);
      final patientRef = branchRef.collection('patients').doc(cnic);

      await patientRef.set(data, SetOptions(merge: true));
      await firestore
          .collection('patients')
          .doc(cnic)
          .set(data, SetOptions(merge: true));

      print("✅ Synced patient $cnic");
    } catch (e, st) {
      print("⚠️ Failed to sync patient $cnic: $e\n$st");
      await LocalStorageService.enqueueSync({
        'type': 'save_patient',
        'cnic': cnic,
        'branchId': branchId,
        'data': data,
      });
    }
  }

  Future<void> _syncDeletePatient(Map<String, dynamic> action) async {
    final cnic = action['cnic']?.toString();
    final branchId = action['branchId']?.toString();
    if (cnic == null || branchId == null) return;

    try {
      final branchRef = firestore.collection('branches').doc(branchId);
      await branchRef.collection('patients').doc(cnic).delete();
      await firestore.collection('patients').doc(cnic).delete();

      print("🗑️ Deleted patient $cnic");
    } catch (e, st) {
      print("⚠️ Failed to delete patient $cnic: $e\n$st");
      await LocalStorageService.enqueueSync({
        'type': 'delete_patient',
        'cnic': cnic,
        'branchId': branchId,
      });
    }
  }
}
