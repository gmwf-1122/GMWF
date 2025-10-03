// lib/pages/doctor_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;

  String? _selectedPatientId; // CNIC or fallback id
  String? _selectedSerial; // visit serial
  Map<String, dynamic>? _selectedPatientData;
  final TextEditingController _searchController = TextEditingController();

  /// prescriptions map: key = medId, value = { 'name','qty','isCustom','expiryDate','dosage','type' }
  final Map<String, Map<String, dynamic>> _prescriptions = {};

  String? _diagnosis;
  String? _presentComplaint;
  final List<String> _investigations = [];

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      setState(() {
        _isOnline = results.any((r) => r != ConnectivityResult.none);
      });
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ------------------ Helpers ------------------

  int toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  String formatDate(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) {
      final dt = v.toDate().toLocal();
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    }
    return v.toString();
  }

  bool isExpired(dynamic v) {
    if (v == null) return false;
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is String && v.isNotEmpty) {
      // try parsing common formats yyyy-mm-dd or dd-mm-yyyy (best-effort)
      try {
        dt = DateTime.parse(v);
      } catch (_) {
        // ignore parse error
      }
    }
    if (dt == null) return false;
    return dt.isBefore(DateTime.now());
  }

  // ---------------- Firestore ops ----------------

  Future<void> savePrescription({bool isRepeat = false}) async {
    if (_selectedPatientId == null ||
        _selectedPatientData == null ||
        _selectedSerial == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Please select a patient first.")),
      );
      return;
    }

    try {
      final medicinesList = _prescriptions.entries.map((e) {
        return {
          'id': e.key,
          'name': e.value['name'],
          'qty': e.value['qty'],
          'isCustom': e.value['isCustom'] ?? false,
          'expiryDate': e.value['expiryDate'] ?? '',
          'dosage': e.value['dosage'] ?? '',
          'type': e.value['type'] ?? '',
        };
      }).toList();

      final prescriptionData = {
        'doctorId': widget.doctorId,
        'pc': _presentComplaint ?? '',
        'diagnosis': _diagnosis ?? '',
        'investigations': _investigations,
        'medicines': medicinesList,
        'createdAt': FieldValue.serverTimestamp(),
        'serial': _selectedSerial,
      };

      final branchRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId);

      // 1. Save under prescriptions/{cnic}/visits/{serial}
      final presRef = branchRef
          .collection('prescriptions')
          .doc(_selectedPatientId)
          .collection('visits')
          .doc(_selectedSerial);
      await presRef.set(prescriptionData);

      // 2. Update patient status + last diagnosis
      await branchRef
          .collection('patients')
          .doc(_selectedPatientData!['id'])
          .update({
        'status': isRepeat ? 'Repeat' : 'Prescribed',
        'lastDiagnosis': _diagnosis ?? '',
        'presentComplaint': _presentComplaint ?? '',
      });

      // 3. Deduct from inventory for non-custom medicines
      for (var med in medicinesList) {
        if (!(med['isCustom'] ?? false)) {
          final invRef = branchRef.collection('inventory').doc(med['id']);
          await invRef.update({
            'quantity': FieldValue.increment(-(med['qty'] ?? 0)),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRepeat
              ? '🔁 Prescription repeated successfully.'
              : '✅ Prescription saved successfully.'),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error saving prescription: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed to save prescription: $e')),
      );
    }
  }

  // LOAD latest prescription (if exists)
  Future<void> loadLatestPrescription() async {
    if (_selectedPatientId == null || _selectedSerial == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(_selectedPatientId)
          .collection('visits')
          .doc(_selectedSerial)
          .get();

      if (!snap.exists) return;

      final data = snap.data()!;
      setState(() {
        _presentComplaint = data['pc'] ?? '';
        _diagnosis = data['diagnosis'] ?? '';
        _investigations.clear();
        _investigations.addAll(List<String>.from(data['investigations'] ?? []));
        _prescriptions.clear();
        for (var med in (data['medicines'] ?? [])) {
          final id =
              med['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
          _prescriptions[id] = Map<String, dynamic>.from(med);
        }
      });
    } catch (e) {
      debugPrint("⚠️ Error loading prescription: $e");
    }
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            buildTopBar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 1, child: buildPatientsList()),
                  const VerticalDivider(width: 1, color: Colors.black26),
                  Expanded(
                    flex: 2,
                    child: _selectedPatientData == null
                        ? const Center(
                            child: Text(
                              "👈 Select a patient",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          )
                        : buildPatientDetails(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 70,
      color: Colors.black, // classic black bar
      child: Row(
        children: [
          // Left side - Doctor
          const Row(
            children: [
              Icon(FontAwesomeIcons.userDoctor, size: 28, color: Colors.white),
              SizedBox(width: 10),
              Text('Doctor',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20)),
            ],
          ),

          // Center - Logo
          Expanded(
            child: Center(
              child: Image.asset(
                'assets/logo/gmwf.png',
                height: 38, // adjust logo size
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Right side - Cloud + Logout
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4), // prevent cut-off
                    child: Icon(
                      _isOnline
                          ? FontAwesomeIcons.cloudArrowUp
                          : FontAwesomeIcons.cloud,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(
                      FontAwesomeIcons.solidCircle,
                      size: 10,
                      color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: confirmLogout,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black),
                icon: const Icon(FontAwesomeIcons.rightFromBracket),
                label: const Text("Logout"),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildPatientsList() {
    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔎 Search Bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by Serial or CNIC',
                prefixIcon: const Icon(FontAwesomeIcons.magnifyingGlass),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 12),

            // 🔽 Patient List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('patients')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("❌ No patient found"));
                  }

                  // Filter patients by search
                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final query = _searchController.text.trim().toLowerCase();
                    return query.isEmpty ||
                        (data['visitDetails']?['serial'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(query) ||
                        (data['cnic'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(query);
                  }).toList();

                  if (docs.isEmpty) {
                    return const Center(child: Text("❌ No matching patient"));
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final id = docs[i].id;
                      final status = data['status'] ?? 'New';

                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(FontAwesomeIcons.user, size: 18),
                        ),
                        title: Text(
                          data['name'] ?? "Unknown",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("CNIC: ${data['cnic'] ?? "--"}"),
                            Text(
                              "Serial: ${data['visitDetails']?['serial'] ?? "--"}",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: status == 'Prescribed' || status == 'Repeat'
                            ? const Icon(FontAwesomeIcons.circleCheck,
                                color: Colors.green)
                            : const Icon(FontAwesomeIcons.clock,
                                color: Colors.orange),
                        onTap: () {
                          final patientCnic = (data['cnic'] != null &&
                                  data['cnic'].toString().isNotEmpty)
                              ? data['cnic'].toString()
                              : id;

                          setState(() {
                            _selectedPatientId = patientCnic;
                            _selectedSerial = data['visitDetails']?['serial'];
                            _selectedPatientData = {...data, 'id': id};
                          });

                          loadLatestPrescription();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPatientDetails() {
    final data = _selectedPatientData!;
    final visit = data['visitDetails'] ?? {};

    return Container(
      margin: const EdgeInsets.all(12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // patient icon + name
              Row(
                children: [
                  const Icon(FontAwesomeIcons.user, size: 22),
                  const SizedBox(width: 8),
                  Text("${data['name'] ?? "Unknown"}",
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(FontAwesomeIcons.idCard, size: 16),
                const SizedBox(width: 6),
                Text("CNIC: ${data['cnic'] ?? "--"}"),
              ]),
              Row(children: [
                const Icon(FontAwesomeIcons.hashtag, size: 16),
                const SizedBox(width: 6),
                Text("Serial: ${visit['serial'] ?? "--"}"),
              ]),
              const Divider(height: 20),
              Wrap(spacing: 12, runSpacing: 12, children: [
                vitalCard('Age', visit['age']),
                vitalCard('Weight', visit['weight']),
                vitalCard('BP', visit['bloodPressure']),
                vitalCard('Sugar', visit['sugar']),
                vitalCard('Temp', visit['temperature']),
                vitalCard('Gender', visit['gender']),
                vitalCard('Blood', visit['bloodGroup']),
              ]),
              const Divider(height: 20),
              ListTile(
                leading: const Icon(FontAwesomeIcons.stethoscope),
                title: const Text('P/C',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text(
                    _presentComplaint ?? (data['presentComplaint'] ?? '--')),
              ),
              ListTile(
                leading: const Icon(FontAwesomeIcons.notesMedical),
                title: const Text('Diagnosis',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text(
                    _diagnosis ?? (data['lastDiagnosis'] ?? 'No diagnosis')),
              ),
              // Medicines section (fixed layout)
              ListTile(
                leading: const Icon(FontAwesomeIcons.vial),
                title: const Text(
                  'Medicines',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: _prescriptions.isEmpty
                    ? const Text('No medicines added')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _prescriptions.entries.map((e) {
                          final name = e.value['name'];
                          final qty = e.value['qty'];
                          final dosage = e.value['dosage'] ?? '';
                          final isCustom = e.value['isCustom'] ?? false;
                          final expiry = e.value['expiryDate'] ?? '';

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ✅ Icon fixed next to medicine name
                                const Icon(FontAwesomeIcons.pills,
                                    size: 16, color: Colors.black54),
                                const SizedBox(width: 8),

                                // Medicine details (left side)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$name${isCustom ? " (Custom)" : ""}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      if (dosage.isNotEmpty)
                                        Text("Dose: $dosage",
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey)),
                                      if (expiry.isNotEmpty)
                                        Text("Exp: $expiry",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isExpired(expiry)
                                                  ? Colors.red
                                                  : Colors.black,
                                            )),
                                    ],
                                  ),
                                ),

                                // Qty on the right
                                Text(
                                  "Qty: $qty",
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),

              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(FontAwesomeIcons.flask),
                title: const Text('Lab Tests',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: _investigations.isEmpty
                    ? const Text('No investigations added')
                    : Wrap(
                        spacing: 6,
                        children: _investigations
                            .map((t) => Chip(label: Text(t)))
                            .toList()),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                ElevatedButton.icon(
                    icon: const Icon(FontAwesomeIcons.penToSquare),
                    label: const Text("Add/Update Prescription"),
                    onPressed: () => openPrescriptionDialog()),
                ElevatedButton.icon(
                    icon: const Icon(FontAwesomeIcons.solidFloppyDisk),
                    label: const Text("Save"),
                    onPressed: () => savePrescription(isRepeat: false)),
                ElevatedButton.icon(
                    icon: const Icon(FontAwesomeIcons.repeat),
                    label: const Text("Repeat"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent),
                    onPressed: () => savePrescription(isRepeat: true)),
              ])
            ]),
          ),
        ),
      ),
    );
  }

  Widget vitalCard(String label, dynamic value) {
    final display =
        (value == null || value.toString().isEmpty) ? "--" : value.toString();
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black54)),
        const SizedBox(height: 4),
        Text(display, style: const TextStyle(fontSize: 16)),
      ]),
    );
  }

  // ---------------- Prescription dialog ----------------
  void openPrescriptionDialog() {
    final pcController = TextEditingController(text: _presentComplaint ?? "");
    final diagnosisController = TextEditingController(text: _diagnosis ?? "");
    final investigationController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Prescription"),
        content: SizedBox(
          width: 700, // fixed width
          height: 520, // fixed height to allow scrolling inside
          child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // P/C at top
              const Text("P/C (Patient Condition)",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: pcController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLines: null,
                minLines: 2,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "Patient Condition"),
              ),
              const SizedBox(height: 12),

              // Diagnosis
              const Text("Diagnosis",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: diagnosisController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLines: null,
                minLines: 2,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), hintText: "Diagnosis"),
              ),
              const SizedBox(height: 12),

              // Medicines area
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Medicines",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () async {
                      await openMedicineDialog(); // adds to _prescriptions internally
                      setState(() {}); // refresh dialog view
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Add Medicine"),
                  )
                ],
              ),
              const SizedBox(height: 6),
              Card(
                elevation: 1,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  child: _prescriptions.isEmpty
                      ? const Text("No medicines added")
                      : Column(
                          children: _prescriptions.entries.map((e) {
                            final med = e.value;
                            return ListTile(
                              dense: true,
                              title: Text(med['name'] ?? ''),
                              subtitle: Text(
                                  "Qty: ${med['qty']} • Dose: ${med['dosage'] ?? ''}"),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () async {
                                      // allow editing quantity/dosage for existing med
                                      final res = await showQtyDosageEditor(
                                          medId: e.key,
                                          currentName: med['name'] ?? '',
                                          currentQty:
                                              med['qty']?.toString() ?? '1',
                                          currentDosage: med['dosage'] ?? '');
                                      if (res != null) {
                                        setState(() {
                                          _prescriptions[e.key]!['qty'] =
                                              res['qty'];
                                          _prescriptions[e.key]!['dosage'] =
                                              res['dosage'];
                                        });
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () {
                                      setState(() {
                                        _prescriptions.remove(e.key);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ),

              const SizedBox(height: 12),
              // Investigations at the bottom
              const Text("Lab Tests",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: investigationController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: "Add Lab Tests",
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          setState(() {
                            _investigations.add(val.trim());
                          });
                          investigationController.clear();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final val = investigationController.text.trim();
                      if (val.isNotEmpty) {
                        setState(() {
                          _investigations.add(val);
                        });
                        investigationController.clear();
                      }
                    },
                  )
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _investigations
                    .map((i) => Chip(
                          label: Text(i),
                          onDeleted: () =>
                              setState(() => _investigations.remove(i)),
                        ))
                    .toList(),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () {
                setState(() {
                  _presentComplaint = pcController.text.trim();
                  _diagnosis = diagnosisController.text.trim();
                });
                Navigator.pop(ctx);
              },
              child: const Text("Save"))
        ],
      ),
    );
  }

  // Opens inventory list and allows adding medicine with qty + dosage
  Future<void> openMedicineDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Add Medicine from Inventory"),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('inventory')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text("No inventory items"));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final id = doc.id;
                    final name = data['name'] ?? 'Unknown';
                    final type = data['type'] ?? '';
                    final expiry = formatDate(data['expiryDate']);
                    final qtyInStock = toInt(data['quantity']);
                    final expired = isExpired(data['expiryDate']);

                    IconData icon;
                    switch (type.toString().toLowerCase()) {
                      case 'tablet':
                        icon = FontAwesomeIcons.tablets;
                        break;
                      case 'capsule':
                        icon = FontAwesomeIcons.capsules;
                        break;
                      case 'syrup':
                        icon = FontAwesomeIcons.bottleDroplet;
                        break;
                      case 'injection':
                        icon = FontAwesomeIcons.syringe;
                        break;
                      case 'drip':
                        icon = FontAwesomeIcons.prescription;
                        break;
                      default:
                        icon = FontAwesomeIcons.pills;
                    }

                    return Card(
                      color: expired ? Colors.red[50] : Colors.white,
                      child: ListTile(
                        leading: Icon(icon,
                            color: expired ? Colors.red : Colors.black),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (expiry.isNotEmpty)
                              Text("Exp: $expiry",
                                  style: TextStyle(
                                      color: expired ? Colors.red : null)),
                            Text("Stock: $qtyInStock"),
                          ],
                        ),
                        onTap: expired
                            ? null
                            : () async {
                                final result = await showQtyDosageDialog(
                                  context: context,
                                  medId: id,
                                  medName: name,
                                  medType: type,
                                  maxQty: qtyInStock,
                                  expiry: expiry,
                                  isCustom: false,
                                );
                                if (result != null) {
                                  setState(() {
                                    _prescriptions[id] = {
                                      'name': name,
                                      'qty': result['qty'],
                                      'isCustom': false,
                                      'expiryDate': expiry,
                                      'dosage': result['dosage'],
                                      'type': type,
                                    };
                                  });
                                  Navigator.pop(
                                      ctx); // close inventory dialog after add
                                }
                              },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () async {
                  // Add custom medicine flow
                  final custom = await showCustomMedicineDialog(context);
                  if (custom != null) {
                    setState(() {
                      _prescriptions[custom['id']] = custom;
                    });
                    Navigator.pop(ctx);
                  }
                },
                child: const Text("Custom Medicine")),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Close")),
          ],
        );
      },
    );
  }

  // dialog for qty + dosage (used for both inventory med and editing)
  Future<Map<String, dynamic>?> showQtyDosageDialog({
    required BuildContext context,
    required String medId,
    required String medName,
    required String medType,
    required int maxQty,
    required String expiry,
    bool isCustom = false,
    String? currentQty,
    String? currentDosage,
  }) async {
    final qtyController = TextEditingController(text: currentQty ?? '1');
    String selectedDosage = currentDosage ?? 'Once a day';
    final customDosageController = TextEditingController();

    final dosageOptions = [
      "Once a day",
      "Twice a day",
      "Thrice a day",
      "Every 6 hours",
      "Before meal",
      "After meal",
      "Custom",
    ];

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(medName),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: "Quantity (max $maxQty)"),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: dosageOptions.contains(selectedDosage)
                    ? selectedDosage
                    : 'Once a day',
                items: dosageOptions
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) selectedDosage = v;
                },
                decoration: const InputDecoration(labelText: "Dosage"),
              ),
              const SizedBox(height: 8),
              // show custom dosage input when custom selected
              Builder(builder: (bctx) {
                if (selectedDosage == 'Custom') {
                  return TextField(
                    controller: customDosageController,
                    decoration:
                        const InputDecoration(labelText: "Custom dosage"),
                  );
                }
                return const SizedBox.shrink();
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () {
                final parsedQty = int.tryParse(qtyController.text.trim()) ?? 1;
                final finalDosage = (selectedDosage == 'Custom' &&
                        customDosageController.text.trim().isNotEmpty)
                    ? customDosageController.text.trim()
                    : selectedDosage;
                if (parsedQty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Quantity must be > 0")));
                  return;
                }
                Navigator.pop(ctx, {
                  'qty': parsedQty,
                  'dosage': finalDosage,
                });
              },
              child: const Text("Add"))
        ],
      ),
    );
  }

  // Custom medicine dialog
  Future<Map<String, dynamic>?> showCustomMedicineDialog(
      BuildContext context) async {
    final nameController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final dosageController = TextEditingController();

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Custom Medicine"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Name")),
            TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Qty")),
            TextField(
                controller: dosageController,
                decoration:
                    const InputDecoration(labelText: "Dosage (optional)")),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final qty = int.tryParse(qtyController.text.trim()) ?? 1;
              final dosage = dosageController.text.trim();
              if (name.isEmpty) return;
              final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
              Navigator.pop(ctx, {
                'id': id,
                'name': name,
                'qty': qty,
                'isCustom': true,
                'expiryDate': '',
                'dosage': dosage,
                'type': 'Custom',
              });
            },
            child: const Text("Add"),
          )
        ],
      ),
    );
  }

  // edit qty/dosage for an existing med (used in prescription dialog)
  Future<Map<String, dynamic>?> showQtyDosageEditor({
    required String medId,
    required String currentName,
    required String currentQty,
    required String currentDosage,
  }) {
    return showQtyDosageDialog(
      context: context,
      medId: medId,
      medName: currentName,
      medType: '',
      maxQty: 99999,
      expiry: '',
      isCustom: false,
      currentQty: currentQty,
      currentDosage: currentDosage,
    );
  }

  // Logout helpers
  void confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                logout();
              },
              child: const Text("Logout")),
        ],
      ),
    );
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }
}
