// lib/pages/dispensar_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DispensarScreen extends StatefulWidget {
  final String branchId;

  const DispensarScreen({super.key, required this.branchId});

  @override
  State<DispensarScreen> createState() => _DispensarScreenState();
}

class _DispensarScreenState extends State<DispensarScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  Box? _localBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _initHive();
    _listenConnectivity();
  }

  Future<void> _initHive() async {
    try {
      _localBox = await Hive.openBox("dispensar_${widget.branchId}");
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("❌ Hive init error: $e");
    }
  }

  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.isNotEmpty &&
          results.any((r) => r != ConnectivityResult.none);

      if (hasNetwork && !_isOnline) {
        _syncLocalToFirestore();
      }
      if (mounted) setState(() => _isOnline = hasNetwork);
    });
  }

  Future<void> _syncLocalToFirestore() async {
    if (_localBox == null || !_localBox!.isOpen) return;

    final cachedReceipts = List<Map<String, dynamic>>.from(
      _localBox!.get("pendingReceipts", defaultValue: []),
    );

    final List<Map<String, dynamic>> unsynced = [];

    for (var receipt in cachedReceipts) {
      try {
        final receiptId = receipt["receiptId"];
        final branchId = widget.branchId;

        await _firestore
            .collection("branches")
            .doc(branchId)
            .collection("receipts")
            .doc(receiptId)
            .set(receipt, SetOptions(merge: true));

        final patientSerial = receipt["serial"];
        if (patientSerial != null) {
          await _firestore
              .collection("branches")
              .doc(branchId)
              .collection("patients")
              .doc(patientSerial)
              .update({"status": "Completed"}); // ✅ Mark completed
        }

        if (receipt["medicines"] != null) {
          await _updateInventory(
              List<Map<String, dynamic>>.from(receipt["medicines"]));
        }
      } catch (e) {
        debugPrint("❌ Sync failed for receipt: $e");
        unsynced.add(receipt);
      }
    }

    await _localBox!.put("pendingReceipts", unsynced);
  }

  Future<void> _updateInventory(List<Map<String, dynamic>> usedMeds) async {
    final branchInventory = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory");

    for (var med in usedMeds) {
      final medId = med["medId"];
      final usedQty = med["quantity"] ?? 0;

      if (medId == null) continue;

      try {
        final medDoc = branchInventory.doc(medId);
        final snapshot = await medDoc.get();

        if (snapshot.exists) {
          final stock = (snapshot["stock"] is int)
              ? snapshot["stock"]
              : int.tryParse(snapshot["stock"].toString()) ?? 0;

          await medDoc.update({
            "stock": (stock - usedQty).clamp(0, 999999),
          });
        }
      } catch (e) {
        debugPrint("❌ Inventory update error: $e");
      }
    }
  }

  Future<void> _generateReceipt(Map<String, dynamic> patient) async {
    if (_localBox == null || !_localBox!.isOpen) return;

    final receiptId = _uuid.v4();
    final String patientSerial = patient['serial'] ?? '';
    final List<Map<String, dynamic>> medicines =
        List<Map<String, dynamic>>.from(patient["prescription"] ?? []);

    final dispenserId = _auth.currentUser?.uid ?? '';
    final dispenserEmail = _auth.currentUser?.email ?? '';

    final receipt = {
      'receiptId': receiptId,
      'serial': patientSerial,
      'patientName': patient['name'] ?? 'Unknown',
      'medicines': medicines,
      'dispenserId': dispenserId,
      'dispenserEmail': dispenserEmail,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'branchId': widget.branchId,
    };

    try {
      if (_isOnline) {
        await _firestore
            .collection("branches")
            .doc(widget.branchId)
            .collection("receipts")
            .doc(receiptId)
            .set(receipt, SetOptions(merge: true));

        if (patientSerial.isNotEmpty) {
          await _firestore
              .collection("branches")
              .doc(widget.branchId)
              .collection("patients")
              .doc(patientSerial)
              .update({"status": "Completed"}); // ✅
        }

        await _updateInventory(medicines);
      } else {
        final cached = List<Map<String, dynamic>>.from(
          _localBox!.get("pendingReceipts", defaultValue: []),
        );
        cached.add(receipt);
        await _localBox!.put("pendingReceipts", cached);

        final patientsCache = Map<String, dynamic>.from(
          _localBox!.get("patientsCache", defaultValue: {}),
        );
        if (patientsCache.containsKey(patientSerial)) {
          patientsCache[patientSerial]["status"] = "Completed";
          await _localBox!.put("patientsCache", patientsCache);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isOnline
              ? "✅ Receipt saved & stock updated"
              : "💾 Saved offline (will sync when online)"),
        ),
      );
    } catch (e) {
      debugPrint("❌ Generate receipt error: $e");
    }
  }

  Future<void> _logout(BuildContext context) async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed("/login");
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localBox == null || !_localBox!.isOpen) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.green.shade50,
        appBar: AppBar(
          title: const Text("Dispenser Dashboard"),
          backgroundColor: Colors.green,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "Logout",
              onPressed: () => _logout(context),
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection("branches")
              .doc(widget.branchId)
              .collection("patients")
              .where("status", isEqualTo: "PrescriptionReady") // ✅ Only ready
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text("❌ Error loading patients: ${snapshot.error}"),
              );
            }

            final patients = snapshot.data?.docs ?? [];
            if (patients.isEmpty) {
              return const Center(child: Text("🎉 No pending prescriptions"));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final patient =
                    patients[index].data() as Map<String, dynamic>? ?? {};
                patient["serial"] = patients[index].id;
                return _buildPatientCard(patient);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final patientName = patient["name"] ?? "Unknown";
    final doctorId = patient["doctorId"] ?? "Unknown";

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text("👤 Patient: $patientName",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("👨‍⚕️ Doctor ID: $doctorId"),
        trailing: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => _generateReceipt(patient),
          icon: const Icon(Icons.local_pharmacy),
          label: const Text("Dispense"),
        ),
      ),
    );
  }
}
