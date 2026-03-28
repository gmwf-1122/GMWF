// lib/pages/patient_form.dart
// CHANGES IN THIS VERSION:
//   • When daysOfMedicine > 1 a teal banner is shown at the top of the
//     prescription content: "Medicines for X days — total quantities below".
//   • Medicine quantities shown in the dispenser view are the TOTAL for all
//     days (already multiplied by the doctor at save time). A small per-day
//     note is added below each item when quantityPerDay is available.
// All previous fixes (FIX-INV, FIX-QT) are retained unchanged.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import '../../../services/local_storage_service.dart';
import '../../../services/sync_service.dart';
import 'patient_form_helper.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';

class PatientForm extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic> queueEntry;
  final VoidCallback? onDispensed;
  final String? dispenserName;

  const PatientForm({
    super.key,
    required this.branchId,
    required this.queueEntry,
    this.onDispensed,
    this.dispenserName,
  });

  @override
  State<PatientForm> createState() => _PatientFormState();
}

class _PatientFormState extends State<PatientForm> {
  Map<String, dynamic> _data = {};
  String? _gender;
  String? _age;
  String? _branchName;
  bool _isDispensed           = false;
  bool _isPrinting            = false;
  bool _isDispensing          = false;
  bool _loadingBranch         = true;
  bool _isLoadingPrescription = true;

  static const Color _teal = Color(0xFF00695C);

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  // ─── Queue-type normaliser ────────────────────────────────────────────────
  static String _normaliseQueueType(String? raw) {
    final s = (raw ?? '').toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) return 'non-zakat';
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    return 'zakat';
  }

  // ─── Serial resolver ──────────────────────────────────────────────────────
  String get _resolvedSerial {
    for (final f in ['serial', 'id', 'tokenSerial', 'tokenId', 'serialNumber']) {
      final v = widget.queueEntry[f]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    for (final f in ['serial', 'id', 'tokenSerial', 'tokenId']) {
      final v = _data[f]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final embedded = widget.queueEntry['prescription'];
    if (embedded is Map) {
      for (final f in ['serial', 'id']) {
        final v = embedded[f]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  // ─── Queue-type resolver ──────────────────────────────────────────────────
  String get _resolvedQueueType {
    final serial = _resolvedSerial;
    if (serial.isNotEmpty) {
      final raw = Hive.box(LocalStorageService.entriesBox)
          .get('${widget.branchId}-$serial')?['queueType']?.toString();
      if (raw != null && raw.isNotEmpty) return _normaliseQueueType(raw);
    }
    final fromQueue = widget.queueEntry['queueType']?.toString();
    if (fromQueue != null && fromQueue.isNotEmpty) return _normaliseQueueType(fromQueue);
    final fromData = _data['queueType']?.toString();
    if (fromData != null && fromData.isNotEmpty) return _normaliseQueueType(fromData);
    return 'zakat';
  }

  // ─── Days of medicine ─────────────────────────────────────────────────────
  int get _daysOfMedicine {
    // From loaded prescription data
    final fromData = _data['daysOfMedicine'];
    if (fromData is int && fromData > 1) return fromData;
    // From embedded prescription in queue entry
    final embedded = widget.queueEntry['prescription'];
    if (embedded is Map) {
      final d = embedded['daysOfMedicine'];
      if (d is int && d > 1) return d;
    }
    // From top-level entry
    final topLevel = widget.queueEntry['daysOfMedicine'];
    if (topLevel is int && topLevel > 1) return topLevel;
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _loadBranchName();
    _loadPrescription();

    _realtimeSub = RealtimeManager().messageStream.listen((event) {
      final type  = event['event_type'] as String?;
      final data  = event['data'] as Map<String, dynamic>? ?? {};
      if (type == null) return;

      final eventSerial = data['serial']?.toString().trim().toLowerCase();
      final mySerial    = _resolvedSerial.toLowerCase();
      final eventBranch = data['branchId']?.toString().trim().toLowerCase();
      final myBranch    = widget.branchId.toLowerCase().trim();

      if (eventBranch != null && eventBranch != myBranch) return;
      if (eventSerial != null && eventSerial.isNotEmpty &&
          mySerial.isNotEmpty && eventSerial != mySerial) return;

      if (type == RealtimeEvents.savePrescription ||
          type == RealtimeEvents.saveEntry ||
          type == 'dispense_completed') {
        _loadPrescription();
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  // ─── Branch name ──────────────────────────────────────────────────────────
  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).get();
      if (mounted) setState(() {
        _branchName    = doc.exists ? (doc.data()?['name'] ?? 'Free Dispensary') : 'Free Dispensary';
        _loadingBranch = false;
      });
    } catch (_) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
    }
  }

  // ─── Prescription loader ──────────────────────────────────────────────────
  Future<void> _loadPrescription() async {
    if (!mounted) return;
    setState(() => _isLoadingPrescription = true);

    String serial = '';
    for (final f in ['serial', 'id', 'tokenSerial', 'tokenId', 'serialNumber']) {
      final v = widget.queueEntry[f]?.toString().trim() ?? '';
      if (v.isNotEmpty) { serial = v.toLowerCase(); break; }
    }

    String cnic = '';
    for (final f in ['patientCnic', 'cnic', 'guardianCnic', 'patientCNIC', 'guardianCNIC']) {
      final v = (widget.queueEntry[f]?.toString() ?? '')
          .trim().replaceAll('-', '').replaceAll(' ', '').toLowerCase();
      if (v.isNotEmpty && v != '0000000000000') { cnic = v; break; }
    }

    Map<String, dynamic> found = {};

    found = _searchHive(serial, cnic);
    if (found.isEmpty) {
      final entryKey = '${widget.branchId}-$serial';
      final entry    = Hive.box(LocalStorageService.entriesBox).get(entryKey);
      final embedded = (entry is Map) ? entry['prescription'] : null;
      if (embedded is Map && embedded.isNotEmpty) {
        found = Map<String, dynamic>.from(embedded);
      }
    }
    if (found.isEmpty && serial.isNotEmpty && cnic.isNotEmpty) {
      found = await _fetchFromPrescriptionsByCnic(serial, cnic);
      if (found.isNotEmpty) await LocalStorageService.saveLocalPrescription(found);
    }
    if (found.isEmpty && serial.isNotEmpty) {
      found = await _fetchFromPrescriptionsScanAll(serial);
      if (found.isNotEmpty) await LocalStorageService.saveLocalPrescription(found);
    }
    if (found.isEmpty && serial.isNotEmpty) {
      found = await _fetchFromSerialsEmbedded(serial);
      if (found.isNotEmpty) await LocalStorageService.saveLocalPrescription(found);
    }
    if (found.isEmpty) found = _searchHive(serial, cnic);

    final vitals  = (widget.queueEntry['vitals'] as Map<String, dynamic>?) ?? {};
    final gender  = found['patientGender']?.toString() ??
        widget.queueEntry['patientGender']?.toString() ??
        vitals['gender']?.toString() ?? 'N/A';
    final age     = found['patientAge']?.toString() ??
        widget.queueEntry['patientAge']?.toString() ??
        vitals['age']?.toString() ?? 'N/A';

    final dispenseStatus = (widget.queueEntry['dispenseStatus'] ?? '').toString().toLowerCase();
    final patientName = found['patientName']?.toString() ??
        widget.queueEntry['patientName']?.toString() ?? 'Unknown Patient';
    if (found.isNotEmpty) found['patientName'] = patientName;

    if (mounted) setState(() {
      _data                  = found;
      _gender                = gender;
      _age                   = age;
      _isDispensed           = dispenseStatus == 'dispensed';
      _isLoadingPrescription = false;
    });
  }

  Map<String, dynamic> _searchHive(String serial, String cnic) {
    final box = Hive.box(LocalStorageService.prescriptionsBox);
    if (cnic.isNotEmpty && serial.isNotEmpty) {
      final v = box.get('${cnic}_$serial');
      if (v is Map && v.isNotEmpty) return Map<String, dynamic>.from(v);
    }
    if (serial.isNotEmpty) {
      final v = box.get(serial);
      if (v is Map && v.isNotEmpty) return Map<String, dynamic>.from(v);
    }
    if (serial.isNotEmpty) {
      for (final key in box.keys) {
        if (key is String && key.toLowerCase().endsWith('_$serial')) {
          final v = box.get(key);
          if (v is Map && v.isNotEmpty) return Map<String, dynamic>.from(v);
        }
      }
    }
    if (serial.isNotEmpty) {
      for (final key in box.keys) {
        if (key is String && key.toLowerCase().contains(serial)) {
          final v = box.get(key);
          if (v is Map && v.isNotEmpty) {
            final m = Map<String, dynamic>.from(v);
            if (m['serial']?.toString().trim().toLowerCase() == serial) return m;
          }
        }
      }
    }
    return {};
  }

  Future<Map<String, dynamic>> _fetchFromPrescriptionsByCnic(String serial, String cnic) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId)
          .collection('prescriptions').doc(cnic)
          .collection('prescriptions').doc(serial).get();
      if (snap.exists && snap.data() != null) {
        final d = Map<String, dynamic>.from(snap.data()!);
        d['id'] = snap.id; d['serial'] = snap.id;
        return d;
      }
    } catch (e) { debugPrint('[PatientForm] Firestore prescriptions/{cnic} error: $e'); }
    return {};
  }

  Future<Map<String, dynamic>> _fetchFromPrescriptionsScanAll(String serial) async {
    try {
      final cnicDocs = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId)
          .collection('prescriptions').get();
      for (final cnicDoc in cnicDocs.docs) {
        final prescSnap = await cnicDoc.reference.collection('prescriptions').doc(serial).get();
        if (prescSnap.exists && prescSnap.data() != null) {
          final d = Map<String, dynamic>.from(prescSnap.data()!);
          d['id'] = prescSnap.id; d['serial'] = prescSnap.id;
          d['patientCnic'] = cnicDoc.id; d['cnic'] = cnicDoc.id;
          return d;
        }
      }
    } catch (e) { debugPrint('[PatientForm] Firestore scan-all error: $e'); }
    return {};
  }

  Future<Map<String, dynamic>> _fetchFromSerialsEmbedded(String serial) async {
    try {
      final dateKey = serial.contains('-') ? serial.split('-')[0] : '';
      if (dateKey.isEmpty) return {};
      for (final type in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await FirebaseFirestore.instance
            .collection('branches').doc(widget.branchId)
            .collection('serials').doc(dateKey)
            .collection(type).doc(serial).get();
        if (snap.exists && snap.data() != null) {
          final d = Map<String, dynamic>.from(snap.data()!);
          d['queueType'] = type;
          final embedded = d['prescription'];
          if (embedded is Map && embedded.isNotEmpty) {
            final result = Map<String, dynamic>.from(embedded);
            result['queueType'] = type;
            return result;
          }
          if (d.containsKey('prescriptions')) return d;
        }
      }
    } catch (e) { debugPrint('[PatientForm] Firestore serials embedded error: $e'); }
    return {};
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  bool get _hasPrintableContent {
    final lab = (_data['labResults']    ?? []) as List;
    final rx  = (_data['prescriptions'] ?? []) as List;
    return lab.isNotEmpty || rx.isNotEmpty;
  }

  String _getMedAbbrev(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('syrup'))     return 'syp.';
    if (t.contains('injection')) return 'inj.';
    if (t.contains('tablet'))    return 'tab.';
    if (t.contains('capsule'))   return 'cap.';
    if (t.contains('drip'))      return 'drip.';
    if (t.contains('syringe'))   return 'syr.';
    return '';
  }

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  // ─── Print ────────────────────────────────────────────────────────────────
  Future<void> _printOnly() async {
    if (!_hasPrintableContent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nothing to print'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isPrinting = true);
    try {
      final pdfBytes = await PatientFormHelper.generatePrintSlip(
          data: _data, branchName: _branchName ?? 'Free Dispensary');
      await Printing.layoutPdf(
          onLayout: (_) => pdfBytes,
          name: 'Slip_${_resolvedSerial.isNotEmpty ? _resolvedSerial : 'unknown'}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  // ─── Inventory deduction ──────────────────────────────────────────────────
  // Tablets / capsules / syrups: deduct quantity × days (N days' supply).
  // Injections / drips / nebulisation: always × 1 — one-time use only.
  static bool _isInjectableType(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('injection') || t.contains('inj') ||
        t.contains('drip') || t.contains('syringe') || t.contains('nebulization');
  }

  Future<void> _deductInventoryLocally(
      String branchId, String serial, List<dynamic> medicines, int days) async {
    for (final med in medicines) {
      if (med is! Map) continue;
      final medMap     = Map<String, dynamic>.from(med);
      final medicineId = (medMap['inventoryId'] ??
              medMap['medicineId'] ?? medMap['id'] ?? '').toString().trim();
      final perDayRaw  = medMap['quantity'] ?? medMap['qty'] ?? 0;
      final perDay     = perDayRaw is num
          ? perDayRaw.toDouble()
          : double.tryParse(perDayRaw.toString()) ?? 0.0;
      if (medicineId.isEmpty || perDay <= 0) continue;

      // Injections/drips always × 1; oral/syrup × days
      final multiplier = _isInjectableType(medMap['type']?.toString()) ? 1 : days;
      final qtyNum     = perDay * multiplier;

      debugPrint('[PatientForm] deduct $medicineId: ${perDay}/day × $multiplier = $qtyNum');

      try {
        final stockBox = Hive.box('stock_items');
        final existing = stockBox.get(medicineId);
        if (existing is Map) {
          final updated = Map<String, dynamic>.from(existing);
          final current = (updated['quantity'] as num?)?.toDouble() ?? 0.0;
          updated['quantity'] = (current - qtyNum).clamp(0.0, double.infinity);
          stockBox.put(medicineId, updated);
          debugPrint('[PatientForm] Hive stock $medicineId: $current → ${updated['quantity']}');
        }
      } catch (e) {
        debugPrint('[PatientForm] Hive stock decrement failed $medicineId: $e');
      }

      bool firestoreWritten = false;
      try {
        final conn   = await Connectivity().checkConnectivity();
        final online = !conn.contains(ConnectivityResult.none);
        if (online) {
          await FirebaseFirestore.instance
              .collection('branches').doc(branchId)
              .collection('inventory').doc(medicineId)
              .update({'quantity': FieldValue.increment(-qtyNum)});
          firestoreWritten = true;
          debugPrint('[PatientForm] ✅ Firestore inventory $medicineId -= $qtyNum');
        }
      } catch (e) {
        debugPrint('[PatientForm] Firestore inventory update failed: $e');
      }

      if (!firestoreWritten) {
        await LocalStorageService.enqueueSync({
          'type': 'update_inventory', 'branchId': branchId,
          'medicineId': medicineId, 'delta': -qtyNum, 'serial': serial,
          'data': {'medicineId': medicineId, 'medicineName': medMap['name'] ?? '',
              'delta': -qtyNum, 'serial': serial},
        });
        debugPrint('[PatientForm] 📥 Queued inventory deduction: $medicineId -= $qtyNum');
      }
    }
  }

  // ─── Dispense ─────────────────────────────────────────────────────────────
  Future<void> _dispenseOnly() async {
    if (_isDispensed) return;

    final days = _daysOfMedicine;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Dispense'),
        content: Text(days > 1
            ? 'Give $days days\' supply of each medicine (tablets/capsules/syrups ×$days). '
              'Injections and drips are given once only.\n\nThis cannot be undone.'
            : 'Mark this prescription as dispensed? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            child: const Text('Dispense', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isDispensing = true);
    try {
      final serial = _resolvedSerial;
      if (serial.isEmpty) throw Exception(
          'Missing serial — queueEntry keys: ${widget.queueEntry.keys.toList()}');

      final queueType     = _resolvedQueueType;
      final now           = DateTime.now();
      final dateKey       = DateFormat('ddMMyy').format(now);
      final nowIso        = now.toIso8601String();
      final dispenserName = widget.dispenserName ?? 'Unknown Dispenser';

      final doctorName = _firstNonEmpty([
        _data['doctorName'], _data['prescribedBy'], _data['updatedBy'],
        widget.queueEntry['doctorName'], 'Unknown',
      ]);
      final tokenBy = _firstNonEmpty([
        widget.queueEntry['createdByName'], widget.queueEntry['tokenBy'],
        widget.queueEntry['createdBy'], 'Unknown',
      ]);

      final minimalUpdate = {
        'dispenseStatus': 'dispensed',
        'dispensedAt':    nowIso,
        'dispensedBy':    dispenserName,
        'dispenserName':  dispenserName,
        'serial':         serial,
        'dateKey':        dateKey,
        'queueType':      queueType,
        'branchId':       widget.branchId,
        'daysOfMedicine': days,
      };

      final entryKey     = '${widget.branchId}-$serial';
      final currentEntry = Hive.box(LocalStorageService.entriesBox).get(entryKey);
      if (currentEntry != null) {
        final updated = Map<String, dynamic>.from(currentEntry)..addAll(minimalUpdate);
        await Hive.box(LocalStorageService.entriesBox).put(entryKey, updated);
      }

      final dispensaryRecord = {
        ...Map<String, dynamic>.from(widget.queueEntry),
        ...Map<String, dynamic>.from(_data),
        'branchId':       widget.branchId,
        'serial':         serial,
        'dateKey':        dateKey,
        'date':           dateKey,
        'queueType':      queueType,
        'createdAt':      nowIso,
        'dispenseStatus': 'dispensed',
        'dispensedAt':    nowIso,
        'dispensedBy':    dispenserName,
        'dispenserName':  dispenserName,
        'doctorName':     doctorName,
        'prescribedBy':   doctorName,
        'tokenBy':        tokenBy,
        'createdByName':  tokenBy,
        'daysOfMedicine': days,
      };
      await Hive.box(LocalStorageService.dispensaryBox)
          .put('${widget.branchId}_${dateKey}_$serial', dispensaryRecord);

      final medicines = (_data['prescriptions'] as List?)
          ?.where((m) => m is Map &&
              (m['inventoryId'] != null || m['medicineId'] != null || m['id'] != null))
          .toList() ?? [];
      if (medicines.isNotEmpty) {
        // Pass days so tab/cap/syrup are deducted × days; injectables always × 1
        await _deductInventoryLocally(widget.branchId, serial, medicines, days);
      }

      RealtimeManager().sendMessage(RealtimeEvents.payload(
        type: 'dispense_completed',
        data: {
          'branchId': widget.branchId,
          'serial':   serial,
          'dateKey':  dateKey,
          ...minimalUpdate,
          if (medicines.isNotEmpty) 'medicines': medicines,
        },
      ));

      try {
        final branchRef = FirebaseFirestore.instance
            .collection('branches').doc(widget.branchId);
        await branchRef.collection('dispensary').doc(dateKey)
            .collection(dateKey).doc(serial)
            .set(dispensaryRecord, SetOptions(merge: true));
        await branchRef.collection('serials').doc(dateKey)
            .collection(queueType).doc(serial)
            .set(minimalUpdate, SetOptions(merge: true));
      } catch (e) {
        await LocalStorageService.enqueueSync({
          'type': 'save_dispensary_record', 'branchId': widget.branchId,
          'dateKey': dateKey, 'serial': serial, 'data': dispensaryRecord,
        });
      }

      await LocalStorageService.enqueueSync({
        'type': 'update_serial_status', 'branchId': widget.branchId,
        'dateKey': dateKey, 'queueType': queueType, 'serial': serial,
        'data': minimalUpdate,
      });

      SyncService().triggerUpload();

      if (mounted) setState(() => _isDispensed = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(days > 1
              ? 'Dispensed $days-day supply successfully'
              : 'Dispensed successfully'),
          backgroundColor: Colors.green));
      widget.onDispensed?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to dispense: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isDispensing = false);
    }
  }

  // ─── UI helpers ───────────────────────────────────────────────────────────
  Widget _sectionTitle(String title, IconData icon, {bool isMobile = false}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 12),
        child: Row(children: [
          Icon(icon, color: _teal, size: isMobile ? 16 : 20),
          SizedBox(width: isMobile ? 6 : 10),
          Text(title, style: PatientFormHelper.robotoBold(size: isMobile ? 14 : 18, color: _teal)),
        ]),
      );

  Widget _linedList(List items, {bool isLab = false, bool isMobile = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (isLab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(item['name']?.toString() ?? '',
              style: PatientFormHelper.robotoBold(size: isMobile ? 13 : 16)),
        )).toList(),
      );
    }

    final days = _daysOfMedicine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        final abbrev      = _getMedAbbrev(item['type']);
        final rawName     = item['name']?.toString() ?? '';
        final displayName = '$abbrev $rawName'.trim();
        final urduLine    = PatientFormHelper.buildUrduDosageLine(item);
        final mealUrdu    = PatientFormHelper.getMealUrdu(item['meal']?.toString() ?? '');
        final isInj       = _isInjectableType(item['type']?.toString());
        // Per-day quantity as prescribed by the doctor
        final perDayQty   = ((item['quantity'] ?? 1) as num).toInt();
        // Total given at dispense time (injections/drips always ×1)
        final totalQty    = isInj ? perDayQty : perDayQty * days;

        return Container(
          padding: EdgeInsets.only(
              top: isMobile ? 4 : 6, bottom: isMobile ? 10 : 12),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100, width: 1))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: PatientFormHelper.robotoBold(
                            size: isMobile ? 13 : 16)),
                    const SizedBox(height: 2),
                    // For multi-day non-injectable: show per-day timing and
                    // a teal note saying how many days total are being dispensed.
                    if (days > 1 && !isInj)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _teal.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: _teal.withOpacity(0.25)),
                        ),
                        child: Text(
                          '$perDayQty/day · $days days · give $totalQty total',
                          style: TextStyle(
                              fontSize: isMobile ? 10 : 11,
                              color: _teal.withOpacity(0.9),
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Urdu dosage line shows per-day instruction unchanged
                  if (urduLine.isNotEmpty)
                    Text(
                      urduLine,
                      textAlign: TextAlign.right,
                      textDirection: ui.TextDirection.rtl,
                      style: PatientFormHelper.nooriRegular(
                              size: isMobile ? 14 : 16,
                              color: PatientFormHelper.textBlack)
                          .copyWith(height: 1.7),
                    ),
                  if (mealUrdu.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        mealUrdu,
                        textAlign: TextAlign.right,
                        textDirection: ui.TextDirection.rtl,
                        style: PatientFormHelper.nooriRegular(
                                size: isMobile ? 12 : 14,
                                color: Colors.grey.shade600)
                            .copyWith(height: 1.7),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }

  // ─── "Medicines for X days" banner ────────────────────────────────────────
  Widget _buildDaysBanner({required bool isMobile}) {
    final days = _daysOfMedicine;
    if (days <= 1) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16, vertical: isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: _teal,
        borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
      ),
      child: Row(children: [
        Icon(Icons.calendar_month_rounded,
            color: Colors.white, size: isMobile ? 18 : 22),
        SizedBox(width: isMobile ? 8 : 12),
        Expanded(
          child: Text(
            'Medicines for $days days\n'
            'Dosage below is per day — give $days days\' supply of each tablet/capsule/syrup',
            style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w600,
                height: 1.4),
          ),
        ),
      ]),
    );
  }

  // ─── Header / footer ──────────────────────────────────────────────────────
  Widget _buildHeader({required bool isMobile}) => ClipRRect(
    borderRadius: BorderRadius.vertical(top: Radius.circular(isMobile ? 12 : 20)),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      color: _teal,
      child: isMobile
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Image.asset('assets/logo/gmwf.png', width: 48, height: 48),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Padding(padding: const EdgeInsets.only(bottom: 3),
                    child: Text('ہو الشافی',
                        style: PatientFormHelper.nooriRegular(size: 17, color: Colors.white))),
                Text('Gulzar Madina Welfare Foundation',
                    style: PatientFormHelper.robotoBold(size: 10, color: Colors.white),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('Free Dispensary',
                    style: PatientFormHelper.robotoBold(size: 10, color: Colors.white70)),
              ])),
              const SizedBox(width: 8),
              Image.asset('assets/images/moon.png', width: 48, height: 48),
            ])
          : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Image.asset('assets/logo/gmwf.png', width: 100, height: 100),
              Expanded(child: Column(children: [
                Text('ہو الشافی',
                    style: PatientFormHelper.nooriRegular(size: 32, color: Colors.white)),
                Text('Gulzar Madina Welfare Foundation',
                    style: PatientFormHelper.robotoBold(size: 26, color: Colors.white)),
                Text('Free Dispensary',
                    style: PatientFormHelper.robotoBold(size: 24, color: Colors.white)),
              ])),
              Image.asset('assets/images/moon.png', width: 90, height: 90),
            ]),
    ),
  );

  Widget _buildFooter({required bool isMobile}) => ClipRRect(
    borderRadius: BorderRadius.vertical(bottom: Radius.circular(isMobile ? 12 : 20)),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      color: _teal,
      child: Center(child: Column(children: [
        Text('Gulzar Madina ${_branchName ?? ''}',
            style: TextStyle(fontSize: isMobile ? 12 : 16,
                fontWeight: FontWeight.bold, color: Colors.white)),
        Text('Website: gulzarmadina.com',
            style: TextStyle(fontSize: isMobile ? 11 : 14, color: Colors.white70)),
      ])),
    ),
  );

  Widget _buildActionBar({required bool isMobile}) {
    final days    = _daysOfMedicine;
    final printBtn = ElevatedButton.icon(
      onPressed: _hasPrintableContent && !_isPrinting ? _printOnly : null,
      icon: _isPrinting
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.print, color: Colors.white),
      label: Text(_isPrinting ? 'Printing...' : 'Print Slip',
          style: TextStyle(color: Colors.white,
              fontSize: isMobile ? 13 : 16, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _hasPrintableContent ? _teal : Colors.grey.shade400,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: isMobile ? 14 : 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 8),
    );

    final dispenseLabel = _isDispensed
        ? 'Already Dispensed'
        : _isDispensing
            ? 'Dispensing...'
            : days > 1
                ? 'Dispense ($days days\' supply)'
                : 'Dispense Medicine';

    final dispenseBtn = ElevatedButton.icon(
      onPressed: _isDispensed || _isDispensing ? null : _dispenseOnly,
      icon: _isDispensing
          ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_circle, color: Colors.white),
      label: Text(dispenseLabel,
          style: TextStyle(color: Colors.white,
              fontSize: isMobile ? 13 : 16, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isDispensed ? Colors.grey.shade600 : _teal,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40, vertical: isMobile ? 14 : 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 8),
    );

    return Container(
      width: double.infinity, color: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 20, vertical: isMobile ? 12 : 20),
      child: isMobile
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: double.infinity, child: printBtn),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: dispenseBtn),
            ])
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              printBtn, const SizedBox(width: 32), dispenseBtn,
            ]),
    );
  }

  Widget _buildContent({required bool isMobile}) {
    final prescriptions        = (_data['prescriptions'] ?? []) as List;
    final labTests             = (_data['labResults']    ?? []) as List;
    final diagnosis            = _data['diagnosis']?.toString() ?? '';
    final patientName          = _data['patientName'] ?? 'Unknown';
    final inventoryMeds        = prescriptions.where((m) => m['inventoryId'] != null && !PatientFormHelper.isInjectable(m)).toList();
    final inventoryInjectables = prescriptions.where((m) => m['inventoryId'] != null && PatientFormHelper.isInjectable(m)).toList();
    final customMeds           = prescriptions.where((m) => m['inventoryId'] == null && !PatientFormHelper.isInjectable(m)).toList();
    final customInjectables    = prescriptions.where((m) => m['inventoryId'] == null && PatientFormHelper.isInjectable(m)).toList();
    final basePadding          = isMobile ? 16.0 : 40.0;

    Widget patientInfo = Wrap(spacing: 6, runSpacing: 4, children: [
      RichText(text: TextSpan(style: PatientFormHelper.robotoBold(size: isMobile ? 13 : 18), children: [
        TextSpan(text: 'Patient: ', style: PatientFormHelper.robotoBold(color: _teal, size: isMobile ? 13 : 18)),
        TextSpan(text: patientName, style: PatientFormHelper.robotoBold(size: isMobile ? 14 : 20)),
      ])),
      RichText(text: TextSpan(style: PatientFormHelper.robotoBold(size: isMobile ? 13 : 18), children: [
        TextSpan(text: 'Gender: ', style: PatientFormHelper.robotoBold(color: _teal, size: isMobile ? 13 : 18)),
        TextSpan(text: _gender ?? 'N/A', style: PatientFormHelper.robotoBold(size: isMobile ? 14 : 20)),
      ])),
      RichText(text: TextSpan(style: PatientFormHelper.robotoBold(size: isMobile ? 13 : 18), children: [
        TextSpan(text: 'Age: ', style: PatientFormHelper.robotoBold(color: _teal, size: isMobile ? 13 : 18)),
        TextSpan(text: _age ?? 'N/A', style: PatientFormHelper.robotoBold(size: isMobile ? 14 : 20)),
      ])),
    ]);

    Widget medicineBody = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Days banner
      _buildDaysBanner(isMobile: isMobile),
      patientInfo,
      if (diagnosis.isNotEmpty) ...[
        SizedBox(height: isMobile ? 10 : 20),
        _sectionTitle('Diagnosis', Icons.medical_services, isMobile: isMobile),
        Text(diagnosis, style: PatientFormHelper.robotoRegular(size: isMobile ? 13 : 16)),
      ],
      if (isMobile && labTests.isNotEmpty) ...[
        const SizedBox(height: 10),
        _sectionTitle('Lab Tests', Icons.biotech, isMobile: true),
        _linedList(labTests, isLab: true, isMobile: true),
        Divider(color: Colors.grey.shade200, height: 20),
      ],
      if (inventoryMeds.isNotEmpty) ...[
        SizedBox(height: isMobile ? 10 : 20),
        _sectionTitle('Inventory Medicines', Icons.medication, isMobile: isMobile),
        _linedList(inventoryMeds, isMobile: isMobile),
      ],
      if (inventoryInjectables.isNotEmpty) ...[
        SizedBox(height: isMobile ? 10 : 20),
        _sectionTitle('Inventory Injectables', Icons.vaccines, isMobile: isMobile),
        _linedList(inventoryInjectables, isMobile: isMobile),
      ],
      if (customMeds.isNotEmpty) ...[
        SizedBox(height: isMobile ? 10 : 20),
        _sectionTitle('Custom Medicines', Icons.medication_liquid, isMobile: isMobile),
        _linedList(customMeds, isMobile: isMobile),
      ],
      if (customInjectables.isNotEmpty) ...[
        SizedBox(height: isMobile ? 10 : 20),
        _sectionTitle('Custom Injectables', Icons.vaccines, isMobile: isMobile),
        _linedList(customInjectables, isMobile: isMobile),
      ],
    ]);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(basePadding),
      child: isMobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [medicineBody, const SizedBox(height: 20)])
          : IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (labTests.isNotEmpty) ...[
                Expanded(flex: 2, child: _buildLabCol(labTests)),
                Container(width: 1, color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(horizontal: 20)),
              ],
              Expanded(flex: 8, child: medicineBody),
            ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile    = screenWidth < 700;

    if (_isLoadingPrescription) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: _teal),
        SizedBox(height: 16),
        Text('Loading prescription...', style: TextStyle(color: _teal)),
      ]));
    }

    if (_data.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.hourglass_empty, size: 80, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('No prescription found yet',
            style: TextStyle(color: Colors.grey, fontSize: 18)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _loadPrescription, icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(backgroundColor: _teal)),
      ]));
    }

    final bottomBarHeight = isMobile ? 140.0 : 120.0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(children: [
        SingleChildScrollView(
          padding: EdgeInsets.only(
              left: isMobile ? 8 : 16, right: isMobile ? 8 : 16,
              top: isMobile ? 8 : 16, bottom: bottomBarHeight + 16),
          child: Center(child: Container(
            constraints: isMobile ? const BoxConstraints() : const BoxConstraints(maxWidth: 850),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isMobile ? 12 : 20),
              boxShadow: [BoxShadow(
                  color: Colors.grey.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))]),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _buildHeader(isMobile: isMobile),
              _buildContent(isMobile: isMobile),
              _buildFooter(isMobile: isMobile),
            ]),
          )),
        ),
        Align(alignment: Alignment.bottomCenter, child: _buildActionBar(isMobile: isMobile)),
      ]),
    );
  }

  Widget _buildLabCol(List labTests) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Lab Tests', Icons.biotech),
      ...labTests.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(item['name']?.toString() ?? '',
              style: PatientFormHelper.robotoBold(size: 16)))),
    ],
  );
}