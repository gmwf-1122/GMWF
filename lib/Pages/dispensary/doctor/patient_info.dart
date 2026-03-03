// lib/pages/patient_info.dart
// MOBILE: Fully responsive — stacks vertically on small screens,
// vitals wrap instead of overflow, font sizes scale with screen width.

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
    required bool compact,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 6 : 10,
        horizontal: compact ? 4 : 6,
      ),
      margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(compact ? 10 : 16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: compact ? 14 : 20),
          SizedBox(height: compact ? 2 : 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 8 : 10.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: compact ? 1 : 3),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 10 : 13,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (patientData == null || patientData!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 50, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              "Select a patient to view details",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final patient = patientData!;
    final vitals  = Map<String, dynamic>.from(patient['vitals'] ?? {});

    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 480;
      final compact  = constraints.maxWidth < 360;

      final vitalsList = [
        {'label': 'Age',    'value': (vitals['age'] ?? patient['age'] ?? '-').toString(), 'icon': Icons.calendar_today, 'color': _teal},
        {'label': 'Gender', 'value': vitals['gender'] ?? patient['gender'] ?? '-',        'icon': Icons.person_outline, 'color': Colors.blue[700]!},
        {'label': 'Blood',  'value': vitals['bloodGroup'] ?? patient['bloodGroup'] ?? '-','icon': Icons.bloodtype,       'color': Colors.red[700]!},
        {'label': 'BP',     'value': vitals['bp'] ?? '-',                                 'icon': Icons.favorite,        'color': Colors.red},
        {'label': 'Temp',   'value': vitals['temp'] != null ? "${vitals['temp']}°C" : '-','icon': Icons.thermostat,      'color': Colors.orange},
        {'label': 'Sugar',  'value': vitals['sugar'] ?? '-',                              'icon': Icons.opacity,         'color': Colors.purple},
        {'label': 'Weight', 'value': vitals['weight'] != null ? "${vitals['weight']}kg" : '-','icon': Icons.monitor_weight,'color': Colors.green[700]!},
      ];

      return Padding(
        padding: EdgeInsets.fromLTRB(
          isNarrow ? 12 : 20,
          isNarrow ? 10 : 16,
          isNarrow ? 12 : 20,
          isNarrow ? 10 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // ── Patient name + serial badge ────────────────────────────────
            Row(
              children: [
                Icon(Icons.person, color: _teal, size: isNarrow ? 20 : 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    patient['patientName'] ?? patient['name'] ?? 'Unknown Patient',
                    style: TextStyle(
                      fontSize: isNarrow ? 15 : 20,
                      fontWeight: FontWeight.bold,
                      color: _teal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 8 : 14,
                    vertical: isNarrow ? 4 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: _amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: _amber, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.confirmation_number, color: _amber, size: isNarrow ? 14 : 18),
                      const SizedBox(width: 4),
                      Text(
                        patient['serial'] ?? '-',
                        style: TextStyle(
                          color: _amber,
                          fontSize: isNarrow ? 12 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: isNarrow ? 8 : 12),

            // ── Vital tiles — wraps on narrow screens ──────────────────────
            isNarrow
                ? Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: vitalsList.map((v) {
                      return SizedBox(
                        width: (constraints.maxWidth - 40) / 4,
                        height: 60,
                        child: _buildVital(
                          label: v['label'] as String,
                          value: v['value'] as String,
                          icon: v['icon'] as IconData,
                          backgroundColor: v['color'] as Color,
                          compact: true,
                        ),
                      );
                    }).toList(),
                  )
                : SizedBox(
                    height: compact ? 70 : 86,
                    child: Row(
                      children: vitalsList.map((v) => Expanded(
                        child: _buildVital(
                          label: v['label'] as String,
                          value: v['value'] as String,
                          icon: v['icon'] as IconData,
                          backgroundColor: v['color'] as Color,
                          compact: compact,
                        ),
                      )).toList(),
                    ),
                  ),
          ],
        ),
      );
    });
  }
}