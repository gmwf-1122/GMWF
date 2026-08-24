import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/services/auth_service.dart';
import 'package:gmwf/realtime/connection_manager.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/widgets/connection_status_widget.dart';
import 'package:gmwf/widgets/gmwf_app_bar.dart';
import 'package:gmwf/services/camp_session_service.dart';
import '../user_settings_dialog.dart';
import 'patient_queue.dart';
import 'patient_info.dart';
import 'doctor_right_panel.dart';
import 'patient_history.dart';
import 'package:gmwf/widgets/camp_selector_chip.dart';
import 'package:gmwf/pages/dispensary/dispensar/inventory.dart';

class DoctorScreen extends StatefulWidget {
  final String branchId;
  final String doctorId;
  final String doctorName;
  final bool isEmbedded;

  const DoctorScreen({
    super.key,
    required this.branchId,
    required this.doctorId,
    required this.doctorName,
    this.isEmbedded = false,
  });

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  Map<String, dynamic>? _selectedPatientData;

  final TextEditingController _complaintController = TextEditingController();
  final TextEditingController _diagnosisController = TextEditingController();

  List<Map<String, dynamic>> _prescriptions = [];
  List<Map<String, dynamic>> _labResults = [];

  bool _isSaving = false;
  String? _username;
  String? _doctorDegree;
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

  // [BUG-13] Remove function returned by addReconnectListener
  VoidCallback? _removeReconnectListener;

  // [BUG-12] Debounce + guard for reconnect-triggered sync
  Timer? _syncDebounce;
  bool _reconnectSyncing = false;

  static const Color _teal = Color(0xFF00695C);

  int _rightPanelKey = 0;

  late TabController _tabController;

  // ── Queue-type resolver ────────────────────────────────────────────────────
  static String resolveQueueType(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) {
      return 'non-zakat';
    }
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    return 'zakat';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    if (!widget.isEmbedded) {
      SyncService().start(widget.branchId);
    }
    _loadBranchName();
    _listenConnectivity();

    CampSessionService.activeCampNotifier.addListener(_onActiveCampChanged);

    // [FIX-USERNAME] Load name first, then start ConnectionManager with it.
    // _fetchDoctorName() starts the connection once the name is resolved so
    // the identify message carries the real name, not just 'doctor'.
    _fetchDoctorName();

    _connectionSub = ConnectionManager().statusStream.listen((s) {
      if (mounted) setState(() => _connectionStatus = s);
      // [BUG-12] Debounce: only trigger sync after 300 ms of stable connection
      if (s.isConnected && !widget.isEmbedded) {
        _syncDebounce?.cancel();
        _syncDebounce = Timer(const Duration(milliseconds: 300), _syncOnReconnect);
      }
    });

    // [BUG-13] Register via listener list — safe alongside DispensarScreen
    if (!widget.isEmbedded) {
      _removeReconnectListener = ConnectionManager().addReconnectListener(_syncOnReconnect);
    }

    _realtimeSub = RealtimeManager().messageStream.listen(_handleRealtimeUpdate);
  }

  // [FIX-USERNAME] Resolve doctor name then start/update connection with it.
  Future<void> _fetchDoctorName() async {
    String? resolvedName;

    // 1. Try local cache first (instant, no network needed).
    final localUser = LocalStorageService.getLocalUserByUid(widget.doctorId);
    resolvedName = (localUser?['username'] as String?)?.trim();
    if (resolvedName?.isEmpty == true) resolvedName = null;
    final localDegree = (localUser?['degree'] as String?)?.trim();
    if (localDegree != null && localDegree.isNotEmpty) {
      _doctorDegree = localDegree;
    }

    // 2. Fall back to the name passed as a widget param.
    resolvedName ??= widget.doctorName.trim().isNotEmpty ? widget.doctorName.trim() : null;

    if (mounted) setState(() => _username = resolvedName);

    // 3. Start connection immediately with whatever name is available.
    if (!widget.isEmbedded) {
      ConnectionManager().start(
        role:     'doctor',
        branchId: widget.branchId,
        username: resolvedName,
      );
      if (resolvedName != null) {
        RealtimeManager().updateUsername(resolvedName);
      }
    }

    // 4. Fetch authoritative name from Firestore.
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.doctorId)
          .get();
      if (!snap.exists) return;
      final firestoreName =
          (snap.data()?['username'] as String?)?.trim() ??
          (snap.data()?['name']     as String?)?.trim() ?? '';
      if (firestoreName.isNotEmpty) {
        if (mounted) setState(() => _username = firestoreName);
        // [FIX-USERNAME] Push updated name into RealtimeManager so future
        // messages carry the correct attribution.
        if (!widget.isEmbedded) {
          RealtimeManager().updateUsername(firestoreName);
        }
      }
      final firestoreDegree = (snap.data()?['degree'] as String?)?.trim() ?? '';
      if (firestoreDegree.isNotEmpty) {
        if (mounted) setState(() => _doctorDegree = firestoreDegree);
      }
    } catch (e) {
      debugPrint('[DoctorScreen] Could not fetch doctor name: $e');
    }
  }

  // FIX-SYNC-2: Upload first, then let triggerUpload() decide whether it is
  // safe to download. Do NOT call downloadTodayTokens() directly here —
  // that would pull stale Firestore data before pending items are uploaded.
  Future<void> _syncOnReconnect() async {
    if (!mounted || _reconnectSyncing) return;
    _reconnectSyncing = true;
    try {
      // triggerUpload() handles upload → conditional download in the right order
      await SyncService().triggerUpload();
      if (mounted) setState(() {});
      debugPrint('[DoctorScreen] ✅ Synced on reconnect');
    } catch (e) {
      debugPrint('[DoctorScreen] Reconnect sync failed: $e');
    } finally {
      _reconnectSyncing = false;
    }
  }

  void _handleRealtimeUpdate(Map<String, dynamic> event) {
    final type = event['event_type'] as String?;
    final rawData = event['data'];
    final data = (rawData is Map) ? Map<String, dynamic>.from(rawData) : Map<String, dynamic>.from(event);
    if (type == null) return;

    final senderId = event['_clientId']?.toString() ?? '';
    final myId = RealtimeManager().clientId;
    if (senderId.isNotEmpty && myId != null && senderId == myId) return;

    if (type == 'token_created' || (type == RealtimeEvents.saveEntry && (data['status'] == 'waiting' || data['status'] == null) && data['prescriptions'] == null)) {
      _handleNewToken(data);
    } else if (type == RealtimeEvents.savePrescription || type == 'prescription_created' || (type == RealtimeEvents.saveEntry && (data['status'] == 'completed' || data['prescriptions'] != null))) {
      _handlePrescriptionUpdate(data);
    } else if (type == 'dispense_completed') {
      _handleDispenseCompleted(data);
    }
  }

  void _handleNewToken(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial.isNotEmpty) {
      LocalStorageService.saveEntryLocal(widget.branchId, serial, data);
    }
    
    // Ignore if not a waiting new token
    final status = (data['status'] ?? '').toString().toLowerCase();
    if (status == 'completed' || status == 'prescribed' || data['prescriptions'] != null) {
      return;
    }

    final activeCamp = CampSessionService.getActiveCamp(widget.branchId);
    if (activeCamp != null && activeCamp.isNotEmpty && activeCamp != 'all') {
      final matches = CampSessionService.matchesCamp(
        selectedCamp: activeCamp,
        dispensaryId: data['dispensaryId']?.toString(),
        campId: data['campId']?.toString(),
        dispensaryTag: data['dispensaryTag']?.toString(),
        serial: serial,
      );
      if (!matches) return;
    }
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Flushbar(
            message: '🎟️ New token: ${data['patientName'] ?? '#${data['serial']}'}',
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
            icon: const Icon(Icons.person_add, color: Colors.white),
          ).show(context);
        }
      });
    }
  }

  void _handlePrescriptionUpdate(Map<String, dynamic> data) {
    final serial = data['serial']?.toString();
    if (serial != null && serial == _selectedPatientData?['serial']) {
      if (mounted) {
        setState(() {
          _complaintController.text = data['complaint'] ?? _complaintController.text;
          _diagnosisController.text = data['diagnosis'] ?? _diagnosisController.text;
          _prescriptions = List.from(data['prescriptions'] ?? _prescriptions);
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
        setState(() => _selectedPatientData?['dispenseStatus'] = 'dispensed');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Flushbar(
              message: '💊 Patient #$serial has been dispensed',
              backgroundColor: Colors.purple.shade700,
              duration: const Duration(seconds: 3),
            ).show(context);
          }
        });
      }
    }
  }

  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).get();
      if (mounted) {
        setState(() {
        _branchName = doc.data()?['name'] ?? 'Free Dispensary';
        _loadingBranch = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
    }
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (_online != online && mounted) {
        setState(() => _online = online);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Flushbar(
              message: online ? 'Internet restored' : 'Offline (LAN still works)',
              backgroundColor: online ? Colors.green.shade700 : Colors.orange.shade700,
              duration: const Duration(seconds: 3),
            ).show(context);
          }
        });
      }
    });
  }

  Future<void> _forceSync() async {
    if (!_online || _isSyncing || !mounted) return;
    setState(() => _isSyncing = true);
    try {
      await SyncService().forceFullRefresh(widget.branchId);
      await LocalStorageService.downloadTodayTokens(widget.branchId);
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Flushbar(message: 'Sync completed', backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3)).show(context);
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Flushbar(message: 'Sync failed: $e', backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 3)).show(context);
        }
      });
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    try { _connectionSub?.cancel(); _connSub?.cancel(); _realtimeSub?.cancel(); } catch (_) {}
    ConnectionManager().stop().catchError((_) {});
    await AuthService().signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  Future<void> _selectPatient(Map<String, dynamic> rawEntry) async {
    if (_isSaving || !mounted) return;
    setState(() => _isSaving = true);
    try {
      _selectedPatientData = Map.from(rawEntry);
      final rawPresc = rawEntry['prescription'];
      final prescription = (rawPresc is Map) ? Map<String, dynamic>.from(rawPresc) : null;

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

      _rightPanelKey++;

      final screenWidth = MediaQuery.of(context).size.width;
      if (screenWidth < 900) _tabController.animateTo(1);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _skipPatient() async {
    if (_selectedPatientData == null || _isSaving || !mounted) return;

    final patient = Map<String, dynamic>.from(_selectedPatientData!);
    final serial = (patient['serial'] ?? patient['id'])?.toString();
    if (serial == null || serial.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final nowIso = DateTime.now().toIso8601String();
      patient['status'] = 'skipped';
      patient['skippedAt'] = nowIso;
      patient['skippedBy'] = _username ?? widget.doctorName;
      patient['updatedAt'] = nowIso;

      // Clear idempotency key so receptionist can issue a new token if patient returns
      final patientId = (patient['patientId'] ?? '').toString();
      final dateKey = CampSessionService.getDateKeyFromSerial(serial);
      if (patientId.isNotEmpty) {
        final idempotencyKey = '${widget.branchId}_${patientId}_$dateKey';
        try {
          if (Hive.isBoxOpen('issued_token_keys')) {
            await Hive.box('issued_token_keys').delete(idempotencyKey);
          }
        } catch (_) {}
      }

      // 1. Save locally in Hive
      await LocalStorageService.saveEntryLocal(widget.branchId, serial, patient);

      // 2. Broadcast via LAN
      try {
        RealtimeManager().sendMessage(RealtimeEvents.payload(
          type: RealtimeEvents.saveEntry,
          branchId: widget.branchId,
          data: patient,
        ));
      } catch (e) {
        debugPrint('[DoctorScreen] Skip LAN broadcast failed: $e');
      }

      // 3. Firestore background sync
      try {
        final dateKey = CampSessionService.getDateKeyFromSerial(serial);
        final queueType = resolveQueueType(patient['queueType']?.toString() ?? patient['status']?.toString());
        await FirebaseFirestore.instance
            .collection('branches').doc(widget.branchId)
            .collection('serials').doc(dateKey)
            .collection(queueType)
            .doc(serial)
            .set({
          'status': 'skipped',
          'skippedAt': nowIso,
          'skippedBy': _username ?? widget.doctorName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[DoctorScreen] Skip Firestore update deferred: $e');
      }

      if (mounted) {
        Flushbar(
          message: '⏩ Patient #$serial skipped',
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 3),
        ).show(context);
      }

      // Clear current inputs
      _complaintController.clear();
      _diagnosisController.clear();
      _prescriptions.clear();
      _labResults.clear();
      _selectedPatientData = null;

      // Auto-select next waiting patient from today's queue
      final userDisp = CampSessionService.getActiveCamp(widget.branchId);
      final todayKey = CampSessionService.resolveShiftAndDateKey().dateKey;
      final waiting = LocalStorageService.getLocalEntries(
        widget.branchId,
        dispensaryId: userDisp,
        filterByCamp: true,
      ).where((e) {
        final dk = (e['dateKey'] ?? '').toString();
        final st = (e['status'] ?? '').toString().toLowerCase();
        return dk == todayKey && st == 'waiting';
      }).toList();

      if (waiting.isNotEmpty) {
        waiting.sort((a, b) {
          final sA = (a['serial'] ?? '').toString();
          final sB = (b['serial'] ?? '').toString();
          return sA.compareTo(sB);
        });
        await _selectPatient(waiting.first);
      } else {
        if (mounted) setState(() {});
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
        ..addAll((d['prescriptions'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []);
      _labResults
        ..clear()
        ..addAll((d['labResults'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []);
      _rightPanelKey++;
    });

    Flushbar(
      message: '🔁 Repeated — ${_prescriptions.length} medicine(s), ${_labResults.length} lab test(s)',
      backgroundColor: Colors.teal.shade700,
      duration: const Duration(seconds: 3),
    ).show(context);
  }

  void _openFullHistory() {
    if (_selectedPatientData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientHistoryPage(
          branchId: widget.branchId,
          patientData: _selectedPatientData!,
          onRepeatLast: (raw) {
            _applyRepeatData(raw);
            final screenWidth = MediaQuery.of(context).size.width;
            if (screenWidth < 900) _tabController.animateTo(1);
          },
        ),
      ),
    );
  }

  bool get _isDark {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final dark = Hive.box('app_settings').get('is_dark_mode');
        if (dark != null) return dark == true;
      }
    } catch (_) {}
    return Theme.of(context).brightness == Brightness.dark;
  }

  PreferredSizeWidget _buildAppBar(bool isMobile, bool isDark) {
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              const Color(0xFF0F172A),
              const Color(0xFF1E293B),
            ]
          : [
              const Color(0xFF004D40), // Premium Emerald Teal
              const Color(0xFF00796B), // Clean Jade Teal
            ],
    );

    return GmwfAppBar(
      title: 'Doctor Panel – ${_username ?? widget.doctorName}',
      subtitle: CampSessionService.getBranchAndCampDisplayName(
        branchName: _branchName ?? 'Free Dispensary',
        branchId: widget.branchId,
        campId: CampSessionService.getActiveCamp(widget.branchId),
      ),
      onTitleLongPress: () => DispensaryUserSettingsDialog.show(
        context,
        branchId: widget.branchId,
        onUserUpdated: () {
          if (mounted) setState(() { _fetchDoctorName(); });
        },
      ),
      titleTooltip: 'Long press for Settings',
      connectionStatus: _connectionStatus,
      onRetryConnection: () => ConnectionManager().reconnectNow(),
      isOnline: _online,
      isSyncing: _isSyncing,
      onSync: _forceSync,
      onLogout: _logout,
      extraActions: [
        if (CampSessionService.hasCampsForBranch(widget.branchId))
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: CampSelectorChip(branchId: widget.branchId),
          ),
        Tooltip(
          message: 'Medicine Inventory',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InventoryPage(
                    branchId: widget.branchId,
                    isDoctor: true,
                    isDispenser: false,
                  ),
                ),
              ),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F5B46),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: isMobile
          ? PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF00A86B),
                labelColor: const Color(0xFF00A86B),
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(icon: Icon(Icons.people, size: 18), text: 'Queue'),
                  Tab(icon: Icon(Icons.medical_services, size: 18), text: 'Prescription'),
                  Tab(icon: Icon(Icons.history, size: 18), text: 'History'),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildPrescriptionPanel() {
    if (_selectedPatientData == null) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.medical_services_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 12),
          Text('Select a patient from the Queue tab',
              style: TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
        ]),
      );
    }

    final resolvedQueueType = resolveQueueType(
      (_selectedPatientData!['queueType']?.toString().isNotEmpty == true
              ? _selectedPatientData!['queueType']
              : _selectedPatientData!['status'])
          ?.toString(),
    );

    return DoctorRightPanel(
      key: ValueKey(_rightPanelKey),
      branchId: widget.branchId,
      selectedPatientData: _selectedPatientData,
      serialId: _selectedPatientData!['serial']?.toString() ?? '',
      doctorId: widget.doctorId,
      doctorName: _username?.isNotEmpty == true ? _username! : widget.doctorName,
      isPhysiotherapist: _doctorDegree?.toLowerCase().contains('physio') == true ||
                         _doctorDegree?.toLowerCase().contains('dpt') == true,
      queueType: resolvedQueueType,
      complaintController: _complaintController,
      diagnosisController: _diagnosisController,
      prescriptions: _prescriptions,
      labResults: _labResults,
      isSaving: _isSaving,
      onAddLabResult: () => setState(() => _labResults.add({'name': 'New Lab Test'})),
      onRemoveLabResult: (i) => setState(() => _labResults.removeAt(i)),
      onRemoveMedicine: (i) => setState(() => _prescriptions.removeAt(i)),
      onEditMedicine: (med) {
        final idx = _prescriptions.indexWhere((m) => m['name'] == med['name']);
        if (idx != -1) setState(() => _prescriptions[idx] = med);
      },
      onSavePrescription: () async {},
      onEntryCompleted: () => setState(() {
        _selectedPatientData = null;
        _complaintController.clear();
        _diagnosisController.clear();
        _prescriptions.clear();
        _labResults.clear();
        _rightPanelKey++;
      }),
      onRepeatData: _applyRepeatData,
      onSkipPatient: _skipPatient,
    );
  }

  Widget _buildHistoryPanel() {
    if (_selectedPatientData == null) {
      return const Center(
        child: Text('Select a patient to view history',
            style: TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 4),
          child: Row(children: [
            const Icon(Icons.history_edu_rounded, color: _teal, size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Visit History',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: _teal)),
            ),
            TextButton.icon(
              onPressed: _openFullHistory,
              icon: const Icon(Icons.open_in_new_rounded, size: 13),
              label: const Text('All Visits',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                foregroundColor: _teal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: _teal, width: 1),
                ),
              ),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: PatientHistory(
            branchId: widget.branchId,
            patientData: _selectedPatientData,
            compactMode: true,
            onRepeatLast: _applyRepeatData,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = _isDark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    final body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF0B1120), const Color(0xFF0F172A)]
              : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)],
        ),
      ),
      child: isMobile ? _buildMobileBody(isDark) : _buildDesktopBody(isDark),
    );

    if (widget.isEmbedded) return body;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFE8F5E9),
      appBar: _buildAppBar(isMobile, isDark),
      body: body,
    );
  }

  Widget _buildMobileBody(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark
        ? const BorderSide(color: Color(0xFF334155), width: 1)
        : BorderSide.none;

    return TabBarView(
      controller: _tabController,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Card(
            color: cardColor,
            elevation: isDark ? 2 : 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: cardBorder),
            child: PatientQueue(
              branchId: widget.branchId,
              doctorId: widget.doctorId,
              doctorName: _username?.isNotEmpty == true ? _username! : widget.doctorName,
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
                color: cardColor,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: cardBorder),
                clipBehavior: Clip.antiAlias,
                child: PatientInfo(
                  patientData: _selectedPatientData,
                  doctorId: widget.doctorId,
                  doctorName: _username?.isNotEmpty == true ? _username! : widget.doctorName,
                  branchId: widget.branchId,
                  onSkipPatient: _skipPatient,
                  onVitalsUpdated: (updatedVitals) {
                    if (mounted && _selectedPatientData != null) {
                      setState(() {
                        _selectedPatientData!['vitals'] = updatedVitals;
                      });
                    }
                  },
                ),
              ),
            Expanded(
              child: Card(
                color: cardColor,
                elevation: isDark ? 2 : 4,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: cardBorder),
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
            color: cardColor,
            elevation: isDark ? 2 : 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: cardBorder),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildHistoryPanel(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopBody(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark
        ? const BorderSide(color: Color(0xFF334155), width: 1)
        : const BorderSide(color: Color(0xFFE2E8F0), width: 1);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Queue Column
          Expanded(
            flex: 3,
            child: Card(
              color: cardColor,
              elevation: isDark ? 2 : 4,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: cardBorder,
              ),
              child: PatientQueue(
                branchId: widget.branchId,
                doctorId: widget.doctorId,
                doctorName: _username?.isNotEmpty == true ? _username! : widget.doctorName,
                selectedPatient: _selectedPatientData,
                onPatientSelected: _selectPatient,
                isSaving: _isSaving,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Right Workspace Column
          Expanded(
            flex: 8,
            child: Column(
              children: [
                // Top Patient Info & Vitals Header Card
                SizedBox(
                  height: 168,
                  child: Card(
                    color: cardColor,
                    elevation: isDark ? 2 : 4,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: cardBorder,
                    ),
                    child: PatientInfo(
                      patientData: _selectedPatientData,
                      doctorId: widget.doctorId,
                      doctorName: _username?.isNotEmpty == true ? _username! : widget.doctorName,
                      branchId: widget.branchId,
                      onSkipPatient: _skipPatient,
                      onVitalsUpdated: (updatedVitals) {
                        if (mounted && _selectedPatientData != null) {
                          setState(() {
                            _selectedPatientData!['vitals'] = updatedVitals;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Bottom Clinical Panels: Prescription Form & Visit History
                Expanded(
                  child: Row(
                    children: [
                      // Prescription Panel
                      Expanded(
                        flex: 7,
                        child: Card(
                          color: cardColor,
                          elevation: isDark ? 2 : 4,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: cardBorder,
                          ),
                          child: _buildPrescriptionPanel(),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Visit History Panel
                      Expanded(
                        flex: 4,
                        child: Card(
                          color: cardColor,
                          elevation: isDark ? 2 : 4,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: cardBorder,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: _buildHistoryPanel(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onActiveCampChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syncDebounce?.cancel();
    // [BUG-13] Unregister from ConnectionManager's listener list
    _removeReconnectListener?.call();
    CampSessionService.activeCampNotifier.removeListener(_onActiveCampChanged);
    if (!widget.isEmbedded) {
      ConnectionManager().stop();
    }
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    _complaintController.dispose();
    _diagnosisController.dispose();
    super.dispose();
  }
}
