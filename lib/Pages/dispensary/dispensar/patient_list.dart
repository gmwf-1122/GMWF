// lib/pages/patient_list.dart
// MOBILE UPDATE:
//   • Removed fixed width: 440 — now fills available space
//   • Summary cards scale down on narrow screens (responsive font + padding)
//   • ListTile compresses on mobile (smaller avatar, tighter padding)
//   • Header adapts font size on narrow screens
//   • Container border-radius reduced on mobile for better fit
//
// FIX: Auto-select no longer jumps away from a valid pending selection
// FIX: Queue filter now includes 'dispensed' status entries (older sync paths)
// FIX: All pending patients are now selectable (not just the smallest)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:another_flushbar/flushbar.dart';

import '../../../services/local_storage_service.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';

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

  late final AnimationController _pulse;
  final ScrollController _scroll = ScrollController();

  final String _todayKey = DateFormat('ddMMyy').format(DateTime.now());

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoSelectSmallestPending();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    _realtimeSub?.cancel();
    super.dispose();
  }

  // ─── Serial number helper ──────────────────────────────────────────────────
  int _extractSerialNumber(Map<String, dynamic> p) {
    final s     = (p['serial'] ?? '000000-999').toString();
    final parts = s.split('-');
    return parts.length > 1 ? int.tryParse(parts.last) ?? 999999 : 999999;
  }

  // ─── Two-group sort ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _getSortedQueue() {
    final all = LocalStorageService.getLocalEntries(widget.branchId)
        .where((e) {
          final dateKey = e['dateKey']?.toString() ?? '';
          final status  = (e['status'] ?? '').toString().toLowerCase();
          // Include 'completed' and 'dispensed' statuses — older sync paths
          // may save entries with status='dispensed' directly.
          return dateKey == _todayKey &&
              (status == 'completed' || status == 'dispensed');
        })
        .toList();

    final pending   = <Map<String, dynamic>>[];
    final dispensed = <Map<String, dynamic>>[];

    for (final e in all) {
      final ds = (e['dispenseStatus'] ?? '').toString().toLowerCase();
      if (ds == 'dispensed') {
        dispensed.add(e);
      } else {
        pending.add(e);
      }
    }

    pending.sort(
        (a, b) => _extractSerialNumber(a).compareTo(_extractSerialNumber(b)));
    dispensed.sort(
        (a, b) => _extractSerialNumber(a).compareTo(_extractSerialNumber(b)));

    return [...pending, ...dispensed];
  }

  // ─── Auto-select smallest pending ─────────────────────────────────────────
  void _tryAutoSelectSmallestPending() {
    if (!mounted) return;
    final queue = _getSortedQueue();
    final pending = queue
        .where((p) =>
            (p['dispenseStatus'] ?? '').toString().toLowerCase() != 'dispensed')
        .toList();

    if (pending.isEmpty) {
      if (widget.selectedPatient != null &&
          (widget.selectedPatient?['serial']?.toString() ?? '').isNotEmpty) {
        widget.onPatientSelected({});
      }
      return;
    }

    final currentSerial = widget.selectedPatient?['serial']?.toString() ?? '';

    // Only auto-select if nothing is currently selected, or the current
    // selection is no longer pending (just got dispensed).
    // Do NOT jump away from a valid pending selection the dispenser chose.
    final currentIsStillPending = pending
        .any((p) => (p['serial']?.toString() ?? '') == currentSerial);

    if (currentSerial.isEmpty || !currentIsStillPending) {
      final smallest = pending.first;
      debugPrint(
          '[PatientList] Auto-selecting: ${smallest['serial']}');
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 20 : 36),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
                  color: _teal,
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

                                    return Card(
                                      elevation: isSelected ? 8 : 2,
                                      color: isSelected
                                          ? Colors.teal.shade50
                                          : Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            isMobile ? 12 : 16),
                                        side: BorderSide(
                                          color: isSelected
                                              ? _teal
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      margin: EdgeInsets.symmetric(
                                          vertical: isMobile ? 4 : 6),
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
                                                : Colors.black87,
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
                                                ? _teal
                                                : (isDispensed
                                                    ? Colors.grey.shade500
                                                    : Colors.black54),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 20),
        border: Border.all(color: color.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
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
}