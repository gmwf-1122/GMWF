// lib/pages/patient_list.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:another_flushbar/flushbar.dart';

import '../services/local_storage_service.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

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
  static const Color _teal = Color(0xFF00695C);
  static const Color _amber = Color(0xFFFFA000);
  static const Color _blue = Color(0xFF1976D2);
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
      final myBranch = widget.branchId.toLowerCase().trim();
      if (eventBranch != null && eventBranch != myBranch) return;

      if (type == RealtimeEvents.savePrescription ||
          type == RealtimeEvents.saveEntry ||
          type == 'dispense_completed') {
        setState(() {});
        // Re-evaluate auto-selection after queue changes
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
    final s = (p['serial'] ?? '000000-999').toString();
    final parts = s.split('-');
    return parts.length > 1 ? int.tryParse(parts.last) ?? 999999 : 999999;
  }

  // ─── Strict two-group sort for DISPENSER queue ─────────────────────────────
  // Group 1 (top):    status == 'completed' AND dispenseStatus != 'dispensed'
  //                   → sorted ascending by serial (smallest on top)
  // Group 2 (bottom): dispenseStatus == 'dispensed'
  //                   → sorted ascending by serial (smallest on top = earliest dispensed)
  //
  // Only the SMALLEST pending (group 1) entry is auto-selected and selectable.
  // Dispensed entries are NEVER selectable.
  List<Map<String, dynamic>> _getSortedQueue() {
    final all = LocalStorageService.getLocalEntries(widget.branchId)
        .where((e) {
          final dateKey = e['dateKey']?.toString() ?? '';
          final status = (e['status'] ?? '').toString().toLowerCase();
          // Show today's entries that have a completed prescription (ready to dispense)
          return dateKey == _todayKey && status == 'completed';
        })
        .toList();

    final pending = <Map<String, dynamic>>[];
    final dispensed = <Map<String, dynamic>>[];

    for (final e in all) {
      final ds = (e['dispenseStatus'] ?? '').toString().toLowerCase();
      if (ds == 'dispensed') {
        dispensed.add(e);
      } else {
        pending.add(e);
      }
    }

    // Ascending serial in both groups
    pending.sort((a, b) => _extractSerialNumber(a).compareTo(_extractSerialNumber(b)));
    dispensed.sort((a, b) => _extractSerialNumber(a).compareTo(_extractSerialNumber(b)));

    return [...pending, ...dispensed];
  }

  // ─── Auto-select: always force the smallest PENDING (not yet dispensed) ───
  void _tryAutoSelectSmallestPending() {
    if (!mounted) return;
    final queue = _getSortedQueue();
    final pending = queue
        .where((p) =>
            (p['dispenseStatus'] ?? '').toString().toLowerCase() != 'dispensed')
        .toList();

    if (pending.isEmpty) {
      // Nothing left to dispense — clear selection
      if (widget.selectedPatient != null &&
          (widget.selectedPatient?['serial']?.toString() ?? '').isNotEmpty) {
        widget.onPatientSelected({});
      }
      return;
    }

    // Already sorted ascending; first == smallest serial
    final smallest = pending.first;
    final smallestSerial = smallest['serial']?.toString() ?? '';

    final currentSerial =
        widget.selectedPatient?['serial']?.toString() ?? '';
    final currentIsPending = pending
        .any((p) => (p['serial']?.toString() ?? '') == currentSerial);

    if (!currentIsPending || currentSerial != smallestSerial) {
      debugPrint('[PatientList] Auto-selecting smallest pending: $smallestSerial');
      widget.onPatientSelected(smallest);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 440,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
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
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            decoration: const BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_pharmacy, color: Colors.white, size: 30),
                const SizedBox(width: 14),
                const Text(
                  "Dispense Queue",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Tooltip(
                  message: "Refresh queue",
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 28),
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

          // ── List ────────────────────────────────────────────────────────────
          Expanded(
            child: ValueListenableBuilder<Box>(
              valueListenable:
                  Hive.box(LocalStorageService.entriesBox).listenable(),
              builder: (context, box, _) {
                final patients = _getSortedQueue();

                // After every rebuild, enforce auto-selection
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _tryAutoSelectSmallestPending();
                });

                final pendingList = patients
                    .where((p) =>
                        (p['dispenseStatus'] ?? '').toString().toLowerCase() !=
                        'dispensed')
                    .toList();
                final dispensedList = patients
                    .where((p) =>
                        (p['dispenseStatus'] ?? '').toString().toLowerCase() ==
                        'dispensed')
                    .toList();

                final waitingCount = pendingList.length;
                final dispensedCount = dispensedList.length;

                // The ONLY selectable patient is the smallest pending
                final smallestPendingSerial = pendingList.isNotEmpty
                    ? (pendingList.first['serial']?.toString() ?? '')
                    : '';

                return Column(
                  children: [
                    // Summary row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _summaryCard("Pending", waitingCount, _teal),
                          _summaryCard("Dispensed", dispensedCount, _blue),
                          _summaryCard(
                              "Total", patients.length, _purple),
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
                                      size: 80, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    "No completed prescriptions today",
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey.shade600),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 100),
                              itemCount: patients.length,
                              itemBuilder: (context, index) {
                                final patient = patients[index];
                                final serial =
                                    patient['serial']?.toString() ?? 'unknown';
                                final name = patient['patientName'] ??
                                    'Unknown Patient';

                                final isDispensed =
                                    (patient['dispenseStatus'] ?? '')
                                            .toString()
                                            .toLowerCase() ==
                                        'dispensed';
                                final isPending = !isDispensed;

                                // Only the smallest pending is selectable
                                final isSelectable = isPending &&
                                    serial == smallestPendingSerial;

                                final isSelected =
                                    patient['serial']?.toString() ==
                                        widget.selectedPatient?['serial']
                                            ?.toString();

                                return Card(
                                  elevation: isSelected ? 8 : 2,
                                  color: isSelected
                                      ? Colors.teal.shade50
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: isSelected
                                          ? _teal
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 6),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 6),
                                    leading: ScaleTransition(
                                      scale: isPending &&
                                              serial == smallestPendingSerial
                                          ? Tween(begin: 0.95, end: 1.15)
                                              .animate(CurvedAnimation(
                                                  parent: _pulse,
                                                  curve: Curves.easeInOut))
                                          : const AlwaysStoppedAnimation(1.0),
                                      child: CircleAvatar(
                                        radius: 20,
                                        backgroundColor: isDispensed
                                            ? Colors.grey.shade500
                                            : _teal,
                                        child: Text(
                                          serial
                                              .split('-')
                                              .last
                                              .padLeft(3, '0'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 15,
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
                                        fontSize: 14,
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
                                      size: 28,
                                    ),
                                    // Tap only allowed on smallest pending
                                    onTap: isSelectable
                                        ? () {
                                            debugPrint(
                                                '[PatientList] User tapped: $serial');
                                            widget.onPatientSelected(patient);
                                            _scroll.animateTo(
                                              index * 90.0,
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
  }

  Widget _summaryCard(String label, int count, Color color) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
                  fontSize: 12)),
          const SizedBox(height: 4),
          Text(count.toString(),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 24)),
        ],
      ),
    );
  }
}