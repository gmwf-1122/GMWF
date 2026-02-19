// lib/pages/doctor_screen.dart
// FIXED: Removed nested Padding inside Patient Queue card, added clipBehavior,
// unified card radius to 24, fixed PatientInfo card padding

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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
import 'patient_queue.dart';
import 'patient_info.dart';
import 'doctor_right_panel.dart';
import 'patient_history.dart';
import 'inventory_doc.dart';

class DoctorScreen extends StatefulWidget {
  final String branchId;
  final String doctorId;
  final String doctorName;

  const DoctorScreen({
    super.key,
    required this.branchId,
    required this.doctorId,
    required this.doctorName,
  });

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  Map<String, dynamic>? _selectedPatientData;

  final TextEditingController _complaintController = TextEditingController();
  final TextEditingController _diagnosisController = TextEditingController();

  List<Map<String, dynamic>> _prescriptions = [];
  List<Map<String, dynamic>> _labResults    = [];

  bool _isSaving      = false;
  String? _username;
  String? _branchName;
  bool _online        = true;
  bool _isSyncing     = false;
  bool _loadingBranch = true;

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  static const Color _teal = Color(0xFF00695C);

  // Incrementing this key forces DoctorRightPanel to fully reconstruct so
  // its initState can re-seed _selectedQuickTests from the new widget.labResults.
  int _rightPanelKey = 0;

  @override
  void initState() {
    super.initState();
    SyncService().start(widget.branchId);
    _fetchDoctorName();
    _loadBranchName();
    _listenConnectivity();

    _connectionSub = ConnectionManager().statusStream.listen((s) {
      if (mounted) setState(() => _connectionStatus = s);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ConnectionManager().start(role: 'doctor', branchId: widget.branchId);
    });

    _realtimeSub = RealtimeManager().messageStream.listen(_handleRealtimeUpdate);
  }

  // ── Realtime ──────────────────────────────────────────────────────────────
  void _handleRealtimeUpdate(Map<String, dynamic> event) {
    final type = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? event;
    if (type == null) return;

    final senderId = event['_clientId']?.toString() ?? '';
    final myId     = RealtimeManager().clientId;
    if (senderId.isNotEmpty && myId != null && senderId == myId) return;

    if (type == 'token_created' || type == RealtimeEvents.saveEntry) {
      _handleNewToken(data);
    } else if (type == RealtimeEvents.savePrescription || type == 'prescription_created') {
      _handlePrescriptionUpdate(data);
    } else if (type == 'dispense_completed') {
      _handleDispenseCompleted(data);
    }
  }

  void _handleNewToken(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial.isNotEmpty) {
      Hive.box(LocalStorageService.entriesBox).put('${widget.branchId}-$serial', data);
    }
    if (mounted) {
      setState(() {});
      Flushbar(
        message: '🎟️ New token: ${data['patientName'] ?? '#${data['serial']}'}',
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
        icon: const Icon(Icons.person_add, color: Colors.white),
      ).show(context);
    }
  }

  void _handlePrescriptionUpdate(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial == _selectedPatientData?['serial']) {
      if (mounted) setState(() {
        _complaintController.text = data['complaint'] ?? _complaintController.text;
        _diagnosisController.text = data['diagnosis'] ?? _diagnosisController.text;
        _prescriptions = List.from(data['prescriptions'] ?? _prescriptions);
        _labResults    = List.from(data['labResults']    ?? _labResults);
        _rightPanelKey++;
      });
    }
  }

  void _handleDispenseCompleted(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial == _selectedPatientData?['serial']) {
      if (mounted) {
        setState(() => _selectedPatientData?['dispenseStatus'] = 'dispensed');
        Flushbar(
          message: '💊 Patient #$serial has been dispensed',
          backgroundColor: Colors.purple.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }
    }
  }

  Future<void> _fetchDoctorName() async {
    final user = LocalStorageService.getLocalUserByUid(widget.doctorId);
    if (mounted) setState(() => _username = user?['username'] ?? widget.doctorName);
  }

  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('branches').doc(widget.branchId).get();
      if (mounted) setState(() {
        _branchName    = doc.data()?['name'] ?? 'Free Dispensary';
        _loadingBranch = false;
      });
    } catch (_) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
    }
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (_online != online && mounted) {
        setState(() => _online = online);
        Flushbar(
          message: online ? 'Internet restored' : 'Offline (LAN still works)',
          backgroundColor: online ? Colors.green.shade700 : Colors.orange.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }
    });
  }

  Future<void> _forceSync() async {
    if (!_online || _isSyncing || !mounted) return;
    setState(() => _isSyncing = true);
    try {
      await SyncService().forceFullRefresh(widget.branchId);
      Flushbar(message: 'Sync completed',
          backgroundColor: Colors.green.shade700, duration: const Duration(seconds: 3)).show(context);
    } catch (e) {
      Flushbar(message: 'Sync failed: $e',
          backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 3)).show(context);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    try { await ConnectionManager().stop().timeout(const Duration(seconds: 3)); } catch (_) {}
    try { _connectionSub?.cancel(); _connSub?.cancel(); _realtimeSub?.cancel(); } catch (_) {}
    try { await AuthService().signOut().timeout(const Duration(seconds: 5)); } catch (_) {}
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  // ── Patient selection ─────────────────────────────────────────────────────
  Future<void> _selectPatient(Map<String, dynamic> rawEntry) async {
    if (_isSaving || !mounted) return;
    setState(() => _isSaving = true);
    try {
      _selectedPatientData = Map.from(rawEntry);
      final prescription   = rawEntry['prescription'] as Map<String, dynamic>?;

      _prescriptions
        ..clear()
        ..addAll(prescription != null
            ? List<Map<String, dynamic>>.from(
                (prescription['prescriptions'] as List<dynamic>?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [])
            : []);

      _labResults
        ..clear()
        ..addAll(prescription != null
            ? List<Map<String, dynamic>>.from(
                (prescription['labResults'] as List<dynamic>?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [])
            : []);

      _complaintController.text = prescription?['complaint']?.toString() ?? '';
      _diagnosisController.text = prescription?['diagnosis']?.toString() ?? '';

      // Rebuild the right panel so initState re-seeds _selectedQuickTests
      _rightPanelKey++;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── REPEAT LAST VISIT ─────────────────────────────────────────────────────
  void _applyRepeatData(Map<String, dynamic> d) {
    if (!mounted) return;
    setState(() {
      _complaintController.text = d['complaint']?.toString() ?? '';
      _diagnosisController.text = d['diagnosis']?.toString() ?? '';

      _prescriptions
        ..clear()
        ..addAll(
          (d['prescriptions'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
        );

      _labResults
        ..clear()
        ..addAll(
          (d['labResults'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
        );

      _rightPanelKey++;
    });

    Flushbar(
      message: '🔁 Repeated — ${_prescriptions.length} medicine(s), '
          '${_labResults.length} lab test(s)',
      backgroundColor: Colors.teal.shade700,
      duration: const Duration(seconds: 3),
    ).show(context);
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
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
              Text('Doctor Panel – ${_username ?? 'Loading...'}',
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
              ? const SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.sync, size: 32, color: Colors.white),
          tooltip: 'Sync',
          onPressed: _isSyncing ? null : _forceSync,
        ),
        IconButton(
          icon: const Icon(Icons.inventory, size: 32, color: Colors.white),
          tooltip: 'Inventory',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => InventoryDocPage(branchId: widget.branchId))),
        ),
        IconButton(
          icon: const Icon(Icons.logout, size: 32, color: Colors.white),
          tooltip: 'Logout',
          onPressed: _logout,
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── Patient queue ──────────────────────────────────────────
                  // FIX: Removed the extra Padding(24) inside the card.
                  // Added clipBehavior: Clip.antiAlias so PatientQueue's
                  // teal header clips cleanly to the card's rounded corners,
                  // eliminating the "card inside a card" double-border look.
                  // Reduced radius from 36 → 24 for a tighter, cleaner fit.
                  Expanded(
                    flex: 3,
                    child: Card(
                      elevation: 12,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: PatientQueue(
                        branchId: widget.branchId,
                        selectedPatient: _selectedPatientData,
                        onPatientSelected: _selectPatient,
                        isSaving: _isSaving,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),

                  // ── Right column ───────────────────────────────────────────
                  Expanded(
                    flex: 8,
                    child: Column(children: [

                      // Patient info card
                      // FIX: Reduced height slightly and removed the extra
                      // inner Padding from PatientInfo (handled inside the widget).
                      SizedBox(
                        height: 230,
                        child: Card(
                          elevation: 12,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: PatientInfo(patientData: _selectedPatientData),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Expanded(
                        child: Row(children: [

                          // Prescription panel
                          Expanded(
                            flex: 7,
                            child: Card(
                              elevation: 12,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: _selectedPatientData != null
                                    ? DoctorRightPanel(
                                        key: ValueKey(_rightPanelKey),
                                        branchId: widget.branchId,
                                        selectedPatientData: _selectedPatientData,
                                        serialId: _selectedPatientData!['serial']?.toString() ?? '',
                                        complaintController: _complaintController,
                                        diagnosisController: _diagnosisController,
                                        prescriptions: _prescriptions,
                                        labResults: _labResults,
                                        isSaving: _isSaving,
                                        onAddLabResult: () =>
                                            setState(() => _labResults.add({'name': 'New Lab Test'})),
                                        onRemoveLabResult: (i) =>
                                            setState(() => _labResults.removeAt(i)),
                                        onRemoveMedicine: (i) =>
                                            setState(() => _prescriptions.removeAt(i)),
                                        onEditMedicine: (med) {
                                          final idx = _prescriptions
                                              .indexWhere((m) => m['name'] == med['name']);
                                          if (idx != -1) setState(() => _prescriptions[idx] = med);
                                        },
                                        onSavePrescription: () async {
                                          if (mounted) {
                                            Flushbar(
                                              message: 'Prescription saved',
                                              backgroundColor: Colors.green.shade700,
                                              duration: const Duration(seconds: 3),
                                            ).show(context);
                                          }
                                        },
                                        onEntryCompleted: () => setState(() {
                                          _selectedPatientData = null;
                                          _complaintController.clear();
                                          _diagnosisController.clear();
                                          _prescriptions.clear();
                                          _labResults.clear();
                                          _rightPanelKey++;
                                        }),
                                        onRepeatData: _applyRepeatData,
                                      )
                                    : const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.medical_services_outlined,
                                                size: 80, color: Colors.grey),
                                            SizedBox(height: 16),
                                            Text('Select a patient to start consultation',
                                                style: TextStyle(fontSize: 20, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),

                          // Patient history
                          Expanded(
                            flex: 4,
                            child: Card(
                              elevation: 12,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: _selectedPatientData != null
                                    ? PatientHistory(
                                        patientCnic:
                                            _selectedPatientData!['patientCnic']?.toString() ??
                                            _selectedPatientData!['cnic']?.toString() ?? '',
                                        branchId: widget.branchId,
                                        onRepeatLast: _applyRepeatData,
                                      )
                                    : const Center(
                                        child: Text('Patient history will appear here',
                                            style: TextStyle(fontSize: 18, color: Colors.grey)),
                                      ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    _complaintController.dispose();
    _diagnosisController.dispose();
    super.dispose();
  }
}