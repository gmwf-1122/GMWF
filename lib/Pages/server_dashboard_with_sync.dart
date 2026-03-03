// lib/pages/server_dashboard_with_sync.dart
//
// SYNC FIXES IN THIS VERSION:
//   1. ServerSyncManager._mapEventTypeToSyncType() now maps:
//        'save_dispensary_record' → 'save_dispensary_record'
//        'update_serial_status'   → 'update_serial_status'
//        'dispense_completed'     → triggers both writes inline
//   2. _syncToFirestore() has full case handlers for both new types:
//        'save_dispensary_record' → branches/{b}/dispensary/{dateKey}/{dateKey}/{serial}
//        'update_serial_status'   → branches/{b}/serials/{dateKey}/{queueType}/{serial}
//   3. _handleIncomingMessage() now also queues 'dispense_completed'
//      events that arrive over LAN (from dispenser clients).
//   4. queueType is validated and defaults to 'zakat' before the write
//      so we never write to path 'null'.
//   All UI logic (clients panel, stats, log) unchanged.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../realtime/lan_server.dart';
import '../config/constants.dart';
import '../utils/network_utils.dart';
import '../services/local_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Connected client model
// ─────────────────────────────────────────────────────────────────────────────
class ConnectedClient {
  final String socketId;
  final String role;
  final String branchId;
  final String? clientId;
  final String? username;
  final DateTime connectedAt;
  bool isActive;

  ConnectedClient({
    required this.socketId,
    required this.role,
    required this.branchId,
    this.clientId,
    this.username,
    required this.connectedAt,
    this.isActive = true,
  });

  IconData get icon {
    switch (role.toLowerCase()) {
      case 'receptionist': return Icons.person_pin_circle;
      case 'doctor':       return Icons.local_hospital;
      case 'dispenser':
      case 'pharmacist':   return Icons.medication;
      case 'server':       return Icons.dns;
      default:             return Icons.devices;
    }
  }

  Color get color {
    switch (role.toLowerCase()) {
      case 'receptionist': return const Color(0xFF2196F3);
      case 'doctor':       return const Color(0xFF4CAF50);
      case 'dispenser':
      case 'pharmacist':   return const Color(0xFFFF9800);
      case 'server':       return const Color(0xFF9C27B0);
      default:             return const Color(0xFF607D8B);
    }
  }

  String get displayName {
    final roleLabel = role[0].toUpperCase() + role.substring(1);
    if (username != null &&
        username!.isNotEmpty &&
        username!.toLowerCase() != role.toLowerCase()) {
      return '$username ($roleLabel)';
    }
    return roleLabel;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────
class ServerDashboardWithSync extends StatefulWidget {
  final String branchId;
  final bool autoAuthenticate;

  const ServerDashboardWithSync({
    super.key,
    required this.branchId,
    this.autoAuthenticate = true,
  });

  @override
  State<ServerDashboardWithSync> createState() =>
      _ServerDashboardWithSyncState();
}

class _ServerDashboardWithSyncState
    extends State<ServerDashboardWithSync> {
  bool _isAuthenticated = false;
  bool _isRunning       = false;
  String? _serverIp;
  DateTime? _startTime;
  final List<String> _activityLog = [];

  bool _isOnline     = false;
  int  _syncQueueSize = 0;
  int  _syncedToday   = 0;
  int  _syncErrors    = 0;
  DateTime? _lastSyncTime;

  final Map<String, ConnectedClient> _connectedClients = {};

  Timer? _updateTimer;
  Timer? _syncTimer;
  Timer? _udpBroadcastTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  ServerSyncManager? _syncManager;
  LanServer? _server;

  @override
  void initState() {
    super.initState();

    if (widget.autoAuthenticate) {
      setState(() => _isAuthenticated = true);
      _initializeSync();
      _detectIp();
      _checkConnectivity();
      _autoStartServer();
    } else {
      final box = Hive.box('app_settings');
      final savedAuth = box.get('server_authenticated', defaultValue: false);
      if (savedAuth == true) {
        setState(() => _isAuthenticated = true);
        _initializeSync();
        _detectIp();
        _checkConnectivity();
        _autoStartServer();
      }
    }

    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      setState(() => _isOnline = online);
      if (online && _syncManager != null) {
        _addLog('📡 Back online - triggering sync');
        _syncManager!.triggerSync();
      } else if (!online) {
        _addLog('⚠️ Offline - queuing changes');
      }
    });

    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRunning) {
        setState(() {
          _syncQueueSize = _syncManager?.queueSize ?? 0;
        });
      }
    });
  }

  Future<void> _openFirewallPort() async {
    if (!Platform.isWindows) return;
    try {
      final port = AppNetwork.websocketPort;
      await Process.run('netsh', [
        'advfirewall', 'firewall', 'add', 'rule',
        'name=GMWF_LAN_Server',
        'dir=in',
        'action=allow',
        'protocol=TCP',
        'localport=$port',
      ]);
      _addLog('🔓 Firewall rule added for port $port');
    } catch (e) {
      _addLog('⚠️ Could not add firewall rule automatically.');
    }
  }

  Future<void> _autoStartServer() async {
    await Future.delayed(const Duration(seconds: 1));
    if (mounted && !_isRunning) await _startServer();
  }

  Future<void> _initializeSync() async {
    try {
      if (!Hive.isBoxOpen(LocalStorageService.syncBox)) {
        await Hive.openBox(LocalStorageService.syncBox);
      }
    } catch (e) {
      debugPrint('Hive init error: $e');
    }
    if (mounted) {
      setState(() {
        _syncQueueSize =
            Hive.box(LocalStorageService.syncBox).length;
      });
    }
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = results.any((r) => r != ConnectivityResult.none);
    });
  }

  Future<void> _detectIp() async {
    final ip = await getPrimaryLanIp();
    setState(() => _serverIp = ip);
  }

  Future<void> _startServer() async {
    if (_serverIp == null) {
      _showError('Could not detect IP address');
      return;
    }

    await _openFirewallPort();

    try {
      _server = LanServer(port: AppNetwork.websocketPort);

      _server!.onClientConnected = (socketId, info) {
        setState(() {
          _connectedClients[socketId] = ConnectedClient(
            socketId:    socketId,
            role:        info['role']     as String? ?? 'unknown',
            branchId:    info['branchId'] as String? ?? widget.branchId,
            clientId:    info['clientId'] as String?,
            username:    info['username'] as String?,
            connectedAt: DateTime.now(),
          );
        });
        final name = info['username'] ?? info['role'];
        _addLog('🟢 Connected: $name (${info['role']} / ${info['branchId']})');
      };

      _server!.onClientDisconnected = (socketId) {
        final client = _connectedClients[socketId];
        setState(() => _connectedClients.remove(socketId));
        if (client != null) {
          _addLog('🔴 Disconnected: ${client.displayName}');
        }
      };

      _server!.onMessageReceived = (message) {
        _addLog('📨 ${message['event_type']}: '
            'from ${message['_senderUsername'] ?? message['_senderRole']}');
      };

      await _server!.start(_serverIp);

      _syncManager = ServerSyncManager(
        branchId: widget.branchId,
        server:   _server!,
        onSyncComplete: (count) {
          setState(() {
            _syncedToday  += count;
            _lastSyncTime  = DateTime.now();
          });
          _addLog('✅ Synced $count items to Firestore');
        },
        onSyncError: (error) {
          setState(() => _syncErrors++);
          _addLog('❌ Sync error: $error');
        },
        onMessageReceived: (message) {
          _addLog('📨 ${message['event_type']}: '
              '${message['_senderUsername'] ?? message['_senderRole']}');
        },
      );

      await _syncManager!.start();

      setState(() {
        _isRunning = true;
        _startTime = DateTime.now();
      });

      _addLog('✅ Server started on $_serverIp:${AppNetwork.websocketPort}');
      _addLog('✅ Sync bridge active');
      _showSuccess('Server is running!');
      _startUdpBroadcast();
    } catch (e) {
      _showError('Failed to start: $e');
      _addLog('❌ Start failed: $e');
    }
  }

  void _startUdpBroadcast() {
    _udpBroadcastTimer?.cancel();
    _udpBroadcastTimer =
        Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isRunning) return;
      try {
        final socket =
            await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        final message = utf8.encode(
            '${AppNetwork.udpMessagePrefix}'
            '$_serverIp:${AppNetwork.websocketPort}');
        socket.send(message, InternetAddress('255.255.255.255'),
            AppNetwork.udpBroadcastPort);
        socket.close();
      } catch (e) {
        // Silent fail
      }
    });
  }

  Future<void> _stopServer() async {
    try {
      _udpBroadcastTimer?.cancel();
      await _syncManager?.stop();
      await _server?.stop();
      setState(() {
        _isRunning  = false;
        _syncManager = null;
        _server      = null;
        _connectedClients.clear();
      });
      _addLog('🛑 Server stopped');
      _showSuccess('Server stopped');
    } catch (e) {
      _showError('Failed to stop: $e');
    }
  }

  Future<void> _manualSync() async {
    if (_syncManager == null) { _showError('Server not running'); return; }
    _addLog('🔄 Manual sync triggered');
    await _syncManager!.triggerSync();
  }

  void _addLog(String message) {
    setState(() {
      _activityLog.insert(
          0, '${_formatTime(DateTime.now())} - $message');
      if (_activityLog.length > 100) _activityLog.removeLast();
    });
  }

  String _formatTime(DateTime t) => DateFormat('HH:mm:ss').format(t);

  String _formatUptime() {
    if (_startTime == null) return '0s';
    final uptime  = DateTime.now().difference(_startTime!);
    final hours   = uptime.inHours;
    final minutes = uptime.inMinutes % 60;
    final seconds = uptime.inSeconds % 60;
    if (hours > 0)   return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.logout, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          const Text('Confirm Logout'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to logout?'),
            if (_isRunning) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                        'Server is currently running and will be stopped.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
    if (confirmed == true) await _logout();
  }

  Future<void> _logout() async {
    if (_isRunning) await _stopServer();
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint('Logout error: $e');
      _showError('Failed to logout: $e');
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _syncTimer?.cancel();
    _udpBroadcastTimer?.cancel();
    _connectivitySub?.cancel();
    _syncManager?.stop();
    _server?.stop();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) return _buildNotAuthenticatedMessage();

    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.dns, size: 28),
          SizedBox(width: 12),
          Text('GMWF Server Dashboard'),
        ]),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isOnline
                  ? Colors.blue.shade100 : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _isOnline ? Icons.cloud : Icons.cloud_off,
                size: 16,
                color: _isOnline
                    ? Colors.blue.shade700 : Colors.orange.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                _isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _isOnline
                      ? Colors.blue.shade900 : Colors.orange.shade900,
                ),
              ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _isRunning ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white)),
              const SizedBox(width: 8),
              Text(_isRunning ? 'RUNNING' : 'STOPPED',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: _isRunning ? _buildRunningView() : _buildStoppedView(),
    );
  }

  Widget _buildConnectedClientsPanel() {
    const roleOrder = [
      'receptionist', 'doctor', 'dispenser', 'pharmacist', 'server'
    ];

    final roleCounts = <String, int>{};
    for (final c in _connectedClients.values) {
      roleCounts[c.role] = (roleCounts[c.role] ?? 0) + 1;
    }

    final sortedClients = _connectedClients.values.toList()
      ..sort((a, b) {
        final ai = roleOrder.indexOf(a.role);
        final bi = roleOrder.indexOf(b.role);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.people_alt,
                  color: Colors.indigo.shade700, size: 22),
              const SizedBox(width: 10),
              Text(
                'Connected Clients',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade900,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _connectedClients.isEmpty
                      ? Colors.grey.shade200 : Colors.indigo.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_connectedClients.length} connected',
                  style: TextStyle(
                    color: _connectedClients.isEmpty
                        ? Colors.grey.shade600 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _buildRoleSummaryChip('Receptionist',
                  roleCounts['receptionist'] ?? 0,
                  const Color(0xFF2196F3), Icons.person_pin_circle),
              const SizedBox(width: 8),
              _buildRoleSummaryChip('Doctor',
                  roleCounts['doctor'] ?? 0,
                  const Color(0xFF4CAF50), Icons.local_hospital),
              const SizedBox(width: 8),
              _buildRoleSummaryChip(
                'Dispenser',
                (roleCounts['dispenser'] ?? 0) +
                    (roleCounts['pharmacist'] ?? 0),
                const Color(0xFFFF9800), Icons.medication),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            if (sortedClients.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(children: [
                    Icon(Icons.wifi_off,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('No clients connected',
                        style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    Text(
                      'Clients will appear here when they connect',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ]),
                ),
              )
            else
              ...sortedClients.map((client) => _buildClientRow(client)),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSummaryChip(
      String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: count > 0
            ? color.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: count > 0
              ? color.withOpacity(0.4) : Colors.grey.shade300,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon,
            size: 16,
            color: count > 0 ? color : Colors.grey.shade400),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: count > 0
                ? color.withOpacity(0.9) : Colors.grey.shade400,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: count > 0 ? color : Colors.grey.shade300,
          ),
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildClientRow(ConnectedClient client) {
    final duration  = DateTime.now().difference(client.connectedAt);
    final connected = duration.inMinutes > 0
        ? '${duration.inMinutes}m ago'
        : '${duration.inSeconds}s ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: client.color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: client.color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: client.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(client.icon, color: client.color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                client.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: client.color.withOpacity(0.85),
                  fontSize: 14,
                ),
              ),
              Text(
                'Branch: ${client.branchId}',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.green)),
              const SizedBox(width: 5),
              const Text('Online',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 4),
          Text('Connected $connected',
              style: TextStyle(
                  fontSize: 10, color: Colors.grey.shade400)),
        ]),
      ]),
    );
  }

  Widget _buildFirewallBanner() {
    if (!Platform.isWindows) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(children: [
        Icon(Icons.security, color: Colors.amber.shade700, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Windows Firewall',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                      fontSize: 13)),
              Text(
                'If clients cannot connect, run this in PowerShell (Admin):\n'
                'netsh advfirewall firewall add rule name="GMWF_LAN" '
                'dir=in action=allow protocol=TCP '
                'localport=${AppNetwork.websocketPort}',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber.shade800,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _openFirewallPort,
          style: TextButton.styleFrom(
              foregroundColor: Colors.amber.shade800),
          child: const Text('Auto-Fix', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _buildNotAuthenticatedMessage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Dashboard'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline,
                      size: 80, color: Colors.orange.shade700),
                  const SizedBox(height: 24),
                  Text('Authentication Required',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text(
                    'Please log in with a Server role account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go Back'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoppedView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(32),
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dns_outlined,
                    size: 80, color: Colors.indigo.shade700),
                const SizedBox(height: 24),
                Text('GMWF Server Dashboard',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Branch: ${widget.branchId}',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 32),
                if (_serverIp != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      Text('Server IP',
                          style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12)),
                      const SizedBox(height: 4),
                      SelectableText(_serverIp!,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  const SizedBox(height: 32),
                ],
                if (Platform.isWindows) ...[_buildFirewallBanner()],
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _startServer,
                    icon: const Icon(Icons.play_arrow, size: 28),
                    label: const Text('Start Server',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRunningView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Platform.isWindows && _connectedClients.isEmpty)
            _buildFirewallBanner(),

          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2,
            children: [
              _buildStatCard('Server IP', _serverIp ?? 'Unknown',
                  Icons.wifi, Colors.blue),
              _buildStatCard('Uptime', _formatUptime(),
                  Icons.timer, Colors.green),
              _buildStatCard(
                'Clients',
                _connectedClients.length.toString(),
                Icons.people,
                _connectedClients.isEmpty ? Colors.grey : Colors.indigo,
              ),
              _buildStatCard('Synced Today', _syncedToday.toString(),
                  Icons.cloud_done, Colors.purple),
            ],
          ),

          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.info_outline,
                              size: 22, color: Colors.green.shade700),
                          const SizedBox(width: 10),
                          Text('Share with clients',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green.shade900)),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _isOnline ? _manualSync : null,
                            icon: const Icon(Icons.sync, size: 18),
                            label: const Text('Sync Now'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.green.shade200),
                          ),
                          child: SelectableText(
                            'IP: $_serverIp\n'
                            'Port: ${AppNetwork.websocketPort}\n'
                            'Branch: ${widget.branchId}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _buildConnectedClientsPanel(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Row(children: [
            Text('Activity Log',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _stopServer,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Server'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white),
            ),
          ]),
          const SizedBox(height: 16),
          Card(
            child: _activityLog.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No activity yet')))
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _activityLog.length > 30
                        ? 30 : _activityLog.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      dense: true,
                      title: Text(_activityLog[index],
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 24),
              const Spacer(),
              Flexible(
                child: Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            ]),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ServerSyncManager
// ─────────────────────────────────────────────────────────────────────────────
class ServerSyncManager {
  final String branchId;
  final LanServer server;
  final Function(int) onSyncComplete;
  final Function(String) onSyncError;
  final Function(Map<String, dynamic>) onMessageReceived;

  Timer? _syncTimer;
  bool _isSyncing = false;

  // Valid queue type values — used as a guard before writing to Firestore
  // so we never write to a path like serials/{dateKey}/null/{serial}.
  static const _validQueueTypes = {'zakat', 'non-zakat', 'gmwf'};

  ServerSyncManager({
    required this.branchId,
    required this.server,
    required this.onSyncComplete,
    required this.onSyncError,
    required this.onMessageReceived,
  });

  int get queueSize {
    try {
      return Hive.box(LocalStorageService.syncBox).length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> start() async {
    debugPrint('ServerSyncManager: Starting for branch $branchId');
    server.onMessageReceived = _handleIncomingMessage;
    _syncTimer =
        Timer.periodic(const Duration(seconds: 10), (_) { triggerSync(); });
    await triggerSync();
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    final eventType = message['event_type'] as String?;
    if (eventType == null) return;
    onMessageReceived(message);
    _queueForSync(message);
  }

  void _queueForSync(Map<String, dynamic> message) {
    final eventType = message['event_type'] as String?;
    // Skip internal protocol messages and unknowns with no sync value.
    if (eventType == null ||
        eventType == 'ping' ||
        eventType == 'pong' ||
        eventType == 'identify' ||
        eventType == 'identified' ||
        eventType == 'client_count_update') return;

    try {
      final box = Hive.box(LocalStorageService.syncBox);
      final key =
          'sync_${DateTime.now().millisecondsSinceEpoch}_$eventType';

      // For dispense_completed arriving over LAN we split it into the
      // two canonical sync jobs that _syncToFirestore() knows how to handle.
      if (eventType == 'dispense_completed') {
        final data = (message['data'] as Map<String, dynamic>?) ??
            Map<String, dynamic>.from(message);
        final serial    = data['serial']?.toString() ?? '';
        final dateKey   = data['dateKey']?.toString() ?? '';
        final queueType = _resolveQueueType(data['queueType']);
        final bId       = (data['branchId'] as String?)?.trim() ?? branchId;

        if (serial.isNotEmpty && dateKey.isNotEmpty) {
          // Write A: dispensary record
          box.put('${key}_dispensary', {
            'type':      'save_dispensary_record',
            'branchId':  bId,
            'dateKey':   dateKey,
            'serial':    serial,
            'data':      data,
            'createdAt': DateTime.now().toIso8601String(),
            'attempts':  0,
            'status':    'pending',
          });
          // Write B: serial status patch
          box.put('${key}_serial', {
            'type':      'update_serial_status',
            'branchId':  bId,
            'dateKey':   dateKey,
            'queueType': queueType,
            'serial':    serial,
            'data':      {
              'dispenseStatus': data['dispenseStatus'] ?? 'dispensed',
              'dispensedAt':    data['dispensedAt'],
              'dispensedBy':    data['dispensedBy'],
              'serial':         serial,
              'dateKey':        dateKey,
              'queueType':      queueType,
              'branchId':       bId,
            },
            'createdAt': DateTime.now().toIso8601String(),
            'attempts':  0,
            'status':    'pending',
          });
        }
        return;
      }

      // All other event types
      box.put(key, {
        'type':      _mapEventTypeToSyncType(eventType),
        'branchId':  branchId,
        'data':      message['data'] ?? message,
        'createdAt': DateTime.now().toIso8601String(),
        'attempts':  0,
        'status':    'pending',
      });
      debugPrint('Queued for sync: $eventType (queue: ${box.length})');
    } catch (e) {
      debugPrint('Error queuing message: $e');
    }
  }

  // ── Map event type → sync type ─────────────────────────────────────────────
  String _mapEventTypeToSyncType(String eventType) {
    switch (eventType) {
      case 'save_entry':
      case 'token_created':
        return 'save_entry';
      case 'save_prescription':
      case 'prescription_created':
        return 'save_prescription';
      case 'save_patient':
        return 'save_patient';
      case 'delete_patient':
        return 'delete_patient';
      // ── Dispense writes ──────────────────────────────────────────────────
      case 'save_dispensary_record':
        return 'save_dispensary_record';
      case 'update_serial_status':
        return 'update_serial_status';
      // dispense_completed is split above before reaching here
      default:
        return eventType;
    }
  }

  /// Normalise and validate queueType; falls back to 'zakat'.
  String _resolveQueueType(dynamic raw) {
    final s = raw?.toString().toLowerCase().trim() ?? '';
    return _validQueueTypes.contains(s) ? s : 'zakat';
  }

  Future<void> triggerSync() async {
    if (_isSyncing) return;
    final box = Hive.box(LocalStorageService.syncBox);
    if (box.isEmpty) return;

    _isSyncing = true;
    int syncedCount = 0;

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.any((r) => r != ConnectivityResult.none)) {
        _isSyncing = false;
        return;
      }

      final keys = box.keys.toList();
      for (final key in keys) {
        try {
          final item = box.get(key);
          if (item == null || item is! Map) {
            await box.delete(key);
            continue;
          }
          final syncItem = Map<String, dynamic>.from(item);
          final type     = syncItem['type'] as String?;
          final data     = syncItem['data'];
          if (type == null || data == null) {
            await box.delete(key);
            continue;
          }

          // Prefer top-level routing fields on the sync item (set by
          // _queueForSync) over fields embedded in data, so we always
          // have the right dateKey / queueType / serial even if the data
          // map was assembled differently.
          final resolvedBranchId =
              (syncItem['branchId'] as String?)?.trim().isNotEmpty == true
                  ? syncItem['branchId'] as String
                  : branchId;
          final resolvedDateKey =
              (syncItem['dateKey'] as String?)?.trim() ?? '';
          final resolvedQueueType =
              _resolveQueueType(syncItem['queueType']);
          final resolvedSerial =
              (syncItem['serial'] as String?)?.trim() ?? '';

          final dataMap = data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};

          await _syncToFirestore(
            type:       type,
            data:       dataMap,
            branchId:   resolvedBranchId,
            dateKey:    resolvedDateKey,
            queueType:  resolvedQueueType,
            serial:     resolvedSerial,
          );
          await box.delete(key);
          syncedCount++;
        } catch (e) {
          final item = box.get(key);
          if (item is Map) {
            final updated = Map<String, dynamic>.from(item);
            updated['attempts'] =
                (updated['attempts'] as int? ?? 0) + 1;
            updated['lastError'] = e.toString();
            if (updated['attempts'] >= 5) {
              debugPrint(
                  'Dropping sync item after 5 failures: ${updated['type']} — $e');
              await box.delete(key);
            } else {
              await box.put(key, updated);
            }
          }
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (syncedCount > 0) onSyncComplete(syncedCount);
    } catch (e) {
      onSyncError(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  // ── Firestore writer ───────────────────────────────────────────────────────
  Future<void> _syncToFirestore({
    required String type,
    required Map<String, dynamic> data,
    required String branchId,
    required String dateKey,
    required String queueType,
    required String serial,
  }) async {
    final db        = FirebaseFirestore.instance;
    final cleanData = _removeFieldValues(data);

    // Fallback: if top-level keys are empty, try to pull from cleanData.
    final effectiveDateKey  = dateKey.isNotEmpty
        ? dateKey  : (cleanData['dateKey']  as String? ?? '');
    final effectiveSerial   = serial.isNotEmpty
        ? serial   : (cleanData['serial']   as String? ?? '');
    final effectiveQueueType = _validQueueTypes.contains(queueType)
        ? queueType
        : _resolveQueueType(cleanData['queueType']);
    final effectiveBranchId = branchId.isNotEmpty ? branchId : this.branchId;

    switch (type) {
      // ── Token entry ──────────────────────────────────────────────────────
      case 'save_entry':
        final s  = effectiveSerial.isNotEmpty
            ? effectiveSerial
            : (cleanData['serial'] as String? ?? '');
        final dk = effectiveDateKey.isNotEmpty
            ? effectiveDateKey
            : (cleanData['dateKey'] as String? ?? '');
        final qt = effectiveQueueType;
        if (s.isEmpty || dk.isEmpty) {
          throw Exception('save_entry: missing serial ($s) or dateKey ($dk)');
        }
        await db
            .collection('branches').doc(effectiveBranchId)
            .collection('serials').doc(dk)
            .collection(qt).doc(s)
            .set(cleanData, SetOptions(merge: true));
        debugPrint('✅ save_entry → serials/$dk/$qt/$s');
        break;

      // ── Prescription ─────────────────────────────────────────────────────
      case 'save_prescription':
        final s = effectiveSerial.isNotEmpty
            ? effectiveSerial
            : (cleanData['serial'] as String? ?? cleanData['id'] as String? ?? '');
        final cnic = (cleanData['patientCnic'] as String? ??
                cleanData['cnic'] as String? ?? 'unknown')
            .trim();
        if (s.isEmpty) throw Exception('save_prescription: missing serial');
        await db
            .collection('branches').doc(effectiveBranchId)
            .collection('prescriptions').doc(cnic)
            .collection('prescriptions').doc(s)
            .set(cleanData, SetOptions(merge: true));
        debugPrint('✅ save_prescription → prescriptions/$cnic/$s');
        break;

      // ── Patient ──────────────────────────────────────────────────────────
      case 'save_patient':
        final pid = (cleanData['patientId'] as String? ?? '').trim();
        if (pid.isEmpty) throw Exception('save_patient: missing patientId');
        await db
            .collection('branches').doc(effectiveBranchId)
            .collection('patients').doc(pid)
            .set(cleanData, SetOptions(merge: true));
        debugPrint('✅ save_patient → patients/$pid');
        break;

      // ── Dispensary record ─────────────────────────────────────────────────
      // Path: branches/{branchId}/dispensary/{dateKey}/{dateKey}/{serial}
      case 'save_dispensary_record':
        final s  = effectiveSerial.isNotEmpty
            ? effectiveSerial
            : (cleanData['serial'] as String? ?? '');
        final dk = effectiveDateKey.isNotEmpty
            ? effectiveDateKey
            : (cleanData['dateKey'] as String? ?? '');
        if (s.isEmpty || dk.isEmpty) {
          throw Exception(
              'save_dispensary_record: missing serial ($s) or dateKey ($dk)');
        }
        // Remove the routing-only fields before writing to Firestore.
        cleanData.remove('dateKey');
        await db
            .collection('branches').doc(effectiveBranchId)
            .collection('dispensary').doc(dk)
            .collection(dk).doc(s)
            .set(cleanData, SetOptions(merge: true));
        debugPrint('✅ save_dispensary_record → dispensary/$dk/$dk/$s');
        break;

      // ── Serial status patch ───────────────────────────────────────────────
      // Path: branches/{branchId}/serials/{dateKey}/{queueType}/{serial}
      case 'update_serial_status':
        final s  = effectiveSerial.isNotEmpty
            ? effectiveSerial
            : (cleanData['serial'] as String? ?? '');
        final dk = effectiveDateKey.isNotEmpty
            ? effectiveDateKey
            : (cleanData['dateKey'] as String? ?? '');
        final qt = effectiveQueueType;
        if (s.isEmpty || dk.isEmpty) {
          throw Exception(
              'update_serial_status: missing serial ($s) or dateKey ($dk)');
        }
        // Only write the status fields — don't overwrite the full serial doc.
        final statusPatch = {
          'dispenseStatus': cleanData['dispenseStatus'] ?? 'dispensed',
          if (cleanData['dispensedAt'] != null)
            'dispensedAt': cleanData['dispensedAt'],
          if (cleanData['dispensedBy'] != null)
            'dispensedBy': cleanData['dispensedBy'],
        };
        await db
            .collection('branches').doc(effectiveBranchId)
            .collection('serials').doc(dk)
            .collection(qt).doc(s)
            .set(statusPatch, SetOptions(merge: true));
        debugPrint('✅ update_serial_status → serials/$dk/$qt/$s');
        break;

      // ── Delete patient ───────────────────────────────────────────────────
      case 'delete_patient':
        final pid = (cleanData['patientId'] as String? ?? '').trim();
        if (pid.isEmpty) throw Exception('delete_patient: missing patientId');
        await db
            .collection('branches').doc(effectiveBranchId)
            .collection('patients').doc(pid)
            .delete();
        debugPrint('✅ delete_patient → patients/$pid');
        break;

      default:
        debugPrint('⚠️ Unknown sync type "$type" — skipping');
    }
  }

  Map<String, dynamic> _removeFieldValues(Map<String, dynamic> data) {
    final cleaned = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value.runtimeType.toString().contains('FieldValue')) {
        if (['createdAt', 'updatedAt', 'timestamp'].contains(entry.key)) {
          cleaned[entry.key] = DateTime.now().toIso8601String();
        }
        continue;
      }
      if (value is Map) {
        cleaned[entry.key] =
            _removeFieldValues(Map<String, dynamic>.from(value));
      } else {
        cleaned[entry.key] = value;
      }
    }
    return cleaned;
  }

  Future<void> stop() async {
    _syncTimer?.cancel();
    debugPrint('ServerSyncManager: Stopped');
  }
}