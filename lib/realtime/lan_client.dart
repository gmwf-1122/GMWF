// lib/realtime/lan_client.dart
//
// [P4] Pending outbox added — messages sent while the socket is disconnected
//      (or during the reconnect window) are queued in memory and automatically
//      drained once the connection is re-established. This prevents silent
//      message loss on transient disconnects.
//
//      Design notes:
//        - The outbox is intentionally in-memory only. LAN messages are
//          session-scoped; persisting them across a full app restart would
//          require deciding how to handle stale messages — a harder problem
//          than the one being solved here.
//        - _maxOutboxSize (100) caps memory. When exceeded the oldest message
//          is dropped (FIFO). Adjust if your session volume is higher.
//        - _drainOutbox() is called immediately after connect() succeeds,
//          before the connectionController broadcasts true, so subscribers
//          see the connection as live only after the backlog is flushed.
//        - Re-queue on send error: if _socket.add() throws after connect,
//          the message goes back into the outbox for the next reconnect.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/constants.dart';

class LanClient {
  WebSocket? _socket;
  final String serverIp;
  final int port;

  final _messageController    = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<String> get onMessage         => _messageController.stream;
  Stream<bool>   get onConnectionChange => _connectionController.stream;

  bool      _isConnecting       = false;
  bool      _isDisposed         = false;
  DateTime? _lastPongReceived;
  Timer?    _pingTimer;
  Timer?    _reconnectTimer;
  int       _reconnectAttempts  = 0;

  // [P4] In-memory pending outbox
  final List<Map<String, dynamic>> _pendingOutbox = [];
  static const int _maxOutboxSize = 100;

  bool get isConnected => _socket?.readyState == WebSocket.open;

  LanClient({
    required this.serverIp,
    this.port = AppNetwork.websocketPort,
  });

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect() async {
    if (_isConnecting || isConnected || _isDisposed) return;
    _isConnecting = true;

    try {
      final url = 'ws://$serverIp:$port';
      print('LanClient: Connecting to $url');

      _socket = await WebSocket.connect(url).timeout(const Duration(seconds: 10));

      _lastPongReceived = DateTime.now();
      _startPingTimer();
      _reconnectAttempts = 0;

      _socket!.listen(
        (message) {
          if (_isDisposed) return;

          if (message is! String) {
            print('LanClient: Received non-string message');
            return;
          }

          final trimmed = message.trim();

          // Handle pong
          if (trimmed == 'pong' || trimmed == '{"type":"pong"}') {
            _lastPongReceived = DateTime.now();
            return;
          }

          print('LanClient: Received message: '
              '${trimmed.length > 100 ? trimmed.substring(0, 100) + '...' : trimmed}');
          _messageController.add(message);
        },
        onDone: () {
          print('LanClient: Connection closed');
          _handleDisconnect();
        },
        onError: (error) {
          print('LanClient: Error: $error');
          _handleDisconnect();
        },
      );

      _isConnecting = false;

      // [P4] Drain any messages queued while we were offline BEFORE
      // broadcasting the connected state so callers see a fully ready socket.
      _drainOutbox();

      _connectionController.add(true);
      print('LanClient: Connected successfully');
    } catch (error) {
      _isConnecting = false;
      print('LanClient: Connection failed: $error');
      _handleDisconnect();
    }
  }

  // ── Ping / keepalive ───────────────────────────────────────────────────────

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isConnected || _isDisposed) return;

      // Force disconnect if no pong received in 60 seconds
      if (_lastPongReceived != null &&
          DateTime.now().difference(_lastPongReceived!).inSeconds > 60) {
        print('LanClient: Pong timeout - forcing disconnect');
        _handleDisconnect();
        return;
      }

      sendMessage({'type': 'ping'});
    });
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  /// Sends [payload] to the server.
  ///
  /// If the socket is not currently connected the message is placed in the
  /// pending outbox and will be sent automatically once reconnection succeeds.
  /// The outbox has a hard cap of [_maxOutboxSize]; when exceeded the oldest
  /// message is silently dropped to bound memory usage.
  void sendMessage(Map<String, dynamic> payload) {
    if (!isConnected) {
      if (_isDisposed) {
        print('LanClient: disposed — dropping ${payload['event_type'] ?? 'unknown'}');
        return;
      }
      print('LanClient: offline — queuing ${payload['event_type'] ?? 'unknown'} '
          '(outbox size: ${_pendingOutbox.length + 1})');
      _pendingOutbox.add(payload);
      if (_pendingOutbox.length > _maxOutboxSize) {
        final dropped = _pendingOutbox.removeAt(0);
        print('LanClient: outbox full — dropped oldest: '
            '${dropped['event_type'] ?? 'unknown'}');
      }
      return;
    }

    try {
      final message = jsonEncode(payload);
      _socket!.add(message);
      print('LanClient: Sent message: ${payload['event_type'] ?? 'unknown'}');
    } catch (e) {
      print('LanClient: Error sending message: $e — re-queuing');
      // Re-queue on failure so it is retried after the next reconnect
      _pendingOutbox.add(payload);
      if (_pendingOutbox.length > _maxOutboxSize) {
        _pendingOutbox.removeAt(0);
      }
    }
  }

  // ── [P4] Drain outbox after reconnect ─────────────────────────────────────

  /// Called immediately after a successful socket connect.
  /// Flushes all messages that were queued while the socket was offline.
  void _drainOutbox() {
    if (_pendingOutbox.isEmpty) return;

    final toSend = List<Map<String, dynamic>>.from(_pendingOutbox);
    _pendingOutbox.clear();

    print('LanClient: draining ${toSend.length} queued message(s)');
    for (final msg in toSend) {
      sendMessage(msg); // socket is now open; this will send directly
    }
  }

  // ── Disconnect / reconnect ─────────────────────────────────────────────────

  void _handleDisconnect() {
    _pingTimer?.cancel();

    try {
      _socket?.close();
    } catch (_) {}

    _socket = null;

    if (_isDisposed) {
      _connectionController.add(false);
      return;
    }

    // Exponential back-off: 2, 4, 8, 16, 32 seconds
    final delay = [2, 4, 8, 16, 32][_reconnectAttempts.clamp(0, 4)];
    _reconnectAttempts++;

    print('LanClient: Will reconnect in $delay seconds '
        '(attempt $_reconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_isDisposed) connect();
    });

    _connectionController.add(false);
  }

  Future<void> disconnect() async {
    _isDisposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();

    try {
      await _socket?.close();
    } catch (_) {}

    await _messageController.close();
    await _connectionController.close();

    print('LanClient: Disconnected');
  }
}
