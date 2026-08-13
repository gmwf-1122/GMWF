// lib/pages/dispensary/receptionist/receptionist_screen.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
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
import 'package:gmwf/widgets/camp_selection_dialog.dart';
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
    with SingleTickerProviderStateMixin {
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
  String _selectedSessionFilter = 'auto';

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
  static const int _tabLog = 1;
  static const int _tabRegister = 2;

  late TabController _mobileTabController;

  bool get _isDark {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        return Hive.box('app_settings').get('is_dark_mode', defaultValue: false) == true;
      }
    } catch (_) {}
    return false;
  }

  String? get _resolvedDispensaryId {
    final active = CampSessionService.getActiveCamp();
    if (active != null && active.isNotEmpty) return active;
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final userData = Hive.box('app_settings').get('user_data');
        if (userData is Map && userData['dispensaryId'] != null) {
          final d = userData['dispensaryId'].toString().trim();
          if (d.isNotEmpty && d.toLowerCase() != 'all') return d.toLowerCase();
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 3, vsync: this);

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
      final data = event['data'] as Map<String, dynamic>?;

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
        final changes = data?['changes'] as Map<String, dynamic>?;

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

          if (mounted) setState(() {});
        }
        return;
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
    if (mounted) setState(() {});
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

  void _onPatientRegistered(String patientId) {
    setState(() {
      _pendingCnic = patientId;
      _activeSection = 'token';
    });
    if (_mobileTabController.length > _tabToken) {
      _mobileTabController.animateTo(_tabToken);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tokenKey.currentState?.focusAndFillCnic(patientId);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _tokenKey.currentState?.focusAndFillCnic(patientId);
        }
      });
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
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _isDark
          ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
          : const [Color(0xFF004D40), Color(0xFF00796B)],
    );

    if (isMobile) {
      return AppBar(
        automaticallyImplyLeading: false,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: gradient)),
        elevation: 4,
        toolbarHeight: 56,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          Image.asset('assets/logo/gmwf-1.webp', height: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Receptionist – ${_username ?? '...'}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 3),
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
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 3),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _online ? Colors.lightBlueAccent : Colors.grey,
            ),
          ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.white, size: 20),
              onPressed: _forceSync,
            ),
          _isLoggingOut
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                  onPressed: _logout,
                ),
        ],
        bottom: TabBar(
          controller: _mobileTabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.token, size: 18), text: 'Token'),
            Tab(icon: Icon(Icons.list_alt, size: 18), text: 'Log'),
            Tab(icon: Icon(Icons.person_add, size: 18), text: 'Register'),
          ],
        ),
      );
    }

    // Desktop AppBar
    return AppBar(
      automaticallyImplyLeading: false,
      flexibleSpace: Container(decoration: BoxDecoration(gradient: gradient)),
      elevation: 10,
      shadowColor: Colors.black26,
      toolbarHeight: 100,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Row(children: [
        Image.asset('assets/logo/gmwf-1.webp', height: 60),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onLongPress: () => DispensaryUserSettingsDialog.show(
                  context,
                  branchId: widget.branchId,
                  onUserUpdated: () {
                    if (mounted) setState(() { _fetchReceptionistName(); });
                  },
                ),
                child: Tooltip(
                  message: 'Long press for Settings',
                  child: Text('Receptionist – ${_username ?? 'Loading...'}',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ),
              if (!_loadingBranch)
                Text(
                  CampSessionService.getBranchAndCampDisplayName(
                    branchName: _branchName ?? 'Free Dispensary',
                    branchId: widget.branchId,
                    campId: CampSessionService.getActiveCamp(),
                  ),
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
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
              : const Icon(Icons.sync, size: 32, color: Colors.white),
          onPressed: _isSyncing ? null : _forceSync,
        ),
        _isLoggingOut
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5)),
              )
            : IconButton(
                icon: const Icon(Icons.logout, size: 32, color: Colors.white),
                onPressed: _logout,
              ),
          const SizedBox(width: 12),
        ],
      );
    }

  Widget _buildSummaryCards(bool isMobile) {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final activeSession = _selectedSessionFilter == 'auto'
        ? CampSessionService.getCurrentSession()
        : _selectedSessionFilter;

    final allEntries = lss.LocalStorageService.getLocalEntries(
      widget.branchId,
      dispensaryId: _resolvedDispensaryId,
      filterByCamp: true,
      session: activeSession,
      filterBySession: activeSession != 'all',
    );
    final todayEntries =
        allEntries.where((e) => (e['dateKey'] as String?) == today).toList();

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
      _compactSummaryCard('Zakat', zakat, 'PKR $zakatAmount',
          Colors.green[600]!, Icons.volunteer_activism, isMobile: isMobile),
      _compactSummaryCard('Non-Zakat', nonZakat, 'PKR $nonZakatAmount',
          Colors.blue[600]!, Icons.person_outline, isMobile: isMobile),
      _compactSummaryCard('GMWF', gmwf, 'PKR 0', Colors.orange[600]!, null,
          isImage: true, isMobile: isMobile),
      _compactSummaryCard('Total', total, 'PKR $totalAmount',
          Colors.teal[700]!, Icons.people, isMobile: isMobile),
    ];

    return Row(
      children: cards
          .map((c) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 2 : 6),
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
    Color color,
    IconData? icon, {
    bool isImage = false,
    bool isMobile = false,
  }) {
    final gradientColors = [
      color.withValues(alpha: 0.85),
      color.withValues(alpha: 0.95),
    ];
    return Container(
      height: isMobile ? 80 : 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          // ── Background watermark (bottom-right) ──────────────────────────
          Positioned(
            right: -10,
            bottom: -10,
            child: isImage
                ? Opacity(
                    opacity: 0.12,
                    child: Image.asset(
                      'assets/logo/gmwf-1.webp',
                      height: isMobile ? 40 : 54,
                    ),
                  )
                : Icon(
                    icon ?? Icons.spa_rounded,
                    size: isMobile ? 40 : 54,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: isMobile ? 10 : 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    // ── Top-right icon/logo ───────────────────────────────
                    if (isImage)
                      Image.asset('assets/logo/gmwf-1.webp',
                          height: isMobile ? 14 : 18)
                    else if (icon != null)
                      Icon(icon,
                          size: isMobile ? 12 : 16,
                          color: Colors.white.withValues(alpha: 0.9)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!isMobile)
                      Text(
                        amount,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenLog(bool isMobile) {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final activeSession = _selectedSessionFilter == 'auto'
        ? CampSessionService.getCurrentSession()
        : _selectedSessionFilter;

    var entries = lss.LocalStorageService
        .getLocalEntries(
          widget.branchId,
          dispensaryId: _resolvedDispensaryId,
          filterByCamp: true,
          session: activeSession,
          filterBySession: activeSession != 'all',
        )
        .where((e) => (e['dateKey'] as String?) == today)
        .toList();

    entries.sort((a, b) {
      final sa = (a['serial'] as String? ?? '000000-000').split('-').last;
      final sb = (b['serial'] as String? ?? '000000-000').split('-').last;
      final na = int.tryParse(sa) ?? 0;
      final nb = int.tryParse(sb) ?? 0;
      return _sortNewestFirst ? nb.compareTo(na) : na.compareTo(nb);
    });

    if (entries.isEmpty) {
      return const Center(
          child: Text('No tokens issued today',
              style: TextStyle(fontSize: 16, color: Colors.grey)));
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (context, i) {
        final e = entries[i];
        final serial = e['serial'] as String? ?? 'N/A';
        final name = e['patientName'] as String? ?? 'Unknown Patient';
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
        final canReverse = _isWaitingOnly(e);

        Color badgeColor;
        String displayType;
        switch (queueTypeRaw) {
          case 'zakat':
            badgeColor = Colors.green[600]!;
            displayType = 'Zakat';
            break;
          case 'non-zakat':
            badgeColor = Colors.blue[600]!;
            displayType = 'Non-Zakat';
            break;
          case 'gmwf':
            badgeColor = Colors.orange[600]!;
            displayType = 'GMWF';
            break;
          default:
            badgeColor = Colors.grey[600]!;
            displayType = 'Unknown';
        }

        final displayCnic = cnic.isNotEmpty
            ? cnic
            : guardianCnic.isNotEmpty
                ? guardianCnic
                : '-';

        if (isMobile) {
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: badgeColor,
                    radius: 20,
                    child: Text(
                      serial.split('-').last.padLeft(3, '0'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                  if (days > 1)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('×$days',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
              title: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayCnic,
                      style: const TextStyle(fontSize: 11)),
                  Row(children: [
                    Text(DateFormat('hh:mm a').format(timestamp),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                    if (hasExtraDays) ...[
                      const SizedBox(width: 6),
                      Text('PKR $tokenAmount',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.bold)),
                    ],
                  ]),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Chip(
                    label: Text(displayType,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10)),
                    backgroundColor: badgeColor,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (canReverse)
                    GestureDetector(
                      onTap: () => _requestTokenReverse(e),
                      child: const Icon(Icons.undo,
                          color: Colors.redAccent, size: 18),
                    ),
                ],
              ),
            ),
          );
        } else {
          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: badgeColor,
                    radius: 28,
                    child: Text(
                      serial.split('-').last.padLeft(3, '0'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ),
                  if (days > 1)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text('×$days',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
              title: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '$displayCnic • ${DateFormat('hh:mm a').format(timestamp)}',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 13)),
                  if (hasExtraDays)
                    Text(
                        'PKR $tokenAmount total ($days-day prescription)',
                        style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    label: Text(displayType,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    backgroundColor: badgeColor,
                  ),
                  if (canReverse) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.undo,
                          color: Colors.redAccent, size: 24),
                      onPressed: () => _requestTokenReverse(e),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(children: [
                        Center(child: _buildDesktopToggle()),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Card(
                            elevation: 12,
                            color: _isDark ? const Color(0xFF1E293B) : Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(36)),
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
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
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _refreshNotifier,
                        builder: (context, _, _) =>
                            ValueListenableBuilder<Box>(
                          valueListenable: _entriesListenable,
                          builder: (context, _, _) =>
                              ValueListenableBuilder<Box>(
                            valueListenable: _patientsListenable,
                            builder: (context, box, _) {
                              final today =
                                  DateFormat('ddMMyy').format(DateTime.now());
                              final todayCount = lss.LocalStorageService
                                  .getLocalEntries(widget.branchId, dispensaryId: _resolvedDispensaryId, filterByCamp: true)
                                  .where((e) =>
                                      (e['dateKey'] as String?) == today)
                                  .length;

                              return Column(children: [
                                _buildSummaryCards(false),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: Card(
                                    elevation: 8,
                                    color: _isDark ? const Color(0xFF1E293B) : Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(24)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Icon(Icons.list_alt,
                                                color: _isDark ? const Color(0xFF38BDF8) : _teal, size: 32),
                                            const SizedBox(width: 16),
                                            Text("Today's Tokens",
                                                style: TextStyle(
                                                    fontSize: 22,
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
                                                  color: _isDark ? const Color(0xFF38BDF8) : _teal),
                                              onPressed: () => setState(() =>
                                                  _sortNewestFirst =
                                                      !_sortNewestFirst),
                                            ),
                                            // Refresh Button
                                            IconButton(
                                              icon: Icon(Icons.refresh,
                                                  color: _isDark ? const Color(0xFF38BDF8) : _teal, size: 28),
                                              onPressed: _refreshTokenLog,
                                              tooltip: 'Refresh token list',
                                            ),
                                          ]),
                                          Text('$todayCount total',
                                              style: TextStyle(
                                                  color: _isDark ? const Color(0xFF94A3B8) : Colors.grey,
                                                  fontSize: 16)),
                                          const Divider(height: 36),
                                          Expanded(
                                              child: _buildTokenLog(false)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ]);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
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
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
        ],
      ),
      child: ToggleButtons(
        borderRadius: BorderRadius.circular(32),
        selectedColor: Colors.white,
        fillColor: _isDark ? const Color(0xFF0F766E) : const Color(0xFF004D40),
        color: _isDark ? const Color(0xFFCBD5E1) : const Color(0xFF00695C),
        constraints:
            const BoxConstraints(minHeight: 52, minWidth: 190),
        isSelected: [!isToken, isToken],
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(children: const [
              Icon(Icons.person_add, size: 22),
              SizedBox(width: 10),
              Text('Register Patient',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(children: const [
              Icon(Icons.token, size: 22),
              SizedBox(width: 10),
              Text('Issue Token',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
        ],
        onPressed: (index) => setState(
            () => _activeSection = index == 0 ? 'register' : 'token'),
      ),
    );
  }

  @override
  void dispose() {
    CampSessionService.activeCampNotifier.removeListener(_onActiveCampChanged);
    _refreshNotifier.dispose();
    _mobileTabController.dispose();
    ConnectionManager().stop();
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }
}