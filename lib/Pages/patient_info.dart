// lib/pages/patient_info.dart
// FIXED: Replaced the outer SingleChildScrollView + Padding(24) with a direct
// Padding(16) so there's no double-padding inside the Card. The vital tiles
// now use full height and don't feel cramped. Added overflow handling so the
// vital row never wraps weirdly on smaller screens.

import 'package:flutter/material.dart';

class PatientInfo extends StatelessWidget {
  final Map<String, dynamic>? patientData;

  const PatientInfo({
    super.key,
    required this.patientData,
  });

  static const Color _teal  = Color(0xFF00695C);
  static const Color _amber = Color(0xFFFFA000);

  Widget _buildVital({
    required String label,
    required String value,
    required IconData icon,
    required Color backgroundColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When no patient is selected
    if (patientData == null || patientData!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 70, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "Select a patient to view details",
              style: TextStyle(fontSize: 18, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final patient = patientData!;
    final vitals  = Map<String, dynamic>.from(patient['vitals'] ?? {});

    // FIX: Use Padding(16) directly — no extra SingleChildScrollView wrapper.
    // The card is fixed height (230px) so there's no need to scroll; removing
    // the scroll wrapper also prevents the inner Column from miscalculating height.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // ── Patient name + serial badge ──────────────────────────────────
          Row(
            children: [
              const Icon(Icons.person, color: _teal, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  patient['patientName'] ?? patient['name'] ?? 'Unknown Patient',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: _teal),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _amber, width: 2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.confirmation_number, color: _amber, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      patient['serial'] ?? '-',
                      style: const TextStyle(
                          color: _amber, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Vital tiles row ──────────────────────────────────────────────
          SizedBox(
            height: 86,
            child: Row(
              children: [
                _buildVital(
                  label: "Age",
                  value: (vitals['age'] ?? patient['age'] ?? '-').toString(),
                  icon: Icons.calendar_today,
                  backgroundColor: _teal,
                ),
                _buildVital(
                  label: "Gender",
                  value: vitals['gender'] ?? patient['gender'] ?? '-',
                  icon: Icons.person_outline,
                  backgroundColor: Colors.blue[700]!,
                ),
                _buildVital(
                  label: "Blood Group",
                  value: vitals['bloodGroup'] ?? patient['bloodGroup'] ?? '-',
                  icon: Icons.bloodtype,
                  backgroundColor: Colors.red[700]!,
                ),
                _buildVital(
                  label: "BP",
                  value: vitals['bp'] ?? '-',
                  icon: Icons.favorite,
                  backgroundColor: Colors.red,
                ),
                _buildVital(
                  label: "Temp",
                  value: vitals['temp'] != null ? "${vitals['temp']} °C" : '-',
                  icon: Icons.thermostat,
                  backgroundColor: Colors.orange,
                ),
                _buildVital(
                  label: "Sugar",
                  value: vitals['sugar'] ?? '-',
                  icon: Icons.opacity,
                  backgroundColor: Colors.purple,
                ),
                _buildVital(
                  label: "Weight",
                  value: vitals['weight'] != null ? "${vitals['weight']} kg" : '-',
                  icon: Icons.monitor_weight,
                  backgroundColor: Colors.green[700]!,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}