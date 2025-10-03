// lib/pages/token_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'receptionist_screen.dart';

class TokenScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;

  const TokenScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
  });

  @override
  State<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends State<TokenScreen> {
  final _searchController = TextEditingController();
  Map<String, dynamic>? selectedPatient;
  String? selectedPatientId;

  String? nextSerial; // ✅ Show next available serial
  String _tempUnit = "C";

  // ===================== Patient Search =====================
  Future<void> _searchPatient() async {
    final search = _searchController.text.trim();
    if (search.isEmpty) return;

    setState(() {
      selectedPatient = null;
      selectedPatientId = null;
      nextSerial = null;
    });

    try {
      final patientsRef = FirebaseFirestore.instance
          .collection("branches")
          .doc(widget.branchId)
          .collection("patients");

      // 🔹 First try CNIC
      final cnicDoc = await patientsRef.doc(search).get();
      if (cnicDoc.exists) {
        setState(() {
          selectedPatient = cnicDoc.data();
          selectedPatientId = cnicDoc.id;
        });
        await _fetchNextSerial(); // get next available serial
        return;
      }

      // 🔹 Else try phone
      final byPhone = await patientsRef.where("phone", isEqualTo: search).get();
      if (byPhone.docs.isNotEmpty) {
        final result = byPhone.docs.first;
        setState(() {
          selectedPatient = result.data();
          selectedPatientId = result.id;
        });
        await _fetchNextSerial();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ No patient found")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error searching patient: $e")),
      );
    }
  }

  // ===================== Serial =====================
  Future<void> _fetchNextSerial() async {
    final now = DateTime.now();
    final todayKey =
        "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year.toString().substring(2)}";

    final branchRef =
        FirebaseFirestore.instance.collection("branches").doc(widget.branchId);

    final serialDocRef = branchRef.collection("serials").doc(todayKey);
    final serialDoc = await serialDocRef.get();

    int currentNumber = 0;
    if (serialDoc.exists) {
      currentNumber = serialDoc.data()?["lastNumber"] ?? 0;
    }

    final nextNumber = currentNumber + 1;
    final serialString = "$todayKey-${nextNumber.toString().padLeft(3, '0')}";

    setState(() => nextSerial = serialString);
  }

  // ===================== Vitals Dialog =====================
  Future<void> _showVitalsDialog() async {
    if (selectedPatient == null || selectedPatientId == null) return;

    final bpController = TextEditingController();
    final tempController = TextEditingController();
    final sugarController = TextEditingController();
    final weightController = TextEditingController();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.black.withOpacity(0.85),
        title: Text(
          "Enter Vitals\nNext Serial: ${nextSerial ?? '...'}",
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            children: [
              _bpField(bpController),
              const SizedBox(height: 12),
              _tempField(tempController),
              const SizedBox(height: 12),
              _digitField(sugarController, "Sugar (mg/dL)", 3),
              const SizedBox(height: 12),
              _digitField(weightController, "Weight (kg)", 3),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, "Zakat"),
            child: const Text("Zakat", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.pop(ctx, "Non-Zakat"),
            child:
                const Text("Non-Zakat", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (choice != null) {
      await _saveVisit(
        bpController.text,
        tempController.text,
        _tempUnit,
        sugarController.text,
        weightController.text,
        choice,
      );
    }
  }

  // ===================== Save Visit =====================
  Future<void> _saveVisit(
    String bp,
    String temp,
    String tempUnit,
    String sugar,
    String weight,
    String status,
  ) async {
    try {
      final branchRef = FirebaseFirestore.instance
          .collection("branches")
          .doc(widget.branchId);

      final now = DateTime.now();
      final todayKey =
          "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year.toString().substring(2)}";

      final serialDocRef = branchRef.collection("serials").doc(todayKey);
      final serialDoc = await serialDocRef.get();

      int currentNumber = 0;
      if (serialDoc.exists) {
        currentNumber = serialDoc.data()?["lastNumber"] ?? 0;
      }

      final nextNumber = currentNumber + 1;
      final serialString = "$todayKey-${nextNumber.toString().padLeft(3, '0')}";

      // 🔹 Update or create today's serial doc
      await serialDocRef.set({
        "lastNumber": nextNumber,
        "updatedAt": FieldValue.serverTimestamp(),
        "records": FieldValue.arrayUnion([
          {
            "serial": serialString,
            "cnic": selectedPatient?["cnic"] ?? selectedPatientId,
            "name": selectedPatient?["name"],
            "phone": selectedPatient?["phone"],
            "status": status,
            "createdAt": FieldValue.serverTimestamp(),
          }
        ]),
      }, SetOptions(merge: true));

      // 🔹 Save in visits
      final visitData = {
        "serial": serialString,
        "branchId": widget.branchId,
        "patientId": selectedPatientId,
        "cnic": selectedPatient?["cnic"] ?? selectedPatientId,
        "name": selectedPatient?["name"] ?? "",
        "phone": selectedPatient?["phone"] ?? "",
        "status": status,
        "vitals": {
          "bp": bp,
          "temp": temp,
          "tempUnit": tempUnit,
          "sugar": sugar,
          "weight": weight,
        },
        "createdAt": FieldValue.serverTimestamp(),
        "createdBy": widget.receptionistId,
      };

      await FirebaseFirestore.instance
          .collection("visits")
          .doc(serialString)
          .set(visitData);

      // 🔹 Update patient's last visit
      await branchRef.collection("patients").doc(selectedPatientId).update({
        "lastVisit": {
          "serial": serialString,
          "status": status,
          "createdAt": FieldValue.serverTimestamp(),
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Token generated #$serialString")),
      );

      setState(() => nextSerial = null); // reset for new calculation
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error generating token: $e")),
      );
    }
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage("assets/images/1.jpg"),
            fit: BoxFit.cover,
          ),
          color: Colors.green.withOpacity(0.8),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 600,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Token Generator",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  if (nextSerial != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      "Next Token: $nextSerial",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // 🔹 Search
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                              "Search by CNIC or Phone", Icons.search),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _searchPatient,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 20),
                        ),
                        child: const Text("Search"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (selectedPatient != null) ...[
                    Card(
                      color: Colors.white.withOpacity(0.1),
                      child: ListTile(
                        title: Text(
                          selectedPatient!["name"] ?? "No Name",
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          "CNIC: $selectedPatientId\nPhone: ${selectedPatient!["phone"]}",
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _showVitalsDialog,
                      icon: const Icon(Icons.add),
                      label: const Text("Enter Vitals & Generate Token"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),

                  // Back to Reception
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReceptionistScreen(
                            branchId: widget.branchId,
                            receptionistId: widget.receptionistId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text("Back to Reception"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===================== Input Fields =====================
  Widget _bpField(TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: _dialogDecoration("BP (e.g. 120/80)"),
      keyboardType: TextInputType.number,
      inputFormatters: [_BPInputFormatter()],
    );
  }

  Widget _tempField(TextEditingController controller) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: _dialogDecoration("Temp"),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
            ],
          ),
        ),
        const SizedBox(width: 10),
        DropdownButton<String>(
          value: _tempUnit,
          dropdownColor: Colors.black87,
          items: const [
            DropdownMenuItem(value: "C", child: Text("°C")),
            DropdownMenuItem(value: "F", child: Text("°F")),
          ],
          onChanged: (val) => setState(() => _tempUnit = val ?? "C"),
          style: const TextStyle(color: Colors.white),
          iconEnabledColor: Colors.white,
        )
      ],
    );
  }

  Widget _digitField(
      TextEditingController controller, String label, int maxLen) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: _dialogDecoration(label),
      keyboardType: TextInputType.number,
      maxLength: maxLen,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
  }

  InputDecoration _dialogDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white70),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white70),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    );
  }
}

// ===================== Formatters =====================
class _BPInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 3) {
      text = text.substring(0, 3) + '/' + text.substring(3);
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
