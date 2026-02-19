// lib/pages/receptionist_screen.dart
// Connection logic replaced with ConnectionManager (auto-discovery, reliable status).
// UI layout unchanged.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';

import '../config/constants.dart';
import '../services/auth_service.dart';
import '../services/local_storage_service.dart' as lss;
import '../services/sync_service.dart';
import '../realtime/connection_manager.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';
import '../widgets/connection_status_widget.dart';
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

class _ReceptionistScreenState extends State<ReceptionistScreen> {
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

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  static const Color _teal = Color(0xFF00695C);

  @override
  void initState() {
    super.initState();
    SyncService().start(widget.branchId);
    _fetchReceptionistName();
    _loadBranchName();
    _listenConnectivity();
    _startBackgroundSync();

    // Listen to connection state changes
    _connectionSub = ConnectionManager().statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
      if (status.isConnected) {
        debugPrint('Receptionist: Connected to ${status.ip}:${status.port}');
      }
    });

    // Start auto-discovery connection
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ConnectionManager().start(
        role: 'receptionist',
        branchId: widget.branchId,
      );
    });

    // Listen to real-time messages for UI refresh
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
      debugPrint('Background sync failed: $e');
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

  Future<void> _fetchReceptionistName() async {
    try {
      final user =
          lss.LocalStorageService.getLocalUserByUid(widget.receptionistId);
      if (mounted) {
        setState(
            () => _username = user?['username'] ?? widget.receptionistName);
      }
    } catch (_) {
      if (mounted) setState(() => _username = widget.receptionistName);
    }
  }

  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
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
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
    }
  }

  Future<void> _forceSync() async {
    if (!_online || _isSyncing || !mounted) return;
    setState(() => _isSyncing = true);
    try {
      await SyncService().forceFullRefresh(widget.branchId);
      await lss.LocalStorageService.downloadTodayTokens(widget.branchId);
      if (mounted) Flushbar(message: 'Full sync completed', backgroundColor: Colors.green.shade700, duration: const Duration(seconds: 3)).show(context);
    } catch (e) {
      if (mounted) Flushbar(message: 'Sync failed: $e', backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 4)).show(context);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    await ConnectionManager().stop();
    await AuthService().signOut();
    if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  void _handlePatientNotFound(String cnic) {
    setState(() { _pendingCnic = cnic; _activeSection = 'register'; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerKey.currentState?.prefillCnic(cnic);
    });
  }

  void _onPatientRegistered(String patientId) {
    setState(() { _pendingCnic = ''; _activeSection = 'token'; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tokenKey.currentState?.focusAndFillCnic(patientId);
    });
  }

  Future<void> _requestTokenReverse(Map<String, dynamic> entry) async {
    final serial = entry['serial'] as String? ?? 'N/A';
    final patientName = entry['patientName'] as String? ?? 'Unknown';
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Token Reversal', style: TextStyle(color: Colors.orange)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Token: #$serial', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Patient: $patientName'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.undo),
            label: const Text('Send Request'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
            onPressed: () => Navigator.pop(ctx, true),
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
        'type': 'token_reversal',
        'status': 'pending',
        'branchId': widget.branchId,
        'receptionistId': widget.receptionistId,
        'receptionistName': _username ?? 'Unknown',
        'tokenSerial': serial,
        'patientId': entry['patientId'] ?? '',
        'patientName': patientName,
        'queueType': entry['queueType'] ?? 'unknown',
        'originalCreatedAt': entry['createdAt'],
        'reason': reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null,
        'requestedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'decision': null,
      });

      if (mounted) {
        Flushbar(message: 'Reversal request sent for #$serial', backgroundColor: Colors.orange[800]!, duration: const Duration(seconds: 4)).show(context);
      }
    } catch (e) {
      if (mounted) Flushbar(message: 'Failed to send request: $e', backgroundColor: Colors.red, duration: const Duration(seconds: 5)).show(context);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _teal,
      elevation: 10,
      shadowColor: Colors.black26,
      toolbarHeight: 100,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Image.asset('assets/logo/gmwf.png', height: 60),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Receptionist – ${_username ?? 'Loading...'}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (!_loadingBranch)
                  Text(_branchName ?? 'Free Dispensary',
                      style: const TextStyle(fontSize: 16, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
      centerTitle: false,
      actions: [
        // Live connection badge — tap to force retry
        ConnectionStatusBadge(
          status: _connectionStatus,
          onRetry: () => ConnectionManager().reconnectNow(),
        ),
        // Internet badge
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _online ? Colors.blue.shade700 : Colors.grey.shade600,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_online ? Icons.cloud : Icons.cloud_off, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(_online ? 'Internet' : 'No Internet',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
        ),
        IconButton(
          icon: _isSyncing
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.sync, size: 32, color: Colors.white),
          tooltip: 'Sync',
          onPressed: _isSyncing ? null : _forceSync,
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

  // ── All UI helpers below are IDENTICAL to original ───────────────────────────

  Widget _buildToggleButton() {
    final isToken = _activeSection == 'token';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: ToggleButtons(
        borderRadius: BorderRadius.circular(32),
        selectedColor: Colors.white,
        fillColor: const Color(0xFF004D40),
        color: const Color(0xFF00695C),
        constraints: const BoxConstraints(minHeight: 52, minWidth: 190),
        isSelected: [!isToken, isToken],
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(children: const [
              Icon(Icons.person_add, size: 22),
              SizedBox(width: 10),
              Text('Register Patient', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(children: const [
              Icon(Icons.token, size: 22),
              SizedBox(width: 10),
              Text('Issue Token', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
          ),
        ],
        onPressed: (index) => setState(() => _activeSection = index == 0 ? 'register' : 'token'),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final allEntries = lss.LocalStorageService.getLocalEntries(widget.branchId);
    final todayEntries = allEntries.where((e) => (e['dateKey'] as String?) == today).toList();

    int zakat = 0, nonZakat = 0, gmwf = 0;
    for (var e in todayEntries) {
      final qt = (e['queueType'] as String?)?.toLowerCase().trim() ?? 'unknown';
      switch (qt) {
        case 'zakat': zakat++; break;
        case 'non-zakat': nonZakat++; break;
        case 'gmwf': gmwf++; break;
        default: zakat++;
      }
    }
    final total = zakat + nonZakat + gmwf;
    final amount = zakat * 20 + nonZakat * 100;

    return Row(children: [
      Expanded(child: _compactSummaryCard('Zakat', zakat, 'Rs. ${zakat * 20}', Colors.green[600]!, Icons.volunteer_activism)),
      const SizedBox(width: 12),
      Expanded(child: _compactSummaryCard('Non-Zakat', nonZakat, 'Rs. ${nonZakat * 100}', Colors.blue[600]!, Icons.person_outline)),
      const SizedBox(width: 12),
      Expanded(child: _compactSummaryCard('GMWF', gmwf, 'Rs. 0', Colors.orange[600]!, null, isImage: true)),
      const SizedBox(width: 12),
      Expanded(child: _compactSummaryCard('Total', total, 'Rs. $amount', Colors.teal[700]!, Icons.people)),
    ]);
  }

  Widget _compactSummaryCard(String title, int count, String amount, Color color, IconData? icon, {bool isImage = false}) {
    return Card(
      elevation: 6,
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        height: 90,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isImage) Image.asset('assets/logo/gmwf.png', height: 28)
            else if (icon != null) Icon(icon, size: 28, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('$count', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(amount, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenLog() {
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
      return const Center(child: Text('No tokens issued today', style: TextStyle(fontSize: 17, color: Colors.grey)));
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (context, i) {
        final e = entries[i];
        final serial = e['serial'] as String? ?? 'N/A';
        final name = e['patientName'] as String? ?? 'Unknown Patient';
        final cnic = (e['cnic'] as String?)?.trim() ?? '';
        final guardianCnic = (e['guardianCnic'] as String?)?.trim() ?? '';
        final queueTypeRaw = (e['queueType'] as String?)?.toLowerCase().trim() ?? 'unknown';
        final timestamp = DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now();
        final hasPrescription = e['prescriptionId'] != null && (e['prescriptionId'] as String?)?.isNotEmpty == true;

        Color badgeColor;
        String displayType;
        switch (queueTypeRaw) {
          case 'zakat': badgeColor = Colors.green[600]!; displayType = 'Zakat'; break;
          case 'non-zakat': badgeColor = Colors.blue[600]!; displayType = 'Non-Zakat'; break;
          case 'gmwf': badgeColor = Colors.orange[600]!; displayType = 'GMWF'; break;
          default: badgeColor = Colors.grey[600]!; displayType = 'Unknown';
        }

        final isPending = !hasPrescription &&
            (e['status'] as String?)?.toLowerCase() != 'prescribed' &&
            (e['status'] as String?)?.toLowerCase() != 'completed';

        final identityParts = <TextSpan>[];
        if (cnic.isNotEmpty) {
          identityParts.addAll([
            const TextSpan(text: 'CNIC: ', style: TextStyle(color: Colors.grey, fontSize: 13)),
            TextSpan(text: cnic, style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const TextSpan(text: '\n'),
          ]);
        }
        if (guardianCnic.isNotEmpty) {
          identityParts.addAll([
            const TextSpan(text: 'Guardian: ', style: TextStyle(color: Colors.grey, fontSize: 13)),
            TextSpan(text: guardianCnic, style: const TextStyle(color: Color(0xFF2C2C2C), fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const TextSpan(text: '\n'),
          ]);
        }
        if (identityParts.isEmpty) {
          identityParts.add(const TextSpan(text: '—', style: TextStyle(color: Colors.grey, fontSize: 13)));
        }

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: CircleAvatar(
              backgroundColor: badgeColor,
              radius: 28,
              child: Text(serial.split('-').last.padLeft(3, '0'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text.rich(TextSpan(children: [
              ...identityParts,
              TextSpan(
                text: 'Issued: ${DateFormat('hh:mm a').format(timestamp)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12.5, height: 1.4),
              ),
            ])),
            trailing: SizedBox(
              width: 220,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Chip(
                        label: Text(displayType, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        backgroundColor: badgeColor,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(height: 2),
                      Text('#$serial', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _teal)),
                    ],
                  ),
                  if (isPending)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: IconButton(
                        icon: const Icon(Icons.undo, color: Colors.redAccent, size: 26),
                        tooltip: 'Request Reversal',
                        onPressed: () => _requestTokenReverse(e),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final leftPadding = MediaQuery.of(context).size.width >= 1100 ? 80.0 : 16.0;

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: leftPadding),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildToggleButton(),
                        const Spacer(),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 36),
                            child: ValueListenableBuilder<Box>(
                              valueListenable:
                                  Hive.box(lss.LocalStorageService.entriesBox).listenable(),
                              builder: (context, _, __) => _buildSummaryCards(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Card(
                            elevation: 12,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
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
                                        onPatientRegistered: _onPatientRegistered,
                                      )
                                    : TokenScreen(
                                        key: _tokenKey,
                                        branchId: widget.branchId,
                                        receptionistId: widget.receptionistId,
                                        receptionistName: widget.receptionistName,
                                        onPatientNotFound: _handlePatientNotFound,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 2,
                          // ValueListenableBuilder reacts the instant any entry
                          // is written to Hive — no polling, no manual setState needed.
                          child: ValueListenableBuilder<Box>(
                            valueListenable:
                                Hive.box(lss.LocalStorageService.entriesBox).listenable(),
                            builder: (context, box, _) {
                              final today = DateFormat('ddMMyy').format(DateTime.now());
                              final todayCount = lss.LocalStorageService
                                  .getLocalEntries(widget.branchId)
                                  .where((e) => (e['dateKey'] as String?) == today)
                                  .length;
                              return Card(
                                elevation: 8,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Icon(Icons.list_alt, color: _teal, size: 32),
                                        const SizedBox(width: 16),
                                        const Text("Today's Tokens",
                                            style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: _teal)),
                                        const Spacer(),
                                        IconButton(
                                          icon: Icon(
                                              _sortNewestFirst
                                                  ? Icons.arrow_downward_rounded
                                                  : Icons.arrow_upward_rounded,
                                              color: _teal),
                                          tooltip: _sortNewestFirst
                                              ? 'Newest first'
                                              : 'Oldest first',
                                          onPressed: () => setState(
                                              () => _sortNewestFirst =
                                                  !_sortNewestFirst),
                                        ),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 12),
                                          child: Text(
                                            '$todayCount total today',
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 18),
                                          ),
                                        ),
                                      ]),
                                      const Divider(height: 36),
                                      Expanded(child: _buildTokenLog()),
                                    ],
                                  ),
                                ),
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
        ),
      ),
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