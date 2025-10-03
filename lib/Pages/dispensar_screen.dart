// lib/pages/dispensar_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DispensarScreen extends StatefulWidget {
  final String branchId;

  const DispensarScreen({super.key, required this.branchId});

  @override
  State<DispensarScreen> createState() => _DispensarScreenState();
}

class _DispensarScreenState extends State<DispensarScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Box? _localBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOnline = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _initHive();
    _listenConnectivity();
    _tabController =
        TabController(length: 2, vsync: this); // Patients + Inventory
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
      if (mounted) setState(() => _isOnline = hasNetwork);
    });
  }

  /// ========================= PATIENT DISPENSING =========================
  Future<void> _dispensePatient(
      Map<String, dynamic> patientData, String patientId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Dispense"),
        content: const Text("Dispense this patient’s medicines?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Yes")),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prescriptions =
          (patientData["prescriptions"] ?? []) as List<dynamic>;
      if (prescriptions.isEmpty) throw "No prescription found.";

      final latest = prescriptions.last as Map<String, dynamic>;
      final medicines = (latest["medicines"] ?? []) as List<dynamic>;

      for (final med in medicines) {
        final medId = med["id"];
        final qty = med["qty"] ?? 0;
        if (medId == null || qty <= 0) continue;

        final medRef = _firestore
            .collection("branches")
            .doc(widget.branchId)
            .collection("inventory")
            .doc(medId);

        await _firestore.runTransaction((txn) async {
          final snap = await txn.get(medRef);
          if (!snap.exists) return;

          final stock = (snap["stock"] ?? 0) as int;
          if (stock >= qty) {
            txn.update(medRef, {"stock": stock - qty});
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      "⚠️ Not enough stock for ${med['name']} (needed $qty, available $stock)")),
            );
          }
        });
      }

      await _firestore
          .collection("branches")
          .doc(widget.branchId)
          .collection("patients")
          .doc(patientId)
          .update({"status": "Dispensed"});

      await _firestore
          .collection("branches")
          .doc(widget.branchId)
          .collection("dispensary")
          .doc(patientId)
          .set({
        ...patientData,
        "status": "Dispensed",
        "dispensedAt": FieldValue.serverTimestamp(),
        "dispenserId": _auth.currentUser?.uid,
        "dispenserEmail": _auth.currentUser?.email,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Patient dispensed successfully")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error: $e")),
        );
      }
    }
  }

  Widget _buildPatientCard(Map<String, dynamic> data, String patientId) {
    final prescriptions = (data["prescriptions"] ?? []) as List<dynamic>;
    final latest = prescriptions.isNotEmpty
        ? prescriptions.last as Map<String, dynamic>
        : {};
    final diagnosis = latest["diagnosis"] ?? "-";
    final tests = (latest["tests"] ?? []) as List<dynamic>;
    final medicines = (latest["medicines"] ?? []) as List<dynamic>;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("👤 Patient: ${data["name"] ?? "Unknown"}",
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text("🆔 CNIC: ${data["cnic"] ?? "-"}"),
          const Divider(height: 20),
          Text("🩺 Diagnosis: $diagnosis"),
          Text("🧪 Tests: ${tests.isEmpty ? '-' : tests.join(', ')}"),
          Text(
              "💊 Medicines: ${medicines.isEmpty ? '-' : medicines.map((m) => '${m['name']} (x${m['qty']})').join(', ')}"),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.local_pharmacy),
              label: const Text("Dispense"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _dispensePatient(data, patientId),
            ),
          ),
        ]),
      ),
    );
  }

  /// ========================= INVENTORY =========================
  Widget _buildInventoryCard(Map<String, dynamic> med, String medId) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(med["name"] ?? "Unnamed"),
        subtitle: Text("Stock: ${med["stock"] ?? 0}"),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => _addStockDialog(medId, med),
        ),
      ),
    );
  }

  Future<void> _addStockDialog(String medId, Map<String, dynamic> med) async {
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Add stock for ${med["name"]}"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Enter quantity"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(controller.text) ?? 0;
                Navigator.pop(ctx, qty);
              },
              child: const Text("Add")),
        ],
      ),
    );

    if (result == null || result <= 0) return;

    final medRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory")
        .doc(medId);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(medRef);
      final currentStock = (snap["stock"] ?? 0) as int;
      txn.update(medRef, {"stock": currentStock + result});
    });

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Added $result to ${med["name"]}")));
  }

  /// ========================= LOGOUT =========================
  Future<void> _logout(BuildContext context) async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed("/login");
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localBox == null || !_localBox!.isOpen) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final patientsRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("patients")
        .where("status", whereIn: ["Prescribed", "Repeat"]);

    final inventoryRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("inventory");

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF43A047), Color.fromARGB(255, 173, 250, 177)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              // ✅ Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                height: 70,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Image.asset('assets/logo/gmwf.png', height: 50),
                      const SizedBox(width: 10),
                      const Text('Dispenser Dashboard',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20)),
                    ]),
                    TextButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text("Logout",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
              ),
              // ✅ Red strip
              Container(
                height: 20,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.redAccent, Colors.red],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter),
                ),
              ),
              // ✅ TabBar (Patients | Inventory)
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: "Patients"),
                  Tab(text: "Inventory"),
                ],
                labelColor: Colors.white,
                indicatorColor: Colors.yellow,
              ),
              // ✅ Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Patients
                    StreamBuilder<QuerySnapshot>(
                      stream: patientsRef.snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final patients = snapshot.data!.docs;
                        if (patients.isEmpty) {
                          return const Center(
                              child: Text("🎉 No patients to dispense"));
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: patients.length,
                          itemBuilder: (context, index) {
                            final data =
                                patients[index].data() as Map<String, dynamic>;
                            return _buildPatientCard(data, patients[index].id);
                          },
                        );
                      },
                    ),
                    // Inventory
                    StreamBuilder<QuerySnapshot>(
                      stream: inventoryRef.snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final meds = snapshot.data!.docs;
                        if (meds.isEmpty) {
                          return const Center(
                              child: Text("📦 No medicines in inventory"));
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: meds.length,
                          itemBuilder: (context, index) {
                            final med =
                                meds[index].data() as Map<String, dynamic>;
                            return _buildInventoryCard(med, meds[index].id);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
