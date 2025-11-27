// lib/pages/sup_summary.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------
// 1. REUSABLE SUMMARY CARD (Receptionist & Doctor)
// ---------------------------------------------------------------------
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
        final v1 = d['v1'] ?? 0;
        final v2 = d['v2'] ?? 0;
        final total = d['total'] ?? 0;
        final revenue = d['revenue'] ?? 0;

        return Card(
          elevation: 1.5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(titleIcon, color: color, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _mini(valueLabels['v1']!, v1, valueIcons['v1']!, color),
                    _mini(valueLabels['v2']!, v2, valueIcons['v2']!, color),
                    _mini("Total", total, valueIcons['total']!, color),
                  ],
                ),
                if (showRevenue)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_money,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text("Rs. $revenue",
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
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

  Widget _mini(String label, int value, IconData icon, Color color) => Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text("$value",
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _buildLoading() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(titleIcon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: color)),
              const Spacer(),
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(titleIcon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: color)),
              const Spacer(),
              const Text("No data", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------
// 2. MAIN SUPERVISOR SCREEN
// ---------------------------------------------------------------------
class SupervisorScreen extends StatefulWidget {
  final String branchId;

  const SupervisorScreen({super.key, required this.branchId});

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final DateFormat df = DateFormat('ddMMyy');
  final DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Supervisor Dashboard"),
        backgroundColor: Colors.green.shade800,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.amber,
          tabs: const [
            Tab(text: "Today"),
            Tab(text: "This Week"),
            Tab(text: "This Month"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildPeriod(isToday: true),
          _buildPeriod(isToday: false, isWeek: true),
          _buildPeriod(isToday: false, isWeek: false),
        ],
      ),
    );
  }

  Widget _buildPeriod({required bool isToday, bool isWeek = false}) {
    final DateTime start;
    if (isToday) {
      start = DateTime(now.year, now.month, now.day);
    } else if (isWeek) {
      start = now.subtract(const Duration(days: 6));
    } else {
      start = DateTime(now.year, now.month, 1);
    }
    final end = now;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. RECEPTIONIST
        PatientSummaryCard(
          title: "Receptionist",
          dataStream: _receptionistStream(start, end),
          color: Colors.greenAccent,
          titleIcon: Icons.group,
          showRevenue: true,
          valueIcons: {
            'v1': Icons.volunteer_activism,
            'v2': Icons.people,
            'total': Icons.group,
          },
          valueLabels: {
            'v1': 'Zakat',
            'v2': 'Non-Zakat',
          },
        ),
        const SizedBox(height: 16),

        // 2. DOCTOR
        PatientSummaryCard(
          title: "Doctor",
          dataStream: _doctorStream(start, end),
          color: Colors.blueAccent,
          titleIcon: Icons.local_hospital,
          valueIcons: {
            'v1': Icons.hourglass_bottom,
            'v2': Icons.medical_services,
            'total': Icons.local_hospital,
          },
          valueLabels: {
            'v1': 'Waiting',
            'v2': 'Prescribed',
          },
        ),
        const SizedBox(height: 16),

        // 3. DISPENSARY
        _dispensaryCard(start, end),
      ],
    );
  }

  // -----------------------------------------------------------------
  // 1. RECEPTIONIST: Zakat, Non-Zakat, Total, Revenue
  // -----------------------------------------------------------------
  Stream<Map<String, int>> _receptionistStream(DateTime start, DateTime end) {
    return Stream.fromFuture(_fetchReceptionist(start, end));
  }

  Future<Map<String, int>> _fetchReceptionist(
      DateTime start, DateTime end) async {
    int zakat = 0, nonZakat = 0;

    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ds = df.format(d);
      final base = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(ds);

      final zSnap = await base.collection('zakat').get();
      final nzSnap = await base.collection('non-zakat').get();

      zakat += zSnap.size;
      nonZakat += nzSnap.size;
    }

    final total = zakat + nonZakat;
    final revenue = (zakat * 20) + (nonZakat * 100);

    return {
      'v1': zakat,
      'v2': nonZakat,
      'total': total,
      'revenue': revenue,
    };
  }

  // -----------------------------------------------------------------
  // 2. DOCTOR: Waiting, Prescribed, Total
  // -----------------------------------------------------------------
  Stream<Map<String, int>> _doctorStream(DateTime start, DateTime end) {
    return Stream.fromFuture(_fetchDoctor(start, end));
  }

  Future<Map<String, int>> _fetchDoctor(DateTime start, DateTime end) async {
    final Set<String> registeredCNICs = {};

    // ---- Registered patients (serials) ----
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      final ds = df.format(d);
      final base = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(ds);

      for (final coll in ['zakat', 'non-zakat']) {
        final snap = await base.collection(coll).get();
        for (final doc in snap.docs) {
          final cnic = doc.data()['patientCNIC']?.toString();
          if (cnic != null && cnic.isNotEmpty) {
            registeredCNICs.add(cnic);
          }
        }
      }
    }

    // ---- Prescribed patients (any doc in prescriptions/{cnic}/prescriptions) ----
    final Set<String> prescribedCNICs = {};
    final presBase = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('prescriptions');

    final cnicDocs = await presBase.get();
    for (final doc in cnicDocs.docs) {
      final presSnap = await doc.reference.collection('prescriptions').get();
      if (presSnap.docs.isNotEmpty) {
        prescribedCNICs.add(doc.id);
      }
    }

    final prescribed = registeredCNICs.intersection(prescribedCNICs).length;
    final waiting = registeredCNICs.length - prescribed;

    return {
      'v1': waiting,
      'v2': prescribed,
      'total': registeredCNICs.length,
    };
  }

  // -----------------------------------------------------------------
  // 3. DISPENSARY: Waiting, Dispensed, Total + WhatsApp
  // -----------------------------------------------------------------
  Widget _dispensaryCard(DateTime start, DateTime end) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: Stream.fromFuture(_fetchDispensary(start, end)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildDispensaryLoading();
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildDispensaryEmpty();
        }

        final data = snapshot.data!;
        final waiting = data['waiting'] as int;
        final dispensedList = data['dispensed'] as List<Map<String, dynamic>>;
        final total = waiting + dispensedList.length;

        return Card(
          elevation: 1.5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.medication,
                        color: Colors.purpleAccent, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      "Dispensary",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.purpleAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _miniStat("Waiting", waiting, Icons.schedule,
                        Colors.purpleAccent),
                    _miniStat("Dispensed", dispensedList.length,
                        Icons.check_circle, Colors.purpleAccent),
                    _miniStat(
                        "Total", total, Icons.medication, Colors.purpleAccent),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (dispensedList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text("No dispensed patients",
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ...dispensedList
                      .map((p) => _dispensedPatientTile(p))
                      .toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchDispensary(
      DateTime start, DateTime end) async {
    final List<Map<String, dynamic>> dispensed = [];
    final Set<String> dispensedCNICs = {};

    // ---- Prescribed patients (any doc in prescriptions/{cnic}/prescriptions) ----
    final Set<String> prescribedCNICs = {};
    final presBase = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('prescriptions');

    final cnicDocs = await presBase.get();
    for (final doc in cnicDocs.docs) {
      final presSnap = await doc.reference.collection('prescriptions').get();
      if (presSnap.docs.isNotEmpty) {
        prescribedCNICs.add(doc.id);
      }
    }

    // ---- Dispensed patients (any doc in dispensary/{ddMMyy}/{ddMMyy}) ----
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
        data['docId'] = doc.id; // fallback serial if needed
        dispensed.add(data);
        final cnic = data['patientCNIC']?.toString();
        if (cnic != null) dispensedCNICs.add(cnic);
      }
    }

    final waiting = prescribedCNICs.difference(dispensedCNICs).length;

    return {
      'waiting': waiting,
      'dispensed': dispensed,
    };
  }

  // -----------------------------------------------------------------
  // UI HELPERS
  // -----------------------------------------------------------------
  Widget _miniStat(String label, int value, IconData icon, Color color) =>
      Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text("$value",
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _dispensedPatientTile(Map<String, dynamic> p) {
    final phone =
        (p['patientPhone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final hasWhatsApp = phone.length >= 10;
    final name = p['patientName'] ?? 'Patient';
    final cnic = p['patientCNIC']?.toString() ?? '';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: Colors.purpleAccent,
        child: Icon(Icons.check_circle, color: Colors.white, size: 16),
      ),
      title: Text(name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text("CNIC: $cnic", style: const TextStyle(fontSize: 12)),
      trailing: hasWhatsApp
          ? IconButton(
              icon: const Icon(Icons.message, color: Colors.green, size: 20),
              tooltip: "WhatsApp",
              onPressed: () => _openWhatsApp(phone, name),
            )
          : const Icon(Icons.phone_disabled, color: Colors.grey, size: 20),
    );
  }

  void _openWhatsApp(String phone, String name) async {
    final msg = Uri.encodeComponent(
        "Hello $name, your medicine has been dispensed. Thank you!");
    final url = Uri.parse("https://wa.me/$phone?text=$msg");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("WhatsApp not available")),
        );
      }
    }
  }

  Widget _buildDispensaryLoading() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.medication, color: Colors.purpleAccent, size: 22),
              const SizedBox(width: 8),
              Text("Dispensary",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.purpleAccent)),
              const Spacer(),
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
      );

  Widget _buildDispensaryEmpty() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.medication, color: Colors.purpleAccent, size: 22),
              const SizedBox(width: 8),
              Text("Dispensary",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.purpleAccent)),
              const Spacer(),
              const Text("No data", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}
