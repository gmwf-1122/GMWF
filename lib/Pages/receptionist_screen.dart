// lib/pages/receptionist_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ✅ Import InventoryPage (correct path)
import 'inventory.dart';

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
  final _cnicController = TextEditingController();
  final _patientName = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _temperature = TextEditingController();
  final _sugarTest = TextEditingController();
  final _searchController = TextEditingController();

  String? selectedGender;
  String? selectedBloodType;
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

  late Box<Map> _localBox;
  late StreamSubscription<dynamic> _connectivitySub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _initHive();
    _listenConnectivity();
    _fetchCurrentSerial(widget.branchId);
  }

  Future<void> _initHive() async {
    _localBox = await Hive.openBox<Map>("patients_${widget.branchId}");
    await _syncLocalPatients();
  }

  void _listenConnectivity() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((dynamic event) async {
      List<ConnectivityResult> results;
      if (event is ConnectivityResult) {
        results = [event];
      } else if (event is List<ConnectivityResult>) {
        results = event;
      } else {
        results = [ConnectivityResult.none];
      }

      final online = results.any((r) => r != ConnectivityResult.none);

      if (online && !_isOnline) {
        await _syncLocalPatients();
        await _fetchCurrentSerial(widget.branchId);
      }

      if (mounted) setState(() => _isOnline = online);
    });
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

      int count = 0;
      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null && data.containsKey(datePart)) {
          count = data[datePart] is int
              ? data[datePart]
              : int.tryParse(data[datePart].toString()) ?? 0;
        }
      }

      if (mounted) {
        setState(() {
          currentSerial = "$datePart-${(count + 1).toString().padLeft(3, '0')}";
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
        final cnic = p["cnic"];
        await _firestore
            .collection("branches")
            .doc(widget.branchId)
            .collection("patients")
            .doc(cnic)
            .set(p, SetOptions(merge: true));
      }
      await _localBox.clear();
    } catch (e) {
      debugPrint("❌ Failed to sync local patients: $e");
    }
  }

  Future<void> _savePatient() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final cnic = _cnicController.text.trim();

    final patientRef = _firestore
        .collection("branches")
        .doc(widget.branchId)
        .collection("patients")
        .doc(cnic);

    final existing = await patientRef.get();

    final visitData = {
      "serial": currentSerial ?? "",
      "age": _age.text,
      "weight": _weight.text,
      "temperature": _temperature.text,
      "sugarTest": _sugarTest.text,
      "branchId": widget.branchId,
      "receptionistId": user.uid,
      "createdAt": FieldValue.serverTimestamp(),
    };

    final patientData = {
      "cnic": cnic,
      "name": _patientName.text,
      "gender": selectedGender ?? "Unknown",
      "bloodType": selectedBloodType ?? "Unknown",
      "branchId": widget.branchId,
      "visits": FieldValue.arrayUnion([visitData]),
    };

    try {
      if (_isOnline) {
        if (existing.exists) {
          await patientRef.update({
            "visits": FieldValue.arrayUnion([visitData]),
          });
        } else {
          await patientRef.set(patientData, SetOptions(merge: true));
        }

        final today = DateTime.now();
        final datePart =
            "${today.day.toString().padLeft(2, '0')}${today.month.toString().padLeft(2, '0')}${today.year.toString().substring(2)}";

        await _firestore
            .collection("branches")
            .doc(widget.branchId)
            .collection("metadata")
            .doc("serials")
            .set({datePart: FieldValue.increment(1)}, SetOptions(merge: true));

        await _fetchCurrentSerial(widget.branchId);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Patient registered successfully")),
        );
      } else {
        await _localBox.put(cnic, Map<String, dynamic>.from(patientData));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("📦 Patient saved locally (offline)")),
        );
      }

      _patientName.clear();
      _age.clear();
      _weight.clear();
      _temperature.clear();
      _sugarTest.clear();
      setState(() {
        selectedGender = null;
        selectedBloodType = null;
      });
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

  InputDecoration _roundedInput(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black54),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.green),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _cnicController.dispose();
    _patientName.dispose();
    _age.dispose();
    _weight.dispose();
    _temperature.dispose();
    _sugarTest.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(76, 175, 80, 1),
        appBar: AppBar(
          title: const Text("Receptionist Dashboard",
              style: TextStyle(color: Colors.white)),
          backgroundColor: const Color.fromRGBO(76, 175, 80, 1),
          automaticallyImplyLeading: false,
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        InventoryPage(branchId: widget.branchId),
                  ),
                );
              },
              icon: const Icon(Icons.inventory),
              label: const Text("Inventory"),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Row(
                  children: [
                    const Text("Patient Details",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const Spacer(),
                    if (currentSerial != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(currentSerial!,
                            style: const TextStyle(
                                color: Colors.green,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _cnicController,
                                  decoration:
                                      _roundedInput("CNIC (XXXXX-XXXXXXX-X)"),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(13),
                                    CnicInputFormatter(),
                                  ],
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Enter CNIC';
                                    }
                                    if (!RegExp(r'^\d{5}-\d{7}-\d{1}$')
                                        .hasMatch(v)) {
                                      return 'Invalid CNIC format';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _patientName,
                                  decoration: _roundedInput("Patient Name"),
                                  validator: (v) =>
                                      v!.isEmpty ? "Enter patient name" : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedGender,
                                  decoration: _roundedInput("Gender"),
                                  items: genders
                                      .map((g) => DropdownMenuItem(
                                          value: g, child: Text(g)))
                                      .toList(),
                                  onChanged: (val) =>
                                      setState(() => selectedGender = val),
                                  validator: (v) =>
                                      v == null ? "Select gender" : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedBloodType,
                                  decoration: _roundedInput("Blood Type"),
                                  items: bloodTypes
                                      .map((b) => DropdownMenuItem(
                                          value: b, child: Text(b)))
                                      .toList(),
                                  onChanged: (val) =>
                                      setState(() => selectedBloodType = val),
                                  validator: (v) =>
                                      v == null ? "Select blood type" : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _age,
                                  decoration: _roundedInput("Age"),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _weight,
                                  decoration: _roundedInput("Weight (kg)"),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _temperature,
                                  decoration: _roundedInput("Temperature (°C)"),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _sugarTest,
                                  decoration: _roundedInput("Sugar Test"),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30))),
                            onPressed: _savePatient,
                            child: const Text("Confirm"),
                          ),
                        ],
                      ),
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
}

class CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited =
        digitsOnly.length <= 13 ? digitsOnly : digitsOnly.substring(0, 13);

    String formatted;
    if (limited.length <= 5) {
      formatted = limited;
    } else if (limited.length <= 12) {
      formatted = '${limited.substring(0, 5)}-${limited.substring(5)}';
    } else {
      formatted =
          '${limited.substring(0, 5)}-${limited.substring(5, 12)}-${limited.substring(12)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
