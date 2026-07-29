// lib/pages/dispensary/hybrid_dispensary_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:another_flushbar/flushbar.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/services/auth_service.dart';
import 'package:gmwf/realtime/connection_manager.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/widgets/connection_status_widget.dart';

import 'package:gmwf/models/patient.dart';
import 'package:gmwf/models/token.dart';
import 'package:gmwf/services/firestore_service.dart';

import 'receptionist/receptionist_screen.dart';
import 'dispensar/dispensar_screen.dart';
import 'dispensar/inventory.dart';
import 'doctor/doctor_screen.dart';
import 'package:gmwf/pages/login_page.dart';

class HybridDispensaryScreen extends StatefulWidget {
  final String branchId;
  final String userId;
  final String userName;
  final String role; // 'rec+dis', 'doc+rec', 'doc+dis', 'doc+rec+dis'

  const HybridDispensaryScreen({
    super.key,
    required this.branchId,
    required this.userId,
    required this.userName,
    required this.role,
  });

  @override
  State<HybridDispensaryScreen> createState() => _HybridDispensaryScreenState();
}

class _HybridDispensaryScreenState extends State<HybridDispensaryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Map<String, dynamic>> _tabs = [];

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  bool _online = true;
  bool _isSyncing = false;
  bool _loadingBranch = true;
  String? _branchName;
  String? _resolvedName;

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  static const Color _teal = Color(0xFF00695C);

  @override
  void initState() {
    super.initState();

    _parseRole();
    _tabController = TabController(length: _tabs.length, vsync: this);

    // Start services once
    SyncService().start(widget.branchId);
    _listenConnectivity();
    _loadBranchName();

    _fetchUserNameAndConnect();

    _connectionSub = ConnectionManager().statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });

    // Run receptionist bootstrap if "rec" is included in role
    if (widget.role.toLowerCase().contains('rec')) {
      _bootstrapReceptionistData(widget.branchId);
    }
  }

  void _parseRole() {
    final r = widget.role.toLowerCase().trim();
    if (r.contains('doc') || r.contains('doctor')) {
      _tabs.add({
        'title': 'Doctor',
        'icon': Icons.medical_services_outlined,
        'widget': DoctorScreen(
          branchId: widget.branchId,
          doctorId: widget.userId,
          doctorName: widget.userName,
          isEmbedded: true,
        ),
      });
    }
    if (r.contains('rec') || r.contains('receptionist')) {
      _tabs.add({
        'title': 'Receptionist',
        'icon': Icons.support_agent_rounded,
        'widget': ReceptionistScreen(
          branchId: widget.branchId,
          receptionistId: widget.userId,
          receptionistName: widget.userName,
          isEmbedded: true,
        ),
      });
    }
    if (r.contains('dis') || r.contains('dispenser') || r.contains('dispensar')) {
      _tabs.add({
        'title': 'Dispenser',
        'icon': Icons.medication_outlined,
        'widget': DispensarScreen(
          branchId: widget.branchId,
          isEmbedded: true,
        ),
      });
    }
    if (r.contains('dis') || r.contains('dispenser') || r.contains('dispensar') || r.contains('doc') || r.contains('inventory')) {
      _tabs.add({
        'title': 'Stock & Inventory',
        'icon': Icons.inventory_2_outlined,
        'widget': InventoryPage(
          branchId: widget.branchId,
          isDispenser: true,
          isEmbedded: true,
        ),
      });
    }
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_online != isOnline && mounted) {
        setState(() => _online = isOnline);
        if (isOnline) {
          _forceSync();
        }
      }
    });
  }

  Future<void> _fetchUserNameAndConnect() async {
    String? name;

    // 1. Try local cache
    try {
      final local = LocalStorageService.getLocalUserByUid(widget.userId);
      name = (local?['username'] as String?)?.trim();
      if (name?.isEmpty == true) name = null;
    } catch (_) {}

    // 2. Fall back to widget param
    name ??= widget.userName.trim().isNotEmpty ? widget.userName.trim() : null;

    if (mounted) setState(() => _resolvedName = name);

    // Start connection
    ConnectionManager().start(
      role: widget.role,
      branchId: widget.branchId,
      username: name,
    );
    if (name != null) {
      RealtimeManager().updateUsername(name);
    }

    // 3. Fetch from Firestore for authoritative name
    try {
      final userData = await AuthService().getUserByUid(widget.userId);
      final firestoreName =
          (userData?['username'] as String?)?.trim() ??
          (userData?['name'] as String?)?.trim();
      if (firestoreName != null && firestoreName.isNotEmpty && firestoreName != name) {
        if (mounted) setState(() => _resolvedName = firestoreName);
        RealtimeManager().updateUsername(firestoreName);
      }
    } catch (e) {
      debugPrint('[HybridScreen] Could not fetch name from Firestore: $e');
    }
  }

  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) {
        setState(() {
          _branchName = 'Free Dispensary';
          _loadingBranch = false;
        });
      }
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .get();
      if (mounted) {
        setState(() {
          _branchName = doc.data()?['name'] ?? 'Free Dispensary';
          _loadingBranch = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _branchName = 'Free Dispensary';
          _loadingBranch = false;
        });
      }
    }
  }

  Future<void> _forceSync() async {
    if (!_online || _isSyncing || !mounted) return;
    setState(() => _isSyncing = true);
    try {
      await SyncService().forceFullRefresh(widget.branchId);
      if (mounted) {
        Flushbar(
          message: 'Full sync completed',
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ).show(context);
      }
    } catch (e) {
      if (mounted) {
        Flushbar(
          message: 'Sync failed: $e',
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _bootstrapReceptionistData(String branchId) async {
    final isOnline = _online;
    if (!isOnline) return;

    final firestoreService = FirestoreService();
    try {
      final existingPatientIds = LocalStorageService.getAllLocalPatients(
              branchId: branchId)
          .map((m) => m['patientId'] as String?)
          .whereType<String>()
          .toSet();

      final List<Patient> patients =
          await firestoreService.getAllPatientsForBranch(branchId);
      for (final patient in patients) {
        final map = patient.toMap();
        final patientId = map['patientId'] as String?;
        if (patientId != null && !existingPatientIds.contains(patientId)) {
          await LocalStorageService.saveLocalPatient(map);
        }
      }

      final existingSerials = LocalStorageService.getLocalEntries(branchId)
          .map((m) => m['serial'] as String?)
          .whereType<String>()
          .toSet();

      final List<Token> tokens =
          await firestoreService.getTodayTokensForBranch(branchId);
      for (final token in tokens) {
        final map = token.toMap();
        final serial = map['serial'] as String?;
        if (serial != null && !existingSerials.contains(serial)) {
          await LocalStorageService.saveEntryLocal(branchId, serial, map);
        }
      }
    } catch (e) {
      debugPrint("Warning: Error bootstrapping receptionist data: $e");
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of GMWF?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (r) => false,
        );
      }
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _connectionSub?.cancel();
    _tabController.dispose();
    ConnectionManager().stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _teal,
        elevation: 6,
        shadowColor: Colors.black26,
        toolbarHeight: isMobile ? 80 : 90,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Image.asset('assets/logo/gmwf-1.png', height: isMobile ? 45 : 55),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Hybrid Desk – ${_resolvedName ?? widget.userName}',
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _branchName ?? 'Free Dispensary',
                    style: TextStyle(
                      fontSize: isMobile ? 13 : 15,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3.5,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: _tabs.map((t) {
            return Tab(
              icon: Icon(t['icon'] as IconData, size: 20),
              text: t['title'] as String,
            );
          }).toList(),
        ),
        actions: [
          if (!isMobile) ...[
            ConnectionStatusBadge(
              status: _connectionStatus,
              onRetry: () => ConnectionManager().reconnectNow(),
            ),
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _online ? Colors.blue.shade700 : Colors.grey.shade600,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_online ? Icons.cloud : Icons.cloud_off, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _online ? 'Internet' : 'Offline',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.sync, color: Colors.white),
            onPressed: _isSyncing ? null : _forceSync,
            tooltip: 'Force full sync',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
            tooltip: 'Log out',
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(), // Keep state and prevent accidental swipe
        children: _tabs.map((t) => t['widget'] as Widget).toList(),
      ),
    );
  }
}
