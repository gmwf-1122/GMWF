// lib/pages/receptionist_screen.dart
//
// ARCHITECTURE FIX:
//   The receptionist is a pure LAN CLIENT — not a server.
//   The dedicated server device runs ServerDashboardWithSync.
//   This screen now connects via ConnectionManager (LanDiscovery → WebSocket)
//   exactly the same way as the doctor and dispenser screens.
//
//   REMOVED: All LanHostManager.startHost() / LanHostManager.stopHost() calls.
//   ConnectionManager.start() handles everything.
//
// MOBILE TAB ORDER: Token (0) | Log (1) | Register (2)

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';

import '../../../config/constants.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_storage_service.dart' as lss;
import '../../../services/sync_service.dart';
import '../../../realtime/connection_manager.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';
import '../../../widgets/connection_status_widget.dart';
import 'patient_register.dart';
import 'token_screen.dart';

class ReceptionistScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String receptionistName;

  const ReceptionistScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
    required this.receptionistName,
  });

  @override
  State<ReceptionistScreen> createState() => _ReceptionistScreenState();
}

class _ReceptionistScreenState extends State<ReceptionistScreen>
    with SingleTickerProviderStateMixin {
  String? _username;
  String? _branchName;
  String _pendingCnic    = '';
  String _activeSection  = 'token'; // desktop toggle

  final GlobalKey<PatientRegisterPageState> _registerKey =
      GlobalKey<PatientRegisterPageState>();
  final GlobalKey<TokenScreenState> _tokenKey =
      GlobalKey<TokenScreenState>();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<Map<String, dynamic>>?     _realtimeSub;
  StreamSubscription<ConnectionStatus>?         _connectionSub;

  bool _online        = true;
  bool _isSyncing     = false;
  bool _loadingBranch = true;
  bool _sortNewestFirst = true;

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  static const Color _teal = Color(0xFF00695C);

  // ── Tab indices (mobile) ─────────────────────────────────────────────────────
  // 0 = Token  |  1 = Log  |  2 = Register
  static const int _tabToken    = 0;
  static const int _tabLog      = 1;
  static const int _tabRegister = 2;

  late TabController _mobileTabController;

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 3, vsync: this);

    SyncService().start(widget.branchId);
    _fetchReceptionistName();
    _loadBranchName();
    _listenConnectivity();
    _startBackgroundSync();

    // ── LAN connection (pure client — same as doctor / dispenser) ────────────
    _connectionSub =
        ConnectionManager().statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Connect as a regular client to the dedicated server.
      ConnectionManager().start(
        role:     'receptionist',
        branchId: widget.branchId,
      );
    });

    _realtimeSub = RealtimeManager().messageStream.listen((event) {
      final type = event['event_type'] as String?;
      if (type == RealtimeEvents.saveEntry ||
          type == RealtimeEvents.savePrescription ||
          type == 'dispense_completed' ||
          type == 'token_created' ||
          type == 'prescription_created') {
        if (mounted) setState(() {});
      }
    });
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
    _connSub =
        Connectivity().onConnectivityChanged.listen((results) {
      final isOnline =
          results.any((r) => r != ConnectivityResult.none);
      if (_online != isOnline && mounted) {
        setState(() => _online = isOnline);
        if (isOnline) _forceSync();
      }
    });
  }

  Future<void> _fetchReceptionistName() async {
    try {
      final user = lss.LocalStorageService.getLocalUserByUid(
          widget.receptionistId);
      if (mounted) {
        setState(() =>
            _username = user?['username'] ?? widget.receptionistName);
      }
    } catch (_) {
      if (mounted) setState(() => _username = widget.receptionistName);
    }
  }

  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) {
        setState(() {
          _branchName   = 'Free Dispensary';
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
          _branchName   = doc.data()?['name'] ?? 'Free Dispensary';
          _loadingBranch = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _branchName   = 'Free Dispensary';
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

  Future<void> _logout() async {
    // Stop LAN client connection.
    await ConnectionManager().stop();
    await AuthService().signOut();
    if (mounted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (r) => false);
    }
  }

  // ── Patient-not-found → open Register tab (index 2 on mobile) ────────────────
  void _handlePatientNotFound(String cnic) {
    setState(() {
      _pendingCnic  = cnic;
      _activeSection = 'register';
    });
    _mobileTabController.animateTo(_tabRegister);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerKey.currentState?.prefillCnic(cnic);
    });
  }

  // ── After registration → back to Token tab (index 0 on mobile) ───────────────
  void _onPatientRegistered(String patientId) {
    setState(() {
      _pendingCnic  = '';
      _activeSection = 'token';
    });
    _mobileTabController.animateTo(_tabToken);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tokenKey.currentState?.focusAndFillCnic(patientId);
    });
  }

  Future<void> _requestTokenReverse(Map<String, dynamic> entry) async {
    final serial      = entry['serial'] as String?      ?? 'N/A';
    final patientName = entry['patientName'] as String? ?? 'Unknown';
    final reasonCtrl  = TextEditingController();

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
            onPressed: () {
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop(false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon:  const Icon(Icons.undo),
            label: const Text('Send Request'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800]),
            onPressed: () {
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop(true);
            },
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .add({
        'type':              'token_reversal',
        'status':            'pending',
        'branchId':          widget.branchId,
        'receptionistId':    widget.receptionistId,
        'receptionistName':  _username ?? 'Unknown',
        'tokenSerial':       serial,
        'patientId':         entry['patientId'] ?? '',
        'patientName':       patientName,
        'queueType':         entry['queueType'] ?? 'unknown',
        'originalCreatedAt': entry['createdAt'],
        'reason':
            reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null,
        'requestedAt': FieldValue.serverTimestamp(),
        'reviewedAt':  null,
        'reviewedBy':  null,
        'decision':    null,
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

  // ── AppBar ────────────────────────────────────────────────────────────────────
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
          // LAN status dot
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 3),
            width: 9, height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connectionStatus.isConnected
                  ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
          // Internet status dot
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 3),
            width: 9, height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _online ? Colors.lightBlueAccent : Colors.grey,
            ),
          ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.white, size: 20),
              onPressed: _forceSync,
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white, size: 20),
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _mobileTabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.token, size: 18),      text: 'Token'),
            Tab(icon: Icon(Icons.list_alt, size: 18),   text: 'Log'),
            Tab(icon: Icon(Icons.person_add, size: 18), text: 'Register'),
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
              Text(
                'Receptionist – ${_username ?? 'Loading...'}',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              if (!_loadingBranch)
                Text(
                  _branchName ?? 'Free Dispensary',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
            ],
          ),
        ),
      ]),
      centerTitle: false,
      actions: [
        ConnectionStatusBadge(
          status:  _connectionStatus,
          onRetry: () => ConnectionManager().reconnectNow(),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _online
                ? Colors.blue.shade700 : Colors.grey.shade600,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_online ? Icons.cloud : Icons.cloud_off,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              _online ? 'Internet' : 'No Internet',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ]),
        ),
        IconButton(
          icon: _isSyncing
              ? const SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.sync, size: 32, color: Colors.white),
          onPressed: _isSyncing ? null : _forceSync,
        ),
        IconButton(
          icon: const Icon(Icons.logout, size: 32, color: Colors.white),
          onPressed: _logout,
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  // ── Summary cards ─────────────────────────────────────────────────────────────
  Widget _buildSummaryCards(bool isMobile) {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final allEntries =
        lss.LocalStorageService.getLocalEntries(widget.branchId);
    final todayEntries =
        allEntries.where((e) => (e['dateKey'] as String?) == today).toList();

    int zakat = 0, nonZakat = 0, gmwf = 0;
    for (var e in todayEntries) {
      final qt =
          (e['queueType'] as String?)?.toLowerCase().trim() ?? 'unknown';
      switch (qt) {
        case 'zakat':     zakat++;    break;
        case 'non-zakat': nonZakat++; break;
        case 'gmwf':      gmwf++;     break;
        default:          zakat++;
      }
    }
    final total  = zakat + nonZakat + gmwf;
    final amount = zakat * 20 + nonZakat * 100;

    final cards = [
      _compactSummaryCard('Zakat',     zakat,    'Rs. ${zakat * 20}',
          Colors.green[600]!, Icons.volunteer_activism, isMobile: isMobile),
      _compactSummaryCard('Non-Zakat', nonZakat, 'Rs. ${nonZakat * 100}',
          Colors.blue[600]!, Icons.person_outline, isMobile: isMobile),
      _compactSummaryCard('GMWF',      gmwf,     'Rs. 0',
          Colors.orange[600]!, null, isImage: true, isMobile: isMobile),
      _compactSummaryCard('Total',     total,    'Rs. $amount',
          Colors.teal[700]!, Icons.people, isMobile: isMobile),
    ];

    return Row(
      children: cards
          .map((c) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 2 : 6),
                  child: c,
                ),
              ))
          .toList(),
    );
  }

  Widget _compactSummaryCard(
    String title, int count, String amount, Color color, IconData? icon,
    {bool isImage = false, bool isMobile = false}) {
    return Card(
      elevation: 4,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: isMobile ? 70 : 90,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isImage)
              Image.asset('assets/logo/gmwf.png',
                  height: isMobile ? 18 : 22)
            else if (icon != null)
              Icon(icon,
                  size: isMobile ? 16 : 22, color: Colors.white),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 9 : 11,
                  fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '$count',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold),
            ),
            if (!isMobile)
              Text(amount,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  // ── Token log ─────────────────────────────────────────────────────────────────
  Widget _buildTokenLog(bool isMobile) {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    var entries = lss.LocalStorageService.getLocalEntries(widget.branchId)
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
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (context, i) {
        final e            = entries[i];
        final serial       = e['serial'] as String?      ?? 'N/A';
        final name         = e['patientName'] as String? ?? 'Unknown Patient';
        final cnic         = (e['cnic'] as String?)?.trim()         ?? '';
        final guardianCnic = (e['guardianCnic'] as String?)?.trim() ?? '';
        final queueTypeRaw =
            (e['queueType'] as String?)?.toLowerCase().trim() ?? 'unknown';
        final timestamp    =
            DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now();
        final hasPrescription =
            e['prescriptionId'] != null &&
                (e['prescriptionId'] as String?)?.isNotEmpty == true;
        final isPending = !hasPrescription &&
            (e['status'] as String?)?.toLowerCase() != 'prescribed' &&
            (e['status'] as String?)?.toLowerCase() != 'completed';

        Color  badgeColor;
        String displayType;
        switch (queueTypeRaw) {
          case 'zakat':
            badgeColor = Colors.green[600]!;  displayType = 'Zakat';     break;
          case 'non-zakat':
            badgeColor = Colors.blue[600]!;   displayType = 'Non-Zakat'; break;
          case 'gmwf':
            badgeColor = Colors.orange[600]!; displayType = 'GMWF';      break;
          default:
            badgeColor = Colors.grey[600]!;   displayType = 'Unknown';
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
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              leading: CircleAvatar(
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
              title: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayCnic,
                      style: const TextStyle(fontSize: 11)),
                  Text(DateFormat('hh:mm a').format(timestamp),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
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
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (isPending)
                    GestureDetector(
                      onTap: () => _requestTokenReverse(e),
                      child: const Icon(Icons.undo,
                          color: Colors.redAccent, size: 18),
                    ),
                ],
              ),
            ),
          );
        } else {      // Desktop row
          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              leading: CircleAvatar(
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
              title: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: Text(
                '$displayCnic  •  ${DateFormat('hh:mm a').format(timestamp)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                      label: Text(displayType,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      backgroundColor: badgeColor),
                  if (isPending) ...[
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
    final isMobile   = screenWidth < 800;

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
        child: isMobile ? _buildMobileBody() : _buildDesktopBody(),
      ),
    );
  }

  // ── Mobile TabBarView ─────────────────────────────────────────────────────────
  Widget _buildMobileBody() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: ValueListenableBuilder<Box>(
          valueListenable:
              Hive.box(lss.LocalStorageService.entriesBox).listenable(),
          builder: (context, _, __) => _buildSummaryCards(true),
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
                      color: _teal, size: 20,
                    ),
                    onPressed: () => setState(
                        () => _sortNewestFirst = !_sortNewestFirst),
                  ),
                ]),
                const SizedBox(height: 4),
                Expanded(
                  child: ValueListenableBuilder<Box>(
                    valueListenable: Hive.box(
                        lss.LocalStorageService.entriesBox).listenable(),
                    builder: (context, _, __) => _buildTokenLog(true),
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

  // ── Desktop layout ────────────────────────────────────────────────────────────
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
              // Main content area
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left section - Toggle button above Token/Register card
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // Toggle button centered above the card
                          Center(child: _buildDesktopToggle()),
                          const SizedBox(height: 16),
                          // Token/Register card
                          Expanded(
                            child: Card(
                              elevation: 12,
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
                                            receptionistName: widget.receptionistName,
                                            onPatientNotFound:
                                                _handlePatientNotFound,
                                          ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Right section - Summary cards above Today's Tokens card
                    Expanded(
                      flex: 2,
                      child: ValueListenableBuilder<Box>(
                        valueListenable: Hive.box(
                            lss.LocalStorageService.entriesBox).listenable(),
                        builder: (context, box, _) {
                          final today =
                              DateFormat('ddMMyy').format(DateTime.now());
                          final todayCount = lss.LocalStorageService
                              .getLocalEntries(widget.branchId)
                              .where((e) =>
                                  (e['dateKey'] as String?) == today)
                              .length;
                          return Column(
                            children: [
                              // Summary cards positioned higher to align with toggle button
                              SizedBox(height: 0), // Minimal top spacing
                              _buildSummaryCards(false),
                              const SizedBox(height: 16),
                              // Today's Tokens card - now matches height with Token screen card
                              Expanded(
                                child: Card(
                                  elevation: 8,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Today's Tokens header
                                          Row(children: [
                                            Icon(Icons.list_alt,
                                                color: _teal, size: 32),
                                            const SizedBox(width: 16),
                                            const Text(
                                              "Today's Tokens",
                                              style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                  color: _teal),
                                            ),
                                            const Spacer(),
                                            IconButton(
                                              icon: Icon(
                                                _sortNewestFirst
                                                    ? Icons.arrow_downward_rounded
                                                    : Icons.arrow_upward_rounded,
                                                color: _teal,
                                              ),
                                              onPressed: () => setState(() =>
                                                  _sortNewestFirst =
                                                      !_sortNewestFirst)),
                                            ],
                                          ),
                                          Text('$todayCount total',
                                              style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 16)),
                                          const Divider(height: 36),
                                          // Today's Tokens list
                                          Expanded(
                                              child: _buildTokenLog(false)),
                                        ]),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 5))
        ],
      ),
      child: ToggleButtons(
        borderRadius: BorderRadius.circular(32),
        selectedColor: Colors.white,
        fillColor: const Color(0xFF004D40),
        color: const Color(0xFF00695C),
        constraints:
            const BoxConstraints(minHeight: 52, minWidth: 190),
        isSelected: [!isToken, isToken],
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 8),
            child: Row(children: const [
              Icon(Icons.person_add, size: 22),
              SizedBox(width: 10),
              Text('Register Patient',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 8),
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
    _mobileTabController.dispose();
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }
}