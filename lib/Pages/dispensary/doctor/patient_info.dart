// lib/pages/dispensary/doctor/patient_info.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:another_flushbar/flushbar.dart';
import '../../../services/local_storage_service.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';

class PatientInfo extends StatelessWidget {
  final Map<String, dynamic>? patientData;
  final String? doctorId;
  final String? doctorName;
  final String? branchId;
  final ValueChanged<Map<String, dynamic>>? onVitalsUpdated;

  const PatientInfo({
    super.key,
    required this.patientData,
    this.doctorId,
    this.doctorName,
    this.branchId,
    this.onVitalsUpdated,
  });

  static const Color _teal  = Color(0xFF00695C);
  static const Color _amber = Color(0xFFFFA000);

  Widget _buildVital({
    required String label,
    required String value,
    required IconData icon,
    required Color backgroundColor,
    required bool compact,
    String? auditSubtext,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 6 : 8,
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
          Icon(icon, color: Colors.white, size: compact ? 14 : 18),
          SizedBox(height: compact ? 2 : 4),
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
          SizedBox(height: compact ? 1 : 2),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 10 : 12.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (auditSubtext != null && auditSubtext.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              auditSubtext,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: compact ? 7 : 8.5,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  void _showEditVitalsDialog(BuildContext context, Map<String, dynamic> patient) {
    final vitals = Map<String, dynamic>.from(patient['vitals'] ?? {});
    final recVitals = (vitals['receptionistVitals'] is Map)
        ? Map<String, dynamic>.from(vitals['receptionistVitals'])
        : <String, dynamic>{};
    final docVitals = (vitals['doctorVitals'] is Map)
        ? Map<String, dynamic>.from(vitals['doctorVitals'])
        : <String, dynamic>{};

    final currentBp = (vitals['bp'] ?? '').toString();
    String initSys = '';
    String initDia = '';
    if (currentBp.contains('/')) {
      final parts = currentBp.split('/');
      initSys = parts[0].trim();
      if (parts.length > 1) initDia = parts[1].trim();
    } else if (currentBp != 'N/A') {
      initSys = currentBp;
    }

    final sysCtrl  = TextEditingController(text: initSys);
    final diaCtrl  = TextEditingController(text: initDia);
    final tempCtrl = TextEditingController(text: (vitals['temp'] ?? '').toString() == 'N/A' ? '' : (vitals['temp'] ?? '').toString());
    final sugarCtrl = TextEditingController(text: (vitals['sugar'] ?? '').toString());
    final weightCtrl = TextEditingController(text: (vitals['weight'] ?? '').toString() == 'N/A' ? '' : (vitals['weight'] ?? '').toString());

    final recBp = recVitals['bp'] ?? vitals['bp'] ?? 'N/A';
    final recTemp = recVitals['temp'] ?? vitals['temp'] ?? 'N/A';
    final recBy = recVitals['addedBy'] ?? patient['createdByName'] ?? 'Receptionist';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.teal.shade800, size: 24),
              const SizedBox(width: 10),
              Text(
                'Edit Vitals & View Audit',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Audit info header: What receptionist added ─────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.support_agent_rounded, size: 18, color: Colors.blue.shade800),
                          const SizedBox(width: 6),
                          Text(
                            'Added by Receptionist ($recBy)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'BP: $recBp | Temp: $recTemp°C | Weight: ${recVitals['weight'] ?? 'N/A'} kg',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ],
                  ),
                ),
                if (docVitals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.medical_services_rounded, size: 18, color: Colors.amber.shade900),
                            const SizedBox(width: 6),
                            Text(
                              'Previous Doctor Update (${docVitals['updatedBy'] ?? 'Doctor'})',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'BP: ${docVitals['bp'] ?? 'N/A'} | Temp: ${docVitals['temp'] ?? 'N/A'}°C',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Update Vitals (Doctor):',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: sysCtrl,
                        maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Systolic BP',
                          hintText: 'e.g. 120',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          counterText: '',
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('/', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: diaCtrl,
                        maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Diastolic BP',
                          hintText: 'e.g. 80',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Temperature (°C)',
                    hintText: 'e.g. 98.6',
                    prefixIcon: const Icon(Icons.thermostat),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: sugarCtrl,
                        maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Sugar (optional)',
                          prefixIcon: const Icon(Icons.opacity),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: weightCtrl,
                        maxLength: 3,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Weight (kg)',
                          prefixIcon: const Icon(Icons.monitor_weight),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save Updated Vitals'),
            onPressed: () async {
              final sys = sysCtrl.text.trim();
              final dia = diaCtrl.text.trim();
              final bpVal = (sys.isNotEmpty && dia.isNotEmpty) ? '$sys/$dia' : (sys.isNotEmpty ? sys : 'N/A');
              final tempVal = tempCtrl.text.trim().isNotEmpty ? tempCtrl.text.trim() : 'N/A';
              final sugarVal = sugarCtrl.text.trim();
              final weightVal = weightCtrl.text.trim().isNotEmpty ? weightCtrl.text.trim() : 'N/A';
              final nowIso = DateTime.now().toIso8601String();
              final docName = doctorName ?? 'Doctor';
              final docId   = doctorId ?? '';

              final auditList = List<Map<String, dynamic>>.from(
                (vitals['auditTrail'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
              );

              auditList.add({
                'role': 'doctor',
                'action': 'Updated vitals',
                'by': docName,
                'byId': docId,
                'at': nowIso,
                'bp': bpVal,
                'temp': tempVal,
                'weight': weightVal,
                if (sugarVal.isNotEmpty) 'sugar': sugarVal,
              });

              vitals['bp'] = bpVal;
              vitals['temp'] = tempVal;
              vitals['weight'] = weightVal;
              if (sugarVal.isNotEmpty) vitals['sugar'] = sugarVal;
              vitals['doctorVitals'] = {
                'bp': bpVal,
                'temp': tempVal,
                'weight': weightVal,
                if (sugarVal.isNotEmpty) 'sugar': sugarVal,
                'updatedBy': docName,
                'updatedById': docId,
                'updatedAt': nowIso,
              };
              vitals['auditTrail'] = auditList;
              patient['vitals'] = vitals;

              // Save to Hive
              final serial = patient['serial']?.toString() ?? '';
              final bId    = branchId ?? patient['branchId']?.toString() ?? '';
              if (serial.isNotEmpty && bId.isNotEmpty) {
                final entryKey = '$bId-$serial';
                final box = Hive.box(LocalStorageService.entriesBox);
                final existing = box.get(entryKey);
                if (existing != null) {
                  final updatedEntry = Map<String, dynamic>.from(existing);
                  updatedEntry['vitals'] = vitals;
                  await box.put(entryKey, updatedEntry);

                  try {
                    RealtimeManager().sendMessage({
                      ...RealtimeEvents.payload(
                        type: RealtimeEvents.saveEntry,
                        branchId: bId,
                        data: updatedEntry,
                      ),
                    });
                  } catch (_) {}
                }
              }

              if (context.mounted) {
                Navigator.pop(ctx);
                onVitalsUpdated?.call(vitals);
                Flushbar(
                  message: '✅ Vitals updated and audit trail saved',
                  backgroundColor: Colors.teal.shade700,
                  duration: const Duration(seconds: 3),
                ).show(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAuditTrailDialog(BuildContext context, Map<String, dynamic> patient) {
    final vitals = Map<String, dynamic>.from(patient['vitals'] ?? {});
    final auditList = List<Map<String, dynamic>>.from(
      (vitals['auditTrail'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? []
    );

    if (auditList.isEmpty) {
      final recV = (vitals['receptionistVitals'] is Map) ? Map<String, dynamic>.from(vitals['receptionistVitals']) : {};
      final docV = (vitals['doctorVitals'] is Map) ? Map<String, dynamic>.from(vitals['doctorVitals']) : {};

      if (recV.isNotEmpty || vitals['bp'] != null) {
        auditList.add({
          'role': 'receptionist',
          'action': 'Added initial vitals',
          'by': recV['addedBy'] ?? patient['createdByName'] ?? 'Receptionist',
          'at': recV['addedAt'] ?? patient['createdAt'] ?? '',
          'bp': recV['bp'] ?? vitals['bp'] ?? 'N/A',
          'temp': recV['temp'] ?? vitals['temp'] ?? 'N/A',
        });
      }
      if (docV.isNotEmpty) {
        auditList.add({
          'role': 'doctor',
          'action': 'Updated vitals',
          'by': docV['updatedBy'] ?? 'Doctor',
          'at': docV['updatedAt'] ?? '',
          'bp': docV['bp'] ?? 'N/A',
          'temp': docV['temp'] ?? 'N/A',
        });
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.history_rounded, color: Colors.blue.shade800, size: 24),
            const SizedBox(width: 8),
            const Text('Vitals Audit Trail', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: auditList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No audit history available for this entry.', textAlign: TextAlign.center),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: auditList.length,
                  separatorBuilder: (ctx, i) => const Divider(),
                  itemBuilder: (_, i) {
                    final item = auditList[i];
                    final isDoc = item['role'] == 'doctor';
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: isDoc ? Colors.amber.shade100 : Colors.blue.shade100,
                        child: Icon(
                          isDoc ? Icons.medical_services : Icons.support_agent,
                          color: isDoc ? Colors.amber.shade900 : Colors.blue.shade900,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        '${item['action'] ?? 'Vitals recorded'} by ${item['by'] ?? 'User'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text('BP: ${item['bp'] ?? 'N/A'}  •  Temp: ${item['temp'] ?? 'N/A'}°C',
                              style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          if (item['at'] != null && item['at'].toString().isNotEmpty)
                            Text(
                              item['at'].toString().replaceAll('T', ' ').split('.')[0],
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
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
    final recVitals = (vitals['receptionistVitals'] is Map) ? Map<String, dynamic>.from(vitals['receptionistVitals']) : {};
    final docVitals = (vitals['doctorVitals'] is Map) ? Map<String, dynamic>.from(vitals['doctorVitals']) : {};
    final hasDocUpdate = docVitals.isNotEmpty;
    final recBp   = recVitals['bp'] ?? (hasDocUpdate ? 'Rec' : null);
    final recTemp = recVitals['temp'] ?? (hasDocUpdate ? 'Rec' : null);
    final recSugar = recVitals['sugar'];
    final recWeight = recVitals['weight'];

    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 480;
      final compact  = constraints.maxWidth < 360;

      final vitalsList = [
        {'label': 'Age',    'value': (vitals['age'] ?? patient['age'] ?? '-').toString(), 'icon': Icons.calendar_today, 'color': _teal, 'sub': null},
        {'label': 'Gender', 'value': vitals['gender'] ?? patient['gender'] ?? '-',        'icon': Icons.person_outline, 'color': Colors.blue[700]!, 'sub': null},
        {'label': 'Blood',  'value': vitals['bloodGroup'] ?? patient['bloodGroup'] ?? '-','icon': Icons.bloodtype,       'color': Colors.red[700]!, 'sub': null},
        {'label': 'BP',     'value': vitals['bp'] ?? '-',                                 'icon': Icons.favorite,        'color': Colors.red, 'sub': hasDocUpdate && recBp != null && recBp.toString() != vitals['bp']?.toString() ? 'Rec: $recBp' : null},
        {'label': 'Temp',   'value': vitals['temp'] != null ? "${vitals['temp']}°C" : '-','icon': Icons.thermostat,      'color': Colors.orange, 'sub': hasDocUpdate && recTemp != null && recTemp.toString() != vitals['temp']?.toString() ? 'Rec: $recTemp°C' : null},
        {'label': 'Sugar',  'value': vitals['sugar'] ?? '-',                              'icon': Icons.opacity,         'color': Colors.purple, 'sub': hasDocUpdate && recSugar != null && recSugar.toString() != vitals['sugar']?.toString() ? 'Rec: $recSugar' : null},
        {'label': 'Weight', 'value': vitals['weight'] != null ? "${vitals['weight']}kg" : '-','icon': Icons.monitor_weight,'color': Colors.green[700]!, 'sub': hasDocUpdate && recWeight != null && recWeight.toString() != vitals['weight']?.toString() ? 'Rec: ${recWeight}kg' : null},
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
            // ── Patient name + serial badge + Edit Vitals / Audit ────────────
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
                    color: _amber.withValues(alpha: 0.15),
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
                const SizedBox(width: 8),
                // Edit Vitals Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isNarrow ? 8 : 12,
                      vertical: isNarrow ? 4 : 8,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(Icons.edit_note_rounded, size: isNarrow ? 14 : 18),
                  label: Text(
                    'Edit BP/Temp',
                    style: TextStyle(fontSize: isNarrow ? 11 : 13, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _showEditVitalsDialog(context, patient),
                ),
                const SizedBox(width: 6),
                // Audit Trail Info Button
                IconButton(
                  tooltip: 'View Vitals Audit History',
                  icon: Icon(Icons.history_rounded, color: Colors.blue.shade700, size: isNarrow ? 20 : 22),
                  onPressed: () => _showAuditTrailDialog(context, patient),
                ),
                if (patient['suggestedDays'] != null) ...[
                  const SizedBox(width: 8),
                  (() {
                    final suggested = (patient['suggestedDays'] as int?) ?? 1;
                    int prescribed = 1;
                    final existingPresc = patient['prescription'];
                    if (existingPresc is Map) {
                      prescribed = (existingPresc['daysOfMedicine'] as int?) ?? 1;
                    } else if (patient['daysOfMedicine'] is int) {
                      prescribed = patient['daysOfMedicine'];
                    }

                    final hasMismatch = suggested != prescribed && existingPresc != null;

                    return Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 8 : 12,
                        vertical: isNarrow ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: hasMismatch ? Colors.orange.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasMismatch ? Colors.orange.shade300 : Colors.green.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasMismatch ? Icons.warning_amber_rounded : Icons.info_outline,
                            color: hasMismatch ? Colors.orange.shade800 : Colors.green.shade800,
                            size: isNarrow ? 14 : 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasMismatch
                                ? 'Mismatched: $suggested Paid vs $prescribed Prescribed'
                                : 'Asked for $suggested day${suggested > 1 ? 's' : ''} medicine',
                            style: TextStyle(
                              color: hasMismatch ? Colors.orange.shade900 : Colors.green.shade900,
                              fontSize: isNarrow ? 11 : 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  })(),
                ],
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
                        height: 64,
                        child: _buildVital(
                          label: v['label'] as String,
                          value: v['value'] as String,
                          icon: v['icon'] as IconData,
                          backgroundColor: v['color'] as Color,
                          compact: true,
                          auditSubtext: v['sub'] as String?,
                        ),
                      );
                    }).toList(),
                  )
                : SizedBox(
                    height: compact ? 72 : 88,
                    child: Row(
                      children: vitalsList.map((v) => Expanded(
                        child: _buildVital(
                          label: v['label'] as String,
                          value: v['value'] as String,
                          icon: v['icon'] as IconData,
                          backgroundColor: v['color'] as Color,
                          compact: compact,
                          auditSubtext: v['sub'] as String?,
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
