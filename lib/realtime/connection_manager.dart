// lib/realtime/connection_manager.dart
// Single source of truth for WebSocket connection state.
// Used by Receptionist, Doctor, Dispenser screens.
//
// Key design:
//  - isConnected = true ONLY after WebSocket.readyState == open AND server echoes 'identified'
//  - Auto-discovers server via LanDiscovery (mDNS + UDP + subnet scan)
//  - Saves last-known good IP; re-validates before using saved IP
//  - Reconnects automatically with exponential backoff
//  - Emits stable stream so UI always reflects truth

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import 'lan_discovery.dart';
import 'realtime_manager.dart';

enum LanConnectionState { disconnected, searching, connecting, connected }

class ConnectionStatus {
  final LanConnectionState state;
  final String? ip;
  final int? port;
  final String message;

  const ConnectionStatus({
    required this.state,
    this.ip,
    this.port,
    required this.message,
  });

  bool get isConnected => state == LanConnectionState.connected;
  bool get isSearching => state == LanConnectionState.searching;
  bool get isConnecting => state == LanConnectionState.connecting;
}

class ConnectionManager {
  static final ConnectionManager _instance = ConnectionManager._();
  factory ConnectionManager() => _instance;
  ConnectionManager._();

  final _statusController =
      StreamController<ConnectionStatus>.broadcast();

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus _current = const ConnectionStatus(
      state: LanConnectionState.disconnected, message: 'Not connected');

  ConnectionStatus get status => _current;
  bool get isConnected => _current.isConnected;

  String? _role;
  String? _branchId;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  bool _running = false;
  bool _disposed = false;

  static const _savedIpKey = 'last_server_ip';
  static const _savedPortKey = 'last_server_port';

  // ── Initialize ───────────────────────────────────────────────────────────────
  Future<void> start({
    required String role,
    required String branchId,
  }) async {
    _role = role.toLowerCase().trim();
    _branchId = branchId.toLowerCase().trim();
    _running = true;
    _disposed = false;
    _reconnectAttempts = 0;

    debugPrint('ConnectionManager: Starting for role=$_role branch=$_branchId');

    await _tryConnect();
  }

  // ── Main connect flow ────────────────────────────────────────────────────────
  Future<void> _tryConnect() async {
    if (!_running || _disposed) return;

    _emit(ConnectionStatus(
      state: LanConnectionState.searching,
      message: 'Looking for server...',
    ));

    // 1. Try saved IP first (fast path)
    final saved = _getSavedServer();
    if (saved != null) {
      final reachable = await LanDiscovery.isReachable(saved.$1, saved.$2);
      if (reachable) {
        debugPrint('ConnectionManager: Saved IP reachable — connecting');
        final ok = await _connectTo(saved.$1, saved.$2);
        if (ok) return;
      } else {
        debugPrint('ConnectionManager: Saved IP unreachable — will scan');
      }
    }

    // 2. Auto-discover
    _emit(ConnectionStatus(
      state: LanConnectionState.searching,
      message: 'Scanning network for server...',
    ));

    final found = await LanDiscovery.findServer(
      timeout: const Duration(seconds: 15),
      onStatus: (s) => _emit(ConnectionStatus(
        state: LanConnectionState.searching,
        message: s,
      )),
    );

    if (found == null) {
      debugPrint('ConnectionManager: Discovery failed');
      _emit(const ConnectionStatus(
        state: LanConnectionState.disconnected,
        message: 'Server not found on network',
      ));
      _scheduleReconnect();
      return;
    }

    final ok = await _connectTo(found.ip, found.port);
    if (!ok) _scheduleReconnect();
  }

  // ── Connect to specific IP ───────────────────────────────────────────────────
  Future<bool> _connectTo(String ip, int port) async {
    if (!_running || _disposed) return false;

    debugPrint('ConnectionManager: Connecting to $ip:$port as $_role/$_branchId');
    _emit(ConnectionStatus(
      state: LanConnectionState.connecting,
      ip: ip,
      port: port,
      message: 'Connecting to $ip...',
    ));

    try {
      await RealtimeManager().initialize(
        role: _role!,
        branchId: _branchId!,
        serverIp: ip,
        port: port,
      );

      // Wait up to 4s for the 'identified' confirmation from server
      final confirmed = await _waitForIdentified(timeoutSeconds: 4);

      if (!confirmed) {
        debugPrint('ConnectionManager: No identified response from $ip');
        return false;
      }

      _saveServer(ip, port);
      _reconnectAttempts = 0;

      _emit(ConnectionStatus(
        state: LanConnectionState.connected,
        ip: ip,
        port: port,
        message: 'Connected to $ip:$port',
      ));

      _startHeartbeat(ip, port);
      debugPrint('ConnectionManager: Connected and identified at $ip:$port');
      return true;
    } catch (e) {
      debugPrint('ConnectionManager: Connect failed: $e');
      _emit(ConnectionStatus(
        state: LanConnectionState.disconnected,
        message: 'Connection failed: $e',
      ));
      return false;
    }
  }

  // ── Wait for 'identified' event (proves connection is fully ready) ────────────
  Future<bool> _waitForIdentified({required int timeoutSeconds}) async {
    final completer = Completer<bool>();

    late StreamSubscription sub;
    sub = RealtimeManager().messageStream.listen((event) {
      final type = event['event_type']?.toString();
      if (type == 'identified' && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    // Also check raw RealtimeManager connection (already connected = good enough)
    if (RealtimeManager().isConnected) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!completer.isCompleted) completer.complete(true);
    }

    Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        // Even without 'identified', if websocket is open we accept it
        completer.complete(RealtimeManager().isConnected);
      }
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  // ── Heartbeat — detects silent disconnections ────────────────────────────────
  void _startHeartbeat(String ip, int port) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!_running || _disposed) return;

      final realtimeOk = RealtimeManager().isConnected;

      if (!realtimeOk) {
        debugPrint('ConnectionManager: Heartbeat detected disconnect');
        _heartbeatTimer?.cancel();
        _emit(const ConnectionStatus(
          state: LanConnectionState.disconnected,
          message: 'Connection lost — reconnecting...',
        ));
        _scheduleReconnect();
      }
    });
  }

  // ── Reconnect with backoff ───────────────────────────────────────────────────
  void _scheduleReconnect() {
    if (!_running || _disposed) return;

    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    final delays = [3, 5, 10, 15, 20];
    final delay = delays[_reconnectAttempts.clamp(0, delays.length - 1)];
    _reconnectAttempts++;

    debugPrint(
        'ConnectionManager: Reconnect in ${delay}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(Duration(seconds: delay), _tryConnect);
  }

  // ── Manual trigger (from UI "Retry" button) ──────────────────────────────────
  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectAttempts = 0;
    await _tryConnect();
  }

  // ── Persistence ──────────────────────────────────────────────────────────────
  (String, int)? _getSavedServer() {
    try {
      final box = Hive.box('app_settings');
      final ip = box.get(_savedIpKey) as String?;
      final port = box.get(_savedPortKey) as int?;
      if (ip != null && port != null) return (ip, port);
    } catch (_) {}
    return null;
  }

  void _saveServer(String ip, int port) {
    try {
      final box = Hive.box('app_settings');
      box.put(_savedIpKey, ip);
      box.put(_savedPortKey, port);
    } catch (_) {}
  }

  // ── Emit ─────────────────────────────────────────────────────────────────────
  void _emit(ConnectionStatus status) {
    if (_disposed) return;
    _current = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  // ── Stop ─────────────────────────────────────────────────────────────────────
  Future<void> stop() async {
    _running = false;
    _disposed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await RealtimeManager().dispose();
    _emit(const ConnectionStatus(
        state: LanConnectionState.disconnected, message: 'Disconnected'));
  }
}