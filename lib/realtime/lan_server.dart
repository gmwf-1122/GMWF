import 'dart:convert';
import 'dart:io';

import '../config/constants.dart';

class LanServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  final Map<WebSocket, Map<String, dynamic>> _clientInfo = {};
  final int port;

  int _messagesReceived = 0;
  int _messagesSent = 0;

  // ── Callbacks ────────────────────────────────────────────────────────────────
  /// Called when a client sends a valid 'identify' message.
  /// [socketId] is a stable string key (socket.hashCode.toString()).
  /// [info] contains 'role', 'branchId', 'clientId'.
  Function(String socketId, Map<String, dynamic> info)? onClientConnected;

  /// Called when a client disconnects.
  Function(String socketId)? onClientDisconnected;

  /// Called when any identified client sends a non-protocol message.
  Function(Map<String, dynamic>)? onMessageReceived;

  LanServer({this.port = AppNetwork.websocketPort});

  int get clientCount => _clientInfo.length;
  int get messagesReceived => _messagesReceived;
  int get messagesSent => _messagesSent;

  Future<void> start(String? forcedIp) async {
    try {
      final address = InternetAddress.anyIPv4;
      _server = await HttpServer.bind(address, port, shared: true);

      final ipShown = forcedIp ?? 'your-LAN-IP';
      print('╔════════════════════════════════════════════════════════════╗');
      print('║ LAN WebSocket Server STARTED                               ║');
      print('║ Listening on: 0.0.0.0:$port   (share $ipShown:$port)      ║');
      print('╚════════════════════════════════════════════════════════════╝');

      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            _addClient(socket);
          } catch (e) {
            print('WebSocket upgrade failed: $e');
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write('WebSocket upgrade failed')
              ..close();
          }
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..write('GMWF LAN Token Server - Use ws://$ipShown:$port')
            ..close();
        }
      });
    } catch (e) {
      print('╔════════════════════════════════════════════════════════════╗');
      print('║ FAILED TO START LAN SERVER on port $port                   ║');
      print('║ Error: $e                                                  ║');
      print('╚════════════════════════════════════════════════════════════╝');
      rethrow;
    }
  }

  void _addClient(WebSocket socket) {
    _clients.add(socket);
    final socketId = socket.hashCode.toString();

    print('╔════════════════════════════════════════════════════════════╗');
    print('║ NEW CLIENT CONNECTED                                       ║');
    print('║ Socket: $socketId                                          ║');
    print('║ Total clients: ${_clients.length}                         ║');
    print('╚════════════════════════════════════════════════════════════╝');

    socket.add(jsonEncode({
      'event_type': 'identify_request',
      'timestamp': DateTime.now().toIso8601String(),
      'message': 'Please identify your role and branch',
    }));

    socket.listen(
      (message) {
        if (message is! String) return;

        final trimmed = message.trim();

        if (trimmed == 'ping' || trimmed == '{"type":"ping"}') {
          socket.add('pong');
          return;
        }
        if (trimmed == 'pong' || trimmed == '{"type":"pong"}') return;

        try {
          final data = jsonDecode(message) as Map<String, dynamic>;
          final eventType = data['event_type'] as String?;

          _messagesReceived++;

          if (eventType == 'identify') {
            final role = data['role'] as String?;
            final branchId = data['branchId'] as String?;
            final clientId = data['_clientId'] as String?;

            if (role != null && branchId != null) {
              final info = {
                'role': role.toLowerCase().trim(),
                'branchId': branchId.toLowerCase().trim(),
                'clientId': clientId,
                'identified': true,
                'connectedAt': DateTime.now().toIso8601String(),
              };
              _clientInfo[socket] = info;

              print('╔════════════════════════════════════════════════════════════╗');
              print('║ CLIENT IDENTIFIED                                          ║');
              print('║ Socket: $socketId  Role: $role  Branch: $branchId         ║');
              print('║ Total identified: ${_clientInfo.length}                    ║');
              print('╚════════════════════════════════════════════════════════════╝');

              socket.add(jsonEncode({
                'event_type': 'identified',
                'role': role,
                'branchId': branchId,
                'clientId': clientId,
                'timestamp': DateTime.now().toIso8601String(),
              }));

              // ← Notify dashboard of new connected client
              onClientConnected?.call(socketId, info);

              _broadcastClientCount();
            } else {
              print('⚠️ Incomplete identification: role=$role, branch=$branchId');
            }
            return;
          }

          if (!_clientInfo.containsKey(socket) ||
              _clientInfo[socket]!['identified'] != true) {
            print('❌ Message from UNIDENTIFIED client $socketId - REJECTING');
            return;
          }

          print('╔════════════════════════════════════════════════════════════╗');
          print('║ MESSAGE FROM: ${_clientInfo[socket]!['role']}   Event: $eventType');
          print('╚════════════════════════════════════════════════════════════╝');

          final enhancedData = Map<String, dynamic>.from(data);
          enhancedData['_serverTimestamp'] = DateTime.now().toIso8601String();
          enhancedData['_senderRole'] = _clientInfo[socket]!['role'];
          enhancedData['_senderBranch'] = _clientInfo[socket]!['branchId'];
          enhancedData['_clientId'] ??= _clientInfo[socket]!['clientId'];

          onMessageReceived?.call(enhancedData);
          _routeMessage(socket, enhancedData);
        } catch (e) {
          print('❌ Error processing message from $socketId: $e');
        }
      },
      onDone: () => _removeClient(socket),
      onError: (error) => _removeClient(socket),
    );
  }

  void _routeMessage(WebSocket sender, Map<String, dynamic> message) {
    final senderInfo = _clientInfo[sender];
    if (senderInfo == null) return;

    final eventType = message['event_type'] as String? ?? 'unknown';
    final senderBranch = senderInfo['branchId'] as String;

    final messageBranch =
        (message['branchId'] as String?)?.toLowerCase().trim() ??
        (message['data'] is Map
            ? (message['data']['branchId'] as String?)?.toLowerCase().trim()
            : null) ??
        senderBranch;

    final messageJson = jsonEncode(message);
    int sentCount = 0;

    for (final client in List<WebSocket>.from(_clients)) {
      if (client == sender) continue;
      if (client.readyState != WebSocket.open) continue;

      final clientInfo = _clientInfo[client];
      if (clientInfo == null || clientInfo['identified'] != true) continue;

      final clientBranch = clientInfo['branchId'] as String;
      if (clientBranch != messageBranch && clientBranch != senderBranch) continue;

      try {
        client.add(messageJson);
        sentCount++;
        _messagesSent++;
      } catch (e) {
        print('  ❌ ERROR sending to ${client.hashCode}: $e');
      }
    }

    if (sentCount == 0 && eventType != 'identify') {
      print('⚠️ Message "$eventType" not delivered to any client!');
    }
  }

  void _broadcastClientCount() {
    final count = _clientInfo.length;
    final countMsg = jsonEncode({
      'event_type': 'client_count_update',
      'count': count,
      'timestamp': DateTime.now().toIso8601String(),
    });

    for (final client in _clients) {
      if (client.readyState == WebSocket.open && _clientInfo.containsKey(client)) {
        try {
          client.add(countMsg);
        } catch (e) {
          print('Error broadcasting count: $e');
        }
      }
    }
  }

  void _removeClient(WebSocket socket) {
    final socketId = socket.hashCode.toString();
    _clients.remove(socket);
    _clientInfo.remove(socket);

    print('╔════════════════════════════════════════════════════════════╗');
    print('║ CLIENT DISCONNECTED: $socketId                            ║');
    print('║ Remaining clients: ${_clients.length}                     ║');
    print('╚════════════════════════════════════════════════════════════╝');

    // ← Notify dashboard of disconnection
    onClientDisconnected?.call(socketId);

    _broadcastClientCount();
  }

  void broadcast(String rawMessage, {WebSocket? exclude}) {
    int forwarded = 0;
    for (final client in List<WebSocket>.from(_clients)) {
      if (client.readyState == WebSocket.open && client != exclude) {
        client.add(rawMessage);
        forwarded++;
      }
    }
    if (forwarded > 0) print('Broadcast sent to $forwarded client(s)');
  }

  Future<void> stop() async {
    print('Shutting down LAN server... (${_clients.length} clients)');
    for (final client in _clients) {
      try {
        client.close();
      } catch (_) {}
    }
    _clients.clear();
    _clientInfo.clear();
    try {
      await _server?.close(force: true);
      print('LAN server socket closed');
    } catch (e) {
      print('Error closing server socket: $e');
    }
    _server = null;
    print('LAN server fully stopped');
  }
}