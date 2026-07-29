// lib/pages/settings/biometric_device_manager_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/biometric_device_config.dart';
import '../../models/biometric_credential.dart';
import '../../services/zkteco_network_service.dart';
import '../../services/local_storage_service.dart';

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
  bool _isAutoAssigning = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Ensure ZKTeco network server is running
    ZkTecoNetworkService.startServer();

    // Listen to realtime punch stream
    _punchSubscription = ZkTecoNetworkService.punchStream.listen((punch) {
      if (mounted) {
        setState(() {
          _livePunches.insert(0, punch);
          if (_livePunches.length > 100) _livePunches.removeLast();
        });
      }
    });
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Biometric Attendance Settings & Devices',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF10B981),
          indicatorWeight: 3,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.normal),
          tabs: const [
            Tab(icon: Icon(Icons.router_rounded), text: 'ZKTeco Devices'),
            Tab(icon: Icon(Icons.badge_rounded), text: 'User Biometric PINs'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Live Wi-Fi Logs'),
          ],
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

  // ── Server Status Banner ───────────────────────────────────────────────────

  Widget _buildServerStatusBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: ZkTecoNetworkService.isServerRunningNotifier,
      builder: (context, isRunning, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: isRunning ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
          child: Row(
            children: [
              Icon(
                isRunning ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                color: isRunning ? const Color(0xFF059669) : const Color(0xFFDC2626),
                size: 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRunning
                          ? 'ZKTeco Wi-Fi Listener Active (Port 8088 / 4370)'
                          : 'ZKTeco Wi-Fi Listener Stopped',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: isRunning ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRunning
                          ? 'Listening for Wi-Fi punches across Office, Dispensary, and Madrassa devices on network "gmwf".'
                          : 'Click start server to enable real-time ZKTeco punch capture.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isRunning ? const Color(0xFF10B981) : Colors.grey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count Punches',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
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
                  backgroundColor: isRunning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          padding: const EdgeInsets.all(20),
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
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Map ZKTeco Wi-Fi readers to physical building locations (Office, Dispensary, Madrassa)',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditDeviceDialog(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (devices.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.router_rounded, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          'No Biometric Devices Configured',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Click "Add Device" or turn on a ZKTeco device connected to Wi-Fi "gmwf" for auto-discovery.',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
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

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: isOnline ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
                            child: Icon(
                              Icons.fingerprint_rounded,
                              color: isOnline ? const Color(0xFF10B981) : Colors.grey,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                dev.deviceName,
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  dev.buildingLocation,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'IP: ${dev.ipAddress} | Port: ${dev.port} | SN: ${dev.serialNumber.isEmpty ? "N/A" : dev.serialNumber} | Last Seen: $lastHb',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline ? const Color(0xFF10B981) : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, color: Colors.blue),
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

  // ── Tab 2: User Biometric PINs ─────────────────────────────────────────────

  Widget _buildUserPinsTab() {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(LocalStorageService.biometricCredentialsBox).listenable(),
      builder: (context, box, child) {
        final credentials = ZkTecoNetworkService.getAllCredentials();
        final filtered = credentials.where((c) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return c.entityName.toLowerCase().contains(q) ||
              c.biometricPin.toLowerCase().contains(q) ||
              c.entityType.toLowerCase().contains(q);
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search by Name, Biometric PIN, or Role...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showAddCredentialDialog(),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Link User PIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No biometric credentials linked yet. Click "Bulk Auto-Assign PINs" to assign PINs to all existing users!',
                            style: GoogleFonts.inter(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (ctx, i) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final c = filtered[i];
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'PIN\n${c.biometricPin}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: const Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                              title: Text(
                                c.entityName,
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Role: ${c.entityType.toUpperCase()} | Enrolled: ${DateFormat('yyyy-MM-dd').format(c.enrolledAt)}',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.fingerprint_rounded, color: Color(0xFF10B981)),
                                    tooltip: 'Enroll Fingerprint Steps for PIN ${c.biometricPin}',
                                    onPressed: () => _showEnrollFingerprintGuide(c),
                                  ),
                                  const SizedBox(width: 4),
                                  Chip(
                                    label: Text(c.deviceSource),
                                    backgroundColor: const Color(0xFFF1F5F9),
                                  ),
                                ],
                              ),
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

  // ── Tab 3: Live Wi-Fi Punch Logs ───────────────────────────────────────────

  Widget _buildLiveLogsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Incoming Wi-Fi Scans',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Real-time stream of finger scans captured from ZKTeco devices across all buildings',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: _livePunches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.stream_rounded, size: 48, color: Colors.grey),
                          const SizedBox(height: 8),
                          Text(
                            'Waiting for finger scans on ZKTeco devices...',
                            style: GoogleFonts.inter(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _livePunches.length,
                      itemBuilder: (ctx, i) {
                        final p = _livePunches[i];
                        final isMapped = p['isMapped'] == true;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isMapped ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                            child: Icon(
                              isMapped ? Icons.check_circle_rounded : Icons.help_outline_rounded,
                              color: isMapped ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                          title: Text(
                            '${p['entityName']} (PIN: ${p['pin']})',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Location: ${p['buildingLocation']} | IP: ${p['deviceIp']} | Time: ${p['timestamp']}',
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                          trailing: Container(
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
    final ipCtrl = TextEditingController(text: device?.ipAddress ?? '192.168.1.101');
    final portCtrl = TextEditingController(text: (device?.port ?? 4370).toString());
    String location = device?.buildingLocation ?? 'Office/Dasterkhwaan';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'Edit ZKTeco Device' : 'Add ZKTeco Wi-Fi Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Device Name (e.g. Madrassa Gate Scanner)'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: location,
              decoration: const InputDecoration(labelText: 'Building Location'),
              items: const [
                DropdownMenuItem(value: 'Office/Dasterkhwaan', child: Text('Building 1: Office & Dasterkhwaan')),
                DropdownMenuItem(value: 'Dispensary', child: Text('Building 2: Dispensary')),
                DropdownMenuItem(value: 'Madrassa', child: Text('Building 3: Madrassa')),
              ],
              onChanged: (val) {
                if (val != null) location = val;
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(labelText: 'Static IP Address on Wi-Fi "gmwf"'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port (default 4370 / 8088)'),
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
              final newConfig = BiometricDeviceConfig(
                deviceId: device?.deviceId ?? DateTime.now().millisecondsSinceEpoch.toString(),
                deviceName: nameCtrl.text.trim(),
                buildingLocation: location,
                ipAddress: ipCtrl.text.trim(),
                port: int.tryParse(portCtrl.text.trim()) ?? 4370,
                status: 'Online',
              );
              await ZkTecoNetworkService.saveDeviceConfig(newConfig);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Device'),
          ),
        ],
      ),
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
              value: type,
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
}
