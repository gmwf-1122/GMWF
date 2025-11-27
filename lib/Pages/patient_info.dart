import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PatientInfo extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? patientData;

  const PatientInfo({
    super.key,
    required this.branchId,
    required this.patientData,
  });

  @override
  State<PatientInfo> createState() => _PatientInfoState();
}

class _PatientInfoState extends State<PatientInfo> {
  Map<String, dynamic>? _fullPatientData;
  bool _loading = true;

  static const Color _green = Color(0xFF2E7D32);
  static const Color _amber = Color(0xFFFFA000);

  @override
  void initState() {
    super.initState();
    _fetchFullPatientData();
  }

  Future<void> _fetchFullPatientData() async {
    if (widget.patientData == null) return;
    setState(() => _loading = true);

    try {
      final today = DateFormat('ddMMyy').format(DateTime.now());
      final serialId = widget.patientData!['id'];

      // Check zakat first
      var doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(today)
          .collection('zakat')
          .doc(serialId)
          .get();

      // If not found, check non-zakat
      if (!doc.exists) {
        doc = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('serials')
            .doc(today)
            .collection('non-zakat')
            .doc(serialId)
            .get();
      }

      if (!doc.exists) {
        setState(() => _loading = false);
        return;
      }

      final serialData = doc.data()!;
      final cnic = serialData['patientCNIC'];

      // Fetch full patient info
      final patientDoc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('patients')
          .doc(cnic)
          .get();

      if (patientDoc.exists) {
        setState(() {
          _fullPatientData = {...serialData, ...patientDoc.data()!};
          _loading = false;
        });
      } else {
        setState(() {
          _fullPatientData = serialData;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching patient info: $e");
      setState(() => _loading = false);
    }
  }

  Widget _buildVitalsCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      width: 110, // fixed width for horizontal scroll
      height: 65,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_fullPatientData == null) {
      return const Center(child: Text("No patient info available"));
    }

    final patient = _fullPatientData!;

    return Container(
      height: 320, // 👈 Fixed height (adjust as needed)
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Name + Serial Row
          Row(
            children: [
              const Icon(Icons.person, color: Colors.black87),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  patient['patientName'] ?? patient['name'] ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.confirmation_number, color: _amber),
                  const SizedBox(width: 4),
                  Text(
                    patient['serial'] ?? '-',
                    style: const TextStyle(
                      color: _amber,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Title for vitals
          const Row(
            children: [
              Icon(Icons.monitor_heart, color: _green, size: 20),
              SizedBox(width: 6),
              Text(
                "Vitals",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _green,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Horizontally scrollable vitals row
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildVitalsCard("Age", patient['age']?.toString() ?? '-',
                      Icons.calendar_today, _green),
                  _buildVitalsCard("Gender", patient['gender'] ?? '-',
                      Icons.male, Colors.blueAccent),
                  _buildVitalsCard("Blood", patient['bloodGroup'] ?? '-',
                      Icons.bloodtype, Colors.redAccent),
                  _buildVitalsCard("BP", patient['vitals']?['bp'] ?? '-',
                      Icons.favorite, Colors.red),
                  _buildVitalsCard(
                      "Temp",
                      patient['vitals']?['temp'] != null
                          ? "${patient['vitals']!['temp']} ${patient['vitals']!['tempUnit'] ?? ''}"
                          : '-',
                      Icons.thermostat,
                      Colors.orange),
                  _buildVitalsCard("Sugar", patient['vitals']?['sugar'] ?? '-',
                      Icons.opacity, Colors.purple),
                  _buildVitalsCard(
                      "Weight",
                      patient['vitals']?['weight'] ?? '-',
                      Icons.fitness_center,
                      Colors.greenAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
