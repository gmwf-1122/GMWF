// lib/pages/school/utils/school_sync_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/sync_service.dart';
import 'school_local_storage.dart';

enum SchoolSyncState {
  synced,
  syncing,
  offlinePending,
  failed,
}

class SchoolSyncStatus {
  final SchoolSyncState state;
  final int pendingCount;
  final int failedCount;
  final bool isOnline;
  final String? lastSyncedTime;

  const SchoolSyncStatus({
    required this.state,
    required this.pendingCount,
    required this.failedCount,
    required this.isOnline,
    this.lastSyncedTime,
  });
}

class SchoolSyncService {
  static final SchoolSyncService _instance = SchoolSyncService._internal();
  factory SchoolSyncService() => _instance;
  SchoolSyncService._internal();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<BoxEvent>? _syncBoxSub;
  final StreamController<SchoolSyncStatus> _statusController =
      StreamController<SchoolSyncStatus>.broadcast();

  bool _isOnline = true;
  bool _isSyncing = false;
  int _retryCount = 0;
  static const int _maxRetries = 5;

  Stream<SchoolSyncStatus> get statusStream => _statusController.stream;

  void init() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      _updateStatus();
      if (_isOnline) {
        syncNow();
      }
    });

    final syncBox = Hive.isBoxOpen(LocalStorageService.syncBox)
        ? Hive.box(LocalStorageService.syncBox)
        : null;

    if (syncBox != null) {
      _syncBoxSub?.cancel();
      _syncBoxSub = syncBox.watch().listen((_) => _updateStatus());
    }

    _updateStatus();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _syncBoxSub?.cancel();
  }

  int getPendingSchoolQueueCount() {
    if (!Hive.isBoxOpen(LocalStorageService.syncBox)) return 0;
    final box = Hive.box(LocalStorageService.syncBox);
    int count = 0;
    for (final v in box.values) {
      if (v is Map) {
        final collection = (v['collection'] ?? '').toString();
        final type = (v['type'] ?? v['action'] ?? '').toString();
        if (collection.contains('school_') || type.contains('school_')) {
          count++;
        }
      }
    }
    return count;
  }

  int getFailedSchoolRecordsCount(String branchId) {
    int failed = 0;

    void checkList(List<Map<String, dynamic>> items) {
      for (final item in items) {
        if ((item['syncStatus'] ?? '') == 'failed') {
          failed++;
        }
      }
    }

    checkList(SchoolLocalStorage.getAllStudentsCached(branchId));
    checkList(SchoolLocalStorage.getAllTeachersCached(branchId));
    checkList(SchoolLocalStorage.getAllBooksCached(branchId));
    checkList(SchoolLocalStorage.getAllBookLoansCached(branchId));

    return failed;
  }

  void _updateStatus() {
    final pending = getPendingSchoolQueueCount();
    final failed = getFailedSchoolRecordsCount('all');

    SchoolSyncState state;
    if (_isSyncing) {
      state = SchoolSyncState.syncing;
    } else if (failed > 0) {
      state = SchoolSyncState.failed;
    } else if (!_isOnline || pending > 0) {
      state = SchoolSyncState.offlinePending;
    } else {
      state = SchoolSyncState.synced;
    }

    final ts = SchoolLocalStorage.getLastSchoolSyncTimestamp();

    _statusController.add(SchoolSyncStatus(
      state: state,
      pendingCount: pending,
      failedCount: failed,
      isOnline: _isOnline,
      lastSyncedTime: ts,
    ));
  }

  /// Trigger manual sync (Push pending queue & Pull remote records)
  Future<void> syncNow({String branchId = 'all'}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    _updateStatus();

    try {
      // 1. Trigger global SyncService upload
      SyncService().triggerUpload();

      // 2. Fetch and merge latest remote school records for branch
      await fetchRemoteSchoolData(branchId);

      // 3. Mark last synced timestamp
      await SchoolLocalStorage.setLastSchoolSyncTimestamp(
        DateTime.now().toIso8601String(),
      );

      _retryCount = 0;
    } catch (e) {
      debugPrint('[SchoolSyncService] Sync failed: $e');
      _retryCount++;
      
      await SchoolLocalStorage.logAudit(
        branchId: branchId,
        action: 'SYNC_FAILURE',
        user: 'System Sync',
        details: 'School sync failed (Attempt $_retryCount/$_maxRetries): $e',
      );

      if (_retryCount < _maxRetries && _isOnline) {
        final backoffSec = (1 << _retryCount).clamp(2, 30);
        Timer(Duration(seconds: backoffSec), () => syncNow(branchId: branchId));
      }
    } finally {
      _isSyncing = false;
      _updateStatus();
    }
  }

  /// Pull remote school collections from Firestore & resolve conflicts
  Future<void> fetchRemoteSchoolData(String branchId) async {
    final firestore = FirebaseFirestore.instance;

    // Fetch Students
    try {
      final snap = await firestore
          .collection('branches')
          .doc(branchId)
          .collection('school_students')
          .get();

      for (final doc in snap.docs) {
        final remote = doc.data();
        final local = SchoolLocalStorage.getStudentCached(branchId, doc.id);
        
        await _resolveAndSaveRecord(
          branchId: branchId,
          recordId: doc.id,
          remoteData: remote,
          localData: local,
          saveLocal: (data) => SchoolLocalStorage.cacheStudent(branchId, doc.id, data),
          recordType: 'Student',
        );
      }
    } catch (e) {
      debugPrint('[SchoolSyncService] Remote student fetch error: $e');
    }

    // Fetch Teachers
    try {
      final snap = await firestore
          .collection('branches')
          .doc(branchId)
          .collection('school_teachers')
          .get();

      for (final doc in snap.docs) {
        final remote = doc.data();
        final local = SchoolLocalStorage.getTeacherCached(branchId, doc.id);

        await _resolveAndSaveRecord(
          branchId: branchId,
          recordId: doc.id,
          remoteData: remote,
          localData: local,
          saveLocal: (data) => SchoolLocalStorage.cacheTeacher(branchId, doc.id, data),
          recordType: 'Teacher',
        );
      }
    } catch (e) {
      debugPrint('[SchoolSyncService] Remote teacher fetch error: $e');
    }

    // Fetch Books
    try {
      final snap = await firestore
          .collection('branches')
          .doc(branchId)
          .collection('school_books')
          .get();

      for (final doc in snap.docs) {
        final remote = doc.data();
        final local = SchoolLocalStorage.getBookCached(branchId, doc.id);

        await _resolveAndSaveRecord(
          branchId: branchId,
          recordId: doc.id,
          remoteData: remote,
          localData: local,
          saveLocal: (data) => SchoolLocalStorage.cacheBook(branchId, doc.id, data),
          recordType: 'Book',
        );
      }
    } catch (e) {
      debugPrint('[SchoolSyncService] Remote books fetch error: $e');
    }
  }

  /// Conflict Resolution (Last-Write-Wins based on lastModified)
  Future<void> _resolveAndSaveRecord({
    required String branchId,
    required String recordId,
    required Map<String, dynamic> remoteData,
    required Map<String, dynamic>? localData,
    required Future<void> Function(Map<String, dynamic> data) saveLocal,
    required String recordType,
  }) async {
    if (localData == null) {
      // New record from cloud
      remoteData['syncStatus'] = 'synced';
      remoteData['lastSyncedAt'] = DateTime.now().toIso8601String();
      await saveLocal(remoteData);
      return;
    }

    final localModifiedStr = localData['lastModified']?.toString();
    final remoteModifiedStr = remoteData['lastModified']?.toString();

    final localModified = DateTime.tryParse(localModifiedStr ?? '') ?? DateTime(2000);
    final remoteModified = DateTime.tryParse(remoteModifiedStr ?? '') ?? DateTime(2000);

    if (remoteModified.isAfter(localModified)) {
      // Remote write wins -> notify audit log if local had unsynced changes
      if (localData['syncStatus'] == 'pending') {
        await SchoolLocalStorage.logAudit(
          branchId: branchId,
          action: 'SYNC_CONFLICT_WARNING',
          user: 'System Conflict Resolver',
          details: 'Remote overwrite applied for $recordType ID $recordId (Remote: $remoteModifiedStr vs Local: $localModifiedStr)',
        );
      }

      remoteData['syncStatus'] = 'synced';
      remoteData['lastSyncedAt'] = DateTime.now().toIso8601String();
      await saveLocal(remoteData);
    } else {
      // Local write is newer or equal
      if (localData['syncStatus'] != 'synced') {
        localData['syncStatus'] = 'synced';
        localData['lastSyncedAt'] = DateTime.now().toIso8601String();
        await saveLocal(localData);
      }
    }
  }
}
