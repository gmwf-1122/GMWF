// lib/pages/patient_queue.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:async/async.dart';

class PatientQueue extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? selectedPatient;
  final Function(Map<String, dynamic>) onPatientSelected;

  const PatientQueue({
    super.key,
    required this.branchId,
    required this.selectedPatient,
    required this.onPatientSelected,
  });

  @override
  State<PatientQueue> createState() => _PatientQueueState();
}

class _PatientQueueState extends State<PatientQueue>
    with SingleTickerProviderStateMixin {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _amber = Color(0xFFFFA000);
  static const Color _purple = Color.fromARGB(255, 167, 25, 210);
  static const Color _blue = Color(0xFF1976D2);

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  String? _lastAutoSelectedId;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 1.0, end: 1.4).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(covariant PatientQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.selectedPatient?['id'];
    final newId = widget.selectedPatient?['id'];
    if (oldId != newId) {
      _lastAutoSelectedId = newId;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _getPatientStream() {
    final today = DateFormat('ddMMyy').format(DateTime.now());

    final zakatStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today)
        .collection('zakat')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {...d.data(), 'id': d.id, 'queueType': 'zakat'})
            .toList());

    final nonZakatStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today)
        .collection('non-zakat')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {...d.data(), 'id': d.id, 'queueType': 'non-zakat'})
            .toList());

    return StreamZip([zakatStream, nonZakatStream]).map((lists) {
      final combined = [...lists[0], ...lists[1]];

      // Sort: waiting → completed → dispensed → others
      combined.sort((a, b) {
        const order = {
          'waiting': 0,
          'completed': 1,
          'dispensed': 2,
          'other': 3,
        };
        final aStatus = a['status'] ?? 'other';
        final bStatus = b['status'] ?? 'other';

        final aPriority = order[aStatus] ?? 3;
        final bPriority = order[bStatus] ?? 3;

        if (aPriority != bPriority) {
          return aPriority.compareTo(bPriority);
        }

        final aSerialNum =
            int.tryParse(a['serial']?.split('-').last ?? '999') ?? 999;
        final bSerialNum =
            int.tryParse(b['serial']?.split('-').last ?? '999') ?? 999;
        return aSerialNum.compareTo(bSerialNum);
      });

      return combined;
    });
  }

  Future<Map<String, dynamic>?> _fetchPrescriptionData(
      String branchId, String patientCNIC, String serial) async {
    final doc = await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('prescriptions')
        .doc(patientCNIC)
        .collection('prescriptions')
        .doc(serial)
        .get();

    if (doc.exists) return doc.data();
    return null;
  }

  Future<void> _showEditRequestDialog(Map<String, dynamic> patient) async {
    final branchId = widget.branchId;
    final patientCNIC = patient['patientCNIC'];
    final serial = patient['serial'];

    final existingData =
        await _fetchPrescriptionData(branchId, patientCNIC, serial);

    final TextEditingController diagnosisCtrl =
        TextEditingController(text: existingData?['diagnosis'] ?? '');
    final TextEditingController conditionCtrl =
        TextEditingController(text: existingData?['complaint'] ?? '');
    final TextEditingController medicinesCtrl = TextEditingController(
        text: (existingData?['prescriptions'] as List?)
                ?.map((m) => m['name'])
                .join(", ") ??
            '');
    final TextEditingController labTestsCtrl = TextEditingController(
        text: (existingData?['labResults'] as List?)
                ?.map((t) => t['name'])
                .join(", ") ??
            '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Request Prescription Edit"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: diagnosisCtrl,
                decoration: const InputDecoration(labelText: "Diagnosis"),
              ),
              TextField(
                controller: conditionCtrl,
                decoration:
                    const InputDecoration(labelText: "Patient Condition"),
              ),
              TextField(
                controller: medicinesCtrl,
                decoration: const InputDecoration(
                    labelText: "Medicines (comma separated)"),
              ),
              TextField(
                controller: labTestsCtrl,
                decoration: const InputDecoration(
                    labelText: "Lab Tests (comma separated)"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.white,
            ),
            child: const Text("Request Change"),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('branches')
                  .doc(branchId)
                  .collection('editRequests')
                  .doc(serial)
                  .set({
                'serial': serial,
                'branchId': branchId,
                'patientName': patient['patientName'],
                'patientCNIC': patient['patientCNIC'],
                'requestedBy': patient['doctorId'] ?? 'unknown',
                'queueType': patient['queueType'],
                'oldData': existingData,
                'newData': {
                  'diagnosis': diagnosisCtrl.text.trim(),
                  'condition': conditionCtrl.text.trim(),
                  'medicines': medicinesCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                  'labTests': labTestsCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                },
                'status': 'pending',
                'requestedAt': Timestamp.now(),
              });

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Edit request sent for supervisor approval."),
              ));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _green,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_alt, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  "Patient Queue",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Summary section
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _getPatientStream(),
            builder: (context, snapshot) {
              final allPatients = snapshot.data ?? [];
              final waitingCount =
                  allPatients.where((p) => p['status'] == 'waiting').length;
              final completedCount =
                  allPatients.where((p) => p['status'] == 'completed').length;
              final totalCount = allPatients.length;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryCard("Waiting", waitingCount, _amber),
                    _buildSummaryCard("Completed", completedCount, _green),
                    _buildSummaryCard("Total", totalCount, _purple),
                  ],
                ),
              );
            },
          ),

          // List view
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _getPatientStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allPatients = snapshot.data!;
                if (allPatients.isEmpty) {
                  return const Center(
                      child: Text("No patients in queue",
                          style: TextStyle(color: Colors.black54)));
                }

                final waitingPatients =
                    allPatients.where((p) => p['status'] == 'waiting').toList();
                final firstWaiting =
                    waitingPatients.isNotEmpty ? waitingPatients.first : null;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final current = widget.selectedPatient;
                  final currentStatus = current?['status'] ?? '';
                  final currentId = current?['id'];

                  final shouldAutoSelect = current == null ||
                      currentStatus != 'waiting' ||
                      !waitingPatients.any((p) => p['id'] == currentId);

                  if (shouldAutoSelect && firstWaiting != null) {
                    final candidateId = firstWaiting['id'];
                    if (_lastAutoSelectedId != candidateId) {
                      widget.onPatientSelected(firstWaiting);
                      _lastAutoSelectedId = candidateId;
                    }
                  }
                });

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4),
                  itemCount: allPatients.length,
                  itemBuilder: (context, index) {
                    final patient = allPatients[index];
                    final isSelected =
                        widget.selectedPatient?['id'] == patient['id'];
                    final status = patient['status'] ?? '';
                    final isCompleted = status == 'completed';
                    final isDispensed = status == 'dispensed';
                    final isWaiting = status == 'waiting';

                    Color dotColor = isWaiting
                        ? _amber
                        : (isCompleted || isDispensed)
                            ? _green
                            : _purple;

                    Widget dot = Container(
                      height: 10,
                      width: 10,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    );

                    if (isWaiting) {
                      dot = ScaleTransition(
                        scale: _pulseAnimation,
                        child: dot,
                      );
                    }

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _amber.withOpacity(0.15)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dotColor, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12.withOpacity(0.08),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person, color: dotColor, size: 26),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patient['patientName'] ?? 'Unknown',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text(
                                      "Serial: ",
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      patient['serial'] ?? '-',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Show edit button ONLY if completed, NOT dispensed
                          if (isCompleted && !isDispensed)
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Colors.orange, size: 20),
                              tooltip: "Request Edit",
                              onPressed: () => _showEditRequestDialog(patient),
                            ),
                          dot,
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, int count, Color color) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            count.toString(),
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
