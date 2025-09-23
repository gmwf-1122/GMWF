// lib/services/sync_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_storage_service.dart';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<List<ConnectivityResult>>? _sub; // ✅ old API
  bool _isSyncing = false;

  void start() {
    // ✅ Listen for connectivity changes (old API uses List<ConnectivityResult>)
    _sub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _syncQueued();
      }
    });

    _syncQueued(); // initial sync
  }

  void dispose() => _sub?.cancel();

  Future<void> _syncQueued() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final queue = LocalStorageService.getAllSync();
      for (final entry in queue.entries) {
        final key = entry.key;
        final action = Map<String, dynamic>.from(entry.value);

        try {
          final type = (action['type']?.toString() ?? '').toLowerCase();

          if (type == 'save_user') {
            await _syncSaveUser(action);
          } else if (type == 'delete_user') {
            await _syncDeleteUser(action);
          } else {
            print("⚠️ Unknown sync type: $type");
          }

          await LocalStorageService.removeSyncKey(key);
        } catch (e, st) {
          print("⚠️ Sync failed for key $key: $e\n$st");
        }

        await Future.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncSaveUser(Map<String, dynamic> action) async {
    final uid = action['uid']?.toString();
    final data = Map<String, dynamic>.from(action['data'] ?? {});

    if (uid == null || data.isEmpty) return;

    try {
      // ✅ Save in global users
      await _firestore
          .collection('users')
          .doc(uid)
          .set(data, SetOptions(merge: true));

      // ✅ Save in branch subcollection
      final branchId = data['branchId']?.toString();
      if (branchId != null && branchId.isNotEmpty) {
        await _firestore
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
      // ✅ Delete from global users
      await _firestore.collection('users').doc(uid).delete();

      // ✅ Delete from branch subcollection if known
      if (branchId != null && branchId.isNotEmpty) {
        await _firestore
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
}
