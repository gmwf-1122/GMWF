// lib/realtime/lan_host_manager.dart
//
// ARCHITECTURE CORRECTION:
//   The receptionist device is NOT a server/host.
//   The dedicated server device runs ServerDashboardWithSync
//   (LanServer + ServerSyncManager). All clients — receptionist,
//   doctor, dispenser — are pure WebSocket clients that connect to it.
//
//   This file satisfies any remaining call sites that referenced the
//   old host-mode pattern. Every method is a safe no-op. Nothing will
//   crash if called. The real connection is handled by:
//     ConnectionManager.start(role: '...', branchId: '...')
//     → LanDiscovery.findServer()
//     → RealtimeManager.initialize(serverIp: ...)
//
// HOW TO MIGRATE CALL SITES:
//   Replace: LanHostManager.startHost(branchId: x)
//   With:    ConnectionManager().start(role: 'receptionist', branchId: x)
//
//   Replace: LanHostManager.stopHost()
//   With:    ConnectionManager().stop()
//
//   Replace: LanHostManager.broadcast(msg)
//   With:    RealtimeManager().sendMessage(payload)
//
//   Replace: LanHostManager.autoDiscoverServer()
//   With:    LanDiscovery.findServer()
//
//   Replace: LanHostManager.identifyLocalClientWithBranch(branch)
//   With:    (no replacement needed — ConnectionManager handles identity)

import 'dart:async';

import 'package:flutter/foundation.dart';

// ── Minimal stub so the old LanClient type reference compiles ─────────────────
//
// Any code that does:
//   LanHostManager.localClient?.isConnected
//   LanHostManager.localClient?.sendMessage(...)
//   LanHostManager.localClient?.onMessage.listen(...)
// ...will get this no-op object and nothing will throw.

class _NoOpLocalClient {
  bool get isConnected => false;

  /// Returns a stream that never emits — safe for any .listen() call.
  Stream<String> get onMessage => const Stream.empty();

  /// No-op send — logs a warning in debug mode.
  void sendMessage(Map<String, dynamic> payload) {
    if (kDebugMode) {
      debugPrint('[LanHostManager] sendMessage() no-op — '
          'receptionist is a CLIENT, not a server. '
          'Use RealtimeManager().sendMessage() instead.');
    }
  }
}

// ── Main class ────────────────────────────────────────────────────────────────

class LanHostManager {
  // Singleton so LanHostManager() always returns the same instance.
  static final LanHostManager _instance = LanHostManager._();
  factory LanHostManager() => _instance;
  LanHostManager._();

  // ── State fields ──────────────────────────────────────────────────────────

  /// Always false — there is no local LAN server on client devices.
  static bool get isHostRunning => false;

  /// Returns a no-op client so .localClient?.isConnected / .sendMessage()
  /// / .onMessage don't throw a null-dereference.
  static _NoOpLocalClient? get localClient => _NoOpLocalClient();

  // Stored so identifyLocalClientWithBranch() doesn't crash if called.
  String? _hostBranchId;

  // ── startHost ─────────────────────────────────────────────────────────────
  //
  // Old callers: await LanHostManager.startHost(branchId: widget.branchId);
  // New callers: await ConnectionManager().start(role: 'receptionist',
  //                                              branchId: widget.branchId);
  static Future<void> startHost({
    bool forceRefreshIp = false,
    String? branchId,
  }) async {
    if (kDebugMode) {
      debugPrint('╔══════════════════════════════════════════════════════════╗');
      debugPrint('║  LanHostManager.startHost() — DEPRECATED / NO-OP        ║');
      debugPrint('║  The receptionist is a CLIENT, not a server.            ║');
      debugPrint('║  Migrate to: ConnectionManager().start(...)             ║');
      debugPrint('╚══════════════════════════════════════════════════════════╝');
    }
    _instance._hostBranchId = branchId?.toLowerCase().trim();
  }

  // ── identifyLocalClientWithBranch ─────────────────────────────────────────
  //
  // In the correct architecture ConnectionManager + RealtimeManager send the
  // 'identify' message automatically after connecting. No action needed here.
  static Future<void> identifyLocalClientWithBranch(String branchId) async {
    _instance._hostBranchId = branchId.toLowerCase().trim();
    if (kDebugMode) {
      debugPrint('[LanHostManager] identifyLocalClientWithBranch() — no-op. '
          'ConnectionManager handles identification automatically.');
    }
  }

  // ── stopHost ──────────────────────────────────────────────────────────────
  //
  // Old callers: await LanHostManager.stopHost();
  // New callers: await ConnectionManager().stop();
  static Future<void> stopHost({bool clearBranchId = true}) async {
    if (clearBranchId) _instance._hostBranchId = null;
    if (kDebugMode) {
      debugPrint('[LanHostManager] stopHost() — no-op. '
          'Migrate to: ConnectionManager().stop()');
    }
  }

  // ── broadcast ─────────────────────────────────────────────────────────────
  //
  // Client devices cannot broadcast — only the server can.
  // Old callers: LanHostManager.broadcast(jsonEncode(msg));
  // New callers: RealtimeManager().sendMessage(payload);
  static void broadcast(String rawMessage) {
    if (kDebugMode) {
      debugPrint('[LanHostManager] broadcast() — no-op. '
          'Clients cannot broadcast directly. '
          'Migrate to: RealtimeManager().sendMessage(payload)');
    }
  }

  // ── autoDiscoverServer ────────────────────────────────────────────────────
  //
  // Always returns null. ConnectionManager uses LanDiscovery internally,
  // so you don't need to call this at all.
  // Old callers: final info = await LanHostManager.autoDiscoverServer();
  // New callers: let ConnectionManager().start() handle it automatically.
  static Future<Map<String, dynamic>?> autoDiscoverServer(
      {int retries = 4}) async {
    if (kDebugMode) {
      debugPrint('[LanHostManager] autoDiscoverServer() — no-op / returns null. '
          'Use LanDiscovery.findServer() or let ConnectionManager handle it.');
    }
    return null;
  }

  // ── Instance-style accessors (for any code using new LanHostManager()) ────
  //
  // The original class was all-static but in case some call site
  // instantiated it, these instance wrappers cover that too.

  bool get isRunning => false;
  String? get hostBranchId => _hostBranchId;

  Future<void> start({String? branchId}) async =>
      startHost(branchId: branchId);

  Future<void> stop({bool clearBranchId = true}) async =>
      stopHost(clearBranchId: clearBranchId);
}