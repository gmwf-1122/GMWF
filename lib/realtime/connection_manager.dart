// lib/realtime/connection_manager.dart
//
// CHANGES IN THIS VERSION:
//   1. start() now accepts optional 'username' parameter.
//   2. Passes username down to RealtimeManager.initialize().
//   All other logic unchanged.

import 'dart:async';

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

  bool get isConnected  => state == LanConnectionState.connected;
  bool get isSearching  => state == LanConnectionState.searching;
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
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );
  ConnectionStatus get status      => _current;
  bool             get isConnected => _current.isConnected;

  String? _role;
  String? _branchId;
  String? _username;   // ← stored so reconnects re-use it

  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int    _reconnectAttempts = 0;
  bool   _running  = false;
  bool   _disposed = false;

  static const _savedIpKey   = 'last_server_ip';
  static const _savedPortKey = 'last_server_port';

  // ── Start ──────────────────────────────────────────────────────────────────
  Future<void> start({
    required String role,
    required String branchId,
    String? username,         // ← NEW: display name sent to server
  }) async {
    _role     = role.toLowerCase().trim();
    _branchId = branchId.toLowerCase().trim();
    _username = username?.trim();
    _running  = true;
    _disposed = false;
    _reconnectAttempts = 0;

    debugPrint('[ConnectionManager] Starting: '
        'role=$_role branch=$_branchId username=$_username');
    await _tryConnect();
  }

  // ── Discovery + connect loop ───────────────────────────────────────────────
  Future<void> _tryConnect() async {
    if (!_running || _disposed) return;

    _emit(const ConnectionStatus(
      state: LanConnectionState.searching,
      message: 'Looking for server...',
    ));

    // 1. Try last-known-good IP first.
    final saved = _getSavedServer();
    if (saved != null) {
      final reachable = await LanDiscovery.isReachable(saved.$1, saved.$2);
      if (reachable) {
        debugPrint('[ConnectionManager] Saved IP reachable → connecting');
        final ok = await _connectTo(saved.$1, saved.$2);
        if (ok) return;
      } else {
        debugPrint('[ConnectionManager] Saved IP unreachable → scanning');
      }
    }

    // 2. Auto-discover.
    _emit(const ConnectionStatus(
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
      debugPrint('[ConnectionManager] Discovery failed');
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

  // ── Connect to specific IP ─────────────────────────────────────────────────
  Future<bool> _connectTo(String ip, int port) async {
    if (!_running || _disposed) return false;

    debugPrint('[ConnectionManager] Connecting to $ip:$port '
        'as $_role/$_branchId (username: $_username)');

    _emit(ConnectionStatus(
      state: LanConnectionState.connecting,
      ip: ip,
      port: port,
      message: 'Connecting to $ip...',
    ));

    try {
      await RealtimeManager().initialize(
        role:     _role!,
        branchId: _branchId!,
        serverIp: ip,
        port:     port,
        username: _username,    // ← pass username down
      );

      final confirmed = await _waitForIdentified(timeoutSeconds: 4);

      if (!confirmed) {
        debugPrint('[ConnectionManager] No identified response from $ip');
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
      debugPrint('[ConnectionManager] Connected & identified at $ip:$port');
      return true;
    } catch (e) {
      debugPrint('[ConnectionManager] Connect failed: $e');
      _emit(ConnectionStatus(
        state: LanConnectionState.disconnected,
        message: 'Connection failed: $e',
      ));
      return false;
    }
  }

  // ── Wait for 'identified' ──────────────────────────────────────────────────
  Future<bool> _waitForIdentified({required int timeoutSeconds}) async {
    final completer = Completer<bool>();

    late StreamSubscription sub;
    sub = RealtimeManager().messageStream.listen((event) {
      if (event['event_type'] == 'identified' && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    if (RealtimeManager().isConnected) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!completer.isCompleted) completer.complete(true);
    }

    Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        completer.complete(RealtimeManager().isConnected);
      }
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────
  void _startHeartbeat(String ip, int port) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!_running || _disposed) return;

      if (!RealtimeManager().isConnected) {
        debugPrint('[ConnectionManager] Heartbeat: disconnect detected');
        _heartbeatTimer?.cancel();
        _emit(const ConnectionStatus(
          state: LanConnectionState.disconnected,
          message: 'Connection lost — reconnecting...',
        ));
        _scheduleReconnect();
      }
    });
  }

  // ── Backoff reconnect ──────────────────────────────────────────────────────
  void _scheduleReconnect() {
    if (!_running || _disposed) return;

    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    const delays = [3, 5, 10, 15, 20];
    final delay =
        delays[_reconnectAttempts.clamp(0, delays.length - 1)];
    _reconnectAttempts++;

    debugPrint('[ConnectionManager] Reconnect in ${delay}s '
        '(attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(Duration(seconds: delay), _tryConnect);
  }

  // ── Manual retry ───────────────────────────────────────────────────────────
  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectAttempts = 0;
    await _tryConnect();
  }

  // ── Persistence ────────────────────────────────────────────────────────────
  (String, int)? _getSavedServer() {
    try {
      final box  = Hive.box('app_settings');
      final ip   = box.get(_savedIpKey)   as String?;
      final port = box.get(_savedPortKey) as int?;
      if (ip != null && port != null) return (ip, port);
    } catch (_) {}
    return null;
  }

  void _saveServer(String ip, int port) {
    try {
      final box = Hive.box('app_settings');
      box.put(_savedIpKey,   ip);
      box.put(_savedPortKey, port);
    } catch (_) {}
  }

  // ── Emit ───────────────────────────────────────────────────────────────────
  void _emit(ConnectionStatus s) {
    if (_disposed) return;
    _current = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  // ── Stop ───────────────────────────────────────────────────────────────────
  Future<void> stop() async {
    _running  = false;
    _disposed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await RealtimeManager().dispose();
    _emit(const ConnectionStatus(
      state: LanConnectionState.disconnected,
      message: 'Disconnected',
    ));
  }
}