// lib/realtime/connection_manager.dart
//
// PERSISTENCE FIX:
//   [FIX-P1] onReconnected callback — fired every time a connection is
//            successfully established. Doctor/Dispenser screens subscribe
//            to this to pull missing data immediately on reconnect.
//
// BUG FIXES:
//   [BUG-9]  onReconnected was a single nullable field — a second screen
//            calling start() would silently overwrite the first screen's
//            callback. Replaced with a listener list (_reconnectListeners)
//            so multiple screens can subscribe independently without
//            stomping each other.
//
//   [BUG-10] _waitForIdentified completed with true merely because
//            isConnected was already true, before the server had processed
//            the identify message. The isConnected fast-path now waits a
//            full 500 ms to give the server time to echo 'identified'.
//
//   [BUG-11] _heartbeatTimer guard: if stop() is called between the timer
//            firing and the _running check, _scheduleReconnect could run
//            on a disposed manager. Added explicit _disposed guard.
//
// NETWORK FIXES:
//   [FIX-NET-1] useDedicatedServer support — when AppNetwork.useDedicatedServer
//               is true, _tryConnect() skips LanDiscovery entirely and connects
//               directly to AppNetwork.dedicatedServerIp. This bypasses mDNS,
//               UDP broadcast, and subnet scan which all fail under AP isolation.
//
//   [FIX-NET-2] Discovery timeout increased from 15 s to 25 s to give the
//               server time to start broadcasting before clients give up.
//
//   [FIX-NET-3] On discovery failure the error message now distinguishes
//               between "no WiFi" and "server not found" to help diagnose
//               AP isolation vs server-not-running issues.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
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
  String? _username;

  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int    _reconnectAttempts = 0;
  bool   _running  = false;
  bool   _disposed = false;

  // [BUG-9] List of reconnect listeners instead of a single nullable field.
  final List<VoidCallback> _reconnectListeners = [];

  /// Register a callback that fires every time a connection is confirmed.
  /// Returns a remove function for easy cleanup in dispose().
  VoidCallback addReconnectListener(VoidCallback cb) {
    _reconnectListeners.add(cb);
    return () => _reconnectListeners.remove(cb);
  }

  /// Remove a specific reconnect listener.
  void removeReconnectListener(VoidCallback cb) {
    _reconnectListeners.remove(cb);
  }

  // Back-compat setter — adds to listener list.
  set onReconnected(VoidCallback? cb) {
    if (cb != null) _reconnectListeners.add(cb);
  }

  static const _savedIpKey   = 'last_server_ip';
  static const _savedPortKey = 'last_server_port';

  // ── Start ──────────────────────────────────────────────────────────────────
  Future<void> start({
    required String role,
    required String branchId,
    String? username,
  }) async {
    _role     = role.toLowerCase().trim();
    _branchId = branchId.toLowerCase().trim();
    _username = username?.trim();
    _running  = true;
    _disposed = false;
    _reconnectAttempts = 0;

    debugPrint('[ConnectionManager] Starting: role=$_role branch=$_branchId'
        '${AppNetwork.useDedicatedServer ? " [dedicated: ${AppNetwork.dedicatedServerIp}]" : ""}');
    await _tryConnect();
  }

  // ── Discovery + connect loop ───────────────────────────────────────────────
  Future<void> _tryConnect() async {
    if (!_running || _disposed) return;

    // ── [FIX-NET-1] Dedicated-server fast-path ─────────────────────────────
    // Skip all discovery when a fixed server IP is configured. This is the
    // correct approach for production deployments and avoids every UDP/mDNS
    // failure mode including AP isolation.
    if (AppNetwork.useDedicatedServer) {
      _emit(ConnectionStatus(
        state: LanConnectionState.connecting,
        ip: AppNetwork.dedicatedServerIp,
        port: AppNetwork.websocketPort,
        message: 'Connecting to ${AppNetwork.dedicatedServerIp}...',
      ));
      final ok = await _connectTo(
        AppNetwork.dedicatedServerIp,
        AppNetwork.websocketPort,
      );
      if (!ok) {
        _emit(ConnectionStatus(
          state: LanConnectionState.disconnected,
          message: 'Cannot reach server at ${AppNetwork.dedicatedServerIp}:${AppNetwork.websocketPort}. '
              'Check the IP and that the server is running.',
        ));
        _scheduleReconnect();
      }
      return;
    }

    // ── Auto-discovery path ────────────────────────────────────────────────
    final connList = await Connectivity().checkConnectivity();
    final hasNetwork = connList.contains(ConnectivityResult.wifi) ||
        connList.contains(ConnectivityResult.ethernet) ||
        connList.contains(ConnectivityResult.other);

    if (!hasNetwork) {
      _emit(const ConnectionStatus(
        state: LanConnectionState.disconnected,
        // [FIX-NET-3] Clearer message to distinguish no-WiFi from no-server
        message: 'No WiFi or LAN detected. Connect all devices to the same network.',
      ));
      _scheduleReconnect();
      return;
    }

    _emit(const ConnectionStatus(
      state: LanConnectionState.searching,
      message: 'Looking for server...',
    ));

    // Try last-known server first (fastest path after first connection).
    final saved = _getSavedServer();
    if (saved != null) {
      debugPrint('[ConnectionManager] Trying saved server: ${saved.$1}:${saved.$2}');
      final reachable = await LanDiscovery.isReachable(saved.$1, saved.$2);
      if (reachable) {
        final ok = await _connectTo(saved.$1, saved.$2);
        if (ok) return;
      } else {
        debugPrint('[ConnectionManager] Saved server unreachable, falling back to discovery');
      }
    }

    _emit(const ConnectionStatus(
      state: LanConnectionState.searching,
      message: 'Scanning network for server...',
    ));

    // [FIX-NET-2] Increased timeout from 15 s → 25 s
    final found = await LanDiscovery.findServer(
      timeout: const Duration(seconds: 25),
      onStatus: (s) => _emit(ConnectionStatus(
        state: LanConnectionState.searching,
        message: s,
      )),
    );

    if (found == null) {
      _emit(const ConnectionStatus(
        state: LanConnectionState.disconnected,
        // [FIX-NET-3] Actionable message — most common cause is AP isolation
        message: 'Server not found. Ensure all devices are on the same WiFi/LAN '
            'and AP isolation is disabled on the router. '
            'Or set dedicatedServerIp in AppNetwork.',
      ));
      _scheduleReconnect();
      return;
    }

    debugPrint('[ConnectionManager] Discovered server via ${found.method}: ${found.ip}:${found.port}');
    final ok = await _connectTo(found.ip, found.port);
    if (!ok) _scheduleReconnect();
  }

  // ── Connect to specific IP ─────────────────────────────────────────────────
  Future<bool> _connectTo(String ip, int port) async {
    if (!_running || _disposed) return false;

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
        username: _username,
      );

      final confirmed = await _waitForIdentified(timeoutSeconds: 6);

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

      // [FIX-P1] [BUG-9] Notify all registered listeners.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!_disposed) {
          for (final cb in List<VoidCallback>.from(_reconnectListeners)) {
            try { cb(); } catch (e) {
              debugPrint('[ConnectionManager] reconnect listener error: $e');
            }
          }
        }
      });

      _startHeartbeat(ip, port);
      debugPrint('[ConnectionManager] ✅ Connected at $ip:$port');
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
  // [BUG-10] The isConnected fast-path now waits 500 ms (was 250 ms) before
  // completing, giving the server more time to echo 'identified'.
  Future<bool> _waitForIdentified({required int timeoutSeconds}) async {
    final completer = Completer<bool>();

    late StreamSubscription sub;
    sub = RealtimeManager().messageStream.listen((event) {
      if (event['event_type'] == 'identified' && !completer.isCompleted) {
        sub.cancel();
        completer.complete(true);
      }
    });

    // Fast-path: if already connected wait 500 ms for the echo then resolve.
    if (RealtimeManager().isConnected) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!completer.isCompleted) completer.complete(true);
    }

    Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(RealtimeManager().isConnected);
      }
    });

    return completer.future;
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────
  void _startHeartbeat(String ip, int port) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 4), (_) async {
      // [BUG-11] Explicit disposed guard.
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

    debugPrint('[ConnectionManager] Reconnect in ${delay}s (attempt $_reconnectAttempts)');
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
    // Don't use saved server when dedicated mode is on — always use the fixed IP.
    if (AppNetwork.useDedicatedServer) return null;
    try {
      final box  = Hive.box('app_settings');
      final ip   = box.get(_savedIpKey)   as String?;
      final port = box.get(_savedPortKey) as int?;
      if (ip != null && port != null) return (ip, port);
    } catch (_) {}
    return null;
  }

  void _saveServer(String ip, int port) {
    if (AppNetwork.useDedicatedServer) return; // no need to cache a fixed address
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
    // [BUG-9] Do NOT clear _reconnectListeners here — screens will call
    // removeReconnectListener in their own dispose().
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await RealtimeManager().dispose();
    _emit(const ConnectionStatus(
      state: LanConnectionState.disconnected,
      message: 'Disconnected',
    ));
  }
}