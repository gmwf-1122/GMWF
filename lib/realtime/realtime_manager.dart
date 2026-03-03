// lib/realtime/realtime_manager.dart
//
// ARCHITECTURE: Pure WebSocket client for ALL roles (receptionist, doctor, dispenser).
// Dedicated server device runs ServerDashboardWithSync (LanServer + ServerSyncManager).
//
// CHANGES IN THIS VERSION:
//   1. initialize() now accepts optional 'username' parameter.
//   2. 'identify' message includes username so server dashboard shows real names.
//   3. All other logic unchanged from previous client-only version.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'realtime_router.dart';

class RealtimeManager {
  static final RealtimeManager _instance = RealtimeManager._internal();
  factory RealtimeManager() => _instance;
  RealtimeManager._internal();

  // ── State ─────────────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected      = false;
  bool _serverIdentified = false;

  String? _role;
  String? _branchId;
  String? _username;   // ← NEW: displayed on server dashboard
  String? _serverIp;
  int     _port      = 53281;
  String? _clientId;

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int    _reconnectAttempts = 0;
  DateTime? _lastPong;

  final List<Map<String, dynamic>> _pendingMessages = [];

  // ── Public getters ─────────────────────────────────────────────────────────
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  bool    get isConnected => _isConnected;
  String? get role        => _role;
  String? get branchId    => _branchId;
  String? get username    => _username;
  String? get clientId    => _clientId;

  // ── Initialize ─────────────────────────────────────────────────────────────
  Future<void> initialize({
    required String role,
    required String branchId,
    required String serverIp,
    int    port     = 53281,
    String? username,           // ← NEW: pass display name here
  }) async {
    await dispose();

    _role     = role.trim().toLowerCase();
    _branchId = branchId.trim().toLowerCase();
    _serverIp = serverIp.trim();
    _port     = port;
    _username = username?.trim();
    _serverIdentified = false;

    _clientId =
        '${DateTime.now().millisecondsSinceEpoch}_${_role}_${Random().nextInt(9999)}';

    if (kDebugMode) {
      print('╔══════════════════════════════════════════════════════════════╗');
      print('║ REALTIME MANAGER — initializing                             ║');
      print('║  Role     : $_role');
      print('║  Branch   : $_branchId');
      print('║  Username : ${_username ?? "(none)"}');
      print('║  Server   : $_serverIp:$_port');
      print('║  ClientId : $_clientId');
      print('╚══════════════════════════════════════════════════════════════╝');
    }

    await _connectClient();
  }

  // ── WebSocket connect ──────────────────────────────────────────────────────
  Future<void> _connectClient() async {
    if (_serverIp == null || _serverIp!.isEmpty) {
      if (kDebugMode) print('[RealtimeManager] No server IP — cannot connect');
      return;
    }

    final wsUrl = 'ws://$_serverIp:$_port';
    if (kDebugMode) print('[RealtimeManager] Connecting → $wsUrl');

    _serverIdentified = false;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Send 'identify' immediately with username included so the server
      // dashboard can display the real name of the connected client.
      final identifyMsg = {
        'event_type': 'identify',
        'role':       _role,
        'branchId':   _branchId,
        'username':   _username ?? _role,   // ← username in identify payload
        '_clientId':  _clientId,
        '_timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _channel!.sink.add(jsonEncode(identifyMsg));

      if (kDebugMode) {
        print('[RealtimeManager] Sent identify: '
            'role=$_role username=$_username branch=$_branchId');
      }

      await Future.delayed(const Duration(milliseconds: 300));

      _channelSub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _handleDisconnect(),
        onDone:  ()  => _handleDisconnect(),
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _startPingTimer();
      _schedulePendingFallback();

      if (kDebugMode) {
        print('[RealtimeManager] WebSocket open — waiting for identified echo');
      }
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] Connect failed: $e');
      _handleDisconnect();
    }
  }

  // ── Incoming message ───────────────────────────────────────────────────────
  void _onMessage(dynamic raw) {
    if (raw == null) return;
    final msg = raw as String;

    if (msg == 'pong' || msg == '{"type":"pong"}') {
      _lastPong = DateTime.now();
      return;
    }

    try {
      final decoded = jsonDecode(msg) as Map<String, dynamic>;

      if (decoded['event_type'] == 'identified' && !_serverIdentified) {
        _serverIdentified = true;
        if (kDebugMode) {
          print('[RealtimeManager] Server confirmed identity — '
              'flushing ${_pendingMessages.length} pending messages');
        }
        _sendPendingMessages();
      }

      if (kDebugMode) {
        print('[RealtimeManager] ← ${decoded['event_type']} '
            'from ${decoded['_senderRole'] ?? 'server'}');
      }

      _routeIncoming(decoded);
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] Decode error: $e');
    }
  }

  // ── Fallback flush (if server never echoes 'identified') ──────────────────
  void _schedulePendingFallback() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_serverIdentified && _isConnected && _pendingMessages.isNotEmpty) {
        if (kDebugMode) {
          print('[RealtimeManager] No identified echo after 3 s — '
              'flushing pending (fallback)');
        }
        _serverIdentified = true;
        _sendPendingMessages();
      }
    });
  }

  // ── Ping / pong ────────────────────────────────────────────────────────────
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isConnected) return;

      if (_lastPong != null &&
          DateTime.now().difference(_lastPong!).inSeconds > 50) {
        if (kDebugMode) print('[RealtimeManager] Pong timeout → reconnecting');
        _handleDisconnect();
        return;
      }

      sendMessage({'type': 'ping'});
    });
  }

  // ── Disconnect / reconnect ─────────────────────────────────────────────────
  void _handleDisconnect() {
    _isConnected      = false;
    _serverIdentified = false;
    _pingTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close(ws_status.goingAway);
    _channelSub = null;

    if (_reconnectAttempts < 5) {
      final delay =
          const [2, 4, 8, 16, 32][(_reconnectAttempts).clamp(0, 4)];
      _reconnectAttempts++;
      if (kDebugMode) {
        print('[RealtimeManager] Reconnect in ${delay}s '
            '(attempt $_reconnectAttempts)');
      }
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delay), _connectClient);
    } else {
      if (kDebugMode) print('[RealtimeManager] Max reconnect attempts reached');
    }
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  void sendMessage(Map<String, dynamic> payload) {
    final normalized = _normalizeMessage(payload);

    if (!_isConnected || _channel == null || !_serverIdentified) {
      if (kDebugMode &&
          normalized['event_type'] != 'ping' &&
          normalized['type'] != 'ping') {
        print('[RealtimeManager] Queuing '
            '(${!_isConnected ? "not connected" : "not yet identified"}): '
            '${normalized['event_type']}');
      }
      _pendingMessages.add(normalized);
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(normalized));
      if (kDebugMode) print('[RealtimeManager] → ${normalized['event_type']}');
    } catch (e) {
      if (kDebugMode) print('[RealtimeManager] Send failed: $e → queuing');
      _pendingMessages.add(normalized);
      _handleDisconnect();
    }
  }

  // ── Flush pending ──────────────────────────────────────────────────────────
  void _sendPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_pendingMessages);
    _pendingMessages.clear();

    if (kDebugMode) {
      print('[RealtimeManager] Flushing ${pending.length} pending messages');
    }

    for (final msg in pending) {
      if (msg['event_type'] == 'ping' || msg['type'] == 'ping') continue;
      sendMessage(msg);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> original) {
    final copy = Map<String, dynamic>.from(original);

    copy['_clientId']     ??= _clientId;
    copy['_senderRole']   ??= _role;
    copy['_senderBranch'] ??= _branchId;
    copy['_username']     ??= _username ?? _role;  // ← include in every message
    copy['event_type']    ??= 'unknown';
    copy['_timestamp']      = DateTime.now().millisecondsSinceEpoch;
    copy['_messageId']    ??= _generateMessageId();

    if (_branchId != null && !copy.containsKey('branchId')) {
      copy['branchId'] = _branchId;
    }

    if (copy['data'] is Map) {
      final data = copy['data'] as Map;
      if (data.containsKey('branchId')) {
        copy['branchId'] ??= data['branchId'];
        data.remove('branchId');
      }
    }

    return copy;
  }

  String _generateMessageId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}';

  // ── Route incoming ─────────────────────────────────────────────────────────
  void _routeIncoming(Map<String, dynamic> decoded) {
    final type     = decoded['event_type'] as String?;
    final data     = decoded['data'] as Map<String, dynamic>? ?? decoded;
    final senderId = decoded['_clientId']?.toString() ?? '';

    if (senderId.isNotEmpty && senderId == _clientId) {
      if (kDebugMode) print('[RealtimeManager] Ignoring own echo: $type');
      return;
    }

    final msgBranch = (decoded['branchId'] ?? decoded['_senderBranch'])
        ?.toString().toLowerCase().trim();
    final myBranch = _branchId?.toLowerCase().trim();

    if (msgBranch != null && myBranch != null && msgBranch != myBranch) {
      if (kDebugMode) {
        print('[RealtimeManager] Ignoring cross-branch: '
            '$msgBranch (mine: $myBranch)');
      }
      return;
    }

    RealtimeRouter.routeMessage(decoded);

    _messageController.add({
      'event_type': type,
      'data':       data,
      'decoded':    decoded,
    });
  }

  // ── Dispose ────────────────────────────────────────────────────────────────
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channelSub?.cancel();
    await _channel?.sink.close(ws_status.normalClosure);

    _channel       = null;
    _channelSub    = null;
    _isConnected   = false;
    _serverIdentified = false;
    _pendingMessages.clear();
    _lastPong      = null;

    if (kDebugMode) print('[RealtimeManager] Disposed');
  }
}