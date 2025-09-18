// lib/pages/receptionist_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ReceptionistScreen extends StatefulWidget {
  final String branchId;

  const ReceptionistScreen({super.key, required this.branchId});

  @override
  State<ReceptionistScreen> createState() => _ReceptionistScreenState();
}

class _ReceptionistScreenState extends State<ReceptionistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;

  // Controllers
  final _patientName = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _temperature = TextEditingController();
  final _sugarTest = TextEditingController();
  final _serialController = TextEditingController();

  final FocusNode _nameFocus = FocusNode();

  String? selectedBranchId;
  String? selectedBranchName;
  String? selectedBloodType;
  String? selectedGender;
  String? currentSerial;

  final List<String> bloodTypes = [
    "A+",
    "A-",
    "B+",
    "B-",
    "O+",
    "O-",
    "AB+",
    "AB-"
  ];
  final List<String> genders = ["Male", "Female"];

  List<Map<String, String>> branches = [];

  late Box<Map> _localBox;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    selectedBranchId = widget.branchId;
    _initHive();
    _listenConnectivity();
    _fetchBranches();
    _fetchCurrentSerial(widget.branchId);
  }

  Future<void> _initHive() async {
    _localBox = await Hive.openBox<Map>("patients_${widget.branchId}");
    await _syncLocalPatients();
  }

  void _listenConnectivity() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) async {
      final result =
          results.isNotEmpty ? results.first : ConnectivityResult.none;
      final online = result != ConnectivityResult.none;

      if (online && !_isOnline) {
        await _syncLocalPatients();
      }
      if (mounted) {
        setState(() => _isOnline = online);
      }
    });
  }

  Future<void> _fetchBranches() async {
    try {
      final snapshot = await _firestore.collection("branches").get();
      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        final name =
            data.containsKey('name') ? data['name'].toString() : doc.id;
        return {"id": doc.id, "name": name};
      }).toList();

      if (mounted) {
        setState(() {
          branches = List<Map<String, String>>.from(list);
        });

        if (branches.isNotEmpty) {
          final defaultBranch = branches.firstWhere(
            (b) => b["id"] == widget.branchId,
            orElse: () => branches.first,
          );
          setState(() {
            selectedBranchId = defaultBranch["id"];
            selectedBranchName = defaultBranch["name"];
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Failed to fetch branches: $e");
    }
  }

  Future<void> _fetchCurrentSerial(String branchId) async {
    try {
      final today = DateTime.now();
      final datePart =
          "${today.day.toString().padLeft(2, '0')}${today.month.toString().padLeft(2, '0')}${today.year.toString().substring(2)}";

      final docSnap = await _firestore
          .collection("branches")
          .doc(branchId)
          .collection("metadata")
          .doc("serials")
          .get();

      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null && data.containsKey(datePart)) {
          final count = data[datePart] is int
              ? data[datePart]
              : int.tryParse(data[datePart].toString()) ?? 0;
          if (mounted) {
            setState(() {
              currentSerial = "${datePart}_${count.toString().padLeft(3, '0')}";
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          currentSerial = "${datePart}_000";
        });
      }
    } catch (e) {
      debugPrint("❌ Failed to fetch current serial: $e");
    }
  }

  Future<void> _syncLocalPatients() async {
    if (!_isOnline) return;
    try {
      final cachedPatients = _localBox.values.toList();
      for (var patient in cachedPatients) {
        final Map<String, dynamic> p = Map<String, dynamic>.from(patient);
        final branchId = p["branchId"] ?? widget.branchId;
        final serial =
            p["serial"] ?? DateTime.now().millisecondsSinceEpoch.toString();

        await _firestore
            .collection("branches")
            .doc(branchId)
            .collection("patients")
            .doc(serial)
            .set(p);
      }
      await _localBox.clear();
    } catch (e) {
      debugPrint("❌ Failed to sync local patients: $e");
    }
  }

  Future<void> _saveLocally(Map<String, dynamic> data) async {
    final branchId = data["branchId"] ?? selectedBranchId ?? widget.branchId;
    final box = await Hive.openBox<Map>("patients_$branchId");
    await box.put(data["serial"], Map<String, dynamic>.from(data));
  }

  Future<String> _generateSerial(String branchId) async {
    final today = DateTime.now();
    final datePart =
        "${today.day.toString().padLeft(2, '0')}${today.month.toString().padLeft(2, '0')}${today.year.toString().substring(2)}";

    final counterDoc = _firestore
        .collection("branches")
        .doc(branchId)
        .collection("metadata")
        .doc("serials");

    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterDoc);
      int count = 0;
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data.containsKey(datePart)) {
          count = data[datePart] is int
              ? data[datePart]
              : int.tryParse(data[datePart].toString()) ?? 0;
        }
      }
      count++;
      transaction.set(counterDoc, {datePart: count}, SetOptions(merge: true));
      return "${datePart}_${count.toString().padLeft(3, '0')}";
    });
  }

  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please select a branch")),
      );
      return;
    }

    String serial = currentSerial ?? await _generateSerial(selectedBranchId!);

    final patientData = {
      "serial": serial,
      "name": _patientName.text,
      "age": _age.text,
      "weight": _weight.text,
      "gender": selectedGender ?? "Unknown",
      "bloodType": selectedBloodType ?? "Unknown",
      "temperature": _temperature.text,
      "sugarTest": _sugarTest.text,
      "branchId": selectedBranchId!,
      "branchName": selectedBranchName ?? "",
      "createdAt": DateTime.now().toIso8601String(),
      "status": "New",
      "prescriptions": [],
    };

    try {
      if (_isOnline) {
        await _firestore
            .collection("branches")
            .doc(selectedBranchId!)
            .collection("patients")
            .doc(serial)
            .set(patientData);

        await _saveLocally(patientData);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("✅ Patient details sent to doctor successfully")),
        );

        await _fetchCurrentSerial(selectedBranchId!);
      } else {
        await _saveLocally(patientData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("📦 Patient saved locally (offline)")),
        );
      }

      // ✅ Instead of closing app → just reset form and show next serial
      _formKey.currentState!.reset();
      _patientName.clear();
      _age.clear();
      _weight.clear();
      _temperature.clear();
      _sugarTest.clear();
      _serialController.clear();
      setState(() {
        selectedBloodType = null;
        selectedGender = null;
      });
      FocusScope.of(context).requestFocus(_nameFocus);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error saving patient: $e")),
      );
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, "/login", (route) => false);
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _patientName.dispose();
    _age.dispose();
    _weight.dispose();
    _temperature.dispose();
    _sugarTest.dispose();
    _serialController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.green.shade50,
        appBar: AppBar(
          title: const Text("Receptionist Dashboard"),
          backgroundColor: Colors.green,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.inventory),
              tooltip: "Inventory",
              onPressed: () {
                Navigator.pushNamed(context, "/inventory",
                    arguments: selectedBranchId);
              },
            ),
            IconButton(
                icon: const Icon(Icons.logout),
                tooltip: "Logout",
                onPressed: _logout),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // Show current serial prominently
                if (currentSerial != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      "Current Serial: $currentSerial",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),

                // Patient form
                TextFormField(
                  controller: _patientName,
                  focusNode: _nameFocus,
                  decoration: const InputDecoration(labelText: "Patient Name"),
                  validator: (val) =>
                      val!.isEmpty ? "Enter patient name" : null,
                ),
                TextFormField(
                  controller: _age,
                  decoration: const InputDecoration(labelText: "Age"),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(
                  controller: _weight,
                  decoration: const InputDecoration(labelText: "Weight"),
                  keyboardType: TextInputType.number,
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedGender,
                  items: genders
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedGender = val),
                  decoration: const InputDecoration(labelText: "Gender"),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedBloodType,
                  items: bloodTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedBloodType = val),
                  decoration: const InputDecoration(labelText: "Blood Type"),
                ),
                TextFormField(
                  controller: _temperature,
                  decoration: const InputDecoration(labelText: "Temperature"),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(
                  controller: _sugarTest,
                  decoration: const InputDecoration(labelText: "Sugar Test"),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranchId,
                  items: branches
                      .map((branch) => DropdownMenuItem(
                          value: branch["id"], child: Text(branch["name"]!)))
                      .toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    final branch = branches.firstWhere((b) => b["id"] == val);
                    setState(() {
                      selectedBranchId = branch["id"];
                      selectedBranchName = branch["name"];
                    });
                    _localBox =
                        await Hive.openBox<Map>("patients_${branch["id"]}");
                    await _fetchCurrentSerial(branch["id"]!);
                  },
                  decoration: const InputDecoration(labelText: "Select Branch"),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50)),
                  onPressed: _savePatient,
                  child: const Text("Save & Send"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
