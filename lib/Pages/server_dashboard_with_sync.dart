// lib/pages/server_dashboard_with_sync.dart
// FIXED:
// 1. Connected clients panel showing receptionist, doctor, dispenser with live status
// 2. Firewall port opening via process call on Windows
// 3. Client tracking added to LanServer integration

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

// ─────────────────────────────────────────────
// Connected client model
// ─────────────────────────────────────────────
class ConnectedClient {
  final String socketId;
  final String role;
  final String branchId;
  final String? clientId;
  final DateTime connectedAt;
  bool isActive;

  ConnectedClient({
    required this.socketId,
    required this.role,
    required this.branchId,
    this.clientId,
    required this.connectedAt,
    this.isActive = true,
  });

  IconData get icon {
    switch (role.toLowerCase()) {
      case 'receptionist':
        return Icons.person_pin_circle;
      case 'doctor':
        return Icons.local_hospital;
      case 'dispenser':
      case 'pharmacist':
        return Icons.medication;
      case 'server':
        return Icons.dns;
      default:
        return Icons.devices;
    }
  }

  Color get color {
    switch (role.toLowerCase()) {
      case 'receptionist':
        return const Color(0xFF2196F3);
      case 'doctor':
        return const Color(0xFF4CAF50);
      case 'dispenser':
      case 'pharmacist':
        return const Color(0xFFFF9800);
      case 'server':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF607D8B);
    }
  }

  String get displayName {
    final base = role[0].toUpperCase() + role.substring(1);
    return base;
  }
}

// ─────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────
class ServerDashboardWithSync extends StatefulWidget {
  final String branchId;
  final bool autoAuthenticate;

  const ServerDashboardWithSync({
    super.key,
    required this.branchId,
    this.autoAuthenticate = true,
  });

  @override
  State<ServerDashboardWithSync> createState() => _ServerDashboardWithSyncState();
}

class _ServerDashboardWithSyncState extends State<ServerDashboardWithSync> {
  bool _isAuthenticated = false;
  bool _isRunning = false;
  String? _serverIp;
  DateTime? _startTime;
  final List<String> _activityLog = [];

  bool _isOnline = false;
  int _syncQueueSize = 0;
  int _syncedToday = 0;
  int _syncErrors = 0;
  DateTime? _lastSyncTime;

  // Connected clients tracking
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

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
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

  // ── Firewall helper (Windows only) ─────────────────────────────────────────
  Future<void> _openFirewallPort() async {
    if (!Platform.isWindows) return;
    try {
      final port = AppNetwork.websocketPort;
      // Add inbound rule via netsh (requires admin; silently fails if not admin)
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
      _addLog('⚠️ Could not add firewall rule automatically. Run as Administrator or add manually.');
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  Future<void> _autoStartServer() async {
    await Future.delayed(const Duration(seconds: 1));
    if (mounted && !_isRunning) {
      await _startServer();
    }
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
        _syncQueueSize = Hive.box(LocalStorageService.syncBox).length;
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

  // ── Server start/stop ───────────────────────────────────────────────────────
  Future<void> _startServer() async {
    if (_serverIp == null) {
      _showError('Could not detect IP address');
      return;
    }

    // Open firewall port BEFORE binding
    await _openFirewallPort();

    try {
      _server = LanServer(port: AppNetwork.websocketPort);

      // Hook into server events for client tracking
      _server!.onClientConnected = (socketId, info) {
        setState(() {
          _connectedClients[socketId] = ConnectedClient(
            socketId: socketId,
            role: info['role'] as String? ?? 'unknown',
            branchId: info['branchId'] as String? ?? widget.branchId,
            clientId: info['clientId'] as String?,
            connectedAt: DateTime.now(),
          );
        });
        _addLog('🟢 Connected: ${info['role']} (${info['branchId']})');
      };

      _server!.onClientDisconnected = (socketId) {
        final client = _connectedClients[socketId];
        setState(() {
          _connectedClients.remove(socketId);
        });
        if (client != null) {
          _addLog('🔴 Disconnected: ${client.role}');
        }
      };

      _server!.onMessageReceived = (message) {
        _addLog('📨 ${message['event_type']}: from ${message['_senderRole']}');
      };

      await _server!.start(_serverIp);

      _syncManager = ServerSyncManager(
        branchId: widget.branchId,
        server: _server!,
        onSyncComplete: (count) {
          setState(() {
            _syncedToday += count;
            _lastSyncTime = DateTime.now();
          });
          _addLog('✅ Synced $count items to Firestore');
        },
        onSyncError: (error) {
          setState(() => _syncErrors++);
          _addLog('❌ Sync error: $error');
        },
        onMessageReceived: (message) {
          _addLog('📨 ${message['event_type']}: ${message['_senderRole']}');
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
    _udpBroadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isRunning) return;
      try {
        final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        final message = utf8.encode(
            '${AppNetwork.udpMessagePrefix}$_serverIp:${AppNetwork.websocketPort}');
        socket.send(
            message, InternetAddress('255.255.255.255'), AppNetwork.udpBroadcastPort);
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
        _isRunning = false;
        _syncManager = null;
        _server = null;
        _connectedClients.clear();
      });
      _addLog('🛑 Server stopped');
      _showSuccess('Server stopped');
    } catch (e) {
      _showError('Failed to stop: $e');
    }
  }

  Future<void> _manualSync() async {
    if (_syncManager == null) {
      _showError('Server not running');
      return;
    }
    _addLog('🔄 Manual sync triggered');
    await _syncManager!.triggerSync();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  void _addLog(String message) {
    setState(() {
      _activityLog.insert(0, '${_formatTime(DateTime.now())} - $message');
      if (_activityLog.length > 100) _activityLog.removeLast();
    });
  }

  String _formatTime(DateTime time) => DateFormat('HH:mm:ss').format(time);

  String _formatUptime() {
    if (_startTime == null) return '0s';
    final uptime = DateTime.now().difference(_startTime!);
    final hours = uptime.inHours;
    final minutes = uptime.inMinutes % 60;
    final seconds = uptime.inSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
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

  // ── Build ────────────────────────────────────────────────────────────────────
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
          // Online indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isOnline ? Colors.blue.shade100 : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                _isOnline ? Icons.cloud : Icons.cloud_off,
                size: 16,
                color: _isOnline ? Colors.blue.shade700 : Colors.orange.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                _isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _isOnline ? Colors.blue.shade900 : Colors.orange.shade900,
                ),
              ),
            ]),
          ),
          // Running indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  // ── Connected Clients Panel ──────────────────────────────────────────────────
  Widget _buildConnectedClientsPanel() {
    // Role order for display
    const roleOrder = ['receptionist', 'doctor', 'dispenser', 'pharmacist', 'server'];

    // Count by role
    final roleCounts = <String, int>{};
    for (final c in _connectedClients.values) {
      roleCounts[c.role] = (roleCounts[c.role] ?? 0) + 1;
    }

    // Sorted client list
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
            // Header
            Row(children: [
              Icon(Icons.people_alt, color: Colors.indigo.shade700, size: 22),
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
              // Total badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _connectedClients.isEmpty
                      ? Colors.grey.shade200
                      : Colors.indigo.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_connectedClients.length} connected',
                  style: TextStyle(
                    color: _connectedClients.isEmpty
                        ? Colors.grey.shade600
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Role summary row
            Row(
              children: [
                _buildRoleSummaryChip(
                  'Receptionist',
                  roleCounts['receptionist'] ?? 0,
                  const Color(0xFF2196F3),
                  Icons.person_pin_circle,
                ),
                const SizedBox(width: 8),
                _buildRoleSummaryChip(
                  'Doctor',
                  roleCounts['doctor'] ?? 0,
                  const Color(0xFF4CAF50),
                  Icons.local_hospital,
                ),
                const SizedBox(width: 8),
                _buildRoleSummaryChip(
                  'Dispenser',
                  (roleCounts['dispenser'] ?? 0) +
                      (roleCounts['pharmacist'] ?? 0),
                  const Color(0xFFFF9800),
                  Icons.medication,
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Client list
            if (sortedClients.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(children: [
                    Icon(Icons.wifi_off, size: 40, color: Colors.grey.shade400),
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
        color: count > 0 ? color.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: count > 0 ? color.withOpacity(0.4) : Colors.grey.shade300,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: count > 0 ? color : Colors.grey.shade400),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: count > 0 ? color.withOpacity(0.9) : Colors.grey.shade400,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 20,
          height: 20,
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
    final duration =
        DateTime.now().difference(client.connectedAt);
    final connected = duration.inMinutes > 0
        ? '${duration.inMinutes}m ago'
        : '${duration.inSeconds}s ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: client.color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: client.color.withOpacity(0.2)),
      ),
      child: Row(children: [
        // Role icon
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: client.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(client.icon, color: client.color, size: 20),
        ),
        const SizedBox(width: 12),
        // Role + branch
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
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        // Connected time
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
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
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ]),
      ]),
    );
  }

  // ── Firewall Warning Banner ──────────────────────────────────────────────────
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
                'dir=in action=allow protocol=TCP localport=${AppNetwork.websocketPort}',
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
          style: TextButton.styleFrom(foregroundColor: Colors.amber.shade800),
          child: const Text('Auto-Fix', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  // ── Views ────────────────────────────────────────────────────────────────────
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
                  Icon(Icons.lock_outline, size: 80, color: Colors.orange.shade700),
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
                Icon(Icons.dns_outlined, size: 80, color: Colors.indigo.shade700),
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
                              color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 4),
                      SelectableText(_serverIp!,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  const SizedBox(height: 32),
                ],
                if (Platform.isWindows) ...[
                  _buildFirewallBanner(),
                ],
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
          // Firewall banner at top when running on Windows
          if (Platform.isWindows && _connectedClients.isEmpty)
            _buildFirewallBanner(),

          // Stat cards
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2,
            children: [
              _buildStatCard('Server IP', _serverIp ?? 'Unknown', Icons.wifi,
                  Colors.blue),
              _buildStatCard(
                  'Uptime', _formatUptime(), Icons.timer, Colors.green),
              _buildStatCard(
                'Clients',
                _connectedClients.length.toString(),
                Icons.people,
                _connectedClients.isEmpty ? Colors.grey : Colors.indigo,
              ),
              _buildStatCard(
                'Synced Today',
                _syncedToday.toString(),
                Icons.cloud_done,
                Colors.purple,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Two-column layout: connection info + clients
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection info card
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
                            border:
                                Border.all(color: Colors.green.shade200),
                          ),
                          child: SelectableText(
                            'IP: $_serverIp\nPort: ${AppNetwork.websocketPort}\nBranch: ${widget.branchId}',
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

              // Connected clients panel
              Expanded(
                flex: 3,
                child: _buildConnectedClientsPanel(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Activity Log
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
                    itemCount:
                        _activityLog.length > 30 ? 30 : _activityLog.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ServerSyncManager (unchanged logic, kept here)
// ─────────────────────────────────────────────
class ServerSyncManager {
  final String branchId;
  final LanServer server;
  final Function(int) onSyncComplete;
  final Function(String) onSyncError;
  final Function(Map<String, dynamic>) onMessageReceived;

  Timer? _syncTimer;
  bool _isSyncing = false;

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
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      triggerSync();
    });
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
    if (eventType == null ||
        eventType == 'ping' ||
        eventType == 'pong' ||
        eventType == 'identify' ||
        eventType == 'identified' ||
        eventType == 'client_count_update') {
      return;
    }
    try {
      final box = Hive.box(LocalStorageService.syncBox);
      final key = 'sync_${DateTime.now().millisecondsSinceEpoch}_$eventType';
      box.put(key, {
        'type': _mapEventTypeToSyncType(eventType),
        'branchId': branchId,
        'data': message['data'] ?? message,
        'createdAt': DateTime.now().toIso8601String(),
        'attempts': 0,
        'status': 'pending',
      });
      debugPrint('Queued for sync: $eventType (queue: ${box.length})');
    } catch (e) {
      debugPrint('Error queuing message: $e');
    }
  }

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
      default:
        return eventType;
    }
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
          final type = syncItem['type'] as String?;
          final data = syncItem['data'] as Map<String, dynamic>?;
          if (type == null || data == null) {
            await box.delete(key);
            continue;
          }
          await _syncToFirestore(type, data);
          await box.delete(key);
          syncedCount++;
        } catch (e) {
          final item = box.get(key);
          if (item is Map) {
            final updated = Map<String, dynamic>.from(item);
            updated['attempts'] = (updated['attempts'] as int? ?? 0) + 1;
            updated['lastError'] = e.toString();
            if (updated['attempts'] >= 5) {
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

  Future<void> _syncToFirestore(String type, Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    final cleanData = _removeFieldValues(data);

    switch (type) {
      case 'save_entry':
        final serial = cleanData['serial'] as String?;
        final dateKey = cleanData['dateKey'] as String?;
        final queueType = cleanData['queueType'] as String? ?? 'zakat';
        if (serial == null || dateKey == null) throw Exception('Missing serial or dateKey');
        await db
            .collection('branches')
            .doc(branchId)
            .collection('serials')
            .doc(dateKey)
            .collection(queueType)
            .doc(serial)
            .set(cleanData, SetOptions(merge: true));
        break;
      case 'save_prescription':
        final serial = cleanData['serial'] as String? ?? cleanData['id'] as String?;
        final patientCnic =
            cleanData['patientCnic'] as String? ?? cleanData['cnic'] as String? ?? 'unknown';
        if (serial == null) throw Exception('Missing prescription serial');
        await db
            .collection('branches')
            .doc(branchId)
            .collection('prescriptions')
            .doc(patientCnic)
            .collection('prescriptions')
            .doc(serial)
            .set(cleanData, SetOptions(merge: true));
        break;
      case 'save_patient':
        final patientId = cleanData['patientId'] as String?;
        if (patientId == null) throw Exception('Missing patientId');
        await db
            .collection('branches')
            .doc(branchId)
            .collection('patients')
            .doc(patientId)
            .set(cleanData, SetOptions(merge: true));
        break;
      default:
        debugPrint('Unknown sync type: $type');
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
        cleaned[entry.key] = _removeFieldValues(Map<String, dynamic>.from(value));
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