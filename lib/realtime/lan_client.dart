import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/constants.dart';

class LanClient {
  WebSocket? _socket;
  final String serverIp;
  final int port;

  final _messageController = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  
  Stream<String> get onMessage => _messageController.stream;
  Stream<bool> get onConnectionChange => _connectionController.stream;

  bool _isConnecting = false;
  bool _isDisposed = false;
  DateTime? _lastPongReceived;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  bool get isConnected => _socket?.readyState == WebSocket.open;

  LanClient({
    required this.serverIp,
    this.port = AppNetwork.websocketPort,
  });

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

          print('LanClient: Received message: ${trimmed.substring(0, 100)}...');
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
      _connectionController.add(true);
      print('LanClient: Connected successfully');

    } catch (error) {
      _isConnecting = false;
      print('LanClient: Connection failed: $error');
      _handleDisconnect();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isConnected || _isDisposed) return;

      // Check if we haven't received pong in 60 seconds
      if (_lastPongReceived != null &&
          DateTime.now().difference(_lastPongReceived!).inSeconds > 60) {
        print('LanClient: Pong timeout - forcing disconnect');
        _handleDisconnect();
        return;
      }

      // Send ping
      sendMessage({'type': 'ping'});
    });
  }

  void sendMessage(Map<String, dynamic> payload) {
    if (!isConnected) {
      print('LanClient: Cannot send - not connected');
      return;
    }
    
    try {
      final message = jsonEncode(payload);
      _socket!.add(message);
      print('LanClient: Sent message: ${payload['event_type'] ?? 'unknown'}');
    } catch (e) {
      print('LanClient: Error sending message: $e');
    }
  }

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

    // Try to reconnect
    final delay = [2, 4, 8, 16, 32][_reconnectAttempts.clamp(0, 4)];
    _reconnectAttempts++;

    print('LanClient: Will reconnect in $delay seconds (attempt $_reconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_isDisposed) {
        connect();
      }
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