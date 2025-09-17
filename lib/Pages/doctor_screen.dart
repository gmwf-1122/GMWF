import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'patient_detail_screen.dart';

class DoctorScreen extends StatefulWidget {
  final String branchId;

  const DoctorScreen({super.key, required this.branchId});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late Box _localBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _initHive();
    _listenConnectivity();
  }

  /// Initialize Hive box for local cache
  Future<void> _initHive() async {
    try {
      _localBox = await Hive.openBox("doctorData_${widget.branchId}");
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("❌ Hive init error: $e");
    }
  }

  /// Listen for connectivity changes (new API returns a List<ConnectivityResult>)
  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online =
          results.isNotEmpty && results.first != ConnectivityResult.none;

      if (online && !_isOnline) {
        _syncLocalToFirestore();
      }

      if (mounted) {
        setState(() => _isOnline = online);
      }
    });
  }

  /// Sync offline prescriptions to Firestore
  Future<void> _syncLocalToFirestore() async {
    if (!_localBox.isOpen) return;

    final cachedPrescriptions =
        _localBox.get("pendingPrescriptions", defaultValue: []) as List;

    for (var item in cachedPrescriptions) {
      if (item is! Map) continue;
      final patientId = item["patientId"];
      if (patientId == null) continue;

      final safeItem = Map<String, dynamic>.from(item);

      try {
        await _firestore.collection("patients").doc(patientId).set({
          "doctorNotes": FieldValue.arrayUnion([safeItem])
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("❌ Failed to sync prescription: $e");
      }
    }

    await _localBox.put("pendingPrescriptions", []);
  }

  /// Logout function
  Future<void> _logout() async {
    try {
      await _auth.signOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      debugPrint("❌ Logout error: $e");
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Load patients created by receptionists of the same branch
  Future<List<Map<String, dynamic>>> _loadPatients() async {
    if (!_localBox.isOpen) return [];

    Map<String, dynamic> data = {};

    if (_isOnline) {
      try {
        final snapshot = await _firestore
            .collection("patients")
            .where("branchId", isEqualTo: widget.branchId)
            .get();

        for (var doc in snapshot.docs) {
          data[doc.id] = doc.data();
        }

        await _localBox.put("patientsCache", data);
      } catch (e) {
        debugPrint("❌ Failed to load patients: $e");
      }
    } else {
      final cached = _localBox.get("patientsCache", defaultValue: {});
      data = Map<String, dynamic>.from(cached);
    }

    return data.entries.map((entry) {
      final patient = Map<String, dynamic>.from(entry.value);
      patient["id"] = entry.key;
      return patient;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!_localBox.isOpen) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Doctor Dashboard"),
        backgroundColor: Colors.green,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: "Logout",
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadPatients(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Error loading patients: ${snapshot.error}"),
            );
          }

          final patients = snapshot.data ?? [];
          if (patients.isEmpty) {
            return const Center(
              child: Text("No patients for this branch yet"),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  title: Text(
                    "Serial: ${patient["serial"] ?? "N/A"}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Name: ${patient["name"] ?? "Unknown"}"),
                      Text("Age: ${patient["age"] ?? "N/A"}"),
                      Text("Gender: ${patient["gender"] ?? "N/A"}"),
                    ],
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientDetailScreen(
                            patientId: patient["id"],
                            patientData: patient,
                            isOnline: _isOnline,
                            localBox: _localBox,
                            branchId: widget.branchId,
                          ),
                        ),
                      );
                    },
                    child: const Text("See Patient"),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
