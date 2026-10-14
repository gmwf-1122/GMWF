// lib/pages/dispensary/hybrid_dispensary_screen.dart

import 'dart:async';
import '../../widgets/lazy_indexed_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/design/components/flushbar_compat.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/services/auth_service.dart';
import 'package:gmwf/realtime/connection_manager.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/widgets/gmwf_app_bar.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/widgets/camp_selector_chip.dart';
import 'user_settings_dialog.dart';
import 'widgets/connection_status_same.dart';

import 'package:gmwf/models/patient.dart';
import 'package:gmwf/services/firestore_service.dart';
import 'package:gmwf/design/design_system.dart';

import 'receptionist/receptionist_screen.dart';
import 'dispensar/dispensar_screen.dart';
import 'dispensar/inventory.dart';
import 'hybrid_all_in_one_screen.dart';
import '../../services/dispensary_preferences_service.dart';
import 'doctor/doctor_screen.dart';
import 'package:gmwf/constants/navigator_key.dart';
import 'package:gmwf/utils/formatters.dart';

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
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _controllerInitialized = false;
  int _activeTabIndex = 0;
  bool _isLoggingOut = false;
  ValueListenable<Box>? _hybridBoxListenable;
  VoidCallback? _hybridBoxListener;
  final List<Map<String, dynamic>> _tabs = [];

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<ConnectionStatus>? _connectionSub;

  bool _online = true;
  bool _isSyncing = false;
  String? _branchName;
  String? _resolvedName;

  ConnectionStatus _connectionStatus = ConnectionManager().status;

  static const Color _teal = SoftPalette.teal600;

  StreamSubscription? _restockRealtimeSub;
  StreamSubscription? _restockFirestoreSub;
  List<Map<String, dynamic>> _pendingRestockAlerts = [];

  // Dispenser tab badge: today's prescribed patients not yet dispensed.
  int _readyToDispenseCount = 0;

  // Theme-toggle refresh of the kept-alive tab screens (see _rebuildTabsForTheme).
  final GlobalKey _tabBodyKey = GlobalKey();
  bool? _lastIsDark;
  StreamSubscription? _readyCountSub;
  Timer? _readyCountDebounce;

  bool get _isStockTabActive {
    final i = _activeTabIndex;
    if (i < 0 || i >= _tabs.length) return false;
    final title = (_tabs[i]['title'] as String).toLowerCase();
    return title.contains('stock') || title.contains('inventory');
  }

  /// The tab that dispenses: "Dispenser", or "Pharmacy" in the all-in-one layout.
  static bool _isDispenseTab(String title) {
    final t = title.toLowerCase();
    return t.contains('dispens') || t.contains('pharmacy');
  }

  void _startReadyToDispenseCounter() {
    final hasDispenserTab = _tabs.any((t) => _isDispenseTab(t['title'] as String));
    if (!hasDispenserTab) return;
    CampSessionService.activeCampNotifier.addListener(_scheduleReadyCount);
    // The entries box is opened asynchronously on desk entry — wait for it instead of giving up.
    LocalStorageService.ensureBoxOpen(LocalStorageService.entriesBox).then((box) {
      if (!mounted) return;
      _recomputeReadyToDispense();
      _readyCountSub?.cancel();
      // Debounced: a catch-up writes many entries in a burst; count once after it settles.
      _readyCountSub = box.watch().listen((_) => _scheduleReadyCount());
    }).catchError((e) {
      debugPrint('[HybridScreen] Ready-to-dispense counter could not start: $e');
    });
  }

  void _scheduleReadyCount() {
    _readyCountDebounce?.cancel();
    _readyCountDebounce = Timer(const Duration(milliseconds: 800), _recomputeReadyToDispense);
  }

  void _recomputeReadyToDispense() {
    if (_isLoggingOut || !mounted || !Hive.isBoxOpen(LocalStorageService.entriesBox)) return;
    final today = CampSessionService.resolveShiftAndDateKey(null, widget.branchId).dateKey;
    final camp = CampSessionService.getActiveCamp(widget.branchId);
    final byCamp = camp != null && camp.isNotEmpty && camp != 'all';
    final seen = <String>{};
    var count = 0;
    for (final e in LocalStorageService.getLocalEntries(widget.branchId, dispensaryId: camp, filterByCamp: byCamp)) {
      final serial = (e['serial'] ?? e['id'] ?? '').toString().trim().toUpperCase();
      if (serial.isEmpty || !seen.add(serial)) continue;
      final dk = (e['dateKey'] ?? '').toString().trim();
      if (dk != today && CampSessionService.getDateKeyFromSerial(serial) != today) continue;
      // Same rule as the Receptionist list's "Waiting for Dispense" label.
      final s = (e['status'] ?? 'waiting').toString().toLowerCase().trim();
      if (s == 'cancelled' || s == 'rejected' || s == 'reversed' || s == 'deleted' || s == 'skipped') continue;
      final isDispensed = s == 'dispensed' || e['dispensedAt'] != null ||
          (e['dispenseStatus'] ?? '').toString().toLowerCase().trim() == 'dispensed';
      if (isDispensed) continue;
      final hasPrescription = (e['prescriptionId']?.toString().isNotEmpty ?? false) || e['prescription'] is Map;
      if (hasPrescription || s == 'completed' || s == 'prescribed' ||
          s == 'waiting_to_dispense' || s == 'waiting_for_dispense') {
        count++;
      }
    }
    if (count != _readyToDispenseCount && mounted && !_isLoggingOut) {
      setState(() => _readyToDispenseCount = count);
    }
  }

  bool get _shouldShowRestockAlert {
    final r = widget.role.toLowerCase().trim();
    final hasDispenser = r.contains('dis') || r.contains('dispenser') || r.contains('dispensar');
    final hasDoctor = r.contains('doc') || r.contains('doctor');
    return hasDispenser && !hasDoctor;
  }

  static String? _lastActiveTabTitle;
  static int? _lastActiveTabIndex;

  void _saveCurrentActiveTab(int idx) {
    if (idx >= 0 && idx < _tabs.length) {
      _lastActiveTabIndex = idx;
      final title = _tabs[idx]['title'] as String?;
      if (title != null && title.isNotEmpty) {
        _lastActiveTabTitle = title;
        try {
          if (Hive.isBoxOpen('app_settings')) {
            Hive.box('app_settings').put('last_hybrid_tab_title', title);
          }
        } catch (_) {}
      }
    }
  }

  int _resolveInitialTabIndex() {
    if (_tabs.isEmpty) return 0;
    // 1. Try in-memory static last active index
    if (_lastActiveTabIndex != null && _lastActiveTabIndex! >= 0 && _lastActiveTabIndex! < _tabs.length) {
      return _lastActiveTabIndex!;
    }
    // 2. Try in-memory static last active title
    if (_lastActiveTabTitle != null) {
      final idx = _tabs.indexWhere((t) => t['title'] == _lastActiveTabTitle);
      if (idx >= 0) return idx;
    }
    // 3. Try Hive app_settings
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final saved = Hive.box('app_settings').get('last_hybrid_tab_title')?.toString();
        if (saved != null && saved.isNotEmpty) {
          final idx = _tabs.indexWhere((t) => t['title'] == saved);
          if (idx >= 0) return idx;
        }
      }
    } catch (_) {}
    // 4. Fallback based on role: if role has dispenser or stock, do NOT default to Receptionist
    final r = widget.role.toLowerCase().trim();
    if (r.contains('dis') || r.contains('dispenser') || r.contains('dispensar')) {
      final disIdx = _tabs.indexWhere((t) =>
          _isDispenseTab(t['title'] as String) ||
          (t['title'] as String).toLowerCase().contains('stock') ||
          (t['title'] as String).toLowerCase().contains('inventory'));
      if (disIdx >= 0) return disIdx;
    }
    return 0;
  }

  void _onTabControllerChanged() {
    if (_tabController.index < _tabs.length) {
      _saveCurrentActiveTab(_tabController.index);
    }
    if (_activeTabIndex != _tabController.index && !_tabController.indexIsChanging) {
      if (mounted && !_isLoggingOut) {
        setState(() {
          _activeTabIndex = _tabController.index;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint("[Lifecycle] HybridDispensaryScreen initState");

    _parseRole();
    _syncTabController();

    if (_shouldShowRestockAlert) {
      _listenRestockRequests();
    }
    _startReadyToDispenseCounter();

    // Start services once
    SyncService().start(widget.branchId);
    _listenConnectivity();
    _loadBranchName();

    _fetchUserNameAndConnect();

    _connectionStatus = ConnectionManager().status;
    _connectionSub = ConnectionManager().statusStream.listen((status) {
      // Only rebuild when the status really changed (the stream re-emits the same state).
      if (mounted && !status.sameAs(_connectionStatus)) setState(() => _connectionStatus = status);
    });

    // Ensure all role boxes (patients, entries, stock, prescriptions) are opened on desk entry
    LocalStorageService.initForRoles([widget.role, 'receptionist', 'dispenser']);

    // Ensure active camp is resolved — getActiveCamp() now handles time-based detection automatically
    if (CampSessionService.hasCampsForBranch(widget.branchId)) {
      CampSessionService.getActiveCamp(widget.branchId);
      CampSessionService.startAutoCampTimer();
    }

    CampSessionService.activeCampNotifier.addListener(_onCampChanged);

    // Run receptionist bootstrap if "rec" is included in role
    if (widget.role.toLowerCase().contains('rec')) {
      _bootstrapReceptionistData(widget.branchId);
    }

    if (Hive.isBoxOpen('app_settings')) {
      final hybridKey = DispensaryPreferencesService.getHybridAllInOneKey(widget.userId);
      _hybridBoxListenable = Hive.box('app_settings').listenable(keys: [hybridKey]);
      _hybridBoxListener = () {
        if (mounted && !_isLoggingOut) {
          setState(() {
            _parseRole();
          });
        }
      };
      _hybridBoxListenable?.addListener(_hybridBoxListener!);
    }
  }

  void _onCampChanged() {
    if (mounted && !_isLoggingOut) setState(() {});
  }

  void _parseRole([String? effectiveName]) {
    final name = effectiveName ?? _resolvedName ?? widget.userName;
    _tabs.clear();
    final r = widget.role.toLowerCase().trim();
    final hasReception = r.contains('rec') || r.contains('receptionist');
    final hasDispense = r.contains('dis') || r.contains('dispenser') || r.contains('dispensar');
    // Reception + dispense desks can switch between the all-in-one Pharmacy layout
    // and the separate Receptionist / Dispenser tabs via the 3-dot menu.
    // Default is always false (the normal separate tabs), per-account isolated.
    final bool allInOneEnabled = DispensaryPreferencesService.isHybridAllInOne(widget.userId);
    final useAllInOne = hasReception && hasDispense && allInOneEnabled;
    if (r.contains('doc') || r.contains('doctor')) {
      _tabs.add({
        'title': 'Doctor',
        'icon': Icons.medical_services_outlined,
        'widget': DoctorScreen(
          branchId: widget.branchId,
          doctorId: widget.userId,
          doctorName: name,
          isEmbedded: true,
        ),
      });
    }
    if (useAllInOne) {
      _tabs.add({
        'title': 'Pharmacy',
        'icon': Icons.local_pharmacy_outlined,
        'widget': HybridAllInOneScreen(
          branchId: widget.branchId,
          userId: widget.userId,
          userName: name,
        ),
      });
    }
    if (!useAllInOne && hasReception) {
      // Doctor desks write the prescriptions; dispenser desks get the Dispenser tab badge.
      // Either way a popup per prescription on the Receptionist tab is noise.
      final suppressPrescriptionNotifications = r.contains('doc') || r.contains('doctor') ||
          r.contains('dis') || r.contains('dispenser') || r.contains('dispensar');
      _tabs.add({
        'title': 'Receptionist',
        'icon': Icons.support_agent_rounded,
        'widget': ReceptionistScreen(
          branchId: widget.branchId,
          receptionistId: widget.userId,
          receptionistName: name,
          isEmbedded: true,
          suppressPrescriptionNotifications: suppressPrescriptionNotifications,
        ),
      });
    }
    if (!useAllInOne && hasDispense) {
      _tabs.add({
        'title': 'Dispenser',
        'icon': Icons.medication_outlined,
        'widget': DispensarScreen(
          branchId: widget.branchId,
          dispenserId: widget.userId,
          dispenserName: name,
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
    if (_tabs.isEmpty) {
      _tabs.add({
        'title': 'Desk',
        'icon': Icons.support_agent_rounded,
        'widget': ReceptionistScreen(
          branchId: widget.branchId,
          receptionistId: widget.userId,
          receptionistName: name,
          isEmbedded: true,
        ),
      });
    }

    _syncTabController();
  }

  void _syncTabController() {
    if (_isLoggingOut || _tabs.isEmpty) return;
    final targetLength = _tabs.length;
    final bool needsNew = !_controllerInitialized || _tabController.length != targetLength;
    if (needsNew) {
      final old = _controllerInitialized ? _tabController : null;
      if (old != null) {
        old.removeListener(_onTabControllerChanged);
      }
      final targetIndex = (_controllerInitialized && _tabController.index < targetLength)
          ? _tabController.index
          : _resolveInitialTabIndex().clamp(0, targetLength - 1);

      _tabController = TabController(
        length: targetLength,
        initialIndex: targetIndex.clamp(0, targetLength - 1),
        vsync: this,
      );
      _controllerInitialized = true;
      _activeTabIndex = _tabController.index;
      _tabController.addListener(_onTabControllerChanged);

      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            old.dispose();
          } catch (_) {}
        });
      }
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
      if (local != null) {
        final n = resolveUserDisplayName(local);
        if (n.isNotEmpty && n != 'User' && n != 'Doctor') name = n;
      }
    } catch (_) {}

    // 2. Check app_settings cache
    if (name == null || name == 'User' || name == 'Doctor') {
      try {
        if (Hive.isBoxOpen('app_settings')) {
          final box = Hive.box('app_settings');
          final uData = box.get('user_data') ?? box.get('currentUser');
          if (uData is Map) {
            final n = resolveUserDisplayName(Map<String, dynamic>.from(uData));
            if (n.isNotEmpty && n != 'User' && n != 'Doctor') name = n;
          }
        }
      } catch (_) {}
    }

    // 3. Fall back to widget param
    if (name == null || name == 'User' || name == 'Doctor') {
      if (widget.userName.trim().isNotEmpty && widget.userName.trim().toLowerCase() != 'user') {
        name = widget.userName.trim();
      }
    }

    if (mounted && name != null && name.isNotEmpty) {
      setState(() {
        _resolvedName = name;
        _parseRole(name);
      });
    }

    // Start connection
    ConnectionManager().start(
      role: widget.role,
      branchId: widget.branchId,
      username: name,
    );
    if (name != null) {
      RealtimeManager().updateUsername(name);
    }

    // 4. Fetch from Firestore for authoritative user profile and cache it
    try {
      final userData = await AuthService().getUserByUid(widget.userId);
      if (userData != null && Hive.isBoxOpen('app_settings')) {
        await Hive.box('app_settings').put('user_data', userData);
        await Hive.box('app_settings').put('currentUser', userData);
      }
      final firestoreName = resolveUserDisplayName(userData);
      if (mounted && firestoreName.isNotEmpty && firestoreName != 'User' && firestoreName != 'Doctor') {
        setState(() {
          _resolvedName = firestoreName;
          _parseRole(firestoreName);
        });
        RealtimeManager().updateUsername(firestoreName);
      }
    } catch (e) {
      debugPrint('[HybridScreen] Could not fetch name from Firestore: $e');
    }
  }

  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) setState(() => _branchName = 'Free Dispensary');
      return;
    }
    final localName = LocalStorageService.getBranchName(widget.branchId);
    if (localName.isNotEmpty && localName != 'Free Dispensary') {
      if (mounted) setState(() => _branchName = localName);
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .get();
      if (mounted && doc.exists) {
        final n = doc.data()?['name']?.toString();
        if (n != null && n.isNotEmpty) {
          setState(() => _branchName = n);
        }
      }
    } catch (_) {}
  }

  Future<void> _forceSync() async {
    if (_isSyncing || !mounted) return;
    setState(() => _isSyncing = true);
    try {
      // 1. Force-flush LAN WebSocket outbox & request catch-up from LAN server
      await RealtimeManager().forceFlushAndCatchUp();

      // 2. If online, sync with cloud
      if (_online) {
        await SyncService().syncTodayOnly(widget.branchId);
        await SyncService().triggerUpload();
      }
      if (mounted) {
        Flushbar(
          message: _online ? 'Full sync completed (LAN & Cloud)' : 'LAN Sync completed (Outbox flushed)',
          backgroundColor: SoftPalette.green500,
          duration: const Duration(seconds: 2),
        ).show(context);
      }
    } catch (e) {
      if (mounted) {
        Flushbar(
          message: 'Sync failed: $e',
          backgroundColor: SoftPalette.red500,
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
      await LocalStorageService.ensureBoxOpen(LocalStorageService.patientsBox);
      await LocalStorageService.ensureBoxOpen(LocalStorageService.entriesBox);
      // Only do a bulk patient download if local storage is fresh/empty (< 5 patients)
      final localCount = LocalStorageService.getAllLocalPatients(branchId: branchId).length;
      if (localCount < 5) {
        final List<Patient> patients =
            await firestoreService.getAllPatientsForBranch(branchId);
        final patientsList = patients.map((p) => p.toMap()).toList();
        await LocalStorageService.saveAllLocalPatients(patientsList);
      }

      await LocalStorageService.downloadTodayTokens(branchId);
    } catch (e) {
      debugPrint("Warning: Error bootstrapping receptionist data: $e");
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final confirm = await showLogoutDialog(context);

    if (confirm == true && mounted) {
      setState(() => _isLoggingOut = true);
      try { _connectionSub?.cancel(); _connSub?.cancel(); } catch (_) {}
      try { _restockRealtimeSub?.cancel(); _restockFirestoreSub?.cancel(); } catch (_) {}
      try { _readyCountSub?.cancel(); _readyCountDebounce?.cancel(); } catch (_) {}
      try { ConnectionManager().stop().catchError((_) {}); } catch (_) {}
      try {
        await AuthService().signOut().timeout(const Duration(seconds: 4));
      } catch (_) {}

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (r) => false);
      } else if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushNamedAndRemoveUntil('/login', (r) => false);
      }
    }
  }

  @override
  void dispose() {
    _isLoggingOut = true;
    CampSessionService.activeCampNotifier.removeListener(_onCampChanged);
    CampSessionService.stopAutoCampTimer();
    if (_hybridBoxListenable != null && _hybridBoxListener != null) {
      _hybridBoxListenable!.removeListener(_hybridBoxListener!);
    }
    _restockRealtimeSub?.cancel();
    _restockFirestoreSub?.cancel();
    _readyCountSub?.cancel();
    _readyCountDebounce?.cancel();
    CampSessionService.activeCampNotifier.removeListener(_scheduleReadyCount);
    _connSub?.cancel();
    _connectionSub?.cancel();
    if (_controllerInitialized) {
      _tabController.removeListener(_onTabControllerChanged);
      _tabController.dispose();
    }
    ConnectionManager().stop();
    debugPrint("[Lifecycle] HybridDispensaryScreen dispose");
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = GBreakpoint.isMobile(context);

    if (!Hive.isBoxOpen('app_settings')) {
      return FutureBuilder<Box>(
        future: LocalStorageService.ensureBoxOpen('app_settings'),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null || !snapshot.data!.isOpen) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: _teal)),
            );
          }
          final isDark = snapshot.data!.get('is_dark_mode', defaultValue: false) == true;
          return _buildThemedScaffold(context, isDark, isMobile);
        },
      );
    }

    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('app_settings').listenable(keys: ['is_dark_mode']),
      builder: (context, box, _) {
        final isDark = box.isOpen ? (box.get('is_dark_mode', defaultValue: false) == true) : false;
        return _buildThemedScaffold(context, isDark, isMobile);
      },
    );
  }

  /// The embedded tab screens are kept-alive widget instances, so a theme toggle does not
  /// rebuild them; parts that read `is_dark_mode` from Hive kept the old theme while
  /// Theme-driven parts switched (light text on light / dark on dark). Rebuild them once.
  void _rebuildTabsForTheme() {
    if (!mounted) return;
    final root = _tabBodyKey.currentContext;
    if (root is! Element) return;
    void mark(Element el) {
      el.markNeedsBuild();
      el.visitChildren(mark);
    }
    root.visitChildren(mark);
  }

  Widget _buildThemedScaffold(BuildContext context, bool isDark, bool isMobile) {
    if (!_isLoggingOut) {
      _syncTabController();
    }
    if (_lastIsDark != null && _lastIsDark != isDark) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildTabsForTheme());
    }
    _lastIsDark = isDark;

    final isAllInOne = DispensaryPreferencesService.isHybridAllInOne(widget.userId);
    final isRecDis = widget.role.toLowerCase().contains('rec') && widget.role.toLowerCase().contains('dis');

    return Scaffold(
      backgroundColor: isDark ? SoftPalette.slate900 : SoftPalette.emerald100t,
      appBar: GmwfAppBar(
        isFloating: false,
        title: 'Hybrid Desk – ${_resolvedName ?? widget.userName}',
        subtitle: CampSessionService.getBranchAndCampDisplayName(
          branchName: _branchName ?? LocalStorageService.getBranchName(widget.branchId),
          branchId: widget.branchId,
          campId: CampSessionService.getActiveCamp(widget.branchId),
        ),
        userId: widget.userId,
        showHybridLayoutToggle: isRecDis,
        showTimingFormatToggle: true,
        showPaneOrderToggle: isRecDis && isAllInOne,
        onToggleHybridLayout: () {
          if (mounted) setState(() => _parseRole());
        },
        onToggleTimingFormat: () {
          if (mounted) setState(() {});
        },
        onTogglePaneOrder: () {
          if (mounted) setState(() {});
        },
        extraActions: [
          CampSelectorChip(
            branchId: widget.branchId,
            textColor: isDark ? SoftPalette.sky350 : SoftPalette.emerald600,
            bgColor: isDark ? SoftPalette.slate700 : SoftPalette.green100m,
            borderColor: isDark ? SoftPalette.slate600 : SoftPalette.emerald150,
          ),
        ],
        onTitleLongPress: () => DispensaryUserSettingsDialog.show(
          context,
          branchId: widget.branchId,
          onUserUpdated: () {
            if (mounted) setState(() { _fetchUserNameAndConnect(); });
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
        onInventory: () {
          final stockIdx = _tabs.indexWhere((t) =>
              (t['title'] as String).toLowerCase().contains('stock') ||
              (t['title'] as String).toLowerCase().contains('inventory'));
          if (stockIdx >= 0) {
            _tabController.animateTo(stockIdx);
            if (_activeTabIndex != stockIdx) {
              setState(() => _activeTabIndex = stockIdx);
            }
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InventoryPage(
                  branchId: widget.branchId,
                  isDispenser: widget.role.toLowerCase().contains('dis'),
                ),
              ),
            );
          }
        },
        onUserSettings: () => DispensaryUserSettingsDialog.show(
          context,
          branchId: widget.branchId,
          onUserUpdated: () {
            if (mounted) setState(() { _fetchUserNameAndConnect(); });
          },
        ),
        bottom: (isMobile || _tabs.length <= 1)
            ? null
            : PreferredSize(
                key: ValueKey('hybrid_tabbar_pref_${_tabs.length}_${_tabController.length}_${identityHashCode(_tabController)}'),
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? SoftPalette.slate800 : SoftPalette.gray50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? SoftPalette.slate700 : SoftPalette.slate150,
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SoftPalette.gray900.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: TabBar(
                    key: ValueKey('tabbar_${_tabs.length}_${_tabController.length}_${identityHashCode(_tabController)}'),
                    controller: _tabController,
                    onTap: (idx) {
                      _saveCurrentActiveTab(idx);
                      if (_activeTabIndex != idx) {
                        setState(() => _activeTabIndex = idx);
                      }
                    },
                    isScrollable: false,
                    indicator: BoxDecoration(
                      color: isDark ? SoftPalette.teal550.withValues(alpha: 0.35) : SoftPalette.green100m,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: SoftPalette.emerald350,
                        width: 1.2,
                      ),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    dividerColor: Colors.transparent,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    tabs: _tabs.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final t = entry.value;
                      final isSelected = _activeTabIndex == idx;
                      return Tab(
                        height: 38,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                t['icon'] as IconData,
                                size: 18,
                                color: isSelected
                                    ? (isDark ? SoftPalette.emerald300 : SoftPalette.emerald550)
                                    : (isDark ? SoftPalette.slate350 : SoftPalette.slate550),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                t['title'] as String,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                  color: isSelected
                                      ? (isDark ? SoftPalette.emerald300 : SoftPalette.emerald550)
                                      : (isDark ? SoftPalette.slate350 : SoftPalette.slate550),
                                ),
                              ),
                              // Patients prescribed and waiting to be dispensed.
                              if (_readyToDispenseCount > 0 &&
                                  _isDispenseTab(t['title'] as String)) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: SoftPalette.emerald550,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$_readyToDispenseCount',
                                    style: const TextStyle(
                                      color: SoftPalette.gray50,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              // Restock requests belong to the inventory only.
                              if (_shouldShowRestockAlert &&
                                  _pendingRestockAlerts.isNotEmpty &&
                                  ((t['title'] as String).toLowerCase().contains('stock') ||
                                      (t['title'] as String).toLowerCase().contains('inventory'))) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: SoftPalette.red500,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_pendingRestockAlerts.length}',
                                    style: const TextStyle(
                                      color: SoftPalette.gray50,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          // Restock requests are shown only inside Stock & Inventory.
          if (_isStockTabActive) _buildRestockBanner(isDark),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('tab_body_${_tabs.length}_${_tabController.length}_$isAllInOne'),
              child: LazyIndexedStack(
                index: _tabs.isEmpty ? 0 : _activeTabIndex.clamp(0, _tabs.length - 1),
                children: _tabs.map((t) => t['widget'] as Widget).toList(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: (isMobile && _tabs.length > 1) ? _buildMobileBottomBar(isDark) : null,
    );
  }

  Widget _buildMobileBottomBar(bool isDark) {
    final activeColor = isDark ? SoftPalette.emerald300 : SoftPalette.emerald550;
    final inactiveColor = isDark ? SoftPalette.slate350 : SoftPalette.slate550;
    final activeBg = isDark ? SoftPalette.teal550.withValues(alpha: 0.3) : SoftPalette.green100m;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? SoftPalette.slate800 : SoftPalette.gray50,
        border: Border(
          top: BorderSide(
            color: isDark ? SoftPalette.slate700 : SoftPalette.slate150,
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: SoftPalette.gray900.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: _tabs.asMap().entries.map((entry) {
              final idx = entry.key;
              final t = entry.value;
              final activeIndex = _tabs.isEmpty ? 0 : _activeTabIndex.clamp(0, _tabs.length - 1);
              final isSelected = activeIndex == idx;

              return Expanded(
                child: InkWell(
                  onTap: () {
                    _saveCurrentActiveTab(idx);
                    if (_tabController.index != idx) {
                      _tabController.animateTo(idx);
                    }
                    if (_activeTabIndex != idx) {
                      setState(() => _activeTabIndex = idx);
                    }
                  },
                  splashColor: activeColor.withValues(alpha: 0.12),
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? activeBg : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          t['icon'] as IconData,
                          size: 20,
                          color: isSelected ? activeColor : inactiveColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t['title'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? activeColor : inactiveColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _listenRestockRequests() {
    if (widget.branchId.isEmpty) return;

    // 1. Initial load from local Hive storage (instant, persists across restarts and works offline)
    _pendingRestockAlerts = LocalStorageService.getPendingRestockRequests(widget.branchId);

    // 2. Realtime WebSocket message stream
    _restockRealtimeSub?.cancel();
    _restockRealtimeSub = RealtimeManager().messageStream.listen((event) {
      final type = (event['event_type'] ?? event['type'])?.toString();
      if (type == RealtimeEvents.restockRequest || type == 'restock_request') {
        final rawData = event['data'];
        final data = (rawData is Map) ? Map<String, dynamic>.from(rawData) : Map<String, dynamic>.from(event);
        final medName = (data['medicineName'] ?? data['name'] ?? 'Medicine').toString();
        final currentQty = data['currentQty'] ?? data['quantity'] ?? 'low';
        final doctor = (data['requestedBy'] ?? 'Doctor').toString();
        final notes = (data['notes'] ?? '').toString();
        final reqId = data['id']?.toString() ?? 'restock_${DateTime.now().millisecondsSinceEpoch}';

        final reqData = {
          'id': reqId,
          'medicineName': medName,
          'currentQty': currentQty,
          'requestedBy': doctor,
          'notes': notes,
          'status': 'pending',
          'branchId': widget.branchId,
          'timestamp': DateTime.now().toIso8601String(),
        };

        LocalStorageService.saveRestockRequest(widget.branchId, reqData);

        final exists = _pendingRestockAlerts.any((r) => r['id'] == reqId || (r['medicineName'] == medName && r['status'] == 'pending'));
        if (!exists) {
          _pendingRestockAlerts.insert(0, reqData);
        }

        // No popup: the Stock & Inventory tab badge and the banner inside it show the request.
        if (mounted) setState(() {});
      }
    });

    // 3. Firestore snapshot listener for pending cloud catch-up
    try {
      _restockFirestoreSub?.cancel();
      _restockFirestoreSub = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('restock_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        final alerts = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final d = Map<String, dynamic>.from(doc.data());
          d['id'] = doc.id;
          alerts.add(d);
          LocalStorageService.saveRestockRequest(widget.branchId, d);
        }
        setState(() {
          _pendingRestockAlerts = alerts;
        });
      }, onError: (e) {
        debugPrint('[HybridScreen] Restock requests stream error: $e');
      });
    } catch (_) {}
  }

  Future<void> _dismissRestockAlert(String reqId) async {
    setState(() {
      _pendingRestockAlerts.removeWhere((r) => r['id'] == reqId);
    });
    await LocalStorageService.updateRestockRequestStatus(widget.branchId, reqId, 'acknowledged');
    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('restock_requests')
          .doc(reqId)
          .update({'status': 'acknowledged', 'acknowledgedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  Widget _buildRestockBanner(bool isDark) {
    if (!_shouldShowRestockAlert || _pendingRestockAlerts.isEmpty) return const SizedBox.shrink();

    final first = _pendingRestockAlerts.first;
    final count = _pendingRestockAlerts.length;
    final medName = first['medicineName'] ?? first['name'] ?? 'Medicine';
    final doctor = first['requestedBy'] ?? 'Doctor';
    final currentQty = first['currentQty'] ?? first['quantity'] ?? '0';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? SoftPalette.orange800 : SoftPalette.yellow50m,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftPalette.amber300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: SoftPalette.gray900.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: SoftPalette.orange400, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count > 1
                      ? '⚠️ Restock Requests ($count pending): $medName and ${count - 1} more'
                      : '⚠️ Restock Alert: $medName (Current: $currentQty)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? SoftPalette.yellow150 : SoftPalette.orange600,
                  ),
                ),
                Text(
                  '$doctor requested restock from dispensary. Please restock soon.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? SoftPalette.slate200 : SoftPalette.orange700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              final stockIdx = _tabs.indexWhere((t) =>
                  (t['title'] as String).toLowerCase().contains('stock') ||
                  (t['title'] as String).toLowerCase().contains('inventory'));
              if (stockIdx >= 0) {
                _tabController.animateTo(stockIdx);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InventoryPage(
                      branchId: widget.branchId,
                      isDispenser: true,
                    ),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: SoftPalette.orange400,
              foregroundColor: SoftPalette.gray50,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Open Inventory', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: isDark ? SoftPalette.gray50A70 : SoftPalette.gray900A54,
            tooltip: 'Dismiss alert',
            onPressed: () {
              final id = first['id']?.toString();
              if (id != null) _dismissRestockAlert(id);
            },
          ),
        ],
      ),
    );
  }
}
