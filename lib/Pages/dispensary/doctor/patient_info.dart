// lib/pages/dispensary/doctor/patient_info.dart (updated)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:another_flushbar/flushbar.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/staff_patient_link_service.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';
import 'package:gmwf/design/design_system.dart';

enum VitalStatus {
  normal,      // Safe: Green
  warning,     // A little high / mild: Amber / Yellow
  critical,    // High or severe low: Red
  neutral,     // N/A or default: Slate / Muted
}

class VitalEvaluation {
  final String displayValue;
  final VitalStatus status;
  final Color color;

  const VitalEvaluation({
    required this.displayValue,
    required this.status,
    required this.color,
  });
}

class PatientInfo extends StatelessWidget {
  final Map<String, dynamic>? patientData;
  final String? doctorId;
  final String? doctorName;
  final String? branchId;
  final ValueChanged<Map<String, dynamic>>? onVitalsUpdated;
  final VoidCallback? onSkipPatient;

  const PatientInfo({
    super.key,
    required this.patientData,
    this.doctorId,
    this.doctorName,
    this.branchId,
    this.onVitalsUpdated,
    this.onSkipPatient,
  });

  static const Color _teal  = Color(0xFF00695C);
  static const Color _amber = Color(0xFFFFA000);

  /// Extract a clean token number (e.g. '#005' or '#002') from a full serial string
  static String formatDisplayToken(String? serial) {
    if (serial == null || serial.trim().isEmpty) return '-';
    final s = serial.trim();
    final parts = s.split('-');
    if (parts.isNotEmpty) {
      final last = parts.last;
      if (int.tryParse(last) != null) {
        return '#$last';
      }
    }
    return s;
  }

  static VitalEvaluation evaluateBp(dynamic rawBp, bool isDark) {
    if (rawBp == null) {
      return VitalEvaluation(
        displayValue: 'N/A',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }
    final s = rawBp.toString().trim();
    if (s.isEmpty || s == '-' || s.toUpperCase() == 'N/A') {
      return VitalEvaluation(
        displayValue: 'N/A',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }

    int? sys;
    int? dia;
    if (s.contains('/')) {
      final parts = s.split('/');
      sys = int.tryParse(parts[0].trim());
      if (parts.length > 1) {
        dia = int.tryParse(parts[1].trim());
      }
    } else {
      sys = int.tryParse(s);
    }

    if (sys == null && dia == null) {
      return VitalEvaluation(
        displayValue: s,
        status: VitalStatus.neutral,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      );
    }

    // Critical High: Sys >= 140 or Dia >= 90
    // Critical Low: Sys < 90 or Dia < 60
    // Warning (A little high): Sys 121..139 or Dia 81..89
    // Safe / Normal: Sys 90..120 and Dia 60..80
    final bool isCritHigh = (sys != null && sys >= 140) || (dia != null && dia >= 90);
    final bool isCritLow  = (sys != null && sys < 90)  || (dia != null && dia < 60);
    final bool isWarnHigh = (sys != null && sys >= 121 && sys < 140) || (dia != null && dia >= 81 && dia < 90);

    if (isCritHigh || isCritLow) {
      return VitalEvaluation(
        displayValue: s,
        status: VitalStatus.critical,
        color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626), // Vivid Red
      );
    } else if (isWarnHigh) {
      return VitalEvaluation(
        displayValue: s,
        status: VitalStatus.warning,
        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706), // Amber / Yellow
      );
    } else {
      return VitalEvaluation(
        displayValue: s,
        status: VitalStatus.normal,
        color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A), // Green
      );
    }
  }

  static VitalEvaluation evaluateTemp(dynamic rawTemp, bool isDark) {
    if (rawTemp == null) {
      return VitalEvaluation(
        displayValue: 'N/A',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }
    final s = rawTemp.toString().trim();
    if (s.isEmpty || s == '-' || s.toUpperCase() == 'N/A') {
      return VitalEvaluation(
        displayValue: 'N/A',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }

    final cleanStr = s.replaceAll('°C', '').replaceAll('°F', '').replaceAll('C', '').replaceAll('F', '').trim();
    final val = double.tryParse(cleanStr);
    if (val == null) {
      return VitalEvaluation(
        displayValue: s,
        status: VitalStatus.neutral,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      );
    }

    // Auto-detect Celsius vs Fahrenheit: val <= 50 -> Celsius, > 50 -> Fahrenheit
    final isCelsius = val <= 50.0;
    final displayVal = s.contains('°') ? s : (isCelsius ? '$val°C' : '$val°F');

    bool isCritical = false;
    bool isWarning = false;

    if (isCelsius) {
      if (val > 38.0 || val < 35.0) {
        isCritical = true;
      } else if (val >= 37.3 && val <= 38.0) {
        isWarning = true;
      }
    } else {
      if (val > 100.4 || val < 95.0) {
        isCritical = true;
      } else if (val >= 99.1 && val <= 100.4) {
        isWarning = true;
      }
    }

    if (isCritical) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.critical,
        color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626), // Vivid Red
      );
    } else if (isWarning) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.warning,
        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706), // Amber / Yellow
      );
    } else {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.normal,
        color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A), // Green
      );
    }
  }

  static VitalEvaluation evaluateSugar(dynamic rawSugar, bool isDark) {
    if (rawSugar == null) {
      return VitalEvaluation(
        displayValue: 'N/A',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }
    final s = rawSugar.toString().trim();
    if (s.isEmpty || s == '-' || s.toUpperCase() == 'N/A') {
      return VitalEvaluation(
        displayValue: 'N/A',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }

    final cleanStr = s.replaceAll(RegExp(r'[^\d.]'), '').trim();
    final val = double.tryParse(cleanStr);
    if (val == null) {
      return VitalEvaluation(
        displayValue: s,
        status: VitalStatus.neutral,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      );
    }

    final displayVal = s.toLowerCase().contains('mg') ? s : '$s mg/dL';

    if (val >= 200 || val < 70) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.critical,
        color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626), // Vivid Red
      );
    } else if (val >= 141 && val < 200) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.warning,
        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706), // Amber / Yellow
      );
    } else {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.normal,
        color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A), // Green
      );
    }
  }

  static VitalEvaluation evaluateWeight(dynamic rawWeight, bool isDark) {
    if (rawWeight == null) {
      return VitalEvaluation(
        displayValue: 'N/A kg',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }
    final s = rawWeight.toString().trim();
    if (s.isEmpty || s == '-' || s.toUpperCase() == 'N/A') {
      return VitalEvaluation(
        displayValue: 'N/A kg',
        status: VitalStatus.neutral,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      );
    }

    final cleanStr = s.replaceAll(RegExp(r'[^\d.]'), '').trim();
    final val = double.tryParse(cleanStr);
    if (val == null) {
      return VitalEvaluation(
        displayValue: s,
        status: VitalStatus.neutral,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      );
    }

    final displayVal = s.toLowerCase().contains('kg') ? s : '$s kg';

    // Weight clinical evaluation:
    // >= 100 kg: Dangerous Obesity -> RED
    // >= 85 kg: Overweight warning -> AMBER / YELLOW
    // < 35 kg: Dangerously low weight -> RED
    // < 45 kg: Underweight warning -> AMBER / YELLOW
    // 45 - 84 kg: Normal healthy range -> GREEN
    if (val >= 100) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.critical,
        color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626), // Red (Dangerous)
      );
    } else if (val >= 85) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.warning,
        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706), // Amber / Yellow (High)
      );
    } else if (val < 35) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.critical,
        color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626), // Red (Severe low)
      );
    } else if (val < 45) {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.warning,
        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706), // Amber / Yellow (Low)
      );
    } else {
      return VitalEvaluation(
        displayValue: displayVal,
        status: VitalStatus.normal,
        color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A), // Green (Normal)
      );
    }
  }

  static VitalEvaluation evaluateBloodGroup(dynamic rawBg, bool isDark) {
    final s = (rawBg ?? '').toString().trim();
    final isMissing = s.isEmpty || s == '-' || s.toUpperCase() == 'N/A';
    return VitalEvaluation(
      displayValue: isMissing ? 'N/A' : s,
      status: VitalStatus.neutral,
      color: isDark ? Colors.white : const Color(0xFF0F172A),
    );
  }

  Widget _buildVitalCell({
    required Map<String, dynamic> vital,
    required bool isDark,
    required bool compact,
  }) {
    final label = vital['label'] as String;
    final eval  = vital['eval'] as VitalEvaluation;
    final icon  = vital['icon'] as IconData;
    final sub   = vital['sub'] as String?;

    final iconColor = eval.status == VitalStatus.neutral
        ? (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))
        : eval.color;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 12 : 13, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: compact ? 9.5 : 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            eval.displayValue,
            style: TextStyle(
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w900,
              color: eval.color,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null && sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                sub,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : null,
          title: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F766E).withValues(alpha: 0.25) : Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              border: isDark ? Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.3)) : null,
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded, color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800, size: 24),
                const SizedBox(width: 10),
                Text(
                  'Edit Vitals & View Audit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.teal.shade900,
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
                      color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.3) : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.4) : Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.support_agent_rounded, size: 18, color: isDark ? const Color(0xFF60A5FA) : Colors.blue.shade800),
                            const SizedBox(width: 6),
                            Text(
                              'Added by Receptionist ($recBy)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? const Color(0xFF93C5FD) : Colors.blue.shade900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'BP: $recBp | Temp: $recTemp°C | Weight: ${recVitals['weight'] ?? 'N/A'} kg',
                          style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFDBEAFE) : Colors.blue.shade900),
                        ),
                      ],
                    ),
                  ),
                  if (docVitals.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.3) : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : Colors.amber.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.medical_services_rounded, size: 18, color: isDark ? const Color(0xFFFBBF24) : Colors.amber.shade900),
                              const SizedBox(width: 6),
                              Text(
                                'Previous Doctor Update (${docVitals['updatedBy'] ?? 'Doctor'})',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? const Color(0xFFFDE68A) : Colors.amber.shade900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'BP: ${docVitals['bp'] ?? 'N/A'} | Temp: ${docVitals['temp'] ?? 'N/A'}°C',
                            style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFFEF3C7) : Colors.amber.shade900),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Update Vitals (Doctor):',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('/', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
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
                final box = await LocalStorageService.ensureBoxOpen(LocalStorageService.entriesBox);
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
      );
    },
  );
}

  String? _resolveGuardianName(Map<String, dynamic> patient) {
    if (patient['guardianName'] != null && patient['guardianName'].toString().trim().isNotEmpty) {
      return patient['guardianName'].toString().trim();
    }
    final gCnic = (patient['guardianCnic'] ?? '').toString().trim();
    if (gCnic.isEmpty) return null;

    try {
      final bId = branchId ?? patient['branchId']?.toString();
      final list = LocalStorageService.searchPatientsByCnicOrGuardian(gCnic, branchId: bId);
      for (final p in list) {
        final isAdult = p['isAdult'] == true ||
            (p['guardianCnic'] == null || (p['guardianCnic'] as String).trim().isEmpty);
        if (isAdult) {
          final gName = (p['patientName'] ?? p['name'] ?? p['fullName'])?.toString().trim();
          if (gName != null && gName.isNotEmpty) return gName;
        }
      }
      if (list.isNotEmpty) {
        final gName = (list.first['patientName'] ?? list.first['name'] ?? list.first['fullName'])?.toString().trim();
        if (gName != null && gName.isNotEmpty) return gName;
      }
    } catch (_) {}
    return null;
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

    final patientName = (patient['patientName'] ?? patient['name'] ?? 'Unknown Patient').toString();
    final guardianName = _resolveGuardianName(patient);
    final isChild = (patient['guardianCnic'] != null && patient['guardianCnic'].toString().trim().isNotEmpty) ||
        (patient['isAdult'] == false);

    final ageStr = (vitals['age'] ?? patient['age'] ?? '').toString().trim();
    final genderStr = (vitals['gender'] ?? patient['gender'] ?? '').toString().trim();
    final staffInfo = StaffPatientLinkService.getStaffInfoFromPatientMap(patient);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = GBreakpoint.isMobileC(constraints);
      final compact  = constraints.maxWidth < 450;

      final bpEval     = evaluateBp(vitals['bp'], isDark);
      final tempEval   = evaluateTemp(vitals['temp'], isDark);
      final sugarEval  = evaluateSugar(vitals['sugar'], isDark);
      final weightEval = evaluateWeight(vitals['weight'], isDark);
      final bgEval     = evaluateBloodGroup(vitals['bloodGroup'] ?? patient['bloodGroup'], isDark);

      final clinicalVitals = [
        {
          'label': 'BP',
          'eval': bpEval,
          'icon': Icons.favorite_rounded,
          'sub': hasDocUpdate && recBp != null && recBp.toString() != vitals['bp']?.toString() ? 'Rec: $recBp' : null,
        },
        {
          'label': 'Temp',
          'eval': tempEval,
          'icon': Icons.thermostat_rounded,
          'sub': hasDocUpdate && recTemp != null && recTemp.toString() != vitals['temp']?.toString() ? 'Rec: $recTemp°C' : null,
        },
        {
          'label': 'Sugar',
          'eval': sugarEval,
          'icon': Icons.water_drop_rounded,
          'sub': hasDocUpdate && recSugar != null && recSugar.toString() != vitals['sugar']?.toString() ? 'Rec: $recSugar' : null,
        },
        {
          'label': 'Weight',
          'eval': weightEval,
          'icon': Icons.monitor_weight_rounded,
          'sub': hasDocUpdate && recWeight != null && recWeight.toString() != vitals['weight']?.toString() ? 'Rec: ${recWeight}kg' : null,
        },
        {
          'label': 'Blood',
          'eval': bgEval,
          'icon': Icons.bloodtype_rounded,
          'sub': null,
        },
      ];

      final rawSerial = (patient['serial'] ?? patient['id'] ?? '-').toString();
      final displayToken = formatDisplayToken(rawSerial);

      final prescDays = (() {
        final d = patient['daysOfMedicine'] ?? patient['suggestedDays'] ?? patient['requestedDays'];
        if (d is int && d > 1) return d;
        final presc = patient['prescription'];
        if (presc is Map) {
          final pd = presc['daysOfMedicine'];
          if (pd is int && pd > 1) return pd;
        }
        return 1;
      })();

      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 10 : 14,
          vertical: 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top Identity & Actions Row ─────────────────────────────────
            Row(
              children: [
                // Avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF2DD4BF) : _teal,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: isDark ? const Color(0xFF2DD4BF) : _teal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),

                // Patient Name & Demographics
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        patientName,
                        style: TextStyle(
                          fontSize: isNarrow ? 15 : 17,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (genderStr.isNotEmpty || ageStr.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            [
                              if (genderStr.isNotEmpty) genderStr,
                              if (ageStr.isNotEmpty) '$ageStr yrs',
                            ].join(' • '),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      if (staffInfo != null)
                        StaffPatientLinkService.buildStaffBadge(staffInfo, isDark: isDark),
                      if (isChild && guardianName != null && guardianName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF134E4A) : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade200),
                          ),
                          child: Text(
                            'Guardian: $guardianName',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF5EEAD4) : Colors.teal.shade900,
                            ),
                          ),
                        ),
                      if (patient['isVitalsOnly'] == true || patient['vitalsOnly'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF6B21A8) : Colors.purple.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🩺 VITALS ONLY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Serial Token Badge (Simplified Token Number + Tooltip)
                Tooltip(
                  message: 'Full Serial: $rawSerial',
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFFBBF24),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.confirmation_number_rounded,
                          color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displayToken,
                          style: TextStyle(
                            color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Requested Days Badge
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFF10B981), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                      const SizedBox(width: 4),
                      Text(
                        '$prescDays day requested',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // Edit Vitals Button
                InkWell(
                  onTap: () => _showEditVitalsDialog(context, patient),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F766E) : _teal,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded, color: Colors.white, size: 15),
                        SizedBox(width: 4),
                        Text(
                          'Edit BP/Temp',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Skip Button
                if (onSkipPatient != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onSkipPatient,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF7C2D12) : const Color(0xFFEA580C),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.skip_next_rounded, color: Colors.white, size: 15),
                          SizedBox(width: 3),
                          Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 8),

            // ── Consolidated Clinical Vitals Strip with Vertical Dividers ───
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A0F1D) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
              ),
              child: isNarrow
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: clinicalVitals.map((v) {
                        return SizedBox(
                          width: (constraints.maxWidth - 48) / 3,
                          child: _buildVitalCell(
                            vital: v,
                            isDark: isDark,
                            compact: true,
                          ),
                        );
                      }).toList(),
                    )
                  : IntrinsicHeight(
                      child: Row(
                        children: [
                          for (int i = 0; i < clinicalVitals.length; i++) ...[
                            if (i > 0)
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                indent: 3,
                                endIndent: 3,
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                              ),
                            Expanded(
                              child: _buildVitalCell(
                                vital: clinicalVitals[i],
                                isDark: isDark,
                                compact: compact,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    });
  }
}
