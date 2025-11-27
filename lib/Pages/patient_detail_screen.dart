import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final Map<String, dynamic> patientData;
  final bool isOnline;
  final Box localBox;
  final String branchId;
  final String doctorId; // ✅ doctor ID added

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientData,
    required this.isOnline,
    required this.localBox,
    required this.branchId,
    required this.doctorId,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _noteController = TextEditingController();
  final _medicineController = TextEditingController();

  late List<Map<String, dynamic>> prescriptions;

  @override
  void initState() {
    super.initState();
    prescriptions = List<Map<String, dynamic>>.from(
      widget.patientData['prescriptions'] ?? [], // ✅ fixed key to match model
    );
  }

  Future<void> _addPrescription() async {
    final note = _noteController.text.trim();
    final medicineName = _medicineController.text.trim();

    if (note.isEmpty && medicineName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Enter a note or medicine")),
      );
      return;
    }

    final newPrescription = {
      "timestamp": DateTime.now().toIso8601String(),
      "doctorId": widget.doctorId, // ✅ link to doctor
      "note": note,
      "medicines": medicineName.isNotEmpty
          ? [
              {"name": medicineName, "quantity": 1}
            ]
          : [],
    };

    setState(() {
      prescriptions.add(newPrescription);
    });

    try {
      if (widget.isOnline) {
        // ✅ Update Firestore
        await _firestore.collection("patients").doc(widget.patientId).set(
          {"prescriptions": prescriptions},
          SetOptions(merge: true),
        );

        // ✅ Update branch inventory if medicine used
        if (medicineName.isNotEmpty) {
          final branchDoc =
              _firestore.collection("inventory").doc(widget.branchId);
          final snapshot = await branchDoc.get();

          if (snapshot.exists) {
            final medicines = List<Map<String, dynamic>>.from(
              snapshot.data()?['medicines'] ?? [],
            );

            final index =
                medicines.indexWhere((m) => m['name'] == medicineName);

            if (index != -1) {
              medicines[index]['stock'] =
                  ((medicines[index]['stock'] ?? 0) - 1).clamp(0, 99999);
              await branchDoc.update({"medicines": medicines});
            }
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Prescription added online")),
        );
      } else {
        // 📦 Save offline
        final pending = widget.localBox
            .get("pendingPrescriptions", defaultValue: []) as List;
        pending.add({
          "patientId": widget.patientId,
          "doctorId": widget.doctorId, // ✅ offline also saves doctor
          "note": note,
          "medicines": medicineName.isNotEmpty
              ? [
                  {"name": medicineName, "quantity": 1}
                ]
              : [],
        });

        await widget.localBox.put("pendingPrescriptions", pending);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("📦 Saved locally (offline)")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
    } finally {
      _noteController.clear();
      _medicineController.clear();
    }
  }

  Widget _buildPrescriptionCard(Map<String, dynamic> presc) {
    final medicines = List<Map<String, dynamic>>.from(presc['medicines'] ?? []);
    final date = DateTime.tryParse(presc['timestamp'] ?? '');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Date: ${date != null ? date.toLocal() : 'Unknown'}",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (presc['doctorId'] != null)
            Text("Doctor ID: ${presc['doctorId']}"),
          if (presc['note'] != null && presc['note'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text("Note: ${presc['note']}"),
            ),
          if (medicines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "Medicines: ${medicines.map((e) => e['name']).join(', ')}",
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.patientData;

    return Scaffold(
      appBar: AppBar(
        title: Text("Patient: ${data['name'] ?? 'Unknown'}"),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🧑 Patient Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Age: ${data['age'] ?? 'N/A'}"),
                    Text("Weight: ${data['weight'] ?? 'N/A'}"),
                    Text("Gender: ${data['gender'] ?? 'N/A'}"),
                    Text("Blood Type: ${data['bloodType'] ?? 'N/A'}"),
                    Text("Temperature: ${data['temperature'] ?? 'N/A'}"),
                    Text("Sugar Test: ${data['sugarTest'] ?? 'N/A'}"),
                    Text(
                        "Assigned Doctor: ${data['assignedDoctorId'] ?? 'N/A'}"),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ➕ Add Prescription
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Add Prescription",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: "Note",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _medicineController,
                      decoration: const InputDecoration(
                        labelText: "Medicine",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: _addPrescription,
                      child: const Text("Save Prescription"),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 📋 Prescriptions List
              const Text(
                "Prescriptions / Notes",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...prescriptions.map((p) => _buildPrescriptionCard(p)),
            ],
          ),
        ),
      ),
    );
  }
}
