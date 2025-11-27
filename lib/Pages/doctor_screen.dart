// lib/pages/doctor_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import 'patient_queue.dart';
import 'doctor_right_panel.dart';
import 'patient_info.dart';
import 'patient_history.dart';

class DoctorScreen extends StatefulWidget {
  final String branchId;
  final String doctorId;

  const DoctorScreen({
    super.key,
    required this.branchId,
    required this.doctorId,
  });

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  Map<String, dynamic>? _selectedPatientData;

  final TextEditingController _complaintController = TextEditingController();
  final TextEditingController _diagnosisController = TextEditingController();

  List<Map<String, dynamic>> _prescriptions = [];
  List<Map<String, dynamic>> _labResults = [];

  bool _isSaving = false;
  bool _isOnline = true;
  String? _doctorName;

  StreamSubscription? _connectivitySubscription;
  StreamSubscription<QuerySnapshot>? _zakatSub;
  StreamSubscription<QuerySnapshot>? _nonZakatSub;

  List<Map<String, dynamic>> _latestZakat = [];
  List<Map<String, dynamic>> _latestNonZakat = [];

  static const Color _green = Color(0xFF2E7D32);

  // CORRECT: FocusScopeNode for FocusScope
  final FocusScopeNode _rightPanelFocusScope = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    _fetchDoctorName();
    _monitorConnectivity();
    _subscribeToQueueStreams();
  }

  Future<void> _fetchDoctorName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(widget.doctorId)
          .get();

      final username = (doc.exists && doc.data()?['username'] != null)
          ? doc.data()!['username'].toString()
          : 'Doctor';

      setState(() {
        _doctorName = username;
      });
    } catch (e) {
      debugPrint("Error fetching doctor username: $e");
      setState(() {
        _doctorName = 'Doctor';
      });
    }
  }

  void _monitorConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
    });
  }

  void _subscribeToQueueStreams() {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final base = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today);

    _zakatSub = base.collection('zakat').snapshots().listen((snap) {
      _latestZakat = snap.docs
          .map((d) => {
                ...d.data() as Map<String, dynamic>,
                'id': d.id,
                'queueType': 'zakat'
              })
          .toList();
      _mergeSortAndAutoSelect();
    });

    _nonZakatSub = base.collection('non-zakat').snapshots().listen((snap) {
      _latestNonZakat = snap.docs
          .map((d) => {
                ...d.data() as Map<String, dynamic>,
                'id': d.id,
                'queueType': 'non-zakat'
              })
          .toList();
      _mergeSortAndAutoSelect();
    });
  }

  void _mergeSortAndAutoSelect() {
    final combined = [..._latestZakat, ..._latestNonZakat];
    combined.sort((a, b) {
      final aStatus = (a['status'] ?? '').toString();
      final bStatus = (b['status'] ?? '').toString();
      if (aStatus == 'waiting' && bStatus != 'waiting') return -1;
      if (aStatus != 'waiting' && bStatus == 'waiting') return 1;
      int aNum = _extractSerialSuffix(a['serial'] ?? '');
      int bNum = _extractSerialSuffix(b['serial'] ?? '');
      return aNum.compareTo(bNum);
    });

    final firstWaiting = combined.firstWhere(
        (p) => (p['status'] ?? '').toString() == 'waiting',
        orElse: () => {});
    if (firstWaiting.isNotEmpty && _shouldAutoSelectNext(firstWaiting)) {
      _fetchFullPatientDataAndSelect(firstWaiting);
    }
  }

  bool _shouldAutoSelectNext(Map<String, dynamic> candidate) {
    if (_selectedPatientData == null) return true;
    final currStatus = (_selectedPatientData!['status'] ?? '').toString();
    if (currStatus != 'waiting') return true;
    return false;
  }

  int _extractSerialSuffix(String serial) {
    try {
      if (serial.contains('-')) {
        return int.tryParse(serial.split('-').last) ?? 999999;
      }
      return int.tryParse(serial) ?? 999999;
    } catch (_) {
      return 999999;
    }
  }

  Future<void> _fetchFullPatientDataAndSelect(
      Map<String, dynamic> queueEntry) async {
    final serialId = queueEntry['serial'] ?? queueEntry['id'] ?? '';
    final queueType = queueEntry['queueType'] ?? 'zakat';
    if (serialId.isEmpty) return;
    final dateKey = serialId.split('-').first;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey)
          .collection(queueType)
          .doc(serialId)
          .get();

      if (!doc.exists) {
        setState(() => _selectedPatientData = queueEntry);
        return;
      }

      final merged = {...queueEntry, ...doc.data()!, 'serial': serialId};
      setState(() {
        _selectedPatientData = merged;
        _complaintController.clear();
        _diagnosisController.clear();
        _prescriptions = [];
        _labResults = [];
      });

      // AUTO-FOCUS ON COMPLAINT
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _rightPanelFocusScope.requestFocus();
        }
      });
    } catch (e) {
      debugPrint("Error fetching serial details: $e");
    }
  }

  @override
  void dispose() {
    _complaintController.dispose();
    _diagnosisController.dispose();
    _connectivitySubscription?.cancel();
    _zakatSub?.cancel();
    _nonZakatSub?.cancel();
    _rightPanelFocusScope.dispose();
    super.dispose();
  }

  Future<void> _onPatientSelected(Map<String, dynamic> patientData) async {
    final serialId = patientData['serial'] ?? patientData['id'] ?? '';
    final queueType = patientData['queueType'] ?? 'zakat';
    if (serialId.isEmpty) return;

    try {
      final dateKey = serialId.split('-').first;
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey)
          .collection(queueType)
          .doc(serialId)
          .get();

      if (!doc.exists) return;
      final fullData = {...patientData, ...doc.data()!, 'serial': serialId};

      setState(() {
        _selectedPatientData = fullData;
        _complaintController.clear();
        _diagnosisController.clear();
        _prescriptions = [];
        _labResults = [];
      });

      // AUTO-FOCUS ON COMPLAINT
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _rightPanelFocusScope.requestFocus();
        }
      });
    } catch (e) {
      debugPrint("Error fetching patient details: $e");
    }
  }

  void _handleRepeatLast(Map<String, dynamic> visit) {
    setState(() {
      _complaintController.text = visit['complaint'] ?? '';
      _diagnosisController.text = visit['diagnosis'] ?? '';
      _prescriptions = List<Map<String, dynamic>>.from(
          (visit['prescriptions'] ?? [])
              .map((m) => Map<String, dynamic>.from(m)));
      _labResults = List<Map<String, dynamic>>.from(
          (visit['labResults'] ?? []).map((l) => Map<String, dynamic>.from(l)));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Last visit data loaded successfully')),
    );

    // REFOCUS AFTER REPEAT
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _rightPanelFocusScope.requestFocus();
      }
    });
  }

  void _addLabResult() =>
      setState(() => _labResults.add({'name': 'New Lab Test'}));
  void _removeLabResult(int index) =>
      setState(() => _labResults.removeAt(index));
  void _addMedicine(Map<String, dynamic> medicine) =>
      setState(() => _prescriptions.add(medicine));
  void _editMedicine(Map<String, dynamic> updatedMed) {
    setState(() {
      final index = _prescriptions.indexWhere(
          (med) => med['originalName'] == updatedMed['originalName']);
      if (index != -1) _prescriptions[index] = updatedMed;
    });
  }

  void _removeMedicine(int index) =>
      setState(() => _prescriptions.removeAt(index));

  Future<void> _savePrescription() async {
    if (_selectedPatientData == null) return;

    setState(() => _isSaving = true);

    try {
      final patient = _selectedPatientData!;
      final serial = (patient['serial'] ?? '').toString();
      final patientCNIC =
          (patient['cnic'] ?? patient['patientCNIC'] ?? '').toString();

      final dateKey = serial.split('-').first;
      final data = {
        'serial': serial,
        'cnic': patientCNIC,
        'patientName': patient['patientName'] ?? patient['name'] ?? '',
        'complaint': _complaintController.text.trim(),
        'diagnosis': _diagnosisController.text.trim(),
        'prescriptions': _prescriptions,
        'labResults': _labResults,
        'createdAt': FieldValue.serverTimestamp(),
        'doctorId': widget.doctorId,
        'doctorName': _doctorName ?? '',
        'vitals': patient['vitals'] ?? {},
      };

      final presRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(patientCNIC)
          .collection('prescriptions')
          .doc(serial);

      await presRef.set(data, SetOptions(merge: true));

      final queueType = (patient['queueType'] ?? 'non-zakat').toString();
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey)
          .collection(queueType)
          .doc(serial)
          .update({'status': 'completed'});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prescription saved successfully')),
      );

      setState(() {
        _selectedPatientData = null;
        _complaintController.clear();
        _diagnosisController.clear();
        _prescriptions.clear();
        _labResults.clear();
      });

      _mergeSortAndAutoSelect();
    } catch (e) {
      debugPrint('Error saving prescription: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving prescription: $e')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _green,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const FaIcon(FontAwesomeIcons.userDoctor, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              _doctorName != null ? "Dr. $_doctorName" : "Doctor Panel",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Icon(_isOnline ? Icons.wifi : Icons.wifi_off,
                color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(_isOnline ? "Online" : "Offline",
                style: const TextStyle(color: Colors.white, fontSize: 18)),
            const Spacer(),
            ExcludeFocus(
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.white),
                label:
                    const Text("Logout", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          // LEFT: Patient Queue (NO TAB)
          ExcludeFocus(
            child: Expanded(
              flex: 2,
              child: PatientQueue(
                branchId: widget.branchId,
                onPatientSelected: _onPatientSelected,
                selectedPatient: _selectedPatientData,
              ),
            ),
          ),

          // RIGHT: Work Area
          Expanded(
            flex: 8,
            child: Column(
              children: [
                // Patient Info Card (NO TAB)
                ExcludeFocus(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6.0, vertical: 6.0),
                    child: SizedBox(
                      height: 180,
                      child: Card(
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: (_selectedPatientData != null)
                              ? PatientInfo(
                                  branchId: widget.branchId,
                                  patientData: _selectedPatientData!,
                                )
                              : const Center(
                                  child: Text(
                                    "Select a patient from queue",
                                    style: TextStyle(
                                        color: Colors.black54, fontSize: 16),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Work Area: Right Panel + History
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final remainingHeight = constraints.maxHeight;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6.0, vertical: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // DOCTOR RIGHT PANEL — TAB CONTROLLED
                          Expanded(
                            flex: 5,
                            child: SizedBox(
                              height: remainingHeight,
                              child: Card(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                elevation: 2,
                                margin: const EdgeInsets.only(right: 6.0),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: (_selectedPatientData != null)
                                      ? FocusScope(
                                          node: _rightPanelFocusScope,
                                          child: DoctorRightPanel(
                                            branchId: widget.branchId,
                                            selectedPatientData:
                                                _selectedPatientData,
                                            serialId: _selectedPatientData![
                                                    'serial'] ??
                                                '',
                                            complaintController:
                                                _complaintController,
                                            diagnosisController:
                                                _diagnosisController,
                                            prescriptions: _prescriptions,
                                            labResults: _labResults,
                                            isSaving: _isSaving,
                                            onAddLabResult: _addLabResult,
                                            onRemoveLabResult: _removeLabResult,
                                            onRemoveMedicine: _removeMedicine,
                                            onEditMedicine: _editMedicine,
                                            onSavePrescription:
                                                _savePrescription,
                                          ),
                                        )
                                      : const Center(
                                          child: Text(
                                            "Select a patient to start",
                                            style: TextStyle(
                                                color: Colors.black54,
                                                fontSize: 16),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),

                          // PATIENT HISTORY (NO TAB)
                          ExcludeFocus(
                            child: Expanded(
                              flex: 3,
                              child: SizedBox(
                                height: remainingHeight,
                                child: Card(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  elevation: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: (_selectedPatientData != null)
                                        ? PatientHistory(
                                            branchId: widget.branchId,
                                            patientCNIC:
                                                _selectedPatientData!['cnic'] ??
                                                    _selectedPatientData![
                                                        'patientCNIC'] ??
                                                    '',
                                            maxCardHeight: 120,
                                            onRepeatLast: _handleRepeatLast,
                                          )
                                        : const Center(
                                            child: Text(
                                              "Visit history will appear here",
                                              style: TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 14),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
