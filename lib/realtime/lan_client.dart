import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';

enum LanConnectionState { connected, reconnecting, disconnected }

class LanClient {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  final String serverIp;
  final int port;
  final String? authToken;

  final _messageController         = StreamController<String>.broadcast();
  final _connectionController      = StreamController<bool>.broadcast();
  final _stateController           = StreamController<LanConnectionState>.broadcast();

  Stream<String>             get onMessage           => _messageController.stream;
  Stream<bool>               get onConnectionChange  => _connectionController.stream;
  Stream<LanConnectionState> get connectionStateStream => _stateController.stream;

  bool      _isConnecting       = false;
  bool      _isConnected        = false;
  bool      _isDisposed         = false;
  DateTime? _lastPongReceived;
  Timer?    _pingTimer;
  Timer?    _reconnectTimer;
  int       _reconnectAttempts  = 0;
  LanConnectionState _currentState = LanConnectionState.disconnected;

  // In-memory pending outbox
  final List<Map<String, dynamic>> _pendingOutbox = [];
  static const int _maxOutboxSize = 100;

  bool get isConnected => _isConnected && !_isDisposed;
  LanConnectionState get state => _currentState;

  LanClient({
    required this.serverIp,
    this.port = AppNetwork.websocketPort,
    this.authToken,
  });

  void _setState(LanConnectionState s) {
    _currentState = s;
    _stateController.add(s);
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_isConnecting || isConnected || _isDisposed) return;
    _isConnecting = true;
    _setState(_reconnectAttempts > 0 ? LanConnectionState.reconnecting : LanConnectionState.disconnected);

    // Item 9 — Mixed-Content check on Web HTTPS
    if (kIsWeb && Uri.base.scheme == 'https') {
      final msg = 'HTTPS Mixed-Content Error: Web client served over HTTPS cannot connect to non-TLS ws://$serverIp:$port LAN server. Host web client over HTTP or enable WSS.';
      debugPrint('LanClient: ❌ $msg');
      _messageController.add(jsonEncode({'type': 'error', 'message': msg}));
      _isConnecting = false;
      _setState(LanConnectionState.disconnected);
      return;
    }

    try {
      final url = 'ws://$serverIp:$port';
      debugPrint('LanClient: Connecting to $url');

      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      _channelSub?.cancel();
      _channelSub = _channel!.stream.listen(
        (message) {
          if (_isDisposed) return;

          _lastPongReceived = DateTime.now();
          final trimmed = message.toString().trim();

          // Handle pong
          if (trimmed == 'pong' || trimmed == '{"type":"pong"}' || trimmed.contains('"pong"')) {
            return;
          }

          debugPrint('LanClient: Received message: '
              '${trimmed.length > 100 ? '${trimmed.substring(0, 100)}...' : trimmed}');
          _messageController.add(trimmed);
        },
        onDone: () {
          debugPrint('LanClient: Connection closed');
          _handleDisconnect();
        },
        onError: (error) {
          debugPrint('LanClient: Error: $error');
          _handleDisconnect();
        },
      );

      _isConnected = true;
      _isConnecting = false;
      _lastPongReceived = DateTime.now();
      _startPingTimer();
      _reconnectAttempts = 0;
      _setState(LanConnectionState.connected);

      // Item 10 — Send Auth Handshake
      if (authToken != null && authToken!.isNotEmpty) {
        sendMessage({
          'type': 'auth_handshake',
          'authToken': authToken,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      // Drain any messages queued while offline
      _drainOutbox();

      _connectionController.add(true);
      debugPrint('LanClient: Connected successfully to $url');
    } catch (error) {
      _isConnecting = false;
      _isConnected = false;
      debugPrint('LanClient: Connection failed: $error');
      _handleDisconnect();
    }
  }

  // ── Ping / keepalive ───────────────────────────────────────────────────────

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isConnected || _isDisposed) return;

      if (_lastPongReceived != null &&
          DateTime.now().difference(_lastPongReceived!).inSeconds > 60) {
        debugPrint('LanClient: Pong timeout - forcing disconnect');
        _handleDisconnect();
        return;
      }

      sendMessage({'type': 'ping'});
    });
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  void sendMessage(Map<String, dynamic> payload) {
    if (!isConnected) {
      if (_isDisposed) return;
      _pendingOutbox.add(payload);
      if (_pendingOutbox.length > _maxOutboxSize) {
        _pendingOutbox.removeAt(0);
      }
      return;
    }

    try {
      final message = jsonEncode(payload);
      _channel!.sink.add(message);
    } catch (e) {
      _pendingOutbox.add(payload);
      if (_pendingOutbox.length > _maxOutboxSize) {
        _pendingOutbox.removeAt(0);
      }
    }
  }

  void _drainOutbox() {
    if (_pendingOutbox.isEmpty) return;
    final toSend = List<Map<String, dynamic>>.from(_pendingOutbox);
    _pendingOutbox.clear();
    for (final msg in toSend) {
      sendMessage(msg);
    }
  }

  // ── Disconnect / reconnect ─────────────────────────────────────────────────

  void _handleDisconnect() {
    _pingTimer?.cancel();
    _isConnected = false;
    _isConnecting = false;

    try {
      _channelSub?.cancel();
      _channel?.sink.close();
    } catch (_) {}

    _channelSub = null;
    _channel = null;

    if (_isDisposed) {
      _setState(LanConnectionState.disconnected);
      _connectionController.add(false);
      return;
    }

    _setState(LanConnectionState.reconnecting);

    // Item 8 — Exponential backoff with random jitter (1s up to 30s cap)
    final baseDelay = min(30, pow(2, _reconnectAttempts).toInt());
    final jitter = Random().nextInt(1000); // 0..999 ms
    final delayMs = (baseDelay * 1000) + jitter;
    _reconnectAttempts++;

    debugPrint('LanClient: Will reconnect in ${delayMs / 1000}s (attempt $_reconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_isDisposed) connect();
    });

    _connectionController.add(false);
  }

  Future<void> disconnect() async {
    _isDisposed = true;
    _isConnected = false;
    _isConnecting = false;
    _setState(LanConnectionState.disconnected);
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();

    try {
      await _channelSub?.cancel();
      await _channel?.sink.close();
    } catch (_) {}

    await _messageController.close();
    await _connectionController.close();
    await _stateController.close();

    debugPrint('LanClient: Disconnected');
  }
}
