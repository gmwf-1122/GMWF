// lib/pages/dispensary/dispensar/dispensar_screen.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:another_flushbar/flushbar.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/sync_service.dart';
import 'package:gmwf/services/auth_service.dart';
import 'package:gmwf/realtime/connection_manager.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/widgets/connection_status_widget.dart';
import 'package:gmwf/widgets/camp_selection_dialog.dart';
import '../user_settings_dialog.dart';
import 'inventory.dart';
import 'patient_form.dart';
import 'patient_list.dart';

class DispensarScreen extends StatefulWidget {
  final String branchId;
  final bool isEmbedded;
  const DispensarScreen({
    super.key,
    required this.branchId,
    this.isEmbedded = false,
  });

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
  bool _showingForm = false;

  ConnectionStatus _connectionStatus = const ConnectionStatus(
    state: LanConnectionState.disconnected,
    message: 'Not connected',
  );

  String? _dispenserName;
  String? _branchName;
  bool _loadingBranch = true;

  Map<String, dynamic>? _selectedQueueEntry;

  // [BUG-13] Remove function returned by addReconnectListener
  VoidCallback? _removeReconnectListener;

  // [BUG-12] Debounce + guard for reconnect-triggered sync
  Timer? _syncDebounce;
  bool _reconnectSyncing = false;

  static const Color _teal = Color(0xFF00695C);

  @override
  void initState() {
    super.initState();
    if (!widget.isEmbedded) {
      SyncService().start(widget.branchId);
    }
    _listenConnectivity();

    // [FIX-USERNAME] Load name first, then start ConnectionManager with it.
    // We do NOT call ConnectionManager().start() in postFrameCallback anymore
    // because at that point _dispenserName is still null (async fetch pending).
    // Instead _fetchDispenserName() starts the connection once the name is resolved.
    _fetchDispenserName();
    _loadBranchName();

    _connectionSub = ConnectionManager().statusStream.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
      // [BUG-12] Debounce: only trigger sync after 300 ms of stable connection
      if (status.isConnected && !widget.isEmbedded) {
        _syncDebounce?.cancel();
        _syncDebounce = Timer(const Duration(milliseconds: 300), _syncOnReconnect);
      }
    });

    // [BUG-13] Register via listener list — safe alongside DoctorScreen
    if (!widget.isEmbedded) {
      _removeReconnectListener = ConnectionManager().addReconnectListener(_syncOnReconnect);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!widget.isEmbedded) {
        _startBackgroundSync();
      }
    });

    _realtimeSub = RealtimeManager().messageStream.listen(_handleRealtimeMessage);
  }

  // [FIX-USERNAME] Resolve dispenser name then start/update connection with it.
  Future<void> _fetchDispenserName() async {
    String? resolvedName;

    // 1. Try local cache first (fast, no network needed).
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final local = LocalStorageService.getLocalUserByUid(user.uid);
      resolvedName = (local?['username'] as String?)?.trim();
      if (resolvedName?.isEmpty == true) resolvedName = null;
    }

    // 2. Fall back to email prefix while Firestore loads.
    resolvedName ??= user?.email?.split('@').first;

    if (mounted) setState(() => _dispenserName = resolvedName);

    // 3. Start connection with whatever name we have so far.
    //    This ensures the identify message goes out quickly.
    if (!widget.isEmbedded) {
      ConnectionManager().start(
        role:     'dispenser',
        branchId: widget.branchId,
        username: resolvedName,
      );
      if (resolvedName != null) {
        RealtimeManager().updateUsername(resolvedName);
      }
    }

    // 4. Fetch from Firestore for the authoritative display name.
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final firestoreName =
            (doc.data()?['username'] as String?)?.trim() ??
            (doc.data()?['name']     as String?)?.trim();
        if (firestoreName != null && firestoreName.isNotEmpty) {
          if (mounted) setState(() => _dispenserName = firestoreName);
          // [FIX-USERNAME] Push updated name into RealtimeManager so future
          // messages carry the correct attribution.
          if (!widget.isEmbedded) {
            RealtimeManager().updateUsername(firestoreName);
          }
        }
      } catch (e) {
        debugPrint('[Dispenser] Could not fetch dispenser name from Firestore: $e');
      }
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
      debugPrint('[Dispenser] ✅ Synced on reconnect');
    } catch (e) {
      debugPrint('[Dispenser] Reconnect sync failed: $e');
    } finally {
      _reconnectSyncing = false;
    }
  }

  Future<void> _startBackgroundSync() async {
    try {
      await LocalStorageService.downloadInventory(widget.branchId);
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

    final serial = data['serial']?.toString().trim();
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Flushbar(
            message: '💊 Prescription ready for #$serial',
            backgroundColor: Colors.blue.shade700,
            duration: const Duration(seconds: 5),
          ).show(context);
        }
      });

    } else if (type == RealtimeEvents.saveEntry || type == 'token_created') {
      // [BUG-14] Use saveEntryLocal for proper sanitisation
      LocalStorageService.saveEntryLocal(widget.branchId, serial, data);
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Flushbar(
            message: '🎟️ New token: #$serial',
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ).show(context);
        }
      });

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
        setState(() {
          _selectedQueueEntry = null;
          _showingForm = false;
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Flushbar(
              message: isOnline ? 'Internet restored — syncing...' : 'Offline (LAN still works)',
              backgroundColor: isOnline ? Colors.green.shade700 : Colors.orange.shade700,
              duration: const Duration(seconds: 4),
            ).show(context);
          }
        });
        if (isOnline) _forceSync();
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
          Flushbar(message: 'Full sync completed', backgroundColor: Colors.green.shade700, duration: const Duration(seconds: 4)).show(context);
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Flushbar(message: 'Sync failed: $e', backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 5)).show(context);
        }
      });
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    if (mounted) setState(() => _isLoggingOut = true);
    try { _connectionSub?.cancel(); _connSub?.cancel(); _realtimeSub?.cancel(); } catch (_) {}
    ConnectionManager().stop().catchError((_) {});
    await AuthService().signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    if (isMobile) {
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _isDark ? const Color(0xFF0F172A) : _teal,
        elevation: 4,
        toolbarHeight: 60,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          Image.asset('assets/logo/gmwf-1.webp', height: 36),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Dispensary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connectionStatus.isConnected ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _online ? Colors.lightBlueAccent : Colors.grey,
            ),
          ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 18),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.sync, color: Colors.white, size: 22), onPressed: _forceSync),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 22),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => InventoryPage(branchId: widget.branchId, isDispenser: true)),
            ),
          ),
          _isLoggingOut
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.logout, color: Colors.white, size: 22), onPressed: _logout),
        ],
      );
    }

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: _isDark ? const Color(0xFF0F172A) : _teal,
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
                    if (mounted) setState(() { _fetchDispenserName(); });
                  },
                ),
                child: Tooltip(
                  message: 'Long press for Settings',
                  child: Text('Dispensary – ${_dispenserName ?? 'Loading...'}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
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
        ConnectionStatusBadge(status: _connectionStatus, onRetry: () => ConnectionManager().reconnectNow()),
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
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.sync, size: 32, color: Colors.white),
          onPressed: _isSyncing ? null : _forceSync,
        ),
        IconButton(
          icon: const Icon(Icons.inventory_2_outlined, size: 32, color: Colors.white),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => InventoryPage(branchId: widget.branchId, isDispenser: true)),
          ),
        ),
        _isLoggingOut
            ? const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))))
            : IconButton(icon: const Icon(Icons.logout, size: 32, color: Colors.white), onPressed: _logout),
        const SizedBox(width: 12),
      ],
    );
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
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('app_settings').listenable(keys: ['is_dark_mode']),
      builder: (context, box, _) {
        final isDark = box.get('is_dark_mode', defaultValue: false) == true;

        final bodyContent = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
                  : const [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
            ),
          ),
          child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
        );

        return ValueListenableBuilder<Box>(
          valueListenable: Hive.box(LocalStorageService.entriesBox).listenable(),
          builder: (context, entriesBox, _) {
            return ValueListenableBuilder<Box>(
              valueListenable: Hive.box(LocalStorageService.prescriptionsBox).listenable(),
              builder: (context, prescriptionsBox, _) {
                if (widget.isEmbedded) return bodyContent;

                return Scaffold(
                  backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F8F5),
                  appBar: _buildAppBar(isMobile),
                  body: bodyContent,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    if (_showingForm && _selectedQueueEntry != null) {
      return Column(children: [
        Container(
          color: _isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Row(children: [
            TextButton.icon(
              onPressed: () => setState(() { _showingForm = false; }),
              icon: Icon(Icons.arrow_back, color: _isDark ? const Color(0xFF38BDF8) : _teal),
              label: Text('Queue', style: TextStyle(color: _isDark ? const Color(0xFF38BDF8) : _teal)),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '#${_selectedQueueEntry!['serial'] ?? ''}',
                style: TextStyle(fontWeight: FontWeight.bold, color: _isDark ? Colors.white : _teal),
              ),
            ),
          ]),
        ),
        Divider(height: 1, color: _isDark ? const Color(0xFF334155) : null),
        Expanded(
          child: PatientForm(
            branchId: widget.branchId,
            queueEntry: _selectedQueueEntry!,
            onDispensed: () => setState(() { _selectedQueueEntry = null; _showingForm = false; }),
            dispenserName: _dispenserName,
          ),
        ),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: PatientList(
        branchId: widget.branchId,
        selectedPatient: _selectedQueueEntry,
        onPatientSelected: (e) {
          if (e.isEmpty) return;
          setState(() {
            _selectedQueueEntry = e;
            _showingForm = true;
          });
        },
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return LayoutBuilder(builder: (context, constraints) {
      final isTablet = constraints.maxWidth >= 1000;
      return Row(children: [
        Container(
          width: isTablet ? 480 : constraints.maxWidth * 0.42,
          decoration: BoxDecoration(
            color: _isDark ? const Color(0xFF1E293B).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.7),
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
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _selectedQueueEntry == null
                  ? Container(
                      color: _isDark ? const Color(0xFF1E293B) : Colors.white,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.medical_information_outlined, size: 80, color: _isDark ? const Color(0xFF475569) : Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'Select a patient to dispense medicines',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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
      ]);
    });
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    // [BUG-13] Unregister from ConnectionManager's listener list
    _removeReconnectListener?.call();
    ConnectionManager().stop();
    _connectionSub?.cancel();
    _connSub?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }
}
