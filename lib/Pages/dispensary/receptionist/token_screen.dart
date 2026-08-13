// lib/pages/dispensary/receptionist/token_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'package:gmwf/services/local_storage_service.dart';
import 'package:gmwf/services/camp_session_service.dart';
import 'package:gmwf/services/serials_service.dart';
import 'package:gmwf/realtime/realtime_manager.dart';
import 'package:gmwf/realtime/realtime_events.dart';

class TokenScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String receptionistName;
  final String? dispensaryId;
  final Function(String cnic)? onPatientNotFound;
  final String? initialCnic;

  const TokenScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
    required this.receptionistName,
    this.dispensaryId,
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
  // ignore: unused_field
  String? _guardianCnic;
  // ignore: unused_field
  Map<String, dynamic>? _guardianPatient;
  String? _errorMessage;
  Map<String, dynamic>? _medicineRestriction;
  bool _isExceptionPending = false;

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  String? get _resolvedDispensaryId {
    final active = CampSessionService.getActiveCamp();
    if (active != null && active.isNotEmpty) return active;
    if (widget.dispensaryId != null && widget.dispensaryId!.trim().isNotEmpty) {
      return widget.dispensaryId!.trim().toLowerCase();
    }
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final userData = Hive.box('app_settings').get('user_data');
        if (userData is Map && userData['dispensaryId'] != null) {
          final d = userData['dispensaryId'].toString().trim();
          if (d.isNotEmpty && d.toLowerCase() != 'all') return d.toLowerCase();
        }
      }
    } catch (_) {}
    return null;
  }

  static const Color _teal  = Color(0xFF00695C);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CampSessionService.activeCampNotifier.addListener(_onActiveCampChanged);
    _estimateNextSerial();

    if (widget.initialCnic != null && widget.initialCnic!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusAndFillCnic(widget.initialCnic!);
      });
    }

    _realtimeSub = RealtimeManager().messageStream.listen((message) async {
      final type = message['event_type'] as String?;
      final data = message['data'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      final eventBranch = data['branchId']?.toString().toLowerCase().trim();
      final myBranch    = widget.branchId.toLowerCase().trim();
      if (eventBranch != null && eventBranch != myBranch) return;
      if (type == RealtimeEvents.saveEntry ||
          type == 'token_created' ||
          type == RealtimeEvents.savePrescription) {
        _instantRefresh();
      } else if (type == 'token_reversal_approved') {
        if (_patientData?['patientId'] != null) {
          _checkIfTokenStillExists(_patientData!['patientId'] as String);
        }
        _instantRefresh();
      } else if (type == RealtimeEvents.tokenExceptionApproved) {
        final patientId = data['patientId'] as String?;
        final reason    = data['reason'] as String? ?? 'No reason provided';

        // Match against current patient (either patientId or cleaned CNIC)
        final myPId       = _patientData?['patientId']?.toString();
        final myCleanCnic = _getRestrictionId(_patientData ?? {});

        if (patientId != null && (myPId == patientId || myCleanCnic == patientId)) {
          // ── FIRESTORE FIX: Clear local restriction immediately on approval ──
          await LocalStorageService.clearMedicineRestriction(widget.branchId, patientId);

          setState(() {
            _hasTokenToday = false;
          });
          _checkMedicineRestriction(_patientData!);
          _instantRefresh();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Flushbar(
                title: '✅ Token Exception Approved',
                message: 'Reason: $reason',
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 4),
                flushbarPosition: FlushbarPosition.TOP,
                margin: const EdgeInsets.all(12),
                borderRadius: BorderRadius.circular(12),
                icon: const Icon(Icons.check_circle, color: Colors.white),
              ).show(context);
            }
          });
        }
      }
    });
  }

  void _onActiveCampChanged() {
    if (mounted) {
      _estimateNextSerial();
      setState(() {});
    }
  }

  DateTime? _lastActiveTime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastActiveTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _instantRefresh();
      final now = DateTime.now();
      if (_lastActiveTime == null || now.difference(_lastActiveTime!).inMinutes >= 10) {
        _showDispensarySafetyConfirmation();
      }
      _lastActiveTime = now;
    }
  }

  void _showDispensarySafetyConfirmation() {
    final activeCamp = _resolvedDispensaryId;
    final label = activeCamp != null && activeCamp.isNotEmpty
        ? CampSessionService.getCampLabel(activeCamp)
        : 'General Branch';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.teal),
            SizedBox(width: 10),
            Text('Dispensary Safety Check'),
          ],
        ),
        content: Text(
          'You are issuing tokens for $label.\n\nIs this the correct active dispensary desk?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCampSelector();
            },
            child: const Text('Switch Dispensary'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showCampSelector() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select Active Dispensary Desk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...CampSessionService.allCampsList.map((c) => ListTile(
                    title: Text(c['label']!),
                    onTap: () async {
                      await CampSessionService.setActiveCamp(c['id']!);
                      if (mounted) setState(() {});
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    CampSessionService.activeCampNotifier.removeListener(_onActiveCampChanged);
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSub?.cancel();
    cnicController.dispose();
    _cnicFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TokenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCnic != null &&
        widget.initialCnic!.isNotEmpty &&
        widget.initialCnic != oldWidget.initialCnic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusAndFillCnic(widget.initialCnic!);
      });
    }
  }

  // ── Queue-type resolver ────────────────────────────────────────────────────
  /// Canonical resolver — mirrors SyncService.resolveQueueType exactly.
  /// Input can be patient status ('Zakat', 'Non-Zakat', 'GMWF') or any variant.
  static String _resolveQueueType(String? rawStatus) {
    final s = (rawStatus ?? '').toLowerCase().trim();
    if (s.isEmpty) return 'zakat';
    if (s == 'non-zakat' || s == 'non zakat' || s == 'nonzakat' ||
        s == 'non_zakat' || s.startsWith('non')) {
      return 'non-zakat';
    }
    if (s == 'gmwf' || s == 'gm wf' || s == 'gm-wf' || s == 'gm_wf') return 'gmwf';
    if (s == 'zakat') return 'zakat';
    debugPrint('[TokenScreen] ⚠️ Unknown patient status "$rawStatus" — defaulting to zakat');
    return 'zakat';
  }

  // ── Refresh ────────────────────────────────────────────────────────────────
  Future<void> _instantRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await LocalStorageService.downloadTodayTokens(widget.branchId);
      // ── FIRESTORE FIX: always refresh restrictions on every update ────────
      await LocalStorageService.downloadMedicineRestrictions(widget.branchId);
      _estimateNextSerial();
      if (_patientData?['patientId'] != null) {
        final patientId = _patientData!['patientId'] as String;
        final stillHas = await _tokenExistsToday(patientId);
        setState(() => _hasTokenToday = stillHas);
        _checkMedicineRestriction(_patientData!);
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
    if (_patientData != null) _checkMedicineRestriction(_patientData!);
  }

  /// Checks restriction from local Hive (already refreshed from Firestore
  /// by the caller — _selectPatient or _instantRefresh).
  void _checkMedicineRestriction(Map<String, dynamic> patient) {
    if (!mounted) return;
    final rId = _getRestrictionId(patient);

    // Individual-based check: uses patientId (CNIC for adults, CNIC_child_Name for kids)
    final restriction = LocalStorageService.isPatientBlockedByMedicine(widget.branchId, rId);

    setState(() {
      _medicineRestriction = restriction;
    });
  }

  String _getRestrictionId(Map<String, dynamic> p) {
    // Individual identification: uses patientId (CNIC for adults, CNIC_child_Name for kids)
    return p['patientId']?.toString() ?? p['id']?.toString() ?? '';
  }

  Future<bool> _tokenExistsToday(String patientId) async {
    final datePart   = DateFormat('ddMMyy').format(DateTime.now());
    final activeCamp = _resolvedDispensaryId;
    final entries    = LocalStorageService.getLocalEntries(widget.branchId, dispensaryId: activeCamp, filterByCamp: true);
    return entries.any((e) =>
        e['patientId'] == patientId && (e['dateKey'] as String?) == datePart);
  }

  void _estimateNextSerial() {
    final datePart   = DateFormat('ddMMyy').format(DateTime.now());
    final activeCamp = _resolvedDispensaryId;
    final localCount = LocalStorageService.getLocalEntries(widget.branchId, dispensaryId: activeCamp, filterByCamp: true)
        .where((m) => (m['dateKey'] as String?) == datePart)
        .length;
    final dispTag = CampSessionService.getDispensaryKeyword(activeCamp);
    final serialStr = activeCamp != null && activeCamp.isNotEmpty && activeCamp != 'all'
        ? '$datePart-$dispTag-${(localCount + 1).toString().padLeft(3, '0')}'
        : '$datePart-${(localCount + 1).toString().padLeft(3, '0')}';
    if (mounted) {
      setState(() {
        _nextSerial = serialStr;
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
      var localResults = LocalStorageService.searchPatientsByCnicOrGuardian(
          input, branchId: widget.branchId);
      if (localResults.isEmpty) {
        try {
          await LocalStorageService.downloadAllPatients(widget.branchId);
          localResults = LocalStorageService.searchPatientsByCnicOrGuardian(
              input, branchId: widget.branchId);
        } catch (e) {
          debugPrint('[TokenScreen] Firestore fallback patient fetch failed: $e');
        }
      }
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

  /// Selects a patient and checks medicine restriction.
  /// Downloads restrictions from Firestore first so internet-only terminals
  /// always have the latest data before the block check.
  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    // ── FIRESTORE FIX: pull fresh restrictions before checking ────────────
    try {
      await LocalStorageService.downloadMedicineRestrictions(widget.branchId);
    } catch (e) {
      debugPrint('[TokenScreen] downloadMedicineRestrictions failed: $e');
    }

    final hasToken = await _tokenExistsToday(patient['patientId'] as String);
    if (mounted) {
      setState(() {
        _patientData   = patient;
        _hasTokenToday = hasToken;
        _patientsList.clear();
        _errorMessage  = null;
      });
      _checkMedicineRestriction(patient);
    }
  }

  // ── Generate token ─────────────────────────────────────────────────────────
  Future<void> _generateToken({
    required String bp,
    required String temp,
    required String sugar,
    required String weight,
    int suggestedDays = 1,
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

      // ── FIRESTORE FIX: refresh restrictions one final time at token issue
      // to catch any race conditions between search and issue ────────────────
      try {
        await LocalStorageService.downloadMedicineRestrictions(widget.branchId);
      } catch (e) {
        debugPrint('[TokenScreen] Pre-generate restriction refresh failed: $e');
      }

      _checkMedicineRestriction(_patientData!);
      final restriction = _medicineRestriction;
      if (restriction != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ Patient blocked. Medicine expires in ${restriction['remainingDays']} days.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ));
        }
        setState(() => _isLoading = false);
        return;
      }

      final now = DateTime.now();
      final shiftInfo = CampSessionService.resolveShiftAndDateKey(now);
      final dateKey = shiftInfo.dateKey;
      final session = shiftInfo.session;
      final activeCamp = _resolvedDispensaryId;
      final dispTag = CampSessionService.getDispensaryKeyword(activeCamp);

      final rawStatus = _patientData!['status']?.toString();
      final queueType = _resolveQueueType(rawStatus);

      String serial = '';
      Map<String, dynamic> entryData = {};

      final conn = await Connectivity().checkConnectivity();
      final isOnline = !conn.contains(ConnectivityResult.none);

      final vitals = <String, dynamic>{
        'bp': bp.isNotEmpty ? bp : 'N/A',
        'temp': temp.isNotEmpty ? temp : 'N/A',
        'tempUnit': 'C',
        'weight': weight.isNotEmpty ? weight : 'N/A',
        'age':        _patientData!['age']        ?? 0,
        'gender':     _patientData!['gender']     ?? 'Unknown',
        'bloodGroup': _patientData!['bloodGroup'] ?? 'N/A',
        if (sugar.isNotEmpty) 'sugar': sugar,
        'receptionistVitals': {
          'bp': bp.isNotEmpty ? bp : 'N/A',
          'temp': temp.isNotEmpty ? temp : 'N/A',
          'weight': weight.isNotEmpty ? weight : 'N/A',
          if (sugar.isNotEmpty) 'sugar': sugar,
          'addedBy': widget.receptionistName,
          'addedById': widget.receptionistId,
          'addedAt': now.toIso8601String(),
        },
        'auditTrail': [
          {
            'role': 'receptionist',
            'action': 'Added initial vitals',
            'by': widget.receptionistName,
            'byId': widget.receptionistId,
            'at': now.toIso8601String(),
            'bp': bp.isNotEmpty ? bp : 'N/A',
            'temp': temp.isNotEmpty ? temp : 'N/A',
            'weight': weight.isNotEmpty ? weight : 'N/A',
            if (sugar.isNotEmpty) 'sugar': sugar,
          }
        ],
      };

      final baseData = <String, dynamic>{
        'queueType':     queueType,
        'dateKey':       dateKey,
        'session':       session,
        'patientId':     patientId,
        'patientName':   patientName,
        'patientCnic': (_patientData!['cnic']?.toString().trim().isNotEmpty == true
            ? _patientData!['cnic'].toString().trim()
            : _patientData!['guardianCnic']?.toString().trim() ?? ''),
        'createdAt':     now.toIso8601String(),
        'status':        'waiting',
        'vitals':        vitals,
        'branchId':      widget.branchId,
        'dispensaryTag': dispTag,
        if (_resolvedDispensaryId != null && _resolvedDispensaryId!.isNotEmpty)
          'dispensaryId': _resolvedDispensaryId,
        'createdBy':     widget.receptionistId,
        'createdByName': widget.receptionistName,
        'suggestedDays': suggestedDays,
        if (_patientData!['cnic']?.toString().trim().isNotEmpty == true)
          'cnic': _patientData!['cnic'].toString().trim(),
        if (_patientData!['guardianCnic']?.toString().trim().isNotEmpty == true)
          'guardianCnic': _patientData!['guardianCnic'].toString().trim(),
      };

      if (isOnline) {
        try {
          final txResult = await issueAtomicSerialTransaction(
            branchId: widget.branchId,
            dispensaryTag: dispTag,
            queueType: queueType,
            tokenData: baseData,
            time: now,
          );
          serial = txResult['serial'] as String;
          entryData = Map<String, dynamic>.from(txResult['entryData'] as Map);
        } catch (e) {
          debugPrint('[TokenScreen] Transaction failed, falling back to temp offline serial: $e');
        }
      }

      if (serial.isEmpty) {
        // Offline fallback — prefixed with X- to distinguish from online serials
        final localCount = LocalStorageService.getLocalEntries(widget.branchId, dispensaryId: activeCamp, filterByCamp: true)
            .where((m) => (m['dateKey'] as String?) == dateKey)
            .length;
        final seqPadded = (localCount + 1).toString().padLeft(3, '0');
        serial = 'X-$dateKey-$dispTag-$seqPadded';
        entryData = {
          ...baseData,
          'serial': serial,
          'isTempSerial': true,
          'pendingSync': true,
        };
      }

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

  // ── Firestore sync — always attempts direct write, queues on failure ───────
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
                    final reqId = 'req_patient_edit_${widget.receptionistId}_${DateTime.now().millisecondsSinceEpoch}';
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(widget.branchId)
                        .collection('edit_requests')
                        .doc(reqId)
                        .set({
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
    int suggestedDays   = 1;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF041C16) : Colors.white;
    final titleBg = isDark ? const Color(0xFF072B21) : Colors.green.shade50;
    final titleTextColor = isDark ? const Color(0xFF34D399) : Colors.green.shade700;
    final sectionBg = isDark ? const Color(0xFF02140F) : Colors.grey.shade50;
    final sectionBorder = isDark ? const Color(0xFF0D382B) : Colors.grey.shade300;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final labelColor = isDark ? const Color(0xFFA7F3D0) : Colors.grey.shade700;
    final dialogBorder = isDark ? const Color(0xFF10B981) : Colors.green.shade200;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: dialogBorder, width: 1.5)),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          title: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: titleBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.monitor_heart, color: titleTextColor, size: 24),
              const SizedBox(width: 12),
              Text(
                'Enter Vitals',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: titleTextColor,
                  fontSize: 16,
                ),
              ),
            ]),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: sectionBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sectionBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blood Pressure',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: labelColor),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: TextField(
                              controller: systolicCtrl, maxLength: 3,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                              decoration: _vitalsDecoration('Systolic', Icons.favorite, isDark),
                            )),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('/',
                                  style: TextStyle(
                                      fontSize: 24, color: titleTextColor, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(child: TextField(
                              controller: diastolicCtrl, maxLength: 3,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                              decoration: _vitalsDecoration('Diastolic', null, isDark),
                            )),
                          ],
                        ),
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
                    style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: _vitalsDecoration(
                        'Temperature (°C)',
                        Icons.thermostat,
                        isDark,
                        hint: 'e.g. 98.6'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sugarCtrl, maxLength: 3,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration:
                        _vitalsDecoration('Blood Sugar (optional)', Icons.bloodtype, isDark),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weightCtrl, maxLength: 3,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration:
                        _vitalsDecoration('Weight (kg)', Icons.monitor_weight, isDark),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Days Suggestion (asked by patient):',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: titleTextColor),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [1, 2, 3].map((d) {
                      final isSelected = suggestedDays == d;
                      final itemBg = isSelected
                          ? _teal
                          : (isDark ? const Color(0xFF02140F) : Colors.green.shade50);
                      final itemBorder = isSelected
                          ? _teal
                          : (isDark ? const Color(0xFF0D382B) : Colors.green.shade200);

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: d < 3 ? 8 : 0),
                          child: InkWell(
                            onTap: () => setStateDialog(() => suggestedDays = d),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: itemBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: itemBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$d Day${d > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? const Color(0xFF34D399) : _teal),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sectionBg,
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
                            color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
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

                      if (temp.isNotEmpty) {
                        final tempVal = double.tryParse(temp);
                        if (tempVal == null || tempVal < 80.0 || tempVal > 110.0) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Temperature must be between 80.0 and 110.0'),
                              backgroundColor: Colors.red));
                          return;
                        }
                      }

                      final bpString = (systolic.isNotEmpty && diastolic.isNotEmpty)
                          ? '$systolic/$diastolic'
                          : (systolic.isNotEmpty ? systolic : '');

                      if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                      _generateToken(
                          bp:     bpString,
                          temp:   temp,
                          sugar:  sugar,
                          weight: weight,
                          suggestedDays: suggestedDays);
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

  Future<void> _requestTokenException() async {
    if (_patientData == null) return;
    setState(() => _isLoading = true);

    try {
      final rId = _getRestrictionId(_patientData!);
      final pId = _patientData!['patientId']?.toString() ?? '';

      final matchedId = (LocalStorageService.isPatientBlockedByMedicine(widget.branchId, rId) != null)
          ? rId : pId;

      final patientName = _patientData!['name']?.toString() ?? 'Unknown';

      final requestData = <String, dynamic>{
        'requestType':     'token_exception',
        'status':          'pending',
        'patientId':       matchedId,
        'patientName':     patientName,
        'cnic':            _patientData!['cnic'],
        'guardianCnic':    _patientData!['guardianCnic'],
        'restriction':     _medicineRestriction,
        'requestedBy':     widget.receptionistId,
        'requestedByName': widget.receptionistName,
        'requestedAt':     DateTime.now().toIso8601String(),
        'targetRole':      'doctor',
        'branchId':        widget.branchId,
      };

      final docId = 'req_exception_${widget.receptionistId}_${DateTime.now().millisecondsSinceEpoch}';

      try {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('edit_requests')
            .doc(docId)
            .set({
          ...requestData,
          'requestedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[TokenScreen] Firestore offline — using generated ID: $docId');
      }

      await LocalStorageService.enqueueSync({
        'type':      'save_token_exception_request',
        'branchId':  widget.branchId,
        'requestId': docId,
        'data':      requestData,
      });

      RealtimeManager().sendMessage({
        ...RealtimeEvents.payload(
          type:     RealtimeEvents.tokenExceptionRequest,
          branchId: widget.branchId,
          data: {
            'requestId':   docId,
            'patientId':   matchedId,
            'patientName': patientName,
            'restriction': _medicineRestriction,
            'branchId':    widget.branchId,
          },
        ),
      });

      setState(() {
        _isExceptionPending = true;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Exception request sent to Doctor!'),
          backgroundColor: Colors.blue,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Failed to send request: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final screenWidth    = MediaQuery.of(context).size.width;
    final isMobile       = screenWidth < 600;
    final containerWidth = isMobile ? double.infinity : 480.0;
    final isDark = _isDark;

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
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark ? const Color(0xFF334155) : Colors.green.shade200,
                  width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: isDark ? Colors.black26 : Colors.green.withValues(alpha: 0.07),
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
                    color: isDark ? const Color(0xFF0F766E).withValues(alpha: 0.2) : _teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: isDark ? const Color(0xFF0F766E) : _teal.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Next Token: ${_nextSerial ?? 'Loading...'}',
                    style: TextStyle(
                        color: isDark ? const Color(0xFF38BDF8) : _teal, fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 16 : 20, letterSpacing: 0.4),
                  ),
                ),
                SizedBox(height: isMobile ? 14 : 20),
                Image.asset('assets/logo/gmwf-1.webp',
                    height: isMobile ? 64 : 90),
                SizedBox(height: isMobile ? 10 : 16),
                Text('Issue Token',
                    style: TextStyle(
                        fontSize:   isMobile ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color:      isDark ? Colors.white : Colors.green[900])),
                SizedBox(height: isMobile ? 18 : 28),

                // CNIC field
                TextField(
                  controller:   cnicController,
                  focusNode:    _cnicFocusNode,
                  maxLength:    15,
                  keyboardType: TextInputType.number,
                  cursorColor:  isDark ? const Color(0xFF38BDF8) : Colors.green[900],
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
                  style: TextStyle(color: isDark ? Colors.white : Colors.green[900]),
                  decoration: InputDecoration(
                    labelText:   'Guardian CNIC or Phone',
                    counterText: '',
                    labelStyle:  TextStyle(color: isDark ? const Color(0xFF94A3B8) : Colors.green),
                    prefixIcon:  Icon(Icons.badge, color: isDark ? const Color(0xFF38BDF8) : Colors.green),
                    suffixIcon:  IconButton(
                        icon: Icon(Icons.search, color: isDark ? const Color(0xFF38BDF8) : Colors.green),
                        onPressed: triggerSearch),
                    filled: true, fillColor: isDark ? const Color(0xFF334155) : Colors.green[50],
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? const Color(0xFF475569) : Colors.green)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: isDark ? const Color(0xFF38BDF8) : Colors.green, width: 2)),
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
                              _resolveQueueType(_patientData!['status'] as String?)),
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
                        if (_medicineRestriction != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange.shade300)),
                            child: Column(
                              children: [
                                Row(children: [
                                  Icon(Icons.medication_liquid_outlined,
                                      color: Colors.orange.shade800, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(
                                    _medicineRestriction!['isLastDay'] == true
                                      ? 'Restricted: Medicine expires TODAY'
                                      : 'Restricted: Medicine expires in ${_medicineRestriction!['remainingDays']} days',
                                    style: TextStyle(
                                        color:      Colors.orange.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize:   13),
                                  )),
                                ]),
                                const SizedBox(height: 10),
                                ElevatedButton.icon(
                                  onPressed: (_isLoading || _isExceptionPending) ? null : _requestTokenException,
                                  icon: Icon(
                                    _isExceptionPending ? Icons.hourglass_top : Icons.emergency_share_outlined,
                                    size: 18),
                                  label: Text(_isExceptionPending ? 'Exception Pending...' : 'Request Exception'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isExceptionPending ? Colors.orange.shade300 : Colors.orange.shade700,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 40),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                (_hasTokenToday || _medicineRestriction != null) ? null : _showVitalsDialog,
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
                                  : (_medicineRestriction != null
                                      ? 'Medicine Restriction Active'
                                      : 'Enter Vitals & Issue Token'),
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
    if (ownCnic != null && ownCnic.isNotEmpty) {
      return (cnic: ownCnic, label: 'CNIC');
    }
    if (guardianCnic != null && guardianCnic.isNotEmpty) {
      return (cnic: guardianCnic, label: 'Guardian CNIC');
    }
    return (cnic: '-', label: 'CNIC');
  }

  InputDecoration _vitalsDecoration(String label, IconData? icon, bool isDark,
          {String? hint}) =>
      InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF064E3B)),
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
        counterText: '',
        isDense: true,
        prefixIcon: icon != null
            ? Icon(icon, color: isDark ? const Color(0xFF34D399) : Colors.green.shade700, size: 20)
            : null,
        filled: true,
        fillColor: isDark ? const Color(0xFF02140F) : Colors.white,
        border: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: isDark ? const Color(0xFF0D382B) : Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: isDark ? const Color(0xFF0D382B) : Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: isDark ? const Color(0xFF10B981) : Colors.green.shade700, width: 2)),
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
