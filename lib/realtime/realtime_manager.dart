import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import '../realtime/lan_host_manager.dart';
import 'realtime_router.dart';

class RealtimeManager {
  static final RealtimeManager _instance = RealtimeManager._internal();
  factory RealtimeManager() => _instance;
  RealtimeManager._internal();

  WebSocketChannel? _clientChannel;
  StreamSubscription? _clientSubscription;
  StreamSubscription? _hostMessageSubscription;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  bool _isConnected = false;
  bool _isHostMode = false;
  String? _role;
  String? _branchId;
  String? _serverIp;
  int _port = 53281;
  String? _clientId;

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  DateTime? _lastPong;

  final List<Map<String, dynamic>> _pendingMessages = [];

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  bool get isConnected => _isConnected || (_isHostMode && LanHostManager.isHostRunning);

  String? get role => _role;
  String? get branchId => _branchId;
  String? get clientId => _clientId;

  Future<void> initialize({
    required String role,
    required String branchId,
    String? serverIp,
    int? port,
  }) async {
    await dispose();

    _role = role.trim().toLowerCase();
    _branchId = branchId.trim().toLowerCase();
    _serverIp = serverIp?.trim();
    _port = port ?? _port;

    _clientId = '${DateTime.now().millisecondsSinceEpoch}_${_role}_${Random().nextInt(9999)}';

    print('╔════════════════════════════════════════════════════════════╗');
    print('║ REALTIME MANAGER INITIALIZING                              ║');
    print('╠════════════════════════════════════════════════════════════╣');
    print('║ Role: $_role');
    print('║ Branch: $_branchId');
    print('║ Client ID: $_clientId');
    print('║ Server IP: $_serverIp');
    print('║ Port: $_port');
    print('╚════════════════════════════════════════════════════════════╝');

    if (_role == 'receptionist' || _role == 'host') {
      _isHostMode = true;

      if (LanHostManager.isHostRunning && LanHostManager.localClient != null) {
        print('✅ Host mode detected - using local client');

        _isConnected = LanHostManager.localClient!.isConnected;

        if (_isConnected && _branchId != null) {
          print('🔄 Re-identifying local client with branchId: $_branchId');
          await LanHostManager.identifyLocalClientWithBranch(_branchId!);
          print('✅ Local client re-identified successfully');
        }

        _hostMessageSubscription = LanHostManager.localClient!.onMessage.listen(
          (raw) {
            try {
              final decoded = jsonDecode(raw) as Map<String, dynamic>;
              _routeIncoming(decoded);
            } catch (e) {
              if (kDebugMode) print('Host mode decode error: $e');
            }
          },
          onError: (e) {
            if (kDebugMode) print('Host local client stream error: $e');
          },
          onDone: () {
            if (kDebugMode) print('Host local client stream done');
          },
        );

        _sendPendingMessages();

        print('╔════════════════════════════════════════════════════════════╗');
        print('║ HOST MODE INITIALIZED SUCCESSFULLY                         ║');
        print('║ Local client connected: $_isConnected                      ║');
        print('║ Branch: $_branchId                                         ║');
        print('╚════════════════════════════════════════════════════════════╝');

        return;
      } else {
        print('⚠️ Host mode requested but LanHostManager not running');
        _isHostMode = false;
      }
    }

    if (_serverIp == null || _serverIp!.isEmpty) {
      if (kDebugMode) print('RealtimeManager: No server IP provided for client mode');
      return;
    }

    print('📡 Starting client mode connection...');
    await _connectClient();
  }

  Future<void> _connectClient() async {
    final wsUrl = 'ws://$_serverIp:$_port';
    if (kDebugMode) print('Connecting to WebSocket: $wsUrl (role: $_role, branch: $_branchId)');

    try {
      _clientChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Send identify BEFORE setting up the listener
      final identifyMsg = {
        'event_type': 'identify',
        'role': _role,
        'branchId': _branchId,
        '_clientId': _clientId,
        '_timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      _clientChannel!.sink.add(jsonEncode(identifyMsg));
      print('📤 SENT IDENTIFY IMMEDIATELY:');
      print('   Role: $_role');
      print('   Branch: $_branchId');
      print('   Client ID: $_clientId');

      await Future.delayed(const Duration(milliseconds: 300));

      _clientSubscription = _clientChannel!.stream.listen(
        (message) {
          if (message == 'pong' || message == '{"type":"pong"}') {
            _lastPong = DateTime.now();
            return;
          }

          try {
            final decoded = jsonDecode(message as String) as Map<String, dynamic>;
            print('📨 RAW RECEIVED: ${decoded['event_type']} from ${decoded['_senderRole'] ?? 'unknown'}');
            _routeIncoming(decoded);
          } catch (e) {
            if (kDebugMode) print('Client stream decode error: $e');
          }
        },
        onError: (error) {
          if (kDebugMode) print('WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          if (kDebugMode) print('WebSocket connection closed');
          _handleDisconnect();
        },
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _startPingTimer();
      _sendPendingMessages();

      if (kDebugMode) print('✅ WebSocket connected successfully');
    } catch (e) {
      if (kDebugMode) print('❌ WebSocket connection failed: $e');
      _handleDisconnect();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isConnected) return;

      if (_lastPong != null && DateTime.now().difference(_lastPong!).inSeconds > 50) {
        if (kDebugMode) print('Pong timeout → forcing disconnect');
        _handleDisconnect();
        return;
      }

      sendMessage({'type': 'ping'});
    });
  }

  void _handleDisconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _clientSubscription?.cancel();
    _clientChannel?.sink.close(status.goingAway);
    _clientSubscription = null;

    if (_reconnectAttempts < 5) {
      final delay = [2, 4, 8, 16, 32][_reconnectAttempts.clamp(0, 4)];
      _reconnectAttempts++;
      if (kDebugMode) print('Reconnecting in $delay s (attempt $_reconnectAttempts)');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(seconds: delay), _connectClient);
    } else {
      if (kDebugMode) print('Max reconnection attempts reached');
    }
  }

  void sendMessage(Map<String, dynamic> payload) {
    final normalized = _normalizeMessage(payload);

    normalized['_senderRole'] ??= _role;
    normalized['_senderBranch'] ??= _branchId;
    normalized['_clientId'] ??= _clientId;
    normalized['_timestamp'] = DateTime.now().millisecondsSinceEpoch;
    normalized['_messageId'] ??= _generateMessageId();

    if (_isHostMode && LanHostManager.isHostRunning && LanHostManager.localClient != null) {
      if (LanHostManager.localClient!.isConnected) {
        LanHostManager.localClient!.sendMessage(normalized);
      } else {
        _pendingMessages.add(normalized);
      }
      return;
    }

    if (!_isConnected || _clientChannel == null) {
      _pendingMessages.add(normalized);
      return;
    }

    try {
      _clientChannel!.sink.add(jsonEncode(normalized));
      if (kDebugMode) print('📤 Sent: ${normalized['event_type']}');
    } catch (e) {
      if (kDebugMode) print('Send failed: $e → queuing');
      _pendingMessages.add(normalized);
      _handleDisconnect();
    }
  }

  String _generateMessageId() {
    final rand = Random();
    return '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(100000)}';
  }

  Map<String, dynamic> _normalizeMessage(Map<String, dynamic> original) {
    final copy = Map<String, dynamic>.from(original);

    copy['_clientId'] ??= _clientId;
    copy['_senderRole'] ??= _role;
    copy['_senderBranch'] ??= _branchId;

    if (copy['data'] is Map && copy['data']['branchId'] != null) {
      copy['branchId'] ??= copy['data']['branchId'];
      (copy['data'] as Map).remove('branchId');
    }

    copy['event_type'] ??= 'unknown';

    if (_branchId != null && !copy.containsKey('branchId')) {
      copy['branchId'] = _branchId;
    }

    return copy;
  }

  void _sendPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_pendingMessages);
    _pendingMessages.clear();
    for (final msg in pending) {
      sendMessage(msg);
    }
  }

  void _routeIncoming(Map<String, dynamic> decoded) {
  final type = decoded['event_type'] as String?;
  final data = decoded['data'] as Map<String, dynamic>? ?? decoded;

  final senderId = decoded['_clientId']?.toString() ?? '';
  if (senderId.isNotEmpty && senderId == _clientId) {
    if (kDebugMode) print('⚠️ Ignoring own echo message (clientId match): $type');
    return;  // ✅ PROPER ECHO PREVENTION
  }

    final msgBranch = decoded['branchId']?.toString().toLowerCase().trim() ??
                      decoded['_senderBranch']?.toString().toLowerCase().trim();
    final myBranch = _branchId?.toLowerCase().trim();

    if (msgBranch != null && myBranch != null && msgBranch != myBranch) {
      if (kDebugMode) print('⚠️ Ignoring different branch: $msgBranch (mine: $myBranch)');
      return;
    }

    if (kDebugMode) {
      print('📥 Received: $type | branch: $msgBranch | senderId: $senderId | myId: $_clientId');
    }

    RealtimeRouter.routeMessage(decoded);

    _messageController.add({
      'event_type': type,
      'data': data,
      'decoded': decoded,
    });
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _clientSubscription?.cancel();
    _hostMessageSubscription?.cancel();

    await _clientChannel?.sink.close(status.normalClosure);

    _clientChannel = null;
    _clientSubscription = null;
    _hostMessageSubscription = null;
    _isConnected = false;
    _pendingMessages.clear();
    _lastPong = null;

    if (kDebugMode) print('RealtimeManager fully disposed');
  }
}