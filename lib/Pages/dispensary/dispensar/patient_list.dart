// lib/pages/dispensary/dispensar/patient_list.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/services/serials_service.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/theme/app_theme.dart';

class PatientList extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? selectedPatient;
  final Function(Map<String, dynamic>) onPatientSelected;

  const PatientList({
    super.key,
    required this.branchId,
    this.selectedPatient,
    required this.onPatientSelected,
  });

  @override
  State<PatientList> createState() => _PatientListState();
}

class _PatientListState extends State<PatientList>
    with SingleTickerProviderStateMixin {
  static const Color _teal   = Color(0xFF00695C);
  static const Color _amber  = Color(0xFFFFA000);
  static const Color _blue   = Color(0xFF1976D2);
  static const Color _purple = Color(0xFF6A1B9A);

  bool get _isDark {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        return Hive.box('app_settings').get('is_dark_mode', defaultValue: false) == true;
      }
    } catch (_) {}
    return false;
  }

  late final AnimationController _pulse;
  final ScrollController _scroll = ScrollController();

  String get _todayKey => CampSessionService.resolveShiftAndDateKey().dateKey;
  String _selectedSessionFilter = 'auto';

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;
  List<StreamSubscription>? _todaySerialsSubs;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _realtimeSub = RealtimeManager().messageStream.listen((event) {
      final type = event['event_type'] as String?;
      final data = event['data'] as Map<String, dynamic>?;
      if (type == null || !mounted) return;

      final eventBranch = data?['branchId']?.toString().trim().toLowerCase();
      final myBranch    = widget.branchId.toLowerCase().trim();
      if (eventBranch != null && eventBranch != myBranch) return;

      if (type == RealtimeEvents.savePrescription ||
          type == RealtimeEvents.saveEntry ||
          type == 'dispense_completed') {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryAutoSelectSmallestPending();
        });
      }
    });

    _startTodaySerialsListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoSelectSmallestPending();
    });
  }

  @override
  void didUpdateWidget(PatientList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPatient != widget.selectedPatient ||
        widget.selectedPatient == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryAutoSelectSmallestPending();
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    _realtimeSub?.cancel();
    _cancelTodaySerialsListeners();
    super.dispose();
  }

  void _startTodaySerialsListener() {
    _cancelTodaySerialsListeners();
    if (widget.branchId.isEmpty) return;
    _todaySerialsSubs = [];
    final serialsRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(_todayKey);

    for (final type in ['zakat', 'non-zakat', 'gmwf']) {
      final sub = serialsRef.collection(type).snapshots().listen((snap) {
        bool hasChanges = false;
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.added ||
              change.type == DocumentChangeType.modified) {
            final data = change.doc.data();
            if (data != null) {
              final serial = change.doc.id;
              final entryData = Map<String, dynamic>.from(data);
              entryData['queueType'] ??= type;
              entryData['dateKey']   ??= _todayKey;
              entryData['serial']    ??= serial;
              LocalStorageService.saveEntryLocal(widget.branchId, serial, entryData);
              hasChanges = true;
            }
          }
        }
        if (hasChanges && mounted) {
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryAutoSelectSmallestPending();
          });
        }
      }, onError: (e) {
        debugPrint('[PatientList] Today serials listener error ($type): $e');
      });
      _todaySerialsSubs!.add(sub);
    }
  }

  void _cancelTodaySerialsListeners() {
    if (_todaySerialsSubs != null) {
      for (final sub in _todaySerialsSubs!) {
        sub.cancel();
      }
      _todaySerialsSubs = null;
    }
  }

  int _extractSerialNumber(Map<String, dynamic> p) {
    final s = (p['serial'] ?? p['id'] ?? '').toString();
    return parseSequenceFromSerial(s);
  }

  String? get _userDispensaryId {
    final active = CampSessionService.getActiveCamp();
    if (active != null && active.isNotEmpty) return active;
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final userData = Hive.box('app_settings').get('user_data');
        if (userData is Map && userData['dispensaryId'] != null) {
          final d = userData['dispensaryId'].toString().trim().toLowerCase();
          if (d.isNotEmpty && d != 'all') return d;
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── Two-group sort ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _getSortedQueue() {
    final userDisp = _userDispensaryId;
    final activeShift = CampSessionService.getCurrentSession();
    final targetSession = _selectedSessionFilter == 'auto'
        ? activeShift
        : _selectedSessionFilter;

    var all = LocalStorageService.getLocalEntries(
          widget.branchId,
          dispensaryId: userDisp,
          filterByCamp: true,
        )
        .where((e) {
          final dateKey = e['dateKey']?.toString() ?? '';
          final status  = (e['status'] ?? '').toString().toLowerCase();
          final hasPresc = e['prescription'] != null;
          return dateKey == _todayKey && (status == 'completed' || status == 'dispensed' || status == 'prescribed' || hasPresc);
        })
        .toList();

    if (targetSession != 'all') {
      final String? priorShift = switch (activeShift) {
        'evening' => 'morning',
        'night'   => 'evening',
        _         => null,
      };

      all = all.where((entry) {
        final s = (entry['session'] ?? '').toString().toLowerCase().trim();
        final ds = (entry['dispenseStatus'] ?? '').toString().toLowerCase();
        final isUndispensed = ds != 'dispensed';
        if (s == targetSession) return true;
        // Prior shift carryover
        if (_selectedSessionFilter == 'auto' && priorShift != null && s == priorShift && isUndispensed) {
          return true;
        }
        return false;
      }).toList();
    }

    final pending   = <Map<String, dynamic>>[];
    final onHold    = <Map<String, dynamic>>[];
    final dispensed = <Map<String, dynamic>>[];

    for (final e in all) {
      final ds = (e['dispenseStatus'] ?? '').toString().toLowerCase();
      if (ds == 'dispensed') {
        dispensed.add(e);
      } else if (ds == 'on_hold' || ds == 'hold') {
        onHold.add(e);
      } else {
        pending.add(e);
      }
    }

    int compareTokens(Map<String, dynamic> a, Map<String, dynamic> b) {
      final numA = _extractSerialNumber(a);
      final numB = _extractSerialNumber(b);
      if (numA != numB) return numA.compareTo(numB);
      final dtA = a['createdAt']?.toString() ?? '';
      final dtB = b['createdAt']?.toString() ?? '';
      return dtA.compareTo(dtB);
    }

    pending.sort(compareTokens);
    onHold.sort(compareTokens);
    dispensed.sort(compareTokens);

    return [...pending, ...onHold, ...dispensed];
  }

  // ─── Auto-select smallest active pending ─────────────────────────────────
  void _tryAutoSelectSmallestPending() {
    if (!mounted) return;
    final queue = _getSortedQueue();
    final activePending = queue
        .where((p) {
          final ds = (p['dispenseStatus'] ?? '').toString().toLowerCase();
          return ds != 'dispensed' && ds != 'on_hold' && ds != 'hold';
        })
        .toList();

    if (activePending.isEmpty) {
      if (widget.selectedPatient != null &&
          (widget.selectedPatient?['serial']?.toString() ?? '').isNotEmpty) {
        widget.onPatientSelected({});
      }
      return;
    }

    final currentSerial = widget.selectedPatient?['serial']?.toString() ?? '';

    // Only auto-select if nothing is currently selected, or the current
    // selection is no longer active (just got dispensed or put on hold).
    final currentIsStillActive = activePending
        .any((p) => (p['serial']?.toString() ?? '') == currentSerial);

    if (currentSerial.isEmpty || !currentIsStillActive) {
      final smallest = activePending.first;
      debugPrint(
          '[PatientList] Auto-selecting active: ${smallest['serial']}');
      widget.onPatientSelected(smallest);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile    = screenWidth < 700;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            color: _isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 20 : 36),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              Container(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 28,
                  isMobile ? 16 : 28,
                  isMobile ? 16 : 28,
                  isMobile ? 14 : 24,
                ),
                decoration: BoxDecoration(
                  color: _isDark ? const Color(0xFF0F766E) : _teal,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(isMobile ? 20 : 36)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_pharmacy,
                        color: Colors.white, size: isMobile ? 22 : 30),
                    SizedBox(width: isMobile ? 10 : 14),
                    Text(
                      "Dispense Queue",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: "Refresh queue",
                      child: IconButton(
                        icon: Icon(Icons.refresh_rounded,
                            color: Colors.white, size: isMobile ? 22 : 28),
                        onPressed: () {
                          setState(() {});
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _tryAutoSelectSmallestPending());
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── Session Filter Bar ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Colors.teal.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 14, color: _teal),
                    const SizedBox(width: 6),
                    const Text('Session:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _teal)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildSessionChip('auto', 'Auto (${CampSessionService.getCurrentSession() == 'morning' ? 'Morning' : (CampSessionService.getCurrentSession() == 'evening' ? 'Evening' : 'Night')})'),
                            const SizedBox(width: 6),
                            _buildSessionChip('morning', '☀️ Morning'),
                            const SizedBox(width: 6),
                            _buildSessionChip('evening', '🌅 Evening'),
                            const SizedBox(width: 6),
                            _buildSessionChip('night', '🌙 Night'),
                            const SizedBox(width: 6),
                            _buildSessionChip('all', 'All Sessions'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── List ──────────────────────────────────────────────────────
              Expanded(
                child: ValueListenableBuilder<Box>(
                  valueListenable:
                      Hive.box(LocalStorageService.entriesBox).listenable(),
                  builder: (context, box, _) {
                    final patients = _getSortedQueue();

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _tryAutoSelectSmallestPending();
                    });

                    final pendingList = patients
                        .where((p) =>
                            (p['dispenseStatus'] ?? '')
                                .toString()
                                .toLowerCase() !=
                            'dispensed')
                        .toList();
                    final dispensedList = patients
                        .where((p) =>
                            (p['dispenseStatus'] ?? '')
                                .toString()
                                .toLowerCase() ==
                            'dispensed')
                        .toList();

                    final waitingCount   = pendingList.length;
                    final dispensedCount = dispensedList.length;

                    // For pulse animation only — smallest serial in pending
                    final smallestPendingSerial = pendingList.isNotEmpty
                        ? (pendingList.first['serial']?.toString() ?? '')
                        : '';

                    return Column(
                      children: [
                        // Summary row
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            isMobile ? 12 : 32,
                            isMobile ? 10 : 16,
                            isMobile ? 12 : 32,
                            isMobile ? 8  : 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _summaryCard("Pending",   waitingCount,   _teal,   isMobile),
                              _summaryCard("Dispensed", dispensedCount, _blue,   isMobile),
                              _summaryCard("Total",     patients.length,_purple, isMobile),
                            ],
                          ),
                        ),

                        Expanded(
                          child: patients.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.assignment_turned_in_outlined,
                                          size: isMobile ? 56 : 80,
                                          color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        "No completed prescriptions today",
                                        style: TextStyle(
                                            fontSize: isMobile ? 14 : 18,
                                            color: Colors.grey.shade600),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scroll,
                                  padding: EdgeInsets.fromLTRB(
                                    isMobile ? 8  : 16,
                                    isMobile ? 4  : 8,
                                    isMobile ? 8  : 16,
                                    isMobile ? 16 : 100,
                                  ),
                                  itemCount: patients.length,
                                  itemBuilder: (context, index) {
                                    final patient = patients[index];
                                    final serial  =
                                        patient['serial']?.toString() ??
                                            'unknown';
                                    final name =
                                        patient['patientName'] ??
                                            'Unknown Patient';

                                    final isDispensed =
                                        (patient['dispenseStatus'] ?? '')
                                                .toString()
                                                .toLowerCase() ==
                                            'dispensed';
                                    final isPending = !isDispensed;

                                    // All pending patients are selectable
                                    final isSelectable = isPending;
                                    final isSelected =
                                        patient['serial']?.toString() ==
                                            widget.selectedPatient?['serial']
                                                ?.toString();

                                    // Pulse only on the smallest pending
                                    final isSmallest = isPending &&
                                        serial == smallestPendingSerial;

                                     return Container(
                                       margin: EdgeInsets.symmetric(
                                           vertical: isMobile ? 4 : 6),
                                       decoration: Neumorphic3DStyle.raisedDecoration(
                                          isDark: _isDark,
                                          backgroundColor: isSelected
                                              ? (_isDark ? const Color(0xFF1A3A3A) : Colors.teal.shade50)
                                              : (_isDark ? const Color(0xFF1E293B) : Colors.white),
                                          borderRadius: isMobile ? 12 : 16,
                                          borderColor: isSelected
                                              ? (_isDark ? const Color(0xFF0F766E) : _teal)
                                              : (_isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                          accentColor: _isDark ? const Color(0xFF0F766E) : _teal,
                                          showGlow: isSelected,
                                        ),
                                       child: ListTile(
                                        dense: isMobile,
                                        contentPadding:
                                            EdgeInsets.symmetric(
                                          horizontal: isMobile ? 10 : 16,
                                          vertical:   isMobile ? 2  : 6,
                                        ),
                                        leading: ScaleTransition(
                                          scale: isSmallest
                                              ? Tween(
                                                      begin: 0.95,
                                                      end: 1.15)
                                                  .animate(CurvedAnimation(
                                                      parent: _pulse,
                                                      curve:
                                                          Curves.easeInOut))
                                              : const AlwaysStoppedAnimation(
                                                  1.0),
                                          child: CircleAvatar(
                                            radius: isMobile ? 16 : 20,
                                            backgroundColor: isDispensed
                                                ? Colors.grey.shade500
                                                : _teal,
                                            child: Text(
                                              serial
                                                  .split('-')
                                                  .last
                                                  .padLeft(3, '0'),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    isMobile ? 11 : 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: isMobile ? 13 : 15,
                                            fontWeight: FontWeight.w600,
                                            color: isDispensed
                                                ? Colors.grey.shade500
                                                : (_isDark ? Colors.white : Colors.black87),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          'Serial: $serial',
                                          style: TextStyle(
                                            fontSize: isMobile ? 12 : 14,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? (_isDark ? const Color(0xFF38BDF8) : _teal)
                                                : (isDispensed
                                                    ? Colors.grey.shade500
                                                    : (_isDark ? const Color(0xFF94A3B8) : Colors.black54)),
                                          ),
                                        ),
                                        trailing: Icon(
                                          isDispensed
                                              ? Icons.check_circle_rounded
                                              : Icons.access_time_rounded,
                                          color: isDispensed
                                              ? Colors.grey.shade500
                                              : _amber,
                                          size: isMobile ? 22 : 28,
                                        ),
                                        onTap: isSelectable
                                            ? () {
                                                debugPrint(
                                                    '[PatientList] User tapped: $serial');
                                                widget.onPatientSelected(
                                                    patient);
                                                _scroll.animateTo(
                                                  index *
                                                      (isMobile
                                                          ? 65.0
                                                          : 90.0),
                                                  duration: const Duration(
                                                      milliseconds: 400),
                                                  curve: Curves.easeInOut,
                                                );
                                              }
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryCard(
      String label, int count, Color color, bool isMobile) {
    return Container(
      width:   isMobile ? 68 : 80,
      padding: EdgeInsets.symmetric(vertical: isMobile ? 6 : 8),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 20),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: _isDark ? Colors.black26 : Colors.grey.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 10 : 12)),
          SizedBox(height: isMobile ? 2 : 4),
          Text(count.toString(),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 20 : 24)),
        ],
      ),
    );
  }

  Widget _buildSessionChip(String value, String label) {
    final isSelected = _selectedSessionFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedSessionFilter = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? _teal : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? _teal : Colors.teal.shade200),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.teal.shade900,
          ),
        ),
      ),
    );
  }
}
