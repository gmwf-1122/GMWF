// lib/pages/dispensar_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:another_flushbar/flushbar.dart';

import 'inventory.dart';
import 'patient_form.dart';
import 'patient_list.dart';

class DispensarScreen extends StatefulWidget {
  final String branchId;
  const DispensarScreen({super.key, required this.branchId});

  @override
  State<DispensarScreen> createState() => _DispensarScreenState();
}

class _DispensarScreenState extends State<DispensarScreen> {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Box? _hiveBox;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _online = true;
  String? _dispenserName;
  Map<String, dynamic>? _selectedPrescription;

  @override
  void initState() {
    super.initState();
    _initHive();
    _listenConnectivity();
    _fetchDispenserName();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _initHive() async {
    _hiveBox = await Hive.openBox('dispensar_${widget.branchId}');
    setState(() {});
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_online != isOnline) {
        setState(() => _online = isOnline);
        if (!isOnline) {
          Flushbar(
            message: "No internet connection",
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ).show(context);
        }
      }
    });
  }

  Future<void> _fetchDispenserName() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() {
        _dispenserName = doc.exists
            ? doc['username'] ?? user.email?.split('@').first
            : user.email?.split('@').first;
      });
    } catch (_) {
      setState(() => _dispenserName = user.email?.split('@').first);
    }
  }

  void _onDispensed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        elevation: 0,
        toolbarHeight: 70,
        // LEFT: Crescent + Title + Name
        title: Row(
          children: [
            Transform.rotate(
              angle: -0.25,
              child: Image.asset('assets/images/moon.png', width: 36),
            ),
            const SizedBox(width: 12),
            Text(
              'Dispensary – ${_dispenserName ?? '…'}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),

        // CENTER: Online/Offline Pill
        flexibleSpace: Align(
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _online ? Colors.green.shade600 : Colors.red.shade600,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_online ? Icons.wifi : Icons.wifi_off,
                    size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _online ? "Online" : "Offline",
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        // RIGHT: Buttons
        actions: [
          // Inventory
          TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => InventoryPage(branchId: widget.branchId)),
            ),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Inventory', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),

          // Logout
          TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: () async {
              await _auth.signOut();
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false);
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 900;

          return Row(
            children: [
              // LEFT: Patient List (no header)
              Container(
                width: isTablet
                    ? 380
                    : constraints.maxWidth > 600
                        ? constraints.maxWidth * 0.4
                        : double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: isTablet
                      ? Border(right: BorderSide(color: Colors.grey.shade300))
                      : null,
                  boxShadow: isTablet
                      ? [
                          BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(2, 0))
                        ]
                      : null,
                ),
                child: PatientList(
                  branchId: widget.branchId,
                  selectedPatient: _selectedPrescription,
                  onPatientSelected: (p) {
                    setState(() => _selectedPrescription = p);
                    if (!isTablet) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        Scrollable.ensureVisible(context,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut);
                      });
                    }
                  },
                ),
              ),

              // RIGHT: Prescription Form
              if (isTablet)
                Expanded(child: _buildPrescriptionSection())
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildPrescriptionSection(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrescriptionSection() {
    if (_selectedPrescription == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Select a patient to view prescription',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: PatientForm(
        branchId: widget.branchId,
        cnic: _selectedPrescription!['patientCNIC'] as String,
        serial: _selectedPrescription!['serial'] as String,
        onDispensed: _onDispensed,
      ),
    );
  }
}
