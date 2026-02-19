// lib/pages/token_screen.dart - COMPLETE FIXED VERSION
// FIXES:
// 1. Added patient edit button back
// 2. Improved token generation flow
// 3. Better realtime broadcasting
// 4. Proper local save + LAN broadcast

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../services/local_storage_service.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_events.dart';

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
  State<TokenScreen> createState() => TokenScreenState();
}

class TokenScreenState extends State<TokenScreen> with WidgetsBindingObserver {
  final TextEditingController cnicController = TextEditingController();
  final FocusNode _cnicFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _nextSerial;
  Map<String, dynamic>? _patientData;
  List<Map<String, dynamic>> _patientsList = [];
  bool _hasTokenToday = false;
  String? _guardianCnic;
  Map<String, dynamic>? _guardianPatient;
  String? _errorMessage;

  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

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

      final eventBranch = data['branchId']?.toString()?.toLowerCase()?.trim();
      final myBranch = widget.branchId.toLowerCase().trim();

      if (eventBranch != null && eventBranch != myBranch) return;

      debugPrint("[TokenScreen] Realtime: $type | branch=$eventBranch | serial=${data['serial'] ?? 'unknown'}");

      if (type == RealtimeEvents.saveEntry || type == 'token_created') {
        print("[TokenScreen] New token via realtime → refreshing serial & queue");
        _instantRefresh();
      } else if (type == 'token_reversal_approved') {
        if (_patientData != null && _patientData!['patientId'] != null) {
          _checkIfTokenStillExists(_patientData!['patientId'] as String);
        }
        _instantRefresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _instantRefresh();
    }
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
    if (widget.initialCnic != null && widget.initialCnic != oldWidget.initialCnic) {
      focusAndFillCnic(widget.initialCnic!);
    }
  }

  Future<void> _instantRefresh() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      debugPrint("[TokenScreen] Instant refresh triggered");
      await LocalStorageService.downloadTodayTokens(widget.branchId);
      _estimateNextSerial();

      if (_patientData != null && _patientData!['patientId'] != null) {
        final stillHas = await _tokenExistsToday(_patientData!['patientId'] as String);
        setState(() => _hasTokenToday = stillHas);
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("[TokenScreen] Instant refresh failed: $e");
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _checkIfTokenStillExists(String patientId) async {
    final stillHas = await _tokenExistsToday(patientId);
    if (mounted) {
      setState(() => _hasTokenToday = stillHas);
    }
  }

  Future<bool> _tokenExistsToday(String patientId) async {
    final datePart = DateFormat('ddMMyy').format(DateTime.now());
    final entries = LocalStorageService.getLocalEntries(widget.branchId);
    return entries.any((e) =>
        e['patientId'] == patientId &&
        (e['dateKey'] as String?) == datePart);
  }

  void _estimateNextSerial() {
    final datePart = DateFormat('ddMMyy').format(DateTime.now());
    final localCount = LocalStorageService.getLocalEntries(widget.branchId)
        .where((m) => (m['dateKey'] as String?) == datePart)
        .length;

    if (mounted) {
      setState(() {
        _nextSerial = '$datePart-${(localCount + 1).toString().padLeft(3, '0')}';
      });
    }

    debugPrint('[TokenScreen] Next serial estimated from local: $_nextSerial (${localCount} tokens today)');
  }

  void focusAndFillCnic(String cnic) {
    final formatted = _formatCnic(cnic);
    cnicController.text = formatted;
    cnicController.selection = TextSelection.fromPosition(
      TextPosition(offset: formatted.length),
    );
    _cnicFocusNode.requestFocus();

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) triggerSearch();
    });
  }

  void triggerSearch() {
    _searchPatient();
  }

  String _formatCnic(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9]'), '');
    final b = StringBuffer();
    for (int i = 0; i < d.length; i++) {
      b.write(d[i]);
      if (i == 4 || i == 11) if (i != d.length - 1) b.write('-');
    }
    return b.toString();
  }

  Future<void> _searchPatient() async {
    final input = cnicController.text.trim();
    if (input.isEmpty) return;

    final looksLikeCnic = RegExp(r'^\d{5}-\d{7}-\d{1}$').hasMatch(input);
    final looksLikePhone = RegExp(r'^03\d{9}$').hasMatch(input.replaceAll(RegExp(r'[^0-9]'), ''));

    if (!looksLikeCnic && !looksLikePhone) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Enter valid CNIC (XXXXX-XXXXXXX-X) or phone (03xxxxxxxxx)"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _patientData = null;
        _patientsList.clear();
        _hasTokenToday = false;
        _guardianCnic = null;
        _guardianPatient = null;
      });
    }

    try {
      final localResults = LocalStorageService.searchPatientsByCnicOrGuardian(
        input,
        branchId: widget.branchId,
      );

      if (mounted) {
        setState(() {
          _patientsList = localResults;
        });

        if (localResults.isNotEmpty) {
          if (localResults.length == 1) {
            await _selectPatient(localResults.first);
          }
        } else {
          if (looksLikeCnic && widget.onPatientNotFound != null) {
            widget.onPatientNotFound!(input);
          } else {
            if (mounted) {
              setState(() {
                _errorMessage = "No patient found with this CNIC/phone in local records.";
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("No patient found in local records"),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TokenScreen] Search error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = "Search failed: $e";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Search error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    final hasToken = await _tokenExistsToday(patient['patientId'] as String);
    if (mounted) {
      setState(() {
        _patientData = patient;
        _hasTokenToday = hasToken;
        _patientsList.clear();
        _errorMessage = null;
      });
    }
  }

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
        throw Exception("Missing or invalid patientId");
      }

      String patientName = (_patientData!['name'] as String?)?.trim() ?? 'Patient';
      
      final alreadyHas = await _tokenExistsToday(patientId);
      if (alreadyHas) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ This patient already has a token today!"),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyy').format(now);
      
      final localCount = LocalStorageService.getLocalEntries(widget.branchId)
          .where((m) => (m['dateKey'] as String?) == dateKey)
          .length;
      final serial = '$dateKey-${(localCount + 1).toString().padLeft(3, '0')}';
      
      debugPrint('[TokenScreen] Generating token: $serial (current count: $localCount)');

      String rawStatus = (_patientData!['status'] as String?)?.toLowerCase().trim() ?? 'zakat';
      String queueType;
      switch (rawStatus) {
        case 'non-zakat':
        case 'non zakat':
        case 'nonzakat':
          queueType = 'non-zakat';
          break;
        case 'gmwf':
        case 'gm wf':
        case 'gm-wf':
          queueType = 'gmwf';
          break;
        default:
          queueType = 'zakat';
      }

      final vitals = {
        'bp': bp,
        'temp': temp,
        'tempUnit': 'C',
        'sugar': sugar.isEmpty ? null : sugar,
        'weight': weight,
        'age': _patientData!['age'] ?? 0,
        'gender': _patientData!['gender'] ?? 'Unknown',
        'bloodGroup': _patientData!['bloodGroup'] ?? 'N/A',
      }..removeWhere((k, v) => v == null);

      final entryData = {
        'serial': serial,
        'queueType': queueType,
        'patientId': patientId,
        'patientName': patientName,
        'patientCnic': _patientData!['cnic']?.toString().trim() ?? 
                       _patientData!['guardianCnic']?.toString().trim() ?? '',
        'createdAt': now.toIso8601String(),
        'status': 'waiting',
        'vitals': vitals,
        'branchId': widget.branchId,
        'createdBy': widget.receptionistId,
        'createdByName': widget.receptionistName,
        'dateKey': dateKey,
        if (_patientData!['cnic'] != null && _patientData!['cnic'].toString().trim().isNotEmpty)
          'cnic': _patientData!['cnic'].toString().trim(),
        if (_patientData!['guardianCnic'] != null && _patientData!['guardianCnic'].toString().trim().isNotEmpty)
          'guardianCnic': _patientData!['guardianCnic'].toString().trim(),
      };

      // ═══ STEP 1: Save locally in receptionist's Hive (INSTANT) ═══
      final entryKey = '${widget.branchId}-$serial';
      final entriesBox = Hive.box(LocalStorageService.entriesBox);
      await entriesBox.put(entryKey, entryData);
      debugPrint('[TokenScreen] ✅ Token saved locally (receptionist) → $serial');

      // ═══ STEP 2: Broadcast via LAN to doctor/dispenser (INSTANT) ═══
      try {
        final payload = RealtimeEvents.payload(
          type: RealtimeEvents.saveEntry,
          branchId: widget.branchId,
          data: entryData, // Send complete entry data
        );

        debugPrint('╔════════════════════════════════════════════════════════════╗');
        debugPrint('║ TOKEN BROADCAST (RECEPTIONIST → DOCTOR/DISPENSER)         ║');
        debugPrint('╠════════════════════════════════════════════════════════════╣');
        debugPrint('║ Serial: $serial');
        debugPrint('║ Patient: $patientName');
        debugPrint('║ Queue: $queueType');
        debugPrint('║ Branch: ${widget.branchId}');
        debugPrint('╚════════════════════════════════════════════════════════════╝');

        RealtimeManager().sendMessage(payload);
        debugPrint('[TokenScreen] ✅ Token broadcasted via LAN → $serial');
      } catch (e) {
        debugPrint('[TokenScreen] ⚠️ LAN broadcast failed (continuing): $e');
      }

      // Update next serial immediately
      _estimateNextSerial();

      if (mounted) {
        setState(() {
          _patientData = null;
          _patientsList.clear();
          cnicController.clear();
          _hasTokenToday = true;
          _guardianCnic = null;
          _guardianPatient = null;
          _errorMessage = null;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Token $serial issued to $patientName!"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // ═══ STEP 3: Sync to Firestore in background (DELAYED, NON-BLOCKING) ═══
      _syncToFirestoreInBackground(dateKey, queueType, serial, entryData);

    } catch (e, stack) {
      debugPrint('[TokenScreen] ❌ Token generation failed: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to issue token: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncToFirestoreInBackground(
    String dateKey,
    String queueType,
    String serial,
    Map<String, dynamic> entryData,
  ) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint('[TokenScreen] 🌐 Syncing to Firestore in background...');
        
        final dayRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('serials')
            .doc(dateKey);

        await dayRef.collection(queueType).doc(serial).set(entryData);
        await dayRef.set(
          {'lastSerialNumber': int.parse(serial.split('-').last)},
          SetOptions(merge: true),
        );
        
        debugPrint('[TokenScreen] ✅ Synced to Firestore → $serial');
      } else {
        debugPrint('[TokenScreen] 📴 Offline - queuing for sync');
        await LocalStorageService.enqueueSync({
          'type': 'save_entry',
          'branchId': widget.branchId,
          'dateKey': dateKey,
          'queueType': queueType,
          'serial': serial,
          'data': entryData,
        });
      }
    } catch (e) {
      debugPrint('[TokenScreen] ⚠️ Firestore sync failed (queuing): $e');
      try {
        await LocalStorageService.enqueueSync({
          'type': 'save_entry',
          'branchId': widget.branchId,
          'dateKey': dateKey,
          'queueType': queueType,
          'serial': serial,
          'data': entryData,
        });
      } catch (queueError) {
        debugPrint('[TokenScreen] ⚠️ Queue failed too: $queueError');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // PATIENT EDIT REQUEST (Restored from old version)
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _requestEditPatient() async {
    if (_patientData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No patient selected")),
      );
      return;
    }

    debugPrint("Edit patient button clicked — preparing dialog");

    try {
      bool isChild = _patientData!['isAdult'] != true;

      final cnicCtrl = TextEditingController(
        text: isChild 
            ? (_patientData!['guardianCnic']?.toString() ?? '') 
            : (_patientData!['cnic']?.toString() ?? ''),
      );
      final nameCtrl = TextEditingController(text: _patientData!['name']?.toString() ?? '');
      final phoneCtrl = TextEditingController(text: _patientData!['phone']?.toString() ?? '');
      final dobCtrl = TextEditingController();
      final bloodGroupCtrl = TextEditingController(text: _patientData!['bloodGroup']?.toString() ?? 'N/A');

      String selectedStatus = _patientData!['status']?.toString() ?? 'Zakat';
      String selectedGender = _patientData!['gender']?.toString() ?? 'Male';

      // Handle DOB
      final dobValue = _patientData!['dob'];
      if (dobValue != null) {
        DateTime? birthDate;

        if (dobValue is Timestamp) {
          birthDate = dobValue.toDate();
        } else if (dobValue is String) {
          try {
            birthDate = DateFormat('dd-MM-yyyy').parse(dobValue);
          } catch (_) {
            try {
              birthDate = DateTime.parse(dobValue);
            } catch (_) {
              debugPrint("Could not parse dob string: $dobValue");
            }
          }
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
            backgroundColor: Colors.green[100],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.edit_note, color: Colors.green),
                SizedBox(width: 8),
                Text("Request Patient Edit", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Patient Type", style: TextStyle(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<bool>(
                                title: const Text("Adult"),
                                value: true,
                                groupValue: !isChild,
                                activeColor: Colors.green,
                                onChanged: (v) {
                                  setStateDialog(() {
                                    isChild = !(v!);
                                    cnicCtrl.text = isChild
                                        ? (_patientData!['guardianCnic']?.toString() ?? '')
                                        : (_patientData!['cnic']?.toString() ?? '');
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<bool>(
                                title: const Text("Child"),
                                value: false,
                                groupValue: !isChild,
                                activeColor: Colors.green,
                                onChanged: (v) {
                                  setStateDialog(() {
                                    isChild = !(v!);
                                    cnicCtrl.text = isChild
                                        ? (_patientData!['guardianCnic']?.toString() ?? '')
                                        : (_patientData!['cnic']?.toString() ?? '');
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: cnicCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: isChild ? "Guardian CNIC" : "CNIC",
                      prefixIcon: const Icon(Icons.badge, color: Colors.green),
                      filled: true,
                      fillColor: Colors.white,
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Full Name",
                      prefixIcon: Icon(Icons.person, color: Colors.green),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: "Phone (optional)",
                      prefixIcon: Icon(Icons.phone, color: Colors.green),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dobCtrl,
                    decoration: const InputDecoration(
                      labelText: "DOB (dd-MM-yyyy)",
                      prefixIcon: Icon(Icons.cake, color: Colors.green),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bloodGroupCtrl,
                    decoration: const InputDecoration(
                      labelText: "Blood Group",
                      prefixIcon: Icon(Icons.bloodtype, color: Colors.green),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("Zakat"),
                          value: "Zakat",
                          groupValue: selectedStatus,
                          onChanged: (v) => setStateDialog(() => selectedStatus = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("Non-Zakat"),
                          value: "Non-Zakat",
                          groupValue: selectedStatus,
                          onChanged: (v) => setStateDialog(() => selectedStatus = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("GMWF"),
                          value: "GMWF",
                          groupValue: selectedStatus,
                          onChanged: (v) => setStateDialog(() => selectedStatus = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text("Gender", style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("Male"),
                          value: "Male",
                          groupValue: selectedGender,
                          onChanged: (v) => setStateDialog(() => selectedGender = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("Female"),
                          value: "Female",
                          groupValue: selectedGender,
                          onChanged: (v) => setStateDialog(() => selectedGender = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text("Other"),
                          value: "Other",
                          groupValue: selectedGender,
                          onChanged: (v) => setStateDialog(() => selectedGender = v!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel", style: TextStyle(color: Colors.green)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  DateTime? dob;
                  if (dobCtrl.text.isNotEmpty && RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(dobCtrl.text)) {
                    final p = dobCtrl.text.split('-');
                    try {
                      dob = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                    } catch (e) {
                      debugPrint("Invalid DOB format: ${dobCtrl.text}");
                    }
                  }

                  final newProposed = {
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                    'status': selectedStatus,
                    'bloodGroup': bloodGroupCtrl.text.trim().isNotEmpty ? bloodGroupCtrl.text.trim() : 'N/A',
                    'gender': selectedGender,
                    'isAdult': !isChild,
                    if (dob != null) 'dob': Timestamp.fromDate(dob),
                  };

                  try {
                    await FirebaseFirestore.instance
                        .collection('branches')
                        .doc(widget.branchId)
                        .collection('edit_requests')
                        .add({
                      'requestType': 'patient_edit',
                      'status': 'pending',
                      'patientId': _patientData!['patientId'],
                      'patientName': _patientData!['name'],
                      'cnic': _patientData!['cnic'],
                      'guardianCnic': _patientData!['guardianCnic'],
                      'originalData': Map<String, dynamic>.from(_patientData!),
                      'proposedData': newProposed,
                      'requestedBy': widget.receptionistId,
                      'requestedByName': widget.receptionistName,
                      'requestedAt': FieldValue.serverTimestamp(),
                      'targetRole': 'supervisor',
                    });

                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("✅ Edit request sent to supervisor!"),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  } catch (e) {
                    debugPrint("Failed to send edit request: $e");
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("❌ Failed to send request: $e"),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                child: const Text("Send Request", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint("Edit patient dialog error: $e\n$stack");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not open edit dialog: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showVitalsDialog() {
    final systolicCtrl = TextEditingController();
    final diastolicCtrl = TextEditingController();
    final tempCtrl = TextEditingController();
    final sugarCtrl = TextEditingController();
    final weightCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: Colors.green[100],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.monitor_heart, color: Colors.green),
              SizedBox(width: 8),
              Text("Enter Vitals", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: systolicCtrl,
                        maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: "Systolic",
                          counterText: "",
                          prefixIcon: Icon(Icons.favorite, color: Colors.green),
                          border: OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green, width: 2)),
                        ),
                      ),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 20), child: Text('/')),
                    Expanded(
                      child: TextField(
                        controller: diastolicCtrl,
                        maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: "Diastolic",
                          counterText: "",
                          border: OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green, width: 2)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  onChanged: (_) => _formatTemperatureAutoDot(tempCtrl),
                  decoration: const InputDecoration(
                    labelText: "Temperature (°C)",
                    hintText: "e.g. 98.6, 107.9",
                    counterText: "",
                    prefixIcon: Icon(Icons.thermostat, color: Colors.green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sugarCtrl,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Blood Sugar (mg/dL) (optional)",
                    counterText: "",
                    prefixIcon: Icon(Icons.bloodtype, color: Colors.green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weightCtrl,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Weight (kg)",
                    counterText: "",
                    prefixIcon: Icon(Icons.monitor_weight, color: Colors.green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green, width: 2)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.green)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final systolic = systolicCtrl.text.trim();
                final diastolic = diastolicCtrl.text.trim();
                final bp = '$systolic/$diastolic';
                final temp = tempCtrl.text.trim();
                final sugar = sugarCtrl.text.trim();
                final weight = weightCtrl.text.trim();

                if (systolic.isEmpty || diastolic.isEmpty || temp.isEmpty || weight.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all required fields!"), backgroundColor: Colors.red),
                  );
                  return;
                }

                final tempVal = double.tryParse(temp);
                if (tempVal == null || tempVal < 80.0 || tempVal > 110.0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Temperature must be between 80.0 and 110.0"), backgroundColor: Colors.red),
                  );
                  return;
                }

                Navigator.pop(ctx);
                _generateToken(bp: bp, temp: temp, sugar: sugar, weight: weight);
              },
              icon: const Icon(Icons.local_hospital),
              label: const Text("Issue Token"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[500],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _formatTemperatureAutoDot(TextEditingController controller) {
    String text = controller.text;
    if (text.isEmpty) return;

    if (text.contains('.') && text.endsWith('.')) return;

    String cleaned = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) {
      controller.clear();
      return;
    }

    String formatted = '';
    if (cleaned.startsWith('10')) {
      if (cleaned.length <= 3) {
        formatted = cleaned;
      } else {
        formatted = '${cleaned.substring(0, 3)}.${cleaned.substring(3, cleaned.length.clamp(3, 4))}';
      }
    } else {
      if (cleaned.length <= 2) {
        formatted = cleaned;
      } else {
        formatted = '${cleaned.substring(0, 2)}.${cleaned.substring(2, cleaned.length.clamp(2, 3))}';
      }
    }

    if (formatted != text) {
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final containerWidth = isMobile ? double.infinity : 460.0;

    return Container(
      color: Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: containerWidth,
            margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
            padding: EdgeInsets.all(isMobile ? 20 : 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green[200]!, width: 1.5),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Next Token: ${_nextSerial ?? 'Loading...'}",
                      style: TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 22 : 26,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Image.asset('assets/logo/gmwf.png', height: isMobile ? 80 : 100),
                    const SizedBox(height: 16),
                    Text("Issue Token", style: TextStyle(fontSize: isMobile ? 20 : 22, fontWeight: FontWeight.bold, color: Colors.green[900])),
                    const SizedBox(height: 30),
                    TextField(
                      controller: cnicController,
                      focusNode: _cnicFocusNode,
                      maxLength: 15,
                      keyboardType: TextInputType.number,
                      cursorColor: Colors.green[900],
                      onChanged: (v) {
                        final d = v.replaceAll(RegExp(r'[^0-9]'), '');
                        if (d.startsWith('03') && d.length <= 11) {
                          cnicController.value = TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
                        } else if (d.length <= 13) {
                          final f = _formatCnic(d);
                          cnicController.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
                        }
                      },
                      onSubmitted: (_) => triggerSearch(),
                      style: TextStyle(color: Colors.green[900]),
                      decoration: InputDecoration(
                        labelText: "Guardian CNIC or Phone",
                        counterText: "",
                        labelStyle: const TextStyle(color: Colors.green),
                        prefixIcon: const Icon(Icons.badge, color: Colors.green),
                        suffixIcon: IconButton(icon: const Icon(Icons.search, color: Colors.green), onPressed: triggerSearch),
                        filled: true,
                        fillColor: Colors.green[50],
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.green)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.green, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 15),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    if (_patientsList.isNotEmpty) ...[
                      ..._patientsList.map((p) {
                        final cnicInfo = _getDisplayCnicInfo(p);
                        final phone = p['phone'] as String? ?? '-';
                        return Card(
                          color: Colors.green[50],
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(p['name'] as String? ?? '', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${cnicInfo.label}: ${cnicInfo.cnic}", style: const TextStyle(color: Colors.green)),
                                Text("Phone: $phone", style: const TextStyle(color: Colors.green)),
                              ],
                            ),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[500], foregroundColor: Colors.white),
                              onPressed: () async => await _selectPatient(p),
                              child: const Text("Select"),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 20),
                    ],
                    
                    if (_patientData != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // FIXED: Added edit button back
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _patientData!['name'] as String? ?? '',
                                    style: const TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.orange, size: 28),
                                  tooltip: "Request Edit Patient",
                                  onPressed: _requestEditPatient,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            () {
                              final cnicInfo = _getDisplayCnicInfo(_patientData!);
                              return Text("${cnicInfo.label}: ${cnicInfo.cnic}", style: const TextStyle(color: Colors.green));
                            }(),
                            Text("Phone: ${_patientData!['phone'] ?? '-'}", style: const TextStyle(color: Colors.green)),
                            Text("Status: ${_patientData!['status'] ?? ''}", style: const TextStyle(color: Colors.teal)),
                            const SizedBox(height: 12),
                            
                            if (_hasTokenToday)
                              Container(
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red[300]!, width: 1.5),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Token already issued today for this patient",
                                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: _hasTokenToday ? null : _showVitalsDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _hasTokenToday ? Colors.grey[400] : Colors.green[500],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.local_hospital),
                                label: Text(_hasTokenToday ? "Token Already Issued" : "Enter Vitals & Issue Token"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                    if (_isLoading) const Center(child: CircularProgressIndicator(color: Colors.green)),
                  ],
                ),

                if (_isRefreshing)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                          SizedBox(width: 6),
                          Text("Updating...", style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({String cnic, String label}) _getDisplayCnicInfo(Map<String, dynamic> patient) {
    final ownCnic = patient['cnic']?.toString().trim();
    final guardianCnic = patient['guardianCnic']?.toString().trim();

    if (ownCnic != null && ownCnic.isNotEmpty) {
      return (cnic: ownCnic, label: 'CNIC');
    } else if (guardianCnic != null && guardianCnic.isNotEmpty) {
      return (cnic: guardianCnic, label: 'Guardian CNIC');
    } else {
      return (cnic: '-', label: 'CNIC');
    }
  }
}