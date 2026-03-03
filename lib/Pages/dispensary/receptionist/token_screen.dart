// lib/pages/dispensary/receptionist/token_screen.dart
// FIXES:
//   1. TokenScreenState is PUBLIC — receptionist_screen.dart GlobalKey works.
//   2. _syncToFirestoreInBackground ALWAYS writes to serials/{dateKey}/{queueType}/{serial}
//      and falls back to sync queue on offline/error — never silently drops.
//   3. _resolveQueueType is single source of truth for queue categorisation.
//   4. entryData has 'queueType' at top level for SyncService.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../services/local_storage_service.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';

class TokenScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String receptionistName;
  final Function(String cnic)? onPatientNotFound;
  final String? initialCnic;

  const TokenScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
    required this.receptionistName,
    this.onPatientNotFound,
    this.initialCnic,
  });

  @override
  State<TokenScreen> createState() => TokenScreenState(); // PUBLIC
}

// FIX: PUBLIC (was _TokenScreenState)
class TokenScreenState extends State<TokenScreen> with WidgetsBindingObserver {
  final TextEditingController cnicController = TextEditingController();
  final FocusNode _cnicFocusNode = FocusNode();
  bool _isLoading    = false;
  bool _isRefreshing = false;
  String? _nextSerial;
  Map<String, dynamic>? _patientData;
  List<Map<String, dynamic>> _patientsList = [];
  bool _hasTokenToday    = false;
  String? _guardianCnic;
  Map<String, dynamic>? _guardianPatient;
  String? _errorMessage;

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  static const Color _teal  = Color(0xFF00695C);
  static const Color _green = Color(0xFF388E3C);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _estimateNextSerial();

    if (widget.initialCnic != null && widget.initialCnic!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusAndFillCnic(widget.initialCnic!);
      });
    }

    _realtimeSub = RealtimeManager().messageStream.listen((message) {
      final type = message['event_type'] as String?;
      final data = message['data'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      final eventBranch = data['branchId']?.toString().toLowerCase().trim();
      final myBranch    = widget.branchId.toLowerCase().trim();
      if (eventBranch != null && eventBranch != myBranch) return;
      if (type == RealtimeEvents.saveEntry || type == 'token_created') {
        _instantRefresh();
      } else if (type == 'token_reversal_approved') {
        if (_patientData?['patientId'] != null) {
          _checkIfTokenStillExists(_patientData!['patientId'] as String);
        }
        _instantRefresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _instantRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSub?.cancel();
    cnicController.dispose();
    _cnicFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TokenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCnic != null &&
        widget.initialCnic != oldWidget.initialCnic) {
      focusAndFillCnic(widget.initialCnic!);
    }
  }

  // ── Queue-type resolver ────────────────────────────────────────────────────
  String _resolveQueueType(String? rawStatus) {
    final s = (rawStatus ?? '').toLowerCase().trim();
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) return 'non-zakat';
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    return 'zakat';
  }

  // ── Refresh ────────────────────────────────────────────────────────────────
  Future<void> _instantRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await LocalStorageService.downloadTodayTokens(widget.branchId);
      _estimateNextSerial();
      if (_patientData?['patientId'] != null) {
        final stillHas =
            await _tokenExistsToday(_patientData!['patientId'] as String);
        setState(() => _hasTokenToday = stillHas);
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[TokenScreen] Instant refresh failed: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _checkIfTokenStillExists(String patientId) async {
    final stillHas = await _tokenExistsToday(patientId);
    if (mounted) setState(() => _hasTokenToday = stillHas);
  }

  Future<bool> _tokenExistsToday(String patientId) async {
    final datePart = DateFormat('ddMMyy').format(DateTime.now());
    final entries  = LocalStorageService.getLocalEntries(widget.branchId);
    return entries.any((e) =>
        e['patientId'] == patientId && (e['dateKey'] as String?) == datePart);
  }

  void _estimateNextSerial() {
    final datePart   = DateFormat('ddMMyy').format(DateTime.now());
    final localCount = LocalStorageService.getLocalEntries(widget.branchId)
        .where((m) => (m['dateKey'] as String?) == datePart)
        .length;
    if (mounted) {
      setState(() {
        _nextSerial =
            '$datePart-${(localCount + 1).toString().padLeft(3, '0')}';
      });
    }
  }

  void focusAndFillCnic(String cnic) {
    final formatted = _formatCnic(cnic);
    cnicController.text = formatted;
    cnicController.selection =
        TextSelection.fromPosition(TextPosition(offset: formatted.length));
    _cnicFocusNode.requestFocus();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) triggerSearch();
    });
  }

  void triggerSearch() => _searchPatient();

  String _formatCnic(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9]'), '');
    final b = StringBuffer();
    for (int i = 0; i < d.length; i++) {
      b.write(d[i]);
      if ((i == 4 || i == 11) && i != d.length - 1) b.write('-');
    }
    return b.toString();
  }

  // ── Search ─────────────────────────────────────────────────────────────────
  Future<void> _searchPatient() async {
    final input = cnicController.text.trim();
    if (input.isEmpty) return;
    final looksLikeCnic  = RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(input);
    final looksLikePhone = RegExp(r'^03\d{9}$')
        .hasMatch(input.replaceAll(RegExp(r'[^0-9]'), ''));
    if (!looksLikeCnic && !looksLikePhone) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter valid CNIC (XXXXX-XXXXXXX-X) or phone (03xxxxxxxxx)'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() {
      _isLoading = true; _errorMessage = null; _patientData = null;
      _patientsList.clear(); _hasTokenToday = false;
      _guardianCnic = null; _guardianPatient = null;
    });
    try {
      final localResults = LocalStorageService.searchPatientsByCnicOrGuardian(
          input, branchId: widget.branchId);
      setState(() => _patientsList = localResults);
      if (localResults.isNotEmpty) {
        if (localResults.length == 1) await _selectPatient(localResults.first);
      } else {
        if (looksLikeCnic && widget.onPatientNotFound != null) {
          widget.onPatientNotFound!(input);
        } else {
          setState(() =>
              _errorMessage = 'No patient found with this CNIC/phone.');
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    final hasToken = await _tokenExistsToday(patient['patientId'] as String);
    if (mounted) {
      setState(() {
        _patientData   = patient;
        _hasTokenToday = hasToken;
        _patientsList.clear();
        _errorMessage  = null;
      });
    }
  }

  // ── Generate token ─────────────────────────────────────────────────────────
  Future<void> _generateToken({
    required String bp,
    required String temp,
    required String sugar,
    required String weight,
  }) async {
    if (_patientData == null || _nextSerial == null) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final patientId = _patientData!['patientId'] as String?;
      if (patientId == null || patientId.isEmpty) {
        throw Exception('Missing patientId');
      }
      final patientName =
          (_patientData!['name'] as String?)?.trim() ?? 'Patient';

      if (await _tokenExistsToday(patientId)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ This patient already has a token today!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ));
        setState(() => _isLoading = false);
        return;
      }

      final now     = DateTime.now();
      final dateKey = DateFormat('ddMMyy').format(now);
      // Global serial — count ALL queue types
      final localCount = LocalStorageService.getLocalEntries(widget.branchId)
          .where((m) => (m['dateKey'] as String?) == dateKey)
          .length;
      final serial =
          '$dateKey-${(localCount + 1).toString().padLeft(3, '0')}';

      // FIX: correct queue type from patient status
      final queueType =
          _resolveQueueType(_patientData!['status'] as String?);

      debugPrint(
          '[TokenScreen] status="${_patientData!['status']}" → queueType="$queueType" serial="$serial"');

      final vitals = <String, dynamic>{
        'bp': bp, 'temp': temp, 'tempUnit': 'C', 'weight': weight,
        'age':        _patientData!['age']        ?? 0,
        'gender':     _patientData!['gender']     ?? 'Unknown',
        'bloodGroup': _patientData!['bloodGroup'] ?? 'N/A',
        if (sugar.isNotEmpty) 'sugar': sugar,
      };

      final entryData = <String, dynamic>{
        'serial':        serial,
        'queueType':     queueType,   // always at top level
        'dateKey':       dateKey,
        'patientId':     patientId,
        'patientName':   patientName,
        'patientCnic': (_patientData!['cnic']?.toString().trim().isNotEmpty == true
            ? _patientData!['cnic'].toString().trim()
            : _patientData!['guardianCnic']?.toString().trim() ?? ''),
        'createdAt':     now.toIso8601String(),
        'status':        'waiting',
        'vitals':        vitals,
        'branchId':      widget.branchId,
        'createdBy':     widget.receptionistId,
        'createdByName': widget.receptionistName,
        if (_patientData!['cnic']?.toString().trim().isNotEmpty == true)
          'cnic': _patientData!['cnic'].toString().trim(),
        if (_patientData!['guardianCnic']?.toString().trim().isNotEmpty == true)
          'guardianCnic': _patientData!['guardianCnic'].toString().trim(),
      };

      // STEP 1 — Hive (instant, offline-safe)
      await Hive.box(LocalStorageService.entriesBox)
          .put('${widget.branchId}-$serial', entryData);

      // STEP 2 — LAN broadcast
      try {
        RealtimeManager().sendMessage({
          ...RealtimeEvents.payload(
            type: RealtimeEvents.saveEntry,
            branchId: widget.branchId,
            data: entryData,
          ),
          'queueType': queueType,
          'dateKey':   dateKey,
          'serial':    serial,
        });
      } catch (e) {
        debugPrint('[TokenScreen] LAN broadcast failed: $e');
      }

      _estimateNextSerial();

      if (mounted) {
        setState(() {
          _patientData = null; _patientsList.clear();
          cnicController.clear(); _hasTokenToday = true;
          _guardianCnic = null; _guardianPatient = null;
          _errorMessage = null; _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '✅ Token $serial issued to $patientName! [$queueType]'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
      }

      // STEP 3 — Firestore in background
      _syncToFirestoreInBackground(dateKey, queueType, serial, entryData);
    } catch (e, stack) {
      debugPrint('[TokenScreen] Token generation failed: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to issue token: $e'),
          backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // FIX: always attempts Firestore write; falls back to queue on any failure
  Future<void> _syncToFirestoreInBackground(
    String dateKey,
    String queueType,
    String serial,
    Map<String, dynamic> entryData,
  ) async {
    bool written = false;
    try {
      final conn   = await Connectivity().checkConnectivity();
      final online = !conn.contains(ConnectivityResult.none);
      if (online) {
        final dayRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('serials')
            .doc(dateKey);
        await dayRef
            .collection(queueType)
            .doc(serial)
            .set(entryData, SetOptions(merge: true));
        await dayRef.set(
          {'lastSerialNumber': int.tryParse(serial.split('-').last) ?? 0},
          SetOptions(merge: true),
        );
        debugPrint(
            '[TokenScreen] ✅ Firestore serials/$dateKey/$queueType/$serial');
        written = true;
      }
    } catch (e) {
      debugPrint('[TokenScreen] Firestore write failed: $e');
    }

    if (!written) {
      try {
        await LocalStorageService.enqueueSync({
          'type':      'save_entry',
          'branchId':  widget.branchId,
          'dateKey':   dateKey,
          'queueType': queueType,
          'serial':    serial,
          'data':      entryData,
        });
        debugPrint('[TokenScreen] 📥 Queued for sync: $queueType/$serial');
      } catch (e) {
        debugPrint('[TokenScreen] Enqueue failed: $e');
      }
    }
  }

  // ── Edit patient request ───────────────────────────────────────────────────
  Future<void> _requestEditPatient() async {
    if (_patientData == null) return;
    try {
      bool isChild = _patientData!['isAdult'] != true;
      final cnicCtrl = TextEditingController(
          text: isChild
              ? (_patientData!['guardianCnic']?.toString() ?? '')
              : (_patientData!['cnic']?.toString() ?? ''));
      final nameCtrl       = TextEditingController(text: _patientData!['name']?.toString()       ?? '');
      final phoneCtrl      = TextEditingController(text: _patientData!['phone']?.toString()      ?? '');
      final dobCtrl        = TextEditingController();
      final bloodGroupCtrl = TextEditingController(text: _patientData!['bloodGroup']?.toString() ?? 'N/A');
      String selectedStatus = _patientData!['status']?.toString() ?? 'Zakat';
      String selectedGender = _patientData!['gender']?.toString()  ?? 'Male';

      final dobValue = _patientData!['dob'];
      if (dobValue != null) {
        DateTime? birthDate;
        if (dobValue is Timestamp) {
          birthDate = dobValue.toDate();
        } else if (dobValue is String) {
          try { birthDate = DateFormat('dd-MM-yyyy').parse(dobValue); }
          catch (_) { try { birthDate = DateTime.parse(dobValue); } catch (_) {} }
        }
        if (birthDate != null) {
          dobCtrl.text = DateFormat('dd-MM-yyyy').format(birthDate);
        }
      }

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.green.shade200, width: 1)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            title: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.edit_note, color: Colors.green.shade700, size: 24),
                const SizedBox(width: 12),
                Text('Request Patient Edit',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        color: Colors.green.shade700,
                        fontSize: 16)),
              ]),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Patient Type',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.green)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: RadioListTile<bool>(
                            title: const Text('Adult',
                                style: TextStyle(fontSize: 13)),
                            dense: true, value: true,
                            groupValue: !isChild, activeColor: Colors.green,
                            onChanged: (v) => setStateDialog(() {
                              isChild = !(v!);
                              cnicCtrl.text = isChild
                                  ? (_patientData!['guardianCnic']?.toString() ?? '')
                                  : (_patientData!['cnic']?.toString() ?? '');
                            }),
                          )),
                          Expanded(child: RadioListTile<bool>(
                            title: const Text('Child',
                                style: TextStyle(fontSize: 13)),
                            dense: true, value: false,
                            groupValue: !isChild, activeColor: Colors.green,
                            onChanged: (v) => setStateDialog(() {
                              isChild = !(v!);
                              cnicCtrl.text = isChild
                                  ? (_patientData!['guardianCnic']?.toString() ?? '')
                                  : (_patientData!['cnic']?.toString() ?? '');
                            }),
                          )),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _editField(cnicCtrl, isChild ? 'Guardian CNIC' : 'CNIC',
                      Icons.badge, readOnly: true),
                  const SizedBox(height: 12),
                  _editField(nameCtrl,       'Full Name',        Icons.person),
                  const SizedBox(height: 12),
                  _editField(phoneCtrl,      'Phone (optional)', Icons.phone),
                  const SizedBox(height: 12),
                  _editField(dobCtrl,        'DOB (dd-MM-yyyy)', Icons.cake),
                  const SizedBox(height: 12),
                  _editField(bloodGroupCtrl, 'Blood Group',      Icons.bloodtype),
                  const SizedBox(height: 20),
                  _radioGroup('Status', ['Zakat', 'Non-Zakat', 'GMWF'],
                      selectedStatus,
                      (v) => setStateDialog(() => selectedStatus = v)),
                  const SizedBox(height: 16),
                  _radioGroup('Gender', ['Male', 'Female', 'Other'],
                      selectedGender,
                      (v) => setStateDialog(() => selectedGender = v)),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Cancel',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500)),
              ),
              ElevatedButton(
                onPressed: () async {
                  DateTime? dob;
                  if (dobCtrl.text.isNotEmpty &&
                      RegExp(r'^\d{2}-\d{2}-\d{4}$')
                          .hasMatch(dobCtrl.text)) {
                    final p = dobCtrl.text.split('-');
                    try {
                      dob = DateTime(int.parse(p[2]), int.parse(p[1]),
                          int.parse(p[0]));
                    } catch (_) {}
                  }
                  final proposed = {
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim().isNotEmpty
                        ? phoneCtrl.text.trim()
                        : null,
                    'status':     selectedStatus,
                    'bloodGroup': bloodGroupCtrl.text.trim().isNotEmpty
                        ? bloodGroupCtrl.text.trim()
                        : 'N/A',
                    'gender':  selectedGender,
                    'isAdult': !isChild,
                    if (dob != null) 'dob': Timestamp.fromDate(dob),
                  };
                  try {
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(widget.branchId)
                        .collection('edit_requests')
                        .add({
                      'requestType':     'patient_edit',
                      'status':          'pending',
                      'patientId':       _patientData!['patientId'],
                      'patientName':     _patientData!['name'],
                      'cnic':            _patientData!['cnic'],
                      'guardianCnic':    _patientData!['guardianCnic'],
                      'originalData':    Map<String, dynamic>.from(_patientData!),
                      'proposedData':    proposed,
                      'requestedBy':     widget.receptionistId,
                      'requestedByName': widget.receptionistName,
                      'requestedAt':     FieldValue.serverTimestamp(),
                      'targetRole':      'supervisor',
                    });
                    if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                        content: Text('✅ Edit request sent to supervisor!'),
                        backgroundColor: Colors.blue,
                      ));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('❌ Failed: $e'),
                          backgroundColor: Colors.redAccent));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
                child: const Text('Send Request',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint('Edit dialog error: $e\n$stack');
    }
  }

  Widget _radioGroup(
    String title,
    List<String> options,
    String current,
    void Function(String) onChanged,
  ) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.green,
          )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: options
                .map((o) => SizedBox(
                      width: 100,
                      child: RadioListTile<String>(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        title: Text(o, style: const TextStyle(fontSize: 13)),
                        value: o, groupValue: current, activeColor: Colors.green,
                        onChanged: (v) => onChanged(v!),
                      ),
                    ))
                .toList(),
          ),
        ]),
      );

  // ── Vitals dialog ──────────────────────────────────────────────────────────
  void _showVitalsDialog() {
    final systolicCtrl  = TextEditingController();
    final diastolicCtrl = TextEditingController();
    final tempCtrl      = TextEditingController();
    final sugarCtrl     = TextEditingController();
    final weightCtrl    = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.green.shade200, width: 1)),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          title: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.monitor_heart, color: Colors.green.shade700, size: 24),
              const SizedBox(width: 12),
              Text('Enter Vitals',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      color: Colors.green.shade700,
                      fontSize: 16)),
            ]),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: TextField(
                        controller: systolicCtrl, maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _vitalsDecoration('Systolic', Icons.favorite),
                      )),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('/',
                            style: TextStyle(
                                fontSize: 24, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                      ),
                      Expanded(child: TextField(
                        controller: diastolicCtrl, maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _vitalsDecoration('Diastolic', null),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  onChanged: (_) => _formatTemperatureAutoDot(tempCtrl),
                  decoration: _vitalsDecoration(
                      'Temperature (°C)', Icons.thermostat,
                      hint: 'e.g. 98.6'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sugarCtrl, maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration:
                      _vitalsDecoration('Blood Sugar (optional)', Icons.bloodtype),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weightCtrl, maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration:
                      _vitalsDecoration('Weight (kg)', Icons.monitor_weight),
                ),
              ],
            ),
          ),
          actions: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      final systolic  = systolicCtrl.text.trim();
                      final diastolic = diastolicCtrl.text.trim();
                      final temp      = tempCtrl.text.trim();
                      final sugar     = sugarCtrl.text.trim();
                      final weight    = weightCtrl.text.trim();
                      if (systolic.isEmpty || diastolic.isEmpty ||
                          temp.isEmpty || weight.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Please fill all required fields!'),
                            backgroundColor: Colors.red));
                        return;
                      }
                      final tempVal = double.tryParse(temp);
                      if (tempVal == null || tempVal < 80.0 || tempVal > 110.0) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Temperature must be between 80.0 and 110.0'),
                            backgroundColor: Colors.red));
                        return;
                      }
                      if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                      _generateToken(
                          bp:     '$systolic/$diastolic',
                          temp:   temp,
                          sugar:  sugar,
                          weight: weight);
                    },
                    icon: const Icon(Icons.local_hospital, size: 18),
                    label: const Text('Issue Token',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool readOnly = false,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl, readOnly: readOnly,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
            isDense: true,
            prefixIcon: Icon(icon, color: Colors.green, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.green, width: 2)),
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
      );

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenWidth    = MediaQuery.of(context).size.width;
    final isMobile       = screenWidth < 600;
    final containerWidth = isMobile ? double.infinity : 480.0;

    return Container(
      color: Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical:   isMobile ? 16 : 24),
          child: Container(
            width: containerWidth,
            padding: EdgeInsets.all(isMobile ? 18 : 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.shade200, width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.green.withOpacity(0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Stack(children: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                // Next serial badge
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 24,
                      vertical:   isMobile ? 8  : 10),
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: _teal.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Next Token: ${_nextSerial ?? 'Loading...'}',
                    style: TextStyle(
                        color: _teal, fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 16 : 20, letterSpacing: 0.4),
                  ),
                ),
                SizedBox(height: isMobile ? 14 : 20),
                Image.asset('assets/logo/gmwf.png',
                    height: isMobile ? 64 : 90),
                SizedBox(height: isMobile ? 10 : 16),
                Text('Issue Token',
                    style: TextStyle(
                        fontSize:   isMobile ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color:      Colors.green[900])),
                SizedBox(height: isMobile ? 18 : 28),

                // CNIC field
                TextField(
                  controller:   cnicController,
                  focusNode:    _cnicFocusNode,
                  maxLength:    15,
                  keyboardType: TextInputType.number,
                  cursorColor:  Colors.green[900],
                  onChanged: (v) {
                    final d = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (d.startsWith('03') && d.length <= 11) {
                      cnicController.value = TextEditingValue(
                          text: d,
                          selection: TextSelection.collapsed(offset: d.length));
                    } else if (d.length <= 13) {
                      final f = _formatCnic(d);
                      cnicController.value = TextEditingValue(
                          text: f,
                          selection: TextSelection.collapsed(offset: f.length));
                    }
                  },
                  onSubmitted: (_) => triggerSearch(),
                  style: TextStyle(color: Colors.green[900]),
                  decoration: InputDecoration(
                    labelText:   'Guardian CNIC or Phone',
                    counterText: '',
                    labelStyle:  const TextStyle(color: Colors.green),
                    prefixIcon:  const Icon(Icons.badge, color: Colors.green),
                    suffixIcon:  IconButton(
                        icon: const Icon(Icons.search, color: Colors.green),
                        onPressed: triggerSearch),
                    filled: true, fillColor: Colors.green[50],
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.green)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: Colors.green, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200)),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMessage!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13))),
                    ]),
                  ),

                if (_patientsList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._patientsList.map((p) {
                    final cnicInfo = _getDisplayCnicInfo(p);
                    return Card(
                      color: Colors.green[50],
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        dense: isMobile,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 10 : 16,
                            vertical:   isMobile ? 2  : 8),
                        title: Text(p['name'] as String? ?? '',
                            style: const TextStyle(
                                color:      Colors.green,
                                fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${cnicInfo.label}: ${cnicInfo.cnic}',
                                style: const TextStyle(
                                    color: Colors.green, fontSize: 12)),
                            Text('Phone: ${p['phone'] ?? '-'}',
                                style: const TextStyle(
                                    color: Colors.green, fontSize: 12)),
                          ],
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[500],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              minimumSize: const Size(80, 40)),
                          onPressed: () async => await _selectPatient(p),
                          child: const Text('Select',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                if (_patientData != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(
                              _patientData!['name'] as String? ?? '',
                              style: TextStyle(
                                  fontSize:   isMobile ? 17 : 20,
                                  color:      Colors.green,
                                  fontWeight: FontWeight.bold),
                            )),
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Colors.orange, size: 24),
                              tooltip: 'Request Edit',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _requestEditPatient,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          _infoBadge(Icons.badge, () {
                            final i = _getDisplayCnicInfo(_patientData!);
                            return '${i.label}: ${i.cnic}';
                          }()),
                          _infoBadge(Icons.phone,
                              'Phone: ${_patientData!['phone'] ?? '-'}'),
                          _infoBadge(Icons.category,
                              '${_resolveQueueType(_patientData!['status'] as String?)}'),
                        ]),
                        if (_hasTokenToday) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.red.shade300)),
                            child: const Row(children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.red, size: 22),
                              SizedBox(width: 8),
                              Expanded(child: Text(
                                'Token already issued today for this patient',
                                style: TextStyle(
                                    color:      Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize:   13),
                              )),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                _hasTokenToday ? null : _showVitalsDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hasTokenToday
                                  ? Colors.grey[400]
                                  : Colors.green[500],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                  vertical: isMobile ? 12 : 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.local_hospital),
                            label: Text(
                              _hasTokenToday
                                  ? 'Token Already Issued'
                                  : 'Enter Vitals & Issue Token',
                              style: TextStyle(
                                  fontSize: isMobile ? 14 : 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                SizedBox(height: isMobile ? 16 : 24),
                if (_isLoading)
                  const Center(
                      child: CircularProgressIndicator(
                          color: Colors.green)),
              ]),

              if (_isRefreshing)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 13, height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white)),
                      SizedBox(width: 6),
                      Text('Updating...',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _infoBadge(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.green[700]),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(color: Colors.green[800], fontSize: 12)),
        ],
      );

  ({String cnic, String label}) _getDisplayCnicInfo(
      Map<String, dynamic> patient) {
    final ownCnic      = patient['cnic']?.toString().trim();
    final guardianCnic = patient['guardianCnic']?.toString().trim();
    if (ownCnic != null && ownCnic.isNotEmpty)
      return (cnic: ownCnic, label: 'CNIC');
    if (guardianCnic != null && guardianCnic.isNotEmpty)
      return (cnic: guardianCnic, label: 'Guardian CNIC');
    return (cnic: '-', label: 'CNIC');
  }

  InputDecoration _vitalsDecoration(String label, IconData? icon,
          {String? hint}) =>
      InputDecoration(
        labelText: label, hintText: hint, counterText: '', isDense: true,
        prefixIcon: icon != null
            ? Icon(icon, color: Colors.green, size: 20)
            : null,
        filled: true, fillColor: Colors.white,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10))),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Colors.green, width: 2)),
      );

  void _formatTemperatureAutoDot(TextEditingController controller) {
    final text    = controller.text;
    if (text.isEmpty || (text.contains('.') && text.endsWith('.'))) return;
    final cleaned = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) { controller.clear(); return; }
    String formatted;
    if (cleaned.startsWith('10')) {
      formatted = cleaned.length <= 3
          ? cleaned
          : '${cleaned.substring(0, 3)}.${cleaned.substring(3, cleaned.length.clamp(3, 4))}';
    } else {
      formatted = cleaned.length <= 2
          ? cleaned
          : '${cleaned.substring(0, 2)}.${cleaned.substring(2, cleaned.length.clamp(2, 3))}';
    }
    if (formatted != text) {
      controller.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length));
    }
  }
}