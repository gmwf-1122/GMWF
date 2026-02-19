import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/local_storage_service.dart';

class PatientHistory extends StatefulWidget {
  final String patientCnic;
  final String branchId;
  final Function(Map<String, dynamic> visit)? onRepeatLast;

  const PatientHistory({
    super.key,
    required this.patientCnic,
    required this.branchId,
    this.onRepeatLast,
  });

  @override
  State<PatientHistory> createState() => _PatientHistoryState();
}

class _PatientHistoryState extends State<PatientHistory> {
  static const Color _teal = Color(0xFF00695C);
  static const Color _lightTeal = Color(0xFFE0F2F1);
  static const Color _tealBorder = Color(0xFF4DB6AC);

  List<Map<String, dynamic>> _visits = [];
  Map<String, dynamic> _patientProfile = {};
  bool _loading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      await _fetchFromFirestore();

      if (_visits.isEmpty && _patientProfile.isEmpty) {
        await _loadFromLocal();
        if (mounted) setState(() => _isOffline = true);
      }
    } catch (e) {
      debugPrint("Firestore history fetch failed: $e - falling back to local");
      await _loadFromLocal();
      if (mounted) setState(() => _isOffline = true);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchFromFirestore() async {
    final identifier = widget.patientCnic.trim();
    if (identifier.isEmpty) return;

    var patientQuery = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('patients')
        .where('cnic', isEqualTo: identifier)
        .limit(1)
        .get();

    if (patientQuery.docs.isEmpty) {
      patientQuery = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('patients')
          .where('guardianCnic', isEqualTo: identifier)
          .limit(1)
          .get();
    }

    if (patientQuery.docs.isNotEmpty) {
      _patientProfile = patientQuery.docs.first.data();
    }

    final cnics = [identifier];
    final guardianCnic = _patientProfile['guardianCnic'] as String?;
    if (guardianCnic != null && guardianCnic.isNotEmpty && guardianCnic != identifier) {
      cnics.add(guardianCnic);
    }

    _visits = [];

    for (final cnic in cnics) {
      final prescRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(cnic)
          .collection('prescriptions');

      final prescQuery = await prescRef.orderBy('createdAt', descending: true).get();

      final fetched = prescQuery.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      _visits.addAll(fetched);
    }

    _visits.sort((a, b) {
      final dateA = _parseDate(a['createdAt']);
      final dateB = _parseDate(b['createdAt']);
      return dateB.compareTo(dateA);
    });
  }

  Future<void> _loadFromLocal() async {
    final patients = LocalStorageService.getAllLocalPatients(branchId: widget.branchId);
    _patientProfile = patients.firstWhere(
      (p) => (p['cnic']?.toString().trim() == widget.patientCnic ||
              p['guardianCnic']?.toString().trim() == widget.patientCnic),
      orElse: () => <String, dynamic>{},
    );

    final allPrescriptions = LocalStorageService.getBranchPrescriptions(widget.branchId);

    _visits = allPrescriptions.where((presc) {
      final cnic = presc['patientCnic']?.toString().trim() ?? '';
      final guardian = presc['guardianCnic']?.toString().trim() ?? '';
      final pid = presc['patientId']?.toString().trim() ?? '';
      return cnic == widget.patientCnic || guardian == widget.patientCnic || pid == widget.patientCnic;
    }).toList();

    if (_visits.isEmpty && _patientProfile.isNotEmpty) {
      final targetName = _patientProfile['name']?.toString().trim().toLowerCase() ?? '';
      if (targetName.isNotEmpty) {
        _visits = allPrescriptions.where((p) {
          final name = p['patientName']?.toString().trim().toLowerCase() ?? '';
          return name.contains(targetName);
        }).toList();
      }
    }

    _visits.sort((a, b) {
      final dateA = _parseDate(a['createdAt']);
      final dateB = _parseDate(b['createdAt']);
      return dateB.compareTo(dateA);
    });
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime(1970);
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      var dt = DateTime.tryParse(value);
      dt ??= DateFormat('dd/MM/yyyy HH:mm').tryParse(value);
      dt ??= DateFormat('dd-MM-yyyy HH:mm').tryParse(value);
      dt ??= DateFormat('yyyy-MM-dd HH:mm').tryParse(value);
      dt ??= DateFormat('dd MMM yyyy HH:mm').tryParse(value);
      if (dt != null) return dt;
    }
    return DateTime(1970);
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy • hh:mm a').format(date);
  }

  void _repeatLastVisit() {
    if (_visits.isEmpty || widget.onRepeatLast == null) return;

    final lastVisit = _visits.first;

    final repeatData = <String, dynamic>{
      'complaint': lastVisit['complaint']?.toString().trim() ?? '',
      'diagnosis': lastVisit['diagnosis']?.toString().trim() ?? '',
      'labResults': List<Map<String, dynamic>>.from(
        (lastVisit['labResults'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
      ),
      'prescriptions': List<Map<String, dynamic>>.from(
        (lastVisit['prescriptions'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
      ),
    };

    widget.onRepeatLast!(repeatData);
  }

  Widget _buildMedicineList(List<dynamic>? meds) {
    if (meds == null || meds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: meds.map((med) {
        final name   = med['name']?.toString() ?? 'Unknown';
        final qty    = med['quantity']?.toString() ?? '';
        final timing = med['timing']?.toString() ?? '';
        final dosage = med['dosage']?.toString() ?? '';
        final meal   = med['meal']?.toString() ?? '';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              children: [
                TextSpan(text: '• $name', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (qty.isNotEmpty)    TextSpan(text: ' ×$qty'),
                if (timing.isNotEmpty) TextSpan(text: '  ($timing)'),
                if (dosage.isNotEmpty) TextSpan(text: '  $dosage'),
                if (meal.isNotEmpty)   TextSpan(text: '  - $meal'),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLabList(List<dynamic>? labs) {
    if (labs == null || labs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: labs.map((lab) {
        final name = lab['name']?.toString() ?? 'Unnamed Test';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('• $name', style: const TextStyle(fontSize: 14)),
        );
      }).toList(),
    );
  }

  Widget _buildVitalsCompact(Map<String, dynamic>? vitals) {
    if (vitals == null || vitals.isEmpty) return const SizedBox.shrink();

    final bp       = vitals['bp']?.toString() ?? '-';
    final temp     = vitals['temp']?.toString() ?? '-';
    final tempUnit = vitals['tempUnit']?.toString() ?? 'C';
    final weight   = vitals['weight']?.toString() ?? '-';
    final sugar    = vitals['sugar']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Vitals (latest)", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: _teal)),
        const SizedBox(height: 6),
        _vitalRow("BP", bp),
        _vitalRow("Temp", temp == '-' ? '-' : "$temp °$tempUnit"),
        _vitalRow("Weight", weight == '-' ? '-' : "$weight kg"),
        if (sugar != null && sugar.isNotEmpty) _vitalRow("Sugar", "$sugar mg/dL"),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _vitalRow(String label, String value) {
    if (value == '-') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$label:", style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _viewFullHistory() {
    final name   = _patientProfile['name']?.toString().trim() ?? 'Unknown Patient';
    final gender = _patientProfile['gender']?.toString().trim() ?? 'N/A';
    final blood  = _patientProfile['bloodGroup']?.toString().trim() ?? 'N/A';

    final age = _visits.isNotEmpty
        ? ((_visits.first['vitals'] as Map<String, dynamic>?)?['age']?.toString() ?? 'N/A')
        : 'N/A';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.history, color: _teal),
            SizedBox(width: 12),
            Text("Full Visit History", style: TextStyle(color: _teal, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 600,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _lightTeal,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _tealBorder, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: _teal, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _teal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _infoRow(Icons.cake, "Age", age),
                    _infoRow(Icons.wc, "Gender", gender),
                    _infoRow(Icons.bloodtype, "Blood Group", blood),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: _visits.isEmpty
                    ? const Center(child: Text("No prescription history found", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _visits.length,
                        itemBuilder: (context, i) {
                          final v = _visits[i];
                          final dt = _parseDate(v['createdAt']);
                          final dateStr = (dt.year > 1971) ? _formatDate(dt) : 'Invalid date';
                          final pname = v['patientName']?.toString().trim() ?? name;

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            color: _lightTeal,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: _tealBorder, width: 1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            pname,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 17,
                                              color: _teal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (i == 0)
                                          Chip(
                                            label: const Text("Latest", style: TextStyle(fontSize: 11, color: Colors.white)),
                                            backgroundColor: _teal,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(dateStr, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                                    const SizedBox(height: 12),

                                    if (v['complaint']?.toString().trim().isNotEmpty == true) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.description, color: _teal, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Patient Condition",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: _teal,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        v['complaint'],
                                        style: const TextStyle(height: 1.4, color: Colors.black87),
                                      ),
                                      const SizedBox(height: 16),
                                    ],

                                    if (v['diagnosis']?.toString().trim().isNotEmpty == true) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.medical_services, color: _teal, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Diagnosis",
                                            style: TextStyle(fontWeight: FontWeight.bold, color: _teal, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(v['diagnosis'], style: const TextStyle(height: 1.4)),
                                      const SizedBox(height: 16),
                                    ],

                                    if ((v['prescriptions'] as List?)?.isNotEmpty == true) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.medical_information, color: _teal, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Medicines",
                                            style: TextStyle(fontWeight: FontWeight.bold, color: _teal, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      _buildMedicineList(v['prescriptions']),
                                      const SizedBox(height: 12),
                                    ],

                                    if ((v['labResults'] as List?)?.isNotEmpty == true) ...[
                                      Row(
                                        children: [
                                          Icon(Icons.science, color: _teal, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Lab Tests Advised",
                                            style: TextStyle(fontWeight: FontWeight.bold, color: _teal, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      _buildLabList(v['labResults']),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close", style: TextStyle(color: _teal, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _teal.withOpacity(0.8)),
          const SizedBox(width: 8),
          Text(
            "$label: ",
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _teal));
    }

    final latest = _visits.isNotEmpty ? _visits.first : null;
    final patientName = latest?['patientName']?.toString().trim() ??
        _patientProfile['name']?.toString().trim() ??
        'Patient (${widget.patientCnic.length > 7 ? widget.patientCnic.substring(0, 7) : widget.patientCnic}...)';

    final latestDate = latest != null ? _parseDate(latest['createdAt']) : null;
    final dateStr = (latestDate != null && latestDate.year > 1971)
        ? _formatDate(latestDate)
        : 'Unknown date';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOffline)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Offline mode – showing cached data",
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Row(
            children: const [
              FaIcon(FontAwesomeIcons.history, color: _teal, size: 22),
              SizedBox(width: 10),
              Text("Patient History", style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: _teal)),
            ],
          ),
          const SizedBox(height: 16),

          if (_visits.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 70,
                      color: _patientProfile.isNotEmpty ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _patientProfile.isNotEmpty
                          ? "No prescriptions recorded yet."
                          : "No patient or history found.",
                      style: const TextStyle(fontSize: 15, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: _lightTeal,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _tealBorder, width: 1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              patientName,
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: _teal),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Chip(
                            label: const Text("Latest", style: TextStyle(fontSize: 11, color: Colors.white)),
                            backgroundColor: _teal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(dateStr, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                      const Divider(height: 24),

                      if (latest!['complaint']?.toString().trim().isNotEmpty == true) ...[
                        Row(
                          children: [
                            Icon(Icons.description, color: _teal, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              "Patient Condition",
                              style: TextStyle(fontWeight: FontWeight.bold, color: _teal, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latest['complaint'],
                          style: const TextStyle(height: 1.4, color: Colors.black87),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (latest['diagnosis']?.toString().trim().isNotEmpty == true) ...[
                        Row(
                          children: [
                            Icon(Icons.medical_services, color: _teal, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              "Diagnosis",
                              style: TextStyle(fontWeight: FontWeight.bold, color: _teal, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(latest['diagnosis'], style: const TextStyle(height: 1.3)),
                        const SizedBox(height: 16),
                      ],

                      _buildVitalsCompact((latest['vitals'] as Map<String, dynamic>?)),

                      if ((latest['prescriptions'] as List?)?.isNotEmpty == true) ...[
                        Row(
                          children: [
                            Icon(Icons.medical_information, color: _teal, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              "Medicines",
                              style: TextStyle(fontWeight: FontWeight.bold, color: _teal, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildMedicineList(latest['prescriptions']),
                        const SizedBox(height: 12),
                      ],

                      if ((latest['labResults'] as List?)?.isNotEmpty == true) ...[
                        Row(
                          children: [
                            Icon(Icons.science, color: _teal, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              "Lab Tests Advised",
                              style: TextStyle(fontWeight: FontWeight.bold, color: _teal, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildLabList(latest['labResults']),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _visits.isEmpty ? null : _repeatLastVisit,
                    icon: const Icon(Icons.repeat, size: 18),
                    label: const Text("Repeat Last", style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _viewFullHistory,
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text("Full History", style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: BorderSide(color: _teal, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      minimumSize: const Size(0, 52),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}