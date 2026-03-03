// lib/pages/doctor_screen.dart
// FIXES:
//   1. DOCTOR NAME: _fetchDoctorName() now checks local cache → widget param
//      → Firestore users collection so it's never blank/unknown.
//      The resolved name (_username) is passed to DoctorRightPanel via the
//      new `doctorName` + `doctorId` props so every saved prescription
//      carries the correct doctor name.
//   2. QUEUE TYPE: resolveQueueType() is now a static helper on this class.
//      The normalised queueType is passed to DoctorRightPanel via the new
//      `queueType` prop so prescriptions are written to the correct
//      Firestore sub-collection (zakat / non-zakat / gmwf) — never blindly
//      to 'zakat'.
// MOBILE: Tab-based navigation on narrow screens (Queue / Prescription / History).
// Desktop layout unchanged.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';

import '../../../services/local_storage_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/auth_service.dart';
import '../../../realtime/connection_manager.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';
import '../../../widgets/connection_status_widget.dart';
import 'patient_queue.dart';
import 'patient_info.dart';
import 'doctor_right_panel.dart';
import 'patient_history.dart';
import '../../inventory_doc.dart';

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

class _DoctorScreenState extends State<DoctorScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _selectedPatientData;

  final TextEditingController _complaintController = TextEditingController();
  final TextEditingController _diagnosisController = TextEditingController();

  List<Map<String, dynamic>> _prescriptions = [];
  List<Map<String, dynamic>> _labResults = [];

  bool _isSaving = false;
  String? _username; // resolved doctor display name
  String? _branchName;
  bool _online = true;
  bool _isSyncing = false;
  bool _loadingBranch = true;

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  static const Color _teal = Color(0xFF00695C);

  int _rightPanelKey = 0;

  late TabController _tabController;

  // ─── Queue-type resolver (static — used here AND exported for DoctorRightPanel) ─
  /// Converts any known variant of a patient status / queueType string into
  /// the canonical Firestore collection name: 'zakat' | 'non-zakat' | 'gmwf'
  static String resolveQueueType(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'non-zakat' ||
        s == 'non zakat' ||
        s == 'nonzakat' ||
        s == 'non_zakat' ||
        s.startsWith('non')) {
      return 'non-zakat';
    }
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') {
      return 'gmwf';
    }
    return 'zakat';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

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

    _realtimeSub =
        RealtimeManager().messageStream.listen(_handleRealtimeUpdate);
  }

  void _handleRealtimeUpdate(Map<String, dynamic> event) {
    final type = event['event_type'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? event;
    if (type == null) return;

    final senderId = event['_clientId']?.toString() ?? '';
    final myId = RealtimeManager().clientId;
    if (senderId.isNotEmpty && myId != null && senderId == myId) return;

    if (type == 'token_created' || type == RealtimeEvents.saveEntry) {
      _handleNewToken(data);
    } else if (type == RealtimeEvents.savePrescription ||
        type == 'prescription_created') {
      _handlePrescriptionUpdate(data);
    } else if (type == 'dispense_completed') {
      _handleDispenseCompleted(data);
    }
  }

  void _handleNewToken(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial.isNotEmpty) {
      Hive.box(LocalStorageService.entriesBox)
          .put('${widget.branchId}-$serial', data);
    }
    if (mounted) {
      setState(() {});
      Flushbar(
        message:
            '🎟️ New token: ${data['patientName'] ?? '#${data['serial']}'}',
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
        icon: const Icon(Icons.person_add, color: Colors.white),
      ).show(context);
    }
  }

  void _handlePrescriptionUpdate(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial == _selectedPatientData?['serial']) {
      if (mounted) {
        setState(() {
          _complaintController.text =
              data['complaint'] ?? _complaintController.text;
          _diagnosisController.text =
              data['diagnosis'] ?? _diagnosisController.text;
          _prescriptions =
              List.from(data['prescriptions'] ?? _prescriptions);
          _labResults = List.from(data['labResults'] ?? _labResults);
          _rightPanelKey++;
        });
      }
    }
  }

  void _handleDispenseCompleted(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial == _selectedPatientData?['serial']) {
      if (mounted) {
        setState(
            () => _selectedPatientData?['dispenseStatus'] = 'dispensed');
        Flushbar(
          message: '💊 Patient #$serial has been dispensed',
          backgroundColor: Colors.purple.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }
    }
  }

  // ── FIX 1: robust doctor-name resolution ────────────────────────────────
  Future<void> _fetchDoctorName() async {
    // Step 1: local user cache (fastest, works offline)
    final localUser =
        LocalStorageService.getLocalUserByUid(widget.doctorId);
    final localName =
        (localUser?['username'] as String?)?.trim() ?? '';
    if (localName.isNotEmpty && mounted) {
      setState(() => _username = localName);
      return; // good enough — no need for Firestore round-trip
    }

    // Step 2: name already passed in from login screen
    final passedName = widget.doctorName.trim();
    if (passedName.isNotEmpty && mounted) {
      setState(() => _username = passedName);
      // still try Firestore in background for the most up-to-date value
    }

    // Step 3: fetch from Firestore users collection
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.doctorId)
          .get();
      if (!snap.exists) return;
      final firestoreName =
          (snap.data()?['username'] as String?)?.trim() ??
              (snap.data()?['name'] as String?)?.trim() ??
              '';
      if (firestoreName.isNotEmpty && mounted) {
        setState(() => _username = firestoreName);
      }
    } catch (e) {
      debugPrint('[DoctorScreen] Could not fetch doctor name from Firestore: $e');
      // Already set from step 1 or 2 — no crash
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

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (_online != online && mounted) {
        setState(() => _online = online);
        Flushbar(
          message:
              online ? 'Internet restored' : 'Offline (LAN still works)',
          backgroundColor:
              online ? Colors.green.shade700 : Colors.orange.shade700,
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
      Flushbar(
              message: 'Sync completed',
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3))
          .show(context);
    } catch (e) {
      Flushbar(
              message: 'Sync failed: $e',
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3))
          .show(context);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    try {
      await ConnectionManager().stop().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      _connectionSub?.cancel();
      _connSub?.cancel();
      _realtimeSub?.cancel();
    } catch (_) {}
    try {
      await AuthService().signOut().timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    }
  }

  Future<void> _selectPatient(Map<String, dynamic> rawEntry) async {
    if (_isSaving || !mounted) return;
    setState(() => _isSaving = true);
    try {
      _selectedPatientData = Map.from(rawEntry);
      final prescription =
          rawEntry['prescription'] as Map<String, dynamic>?;

      _prescriptions
        ..clear()
        ..addAll(prescription != null
            ? List<Map<String, dynamic>>.from(
                (prescription['prescriptions'] as List<dynamic>?)
                        ?.map((e) =>
                            Map<String, dynamic>.from(e as Map)) ??
                    [])
            : []);

      _labResults
        ..clear()
        ..addAll(prescription != null
            ? List<Map<String, dynamic>>.from(
                (prescription['labResults'] as List<dynamic>?)
                        ?.map((e) =>
                            Map<String, dynamic>.from(e as Map)) ??
                    [])
            : []);

      _complaintController.text =
          prescription?['complaint']?.toString() ?? '';
      _diagnosisController.text =
          prescription?['diagnosis']?.toString() ?? '';

      _rightPanelKey++;

      final screenWidth = MediaQuery.of(context).size.width;
      if (screenWidth < 900) {
        _tabController.animateTo(1);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _applyRepeatData(Map<String, dynamic> d) {
    if (!mounted) return;
    setState(() {
      _complaintController.text = d['complaint']?.toString() ?? '';
      _diagnosisController.text = d['diagnosis']?.toString() ?? '';

      _prescriptions
        ..clear()
        ..addAll(
          (d['prescriptions'] as List<dynamic>?)
                  ?.map((e) =>
                      Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
        );

      _labResults
        ..clear()
        ..addAll(
          (d['labResults'] as List<dynamic>?)
                  ?.map((e) =>
                      Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
        );

      _rightPanelKey++;
    });

    Flushbar(
      message:
          '🔁 Repeated — ${_prescriptions.length} medicine(s), ${_labResults.length} lab test(s)',
      backgroundColor: Colors.teal.shade700,
      duration: const Duration(seconds: 3),
    ).show(context);
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    if (isMobile) {
      return AppBar(
        backgroundColor: _teal,
        toolbarHeight: 56,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Image.asset('assets/logo/gmwf.png', height: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Doctor – ${_username ?? '...'}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 3),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connectionStatus.isConnected
                  ? Colors.greenAccent
                  : Colors.redAccent,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 3),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _online ? Colors.lightBlueAccent : Colors.grey,
            ),
          ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 6, vertical: 16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
                icon: const Icon(Icons.sync,
                    color: Colors.white, size: 20),
                onPressed: _forceSync),
          IconButton(
            icon: const Icon(Icons.inventory,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => InventoryDocPage(
                        branchId: widget.branchId))),
          ),
          IconButton(
              icon: const Icon(Icons.logout,
                  color: Colors.white, size: 20),
              onPressed: _logout),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.people, size: 18), text: 'Queue'),
            Tab(
                icon:
                    Icon(Icons.medical_services, size: 18),
                text: 'Prescription'),
            Tab(
                icon: Icon(Icons.history, size: 18),
                text: 'History'),
          ],
        ),
      );
    }

    // Desktop AppBar
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
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              if (!_loadingBranch)
                Text(_branchName ?? 'Free Dispensary',
                    style: const TextStyle(
                        fontSize: 16, color: Colors.white70)),
            ],
          ),
        ),
      ]),
      centerTitle: false,
      actions: [
        ConnectionStatusBadge(
            status: _connectionStatus,
            onRetry: () => ConnectionManager().reconnectNow()),
        Container(
          margin: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 16),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _online
                ? Colors.blue.shade700
                : Colors.grey.shade600,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_online ? Icons.cloud : Icons.cloud_off,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(_online ? 'Internet' : 'No Internet',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ]),
        ),
        IconButton(
          icon: _isSyncing
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.sync,
                  size: 32, color: Colors.white),
          onPressed: _isSyncing ? null : _forceSync,
        ),
        IconButton(
          icon: const Icon(Icons.inventory,
              size: 32, color: Colors.white),
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      InventoryDocPage(branchId: widget.branchId))),
        ),
        IconButton(
            icon: const Icon(Icons.logout,
                size: 32, color: Colors.white),
            onPressed: _logout),
        const SizedBox(width: 12),
      ],
    );
  }

  // ── FIX 2: resolve queueType before building the right panel ─────────────
  Widget _buildPrescriptionPanel() {
    if (_selectedPatientData == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medical_services_outlined,
                size: 60, color: Colors.grey),
            SizedBox(height: 12),
            Text('Select a patient from the Queue tab',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    // Prefer the already-stored queueType on the entry; fall back to status.
    // Both are normalised through resolveQueueType so the Firestore path
    // is always correct regardless of what the token screen originally stored.
    final resolvedQueueType = resolveQueueType(
      (_selectedPatientData!['queueType']?.toString().isNotEmpty == true
              ? _selectedPatientData!['queueType']
              : _selectedPatientData!['status'])
          ?.toString(),
    );

    debugPrint(
        '[DoctorScreen] patient queueType="${_selectedPatientData!['queueType']}" '
        'status="${_selectedPatientData!['status']}" → resolved="$resolvedQueueType"');

    return DoctorRightPanel(
      key: ValueKey(_rightPanelKey),
      branchId: widget.branchId,
      selectedPatientData: _selectedPatientData,
      serialId: _selectedPatientData!['serial']?.toString() ?? '',
      // ── NEW props — pass doctor identity so prescriptions are saved correctly
      doctorId: widget.doctorId,
      doctorName: _username?.isNotEmpty == true
          ? _username!
          : widget.doctorName,
      // ── NEW prop — pass normalised queueType for correct Firestore path
      queueType: resolvedQueueType,
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
                  duration: const Duration(seconds: 3))
              .show(context);
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
    );
  }

  Widget _buildHistoryPanel() {
    if (_selectedPatientData == null) {
      return const Center(
        child: Text('Select a patient to view history',
            style: TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center),
      );
    }
    return PatientHistory(
      branchId: widget.branchId,
      // Pass full patient data so history can distinguish siblings that share
      // a guardian CNIC using the stable patientId key.
      patientData: _selectedPatientData,
      onRepeatLast: _applyRepeatData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Scaffold(
      appBar: _buildAppBar(isMobile),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
          ),
        ),
        child:
            isMobile ? _buildMobileBody() : _buildDesktopBody(),
      ),
    );
  }

  Widget _buildMobileBody() {
    return TabBarView(
      controller: _tabController,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Card(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: PatientQueue(
              branchId: widget.branchId,
              selectedPatient: _selectedPatientData,
              onPatientSelected: _selectPatient,
              isSaving: _isSaving,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            if (_selectedPatientData != null)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child:
                    PatientInfo(patientData: _selectedPatientData),
              ),
            Expanded(
              child: Card(
                elevation: 4,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildPrescriptionPanel(),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Card(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildHistoryPanel(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 20),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Card(
                  elevation: 12,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  child: PatientQueue(
                    branchId: widget.branchId,
                    selectedPatient: _selectedPatientData,
                    onPatientSelected: _selectPatient,
                    isSaving: _isSaving,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 8,
                child: Column(children: [
                  SizedBox(
                    height: 230,
                    child: Card(
                      elevation: 12,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      child: PatientInfo(
                          patientData: _selectedPatientData),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Row(children: [
                      Expanded(
                        flex: 7,
                        child: Card(
                          elevation: 12,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(24)),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: _buildPrescriptionPanel(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 4,
                        child: Card(
                          elevation: 12,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(24)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _buildHistoryPanel(),
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
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    _complaintController.dispose();
    _diagnosisController.dispose();
    super.dispose();
  }
}