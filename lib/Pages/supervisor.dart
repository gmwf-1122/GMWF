// lib/pages/supervisor.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import 'sup_summary.dart';
import 'assets.dart';
import 'warehouse.dart';
import 'request.dart';

class SupervisorScreen extends StatefulWidget {
  final String branchId;
  final String supervisorId;

  const SupervisorScreen({
    super.key,
    required this.branchId,
    required this.supervisorId,
  });

  @override
  State<SupervisorScreen> createState() => _SupervisorScreenState();
}

class _SupervisorScreenState extends State<SupervisorScreen> {
  // ── STATE ───────────────────────────────────────────────────────
  String _activeSection = 'summary'; // summary | assets | warehouse | requests
  String _selectedFilter = 'today';
  bool _sidebarExpanded = true;

  late final FirestoreService _firestoreService = FirestoreService();

  String _supervisorName = 'Loading...';
  final DateFormat df = DateFormat('ddMMyy');
  final DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchSupervisorName();
  }

  // ── FETCH SUPERVISOR NAME FROM FIRESTORE ───────────────────────
  Future<void> _fetchSupervisorName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(widget.supervisorId)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data()!;
        final name = data['username']?.toString().trim();
        setState(() {
          _supervisorName = name?.isNotEmpty == true ? name! : 'Supervisor';
        });
      } else {
        setState(() {
          _supervisorName = 'Unknown User';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _supervisorName = 'Error';
        });
      }
    }
  }

  // ── LOGOUT ──────────────────────────────────────────────────────
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    }
  }

  // ── BUILD ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  // ── SIDEBAR ─────────────────────────────────────────────────────
  Widget _buildSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _sidebarExpanded ? 260 : 70,
      color: const Color(0xFF343A40),
      child: Column(
        children: [
          // Toggle
          GestureDetector(
            onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.dashboard, color: Colors.white, size: 24),
                  if (_sidebarExpanded) ...[
                    const SizedBox(width: 12),
                    const Text(
                      "Supervisor Dashboard",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _navItem(
                    Icons.summarize_outlined, "Patient Summary", 'summary'),
                _navItem(
                    Icons.account_balance_wallet, "Assets & Billing", 'assets'),
                _navItem(Icons.warehouse, "Warehouse", 'warehouse'),
                _navItem(Icons.request_page, "Dispense Requests", 'requests'),
              ],
            ),
          ),
          // Logout at bottom
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: _logout,
              child: Row(
                children: [
                  const Icon(Icons.logout, color: Colors.red, size: 22),
                  if (_sidebarExpanded) ...[
                    const SizedBox(width: 12),
                    const Text(
                      "Logout",
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, String section) {
    final active = _activeSection == section;
    return InkWell(
      onTap: () => setState(() => _activeSection = section),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: active ? Colors.blue.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            if (_sidebarExpanded) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── MAIN CONTENT ────────────────────────────────────────────────
  Widget _buildMainContent() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _sectionWidget(),
          ),
        ),
      ],
    );
  }

  Widget _sectionWidget() {
    switch (_activeSection) {
      case 'summary':
        return _buildPatientSummary();
      case 'assets':
        return AssetsPage(
          branchId: widget.branchId,
          isAdmin: true,
        );
      case 'warehouse':
        return WarehouseScreen(branchId: widget.branchId);
      case 'requests':
        return RequestPage(branchId: widget.branchId);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── HEADER (Title + Supervisor Name) ───────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Image.asset(
            'assets/Logo/gmwf.png',
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.local_hospital,
                  size: 32, color: Colors.blue);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Gulzar-e-Madina Dispensary ($_supervisorName)",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── PATIENT SUMMARY (Compact Cards) ────────────────────────────
  Widget _buildPatientSummary() {
    final start = _getStartDate();
    final end = now;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterTabs(),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // RECEPTIONIST CARD
                PatientSummaryCard(
                  title: "Receptionist",
                  dataStream: Stream.fromFuture(_fetchReceptionist(start, end)),
                  color: Colors.green,
                  titleIcon: Icons.receipt_long,
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
                const SizedBox(height: 12),

                // DOCTOR CARD
                PatientSummaryCard(
                  title: "Doctor",
                  dataStream: Stream.fromFuture(_fetchDoctor(start, end)),
                  color: Colors.blue,
                  titleIcon: Icons.local_hospital,
                  valueIcons: {
                    'v1': Icons.hourglass_empty,
                    'v2': Icons.medical_services,
                    'total': Icons.local_hospital,
                  },
                  valueLabels: {
                    'v1': 'Waiting',
                    'v2': 'Prescribed',
                  },
                ),
                const SizedBox(height: 12),

                // DISPENSARY CARD
                _dispensaryCard(start, end),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DateTime _getStartDate() {
    if (_selectedFilter == 'today') {
      return DateTime(now.year, now.month, now.day);
    } else if (_selectedFilter == 'week') {
      return now.subtract(const Duration(days: 6));
    } else {
      return DateTime(now.year, now.month, 1);
    }
  }

  Widget _filterTabs() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['today', 'week', 'month'].map((f) {
          final selected = _selectedFilter == f;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? Colors.blue : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                f.toUpperCase(),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── RECEPTIONIST DATA ───────────────────────────────────────────
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
    final revenue = zakat * 20 + nonZakat * 100;

    return {
      'v1': zakat,
      'v2': nonZakat,
      'total': total,
      'revenue': revenue,
    };
  }

  // ── DOCTOR DATA ─────────────────────────────────────────────────
  Future<Map<String, int>> _fetchDoctor(DateTime start, DateTime end) async {
    final Set<String> registeredCNICs = {};

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

  // ── DISPENSARY CARD (Custom) ───────────────────────────────────
  Widget _dispensaryCard(DateTime start, DateTime end) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: Stream.fromFuture(_fetchDispensary(start, end)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingCard("Dispensary", Icons.medication, Colors.orange);
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _emptyCard("Dispensary", Icons.medication, Colors.orange);
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
                    Icon(Icons.medication, color: Colors.orange, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      "Dispensary",
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _mini("Waiting", waiting, Icons.schedule, Colors.orange),
                    _mini("Dispensed", dispensedList.length, Icons.check_circle,
                        Colors.orange),
                    _mini("Total", total, Icons.medication, Colors.orange),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (dispensedList.isEmpty)
                  const Text("No dispensed patients",
                      style: TextStyle(color: Colors.grey))
                else
                  ...dispensedList.map((p) => _patientTile(p)).toList(),
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

    // Prescribed CNICs
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

    // Dispensed records
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

  Widget _patientTile(Map<String, dynamic> p) {
    final phone =
        (p['patientPhone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final hasWhatsApp = phone.length >= 10;
    final name = p['patientName'] ?? 'Patient';
    final cnic = p['patientCNIC'] ?? '';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: Colors.orange,
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

  Widget _loadingCard(String title, IconData icon, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
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

  Widget _emptyCard(String title, IconData icon, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
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
