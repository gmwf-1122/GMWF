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

  /// ✅ Open Hive local storage
  Future<void> _initHive() async {
    try {
      _localBox = await Hive.openBox("dispensar_${widget.branchId}");
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("❌ Hive init error: $e");
    }
  }

  /// ✅ Monitor connectivity and trigger sync when back online
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

  /// ✅ Sync cached receipts to Firestore
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

        // ✅ Update patient status
        final patientSerial = receipt["serial"];
        if (patientSerial != null) {
          await _firestore
              .collection("branches")
              .doc(branchId)
              .collection("patients")
              .doc(patientSerial)
              .set({"status": "Dispensed"}, SetOptions(merge: true));
        }

        // ✅ Deduct stock
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

  /// ✅ Deduct stock from branch inventory
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

  /// ✅ Generate receipt for a patient
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
              .set({"status": "Dispensed"}, SetOptions(merge: true));
        }

        await _updateInventory(medicines);
      } else {
        final cached = List<Map<String, dynamic>>.from(
          _localBox!.get("pendingReceipts", defaultValue: []),
        );
        cached.add(receipt);
        await _localBox!.put("pendingReceipts", cached);

        // Update local cache
        final patientsCache = Map<String, dynamic>.from(
          _localBox!.get("patientsCache", defaultValue: {}),
        );
        if (patientsCache.containsKey(patientSerial)) {
          patientsCache[patientSerial]["status"] = "Dispensed";
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

  /// ✅ Logout user
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
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadPendingPatients(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text("❌ Error loading patients: ${snapshot.error}"),
              );
            }

            final pending = snapshot.data ?? [];
            if (pending.isEmpty) {
              return const Center(child: Text("🎉 No pending prescriptions"));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pending.length,
              itemBuilder: (context, index) =>
                  _buildPatientCard(pending[index]),
            );
          },
        ),
      ),
    );
  }

  /// ✅ Patient card widget
  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final patientName = patient["name"] ?? "Unknown";
    final assignedDoctor = patient["assignedDoctor"] ?? "Unknown";

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text("👤 Patient: $patientName",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("👨‍⚕️ Doctor: $assignedDoctor"),
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

  /// ✅ Load patients with pending prescriptions
  Future<List<Map<String, dynamic>>> _loadPendingPatients() async {
    if (_localBox == null || !_localBox!.isOpen) return [];

    Map<String, dynamic> data = {};

    try {
      if (_isOnline) {
        final snapshot = await _firestore
            .collection("branches")
            .doc(widget.branchId)
            .collection("patients")
            .get();
        for (var doc in snapshot.docs) {
          data[doc.id] = doc.data();
        }
        await _localBox!.put("patientsCache", data);
      } else {
        final cached = _localBox!.get("patientsCache", defaultValue: {});
        data = Map<String, dynamic>.from(cached);
      }
    } catch (e) {
      debugPrint("❌ Error loading pending patients: $e");
    }

    final patients = data.entries.map((entry) {
      final patient = Map<String, dynamic>.from(entry.value);
      patient["serial"] = entry.key;
      return patient;
    }).toList();

    return patients.where((p) {
      final hasPrescription =
          (p["prescription"] != null && (p["prescription"] as List).isNotEmpty);
      final status = p["status"] ?? "";
      return hasPrescription && status != "Dispensed";
    }).toList();
  }
}
