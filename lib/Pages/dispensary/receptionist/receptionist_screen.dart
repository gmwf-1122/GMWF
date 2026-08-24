// lib/pages/dispensary/receptionist/receptionist_screen.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/foundation.dart';
import 'package:gmwf/services/auth_service.dart';
import 'package:gmwf/services/local_storage_service.dart' as lss;
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/realtime/connection_manager.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/widgets/connection_status_widget.dart';
import 'package:gmwf/widgets/gmwf_app_bar.dart';
import '../user_settings_dialog.dart';
import 'patient_register.dart';
import 'token_screen.dart';

class ReceptionistScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String receptionistName;
  final bool isEmbedded;

  const ReceptionistScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
    required this.receptionistName,
    this.isEmbedded = false,
  });

  @override
  State<ReceptionistScreen> createState() => _ReceptionistScreenState();
}

class _ReceptionistScreenState extends State<ReceptionistScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String? _username;
  String? _branchName;
  String _pendingCnic = '';
  String _activeSection = 'token';

  final GlobalKey<PatientRegisterPageState> _registerKey =
      GlobalKey<PatientRegisterPageState>();
  final GlobalKey<TokenScreenState> _tokenKey =
      GlobalKey<TokenScreenState>();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  bool _online = true;
  bool _isSyncing = false;
  bool _loadingBranch = true;
  bool _sortNewestFirst = true;
  String _selectedSessionFilter = 'all';
  String _selectedCampFilter = 'all';

  bool get _hasMultiCamps => CampSessionService.hasCampsForBranch(widget.branchId);

  // Listenables
  late final ValueListenable<Box> _entriesListenable;
  late final ValueListenable<Box> _patientsListenable;

  // Manual refresh notifier for token log
  final ValueNotifier<int> _refreshNotifier = ValueNotifier<int>(0);

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  static const Color _teal = Color(0xFF00695C);
  static const int _tabToken = 0;
  // ignore: unused_field
  static const int _tabLog = 1;
  static const int _tabRegister = 2;

  late TabController _mobileTabController;

  bool get _isKarachi {
    final b = widget.branchId.toLowerCase().trim();
    return b.contains('karachi') || b.contains('haji') || b.contains('saddar') || b.contains('kapaya');
  }

  bool get _isDark {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        return Hive.box('app_settings').get('is_dark_mode', defaultValue: false) == true;
      }
    } catch (_) {}
    return false;
  }

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 3, vsync: this);

    if (_hasMultiCamps) {
      final active = CampSessionService.getActiveCamp(widget.branchId);
      if (active != null && active.isNotEmpty && active != 'all') {
        _selectedCampFilter = active;
      }
    }

    _entriesListenable =
        Hive.box(lss.LocalStorageService.entriesBox).listenable();
    _patientsListenable =
        Hive.box(lss.LocalStorageService.patientsBox).listenable();

    if (!widget.isEmbedded) {
      SyncService().start(widget.branchId);
    }
    _loadBranchName();
    _listenConnectivity();
    if (!widget.isEmbedded) {
      _startBackgroundSync();
    }

    // [FIX-USERNAME] Load name first, then start ConnectionManager with it.
    // _fetchReceptionistName() starts the connection once the name is resolved.
    CampSessionService.activeCampNotifier.addListener(_onActiveCampChanged);
    _fetchReceptionistName();

    _connectionSub = ConnectionManager().statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });

    _realtimeSub = RealtimeManager().messageStream.listen((event) async {
      final type = event['event_type'] as String?;
      final rawData = event['data'];
      final data = (rawData is Map) ? Map<String, dynamic>.from(rawData) : null;

      debugPrint('[Receptionist] 📨 Got event: $type');

      // TOKEN REVERSAL APPROVED
      if (type == 'token_reversal_approved') {
        final eventBranch = data?['branchId'] as String?;
        if (eventBranch != widget.branchId) return;

        final tokenSerial = data?['tokenSerial'] as String?;
        if (tokenSerial == null || tokenSerial.isEmpty) return;

        final box = Hive.box(lss.LocalStorageService.entriesBox);
        final directKey = '${widget.branchId}-$tokenSerial';

        if (box.containsKey(directKey)) {
          await box.delete(directKey);
          await box.flush();
          debugPrint('[Receptionist] ✅ Direct key delete successful: $directKey');
        } else {
          bool deleted = false;
          for (final k in box.keys.toList()) {
            final v = box.get(k);
            if (v is Map && v['serial']?.toString() == tokenSerial) {
              await box.delete(k);
              await box.flush();
              debugPrint('[Receptionist] ✅ Scan delete successful: key=$k');
              deleted = true;
              break;
            }
          }
          if (!deleted) {
            debugPrint('[Receptionist] ⚠️ Token not found locally, forcing download');
            await lss.LocalStorageService.downloadTodayTokens(widget.branchId);
          }
        }

        // Force UI refresh
        if (mounted) {
          _refreshNotifier.value++;
          setState(() {});
        }
        return;
      }

      // PATIENT EDIT APPROVED
      if (type == 'patient_edit_approved') {
        final eventBranch = data?['branchId'] as String?;
        if (eventBranch != widget.branchId) return;

        final patientId = data?['patientId'] as String?;
        final rawChanges = data?['changes'];
        final changes = (rawChanges is Map) ? Map<String, dynamic>.from(rawChanges) : null;

        if (patientId != null && changes != null && changes.isNotEmpty) {
          final allPatients = lss.LocalStorageService.getAllLocalPatients(
              branchId: widget.branchId);
          final existing = allPatients
              .where((p) => p['patientId'] == patientId)
              .firstOrNull;

          if (existing != null) {
            final updated = Map<String, dynamic>.from(existing)
              ..addAll(lss.LocalStorageService.sanitize(changes));
            await lss.LocalStorageService.saveLocalPatient(updated);
          } else {
            await lss.LocalStorageService.downloadAllPatients(widget.branchId);
          }
          await lss.LocalStorageService.updateActiveEntriesForPatient(widget.branchId, patientId, changes);

          if (mounted) setState(() {});
        }
        return;
      }

      // PRESCRIPTION SAVED BY DOCTOR -> TRIGGER RECEPTIONIST TOAST
      if (type == RealtimeEvents.savePrescription ||
          type == 'prescription_created' ||
          (type == RealtimeEvents.saveEntry &&
              (data?['status'] == 'completed' || data?['prescriptions'] != null))) {
        final eventBranch =
            data?['branchId'] as String? ?? event['branchId'] as String?;
        if (eventBranch == null || eventBranch == widget.branchId) {
          _showPrescriptionNotification(data);
        }
      }

      // Other events that should trigger UI refresh
      if (type == RealtimeEvents.saveEntry ||
          type == RealtimeEvents.savePrescription ||
          type == 'dispense_completed' ||
          type == 'token_created' ||
          type == 'prescription_created') {
        if (mounted) setState(() {});
      }
    });
  }

  String? _lastNotifiedSerial;
  DateTime? _lastNotificationTime;

  void _showPrescriptionNotification(Map<String, dynamic>? data) {
    if (!mounted || data == null) return;

    final serial =
        (data['serial'] ?? data['tokenNumber'] ?? '').toString().trim();
    final now = DateTime.now();

    // Prevent duplicate toast spam if doctor sends multiple events for the same prescription
    if (serial.isNotEmpty &&
        serial == _lastNotifiedSerial &&
        _lastNotificationTime != null &&
        now.difference(_lastNotificationTime!) < const Duration(seconds: 5)) {
      return;
    }

    _lastNotifiedSerial = serial;
    _lastNotificationTime = now;

    final patientName =
        (data['patientName'] ?? data['name'] ?? 'Patient').toString().trim();
    final doctorName = (data['doctorName'] ?? 'Doctor').toString().trim();
    final serialSuffix = serial.contains('-') ? serial.split('-').last : serial;
    final tokenDisplay = serialSuffix.isNotEmpty ? '#$serialSuffix' : serial;

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    Flushbar(
      titleText: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Color(0xFF10B981),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Doctor Ready – Send Next Patient',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
      messageText: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 13, color: Color(0xFFCBD5E1), height: 1.3),
            children: [
              TextSpan(
                text: doctorName.isNotEmpty ? '$doctorName ' : 'Doctor ',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const TextSpan(text: 'finished consultation for '),
              TextSpan(
                text: '$tokenDisplay $patientName',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF34D399),
                ),
              ),
              const TextSpan(
                  text: '. Please call and send in the next patient.'),
            ],
          ),
        ),
      ),
      backgroundColor: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(16),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      flushbarPosition: FlushbarPosition.TOP,
      duration: const Duration(seconds: 6),
      animationDuration: const Duration(milliseconds: 350),
      boxShadows: [
        BoxShadow(
          color: const Color(0xFF10B981).withValues(alpha: 0.35),
          blurRadius: 18,
          spreadRadius: 1,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
      borderColor: const Color(0xFF10B981).withValues(alpha: 0.6),
      borderWidth: 1.4,
    ).show(context);
  }

  // [FIX-USERNAME] Resolve receptionist name then start/update connection with it.
  Future<void> _fetchReceptionistName() async {
    String? resolvedName;

    // 1. Try local cache first (fast, no network needed).
    try {
      final user = lss.LocalStorageService.getLocalUserByUid(widget.receptionistId);
      resolvedName = (user?['username'] as String?)?.trim();
      if (resolvedName?.isEmpty == true) resolvedName = null;
    } catch (_) {}

    // 2. Fall back to the name passed as a widget param.
    resolvedName ??= widget.receptionistName.trim().isNotEmpty
        ? widget.receptionistName.trim()
        : null;

    if (mounted) setState(() => _username = resolvedName);

    // 3. Start connection immediately with whatever name is available.
    if (!widget.isEmbedded) {
      ConnectionManager().start(
        role:     'receptionist',
        branchId: widget.branchId,
        username: resolvedName,
      );
      if (resolvedName != null) {
        RealtimeManager().updateUsername(resolvedName);
      }
    }

    // 4. Optionally fetch authoritative name from Firestore if local was stale.
    //    Receptionist name is usually reliable from widget props / local cache,
    //    but if it differs from Firestore we update in the background.
    try {
      final userData = await AuthService().getUserByUid(widget.receptionistId);
      if (userData != null && Hive.isBoxOpen('app_settings')) {
        await Hive.box('app_settings').put('user_data', userData);
        await Hive.box('app_settings').put('currentUser', userData);
      }
      final firestoreName =
          (userData?['username'] as String?)?.trim() ??
          (userData?['name']     as String?)?.trim();
      if (mounted) {
        setState(() {
          if (firestoreName != null && firestoreName.isNotEmpty) {
            _username = firestoreName;
          }
        });
        if (firestoreName != null && firestoreName.isNotEmpty && !widget.isEmbedded) {
          RealtimeManager().updateUsername(firestoreName);
        }
      }
    } catch (e) {
      debugPrint('[Receptionist] Could not fetch name from Firestore: $e');
    }
  }

  Future<void> _startBackgroundSync() async {
    try {
      await lss.LocalStorageService.downloadTodayTokens(widget.branchId);
      final settings = Hive.box('app_settings');
      final key = 'initial_download_done_${widget.branchId}';
      if (!settings.get(key, defaultValue: false)) {
        SyncService().initialFullDownload(widget.branchId).then((_) {
          settings.put(key, true);
        });
      }
    } catch (e) {
      debugPrint('[ReceptionistScreen] Background sync failed: $e');
    }
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_online != isOnline && mounted) {
        setState(() => _online = isOnline);
        if (isOnline) _forceSync();
      }
    });
  }

  void _onActiveCampChanged() {
    if (!mounted) return;
    if (_hasMultiCamps) {
      final active = CampSessionService.getActiveCamp(widget.branchId);
      if (active != null && active.isNotEmpty && active != 'all') {
        _selectedCampFilter = active;
      }
    }
    setState(() {});
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
      await lss.LocalStorageService.downloadTodayTokens(widget.branchId);
      if (mounted) {
        Flushbar(
          message: 'Full sync completed',
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ).show(context);
      }
    } catch (e) {
      if (mounted) {
        Flushbar(
          message: 'Sync failed: $e',
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ).show(context);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // NEW: Dedicated refresh for token log
  Future<void> _refreshTokenLog() async {
    if (!mounted) return;

    setState(() => _isSyncing = true);

    try {
      // Immediate UI feedback
      _refreshNotifier.value++;

      // Re-download today's tokens (most reliable for reversal issues)
      await lss.LocalStorageService.downloadTodayTokens(widget.branchId);

      debugPrint('[Receptionist] Token log manually refreshed');
    } catch (e) {
      debugPrint('[Receptionist] Manual refresh failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _refreshNotifier.value++; // Final tick to ensure rebuild
      }
    }
  }

  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    if (mounted) setState(() => _isLoggingOut = true);
    try { _connectionSub?.cancel(); _connSub?.cancel(); _realtimeSub?.cancel(); } catch (_) {}
    ConnectionManager().stop().catchError((_) {});
    await AuthService().signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  void _handlePatientNotFound(String cnic) {
    setState(() {
      _pendingCnic = cnic;
      _activeSection = 'register';
    });
    _mobileTabController.animateTo(_tabRegister);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerKey.currentState?.prefillCnic(cnic);
    });
  }

  void _onPatientRegistered(String patientIdOrCnic) {
    final clean = patientIdOrCnic.contains('_child_')
        ? patientIdOrCnic.split('_child_').first
        : patientIdOrCnic;
    setState(() {
      _pendingCnic = clean;
      _activeSection = 'token';
    });
    if (_mobileTabController.length > _tabToken) {
      _mobileTabController.animateTo(_tabToken);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tokenKey.currentState?.focusAndFillCnic(clean);
    });
  }

  Future<void> _requestTokenReverse(Map<String, dynamic> entry) async {
    final serial = entry['serial'] as String? ?? 'N/A';
    final patientName = entry['patientName'] as String? ?? 'Unknown';
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Token Reversal',
            style: TextStyle(color: Colors.orange)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Token: #$serial',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Patient: $patientName'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.undo),
            label: const Text('Send Request'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800]),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final requesterName = (_username?.isNotEmpty == true)
        ? _username!
        : widget.receptionistName;

    try {
      final requestId = 'req_reversal_${widget.receptionistId}_${DateTime.now().millisecondsSinceEpoch}';
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .doc(requestId)
          .set({
        'type': 'token_reversal',
        'requestType': 'token_reversal',
        'status': 'pending',
        'branchId': widget.branchId,
        'receptionistId': widget.receptionistId,
        'receptionistName': requesterName,
        'requesterName': requesterName,
        'requestedBy': widget.receptionistId,
        'tokenSerial': serial,
        'patientId': entry['patientId'] ?? '',
        'patientName': patientName,
        'queueType': entry['queueType'] ?? 'unknown',
        'originalCreatedAt': entry['createdAt'],
        'reason': reasonCtrl.text.trim().isNotEmpty
            ? reasonCtrl.text.trim()
            : null,
        'requestedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'decision': null,
      });

      if (mounted) {
        Flushbar(
          message: 'Reversal request sent for #$serial',
          backgroundColor: Colors.orange[800]!,
          duration: const Duration(seconds: 4),
        ).show(context);
      }
    } catch (e) {
      if (mounted) {
        Flushbar(
          message: 'Failed to send request: $e',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ).show(context);
      }
    }
  }

  bool _isWaitingOnly(Map<String, dynamic> entry) {
    final status = (entry['status'] as String?)?.toLowerCase().trim() ?? '';
    if (status.isNotEmpty && status != 'waiting') return false;
    final hasPrescription =
        (entry['prescriptionId'] as String?)?.isNotEmpty == true;
    if (hasPrescription) return false;
    return true;
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    return GmwfAppBar(
      title: 'Receptionist – ${_username ?? widget.receptionistName}',
      subtitle: CampSessionService.getBranchAndCampDisplayName(
        branchName: _branchName ?? 'Free Dispensary',
        branchId: widget.branchId,
        campId: CampSessionService.getActiveCamp(),
      ),
      onTitleLongPress: () => DispensaryUserSettingsDialog.show(
        context,
        branchId: widget.branchId,
        onUserUpdated: () {
          if (mounted) setState(() { _fetchReceptionistName(); });
        },
      ),
      titleTooltip: 'Long press for Settings',
      connectionStatus: _connectionStatus,
      onRetryConnection: () => ConnectionManager().reconnectNow(),
      isOnline: _online,
      isSyncing: _isSyncing,
      onSync: _forceSync,
      onLogout: _logout,
      isLoggingOut: _isLoggingOut,
      bottom: isMobile
          ? PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: TabBar(
                controller: _mobileTabController,
                indicatorColor: const Color(0xFF00A86B),
                labelColor: const Color(0xFF00A86B),
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(icon: Icon(Icons.token, size: 18), text: 'Token'),
                  Tab(icon: Icon(Icons.list_alt, size: 18), text: 'Log'),
                  Tab(icon: Icon(Icons.person_add, size: 18), text: 'Register'),
                ],
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> _getUserData() {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final userData = Hive.box('app_settings').get('user_data') ?? Hive.box('app_settings').get('currentUser');
        if (userData is Map) return Map<String, dynamic>.from(userData);
      }
    } catch (_) {}
    return {};
  }

  List<Map<String, dynamic>> _getFilteredTodayTokens() {
    final today = CampSessionService.resolveShiftAndDateKey().dateKey;
    final activeShift = CampSessionService.getCurrentSession();
    final userData = _getUserData();
    final scheduledCamps = CampSessionService.getMatchingScheduledCamps(userData);
    final effectiveCamp = _hasMultiCamps
        ? (scheduledCamps.isNotEmpty
            ? scheduledCamps.first
            : CampSessionService.getActiveCamp(widget.branchId))
        : null;

    final rawEntries = lss.LocalStorageService.getLocalEntries(widget.branchId);

    final myId = widget.receptionistId.trim().toLowerCase();
    final myName = (_username ?? widget.receptionistName).trim().toLowerCase();

    final filtered = rawEntries.where((e) {
      // 1. Date filter (strictly today)
      final dk = (e['dateKey'] as String?);
      if (dk != today) return false;

      final serial = (e['serial'] ?? e['id'])?.toString();
      if (!CampSessionService.isSerialMatchingBranch(serial, widget.branchId)) return false;

      // 2. Deleted status filter
      final st = (e['status'] as String?)?.toLowerCase().trim();
      final syncSt = (e['syncStatus'] as String?)?.toLowerCase().trim();
      if (st == 'deleted' || syncSt == 'deleted') return false;

      // 3. Must have valid patient name or cnic
      final name = (e['patientName'] ?? e['name'] ?? '').toString().trim().toLowerCase();
      final cnic = (e['patientCnic'] ?? e['cnic'] ?? e['guardianCnic'] ?? '').toString().trim();
      if ((name.isEmpty || name == 'unknown patient' || name == 'unknown') && cnic.isEmpty) {
        return false;
      }

      // 4. Strict USER ONLY filter (Only this logged-in user's issued tokens!)
      final cb = (e['createdBy'] ?? e['receptionistId'] ?? e['addedById'] ?? '').toString().trim().toLowerCase();
      final cbn = (e['createdByName'] ?? e['receptionistName'] ?? e['performedBy'] ?? e['by'] ?? '').toString().trim().toLowerCase();

      bool matchesUser = false;
      if (myId.isNotEmpty && cb.isNotEmpty) {
        if (cb == myId || cb.contains(myId) || myId.contains(cb)) {
          matchesUser = true;
        }
      }
      if (myName.isNotEmpty && cbn.isNotEmpty) {
        if (cbn == myName || cbn.contains(myName) || myName.contains(cbn)) {
          matchesUser = true;
        }
      }
      // If neither ID nor Name matched, strictly reject (e.g. Kashif's tokens when Ahad is logged in)
      if (!matchesUser) return false;

      // 5. Strict Camp Isolation
      if (_hasMultiCamps && effectiveCamp != null && effectiveCamp.isNotEmpty && effectiveCamp != 'all') {
        final matches = CampSessionService.matchesCamp(
          selectedCamp: effectiveCamp,
          dispensaryId: e['dispensaryId']?.toString(),
          campId: e['campId']?.toString(),
          dispensaryTag: e['dispensaryTag']?.toString(),
          serial: serial,
        );
        if (!matches) return false;
      }

      // 6. Strict Shift Isolation
      final eSession = (e['session'] as String?)?.trim().toLowerCase() ?? '';
      if (eSession.isNotEmpty) {
        if (eSession != activeShift) return false;
      } else {
        final rawTime = e['timestamp'] ?? e['createdAt'] ?? e['date'];
        if (rawTime != null) {
          final dt = DateTime.tryParse(rawTime.toString());
          if (dt != null && CampSessionService.getCurrentSession(dt) != activeShift) {
            return false;
          }
        }
      }

      return true;
    }).toList();

    final Map<String, Map<String, dynamic>> uniqueBySerial = {};
    for (final e in filtered) {
      final s = (e['serial'] ?? e['id'] ?? '').toString().trim().toUpperCase();
      if (s.isEmpty) continue;
      if (!uniqueBySerial.containsKey(s)) {
        uniqueBySerial[s] = e;
      } else {
        final existingName = (uniqueBySerial[s]!['patientName'] ?? uniqueBySerial[s]!['name'] ?? '').toString().toLowerCase();
        final currentName = (e['patientName'] ?? e['name'] ?? '').toString().toLowerCase();
        if (existingName.contains('unknown') && !currentName.contains('unknown')) {
          uniqueBySerial[s] = e;
        }
      }
    }

    return uniqueBySerial.values.toList();
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<Map<String, String>> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((i) => i['id'] == value) ? value : items.first['id'],
          isDense: true,
          icon: Icon(Icons.arrow_drop_down,
              size: 16, color: isDark ? const Color(0xFF38BDF8) : _teal),
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: items.map((i) {
            return DropdownMenuItem<String>(
              value: i['id'],
              child: Text(i['label']!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  )),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isMobile) {
    final todayEntries = _getFilteredTodayTokens();

    int zakat = 0, nonZakat = 0, gmwf = 0;
    int zakatAmount = 0, nonZakatAmount = 0;

    for (final e in todayEntries) {
      final qt = (e['queueType'] as String?)?.toLowerCase().trim() ?? 'unknown';
      final days = _getDaysOfMedicine(e);
      switch (qt) {
        case 'zakat':
          zakat++;
          zakatAmount += 20 * days;
          break;
        case 'non-zakat':
          nonZakat++;
          nonZakatAmount += 100 * days;
          break;
        case 'gmwf':
          gmwf++;
          break;
        default:
          zakat++;
          zakatAmount += 20 * days;
      }
    }

    final total = zakat + nonZakat + gmwf;
    final totalAmount = zakatAmount + nonZakatAmount;

    final cards = [
      _compactSummaryCard(
        _isKarachi ? 'PKR 20' : 'Zakat',
        zakat,
        'PKR $zakatAmount',
        const Color(0xFF00875A), // Solid Emerald Green
        Icons.volunteer_activism_rounded,
        isMobile: isMobile,
      ),
      _compactSummaryCard(
        _isKarachi ? 'PKR 100' : 'Non-Zakat',
        nonZakat,
        _isKarachi && nonZakat == 0 ? 'Disabled 🔒' : 'PKR $nonZakatAmount',
        const Color(0xFF00875A),
        Icons.person_outline_rounded,
        isMobile: isMobile,
        isOutlined: true,
        outlineColor: const Color(0xFF00875A), // Green Outline on White Card
      ),
      _compactSummaryCard(
        'GMWF',
        gmwf,
        'PKR 0',
        const Color(0xFFD97706), // Solid Amber
        null,
        isImage: true,
        isMobile: isMobile,
      ),
      _compactSummaryCard(
        'Total',
        total,
        'PKR $totalAmount',
        const Color(0xFFD97706),
        Icons.people_outline_rounded,
        isMobile: isMobile,
        isOutlined: true,
        outlineColor: const Color(0xFFD97706), // Amber Outline on White Card
      ),
    ];

    return Row(
      children: cards
          .map((c) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 4),
                  child: c,
                ),
              ))
          .toList(),
    );
  }

  int _getDaysOfMedicine(Map<String, dynamic> entry) {
    final topLevel = entry['daysOfMedicine'];
    if (topLevel is int) return topLevel.clamp(1, 99);
    final presc = entry['prescription'];
    if (presc is Map) {
      final nested = presc['daysOfMedicine'];
      if (nested is int) return nested.clamp(1, 99);
    }
    return 1;
  }

  Widget _compactSummaryCard(
    String title,
    int count,
    String amount,
    Color solidColor,
    IconData? icon, {
    bool isImage = false,
    bool isMobile = false,
    bool isOutlined = false,
    Color? outlineColor,
  }) {
    final effectiveOutline = outlineColor ?? solidColor;
    final bgColor = isOutlined
        ? (_isDark ? const Color(0xFF1E293B) : Colors.white)
        : solidColor;
    final primaryTextColor = isOutlined
        ? (_isDark ? Colors.white : effectiveOutline)
        : Colors.white;
    final secondaryTextColor = isOutlined
        ? (_isDark
            ? const Color(0xFF94A3B8)
            : effectiveOutline.withValues(alpha: 0.85))
        : Colors.white.withValues(alpha: 0.85);

    return Container(
      height: isMobile ? 70 : 76,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOutlined
              ? effectiveOutline
              : Colors.white.withValues(alpha: 0.22),
          width: isOutlined ? 1.6 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isOutlined
                ? effectiveOutline.withValues(alpha: _isDark ? 0.25 : 0.15)
                : solidColor.withValues(alpha: _isDark ? 0.45 : 0.35),
            blurRadius: isOutlined ? 10 : 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.30 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 10,
        vertical: isMobile ? 6 : 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: isMobile ? 10.5 : 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              if (isImage)
                Image.asset('assets/logo/gmwf-1.webp',
                    height: isMobile ? 14 : 17)
              else if (icon != null)
                Icon(icon, size: isMobile ? 14 : 16, color: primaryTextColor),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              if (!isMobile)
                Text(
                  amount,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokenLog(bool isMobile) {
    final rawList = _getFilteredTodayTokens();

    rawList.sort((a, b) {
      final sa = (a['serial'] as String? ?? '000000-000').split('-').last;
      final sb = (b['serial'] as String? ?? '000000-000').split('-').last;
      final na = int.tryParse(sa) ?? 0;
      final nb = int.tryParse(sb) ?? 0;
      return _sortNewestFirst ? nb.compareTo(na) : na.compareTo(nb);
    });

    if (rawList.isEmpty) {
      return Center(
        child: Text(
          'No tokens issued today',
          style: TextStyle(
              fontSize: 14,
              color: _isDark ? const Color(0xFF94A3B8) : Colors.grey),
        ),
      );
    }

    return ListView.separated(
      itemCount: rawList.length,
      separatorBuilder: (_, _) => Divider(
          height: 1,
          color: _isDark ? const Color(0xFF334155) : Colors.grey.shade200),
      itemBuilder: (context, i) {
        final e = rawList[i];
        final serial = e['serial'] as String? ?? 'N/A';
        final rawName = (e['patientName'] ?? e['name'] ?? e['fullName'])?.toString().trim();
        final name = (rawName != null && rawName.isNotEmpty && rawName.toLowerCase() != 'null')
            ? rawName
            : 'Unknown Patient';
        final cnic = (e['cnic'] as String?)?.trim() ?? '';
        final guardianCnic = (e['guardianCnic'] as String?)?.trim() ?? '';
        final queueTypeRaw =
            (e['queueType'] as String?)?.toLowerCase().trim() ?? 'unknown';
        final timestamp = DateTime.tryParse(e['createdAt'] as String? ?? '') ??
            DateTime.now();
        final days = _getDaysOfMedicine(e);
        int tokenAmount = 0;
        if (queueTypeRaw == 'zakat') tokenAmount = 20 * days;
        if (queueTypeRaw == 'non-zakat') tokenAmount = 100 * days;
        final hasExtraDays = days > 1 && tokenAmount > 0;

        // Category label & color
        Color badgeColor;
        String displayType;
        if (_isKarachi) {
          if (queueTypeRaw == 'zakat') {
            badgeColor = Colors.green.shade600;
            displayType = 'PKR 20';
          } else if (queueTypeRaw == 'non-zakat') {
            badgeColor = Colors.blue.shade600;
            displayType = 'PKR 100';
          } else if (queueTypeRaw == 'gmwf') {
            badgeColor = Colors.orange.shade600;
            displayType = 'GMWF';
          } else {
            badgeColor = Colors.green.shade600;
            displayType = 'PKR 20';
          }
        } else {
          switch (queueTypeRaw) {
            case 'zakat':
              badgeColor = Colors.green.shade600;
              displayType = 'Zakat';
              break;
            case 'non-zakat':
              badgeColor = Colors.blue.shade600;
              displayType = 'Non-Zakat';
              break;
            case 'gmwf':
              badgeColor = Colors.orange.shade600;
              displayType = 'GMWF';
              break;
            default:
              badgeColor = Colors.grey.shade600;
              displayType = 'Zakat';
          }
        }

        // Status determination
        final s = (e['status'] as String?)?.toLowerCase().trim() ?? 'waiting';
        final hasPrescription = (e['prescriptionId'] as String?)?.isNotEmpty == true || e['prescription'] is Map;
        final isDispensed = s == 'dispensed' || e['dispensedAt'] != null || (e['dispenseStatus'] as String?)?.toLowerCase().trim() == 'dispensed';
        final isWaitingToDispense = !isDispensed && (hasPrescription || s == 'completed' || s == 'prescribed' || s == 'waiting_to_dispense' || s == 'waiting_for_dispense');

        // Only tokens strictly waiting for doctor (not yet prescribed or dispensed) can be reversed/undone!
        final isWaitingOnly = !isDispensed && !isWaitingToDispense && s != 'with_doctor' && s != 'with doctor' && s != 'in_consultation' && s != 'cancelled' && s != 'reversed' && s != 'deleted';
        final canReverse = isWaitingOnly;

        String statusLabel;
        Color statusBg;
        Color statusText;
        IconData statusIcon;

        if (isDispensed) {
          statusLabel = 'Dispensed';
          statusBg = _isDark ? const Color(0xFF14532D) : Colors.green.shade50;
          statusText = _isDark ? const Color(0xFF86EFAC) : Colors.green.shade800;
          statusIcon = Icons.check_circle_outline_rounded;
        } else if (isWaitingToDispense) {
          statusLabel = 'Waiting for Dispense';
          statusBg = _isDark ? const Color(0xFF1E3A5F) : Colors.blue.shade50;
          statusText = _isDark ? const Color(0xFF93C5FD) : Colors.blue.shade800;
          statusIcon = Icons.medication_outlined;
        } else if (s == 'with_doctor' || s == 'with doctor' || s == 'in_consultation') {
          statusLabel = 'With Doctor';
          statusBg = _isDark ? const Color(0xFF3B1D5F) : Colors.purple.shade50;
          statusText = _isDark ? const Color(0xFFD8B4FE) : Colors.purple.shade800;
          statusIcon = Icons.medical_services_outlined;
        } else if (s == 'cancelled' || s == 'reversed') {
          statusLabel = 'Cancelled';
          statusBg = _isDark ? const Color(0xFF450A0A) : Colors.red.shade50;
          statusText = _isDark ? const Color(0xFFFCA5A5) : Colors.red.shade800;
          statusIcon = Icons.cancel_outlined;
        } else {
          statusLabel = 'Waiting';
          statusBg = _isDark ? const Color(0xFF451A03) : Colors.amber.shade50;
          statusText = _isDark ? const Color(0xFFFCD34D) : Colors.amber.shade900;
          statusIcon = Icons.hourglass_empty_rounded;
        }

        final displayCnic = cnic.isNotEmpty
            ? cnic
            : guardianCnic.isNotEmpty
                ? guardianCnic
                : '-';

        final seqNumber = serial.split('-').last.padLeft(3, '0');

        String campTag = (e['dispensaryTag'] ?? e['dispensaryId'] ?? '').toString().trim().toUpperCase();
        if (campTag.isEmpty || campTag == 'ALL') {
          final parts = serial.split('-');
          if (parts.length >= 3) {
            campTag = parts[1].toUpperCase();
          }
        }
        if (campTag == 'KAP' || campTag == 'KAPAYYA' || campTag == 'SADDAR' || campTag == 'SAD') {
          campTag = 'SADD';
        } else if (campTag == 'HC' || campTag == 'HAJI_CAMP' || campTag == 'HAJICAMP') {
          campTag = 'HAJI';
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 8 : 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isDark
                ? const Color(0xFF1E293B)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _isDark
                    ? const Color(0xFF334155)
                    : Colors.grey.shade200),
          ),
          child: Row(
            children: [
              // ── Token Number Pill ──────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#$seqNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // ── Patient Info ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 13 : 14,
                              color: _isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (days > 1) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange,
                              borderRadius:
                                  BorderRadius.circular(6),
                            ),
                            child: Text(
                              '×$days d',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment:
                          WrapCrossAlignment.center,
                      children: [
                        Tooltip(
                          message: 'Click to copy CNIC',
                          child: InkWell(
                            onTap: (displayCnic.isEmpty || displayCnic == '-')
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: displayCnic));
                                    ScaffoldMessenger.of(context).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.check_circle,
                                                color: Colors.white, size: 16),
                                            const SizedBox(width: 8),
                                            Text('Copied: $displayCnic',
                                                style: const TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: _teal,
                                        width: 250,
                                      ),
                                    );
                                  },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3, vertical: 1),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayCnic,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _isDark
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFF00796B),
                                      decoration: (displayCnic.isNotEmpty && displayCnic != '-')
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                      decorationStyle: TextDecorationStyle.dotted,
                                    ),
                                  ),
                                  if (displayCnic.isNotEmpty && displayCnic != '-') ...[
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.copy,
                                      size: 10,
                                      color: _isDark
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFF00796B),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        Text('•',
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade400)),
                        Text(
                          DateFormat('hh:mm a').format(timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: _isDark
                                ? const Color(0xFF94A3B8)
                                : Colors.grey.shade600,
                          ),
                        ),
                        if (_selectedSessionFilter == 'all' && (e['session'] as String?)?.isNotEmpty == true) ...[
                          Text('•',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade400)),
                          Text(
                            e['session'].toString(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: e['session'].toString().toLowerCase().contains('morn')
                                  ? Colors.amber.shade700
                                  : Colors.indigo.shade400,
                            ),
                          ),
                        ],
                        if (_selectedCampFilter == 'all' && _hasMultiCamps && campTag.isNotEmpty) ...[
                          Text('•',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade400)),
                          Text(
                            campTag,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal.shade600,
                            ),
                          ),
                        ],
                        if (hasExtraDays) ...[
                          Text('•',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade400)),
                          Text(
                            'PKR $tokenAmount',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // ── Fee Badge ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  displayType,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // ── Status Chip ───────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: statusText.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 11, color: statusText),
                    const SizedBox(width: 3),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusText,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Undo / Reversal ───────────────────────────────
              if (canReverse) ...[
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.undo,
                      color: Colors.redAccent, size: 16),
                  tooltip: 'Cancel / Reverse Token',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 26, minHeight: 26),
                  onPressed: () => _requestTokenReverse(e),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('app_settings').listenable(keys: ['is_dark_mode']),
      builder: (context, box, _) {
        final isDark = box.get('is_dark_mode', defaultValue: false) == true;

        final body = Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F8F5),
          ),
          child: isMobile ? _buildMobileBody() : _buildDesktopBody(),
        );

        if (widget.isEmbedded) return body;

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F8F5),
          appBar: _buildAppBar(isMobile),
          body: body,
        );
      },
    );
  }

  Widget _buildMobileBody() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: ValueListenableBuilder<Box>(
          valueListenable: _entriesListenable,
          builder: (context, _, _) => _buildSummaryCards(true),
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _mobileTabController,
          children: [
            // Tab 0: Token
            Padding(
              padding: const EdgeInsets.all(8),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TokenScreen(
                    key: _tokenKey,
                    branchId: widget.branchId,
                    receptionistId: widget.receptionistId,
                    receptionistName: widget.receptionistName,
                    initialCnic: _pendingCnic,
                    onPatientNotFound: _handlePatientNotFound,
                  ),
                ),
              ),
            ),
            // Tab 1: Log
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                Row(children: [
                  Text("Today's Tokens",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _teal)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                        _sortNewestFirst
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: _teal,
                        size: 20),
                    onPressed: () =>
                        setState(() => _sortNewestFirst = !_sortNewestFirst),
                  ),
                  // Refresh Button
                  IconButton(
                    icon: const Icon(Icons.refresh, color: _teal, size: 20),
                    onPressed: _refreshTokenLog,
                    tooltip: 'Refresh token list',
                  ),
                ]),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${_getFilteredTodayTokens().length} total',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _refreshNotifier,
                    builder: (context, _, _) => ValueListenableBuilder<Box>(
                      valueListenable: _entriesListenable,
                      builder: (context, _, _) => _buildTokenLog(true),
                    ),
                  ),
                ),
              ]),
            ),
            // Tab 2: Register
            Padding(
              padding: const EdgeInsets.all(8),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: PatientRegisterPage(
                    key: _registerKey,
                    branchId: widget.branchId,
                    receptionistId: widget.receptionistId,
                    initialCnic: _pendingCnic,
                    onPatientRegistered: _onPatientRegistered,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildDesktopBody() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1650),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left Column (flex: 3): Action Toggle + Main Form Card ───────
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildDesktopToggle(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        elevation: 10,
                        color: _isDark ? const Color(0xFF1E293B) : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // ── Authentic Islamic Pattern Background (Vibrant Golden) ──
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: _isDark ? 0.18 : 0.28,
                                  child: Image.asset(
                                    'assets/images/islamic_pattern.webp',
                                    fit: BoxFit.cover,
                                    color: _isDark ? const Color(0xFFF6C358) : const Color(0xFFD4AF37),
                                    colorBlendMode: BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),

                            // ── Form Content ──
                            Padding(
                              padding: const EdgeInsets.all(28),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                child: _activeSection == 'register'
                                    ? PatientRegisterPage(
                                        key: _registerKey,
                                        branchId: widget.branchId,
                                        receptionistId: widget.receptionistId,
                                        initialCnic: _pendingCnic,
                                        onPatientRegistered:
                                            _onPatientRegistered,
                                      )
                                    : TokenScreen(
                                        key: _tokenKey,
                                        branchId: widget.branchId,
                                        receptionistId: widget.receptionistId,
                                        receptionistName:
                                            widget.receptionistName,
                                        initialCnic: _pendingCnic,
                                        onPatientNotFound:
                                            _handlePatientNotFound,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),

              // ── Right Column (flex: 2): Summary Cards + Today's Tokens Card ──
              Expanded(
                flex: 2,
                child: ValueListenableBuilder<int>(
                  valueListenable: _refreshNotifier,
                  builder: (context, _, _) => ValueListenableBuilder<Box>(
                    valueListenable: _entriesListenable,
                    builder: (context, _, _) => Column(
                      children: [
                        _buildSummaryCards(false),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ValueListenableBuilder<Box>(
                            valueListenable: _patientsListenable,
                            builder: (context, box, _) {
                              final todayCount = _getFilteredTodayTokens().length;
                              return Card(
                                elevation: 8,
                                color: _isDark ? const Color(0xFF1E293B) : Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(24)),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  children: [
                                    // ── Vibrant Golden Islamic Watermark (Center Touching Right Edge + Rotated) ──
                                    Positioned(
                                      right: -135,
                                      bottom: -50,
                                      width: 320,
                                      height: 320,
                                      child: IgnorePointer(
                                        child: Transform.rotate(
                                          angle: -0.16, // ~9.2 degrees graceful tilt
                                          child: Opacity(
                                            opacity: _isDark ? 0.22 : 0.32,
                                            child: Image.asset(
                                              'assets/images/1.webp',
                                              fit: BoxFit.contain,
                                              color: _isDark ? const Color(0xFFF6C358) : const Color(0xFFD4AF37),
                                              colorBlendMode: BlendMode.srcIn,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // ── Today's Tokens Content ──
                                    Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Icon(Icons.list_alt_rounded,
                                                color: _isDark ? const Color(0xFF38BDF8) : _teal, size: 26),
                                            const SizedBox(width: 10),
                                            Text("Today's Tokens",
                                                style: TextStyle(
                                                    fontSize: 19,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: _isDark ? Colors.white : _teal)),
                                            const Spacer(),
                                            IconButton(
                                              icon: Icon(
                                                  _sortNewestFirst
                                                      ? Icons
                                                          .arrow_downward_rounded
                                                      : Icons
                                                          .arrow_upward_rounded,
                                                  color: _isDark ? const Color(0xFF38BDF8) : _teal,
                                                  size: 20),
                                              onPressed: () => setState(() =>
                                                  _sortNewestFirst =
                                                      !_sortNewestFirst),
                                              tooltip: _sortNewestFirst
                                                  ? 'Sort: Oldest First'
                                                  : 'Sort: Newest First',
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.refresh_rounded,
                                                  color: _isDark ? const Color(0xFF38BDF8) : _teal, size: 22),
                                              onPressed: _refreshTokenLog,
                                              tooltip: 'Refresh token list',
                                            ),
                                          ]),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Text('$todayCount total',
                                                  style: TextStyle(
                                                      color: _isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                          const Divider(height: 20),
                                          Expanded(child: _buildTokenLog(false)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopToggle() {
    final isToken = _activeSection == 'token';
    return Container(
      width: double.infinity,
      height: 54,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.20 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          // ── Register Patient ──────────────────────────────────────────
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _activeSection = 'register'),
                borderRadius: BorderRadius.circular(28),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: !isToken
                        ? const LinearGradient(
                            colors: [Color(0xFF00A86B), Color(0xFF00875A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: !isToken
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00A86B).withValues(alpha: _isDark ? 0.45 : 0.35),
                              blurRadius: 14,
                              spreadRadius: 1,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 19,
                        color: !isToken
                            ? Colors.white
                            : (_isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Register Patient',
                        style: TextStyle(
                          fontWeight: !isToken ? FontWeight.bold : FontWeight.w600,
                          fontSize: 14.5,
                          color: !isToken
                              ? Colors.white
                              : (_isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // ── Issue Token ───────────────────────────────────────────────
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _activeSection = 'token'),
                borderRadius: BorderRadius.circular(28),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isToken
                        ? const LinearGradient(
                            colors: [Color(0xFF00A86B), Color(0xFF00875A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: isToken
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00A86B).withValues(alpha: _isDark ? 0.45 : 0.35),
                              blurRadius: 14,
                              spreadRadius: 1,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_rounded,
                        size: 19,
                        color: isToken
                            ? Colors.white
                            : (_isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Issue Token',
                        style: TextStyle(
                          fontWeight: isToken ? FontWeight.bold : FontWeight.w600,
                          fontSize: 14.5,
                          color: isToken
                              ? Colors.white
                              : (_isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    CampSessionService.activeCampNotifier.removeListener(_onActiveCampChanged);
    _refreshNotifier.dispose();
    _mobileTabController.dispose();
    if (!widget.isEmbedded) {
      ConnectionManager().stop();
    }
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }
}