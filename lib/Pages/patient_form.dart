// lib/pages/patient_form.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import 'patient_form_helper.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

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

  static const Color _teal = Color(0xFF00695C);

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    debugPrint('[PatientForm] Opened — serial: ${widget.queueEntry['serial']} | branch: ${widget.branchId}');
    _loadBranchName();
    _loadPrescription();

    _realtimeSub = RealtimeManager().messageStream.listen((event) {
      final type = event['event_type'] as String?;
      final data = event['data'] as Map<String, dynamic>? ?? {};
      if (type == null) return;

      final eventSerial = data['serial']?.toString().trim().toLowerCase();
      final mySerial = widget.queueEntry['serial']?.toString().trim().toLowerCase();
      final eventBranch = data['branchId']?.toString().trim().toLowerCase();
      final myBranch = widget.branchId.toLowerCase().trim();

      if (eventBranch != null && eventBranch != myBranch) return;
      if (eventSerial != null && eventSerial != mySerial) return;

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

  // ─── Branch name ───────────────────────────────────────────────────────────
  Future<void> _loadBranchName() async {
    if (widget.branchId.isEmpty) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('branches').doc(widget.branchId).get();
      if (mounted) setState(() {
        _branchName = doc.exists ? (doc.data()?['name'] ?? 'Free Dispensary') : 'Free Dispensary';
        _loadingBranch = false;
      });
    } catch (_) {
      if (mounted) setState(() { _branchName = 'Free Dispensary'; _loadingBranch = false; });
    }
  }

  // ─── Main prescription loader ──────────────────────────────────────────────
  Future<void> _loadPrescription() async {
    if (!mounted) return;
    if (mounted) setState(() => _isLoadingPrescription = true);

    final serial = widget.queueEntry['serial']?.toString().trim().toLowerCase() ?? '';
    final dateKey = serial.isNotEmpty ? serial.split('-')[0] : '';

    // Build CNIC from queueEntry
    String cnic = '';
    for (final field in ['patientCnic', 'cnic', 'guardianCnic', 'patientCNIC', 'guardianCNIC']) {
      final v = widget.queueEntry[field]?.toString().trim().replaceAll('-', '').replaceAll(' ', '').toLowerCase() ?? '';
      if (v.isNotEmpty && v != '0000000000000') { cnic = v; break; }
    }

    debugPrint('[PatientForm] Loading prescription — serial: $serial | cnic: $cnic | dateKey: $dateKey');

    Map<String, dynamic> found = {};

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 1 — Check Hive local storage first (fastest, realtime updates land here)
    // Doctor saves to Hive key: "{cnic}_{serial}" via LocalStorageService.saveLocalPrescription
    // ═══════════════════════════════════════════════════════════════════════════
    found = _searchHive(serial, cnic);

    if (found.isNotEmpty) {
      debugPrint('[PatientForm] ✅ Found in Hive local cache');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 2 — Firestore: branches/{branchId}/prescriptions/{dateKey}/prescriptions/{serial}
    // This is the dedicated prescriptions collection path
    // ═══════════════════════════════════════════════════════════════════════════
    if (found.isEmpty && serial.isNotEmpty && dateKey.isNotEmpty) {
      found = await _fetchFromPrescriptionsCollection(serial, dateKey);
      if (found.isNotEmpty) {
        debugPrint('[PatientForm] ✅ Found in Firestore prescriptions collection');
        // Save to Hive for future use
        await LocalStorageService.saveLocalPrescription(found);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 3 — Firestore: branches/{branchId}/serials/{dateKey}/{queueType}/{serial}
    // This is where the doctor also embeds the prescription in the serial doc
    // ═══════════════════════════════════════════════════════════════════════════
    if (found.isEmpty && serial.isNotEmpty && dateKey.isNotEmpty) {
      found = await _fetchFromSerialsCollection(serial, dateKey);
      if (found.isNotEmpty) {
        debugPrint('[PatientForm] ✅ Found in Firestore serials collection (embedded prescription)');
        await LocalStorageService.saveLocalPrescription(found);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 4 — Check entries box (queueEntry itself may have prescription embedded)
    // ═══════════════════════════════════════════════════════════════════════════
    if (found.isEmpty) {
      final embeddedPrescription = widget.queueEntry['prescription'];
      if (embeddedPrescription is Map && embeddedPrescription.isNotEmpty) {
        found = Map<String, dynamic>.from(embeddedPrescription);
        debugPrint('[PatientForm] ✅ Found prescription embedded in queueEntry');
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STEP 5 — Re-search Hive after Firestore downloads (in case download populated it)
    // ═══════════════════════════════════════════════════════════════════════════
    if (found.isEmpty) {
      found = _searchHive(serial, cnic);
      if (found.isNotEmpty) {
        debugPrint('[PatientForm] ✅ Found in Hive after Firestore sync');
      }
    }

    if (found.isEmpty) {
      debugPrint('[PatientForm] ❌ No prescription found anywhere for serial: $serial');
    } else {
      debugPrint('[PatientForm] Prescription loaded — medicines: ${(found['prescriptions'] as List?)?.length ?? 0} | labs: ${(found['labResults'] as List?)?.length ?? 0}');
    }

    // Extract gender/age from best available source
    final vitals = (widget.queueEntry['vitals'] as Map<String, dynamic>?) ?? {};
    final gender = found['patientGender']?.toString() ??
        widget.queueEntry['patientGender']?.toString() ??
        vitals['gender']?.toString() ??
        'N/A';
    final age = found['patientAge']?.toString() ??
        widget.queueEntry['patientAge']?.toString() ??
        vitals['age']?.toString() ??
        'N/A';

    final dispenseStatus = (widget.queueEntry['dispenseStatus'] ?? '').toString().toLowerCase();
    final patientName = found['patientName']?.toString() ??
        widget.queueEntry['patientName']?.toString() ??
        'Unknown Patient';
    if (found.isNotEmpty) found['patientName'] = patientName;

    if (mounted) {
      setState(() {
        _data = found;
        _gender = gender;
        _age = age;
        _isDispensed = dispenseStatus == 'dispensed';
        _isLoadingPrescription = false;
      });
    }
  }

  // ─── Hive search ───────────────────────────────────────────────────────────
  Map<String, dynamic> _searchHive(String serial, String cnic) {
    final box = Hive.box(LocalStorageService.prescriptionsBox);

    // Priority 1: composite key "{cnic}_{serial}" — matches doctor's save
    if (cnic.isNotEmpty && serial.isNotEmpty) {
      final key = '${cnic}_$serial';
      final v = box.get(key);
      if (v is Map && v.isNotEmpty) return Map<String, dynamic>.from(v);
    }

    // Priority 2: plain serial key
    if (serial.isNotEmpty) {
      final v = box.get(serial);
      if (v is Map && v.isNotEmpty) return Map<String, dynamic>.from(v);
    }

    // Priority 3: scan — any key containing the serial
    if (serial.isNotEmpty) {
      for (final key in box.keys) {
        if (key is String && key.toLowerCase().contains(serial)) {
          final v = box.get(key);
          if (v is Map && (v as Map).isNotEmpty) {
            return Map<String, dynamic>.from(v);
          }
        }
      }
    }

    // Priority 4: scan — any key starting with cnic
    if (cnic.isNotEmpty) {
      for (final key in box.keys) {
        if (key is String && key.toLowerCase().startsWith(cnic)) {
          final v = box.get(key);
          if (v is Map && (v as Map).isNotEmpty) {
            final m = Map<String, dynamic>.from(v);
            // Only return if serial matches
            final s = m['serial']?.toString().trim().toLowerCase() ?? '';
            if (s == serial) return m;
          }
        }
      }
    }

    return {};
  }

  // ─── Firestore: prescriptions collection ──────────────────────────────────
  // Path: branches/{branchId}/prescriptions/{dateKey}/prescriptions/{serial}
  Future<Map<String, dynamic>> _fetchFromPrescriptionsCollection(
      String serial, String dateKey) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(dateKey)
          .collection('prescriptions')
          .doc(serial);

      final snap = await ref.get();
      if (snap.exists && snap.data() != null) {
        return Map<String, dynamic>.from(snap.data()!);
      }
    } catch (e) {
      debugPrint('[PatientForm] Firestore prescriptions collection error: $e');
    }
    return {};
  }

  // ─── Firestore: serials collection (embedded prescription field) ───────────
  // Path: branches/{branchId}/serials/{dateKey}/{queueType}/{serial}
  Future<Map<String, dynamic>> _fetchFromSerialsCollection(
      String serial, String dateKey) async {
    try {
      // Try all queue types since we may not know which type this patient is
      final queueType = widget.queueEntry['queueType']?.toString().toLowerCase() ?? '';
      final typesToTry = queueType.isNotEmpty
          ? [queueType, 'zakat', 'non-zakat', 'gmwf']
          : ['zakat', 'non-zakat', 'gmwf'];

      for (final type in typesToTry.toSet()) {
        final ref = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('serials')
            .doc(dateKey)
            .collection(type)
            .doc(serial);

        final snap = await ref.get();
        if (snap.exists && snap.data() != null) {
          final d = Map<String, dynamic>.from(snap.data()!);
          // The prescription is embedded as a field named 'prescription'
          final embedded = d['prescription'];
          if (embedded is Map && embedded.isNotEmpty) {
            return Map<String, dynamic>.from(embedded);
          }
          // If no embedded prescription but the doc has medicines directly, use it
          if (d.containsKey('prescriptions')) {
            return d;
          }
        }
      }
    } catch (e) {
      debugPrint('[PatientForm] Firestore serials collection error: $e');
    }
    return {};
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────
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

  // ─── Print ──────────────────────────────────────────────────────────────────
  Future<void> _printOnly() async {
    if (!_hasPrintableContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to print'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final pdfBytes = await PatientFormHelper.generatePrintSlip(
        data: _data,
        branchName: _branchName ?? 'Free Dispensary',
      );

      await Printing.layoutPdf(
        onLayout: (_) => pdfBytes,
        name: 'Slip_${widget.queueEntry['serial'] ?? 'unknown'}.pdf',
      );
    } catch (e) {
      debugPrint('[PatientForm] Print error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  // ─── Dispense ───────────────────────────────────────────────────────────────
  Future<void> _dispenseOnly() async {
    if (_isDispensed) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Dispense'),
        content: const Text('Mark this prescription as dispensed? This cannot be undone.'),
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
      final serial = widget.queueEntry['serial']?.toString() ?? '';
      if (serial.isEmpty) throw Exception('Missing serial');

      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyy').format(now);
      final nowIso = now.toIso8601String();

      final minimalUpdate = {
        'dispenseStatus': 'dispensed',
        'dispensedAt': nowIso,
        'dispensedBy': widget.dispenserName ?? 'Unknown Dispenser',
      };

      // Update entries Hive box
      final entryKey = '${widget.branchId}-$serial';
      final currentEntry = Hive.box(LocalStorageService.entriesBox).get(entryKey);
      if (currentEntry != null) {
        final updated = Map<String, dynamic>.from(currentEntry);
        updated.addAll(minimalUpdate);
        await Hive.box(LocalStorageService.entriesBox).put(entryKey, updated);
      }

      // Save dispensary record
      final dispensaryRecord = {
        ...Map<String, dynamic>.from(widget.queueEntry),
        ...Map<String, dynamic>.from(_data),
        'branchId': widget.branchId,
        'serial': serial,
        'date': dateKey,
        'createdAt': nowIso,
        'dispenseStatus': 'dispensed',
        'dispensedAt': nowIso,
        'dispensedBy': widget.dispenserName ?? 'Unknown Dispenser',
      };
      final dispensaryBox = Hive.box('local_dispensary');
      await dispensaryBox.put('${widget.branchId}_${dateKey}_$serial', dispensaryRecord);

      // Broadcast via LAN
      RealtimeManager().sendMessage(RealtimeEvents.payload(
        type: 'dispense_completed',
        data: {'branchId': widget.branchId, 'serial': serial, ...minimalUpdate},
      ));

      // Queue for Firestore sync
      await LocalStorageService.enqueueSync({
        'type': 'update_serial_status',
        'branchId': widget.branchId,
        'serial': serial,
        'data': minimalUpdate,
      });
      await LocalStorageService.enqueueSync({
        'type': 'save_dispensary_record',
        'branchId': widget.branchId,
        'dateKey': dateKey,
        'serial': serial,
        'data': dispensaryRecord,
      });
      SyncService().triggerUpload();

      if (mounted) setState(() => _isDispensed = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispensed successfully'), backgroundColor: Colors.green),
      );
      widget.onDispensed?.call();
    } catch (e) {
      debugPrint('[PatientForm] Dispense error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to dispense: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isDispensing = false);
    }
  }

  // ─── UI Helpers ─────────────────────────────────────────────────────────────
  Widget _sectionTitle(String title, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: _teal, size: 20),
            const SizedBox(width: 10),
            Text(title, style: PatientFormHelper.robotoBold(size: 18, color: _teal)),
          ],
        ),
      );

  Widget _linedList(List items, {bool isLab = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (isLab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(item['name']?.toString() ?? '',
                style: PatientFormHelper.robotoBold(size: 16)),
          );
        }).toList(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        final abbrev = _getMedAbbrev(item['type']);
        final rawName = item['name']?.toString() ?? '';
        final displayName = '$abbrev $rawName'.trim();
        final urduLine = PatientFormHelper.buildUrduDosageLine(item);
        final mealUrdu = PatientFormHelper.getMealUrdu(item['meal']?.toString() ?? '');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(displayName,
                    style: PatientFormHelper.robotoBold(size: 16)),
              ),
              Expanded(
                flex: 4,
                child: Directionality(
                  textDirection: ui.TextDirection.rtl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (urduLine.isNotEmpty)
                        Text(urduLine,
                            textAlign: TextAlign.right,
                            style: PatientFormHelper.nooriRegular(
                                size: 16, color: PatientFormHelper.textBlack)),
                      if (mealUrdu.isNotEmpty)
                        Text(mealUrdu,
                            textAlign: TextAlign.right,
                            style: PatientFormHelper.nooriRegular(
                                size: 14, color: PatientFormHelper.textBlack)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHeader() => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          color: _teal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset('assets/logo/gmwf.png', width: 100, height: 100),
              Expanded(
                child: Column(children: [
                  Text('ہو الشافی',
                      style: PatientFormHelper.nooriRegular(size: 32, color: Colors.white)),
                  Text('Gulzar-e-Madina Welfare Foundation',
                      style: PatientFormHelper.robotoBold(size: 26, color: Colors.white)),
                  Text('Free Dispensary',
                      style: PatientFormHelper.robotoBold(size: 24, color: Colors.white)),
                ]),
              ),
              Image.asset('assets/images/moon.png', width: 90, height: 90),
            ],
          ),
        ),
      );

  Widget _buildFooter() => ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: _teal,
          child: Center(
            child: Column(children: [
              Text('Gulzar e Madina ${_branchName ?? ''}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('Website: gulzarmadina.com',
                  style: TextStyle(fontSize: 14, color: Colors.white70)),
            ]),
          ),
        ),
      );

  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrescription) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _teal),
            SizedBox(height: 16),
            Text('Loading prescription...', style: TextStyle(color: _teal)),
          ],
        ),
      );
    }

    if (_data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No prescription found yet',
                style: TextStyle(color: Colors.grey, fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadPrescription,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: _teal),
            ),
          ],
        ),
      );
    }

    final prescriptions = (_data['prescriptions'] ?? []) as List;
    final labTests = (_data['labResults'] ?? []) as List;
    final diagnosis = _data['diagnosis']?.toString() ?? '';
    final patientName = _data['patientName'] ?? 'Unknown';

    final inventoryMeds = prescriptions
        .where((m) => m['inventoryId'] != null && !PatientFormHelper.isInjectable(m))
        .toList();
    final inventoryInjectables = prescriptions
        .where((m) => m['inventoryId'] != null && PatientFormHelper.isInjectable(m))
        .toList();
    final customMeds = prescriptions
        .where((m) => m['inventoryId'] == null && !PatientFormHelper.isInjectable(m))
        .toList();
    final customInjectables = prescriptions
        .where((m) => m['inventoryId'] == null && PatientFormHelper.isInjectable(m))
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 850),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 8))
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  _buildHeader(),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(40),
                    child: Column(children: [
                      const SizedBox(height: 20),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (labTests.isNotEmpty) ...[
                              Expanded(flex: 2, child: _buildLabCol(labTests)),
                              Container(
                                  width: 1,
                                  color: Colors.grey.shade300,
                                  margin: const EdgeInsets.symmetric(horizontal: 20)),
                            ],
                            Expanded(
                              flex: 8,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      style: PatientFormHelper.robotoBold(size: 18),
                                      children: [
                                        TextSpan(text: 'Patient: ', style: PatientFormHelper.robotoBold(color: _teal, size: 18)),
                                        TextSpan(text: patientName, style: PatientFormHelper.robotoBold(size: 20)),
                                        const TextSpan(text: '   '),
                                        TextSpan(text: 'Gender: ', style: PatientFormHelper.robotoBold(color: _teal, size: 18)),
                                        TextSpan(text: _gender ?? 'N/A', style: PatientFormHelper.robotoBold(size: 20)),
                                        const TextSpan(text: '   '),
                                        TextSpan(text: 'Age: ', style: PatientFormHelper.robotoBold(color: _teal, size: 18)),
                                        TextSpan(text: _age ?? 'N/A', style: PatientFormHelper.robotoBold(size: 20)),
                                      ],
                                    ),
                                  ),
                                  if (diagnosis.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _sectionTitle('Diagnosis', Icons.medical_services),
                                    Text(diagnosis, style: PatientFormHelper.robotoRegular(size: 16)),
                                  ],
                                  if (inventoryMeds.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _sectionTitle('Inventory Medicines', Icons.medication),
                                    _linedList(inventoryMeds),
                                  ],
                                  if (inventoryInjectables.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _sectionTitle('Inventory Injectables', Icons.vaccines),
                                    _linedList(inventoryInjectables),
                                  ],
                                  if (customMeds.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _sectionTitle('Custom Medicines', Icons.medication_liquid),
                                    _linedList(customMeds),
                                  ],
                                  if (customInjectables.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _sectionTitle('Custom Injectables', Icons.vaccines),
                                    _linedList(customInjectables),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ]),
                  ),
                  _buildFooter(),
                  const SizedBox(height: 140),
                ]),
              ),
            ),
          ),

          // ── Bottom action bar ─────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _hasPrintableContent && !_isPrinting ? _printOnly : null,
                    icon: _isPrinting
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print, color: Colors.white),
                    label: Text(_isPrinting ? 'Printing...' : 'Print Slip',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasPrintableContent ? _teal : Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                    ),
                  ),
                  const SizedBox(width: 32),
                  ElevatedButton.icon(
                    onPressed: _isDispensed || _isDispensing ? null : _dispenseOnly,
                    icon: _isDispensing
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle, color: Colors.white),
                    label: Text(
                      _isDispensed ? 'Already Dispensed' : (_isDispensing ? 'Dispensing...' : 'Dispense Medicine'),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDispensed ? Colors.grey.shade600 : _teal,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabCol(List labTests) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Lab Tests', Icons.biotech),
          ...labTests.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(item['name']?.toString() ?? '',
                    style: PatientFormHelper.robotoBold(size: 16)),
              )),
        ],
      );
}