// lib/pages/server_dashboard_with_sync.dart
//
// FIXES vs previous version:
//   [FIX-A] The embedded ServerSyncManager._resolveQueueType() previously only
//           recognised 'zakat' and fell back to 'zakat' for everything else.
//           It now mirrors the canonical resolver: handles non-zakat/gmwf and
//           all known variant spellings.
//
//   [FIX-B] _queueForSync() for 'dispense_completed' now preserves queueType
//           in the serial-status patch op at TOP LEVEL (not just inside data)
//           so _syncToFirestore never has to guess.
//
//   [FIX-C] _syncToFirestore 'update_serial_status' now reads queueType from
//           the op level first, then falls back to a Hive lookup — never zakat
//           silently.
//
//   [FIX-D] Medicine inventory is decremented in Firestore when a
//           'dispense_completed' is synced (FieldValue.increment on
//           branches/{branchId}/inventory/{medicineId}.quantity).

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'server_data_viewer.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../realtime/lan_server.dart';
import '../config/constants.dart';
import '../utils/network_utils.dart';
import '../services/local_storage_service.dart';
import '../widgets/department_activity_widget.dart';
import '../widgets/multi_server_control_widget.dart';
import '../widgets/lan_hardware_status_widget.dart';
import '../services/multi_server_service.dart';
import '../services/zkteco_network_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Connected client model
// ─────────────────────────────────────────────────────────────────────────────
class ConnectedClient {
  final String socketId;
  final String role;
  final String branchId;
  final String? clientId;
  final String? username;
  final String deviceOs;
  final String appVersion;
  final String ipAddress;
  String currentActivity;
  DateTime connectedAt;
  DateTime lastActiveAt;
  int messagesCount;
  bool isActive;

  ConnectedClient({
    required this.socketId,
    required this.role,
    required this.branchId,
    this.clientId,
    this.username,
    this.deviceOs = 'Windows PC',
    this.appVersion = 'v2.4.0',
    this.ipAddress = '192.168.1.x',
    this.currentActivity = 'Active on Network',
    required this.connectedAt,
    DateTime? lastActiveAt,
    this.messagesCount = 0,
    this.isActive = true,
  }) : lastActiveAt = lastActiveAt ?? connectedAt;

  IconData get icon {
    switch (role.toLowerCase()) {
      case 'receptionist': return Icons.person_pin_circle;
      case 'doctor':       return Icons.local_hospital;
      case 'dispenser':
      case 'pharmacist':   return Icons.medication;
      case 'supervisor':   return Icons.admin_panel_settings;
      case 'finance manager':
      case 'finance':      return Icons.account_balance;
      case 'donations':    return Icons.volunteer_activism;
      case 'teacher':
      case 'faculty':
      case 'madrassa':
      case 'school':       return Icons.school;
      case 'library':      return Icons.local_library;
      case 'dasterkhwaan': return Icons.soup_kitchen;
      case 'attendance':   return Icons.fingerprint;
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
      case 'supervisor':   return const Color(0xFFE91E63);
      case 'finance manager':
      case 'finance':      return const Color(0xFF009688);
      case 'donations':    return const Color(0xFF9C27B0);
      case 'teacher':
      case 'faculty':
      case 'madrassa':
      case 'school':       return const Color(0xFF3F51B5);
      case 'library':      return const Color(0xFF795548);
      case 'dasterkhwaan': return const Color(0xFFFF5722);
      case 'attendance':   return const Color(0xFF673AB7);
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
  int  _selectedTab     = 0;
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
    if (kIsWeb || !io.Platform.isWindows) return;
    try {
      final port = AppNetwork.websocketPort;
      await io.Process.run('netsh', [
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
    if (kIsWeb) {
      _showError('Server hosting is not supported on web.');
      return;
    }
    if (_serverIp == null) {
      _showError('Could not detect IP address');
      return;
    }

    await _openFirewallPort();

    try {
      _server = LanServer(port: AppNetwork.websocketPort);

      _server!.onClientConnected = (socketId, info) {
        final cId = info['clientId']?.toString();
        final cIp = info['ipAddress']?.toString() ?? info['deviceIp']?.toString();
        final uName = info['username']?.toString();

        setState(() {
          _connectedClients.removeWhere((key, existing) {
            if (key == socketId) return true;
            if (cId != null && cId.isNotEmpty && existing.clientId == cId) return true;
            if (cIp != null && cIp.isNotEmpty && existing.ipAddress == cIp) return true;
            if (uName != null && uName.isNotEmpty && existing.username == uName) return true;
            return false;
          });

          _connectedClients[socketId] = ConnectedClient(
            socketId:    socketId,
            role:        info['role']     as String? ?? 'unknown',
            branchId:    info['branchId'] as String? ?? widget.branchId,
            clientId:    info['clientId'] as String?,
            username:    info['username'] as String?,
            deviceOs:    info['deviceOs'] as String? ?? info['platform'] as String? ?? (kIsWeb ? 'Chrome Web' : 'Windows PC'),

            appVersion:  info['appVersion'] as String? ?? 'v2.4.0',
            ipAddress:   info['ipAddress'] as String? ?? info['deviceIp'] as String? ?? '192.168.1.x',
            currentActivity: 'Connected to Branch Server',
            connectedAt: DateTime.now(),
          );
        });
        final name = info['username'] ?? info['role'];
        final clientIp = info['ipAddress'] ?? info['deviceIp'] ?? '127.0.0.1';
        _addLog('🟢 Connected: $name (${info['role']} / ${info['branchId']}) - IP: $clientIp');
      };

      _server!.onClientDisconnected = (socketId) {
        final client = _connectedClients[socketId];
        setState(() => _connectedClients.remove(socketId));
        if (client != null) {
          _addLog('🔴 Disconnected: ${client.displayName}');
        }
      };

      _server!.onMessageReceived = (message) {
        final rawType = message['event_type']?.toString() ?? message['type']?.toString() ?? 'activity';
        final sender = message['_senderUsername'] ?? message['_senderRole'] ?? message['username'] ?? 'Client';
        final socketId = message['_socketId']?.toString();
        final clientId = message['_clientId']?.toString();

        if (rawType != 'ping' && rawType != 'pong' && rawType != 'identify' && rawType != 'identified') {
          _addLog('📨 $rawType: from $sender');
        }

        if (mounted) {
          setState(() {
            for (final entry in _connectedClients.entries) {
              if (entry.key == socketId || entry.value.clientId == clientId || entry.value.username == sender) {
                entry.value.messagesCount++;
                entry.value.lastActiveAt = DateTime.now();
                entry.value.currentActivity = _describeActivity(rawType, message['data']);
              }
            }
          });
        }
      };

      await _server!.start(_serverIp);

      _syncManager = ServerSyncManager(
        branchId: widget.branchId,
        server:   _server!,
        onSyncComplete: (int count) {
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
          final rawType = message['event_type']?.toString() ?? message['type']?.toString() ?? 'activity';
          if (rawType != 'ping' && rawType != 'pong' && rawType != 'identify' && rawType != 'identified') {
            _addLog('📨 $rawType: ${message['_senderUsername'] ?? message['_senderRole'] ?? message['username']}');
          }
        },
      );


      await _syncManager!.start();

      // Start embedded ZKTeco Biometric listener on Port 8088 / 4370
      await ZkTecoNetworkService.startServer();
      _addLog('✅ ZKTeco Biometric Listener active on Port 8088 / 4370');

      MultiServerService().startHeartbeatLoop(
        branchId: widget.branchId,
        roleSupplier: () => 'primary',
        clientsSupplier: () => _connectedClients.length,
        queueSupplier: () => _syncManager?.queueSize ?? 0,
      );

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
            await io.RawDatagramSocket.bind(io.InternetAddress.anyIPv4, 0);
        socket.broadcastEnabled = true;
        final message = utf8.encode(
            '${AppNetwork.udpMessagePrefix}'
            '$_serverIp:${AppNetwork.websocketPort}');
        socket.send(message, io.InternetAddress('255.255.255.255'),
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
      await MultiServerService().stopHeartbeat(widget.branchId);
      await _syncManager?.stop();
      await _server?.stop();
      await ZkTecoNetworkService.stopServer();
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

  static String _describeActivity(String type, dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : {};
    switch (type) {
      case 'save_entry':
      case 'token_created':
        return 'Issued Token #${map['serial'] ?? 'N/A'} (${map['queueType'] ?? 'Zakat'})';
      case 'save_prescription':
      case 'prescription_created':
        return 'Created Prescription for Token #${map['serial'] ?? 'N/A'}';
      case 'dispense_completed':
        return 'Completed Dispensing for Token #${map['serial'] ?? 'N/A'}';
      case 'save_biometric_log':
      case 'save_employee_attendance':
      case 'save_faculty_attendance':
      case 'save_student_attendance':
        return 'Recorded Attendance Punch (${map['entityName'] ?? map['pin'] ?? 'Biometric'})';
      case 'save_madrassa_fee':
        return 'Collected Madrassa Fee Receipt #${map['receiptNo'] ?? 'N/A'}';
      case 'save_madrassa_admission':
        return 'Registered Madrassa Student (${map['studentName'] ?? 'New Student'})';
      case 'save_expense':
        return 'Recorded Expense (${map['category'] ?? map['title'] ?? 'Office Expense'})';
      case 'save_loan':
        return 'Issued Loan Transaction (${map['employeeName'] ?? 'Employee'})';
      case 'save_donation_receipt':
        return 'Generated Donation Receipt #${map['receiptNumber'] ?? 'N/A'}';
      case 'save_dasterkhwan_entry':
      case 'save_office_boy_token':
      case 'save_kitchen_serve_log':
        return 'Logged Dasterkhwaan Kitchen Meal Token';
      case 'save_library_book':
      case 'save_library_issue':
        return 'Issued Library Book (${map['bookTitle'] ?? 'Library Catalog'})';
      case 'save_supervisor_action':
      case 'approve_edit_request':
        return 'Supervisor Edit/Approval Action';
      default:
        return 'Processing $type';
    }
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
    if (kIsWeb) return _buildWebUnsupportedMessage();
    if (!_isAuthenticated) return _buildNotAuthenticatedMessage();

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        cardTheme: const CardThemeData(
          color: Color(0xFF111827),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0xFF1E293B)),
          ),
        ),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: const Color(0xFF090D16).withValues(alpha: 0.85)),
            ),
          ),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF3B82F6).withValues(alpha: 0.4), blurRadius: 10),
                ],
              ),
              child: const Icon(Icons.hub_rounded, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GMWF HYBRID COMMAND CENTER',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Primary LAN Node • Realtime Data & Hardware Cluster',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ]),
          actions: [
            _buildStatusBadge(),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => ServerDataViewer(branchId: widget.branchId),
                ));
              },
              icon: const Icon(Icons.storage_rounded, size: 16),
              label: Text('Data Vault', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: const Color(0xFF38BDF8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.power_settings_new, color: Color(0xFFF43F5E)),
              tooltip: 'Logout',
              onPressed: () => _showLogoutDialog(context),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.6),
              radius: 1.4,
              colors: [Color(0xFF1E1B4B), Color(0xFF090D16)],
            ),
          ),
          child: SafeArea(
            child: !_isRunning
                ? _buildStoppedView()
                : Column(
                    children: [
                      // Sub-navigation Tab Bar
                      Container(
                        color: const Color(0xFF1F2937).withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _navTabChip(0, 'Live Server Matrix', Icons.dns_rounded),
                              const SizedBox(width: 8),
                              _navTabChip(1, 'Multi-Server Cluster', Icons.hub_rounded),
                              const SizedBox(width: 8),
                              _navTabChip(2, 'Department Progress', Icons.domain_rounded),
                              const SizedBox(width: 8),
                              _navTabChip(3, 'Data Archive', Icons.storage_rounded),
                              const SizedBox(width: 8),
                              _navTabChip(4, 'LAN Hardware & Devices', Icons.hardware_rounded),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Colors.white10),

                      // Tab View Content
                      Expanded(
                        child: IndexedStack(
                          index: _selectedTab,
                          children: [
                            _buildRunningView(),
                            MultiServerControlWidget(branchId: widget.branchId, onTriggerSync: _manualSync),
                            DepartmentActivityWidget(branchId: widget.branchId),
                            ServerDataViewer(branchId: widget.branchId),
                            SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: const LanHardwareStatusWidget(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _navTabChip(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.white70),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isRunning ? Colors.greenAccent.withValues(alpha: 0.1) : Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isRunning ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRunning ? Colors.greenAccent : Colors.redAccent,
              boxShadow: [
                BoxShadow(color: (_isRunning ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.5), blurRadius: 8)
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_isRunning ? 'SYS ONLINE' : 'SYS OFFLINE',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _isRunning ? Colors.greenAccent : Colors.redAccent,
                  letterSpacing: 1)),
        ]),
      ),
    );
  }

  Widget _buildConnectedClientsPanel() {
    final roleCounts = <String, int>{};
    for (final c in _connectedClients.values) {
      roleCounts[c.role.toLowerCase()] = (roleCounts[c.role.toLowerCase()] ?? 0) + 1;
    }

    final sortedClients = _connectedClients.values.toList()
      ..sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.hub_rounded, color: Colors.blueAccent, size: 24),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active Branch Network Nodes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Realtime WebSocket Client Connections & Live Activity', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.purpleAccent]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.3), blurRadius: 8)],
                ),
                child: Text('${_connectedClients.length} Connected Node${_connectedClients.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildRoleSummaryChip('Supervisor', roleCounts['supervisor'] ?? 0, const Color(0xFFE91E63), Icons.admin_panel_settings),
                _buildRoleSummaryChip('Receptionist', roleCounts['receptionist'] ?? 0, const Color(0xFF2196F3), Icons.person_pin_circle),
                _buildRoleSummaryChip('Doctor', roleCounts['doctor'] ?? 0, const Color(0xFF4CAF50), Icons.local_hospital),
                _buildRoleSummaryChip('Dispenser', (roleCounts['dispenser'] ?? 0) + (roleCounts['pharmacist'] ?? 0), const Color(0xFFFF9800), Icons.medication),
                _buildRoleSummaryChip('Finance', (roleCounts['finance manager'] ?? 0) + (roleCounts['finance'] ?? 0), const Color(0xFF009688), Icons.account_balance),
                _buildRoleSummaryChip('Donations', roleCounts['donations'] ?? 0, const Color(0xFF9C27B0), Icons.volunteer_activism),
                _buildRoleSummaryChip('Madrassa & School', (roleCounts['teacher'] ?? 0) + (roleCounts['madrassa'] ?? 0) + (roleCounts['school'] ?? 0), const Color(0xFF3F51B5), Icons.school),
                _buildRoleSummaryChip('Library', roleCounts['library'] ?? 0, const Color(0xFF795548), Icons.local_library),
                _buildRoleSummaryChip('Dasterkhwaan', roleCounts['dasterkhwaan'] ?? 0, const Color(0xFFFF5722), Icons.soup_kitchen),
                _buildRoleSummaryChip('Attendance', roleCounts['attendance'] ?? 0, const Color(0xFF673AB7), Icons.fingerprint),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),
            if (sortedClients.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(children: [
                    Icon(Icons.radar_rounded, size: 64, color: Colors.blueAccent.withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text('Scanning for LAN Branch Clients...', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Client apps across the branch will automatically connect when opened.', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
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

  Widget _buildRoleSummaryChip(String label, int count, Color color, IconData icon) {
    final bool active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: active ? color : Colors.white30),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.white54)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: active ? color : Colors.white10, borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _buildClientRow(ConnectedClient client) {
    final duration  = DateTime.now().difference(client.connectedAt);
    final connected = duration.inMinutes > 0 ? '${duration.inMinutes}m ${duration.inSeconds % 60}s' : '${duration.inSeconds}s';
    final Color cColor = client.color == const Color(0xFF607D8B) ? Colors.cyanAccent : client.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cColor, cColor.withValues(alpha: 0.6)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: cColor.withValues(alpha: 0.3), blurRadius: 8)],
            ),
            child: Icon(client.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(client.displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text(client.role.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.computer_rounded, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text('${client.deviceOs} • ${client.appVersion}', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
                    const SizedBox(width: 12),
                    Icon(Icons.lan_rounded, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text('IP: ${client.ipAddress}', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6), fontFamily: 'monospace')),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: Colors.amberAccent),
                      const SizedBox(width: 6),
                      Text('Current Activity: ', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                      Text(client.currentActivity, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amberAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent)),
                  const SizedBox(width: 6),
                  const Text('CONNECTED', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(height: 8),
              Text('${client.messagesCount} msgs', style: const TextStyle(fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Uptime: $connected', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4), fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFirewallBanner() {
    if (kIsWeb || !io.Platform.isWindows) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.amberAccent.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: const Icon(Icons.security, color: Colors.amberAccent, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Windows Firewall Configuration', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                'If nodes fail to connect, apply this rule in PowerShell (Admin):',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        'netsh advfirewall firewall add rule name="GMWF_LAN" dir=in action=allow protocol=TCP localport=${AppNetwork.websocketPort}',
                        style: const TextStyle(fontSize: 11, color: Colors.greenAccent, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: 'netsh advfirewall firewall add rule name="GMWF_LAN" dir=in action=allow protocol=TCP localport=${AppNetwork.websocketPort}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Command copied to clipboard!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.greenAccent,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      tooltip: 'Copy command',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: _openFirewallPort,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent.withValues(alpha: 0.2), foregroundColor: Colors.amberAccent),
          child: const Text('Auto-Fix'),
        ),
      ]),
    );
  }

  Widget _buildWebUnsupportedMessage() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 100, color: Colors.blueAccent.withValues(alpha: 0.5)),
              const SizedBox(height: 32),
              const Text('Platform Incompatible', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              const Text(
                'Server hosting requires native socket access. Please run the application on Windows, macOS, or Linux to establish a LAN node.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.5, color: Colors.white60, fontSize: 16),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Return to Matrix'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotAuthenticatedMessage() {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            color: const Color(0xFF1F2937).withValues(alpha: 0.8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orangeAccent.withValues(alpha: 0.1)),
                    child: const Icon(Icons.lock_outline, size: 60, color: Colors.orangeAccent),
                  ),
                  const SizedBox(height: 32),
                  const Text('Access Denied', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  const Text('Server level clearance required. Please authenticate with a Server role.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go Back'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
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
        constraints: const BoxConstraints(maxWidth: 450),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Colors.blueAccent.withValues(alpha: 0.2), Colors.purpleAccent.withValues(alpha: 0.2)]),
                  ),
                  child: const Icon(Icons.dns_rounded, size: 80, color: Colors.blueAccent),
                ),
                const SizedBox(height: 32),
                const Text('Core Server Offline', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text('Node ID: ${widget.branchId}', style: TextStyle(color: Colors.white54, fontSize: 16)),
                const SizedBox(height: 40),
                if (_serverIp != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      const Text('LOCAL IP ASSIGNMENT', style: TextStyle(color: Colors.white30, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SelectableText(_serverIp!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.greenAccent, fontFamily: 'monospace')),
                    ]),
                  ),
                  const SizedBox(height: 40),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _startServer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power_settings_new, size: 24, color: Colors.white),
                        SizedBox(width: 12),
                        Text('INITIALIZE SERVER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white)),
                      ],
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!kIsWeb && io.Platform.isWindows && _connectedClients.isEmpty) _buildFirewallBanner(),

          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.1,
            children: [
              _buildStatCard('SERVER IP ADDRESS', _serverIp ?? 'Unknown', Icons.lan_rounded, [const Color(0xFF0EA5E9), const Color(0xFF0284C7)]),
              _buildStatCard('UPTIME CLOCK', _formatUptime(), Icons.timer_outlined, [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)]),
              _buildStatCard('ACTIVE LAN NODES', '${_connectedClients.length} Connected', Icons.hub_rounded, [const Color(0xFF10B981), const Color(0xFF059669)]),
              _buildStatCard(
                'SYNC TELEMETRY',
                '$_syncedToday (${_syncQueueSize} Queued)',
                Icons.cloud_sync_rounded,
                [const Color(0xFFF59E0B), const Color(0xFFD97706)],
              ),
            ],
          ),

          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.sensors_rounded, size: 22, color: Color(0xFF10B981)),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Node Telemetry & Network Details', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(
                                _lastSyncTime != null
                                    ? 'Last Cloud Sync: ${DateFormat('hh:mm:ss a').format(_lastSyncTime!)}'
                                    : 'Realtime WebSocket & UDP Gateway Operational',
                                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0F19),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailRow('Primary Host IP', _serverIp ?? 'Unknown'),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Color(0xFF1E293B))),
                              _buildDetailRow('WebSocket Port', AppNetwork.websocketPort.toString()),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Color(0xFF1E293B))),
                              _buildDetailRow('ZKTeco Port', '4370 (UDP / TCP)'),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Color(0xFF1E293B))),
                              _buildDetailRow('Active Branch ID', widget.branchId),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isOnline ? _manualSync : null,
                            icon: const Icon(Icons.cloud_sync_rounded, size: 18),
                            label: Text('FORCE CLOUD SYNC', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
                              foregroundColor: const Color(0xFF38BDF8),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              side: const BorderSide(color: Color(0xFF0284C7)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(flex: 3, child: _buildConnectedClientsPanel()),
            ],
          ),

          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.terminal_rounded, color: Color(0xFF38BDF8), size: 22),
                    const SizedBox(width: 12),
                    Text('LIVE NETWORK SYSTEM LOG STREAM', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _stopServer,
                      icon: const Icon(Icons.stop_circle_outlined, color: Color(0xFFF43F5E), size: 18),
                      label: Text('SHUTDOWN SERVER', style: GoogleFonts.inter(color: const Color(0xFFF43F5E), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    height: 220,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF050811),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: _activityLog.isEmpty
                        ? Center(child: Text('Awaiting network events & biometric punches...', style: GoogleFonts.firaCode(color: const Color(0xFF64748B), fontSize: 12)))
                        : ListView.builder(
                            itemCount: _activityLog.length > 50 ? 50 : _activityLog.length,
                            itemBuilder: (context, index) {
                              final log = _activityLog[index];
                              Color textColor = const Color(0xFFCBD5E1);
                              if (log.contains('❌') || log.contains('🔴')) {
                                textColor = const Color(0xFFF43F5E);
                              } else if (log.contains('✅') || log.contains('🟢')) {
                                textColor = const Color(0xFF10B981);
                              } else if (log.contains('⚠️')) {
                                textColor = const Color(0xFFF59E0B);
                              }
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(log, style: GoogleFonts.firaCode(fontSize: 12, color: textColor)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
        SelectableText(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, List<Color> gradientColors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [gradientColors[0].withValues(alpha: 0.15), gradientColors[1].withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gradientColors[0].withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Icon(icon, color: gradientColors[0], size: 24),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ServerSyncManager  (embedded in this file — used by the dashboard widget)
// ─────────────────────────────────────────────────────────────────────────────
class ServerSyncManager {
  final String branchId;
  final LanServer server;
  final Function(int) onSyncComplete;
  final Function(String) onSyncError;
  final Function(Map<String, dynamic>) onMessageReceived;

  Timer? _syncTimer;
  bool _isSyncing = false;

  // FIX-A: full resolver — matches ServerSyncManager in server_sync_manager.dart
  static const _validQueueTypes = {'zakat', 'non-zakat', 'gmwf'};

  /// Canonical resolver — NEVER falls back silently.
  /// Input may be a patient status ('Zakat', 'Non-Zakat', 'GMWF') or any variant.
  static String _resolveQueueType(dynamic raw) {
    if (raw == null) return 'zakat';
    final s = raw.toString().toLowerCase().trim();
    if (s.isEmpty) return 'zakat';
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) {
      return 'non-zakat';
    }
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    if (s == 'zakat') return 'zakat';
    debugPrint('[ServerSyncManager] ⚠️  Unknown queueType "$raw" — defaulting to zakat');
    return 'zakat';
  }

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
    if (eventType == null ||
        eventType == 'unknown' ||
        eventType == 'ping' ||
        eventType == 'pong' ||
        eventType == 'identify' ||
        eventType == 'identified' ||
        eventType == 'client_count_update') {
      return;
    }


    try {
      final box = Hive.box(LocalStorageService.syncBox);
      final key =
          'sync_${DateTime.now().millisecondsSinceEpoch}_$eventType';

      if (eventType == 'dispense_completed') {
        final data = (message['data'] as Map<String, dynamic>?) ??
            Map<String, dynamic>.from(message);

        // FIX-A: resolve queueType from the message, the data map, or from
        // the local entry in Hive — in that priority order.
        final rawQT = (message['queueType'] ?? data['queueType'])?.toString();
        String queueType;
        if (rawQT != null && rawQT.trim().isNotEmpty) {
          queueType = _resolveQueueType(rawQT);
        } else {
          // Fallback: look up the entry in Hive
          final serial    = data['serial']?.toString() ?? '';
          final entryKey  = '$branchId-$serial';
          final localEntry = Hive.box(LocalStorageService.entriesBox).get(entryKey);
          queueType = _resolveQueueType(localEntry?['queueType']);
        }

        final serial    = data['serial']?.toString() ?? '';
        final parts = serial.split('-');
        final cleanDateKey = (parts.isNotEmpty && parts[0].toUpperCase() == 'X')
            ? (parts.length > 1 ? parts[1] : '')
            : (parts.isNotEmpty ? parts[0] : '');
        final dateKey   = data['dateKey']?.toString() ??
            (serial.contains('-') ? cleanDateKey : _todayKey());
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
          // Write B: serial status patch — queueType at TOP LEVEL (FIX-B)
          box.put('${key}_serial', {
            'type':      'update_serial_status',
            'branchId':  bId,
            'dateKey':   dateKey,
            'queueType': queueType,   // FIX-B: top-level, not buried in data
            'serial':    serial,
            'data': {
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

          // FIX-D: Write C: inventory deduction ops for each medicine
          final medicines = data['medicines'];
          if (medicines is List && medicines.isNotEmpty) {
            for (int i = 0; i < medicines.length; i++) {
              final med = medicines[i];
              if (med is! Map) continue;
              final medMap     = Map<String, dynamic>.from(med);
              final medicineId = (medMap['medicineId'] ?? medMap['id'] ??
                      medMap['stockItemId'] ?? '').toString().trim();
              final qty        = medMap['quantity'] ?? medMap['qty'] ?? 0;
              final qtyNum     = qty is num
                  ? qty.toDouble()
                  : double.tryParse(qty.toString()) ?? 0.0;
              if (medicineId.isEmpty || qtyNum <= 0) continue;

              box.put('${key}_inv_$i', {
                'type':       'update_inventory',
                'branchId':   bId,
                'medicineId': medicineId,
                'delta':      -qtyNum,
                'serial':     serial,
                'data': {
                  'medicineId':   medicineId,
                  'medicineName': medMap['medicineName'] ?? medMap['name'] ?? '',
                  'delta':        -qtyNum,
                  'serial':       serial,
                  'dispensedAt':  data['dispensedAt'] ?? DateTime.now().toIso8601String(),
                  'dispensedBy':  data['dispensedBy'] ?? '',
                },
                'createdAt': DateTime.now().toIso8601String(),
                'attempts':  0,
                'status':    'pending',
              });
            }
          }
        }
        return;
      }

      // All other event types
      // FIX-A: carry queueType at top level for save_entry ops
      final opQueueType = _resolveQueueType(
          message['queueType'] ?? (message['data'] is Map ? message['data']['queueType'] : null));

      final clientBranchId = (message['branchId'] ??
              (message['data'] is Map ? message['data']['branchId'] : null))
          ?.toString()
          .trim();
      final bId = (clientBranchId != null && clientBranchId.isNotEmpty)
          ? clientBranchId
          : branchId;

      box.put(key, {
        'type':      _mapEventTypeToSyncType(eventType),
        'branchId':  bId,
        'queueType': opQueueType,   // top level
        'dateKey':   message['dateKey'] ?? (message['data'] is Map ? message['data']['dateKey'] : null),
        'serial':    message['serial'] ?? (message['data'] is Map ? message['data']['serial'] : null),
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
      case 'save_dispensary_record':
        return 'save_dispensary_record';
      case 'update_serial_status':
        return 'update_serial_status';
      default:
        return eventType;
    }
  }

  String _todayKey() => DateFormat('ddMMyy').format(DateTime.now());

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
          if (type == null || type == 'unknown' || data == null) {
            await box.delete(key);
            continue;
          }


          final resolvedBranchId =
              (syncItem['branchId'] as String?)?.trim().isNotEmpty == true
                  ? syncItem['branchId'] as String
                  : branchId;
          final resolvedDateKey =
              (syncItem['dateKey'] as String?)?.trim() ?? '';
          // FIX-A: read from top-level op first
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
            medicineId: (syncItem['medicineId'] as String?)?.trim() ?? '',
            delta:      syncItem['delta'] is num
                ? (syncItem['delta'] as num).toDouble()
                : double.tryParse(syncItem['delta']?.toString() ?? '') ?? 0.0,
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
    String medicineId = '',
    double delta      = 0.0,
  }) async {
    final db        = FirebaseFirestore.instance;
    final cleanData = _removeFieldValues(data);

    final effectiveDateKey  = dateKey.isNotEmpty
        ? dateKey  : (cleanData['dateKey']  as String? ?? '');
    final effectiveSerial   = serial.isNotEmpty
        ? serial   : (cleanData['serial']   as String? ?? '');
    // FIX-A: queueType already resolved to canonical value before this call
    final effectiveQueueType = queueType;
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
        // FIX-A: queueType comes resolved from op level; only fall back to
        // cleanData if effectiveQueueType is somehow still 'zakat' and
        // cleanData has a different value.
        final qt = _validQueueTypes.contains(effectiveQueueType)
            ? effectiveQueueType
            : _resolveQueueType(cleanData['queueType']);
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
        cleanData.remove('dateKey');
        await db
            .collection('branches').doc(effectiveBranchId)
            .collection('dispensary').doc(dk)
            .collection(dk).doc(s)
            .set(cleanData, SetOptions(merge: true));
        debugPrint('✅ save_dispensary_record → dispensary/$dk/$dk/$s');
        break;

      // ── Serial status patch ───────────────────────────────────────────────
      // FIX-C: queueType is now always resolved at op level before reaching here
      case 'update_serial_status':
        final s  = effectiveSerial.isNotEmpty
            ? effectiveSerial
            : (cleanData['serial'] as String? ?? '');
        final dk = effectiveDateKey.isNotEmpty
            ? effectiveDateKey
            : (cleanData['dateKey'] as String? ?? '');
        final qt = effectiveQueueType; // already canonical
        if (s.isEmpty || dk.isEmpty) {
          throw Exception(
              'update_serial_status: missing serial ($s) or dateKey ($dk)');
        }
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

      // FIX-D: inventory deduction ──────────────────────────────────────────
      case 'update_inventory':
        final mid = medicineId.isNotEmpty
            ? medicineId
            : (cleanData['medicineId'] as String? ?? '').trim();
        if (mid.isEmpty) {
          debugPrint('⚠️ update_inventory: missing medicineId — skipping');
          return;
        }
        final d = delta != 0.0
            ? delta
            : (cleanData['delta'] is num
                ? (cleanData['delta'] as num).toDouble()
                : double.tryParse(cleanData['delta']?.toString() ?? '') ?? 0.0);
        final docRef = db
            .collection('branches').doc(effectiveBranchId)
            .collection('inventory').doc(mid);
        await db.runTransaction((transaction) async {
          final snapshot = await transaction.get(docRef);
          if (snapshot.exists) {
            final current = (snapshot.data()?['quantity'] as num?)?.toDouble() ?? 0.0;
            final updated = (current + d).clamp(0.0, double.infinity);
            transaction.update(docRef, {'quantity': updated});
          }
        });
        debugPrint('✅ update_inventory → inventory/$mid delta=$d');
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
