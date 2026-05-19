// lib/pages/dispensary/dispensar/patient_form.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/sync_service.dart';
import 'patient_form_helper.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';
import 'package:gmwf/theme/app_theme.dart';
import 'package:gmwf/theme/role_theme_provider.dart';

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
  bool _isDispensed = false;
  bool _isPrinting = false;
  bool _isDispensing = false;
  bool _loadingBranch = true;
  bool _isLoadingPrescription = true;
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

  int get _daysOfMedicine {
    final fromData = _data['daysOfMedicine'];
    if (fromData is int && fromData >= 1) return fromData;
    final embedded = widget.queueEntry['prescription'];
    if (embedded is Map) {
      final d = embedded['daysOfMedicine'];
      if (d is int && d >= 1) return d;
    }
    final topLevel = widget.queueEntry['daysOfMedicine'];
    if (topLevel is int && topLevel >= 1) return topLevel;
    return 1;
  }

  // ─── Suggested days (paid at token desk) ──────────────────────────────────
  int get _suggestedDays {
    final s = widget.queueEntry['suggestedDays'];
    if (s is int && s >= 1) return s;
    
    final serial = _resolvedSerial;
    if (serial.isNotEmpty) {
      final entryRaw = Hive.box(LocalStorageService.entriesBox).get('${widget.branchId}-$serial');
      if (entryRaw != null) {
        final entry = Map<String, dynamic>.from(entryRaw);
        final sd = entry['suggestedDays'];
        if (sd is int && sd >= 1) return sd;
      }
    }
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _loadBranchName();
    _loadPrescription();
    _realtimeSub = RealtimeManager().messageStream.listen((event) {
      final type = event['event_type'] as String?;
      final data = event['data'] as Map<String, dynamic>? ?? {};
      if (type == null) return;
      final eventSerial = data['serial']?.toString().trim().toLowerCase();
      final mySerial = _resolvedSerial.toLowerCase();
      final eventBranch = data['branchId']?.toString().trim().toLowerCase();
      final myBranch = widget.branchId.toLowerCase().trim();
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
        _branchName = doc.exists ? (doc.data()?['name'] ?? 'Free Dispensary') : 'Free Dispensary';
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
      final entry = Hive.box(LocalStorageService.entriesBox).get(entryKey);
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
    final vitals = (widget.queueEntry['vitals'] as Map<String, dynamic>?) ?? {};
    final gender = found['patientGender']?.toString() ??
        widget.queueEntry['patientGender']?.toString() ??
        vitals['gender']?.toString() ?? 'N/A';
    final age = found['patientAge']?.toString() ??
        widget.queueEntry['patientAge']?.toString() ??
        vitals['age']?.toString() ?? 'N/A';
    final dispenseStatus = (widget.queueEntry['dispenseStatus'] ?? '').toString().toLowerCase();
    final patientName = found['patientName']?.toString() ??
        widget.queueEntry['patientName']?.toString() ?? 'Unknown Patient';
    if (found.isNotEmpty) found['patientName'] = patientName;
    if (mounted) setState(() {
      _data = found;
      _gender = gender;
      _age = age;
      _isDispensed = dispenseStatus == 'dispensed';
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
    final lab = (_data['labResults'] ?? []) as List;
    final rx = (_data['prescriptions'] ?? []) as List;
    return lab.isNotEmpty || rx.isNotEmpty;
  }

  String _getMedAbbrev(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('syrup')) return 'syp.';
    if (t.contains('injection')) return 'inj.';
    if (t.contains('tablet')) return 'tab.';
    if (t.contains('capsule')) return 'cap.';
    if (t.contains('drip')) return 'drip.';
    if (t.contains('syringe')) return 'syr.';
    return '';
  }

  String _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  // ─── Print & Share Options ────────────────────────────────────────────────
  Future<void> _showPrintOptionsSheet() async {
    if (!_hasPrintableContent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nothing to print'), backgroundColor: Colors.orange));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PatientPrintOptionsSheet(
        data: _data,
        branchName: _branchName ?? 'Free Dispensary',
        serial: _resolvedSerial,
        queueType: _resolvedQueueType,
      ),
    );
  }

  // ─── Inventory deduction ──────────────────────────────────────────────────
  static bool _isInjectableType(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('injection') || t.contains('inj') ||
        t.contains('drip') || t.contains('syringe') || t.contains('nebulization');
  }

  Future<void> _deductInventoryLocally(
      String branchId, String serial, List<dynamic> medicines, int days) async {
    for (final med in medicines) {
      if (med is! Map) continue;
      final medMap = Map<String, dynamic>.from(med);
      final medicineId = (medMap['inventoryId'] ??
              medMap['medicineId'] ?? medMap['id'] ?? '').toString().trim();
      final perDayRaw = medMap['quantity'] ?? medMap['qty'] ?? 0;
      final perDay = perDayRaw is num
          ? perDayRaw.toDouble()
          : double.tryParse(perDayRaw.toString()) ?? 0.0;
      if (medicineId.isEmpty || perDay <= 0) continue;
      final multiplier = _isInjectableType(medMap['type']?.toString()) ? 1 : days;
      final qtyNum = perDay * multiplier;
      debugPrint('[PatientForm] deduct $medicineId: ${perDay}/day × $multiplier = $qtyNum');
      try {
        final stockBox = Hive.box(LocalStorageService.stockBox);
        var existing = stockBox.get('stock:$medicineId');
        var keyUsed = 'stock:$medicineId';
        if (existing == null) {
          existing = stockBox.get(medicineId);
          if (existing != null) {
            keyUsed = medicineId;
          }
        }
        if (existing is Map) {
          final updated = Map<String, dynamic>.from(existing);
          final current = (updated['quantity'] as num?)?.toDouble() ?? 0.0;
          updated['quantity'] = (current - qtyNum).clamp(0.0, double.infinity);
          stockBox.put(keyUsed, updated);
          debugPrint('[PatientForm] Hive stock $medicineId: $current → ${updated['quantity']}');
        }
      } catch (e) {
        debugPrint('[PatientForm] Hive stock decrement failed $medicineId: $e');
      }
      bool firestoreWritten = false;
      try {
        final conn = await Connectivity().checkConnectivity();
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

  Future<void> _deductSyringeIfNeeded(
      String branchId, String serial, List<dynamic> allPrescriptions) async {
    double totalSyringesToDeduct = 0.0;
    for (final med in allPrescriptions) {
      if (med is! Map) continue;
      final medMap = Map<String, dynamic>.from(med);
      final type = medMap['type']?.toString();
      final name = medMap['name']?.toString();
      
      final t = (type ?? '').toLowerCase();
      final n = (name ?? '').toLowerCase();
      final isInjOrDrip = t.contains('injection') || t.contains('inj') || t.contains('drip') ||
                          n.contains('injection') || n.contains('inj.') || n.contains('inj ');
      final isSyringe = t.contains('syringe') || n.contains('syringe');
      
      if (isInjOrDrip && !isSyringe) {
        final qtyRaw = medMap['quantity'] ?? medMap['qty'] ?? 1;
        final qty = qtyRaw is num ? qtyRaw.toDouble() : double.tryParse(qtyRaw.toString()) ?? 1.0;
        totalSyringesToDeduct += qty;
      }
    }

    if (totalSyringesToDeduct > 0.0) {
      try {
        final stockBox = Hive.box(LocalStorageService.stockBox);
        String? syringeKey;
        Map<String, dynamic>? syringeMap;
        
        for (final key in stockBox.keys) {
          final val = stockBox.get(key);
          if (val is Map) {
            final name = (val['name'] ?? '').toString().toLowerCase();
            final type = (val['type'] ?? '').toString().toLowerCase();
            if (name.contains('syringe') || type.contains('syringe')) {
              syringeKey = key.toString();
              syringeMap = Map<String, dynamic>.from(val);
              break;
            }
          }
        }
        
        if (syringeKey != null && syringeMap != null) {
          final current = (syringeMap['quantity'] as num?)?.toDouble() ?? 0.0;
          syringeMap['quantity'] = (current - totalSyringesToDeduct).clamp(0.0, double.infinity);
          await stockBox.put(syringeKey, syringeMap);
          debugPrint('[PatientForm] Auto-deducted $totalSyringesToDeduct Syringe ($syringeKey) from Hive: $current → ${syringeMap['quantity']}');
          
          final rawSyringeId = syringeKey.replaceFirst('stock:', '');
          bool firestoreWritten = false;
          try {
            final conn = await Connectivity().checkConnectivity();
            final online = !conn.contains(ConnectivityResult.none);
            if (online) {
              await FirebaseFirestore.instance
                  .collection('branches').doc(branchId)
                  .collection('inventory').doc(rawSyringeId)
                  .update({'quantity': FieldValue.increment(-totalSyringesToDeduct)});
              firestoreWritten = true;
              debugPrint('[PatientForm] ✅ Auto-deducted $totalSyringesToDeduct Syringe ($rawSyringeId) in Firestore');
            }
          } catch (e) {
            debugPrint('[PatientForm] Auto-deducted syringe Firestore update failed: $e');
          }
          
          if (!firestoreWritten) {
            await LocalStorageService.enqueueSync({
              'type': 'update_inventory', 'branchId': branchId,
              'medicineId': rawSyringeId, 'delta': -totalSyringesToDeduct, 'serial': serial,
              'data': {
                'medicineId': rawSyringeId, 
                'medicineName': syringeMap['name'] ?? 'Syringe',
                'delta': -totalSyringesToDeduct, 
                'serial': serial
              },
            });
            debugPrint('[PatientForm] 📥 Queued auto syringe deduction: $rawSyringeId -= $totalSyringesToDeduct');
          }
        } else {
          debugPrint('[PatientForm] ⚠️ Auto syringe deduction skipped: No syringe item found in stock_items');
        }
      } catch (e) {
        debugPrint('[PatientForm] Error during auto syringe deduction: $e');
      }
    }
  }

  // ─── Dispense ─────────────────────────────────────────────────────────────
  Future<void> _dispenseOnly() async {
    if (_isDispensed) return;
    final days = _daysOfMedicine;
    
    // Fallback/standard RoleTheme read to display dialogue matching exact color palette
    var t = RoleThemeScope.dataOf(context);
    if (RoleThemeScope.of(context) == RoleTheme.admin) {
      t = RoleThemeData.of(RoleTheme.dispenser);
    }
    
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
            style: ElevatedButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Dispense'),
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
      final queueType = _resolvedQueueType;
      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyy').format(now);
      final nowIso = now.toIso8601String();
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
        'status': 'completed',
        'dispensedAt': nowIso,
        'dispensedBy': dispenserName,
        'dispenserName': dispenserName,
        'serial': serial,
        'dateKey': dateKey,
        'queueType': queueType,
        'branchId': widget.branchId,
        'daysOfMedicine': days,
      };
      final entryKey = '${widget.branchId}-$serial';
      final currentEntry = Hive.box(LocalStorageService.entriesBox).get(entryKey);
      if (currentEntry != null) {
        final updated = Map<String, dynamic>.from(currentEntry)..addAll(minimalUpdate);
        await Hive.box(LocalStorageService.entriesBox).put(entryKey, updated);
      }
      final dispensaryRecord = {
        ...Map<String, dynamic>.from(widget.queueEntry),
        ...Map<String, dynamic>.from(_data),
        'branchId': widget.branchId,
        'serial': serial,
        'dateKey': dateKey,
        'date': dateKey,
        'queueType': queueType,
        'tokenCreatedAt': widget.queueEntry['createdAt'] ?? _data['createdAt'] ?? _data['tokenCreatedAt'],
        'createdAt': nowIso,
        'dispenseStatus': 'dispensed',
        'status': 'completed',
        'dispensedAt': nowIso,
        'dispensedBy': dispenserName,
        'dispenserName': dispenserName,
        'doctorName': doctorName,
        'prescribedBy': doctorName,
        'tokenBy': tokenBy,
        'createdByName': tokenBy,
        'daysOfMedicine': days,
      };
      await Hive.box(LocalStorageService.dispensaryBox)
          .put('${widget.branchId}_${dateKey}_$serial', dispensaryRecord);
      final allPrescriptions = (_data['prescriptions'] as List?) ?? [];
      final medicines = allPrescriptions
          .where((m) => m is Map &&
              (m['inventoryId'] != null || m['medicineId'] != null || m['id'] != null))
          .toList();
      if (medicines.isNotEmpty) {
        await _deductInventoryLocally(widget.branchId, serial, medicines, days);
      }
      await _deductSyringeIfNeeded(widget.branchId, serial, allPrescriptions);
      RealtimeManager().sendMessage(RealtimeEvents.payload(
        type: 'dispense_completed',
        data: {
          'branchId': widget.branchId,
          'serial': serial,
          'dateKey': dateKey,
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

  // ─── UI builders ──────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, IconData icon, RoleThemeData t, {bool isMobile = false}) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: t.accent, size: isMobile ? 15 : 18),
          ),
          const SizedBox(width: 10),
          Text(
            title, 
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: isMobile ? 15 : 17,
              letterSpacing: 0.2,
            ),
          ),
        ]),
      );

  Widget _linedList(List items, RoleThemeData t, {bool isLab = false, bool isMobile = false}) {
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
        final abbrev = _getMedAbbrev(item['type']);
        final rawName = item['name']?.toString() ?? '';
        final displayName = '$abbrev $rawName'.trim();
        final urduLine = PatientFormHelper.buildUrduDosageLine(item);
        final mealUrdu = PatientFormHelper.getMealUrdu(item['meal']?.toString() ?? '');
        final isInj = _isInjectableType(item['type']?.toString());
        final perDayQty = ((item['quantity'] ?? 1) as num).toInt();
        final totalQty = isInj ? perDayQty : perDayQty * days;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: isMobile ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: t.bgCardAlt.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.bgRule.withValues(alpha: 0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: isMobile ? 13.5 : 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isInj ? 'Single Dose' : '$perDayQty/day',
                            style: TextStyle(
                              color: t.accent,
                              fontSize: isMobile ? 10 : 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!isInj)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: t.zakat.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Qty: $totalQty total',
                              style: TextStyle(
                                color: t.zakat,
                                fontSize: isMobile ? 10 : 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (urduLine.isNotEmpty)
                      Text(
                        urduLine,
                        textAlign: TextAlign.right,
                        textDirection: ui.TextDirection.rtl,
                        style: TextStyle(
                          fontFamily: 'Jameel Noori Nastaleeq',
                          fontSize: isMobile ? 15 : 18,
                          color: t.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (mealUrdu.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          mealUrdu,
                          textAlign: TextAlign.right,
                          textDirection: ui.TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: 'Jameel Noori Nastaleeq',
                            fontSize: isMobile ? 13 : 15,
                            color: t.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── "Medicines for X days" banner ────────────────────────────────────────
  Widget _buildDaysBanner(RoleThemeData t, {required bool isMobile}) {
    final prescribed = _daysOfMedicine;
    final suggested  = _suggestedDays;
    final queueType  = _resolvedQueueType;

    const prices = {'zakat': 20, 'non-zakat': 100, 'gmwf': 0};
    final rate = prices[queueType] ?? 0;

    final refundDays = suggested - prescribed;
    final extraDays  = prescribed - suggested;
    final refundAmt  = refundDays > 0 ? refundDays * rate : 0;
    final extraAmt   = extraDays > 0 ? extraDays * rate : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: isMobile ? 8 : 10),
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.accent.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, color: t.accent, size: isMobile ? 24 : 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medicine Duration Summary',
                      style: PatientFormHelper.robotoBold(size: isMobile ? 14 : 16, color: t.accent),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _dayPill('Paid: $suggested day${suggested > 1 ? 's' : ''}', t.textSecondary),
                        const SizedBox(width: 8),
                        _dayPill('Prescribed: $prescribed day${prescribed > 1 ? 's' : ''}', t.accent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Refund Alert
        if (refundAmt > 0)
          Container(
            margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, color: Colors.orange.shade900, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REFUND REQUIRED: Rs. $refundAmt',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 13 : 15,
                        ),
                      ),
                      Text(
                        'Patient paid for $suggested days but got $prescribed days. Please return the extra amount.',
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Extra Payment Alert
        if (extraAmt > 0)
          Container(
            margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade900, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EXTRA PAYMENT NEEDED: Rs. $extraAmt',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 13 : 15,
                        ),
                      ),
                      Text(
                        'Patient paid for $suggested days but got $prescribed days. Please collect the remaining amount.',
                        style: TextStyle(color: Colors.red.shade800, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dayPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  // ─── Header / footer ──────────────────────────────────────────────────────
  Widget _buildHeader(RoleThemeData t, {required bool isMobile}) => ClipRRect(
    borderRadius: BorderRadius.vertical(top: Radius.circular(isMobile ? 16 : 24)),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.accent, t.accentLight],
        ),
      ),
      child: isMobile
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/logo/gmwf.png', width: 52, height: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: const Text(
                          'ہو الشافی',
                          style: TextStyle(
                            fontFamily: 'Jameel Noori Nastaleeq',
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Text(
                        'Gulzar Madina Welfare Foundation',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Free Dispensary',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Transform.rotate(
                  angle: -0.10,
                  child: Image.asset('assets/images/moon.png', width: 48, height: 48),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset('assets/logo/gmwf.png', width: 110, height: 110),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'ہو الشافی',
                        style: TextStyle(
                          fontFamily: 'Jameel Noori Nastaleeq',
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Gulzar Madina Welfare Foundation',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Free Dispensary',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.85),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.rotate(
                  angle: -0.4,
                  child: Image.asset('assets/images/moon.png', width: 96, height: 96),
                ),
              ],
            ),
    ),
  );

  Widget _buildFooter(RoleThemeData t, {required bool isMobile}) => ClipRRect(
    borderRadius: BorderRadius.vertical(bottom: Radius.circular(isMobile ? 16 : 24)),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.accent, t.accentLight],
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Text(
              'Gulzar Madina ${_branchName ?? ''}',
              style: TextStyle(
                fontSize: isMobile ? 13 : 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Website: gulzarmadina.com',
              style: TextStyle(
                fontSize: isMobile ? 11 : 14,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildActionBar(RoleThemeData t, {required bool isMobile}) {
    final days = _daysOfMedicine;

    final dispenseLabel = _isDispensed
        ? 'Already Dispensed'
        : _isDispensing
            ? 'Dispensing...'
            : days > 1
                ? 'Dispense ($days days\' supply)'
                : 'Dispense Medicine';

    final dispenseBtn = AnimatedScale(
      scale: _isDispensing ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: !_isDispensed && !_isDispensing ? t.accentGradient : null,
          color: _isDispensed || _isDispensing ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(27),
          boxShadow: _isDispensed || _isDispensing
              ? []
              : [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  )
                ],
        ),
        child: ElevatedButton.icon(
          onPressed: _isDispensed || _isDispensing ? null : _dispenseOnly,
          icon: _isDispensing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle, color: Colors.white, size: 20),
          label: Text(
            dispenseLabel,
            style: TextStyle(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          ),
        ),
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 28,
              vertical: isMobile ? 12 : 18,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              border: Border(
                top: BorderSide(color: t.bgRule.withValues(alpha: 0.5), width: 1.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: dispenseBtn,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, RoleThemeData t, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: t.textTertiary, size: isMobile ? 12 : 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: t.textTertiary,
                fontSize: isMobile ? 9 : 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: isMobile ? 12 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(RoleThemeData t, {required bool isMobile}) {
    final prescriptions = (_data['prescriptions'] ?? []) as List;
    final labTests = (_data['labResults'] ?? []) as List;
    final diagnosis = _data['diagnosis']?.toString() ?? '';
    final patientName = _data['patientName'] ?? 'Unknown';
    
    final serial = _resolvedSerial;
    final cnic = _firstNonEmpty([
      _data['patientCnic'], _data['cnic'], widget.queueEntry['patientCnic'], widget.queueEntry['cnic'], 'N/A'
    ]);
    final queueType = _resolvedQueueType.toUpperCase();

    final inventoryMeds = prescriptions.where((m) => m['inventoryId'] != null && !PatientFormHelper.isInjectable(m)).toList();
    final inventoryInjectables = prescriptions.where((m) => m['inventoryId'] != null && PatientFormHelper.isInjectable(m)).toList();
    final customMeds = prescriptions.where((m) => m['inventoryId'] == null && !PatientFormHelper.isInjectable(m)).toList();
    final customInjectables = prescriptions.where((m) => m['inventoryId'] == null && PatientFormHelper.isInjectable(m)).toList();
    
    final basePadding = isMobile ? 16.0 : 32.0;

    Widget patientInfoCard = Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: t.bgCardAlt.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: isMobile ? 20 : 24,
                backgroundColor: t.accent.withValues(alpha: 0.1),
                child: Icon(Icons.person, color: t.accent, size: isMobile ? 20 : 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: isMobile ? 16 : 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'CNIC: $cnic',
                      style: TextStyle(
                        color: t.textTertiary,
                        fontSize: isMobile ? 11 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _resolvedQueueType == 'zakat'
                      ? t.zakat.withValues(alpha: 0.15)
                      : _resolvedQueueType == 'non-zakat'
                          ? t.nonZakat.withValues(alpha: 0.15)
                          : t.gmwf.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _resolvedQueueType == 'zakat'
                        ? t.zakat
                        : _resolvedQueueType == 'non-zakat'
                            ? t.nonZakat
                            : t.gmwf,
                  ),
                ),
                child: Text(
                  queueType,
                  style: TextStyle(
                    color: _resolvedQueueType == 'zakat'
                        ? t.zakat
                        : _resolvedQueueType == 'non-zakat'
                            ? t.nonZakat
                            : t.gmwf,
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 10 : 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoTile(Icons.wc, 'GENDER', _gender ?? 'N/A', t, isMobile),
              _infoTile(Icons.cake, 'AGE', _age != 'N/A' ? '$_age Years' : 'N/A', t, isMobile),
              _infoTile(Icons.tag, 'TOKEN SERIAL', serial, t, isMobile),
            ],
          ),
        ],
      ),
    );

    Widget medicineBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        _buildDaysBanner(t, isMobile: isMobile),
        const SizedBox(height: 12),
        patientInfoCard,
        if (diagnosis.isNotEmpty) ...[
          SizedBox(height: isMobile ? 12 : 20),
          _sectionTitle('Diagnosis', Icons.medical_services, t, isMobile: isMobile),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.bgCardAlt.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.bgRule.withValues(alpha: 0.4)),
            ),
            child: Text(
              diagnosis, 
              style: TextStyle(
                color: t.textPrimary,
                fontSize: isMobile ? 13 : 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (isMobile && labTests.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildLabOrPhysioSection(labTests, t, isMobile: true),
          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade200, height: 20),
        ],
        if (inventoryMeds.isNotEmpty) ...[
          SizedBox(height: isMobile ? 12 : 20),
          _sectionTitle('Inventory Medicines', Icons.medication, t, isMobile: isMobile),
          _linedList(inventoryMeds, t, isMobile: isMobile),
        ],
        if (inventoryInjectables.isNotEmpty) ...[
          SizedBox(height: isMobile ? 12 : 20),
          _sectionTitle('Inventory Injectables', Icons.vaccines, t, isMobile: isMobile),
          _linedList(inventoryInjectables, t, isMobile: isMobile),
        ],
        if (customMeds.isNotEmpty) ...[
          SizedBox(height: isMobile ? 12 : 20),
          _sectionTitle('Custom Medicines', Icons.medication_liquid, t, isMobile: isMobile),
          _linedList(customMeds, t, isMobile: isMobile),
        ],
        if (customInjectables.isNotEmpty) ...[
          SizedBox(height: isMobile ? 12 : 20),
          _sectionTitle('Custom Injectables', Icons.vaccines, t, isMobile: isMobile),
          _linedList(customInjectables, t, isMobile: isMobile),
        ],
      ],
    );

    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(basePadding),
      child: isMobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [medicineBody, const SizedBox(height: 20)])
          : IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (labTests.isNotEmpty) ...[
                Expanded(flex: 3, child: _buildLabOrPhysioSection(labTests, t, isMobile: false)),
                Container(width: 1, color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(horizontal: 20)),
              ],
              Expanded(flex: 7, child: medicineBody),
            ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;
    
    // Curated GMWF Brand Clinical Teal Theme
    const t = RoleThemeData(
      roleLabel:             'CLINICAL',
      bg:                    Color(0xFFF2FBF9),
      bgCard:                Color(0xFFFFFFFF),
      bgCardAlt:             Color(0xFFE6F7F4),
      bgRule:                Color(0xFFCBECE6),
      accent:                Color(0xFF00695C),
      accentLight:           Color(0xFF0D9488),
      accentMuted:           Color(0xFFE0F2F1),
      accentGradient:        LinearGradient(colors: [Color(0xFF00695C), Color(0xFF0D9488)]),
      glassTint:             Color(0x1A00695C),
      textPrimary:           Color(0xFF002521),
      textSecondary:         Color(0xFF004D43),
      textTertiary:          Color(0xFF4DB6A7),
      danger:                Color(0xFFB91C1C),
      zakat:                 Color(0xFF2E7D32),
      nonZakat:              Color(0xFF1565C0),
      gmwf:                  Color(0xFFE65100),
      cardFillTokens:        Color(0xFF00695C),
      cardFillPrescriptions: Color(0xFF004D43),
      cardFillDispensary:    Color(0xFF00332C),
      chartBar1:             Color(0xFF00695C),
      chartBar2:             Color(0xFF2E7D32),
      chartBar3:             Color(0xFF1565C0),
      chartGrid:             Color(0xFFCBECE6),
    );

    if (_isLoadingPrescription) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: [
            CircularProgressIndicator(color: t.accent),
            const SizedBox(height: 16),
            Text('Loading prescription...', style: TextStyle(color: t.accent, fontWeight: FontWeight.bold)),
          ],
        ),
      );
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
          style: ElevatedButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: Colors.white,
          )),
      ]));
    }
    final bottomBarHeight = isMobile ? 148.0 : 92.0;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(children: [
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
              left: isMobile ? 8 : 16, right: isMobile ? 8 : 16,
              top: isMobile ? 8 : 16, bottom: bottomBarHeight + 16),
          child: Center(child: Container(
            constraints: isMobile ? const BoxConstraints() : const BoxConstraints(maxWidth: 850),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06), 
                  blurRadius: 18, 
                  offset: const Offset(0, 8),
                )
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _buildHeader(t, isMobile: isMobile),
              _buildContent(t, isMobile: isMobile),
              _buildFooter(t, isMobile: isMobile),
            ]),
          )),
        ),
        _buildActionBar(t, isMobile: isMobile),
      ]),
    );
  }

  Widget _buildLabOrPhysioSection(List labTests, RoleThemeData t, {required bool isMobile}) {
    if (labTests.isEmpty) return const SizedBox.shrink();
    
    final isPhysio = _data['isPhysiotherapist'] == true ||
        _data['isPhysiotherapy'] == true ||
        _data['department']?.toString().toLowerCase().contains('physio') == true ||
        _data['dpt']?.toString().toLowerCase().contains('physio') == true ||
        labTests.any((item) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          return name.contains('therapy') ||
              name.contains('tens') ||
              name.contains('traction') ||
              name.contains('swd') ||
              name.contains('exercise') ||
              name.contains('diathermy') ||
              name.contains('pack') ||
              name.contains('massage') ||
              name.contains('ultrasound');
        });

    final title = isPhysio ? 'Physiotherapies' : 'Lab Tests';
    final icon = isPhysio ? Icons.accessibility_new_rounded : Icons.biotech_rounded;
    final themeColor = isPhysio ? Colors.indigo : t.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title, icon, t, isMobile: isMobile),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: labTests.map((item) {
            final name = item['name']?.toString() ?? 'Unknown';
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 14,
                vertical: isMobile ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: themeColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPhysio ? Icons.spa_rounded : Icons.science_rounded,
                    color: themeColor,
                    size: isMobile ? 14 : 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.w700,
                      color: themeColor.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PREMIUM PRINT & SHARE OPTIONS SHEET (Matches donations design system)
// ─────────────────────────────────────────────────────────────────────────────
class _PatientPrintOptionsSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final String branchName;
  final String serial;
  final String queueType;

  const _PatientPrintOptionsSheet({
    required this.data,
    required this.branchName,
    required this.serial,
    required this.queueType,
  });

  @override
  State<_PatientPrintOptionsSheet> createState() => _PatientPrintOptionsSheetState();
}

class _PatientPrintOptionsSheetState extends State<_PatientPrintOptionsSheet> {
  bool _isGenerating = false;
  String _loadingMessage = '';

  void _showLoading(String msg) {
    setState(() {
      _isGenerating = true;
      _loadingMessage = msg;
    });
  }

  void _hideLoading() {
    setState(() {
      _isGenerating = false;
    });
  }

  Future<void> _handlePrint() async {
    _showLoading('Preparing print slip...');
    Uint8List? pdfBytes;
    try {
      pdfBytes = await PatientFormHelper.generatePrintSlip(
        data: widget.data,
        branchName: widget.branchName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _hideLoading();
    }

    if (pdfBytes != null) {
      await Printing.layoutPdf(
        onLayout: (_) => pdfBytes!,
        name: 'Slip_${widget.serial.isNotEmpty ? widget.serial : 'unknown'}.pdf',
      );
    }
  }

  Future<void> _handleSavePdf() async {
    _showLoading('Generating PDF file...');
    Uint8List? pdfBytes;
    try {
      pdfBytes = await PatientFormHelper.generatePrintSlip(
        data: widget.data,
        branchName: widget.branchName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save PDF failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _hideLoading();
    }

    if (pdfBytes != null) {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Slip_${widget.serial.isNotEmpty ? widget.serial : 'unknown'}.pdf',
      );
    }
  }

  Future<void> _handleWhatsAppShare() async {
    _showLoading('Generating WhatsApp PDF...');
    Uint8List? pdfBytes;
    try {
      final patientName = widget.data['patientName'] ?? 'Patient';
      final gender = widget.data['patientGender'] ?? widget.data['gender'] ?? 'N/A';
      final age = (widget.data['patientAge'] ?? widget.data['age'] ?? 'N/A').toString();

      pdfBytes = await PatientFormHelper.generateWhatsAppPdf(
        widget.data,
        widget.branchName,
        gender,
        age,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WhatsApp share failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _hideLoading();
    }

    if (pdfBytes != null) {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Prescription_${widget.serial.isNotEmpty ? widget.serial : 'unknown'}.pdf',
      );
    }
  }

  Widget _infoSummary(String label, String value) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Color(0xFF4DB6A7),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF002521),
          ),
        ),
      ],
    );
  }

  Widget _premiumPrintBtn({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 90,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/logo/gmwf.png', height: 36, errorBuilder: (_, __, ___) => const Icon(Icons.medical_services, color: Color(0xFF00695C))),
                  const Text(
                    'Print & Share Slip',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF002521),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Patient Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F7F4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCBECE6)),
                ),
                child: Column(
                  children: [
                    Text(
                      (widget.data['patientName'] ?? 'Unknown Patient').toString().toUpperCase(), 
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF00695C),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _infoSummary('Serial Token', '#${widget.serial}'),
                        Container(width: 1, height: 24, color: const Color(0xFFCBECE6)),
                        _infoSummary('Queue Type', widget.queueType.toUpperCase()),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _premiumPrintBtn(
                      label: 'Print Slip',
                      color: const Color(0xFF00695C),
                      icon: Icons.print_rounded,
                      onTap: _handlePrint,
                    ),
                    _premiumPrintBtn(
                      label: 'Save PDF',
                      color: const Color(0xFFB91C1C),
                      icon: Icons.picture_as_pdf_rounded,
                      onTap: _handleSavePdf,
                    ),
                    _premiumPrintBtn(
                      label: 'WhatsApp',
                      color: const Color(0xFF2E7D32),
                      icon: Icons.share_rounded,
                      onTap: _handleWhatsAppShare,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isGenerating)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF00695C)),
                      const SizedBox(height: 16),
                      Text(
                        _loadingMessage,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF002521),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
