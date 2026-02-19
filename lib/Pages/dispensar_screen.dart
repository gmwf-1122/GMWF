// lib/pages/dispensar_screen.dart
// Connection replaced with ConnectionManager (auto-discovery). UI unchanged.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';

import '../config/constants.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import '../realtime/connection_manager.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';
import '../widgets/connection_status_widget.dart';
import 'inventory.dart';
import 'patient_form.dart';
import 'patient_list.dart';

class DispensarScreen extends StatefulWidget {
  final String branchId;
  const DispensarScreen({super.key, required this.branchId});

  @override
  State<DispensarScreen> createState() => _DispensarScreenState();
}

class _DispensarScreenState extends State<DispensarScreen> {
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  bool _online = true;
  bool _isSyncing = false;
  bool _isLoggingOut = false;

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  String? _dispenserName;
  String? _branchName;
  bool _loadingBranch = true;

  Map<String, dynamic>? _selectedQueueEntry;

  static const Color _teal = Color(0xFF00695C);

  @override
  void initState() {
    super.initState();
    SyncService().start(widget.branchId);
    _listenConnectivity();
    _fetchDispenserName();
    _loadBranchName();

    _connectionSub = ConnectionManager().statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ConnectionManager().start(role: 'dispenser', branchId: widget.branchId);
      _startBackgroundSync();
    });

    _realtimeSub = RealtimeManager().messageStream.listen(_handleRealtimeMessage);
  }

  Future<void> _startBackgroundSync() async {
    try {
      await SyncService().initialFullDownload(widget.branchId);
    } catch (e) {
      debugPrint('Background sync error: $e');
    }
  }

  void _handleRealtimeMessage(Map<String, dynamic> event) {
    final type = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? event;
    if (type == null || data.isEmpty) return;

    final senderId = event['_clientId']?.toString() ?? '';
    final myId = RealtimeManager().clientId;
    if (senderId.isNotEmpty && myId != null && senderId == myId) return;

    final serial = data['serial']?.toString()?.trim();
    final branch = (data['branchId'] ?? event['branchId'] ?? event['_senderBranch'] ?? '')
        .toString().toLowerCase().trim();

    if (serial == null) return;
    if (branch.isNotEmpty && branch != widget.branchId.toLowerCase().trim()) return;

    if (type == RealtimeEvents.savePrescription || type == 'prescription_created') {
      LocalStorageService.saveLocalPrescription(data);

      final entryKey = '${widget.branchId}-$serial';
      final box = Hive.box(LocalStorageService.entriesBox);
      final entry = box.get(entryKey);
      if (entry != null) {
        final updated = Map<String, dynamic>.from(entry);
        updated['status'] = 'completed';
        updated['completedAt'] = data['completedAt'] ?? DateTime.now().toIso8601String();
        updated['prescription'] = data;
        box.put(entryKey, updated);
      }
      if (serial == _selectedQueueEntry?['serial'] && mounted) setState(() {});

      Flushbar(
        message: '💊 Prescription ready for #$serial',
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 5),
      ).show(context);
    } else if (type == RealtimeEvents.saveEntry || type == 'token_created') {
      Hive.box(LocalStorageService.entriesBox).put('${widget.branchId}-$serial', data);
      if (mounted) setState(() {});
      Flushbar(
        message: '🎟️ New token: #$serial',
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
      ).show(context);
    } else if (type == 'dispense_completed') {
      final box = Hive.box(LocalStorageService.entriesBox);
      final key = '${widget.branchId}-$serial';
      final entry = box.get(key);
      if (entry != null) {
        final updated = Map<String, dynamic>.from(entry);
        updated['dispenseStatus'] = 'dispensed';
        box.put(key, updated);
      }
      if (serial == _selectedQueueEntry?['serial'] && mounted) {
        setState(() => _selectedQueueEntry = null);
      }
    }
  }

  Future<void> _fetchDispenserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final local = LocalStorageService.getLocalUserByUid(user.uid);
    if (mounted) setState(() => _dispenserName = local?['username'] ?? user.email?.split('@').first);
  }

  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('branches').doc(widget.branchId).get();
      if (mounted) setState(() { _branchName = doc.data()?['name'] ?? 'Free Dispensary'; _loadingBranch = false; });
    } catch (_) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
    }
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) async {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_online != isOnline && mounted) {
        setState(() => _online = isOnline);
        Flushbar(
          message: isOnline ? 'Internet restored — syncing...' : 'Offline (LAN still works)',
          backgroundColor: isOnline ? Colors.green.shade700 : Colors.orange.shade700,
          duration: const Duration(seconds: 4),
        ).show(context);
        if (isOnline) _forceSync();
      }
    });
  }

  Future<void> _forceSync() async {
    if (!_online || _isSyncing || !mounted) return;
    setState(() => _isSyncing = true);
    try {
      await SyncService().forceFullRefresh(widget.branchId);
      Flushbar(message: 'Full sync completed', backgroundColor: Colors.green.shade700, duration: const Duration(seconds: 4)).show(context);
    } catch (e) {
      Flushbar(message: 'Sync failed: $e', backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 5)).show(context);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // ─── FIXED LOGOUT ──────────────────────────────────────────────────────────
  // Each step is independently try/caught so nothing can block navigation.
  // The mounted check and navigation always runs last regardless of errors above.
  Future<void> _logout() async {
    if (_isLoggingOut) return; // Prevent double-tap
    if (mounted) setState(() => _isLoggingOut = true);

    // Step 1: Stop LAN connection — non-blocking, ignore errors
    try {
      await ConnectionManager().stop().timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('[Dispenser] ConnectionManager.stop() timed out — ignoring'),
      );
    } catch (e) {
      debugPrint('[Dispenser] ConnectionManager.stop() error (ignoring): $e');
    }

    // Step 2: Cancel subscriptions before navigating
    try { _connectionSub?.cancel(); } catch (_) {}
    try { _connSub?.cancel(); } catch (_) {}
    try { _realtimeSub?.cancel(); } catch (_) {}

    // Step 3: Sign out from Firebase — non-blocking, ignore errors
    try {
      await AuthService().signOut().timeout(
        const Duration(seconds: 5),
        onTimeout: () => debugPrint('[Dispenser] AuthService.signOut() timed out — navigating anyway'),
      );
    } catch (e) {
      debugPrint('[Dispenser] AuthService.signOut() error (navigating anyway): $e');
    }

    // Step 4: Navigate — always runs no matter what happened above
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    }
  }
  // ──────────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _teal,
      elevation: 10,
      shadowColor: Colors.black26,
      toolbarHeight: 100,
      automaticallyImplyLeading: false,
      title: Row(children: [
        Image.asset('assets/logo/gmwf.png', height: 60),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Dispensary – ${_dispenserName ?? 'Loading...'}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              if (!_loadingBranch)
                Text(_branchName ?? 'Free Dispensary',
                    style: const TextStyle(fontSize: 16, color: Colors.white70)),
            ],
          ),
        ),
      ]),
      centerTitle: false,
      actions: [
        ConnectionStatusBadge(
          status: _connectionStatus,
          onRetry: () => ConnectionManager().reconnectNow(),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _online ? Colors.blue.shade700 : Colors.grey.shade600,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_online ? Icons.cloud : Icons.cloud_off, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(_online ? 'Internet' : 'No Internet',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          ]),
        ),
        IconButton(
          icon: _isSyncing
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.sync, size: 32, color: Colors.white),
          tooltip: 'Full Sync',
          onPressed: _isSyncing ? null : _forceSync,
        ),
        IconButton(
          icon: const Icon(Icons.inventory_2_outlined, size: 32, color: Colors.white),
          tooltip: 'Inventory',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryPage(branchId: widget.branchId))),
        ),
        // Logout button — shows spinner while logging out to prevent double-tap
        _isLoggingOut
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.logout, size: 32, color: Colors.white),
                tooltip: 'Logout',
                onPressed: _logout,
              ),
        const SizedBox(width: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(LocalStorageService.entriesBox).listenable(),
      builder: (context, entriesBox, _) {
        return ValueListenableBuilder<Box>(
          valueListenable: Hive.box(LocalStorageService.prescriptionsBox).listenable(),
          builder: (context, prescriptionsBox, _) {
            return Scaffold(
              appBar: _buildAppBar(),
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isTablet = constraints.maxWidth >= 1000;
                    return Row(children: [
                      Container(
                        width: isTablet ? 480 : constraints.maxWidth * 0.42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(36),
                            bottomRight: Radius.circular(36),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: PatientList(
                            branchId: widget.branchId,
                            selectedPatient: _selectedQueueEntry,
                            onPatientSelected: (e) => setState(() => _selectedQueueEntry = e),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Card(
                            elevation: 12,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: _selectedQueueEntry == null
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.medical_information_outlined, size: 120, color: Colors.grey.shade400),
                                          const SizedBox(height: 24),
                                          Text('Select a patient to dispense medicines',
                                              style: TextStyle(fontSize: 22, color: Colors.grey.shade700), textAlign: TextAlign.center),
                                        ],
                                      ),
                                    )
                                  : PatientForm(
                                      branchId: widget.branchId,
                                      queueEntry: _selectedQueueEntry!,
                                      onDispensed: () => setState(() => _selectedQueueEntry = null),
                                      dispenserName: _dispenserName,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }
}