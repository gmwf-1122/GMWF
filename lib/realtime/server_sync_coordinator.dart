// lib/realtime/server_sync_coordinator.dart
import 'package:flutter/foundation.dart';

/// Global mutual-exclusion coordinator between SyncService (cloud upload)
/// and ServerSyncManager (server dashboard batch sync).
///
/// Prevents concurrent Hive box access, conflicting deletions,
/// duplicate Firestore batch commits, and premature quarantine into DeadLetterQueue.
class ServerSyncCoordinator {
  static bool _isServerSyncing = false;
  static bool _isSyncServiceUploading = false;
  static DateTime? _lockAcquiredAt;

  static const Duration _watchdogTimeout = Duration(seconds: 120);

  /// Extends the active lock watchdog during ongoing batch processing to prevent premature lock theft.
  static void touch() {
    if (_lockAcquiredAt != null) {
      _lockAcquiredAt = DateTime.now();
    }
  }

  /// Returns true if either sync pipeline is currently running.
  static bool get isAnySyncActive {
    _checkWatchdog();
    return _isServerSyncing || _isSyncServiceUploading;
  }

  static bool get isServerSyncing {
    _checkWatchdog();
    return _isServerSyncing;
  }

  static bool get isSyncServiceUploading {
    _checkWatchdog();
    return _isSyncServiceUploading;
  }

  static void _checkWatchdog() {
    if (_lockAcquiredAt != null && DateTime.now().difference(_lockAcquiredAt!) > _watchdogTimeout) {
      debugPrint('[ServerSyncCoordinator] ⚠️ Sync lock held > ${_watchdogTimeout.inSeconds}s — auto-clearing hung lock');
      _isServerSyncing = false;
      _isSyncServiceUploading = false;
      _lockAcquiredAt = null;
    }
  }

  /// Determines whether a sync pipeline can start.
  /// If [force] is true, always returns true.
  static bool canStartSync({required bool isServer, bool force = false}) {
    if (force) return true;
    _checkWatchdog();

    if (isServer) {
      // ServerSyncManager: do not start if SyncService is uploading
      return !_isServerSyncing && !_isSyncServiceUploading;
    } else {
      // SyncService: do not start if ServerSyncManager is batch-syncing
      return !_isSyncServiceUploading && !_isServerSyncing;
    }
  }

  /// Marks a sync pass as started.
  static void markStarted({required bool isServer}) {
    if (isServer) {
      _isServerSyncing = true;
    } else {
      _isSyncServiceUploading = true;
    }
    _lockAcquiredAt = DateTime.now();
  }

  /// Marks a sync pass as completed.
  static void markFinished({required bool isServer}) {
    if (isServer) {
      _isServerSyncing = false;
    } else {
      _isSyncServiceUploading = false;
    }
    if (!_isServerSyncing && !_isSyncServiceUploading) {
      _lockAcquiredAt = null;
    }
  }
}
