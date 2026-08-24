import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/biometric_device_config.dart';
import '../../models/biometric_credential.dart';
import '../../services/zkteco_network_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/finance_local_storage.dart';
import '../../services/image_upload_service.dart';
import '../../utils/network_utils.dart';

class BiometricDeviceManagerPage extends StatefulWidget {
  final String branchId;
  const BiometricDeviceManagerPage({super.key, this.branchId = 'main'});

  @override
  State<BiometricDeviceManagerPage> createState() => _BiometricDeviceManagerPageState();
}

class _BiometricDeviceManagerPageState extends State<BiometricDeviceManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _punchSubscription;

  final List<Map<String, dynamic>> _livePunches = [];
  String _searchQuery = '';
  String _userPinsFilter = 'All'; // 'All', 'Enrolled', 'Not Enrolled'
  bool _isAutoAssigning = false;
  String _pcIpAddress = 'Detecting...';

  Widget _buildEntityAvatar(String entityId, String entityName, String entityType) {
    if (entityId.isEmpty ||
        entityId == 'null' ||
        entityName.toLowerCase().contains('unknown') ||
        entityName.toLowerCase().contains('test') ||
        entityType == 'unmapped') {
      return const CircleAvatar(
        radius: 20,
        backgroundColor: Color(0xFFF1F5F9),
        child: Icon(Icons.fingerprint_rounded, size: 20, color: Color(0xFF64748B)),
      );
    }

    String photoUrl = '';
    String gender = '';

    if (Hive.isBoxOpen(LocalStorageService.employeesBox)) {
      final emp = Hive.box(LocalStorageService.employeesBox).get(entityId);
      if (emp is Map) {
        if (emp['photoUrl'] != null && emp['photoUrl'].toString().isNotEmpty) {
          photoUrl = emp['photoUrl'].toString();
        } else if (emp['profilePictureUrl'] != null && emp['profilePictureUrl'].toString().isNotEmpty) {
          photoUrl = emp['profilePictureUrl'].toString();
        }
        if (emp['gender'] != null) gender = emp['gender'].toString().toLowerCase();
      }
    }
    if (photoUrl.isEmpty && Hive.isBoxOpen(LocalStorageService.schoolStudentsBox)) {
      final box = Hive.box(LocalStorageService.schoolStudentsBox);
      for (final k in box.keys) {
        if (k.toString().endsWith(entityId)) {
          final st = box.get(k);
          if (st is Map) {
            if (st['photoUrl'] != null && st['photoUrl'].toString().isNotEmpty) {
              photoUrl = st['photoUrl'].toString();
            }
            if (st['gender'] != null) gender = st['gender'].toString().toLowerCase();
            break;
          }
        }
      }
    }
    if (photoUrl.isEmpty && Hive.isBoxOpen(LocalStorageService.madrassaStudentsBox)) {
      final box = Hive.box(LocalStorageService.madrassaStudentsBox);
      for (final k in box.keys) {
        if (k.toString().endsWith(entityId)) {
          final st = box.get(k);
          if (st is Map) {
            if (st['photoUrl'] != null && st['photoUrl'].toString().isNotEmpty) {
              photoUrl = st['photoUrl'].toString();
            }
            if (st['gender'] != null) gender = st['gender'].toString().toLowerCase();
            break;
          }
        }
      }
    }

    final isFemale = gender == 'female';
    final isMale = gender == 'male';

    final bytes = ImageUploadService.decodeBase64ToBytes(photoUrl);
    if (bytes != null && bytes.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: isFemale ? const Color(0xFFFCE7F3) : (isMale ? const Color(0xFFE0F2FE) : const Color(0xFF6366F1).withValues(alpha: 0.1)),
        backgroundImage: MemoryImage(bytes),
      );
    } else if (photoUrl.startsWith('http')) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: isFemale ? const Color(0xFFFCE7F3) : (isMale ? const Color(0xFFE0F2FE) : const Color(0xFF6366F1).withValues(alpha: 0.1)),
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    if (isFemale) {
      return const CircleAvatar(
        radius: 20,
        backgroundColor: Color(0xFFFCE7F3),
        child: Icon(Icons.face_3_rounded, size: 22, color: Color(0xFFDB2777)),
      );
    } else if (isMale) {
      return const CircleAvatar(
        radius: 20,
        backgroundColor: Color(0xFFE0F2FE),
        child: Icon(Icons.face_6_rounded, size: 22, color: Color(0xFF0284C7)),
      );
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
      child: Text(
        entityName.isNotEmpty ? entityName[0].toUpperCase() : '?',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4338CA), fontSize: 13),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Fetch PC LAN IP
    _fetchPcIp();

    // Ensure ZKTeco network server is running
    ZkTecoNetworkService.startServer();

    // Pre-populate with punches from today so user immediately sees previous scans
    _livePunches.addAll(ZkTecoNetworkService.getRecentPunchesToday());

    // Listen to realtime punch stream
    _punchSubscription = ZkTecoNetworkService.punchStream.listen((punch) {
      if (mounted) {
        setState(() {
          // Prevent duplicates
          _livePunches.removeWhere((p) => p['id'] == punch['id']);
          _livePunches.insert(0, punch);
          if (_livePunches.length > 100) _livePunches.removeLast();
        });
      }
    });
  }

  Future<void> _fetchPcIp() async {
    if (kIsWeb) {
      if (mounted) setState(() => _pcIpAddress = 'Cloud Sync Mode (Web)');
      return;
    }
    try {
      final ip = await getPrimaryLanIp();
      if (ip != null && ip.isNotEmpty) {
        if (mounted) setState(() => _pcIpAddress = ip);
        return;
      }
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final a = addr.address;
          if (!a.startsWith('127.') && !a.startsWith('169.254.')) {
            if (mounted) setState(() => _pcIpAddress = a);
            return;
          }
        }
      }
      if (mounted) setState(() => _pcIpAddress = '192.168.1.8');
    } catch (_) {
      if (mounted) setState(() => _pcIpAddress = '192.168.1.8');
    }
  }

  @override
  void dispose() {
    _punchSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Sleek slate surface
      appBar: AppBar(
        title: Text(
          'Biometric Attendance Settings & Devices',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 19),
        ),
        backgroundColor: const Color(0xFF0F172A), // Rich dark slate header
        elevation: 2,
        shadowColor: Colors.black26,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: const Color(0xFF1E293B),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF10B981),
              indicatorWeight: 4,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF94A3B8), // High contrast unselected text
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.router_rounded, size: 18), text: 'ZKTeco Devices'),
                Tab(icon: Icon(Icons.badge_rounded, size: 18), text: 'User Biometric PINs'),
                Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'Live Scans & Logs'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildServerStatusBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDevicesTab(),
                _buildUserPinsTab(),
                _buildLiveLogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerStatusBanner() {
    if (kIsWeb) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFF2563EB),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Cloud Sync Active (Web View)',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E40AF),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D4ED8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Web Browser Mode',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ZKTeco hardware connects directly to your Windows Server PC on Port 8088. This Web App displays live device status & attendance synced from the Server.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Hardware TCP/UDP Port listener runs on the Desktop/Server PC app',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF93C5FD)),
                ),
                child: Text(
                  'Port Listener: Server PC',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF1E40AF),
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: ZkTecoNetworkService.isServerRunningNotifier,
      builder: (context, isRunning, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRunning ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRunning ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isRunning ? const Color(0xFF10B981) : Colors.red).withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isRunning ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isRunning ? 'ZKTeco Server Active' : 'ZKTeco Server Stopped',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            color: isRunning ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: isRunning ? const Color(0xFF047857) : const Color(0xFF991B1B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'PC IP: $_pcIpAddress',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isRunning
                          ? 'Set your ZKTeco machine Cloud Server IP to "$_pcIpAddress" and Port to "8088".'
                          : 'Click "Start Server" to listen for incoming fingerprint scans.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: isRunning ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: ZkTecoNetworkService.totalPunchesReceivedNotifier,
                builder: (context, count, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isRunning ? const Color(0xFF059669) : Colors.grey[600],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '$count Scans',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  if (isRunning) {
                    await ZkTecoNetworkService.stopServer();
                  } else {
                    await ZkTecoNetworkService.startServer();
                  }
                },
                icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                label: Text(isRunning ? 'Stop' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 1: ZKTeco Network Devices ──────────────────────────────────────────

  Widget _buildDevicesTab() {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(LocalStorageService.biometricDevicesBox).listenable(),
      builder: (context, box, child) {
        final devices = ZkTecoNetworkService.getAllDevices();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Building Biometric Devices',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Map ZKTeco Wi-Fi/Ethernet readers to physical building locations',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditDeviceDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (devices.isEmpty)
                Expanded(
                  child: Center(
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.router_rounded, size: 48, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Biometric Devices Configured',
                              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Click "Add Device" or power on a ZKTeco device connected to your LAN for auto-discovery.',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final dev = devices[index];
                      final isOnline = dev.status == 'Online';
                      final lastHb = dev.lastHeartbeat != null
                          ? DateFormat('hh:mm:ss a').format(dev.lastHeartbeat!)
                          : 'Never';

                      // Location pill colors
                      Color locBg = const Color(0xFFEFF6FF);
                      Color locText = const Color(0xFF1D4ED8);
                      if (dev.buildingLocation.toLowerCase().contains('dispensary')) {
                        locBg = const Color(0xFFF0FDF4);
                        locText = const Color(0xFF15803D);
                      } else if (dev.buildingLocation.toLowerCase().contains('madrassa')) {
                        locBg = const Color(0xFFF3E8FF);
                        locText = const Color(0xFF6B21A8);
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isOnline ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.fingerprint_rounded,
                                  color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          dev.deviceName,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: locBg,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            dev.buildingLocation,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: locText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        _buildDetailBadge('IP', dev.ipAddress, const Color(0xFF334155)),
                                        _buildDetailBadge('Port', '${dev.port}', const Color(0xFF334155)),
                                        _buildDetailBadge('SN', dev.serialNumber.isEmpty ? 'N/A' : dev.serialNumber, const Color(0xFF334155)),
                                        _buildDetailBadge('Last Seen', lastHb, isOnline ? const Color(0xFF059669) : const Color(0xFF64748B)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isOnline ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isOnline ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isOnline ? 'ONLINE' : 'OFFLINE',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isOnline ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  if (kIsWeb) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Raw IP ping is performed by the Windows Server PC app.'),
                                        backgroundColor: Color(0xFF2563EB),
                                      ),
                                    );
                                    return;
                                  }
                                  final success = await ZkTecoNetworkService.pingDevice(dev.ipAddress, port: dev.port);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? '🟢 Successfully reached ZKTeco device at ${dev.ipAddress}:${dev.port}!'
                                              : '🔴 Could not reach ${dev.ipAddress}:${dev.port}. Please check router connection.',
                                        ),
                                        backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFDC2626),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.bolt_rounded, size: 16),
                                label: const Text('Test Ping'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  foregroundColor: const Color(0xFF334155),
                                  elevation: 0,
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, color: Color(0xFF2563EB)),
                                tooltip: 'Edit Device Settings',
                                onPressed: () => _showAddEditDeviceDialog(device: dev),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailBadge(String label, String value, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  // ── Tab 2: User Biometric PINs ─────────────────────────────────────────────

  // ── Tab 2: User Biometric PINs ─────────────────────────────────────────────

  Widget _buildUserPinsTab() {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(LocalStorageService.biometricCredentialsBox).listenable(),
      builder: (context, box, child) {
        final credentials = ZkTecoNetworkService.getAllCredentials();
        final enrolledEntityIds = credentials.map((c) => c.entityId).toSet();

        // Get all active employees to also display unenrolled employees
        final allEmployees = FinanceLocalStorage.getEmployees('all').where((e) => e['isActive'] != false).toList();
        final unenrolledEmployees = allEmployees.where((e) {
          final id = e['localId']?.toString() ?? e['id']?.toString() ?? '';
          return !enrolledEntityIds.contains(id);
        }).toList();

        final filteredCredentials = credentials.where((c) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return c.entityName.toLowerCase().contains(q) ||
              c.biometricPin.toLowerCase().contains(q) ||
              c.entityType.toLowerCase().contains(q);
        }).toList();

        final filteredUnenrolled = unenrolledEmployees.where((e) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          final name = (e['name']?.toString() ?? '').toLowerCase();
          final role = (e['role']?.toString() ?? '').toLowerCase();
          final dept = (e['department']?.toString() ?? '').toLowerCase();
          return name.contains(q) || role.contains(q) || dept.contains(q);
        }).toList();

        final totalEnrolled = credentials.length;
        final totalUnenrolled = unenrolledEmployees.length;
        final totalAll = totalEnrolled + totalUnenrolled;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'Search by Employee Name, Biometric PIN, or Role...',
                          hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isAutoAssigning
                        ? null
                        : () async {
                            setState(() => _isAutoAssigning = true);
                            final count = await ZkTecoNetworkService.bulkAutoAssignBiometricPins();
                            setState(() => _isAutoAssigning = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Auto-assigned Biometric PINs to $count profiles!'),
                                  backgroundColor: const Color(0xFF10B981),
                                ),
                              );
                            }
                          },
                    icon: _isAutoAssigning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Bulk Auto-Assign PINs'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showAddCredentialDialog(),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Link User PIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Filter Chips: All, Enrolled, Not Enrolled
              Row(
                children: [
                  _buildPinsFilterChip('All', totalAll),
                  const SizedBox(width: 8),
                  _buildPinsFilterChip('Enrolled', totalEnrolled, badgeColor: const Color(0xFF059669)),
                  const SizedBox(width: 8),
                  _buildPinsFilterChip('Not Enrolled', totalUnenrolled, badgeColor: const Color(0xFFD97706)),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Builder(
                    builder: (_) {
                      final showEnrolled = _userPinsFilter == 'All' || _userPinsFilter == 'Enrolled';
                      final showUnenrolled = _userPinsFilter == 'All' || _userPinsFilter == 'Not Enrolled';

                      final displayList = <Map<String, dynamic>>[];

                      if (showEnrolled) {
                        for (final c in filteredCredentials) {
                          displayList.add({'type': 'enrolled', 'data': c});
                        }
                      }

                      if (showUnenrolled) {
                        for (final u in filteredUnenrolled) {
                          displayList.add({'type': 'unenrolled', 'data': u});
                        }
                      }

                      if (displayList.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.badge_outlined, size: 48, color: Color(0xFF94A3B8)),
                                const SizedBox(height: 12),
                                Text(
                                  'No Profiles Matching Filter',
                                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Click "Bulk Auto-Assign PINs" to assign PINs to all existing staff profiles!',
                                  style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: displayList.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (ctx, i) {
                          final item = displayList[i];
                          if (item['type'] == 'enrolled') {
                            final c = item['data'] as BiometricCredential;
                            final roleName = c.entityType.replaceAll('_', ' ').toUpperCase();

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildEntityAvatar(c.entityId, c.entityName, c.entityType),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 65,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'PIN',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 8.5,
                                            color: const Color(0xFFC7D2FE),
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        Text(
                                          c.biometricPin,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    c.entityName,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Text(
                                      roleName,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: const Text(
                                      'ENROLLED',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Enrolled: ${DateFormat('yyyy-MM-dd').format(c.enrolledAt)}',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                              trailing: ElevatedButton.icon(
                                onPressed: () => _showEnrollFingerprintGuide(c),
                                icon: const Icon(Icons.fingerprint_rounded, size: 16),
                                label: const Text('Enroll Fingerprint'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFECFDF5),
                                  foregroundColor: const Color(0xFF047857),
                                  elevation: 0,
                                  side: const BorderSide(color: Color(0xFFA7F3D0)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            );
                          } else {
                            // Unenrolled Employee
                            final emp = item['data'] as Map<String, dynamic>;
                            final empId = emp['localId']?.toString() ?? emp['id']?.toString() ?? '';
                            final name = emp['name']?.toString() ?? 'Employee';
                            final role = emp['role']?.toString() ?? 'Staff';
                            final dept = emp['department']?.toString() ?? '';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildEntityAvatar(empId, name, 'employee'),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 65,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBEB),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFFDE68A)),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.fingerprint_rounded, size: 18, color: Color(0xFFD97706)),
                                        SizedBox(height: 2),
                                        Text(
                                          'NO PIN',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5, color: Color(0xFF92400E)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBEB),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFFDE68A)),
                                    ),
                                    child: const Text(
                                      'NOT ENROLLED',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '$role • $dept',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                              trailing: ElevatedButton.icon(
                                onPressed: () async {
                                  final assignedPin = await ZkTecoNetworkService.assignPinToEntity(
                                    entityId: empId,
                                    entityName: name,
                                    entityType: 'employee',
                                    branchId: emp['branchId']?.toString() ?? widget.branchId,
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✅ Enrolled $name with PIN: $assignedPin'),
                                        backgroundColor: const Color(0xFF10B981),
                                      ),
                                    );
                                    setState(() {});
                                  }
                                },
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('Assign PIN'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPinsFilterChip(String label, int count, {Color? badgeColor}) {
    final isSelected = _userPinsFilter == label;
    final color = badgeColor ?? const Color(0xFF2563EB);

    return GestureDetector(
      onTap: () => setState(() => _userPinsFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : const Color(0xFFCBD5E1)),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.25) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 3: Live Scans & Logs ───────────────────────────────────────────────

  Widget _buildLiveLogsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Incoming Scans & Cross-Branch Alerts',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                    ),
                    Text(
                      'Real-time stream of finger scans captured from ZKTeco devices across all buildings',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showSimulatePunchDialog,
                icon: const Icon(Icons.fingerprint_rounded, size: 16),
                label: const Text('Simulate Test Scan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                tooltip: 'Reload punches from storage',
                onPressed: () {
                  setState(() {
                    _livePunches.clear();
                    _livePunches.addAll(ZkTecoNetworkService.getRecentPunchesToday());
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reloaded recent punches from storage')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: _livePunches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.stream_rounded, size: 40, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Waiting for finger scans on ZKTeco devices...',
                            style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _livePunches.length,
                      itemBuilder: (ctx, i) {
                        final p = _livePunches[i];
                        final isMapped = p['isMapped'] == true;
                        final isCrossBranchPending = p['isCrossBranchPending'] == true;
                        final crossBranchInfo = p['crossBranchInfo'] as Map<String, dynamic>?;
                        final pendingId = crossBranchInfo?['id']?.toString() ?? '';

                        return ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isMapped || (p['entityId']?.toString() ?? '').isEmpty)
                                const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xFFF1F5F9),
                                  child: Icon(Icons.fingerprint_rounded, size: 20, color: Color(0xFF64748B)),
                                )
                              else
                                _buildEntityAvatar(p['entityId']?.toString() ?? '', p['entityName']?.toString() ?? '', p['entityType']?.toString() ?? 'employee'),
                              const SizedBox(width: 8),
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isCrossBranchPending
                                    ? const Color(0xFFFEF3C7)
                                    : (isMapped ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2)),
                                child: Icon(
                                  isCrossBranchPending
                                      ? Icons.warning_amber_rounded
                                      : (isMapped ? Icons.check_circle_rounded : Icons.help_outline_rounded),
                                  color: isCrossBranchPending
                                      ? const Color(0xFFD97706)
                                      : (isMapped ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            '${p['entityName']} (PIN: ${p['pin']})',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Location: ${p['buildingLocation']} | IP: ${p['deviceIp']} | Time: ${p['timestamp']}',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                              if (isCrossBranchPending)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '⚠️ Assigned to ${p['entityBranchName']} • Punched at ${p['deviceBranchName']} (${p['deviceName']})',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                                  ),
                                ),
                            ],
                          ),
                          trailing: isCrossBranchPending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        if (pendingId.isNotEmpty) {
                                          await ZkTecoNetworkService.approveCrossBranchPunch(
                                            pendingId: pendingId,
                                            reviewerName: 'HQ Manager',
                                          );
                                          if (mounted) {
                                            setState(() {
                                              p['isCrossBranchPending'] = false;
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('✅ Approved ${p['entityName']} (Marked Present)'),
                                                backgroundColor: const Color(0xFF10B981),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      child: const Text('Allow'),
                                    ),
                                    const SizedBox(width: 6),
                                    OutlinedButton(
                                      onPressed: () async {
                                        if (pendingId.isNotEmpty) {
                                          await ZkTecoNetworkService.rejectCrossBranchPunch(
                                            pendingId: pendingId,
                                            reviewerName: 'HQ Manager',
                                          );
                                          if (mounted) {
                                            setState(() {
                                              p['isCrossBranchPending'] = false;
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('❌ Rejected ${p['entityName']}'),
                                                backgroundColor: const Color(0xFFEF4444),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFEF4444),
                                        side: const BorderSide(color: Color(0xFFEF4444)),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      child: const Text('Reject'),
                                    ),
                                  ],
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isMapped ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isMapped ? 'Auto-Logged' : 'Unmapped',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isMapped ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showAddEditDeviceDialog({BiometricDeviceConfig? device}) {
    final isEdit = device != null;
    final nameCtrl = TextEditingController(text: device?.deviceName ?? 'Office Entrance Scanner');
    final ipCtrl = TextEditingController(text: device?.ipAddress ?? '192.168.1.150');
    final portCtrl = TextEditingController(text: (device?.port ?? 4370).toString());
    String location = device?.buildingLocation ?? 'Office/Dasterkhwaan';
    String branchId = (device?.branchId.isNotEmpty == true) ? device!.branchId : widget.branchId;

    showDialog(
      context: context,
      builder: (ctx) {
        final allBranches = FinanceLocalStorage.getAllBranches([])
            .where((b) => (b['id']?.toString() ?? '') != 'all')
            .toList();

        final branchIds = allBranches.map((b) => b['id']?.toString() ?? '').toSet().toList();
        if (!branchIds.contains(branchId) && branchId.isNotEmpty) {
          branchIds.add(branchId);
        }
        if (branchIds.isEmpty) {
          branchIds.addAll(['main', 'gujrat', 'sialkot', 'karachi', 'rawalpindi']);
        }

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(isEdit ? 'Edit ZKTeco Device' : 'Add ZKTeco Device'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Device Name (e.g. Madrassa Gate Scanner)'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: location,
                      decoration: const InputDecoration(labelText: 'Building Location'),
                      items: const [
                        DropdownMenuItem(value: 'Office/Dasterkhwaan', child: Text('Building 1: Office & HQ')),
                        DropdownMenuItem(value: 'Dispensary', child: Text('Building 2: Dispensary Medical Center')),
                        DropdownMenuItem(value: 'Madrassa', child: Text('Building 3: Madrassa & Hifz Department')),
                        DropdownMenuItem(value: 'School', child: Text('Building 4: GMWF Model School')),
                        DropdownMenuItem(value: 'Dasterkhwaan Kitchen', child: Text('Building 5: Dasterkhwaan Dining & Kitchen')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => location = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: branchId.isNotEmpty ? branchId : branchIds.first,
                      decoration: const InputDecoration(labelText: 'Assigned Physical Branch / Campus'),
                      items: branchIds.map((bId) {
                        final bName = LocalStorageService.getBranchName(bId);
                        return DropdownMenuItem(value: bId, child: Text('$bName ($bId)'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => branchId = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ipCtrl,
                      decoration: const InputDecoration(labelText: 'Static IP Address (e.g. 192.168.1.150)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Hardware Port (Default 4370)',
                        helperText: 'Hardware UDP polling port is 4370. ADMS push receiver is 8088.',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newConfig = BiometricDeviceConfig(
                      deviceId: device?.deviceId ?? DateTime.now().millisecondsSinceEpoch.toString(),
                      deviceName: nameCtrl.text.trim(),
                      buildingLocation: location,
                      branchId: branchId,
                      ipAddress: ipCtrl.text.trim(),
                      port: int.tryParse(portCtrl.text.trim()) ?? 4370,
                      status: device?.status ?? 'Offline',
                    );
                    await ZkTecoNetworkService.saveDeviceConfig(newConfig);
                    if (mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save Device'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddCredentialDialog() {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    String type = 'employee';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Link Biometric PIN to User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Biometric PIN (e.g. 101)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(labelText: 'Entity / Student / Employee ID'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Entity Role'),
              items: const [
                DropdownMenuItem(value: 'employee', child: Text('Office / Dasterkhwaan Employee')),
                DropdownMenuItem(value: 'dispensary_staff', child: Text('Dispensary Staff')),
                DropdownMenuItem(value: 'madrassa_student', child: Text('Madrassa Student')),
                DropdownMenuItem(value: 'school_student', child: Text('School Student')),
              ],
              onChanged: (val) {
                if (val != null) type = val;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (pinCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) return;
              final cred = BiometricCredential(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                biometricPin: pinCtrl.text.trim(),
                entityId: idCtrl.text.trim().isEmpty ? pinCtrl.text.trim() : idCtrl.text.trim(),
                entityName: nameCtrl.text.trim(),
                entityType: type,
                branchId: widget.branchId,
                enrolledAt: DateTime.now(),
              );
              await ZkTecoNetworkService.registerBiometricCredential(cred);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Link PIN'),
          ),
        ],
      ),
    );
  }

  void _showEnrollFingerprintGuide(BiometricCredential c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.fingerprint_rounded, color: Color(0xFF10B981), size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enroll Fingerprint for ${c.entityName}',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_rounded, color: Color(0xFF059669)),
                  const SizedBox(width: 10),
                  Text(
                    'Assigned Biometric PIN: ${c.biometricPin}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF065F46)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'How to scan fingerprint on ZKTeco Device:',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text('1. Go to ZKTeco scanner at entrance (Office / Dispensary / Madrassa).', style: GoogleFonts.inter(fontSize: 12)),
            const SizedBox(height: 4),
            Text('2. Press "M/OK" key -> Select "User Mgt" -> "New User" (or Edit User).', style: GoogleFonts.inter(fontSize: 12)),
            const SizedBox(height: 4),
            Text('3. Set User ID = "${c.biometricPin}".', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[800])),
            const SizedBox(height: 4),
            Text('4. Select "Enroll FP" and scan finger 3 times until device beeps green.', style: GoogleFonts.inter(fontSize: 12)),
            const SizedBox(height: 12),
            Text('That\'s it! Once scanned, any future finger scan on that device will instantly auto-log attendance for ${c.entityName}.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[700], fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Got It!'),
          ),
        ],
      ),
    );
  }

  void _showSimulatePunchDialog() {
    final credentials = ZkTecoNetworkService.getAllCredentials();
    String selectedPin = credentials.isNotEmpty ? credentials.first.biometricPin : '101';
    final customPinCtrl = TextEditingController(text: selectedPin);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.fingerprint_rounded, color: Color(0xFF0F766E), size: 28),
              const SizedBox(width: 10),
              Text(
                'Simulate Biometric Scan',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select an enrolled staff member or enter a PIN to simulate a real-time finger punch from the ZKTeco hardware:',
                  style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                if (credentials.isNotEmpty) ...[
                  Text(
                    'Quick Pick Enrolled User:',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: credentials.any((c) => c.biometricPin == selectedPin) ? selectedPin : null,
                        hint: const Text('Choose a person...'),
                        items: credentials.map((c) {
                          return DropdownMenuItem<String>(
                            value: c.biometricPin,
                            child: Text(
                              'PIN ${c.biometricPin} — ${c.entityName} (${c.entityType})',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() {
                              selectedPin = val;
                              customPinCtrl.text = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: customPinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Biometric PIN / Badge #',
                    hintText: 'e.g. 101 or 999',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) => selectedPin = v.trim(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final pin = customPinCtrl.text.trim();
                if (pin.isEmpty) return;
                Navigator.pop(ctx);

                await ZkTecoNetworkService.processIncomingPunch(
                  pin: pin,
                  timestamp: DateTime.now(),
                  deviceIp: _pcIpAddress.isNotEmpty ? _pcIpAddress : '192.168.1.150',
                  deviceSn: 'DEMO_DEVICE_SN',
                  source: 'manual_simulation',
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Simulated scan for PIN $pin! Check Live stream and Attendance tab.'),
                      backgroundColor: const Color(0xFF0F766E),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.touch_app_rounded, size: 16),
              label: const Text('Punch Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
