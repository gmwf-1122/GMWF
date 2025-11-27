// lib/pages/receptionist_screen.dart
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'notification_screen.dart';
import 'patient_register.dart';
import 'token_screen.dart';

class ReceptionistScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final String receptionistName;

  const ReceptionistScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
    required this.receptionistName,
  });

  @override
  State<ReceptionistScreen> createState() => _ReceptionistScreenState();
}

class _ReceptionistScreenState extends State<ReceptionistScreen>
    with TickerProviderStateMixin {
  String? _username;
  String? _pendingCnic;
  String _activeSection = 'token';

  final GlobalKey<PatientRegisterPageState> _registerKey =
      GlobalKey<PatientRegisterPageState>();
  final GlobalKey<TokenScreenState> _tokenKey = GlobalKey<TokenScreenState>();

  @override
  void initState() {
    super.initState();
    _fetchReceptionistName();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _fetchReceptionistName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('users')
          .doc(widget.receptionistId)
          .get();

      setState(() {
        _username = doc.exists
            ? doc['username'] ?? widget.receptionistName
            : widget.receptionistName;
      });
    } catch (_) {
      setState(() => _username = widget.receptionistName);
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  void _handlePatientNotFound(String cnic) {
    setState(() {
      _pendingCnic = cnic;
      _activeSection = 'register';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerKey.currentState?.prefillCnic(cnic);
    });
  }

  void _onPatientRegistered(String cnic) {
    setState(() {
      _pendingCnic = cnic;
      _activeSection = 'token';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tokenKey.currentState?.focusAndFillCnic(cnic);
    });
  }

  Widget _buildActionButton(String label, IconData icon, String section) {
    final bool isActive = _activeSection == section;
    final Color baseColor = section == 'register' ? Colors.amber : Colors.blue;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: ElevatedButton.icon(
          icon: Icon(icon, color: isActive ? Colors.white : baseColor),
          label: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : baseColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isActive ? baseColor : Colors.white.withOpacity(0.85),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: isActive ? 4 : 0,
          ),
          onPressed: () {
            setState(() => _activeSection = section);
          },
        ),
      ),
    );
  }

  Widget _buildAnimatedTokenSummary() {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final firestore = FirebaseFirestore.instance;

    final zakatStream = firestore
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today)
        .collection('zakat')
        .snapshots();

    final nonZakatStream = firestore
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today)
        .collection('non-zakat')
        .snapshots();

    return StreamBuilder<List<QuerySnapshot>>(
      stream: CombineLatestStream.list([zakatStream, nonZakatStream]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }

        final zakatCount = snapshot.data![0].docs.length;
        final nonZakatCount = snapshot.data![1].docs.length;
        final totalPatients = zakatCount + nonZakatCount;
        final zakatAmount = zakatCount * 20;
        final nonZakatAmount = nonZakatCount * 100;
        final totalAmount = zakatAmount + nonZakatAmount;

        final summaryRef = firestore
            .collection('branches')
            .doc(widget.branchId)
            .collection('serials')
            .doc(today);

        summaryRef.set({
          'zakatCount': zakatCount,
          'nonZakatCount': nonZakatCount,
          'totalPatients': totalPatients,
          'zakatAmount': zakatAmount,
          'nonZakatAmount': nonZakatAmount,
          'totalAmount': totalAmount,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildAnimatedSummaryCard(
              "Zakat",
              zakatCount,
              "Rs. $zakatAmount",
              Colors.greenAccent,
              Icons.volunteer_activism,
            ),
            _buildAnimatedSummaryCard(
              "Non-Zakat",
              nonZakatCount,
              "Rs. $nonZakatAmount",
              Colors.lightBlueAccent,
              Icons.people_alt_rounded,
            ),
            _buildAnimatedSummaryCard(
              "Total",
              totalPatients,
              "Rs. $totalAmount",
              Colors.amberAccent,
              Icons.summarize_rounded,
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedSummaryCard(
      String title, int count, String amount, Color color, IconData icon) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: Container(
        key: ValueKey<int>(count),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text("$count Patients",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text(amount,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // REQUEST TOKEN REVERSAL → via dispense_requests
  // -----------------------------------------------------------------
  Future<void> _requestTokenReversal(
    DocumentSnapshot doc,
    bool isZakat,
    String tokenId,
    String patientId,
    double amount,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.green.shade900,
        title: const Text("Request Token Reversal",
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Token ID: $tokenId",
                style: const TextStyle(color: Colors.white70)),
            Text("Patient ID: $patientId",
                style: const TextStyle(color: Colors.white70)),
            Text("Amount to refund: Rs. $amount",
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            const Text(
              "This will send a reversal request to admin. "
              "Token will be deleted and amount refunded only if approved.",
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            child:
                const Text("Cancel", style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Request", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final requestRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('dispense_requests')
          .doc();

      await requestRef.set({
        'requestType': 'token_reversal',
        'status': 'pending',
        'tokenId': tokenId,
        'patientId': patientId,
        'amount': amount,
        'category': isZakat ? 'zakat' : 'non-zakat',
        'requestedBy': widget.receptionistId,
        'requestedAt': FieldValue.serverTimestamp(),
        'createdBy': widget.receptionistName,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reversal request sent to admin!"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to send request: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // -----------------------------------------------------------------
  // LOG CARD – Show "Request Reverse" instead of direct delete
  // -----------------------------------------------------------------
  Widget _buildLogCard() {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final baseRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today);

    return StreamBuilder<List<QuerySnapshot>>(
      stream: CombineLatestStream.list([
        baseRef
            .collection('zakat')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        baseRef
            .collection('non-zakat')
            .orderBy('createdAt', descending: true)
            .snapshots(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }

        final zakatDocs = snapshot.data![0].docs;
        final nonZakatDocs = snapshot.data![1].docs;
        final allDocs = [...zakatDocs, ...nonZakatDocs]..sort((a, b) {
            final ta = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            final tb = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
            return tb.compareTo(ta); // Newest first
          });

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Today's Token Log",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const Divider(color: Colors.white30, height: 18),
              Expanded(
                child: allDocs.isEmpty
                    ? const Center(
                        child: Text("No tokens issued today.",
                            style: TextStyle(color: Colors.white70)))
                    : ListView.builder(
                        itemCount: allDocs.length,
                        itemBuilder: (context, i) {
                          final data =
                              allDocs[i].data() as Map<String, dynamic>;
                          final name = data['patientName'] ?? 'Unknown';
                          final cnic = data['patientCNIC'] ?? '';
                          final serial = data['serial'] ?? 'N/A';
                          final tokenId = allDocs[i].id;
                          final patientId = data['patientId']?.toString() ?? '';
                          final isZakat = zakatDocs.contains(allDocs[i]);
                          final category = isZakat ? 'Zakat' : 'Non-Zakat';
                          final amount = isZakat ? 20.0 : 100.0;
                          final createdAt =
                              (data['createdAt'] as Timestamp?)?.toDate();
                          final status = (data['status'] ?? 'waiting')
                              .toString()
                              .toLowerCase();
                          final isReversible = status == 'waiting';

                          return Card(
                            color: Colors.green.withOpacity(0.25),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              title: Text(
                                "$name ($category)",
                                style: TextStyle(
                                  color: isZakat
                                      ? Colors.greenAccent
                                      : Colors.lightBlueAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                "Token #: $serial\nCNIC: $cnic\nTime: ${createdAt != null ? DateFormat('hh:mm a').format(createdAt) : 'N/A'}",
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: isReversible
                                  ? IconButton(
                                      icon: const Icon(Icons.undo,
                                          color: Colors.orange),
                                      tooltip: "Request Token Reversal",
                                      onPressed: () => _requestTokenReversal(
                                        allDocs[i],
                                        isZakat,
                                        tokenId,
                                        patientId,
                                        amount,
                                      ),
                                    )
                                  : const Tooltip(
                                      message: "Processed — cannot reverse",
                                      child: Icon(Icons.check_circle,
                                          color: Colors.lightGreenAccent,
                                          size: 26),
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 32, 90, 49),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/3.jpg"),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
              color: Colors.green.shade900.withOpacity(0.85),
              child: Row(
                children: [
                  const Icon(Icons.local_hospital_rounded,
                      color: Colors.white, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Receptionist - (${_username ?? 'Loading...'})",
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications,
                        color: Colors.white, size: 24),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationScreen(
                            branchId: widget.branchId,
                            userId: widget.receptionistId,
                            role: 'receptionist',
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text("Logout",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionButton(
                      'Register Patient', Icons.person_add_alt_1, 'register'),
                  _buildActionButton(
                      'Issue Token', Icons.confirmation_num_outlined, 'token'),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(
                      top: 8, left: 20, right: 20, bottom: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left: Register or Token
                      Expanded(
                        flex: 4,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(0.05, 0),
                                      end: Offset.zero)
                                  .animate(anim),
                              child: child,
                            ),
                          ),
                          child: IndexedStack(
                            index: _activeSection == 'register' ? 0 : 1,
                            children: [
                              PatientRegisterPage(
                                key: _registerKey,
                                branchId: widget.branchId,
                                receptionistId: widget.receptionistId,
                                initialCnic: _pendingCnic,
                                onPatientRegistered: _onPatientRegistered,
                              ),
                              TokenScreen(
                                key: _tokenKey,
                                branchId: widget.branchId,
                                receptionistId: widget.receptionistId,
                                onPatientNotFound: _handlePatientNotFound,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 40),

                      // Right: Summary + Log
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _buildAnimatedTokenSummary(),
                            const SizedBox(height: 10),
                            Expanded(child: _buildLogCard()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
