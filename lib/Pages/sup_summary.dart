// lib/pages/sup_summary.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'inventory.dart';
import 'assets.dart';

/// ---------------------------------------------------------------------
/// 1. REUSABLE SUMMARY CARD (Receptionist & Doctor)
/// ---------------------------------------------------------------------
class PatientSummaryCard extends StatelessWidget {
  final String title;
  final Stream<Map<String, int>> dataStream;
  final Color color;
  final IconData titleIcon;
  final bool showRevenue;
  final Map<String, IconData> valueIcons;
  final Map<String, String> valueLabels;

  const PatientSummaryCard({
    super.key,
    required this.title,
    required this.dataStream,
    required this.color,
    required this.titleIcon,
    this.showRevenue = false,
    required this.valueIcons,
    required this.valueLabels,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, int>>(
      stream: dataStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoading();
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmpty();
        }

        final d = snapshot.data!;
        final revenue = d['revenue'] ?? 0;

        final List<Widget> minis = [];
        for (final key in ['v1', 'v2', 'v3']) {
          if (valueLabels.containsKey(key) && valueIcons.containsKey(key)) {
            final value = d[key] ?? 0;
            minis.add(
              _mini(
                valueLabels[key] ?? '',
                value,
                valueIcons[key] ?? Icons.help,
                color,
              ),
            );
          }
        }
        final total = d['total'] ?? 0;
        minis.add(
          _mini("Total", total, valueIcons['total'] ?? Icons.help, color),
        );

        return Card(
          elevation: 4.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(titleIcon, color: color, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: minis,
                ),
                if (showRevenue)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.attach_money,
                          size: 20,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Rs. $revenue",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mini(String label, int value, IconData icon, Color color) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              "$value",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _buildLoading() => Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(titleIcon, color: color, size: 28),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(titleIcon, color: color, size: 28),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              const Text("No data available", style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      );
}

/// ---------------------------------------------------------------------
/// 2. SUPERVISOR SCREEN
/// ---------------------------------------------------------------------
class SupervisorScreen extends StatefulWidget {
  final String branchId;

  const SupervisorScreen({super.key, required this.branchId});

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  final DateFormat df = DateFormat('ddMMyy');
  final DateFormat timeFormat = DateFormat('HH:mm');
  late DateTime now;
  String selectedPeriod = 'today';

  @override
  void initState() {
    super.initState();
    now = DateTime.now();
  }

  DateTime _startForPeriod(String p) {
    final now = DateTime.now();
    if (p == 'today') {
      return DateTime(now.year, now.month, now.day);
    } else if (p == 'week') {
      return DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6));
    } else {
      return DateTime(now.year, now.month, 1);
    }
  }

  DateTime _endForPeriod(String p) => DateTime.now();

  @override
  Widget build(BuildContext context) {
    final branchName = widget.branchId[0].toUpperCase() + widget.branchId.substring(1);
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    branchName,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const Spacer(),
                  ..._buildResourceButtons(),
                  const SizedBox(width: 20),
                  _periodToggle(),
                ],
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 800;
                  return isWide ? _cardsRow() : _cardsColumn();
                },
              ),
              const SizedBox(height: 20),
              StreamBuilder<Map<String, dynamic>>(
                stream: _dispensaryStream(selectedPeriod),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Text("No dispensed patients", style: TextStyle(color: Colors.grey, fontSize: 16));
                  }
                  final data = snapshot.data!;
                  final dispensedList = data['dispensed'] as List<Map<String, dynamic>>? ?? [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Dispensed Patients",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (dispensedList.isNotEmpty)
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: dispensedList.length,
                            itemBuilder: (context, index) {
                              final patient = dispensedList[index];
                              final name = patient['name'] as String? ?? 'Unknown';
                              final serial = patient['serial'] as String? ?? 'N/A';
                              final type = patient['type'] as String? ?? 'Unknown';
                              final doctorName = patient['doctorName'] as String? ?? 'Unknown';
                              final dispenserName = patient['dispenserName'] as String? ?? 'Unknown';
                              final createdByName = patient['createdByName'] as String? ?? 'Unknown';
                              final cnic = patient['cnic'] as String? ?? 'N/A';
                              final phone = patient['phone'] as String? ?? 'N/A';
                              final typeColor = type == 'zakat' ? Colors.green : (type == 'non-zakat' ? Colors.blue : Colors.orange);
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.person, color: Colors.green, size: 24),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            type.toUpperCase(),
                                            style: TextStyle(
                                              color: typeColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _infoRow(Icons.badge, 'CNIC: $cnic', copy: cnic != 'N/A' ? cnic : null),
                                      const SizedBox(height: 8),
                                      _infoRow(Icons.phone, 'Phone: $phone', copy: phone != 'N/A' ? phone : null),
                                      const SizedBox(height: 8),
                                      _infoRow(Icons.medical_services, 'Prescribed by: $doctorName'),
                                      const SizedBox(height: 8),
                                      _infoRow(Icons.token, 'Token generated by: $createdByName'),
                                      const SizedBox(height: 8),
                                      _infoRow(Icons.local_pharmacy, 'Dispensed by: $dispenserName'),
                                      const SizedBox(height: 8),
                                      _infoRow(Icons.numbers, 'Serial: $serial'),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      if (dispensedList.isEmpty)
                        const Center(
                          child: Text(
                            "No dispensed patients",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _periodButton("Today", 'today'),
          const SizedBox(width: 20),
          _periodButton("Week", 'week'),
          const SizedBox(width: 20),
          _periodButton("Month", 'month'),
        ],
      ),
    );
  }

  Widget _periodButton(String label, String p) {
    final selected = selectedPeriod == p;
    return InkWell(
      onTap: () => setState(() => selectedPeriod = p),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade700 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _cardsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SizedBox(
            height: 200, // Fixed height to make cards same size
            child: PatientSummaryCard(
              title: "Tokens",
              dataStream: _tokensStream(selectedPeriod),
              color: Colors.green.shade600,
              titleIcon: Icons.people_alt,
              showRevenue: true,
              valueIcons: {
                'v1': Icons.favorite,
                'v2': Icons.group,
                'v3': Icons.handshake,
                'total': Icons.people_alt,
              },
              valueLabels: {'v1': 'Zakat', 'v2': 'Non-Zakat', 'v3': 'GMWF'},
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: SizedBox(
            height: 200,
            child: PatientSummaryCard(
              title: "Prescriptions",
              dataStream: _prescriptionsStream(selectedPeriod),
              color: Colors.blue.shade600,
              titleIcon: Icons.medical_information,
              valueIcons: {
                'v1': Icons.timer,
                'v2': Icons.check,
                'total': Icons.medical_information,
              },
              valueLabels: {'v1': 'Waiting', 'v2': 'Prescribed'},
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: SizedBox(
            height: 200,
            child: _dispensaryCard(selectedPeriod),
          ),
        ),
      ],
    );
  }

  Widget _cardsColumn() {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PatientSummaryCard(
            title: "Tokens",
            dataStream: _tokensStream(selectedPeriod),
            color: Colors.green.shade600,
            titleIcon: Icons.people_alt,
            showRevenue: true,
            valueIcons: {
              'v1': Icons.favorite,
              'v2': Icons.group,
              'v3': Icons.handshake,
              'total': Icons.people_alt,
            },
            valueLabels: {'v1': 'Zakat', 'v2': 'Non-Zakat', 'v3': 'GMWF'},
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 200,
          child: PatientSummaryCard(
            title: "Prescriptions",
            dataStream: _prescriptionsStream(selectedPeriod),
            color: Colors.blue.shade600,
            titleIcon: Icons.medical_information,
            valueIcons: {
              'v1': Icons.timer,
              'v2': Icons.check,
              'total': Icons.medical_information,
            },
            valueLabels: {'v1': 'Waiting', 'v2': 'Prescribed'},
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 200,
          child: _dispensaryCard(selectedPeriod),
        ),
      ],
    );
  }

  // -------------------- TOKENS STREAM --------------------
  Stream<Map<String, int>> _tokensStream(String period) {
    return Stream.fromFuture(_fetchTokens(period));
  }

  Future<Map<String, int>> _fetchTokens(
    String period,
  ) async {
    int zakat = 0, nonZakat = 0, gmwf = 0;

    final start = _startForPeriod(period);
    final end = _endForPeriod(period);

    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ds = df.format(d);
      final base = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(ds);

      final zSnap = await base.collection('zakat').get();
      final nzSnap = await base.collection('non-zakat').get();
      final gmwfSnap = await base.collection('gmwf').get();

      zakat += zSnap.size;
      nonZakat += nzSnap.size;
      gmwf += gmwfSnap.size;
    }

    final total = zakat + nonZakat + gmwf;
    final revenue = (zakat * 20) + (nonZakat * 100) + (gmwf * 0);

    return {
      'v1': zakat,
      'v2': nonZakat,
      'v3': gmwf,
      'total': total,
      'revenue': revenue,
    };
  }

  // -------------------- PRESCRIPTIONS STREAM --------------------
  Stream<Map<String, int>> _prescriptionsStream(String period) {
    return Stream.fromFuture(_fetchPrescriptions(period));
  }

  Future<Map<String, int>> _fetchPrescriptions(
    String period,
  ) async {
    final start = _startForPeriod(period);
    final end = _endForPeriod(period);

    final Set<String> registeredSerials = {};
    final Map<String, String> serialToCnic = {}; // serial -> cnic mapping
    final Set<String> prescribedSerials = {};
    final Set<String> dispensedSerials = {};

    // ---- SERIALS: collect serials AND CNICs ----
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ds = df.format(d);
      final base = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(ds);

      for (final coll in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await base.collection(coll).get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final serial = data['serial']?.toString();
          final cnic = data['cnic']?.toString() ?? data['id']?.toString();
          if (serial != null && serial.isNotEmpty) {
            registeredSerials.add(serial);
            if (cnic != null && cnic.isNotEmpty) serialToCnic[serial] = cnic;
          }
        }
      }
    }

    // ---- PRESCRIBED: follow Serial -> CNIC -> branches/{branchId}/prescription/{cnic}/prescriptions ----
    final presRoot = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('prescription');

    for (final serial in registeredSerials) {
      final cnic = serialToCnic[serial];
      if (cnic == null || cnic.isEmpty) continue;
      final presColl = presRoot.doc(cnic).collection('prescriptions');
      // query for any prescription doc whose 'serial' field matches this serial
      final qSnap = await presColl.where('serial', isEqualTo: serial).limit(1).get();
      if (qSnap.docs.isNotEmpty) {
        prescribedSerials.add(serial);
      }
    }

    // ---- DISPENSED SERIALS ----
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ds = df.format(d);
      final collRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('dispensary')
          .doc(ds)
          .collection(ds);

      final snap = await collRef.get();
      for (final doc in snap.docs) {
        final serial = doc.data()['serial']?.toString();
        if (serial != null && serial.isNotEmpty) {
          dispensedSerials.add(serial);
        }
      }
    }

    // Per rule: Waiting = registeredSerials MINUS (prescribed ∪ dispensed)
    final unionPrescribedDispensed = prescribedSerials.union(dispensedSerials);
    final waiting = registeredSerials.difference(unionPrescribedDispensed).length;
    final prescribedCount = prescribedSerials.length;

    return {
      'v1': waiting,
      'v2': prescribedCount,
      'total': registeredSerials.length,
    };
  }

  // -------------------- DISPENSARY STREAM --------------------
  Stream<Map<String, dynamic>> _dispensaryStream(String period) {
    return Stream.fromFuture(_fetchDispensary(period));
  }

  Future<Map<String, dynamic>> _fetchDispensary(
    String period,
  ) async {
    final start = _startForPeriod(period);
    final end = _endForPeriod(period);

    final Set<String> registeredSerials = {};
    final Map<String, String> serialToCnic = {};
    final Set<String> prescribedSerials = {};
    final Set<String> dispensedSerials = {};
    final List<Map<String, dynamic>> dispensedList = [];
    final Map<String, String> serialToType = {};
    final Map<String, Map<String, dynamic>> tokensData = {};
    final Map<String, String> userIdToName = {};

    // Fetch users for names
    final usersSnap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('users')
        .get();
    for (var doc in usersSnap.docs) {
      userIdToName[doc.id] = doc.data()['username'] ?? doc.data()['email'] ?? 'Unknown';
    }

    // ---- SERIALS ----
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ds = df.format(d);
      final base = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(ds);

      for (final coll in ['zakat', 'non-zakat', 'gmwf']) {
        final snap = await base.collection(coll).get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final serial = data['serial']?.toString();
          final cnic = data['cnic']?.toString() ?? data['id']?.toString();
          if (serial != null && serial.isNotEmpty) {
            registeredSerials.add(serial);
            tokensData[serial] = data;
            serialToType[serial] = coll;
            if (cnic != null && cnic.isNotEmpty) serialToCnic[serial] = cnic;
          }
        }
      }
    }

    // ---- PRESCRIBED (via CNIC group) ----
    final presRoot = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('prescription');

    for (final serial in registeredSerials) {
      final cnic = serialToCnic[serial];
      if (cnic == null || cnic.isEmpty) continue;
      final presColl = presRoot.doc(cnic).collection('prescriptions');
      final qSnap = await presColl.where('serial', isEqualTo: serial).limit(1).get();
      if (qSnap.docs.isNotEmpty) {
        prescribedSerials.add(serial);
      }
    }

    // ---- DISPENSED SERIALS (and list) ----
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ds = df.format(d);
      final collRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('dispensary')
          .doc(ds)
          .collection(ds);

      final snap = await collRef.get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final serial = data['serial']?.toString();
        if (serial == null || serial.isEmpty) continue;
        data['type'] = serialToType[serial] ?? 'Unknown';
        data['createdBy'] = tokensData[serial]?['createdBy']?.toString() ?? '';
        data['createdByName'] = userIdToName[data['createdBy']] ?? 'Unknown';
        final cnic = serialToCnic[serial];
        data['cnic'] = cnic ?? 'N/A';
        data['phone'] = 'N/A'; // Default
        if (cnic != null && cnic.isNotEmpty) {
          // Fetch patient details for phone
          final patientDoc = await FirebaseFirestore.instance
              .collection('branches/${widget.branchId}/patients')
              .doc(cnic)
              .get();
          if (patientDoc.exists) {
            data['phone'] = patientDoc.data()?['phone']?.toString() ?? 'N/A';
          }
          // Fetch prescription for doctorName
          final presColl = presRoot.doc(cnic).collection('prescriptions');
          final presDoc = await presColl.doc(serial).get();
          if (presDoc.exists) {
            data['doctorName'] = presDoc.data()?['doctorName']?.toString() ?? 'Unknown';
          }
        }
        data['dispenserName'] = data['dispenserName'] ?? 'Unknown';
        dispensedList.add(data);
        dispensedSerials.add(serial);
      }
    }

    // Waiting at dispensary = prescribed MINUS already dispensed
    final waiting = prescribedSerials.difference(dispensedSerials).length;

    return {'v1': waiting, 'v2': dispensedList.length, 'total': waiting + dispensedList.length, 'dispensed': dispensedList};
  }

  // -------------------- DISPENSARY CARD --------------------
  Widget _dispensaryCard(String period) {
    final color = Colors.orange.shade600;
    return StreamBuilder<Map<String, dynamic>>(
      stream: _dispensaryStream(period),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildDispensaryLoading(color);
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildDispensaryEmpty(color);
        }

        final data = snapshot.data!;
        final waiting = data['v1'] as int? ?? 0;
        final dispensedCount = data['v2'] as int? ?? 0;
        final total = data['total'] as int? ?? 0;

        return Card(
          elevation: 4.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_pharmacy,
                      color: color,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Dispensary Data",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _miniStat(
                      "Waiting",
                      waiting,
                      Icons.access_time,
                      color,
                    ),
                    _miniStat(
                      "Dispensed",
                      dispensedCount,
                      Icons.done_all,
                      color,
                    ),
                    _miniStat(
                      "Total",
                      total,
                      Icons.local_pharmacy,
                      color,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniStat(String label, int value, IconData icon, Color color) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              "$value",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _buildDispensaryLoading(Color color) => Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.local_pharmacy, color: color, size: 28),
              const SizedBox(width: 12),
              Text(
                "Dispensary Data",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      );

  Widget _buildDispensaryEmpty(Color color) => Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.local_pharmacy, color: color, size: 28),
              const SizedBox(width: 12),
              Text(
                "Dispensary Data",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              const Text("No data available", style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      );

  List<Widget> _buildResourceButtons() {
    return [
      ElevatedButton.icon(
        icon: const Icon(Icons.inventory),
        label: const Text("View Inventory"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => InventoryPage(branchId: widget.branchId),
            ),
          );
        },
      ),
      const SizedBox(width: 12),
      ElevatedButton.icon(
        icon: const Icon(Icons.account_balance_wallet),
        label: const Text("View Assets"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple.shade600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => AssetsPage(branchId: widget.branchId, isAdmin: false),
            ),
          );
        },
      ),
    ];
  }

  Widget _infoRow(IconData icon, String text, {String? copy}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 14, color: Colors.grey[800]),
          ),
        ),
        if (copy != null)
          IconButton(
            icon: const Icon(Icons.content_copy, size: 20, color: Colors.grey),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copy));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied: $copy')),
              );
            },
          ),
      ],
    );
  }
}