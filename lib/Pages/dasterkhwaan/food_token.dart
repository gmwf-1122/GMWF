import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class DasterkhwaanTokenGenerator extends StatefulWidget {
  static const String routeName = '/dasterkhwaan-token';
  const DasterkhwaanTokenGenerator({super.key});

  @override
  State<DasterkhwaanTokenGenerator> createState() => _DasterkhwaanTokenGeneratorState();
}

class _DasterkhwaanTokenGeneratorState extends State<DasterkhwaanTokenGenerator> {
  final TextEditingController _quantityController = TextEditingController(text: "1");
  final double pricePerToken = 10.0;
  String userName = "User";
  String? _branchId;

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  late final String today = _dateFormat.format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadUserAndBranch();
  }

  Future<void> _loadUserAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final branchesSnap = await FirebaseFirestore.instance.collection("branches").get();
      for (final branch in branchesSnap.docs) {
        final userDoc = await branch.reference.collection("users").doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          setState(() {
            userName = data['username'] ?? user.email?.split('@').first ?? "User";
            _branchId = branch.id;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading user/branch: $e");
    }
  }

  CollectionReference get _tokensCol {
    if (_branchId == null) throw Exception("Branch not found");
    return FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(today)
        .collection('tokens');
  }

  DocumentReference get _dayDoc {
    if (_branchId == null) throw Exception("Branch not found");
    return FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(today);
  }

  Future<Map<String, int>> _getTodayStats() async {
    if (_branchId == null) return {'total': 0, 'served': 0, 'pending': 0};

    final snapshot = await _dayDoc.get();
    final data = snapshot.data() as Map<String, dynamic>? ?? {};
    int total = data['totalTokens'] as int? ?? 0;
    int served = data['servedTokens'] as int? ?? 0;
    int pending = total - served;

    return {'total': total, 'served': served, 'pending': pending};
  }

  Future<void> _onRefresh() async {
    setState(() {});
  }

  Future<void> _generateTokens() async {
    final quantityText = _quantityController.text.trim();
    final quantity = int.tryParse(quantityText) ?? 0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid quantity"), backgroundColor: Colors.red),
      );
      return;
    }

    if (_branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Branch not found!"), backgroundColor: Colors.red),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    final CollectionReference tokensCollectionRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(today)
        .collection('tokens');

    final DocumentReference dayDocRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(today);

    final batch = FirebaseFirestore.instance.batch();

    final snapshot = await tokensCollectionRef.get();
    final startNumber = snapshot.size + 1;

    for (int i = 0; i < quantity; i++) {
      final docRef = tokensCollectionRef.doc();
      batch.set(docRef, {
        'number': startNumber + i,
        'time': FieldValue.serverTimestamp(),
        'served': false,
      });
    }

    batch.set(dayDocRef, {
      'totalTokens': FieldValue.increment(quantity),
    }, SetOptions(merge: true));

    await batch.commit();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$quantity Token${quantity > 1 ? 's' : ''} Generated! → PKR ${quantity * pricePerToken}"),
        backgroundColor: const Color(0xFF4CAF50),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    _quantityController.text = "1";
    setState(() {});
  }

  void _selectQuantity(int qty) {
    _quantityController.text = qty.toString();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            "assets/logo/gmwf.png",
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 40),
          ),
        ),
        title: Text(
          "Tokens ($userName)",
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.black87),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
              }
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text("Logout", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _onRefresh,
        color: const Color(0xFF4CAF50),
        backgroundColor: Colors.white,
        strokeWidth: 2,
        child: LayoutBuilder(
          builder: (context, constraints) {
            bool isWide = constraints.maxWidth > 600;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(isWide ? 32 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<Map<String, int>>(
                    future: _getTodayStats(),
                    builder: (context, snapshot) {
                      final total = snapshot.data?['total'] ?? 0;
                      final served = snapshot.data?['served'] ?? 0;
                      final pending = total - served;
                      final value = total * pricePerToken;

                      List<Widget> statWidgets = [
                        _buildStatCard("Total Tokens", total.toString(), Colors.green[50]!, Colors.green.shade700, icon: Icons.confirmation_number),
                        _buildStatCard("Served", served.toString(), Colors.orange[50]!, Colors.orange.shade700, icon: Icons.check_circle),
                        _buildStatCard("Pending", pending.toString(), Colors.blue[50]!, Colors.blue.shade700, icon: Icons.access_time),
                        _buildStatCard("Total Value", value.toStringAsFixed(0), Colors.purple[50]!, Colors.purple.shade700, icon: Icons.account_balance_wallet, isValue: true),
                      ];

                      return isWide
                          ? GridView.count(
                              crossAxisCount: 4,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 1.2,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              children: statWidgets,
                            )
                          : Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: statWidgets[0]),
                                    const SizedBox(width: 12),
                                    Expanded(child: statWidgets[1]),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: statWidgets[2]),
                                    const SizedBox(width: 12),
                                    Expanded(child: statWidgets[3]),
                                  ],
                                ),
                              ],
                            );
                    },
                  ),
                  SizedBox(height: isWide ? 48 : 32),
                  const Text("Generate New Tokens", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text("Each token = PKR ${pricePerToken.toInt()}", style: TextStyle(color: Colors.grey[600])),

                  SizedBox(height: isWide ? 32 : 20),
                  const Text("Quick Select:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [1, 2, 3, 4, 5].map((qty) {
                      final isSelected = _quantityController.text == qty.toString();
                      return GestureDetector(
                        onTap: () => _selectQuantity(qty),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF4CAF50) : Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
                          ),
                          child: Text(
                            qty.toString(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? Colors.white : const Color(0xFF4CAF50),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  SizedBox(height: isWide ? 32 : 24),
                  const Text("Enter Quantity", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.confirmation_number, color: Color(0xFF4CAF50)),
                      hintText: "1",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    ),
                  ),

                  SizedBox(height: isWide ? 48 : 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _generateTokens,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 24, color: Colors.white),
                      label: const Text("Generate Tokens", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 50),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor, {IconData? icon, bool isValue = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: textColor),
          const SizedBox(height: 8),
          if (isValue)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text("PKR ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: textColor)),
                Text(value, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w500, color: textColor)),
              ],
            )
          else
            Text(value, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w500, color: textColor)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.8), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}