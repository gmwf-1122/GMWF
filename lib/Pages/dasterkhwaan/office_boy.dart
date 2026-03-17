// lib/pages/dasterkhwaan/office_boy_updated.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../donations/donations_screen.dart';

class DasterkhwaanOfficeBoy extends StatefulWidget {
  static const String routeName = '/dasterkhwaan-office-boy';
  const DasterkhwaanOfficeBoy({super.key});

  @override
  State<DasterkhwaanOfficeBoy> createState() => _DasterkhwaanOfficeBoyState();
}

class _DasterkhwaanOfficeBoyState extends State<DasterkhwaanOfficeBoy>
    with TickerProviderStateMixin {
  int _currentNav = 0;
  String userName = "User";
  String? _branchId;

  final TextEditingController _quantityController =
      TextEditingController(text: "1");
  final double pricePerToken = 10.0;

  late AnimationController _heroFadeCtrl;
  late Animation<double> _heroFade;
  late AnimationController _fabPulse;
  late Animation<double> _fabPulseAnim;

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final DateFormat _displayFormat = DateFormat('EEE, dd MMM yyyy');
  late final String today = _dateFormat.format(DateTime.now());

  static const Color _teal = Color(0xFF00A896);
  static const Color _tealDark = Color(0xFF007A6E);
  static const Color _tealDeep = Color(0xFF005A52);
  static const Color _tealLight = Color(0xFFE0F7F5);
  static const Color _accent = Color(0xFFFFB300);
  static const Color _bg = Color(0xFFF0F4F3);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _textDark = Color(0xFF0D1F1E);
  static const Color _textMid = Color(0xFF3D5754);
  static const Color _textLight = Color(0xFF7FA09B);
  static const Color _divider = Color(0xFFDEECEA);

  @override
  void initState() {
    super.initState();

    _heroFadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _heroFade = CurvedAnimation(parent: _heroFadeCtrl, curve: Curves.easeOut);
    _heroFadeCtrl.forward();

    _fabPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _fabPulseAnim = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _fabPulse, curve: Curves.easeInOut),
    );
    _fabPulse.repeat(reverse: true);

    _loadUserAndBranch();
  }

  @override
  void dispose() {
    _heroFadeCtrl.dispose();
    _fabPulse.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final branchesSnap =
          await FirebaseFirestore.instance.collection("branches").get();
      for (final branch in branchesSnap.docs) {
        final userDoc =
            await branch.reference.collection("users").doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          setState(() {
            userName = data['username'] ??
                user.email?.split('@').first ??
                "Office Boy";
            _branchId = branch.id;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading user/branch: $e");
    }
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
    if (_branchId == null) return {'total': 0, 'served': 0};
    final snapshot = await _dayDoc.get();
    final data = snapshot.data() as Map<String, dynamic>? ?? {};
    return {
      'total': data['totalTokens'] as int? ?? 0,
      'served': data['servedTokens'] as int? ?? 0,
    };
  }

  Future<Map<String, dynamic>> _getDonationStats() async {
    if (_branchId == null) {
      return {'pending': 0, 'approved': 0, 'total_amount': 0};
    }

    try {
      final pendingSnap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId)
          .collection('donations')
          .where('status', isEqualTo: 'pending')
          .get();

      final approvedSnap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId)
          .collection('donations')
          .where('status', isEqualTo: 'approved')
          .get();

      double totalAmount = 0;
      for (var doc in approvedSnap.docs) {
        final data = doc.data();
        totalAmount += (data['amount'] as num?)?.toDouble() ?? 0;
      }

      return {
        'pending': pendingSnap.docs.length,
        'approved': approvedSnap.docs.length,
        'total_amount': totalAmount,
      };
    } catch (e) {
      debugPrint("Error getting donation stats: $e");
      return {'pending': 0, 'approved': 0, 'total_amount': 0};
    }
  }

  Future<void> _generateTokens() async {
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
    if (quantity <= 0) {
      _showSnack("Enter a valid quantity", isError: true);
      return;
    }
    if (_branchId == null) {
      _showSnack("Branch not found!", isError: true);
      return;
    }

    HapticFeedback.mediumImpact();

    final tokensRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(today)
        .collection('tokens');
    final dayRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(today);

    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await tokensRef.get();
    final start = snapshot.size + 1;

    for (int i = 0; i < quantity; i++) {
      batch.set(tokensRef.doc(), {
        'number': start + i,
        'time': FieldValue.serverTimestamp(),
        'served': false,
      });
    }
    batch.set(
        dayRef,
        {'totalTokens': FieldValue.increment(quantity)},
        SetOptions(merge: true));
    await batch.commit();

    if (!mounted) return;
    _showSnack(
        "$quantity Token${quantity > 1 ? 's' : ''} Issued · PKR ${(quantity * pricePerToken).toStringAsFixed(0)}");
    _quantityController.text = "1";
    setState(() {});
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isError ? Icons.close_rounded : Icons.check_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(msg,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.white)),
        ),
      ]),
      backgroundColor: isError ? const Color(0xFFD32F2F) : _teal,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _currentNav,
        children: [
          _HomeScreen(
            userName: userName,
            branchId: _branchId,
            today: today,
            displayFmt: _displayFormat,
            getTodayStats: _getTodayStats,
            getDonationStats: _getDonationStats,
            onGoTokens: () => setState(() => _currentNav = 1),
            onGoDonations: () => setState(() => _currentNav = 2),
            onLogout: _logout,
            teal: _teal,
            tealDark: _tealDark,
            tealDeep: _tealDeep,
            tealLight: _tealLight,
            accent: _accent,
            bg: _bg,
            surface: _surface,
            textDark: _textDark,
            textMid: _textMid,
            textLight: _textLight,
            heroFade: _heroFade,
          ),
          _TokensScreen(
            userName: userName,
            branchId: _branchId,
            today: today,
            displayFormat: _displayFormat,
            quantityController: _quantityController,
            pricePerToken: pricePerToken,
            onGenerate: _generateTokens,
            fabPulseAnim: _fabPulseAnim,
            getTodayStats: _getTodayStats,
            onLogout: _logout,
            teal: _teal,
            tealDark: _tealDark,
            tealDeep: _tealDeep,
            tealLight: _tealLight,
            accent: _accent,
            bg: _bg,
            surface: _surface,
            textDark: _textDark,
            textMid: _textMid,
            textLight: _textLight,
            onSelectQty: (qty) {
              _quantityController.text = qty.toString();
              setState(() {});
            },
          ),
          _branchId == null
              ? const Center(
                  child:
                      CircularProgressIndicator(color: _teal, strokeWidth: 2))
              : DonationsScreen.embedded(
                  branchId: _branchId!,
                  username: userName,
                  branchName: '',
                  role: UserRole.officeBoy,                  // ✅ fixed
                  userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    }
  }

  Widget _buildBottomNav() {
    final labels = ["Home", "Tokens", "Donations"];
    final icons = [
      Icons.home_rounded,
      Icons.confirmation_number_rounded,
      Icons.volunteer_activism_rounded,
    ];

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (idx) {
              final sel = _currentNav == idx;
              return GestureDetector(
                onTap: () => setState(() => _currentNav = idx),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? _teal : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icons[idx],
                          size: 22, color: sel ? Colors.white : _textLight),
                      if (sel) ...[
                        const SizedBox(width: 7),
                        Text(labels[idx],
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  final String userName;
  final String? branchId;
  final String today;
  final DateFormat displayFmt;
  final Future<Map<String, int>> Function() getTodayStats;
  final Future<Map<String, dynamic>> Function() getDonationStats;
  final VoidCallback onGoTokens;
  final VoidCallback onGoDonations;
  final VoidCallback onLogout;
  final Color teal, tealDark, tealDeep, tealLight, accent, bg, surface;
  final Color textDark, textMid, textLight;
  final Animation<double> heroFade;

  const _HomeScreen({
    required this.userName,
    required this.branchId,
    required this.today,
    required this.displayFmt,
    required this.getTodayStats,
    required this.getDonationStats,
    required this.onGoTokens,
    required this.onGoDonations,
    required this.onLogout,
    required this.teal,
    required this.tealDark,
    required this.tealDeep,
    required this.tealLight,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.textDark,
    required this.textMid,
    required this.textLight,
    required this.heroFade,
  });

  @override
  Widget build(BuildContext context) {
    final greeting = _greeting();
    return FadeTransition(
      opacity: heroFade,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tealDeep, tealDark, teal],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    Positioned(
                      top: -40,
                      right: -40,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 60,
                      right: 40,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.04),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.20)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.asset(
                                        "assets/logo/gmwf.png",
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                                Icons.restaurant_rounded,
                                                color: Colors.white70,
                                                size: 20),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text("Dasterkhwaan",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2)),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: onLogout,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFEF4444)
                                            .withOpacity(0.40),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.logout_rounded,
                                          color: Colors.white, size: 16),
                                      SizedBox(width: 6),
                                      Text("Logout",
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          Text(greeting,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.65),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          Text(userName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6)),
                          const SizedBox(height: 6),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.20),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.badge_rounded,
                                      color: accent, size: 12),
                                  const SizedBox(width: 5),
                                  Text("Office Boy",
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                                DateFormat('EEE, dd MMM')
                                    .format(DateTime.now()),
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.50),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Quick Actions",
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  Text("Tap a card to get started",
                      style: TextStyle(fontSize: 12, color: textLight)),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.confirmation_number_rounded,
                        iconBg: teal.withOpacity(0.12),
                        iconColor: teal,
                        title: "Issue Tokens",
                        subtitle: "Generate meal tokens",
                        urdu: "کھانے کا ٹوکن",
                        gradientColors: [teal, tealDark],
                        onTap: onGoTokens,
                        surface: surface,
                        textDark: textDark,
                        textLight: textLight,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.volunteer_activism_rounded,
                        iconBg: const Color(0xFFF3E5F5),
                        iconColor: const Color(0xFF8E24AA),
                        title: "Donations",
                        subtitle: "Record contributions",
                        urdu: "عطیات",
                        gradientColors: [
                          const Color(0xFF8E24AA),
                          const Color(0xFF6A1B9A),
                        ],
                        onTap: onGoDonations,
                        surface: surface,
                        textDark: textDark,
                        textLight: textLight,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Today's Overview",
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 14),
                  FutureBuilder<Map<String, int>>(
                    future: getTodayStats(),
                    builder: (context, snap) {
                      final total = snap.data?['total'] ?? 0;
                      final served = snap.data?['served'] ?? 0;
                      return _TokensSummaryCard(
                        total: total,
                        served: served,
                        teal: teal,
                        surface: surface,
                        textDark: textDark,
                        textMid: textMid,
                        textLight: textLight,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Donations Overview",
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 14),
                  FutureBuilder<Map<String, dynamic>>(
                    future: getDonationStats(),
                    builder: (context, snap) {
                      final pending = snap.data?['pending'] ?? 0;
                      final approved = snap.data?['approved'] ?? 0;
                      final totalAmount =
                          (snap.data?['total_amount'] ?? 0).toDouble();
                      return _DonationsSummaryCard(
                        pending: pending,
                        approved: approved,
                        totalAmount: totalAmount,
                        surface: surface,
                        textDark: textDark,
                        textMid: textMid,
                        textLight: textLight,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return "Good morning,";
    if (h < 17) return "Good afternoon,";
    return "Good evening,";
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title, subtitle, urdu;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final Color surface, textDark, textLight;

  const _ActionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.urdu,
    required this.gradientColors,
    required this.onTap,
    required this.surface,
    required this.textDark,
    required this.textLight,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: iconColor.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: iconBg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    letterSpacing: -0.2)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(fontSize: 11, color: textLight)),
            const SizedBox(height: 8),
            Text(urdu,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: iconColor.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}

class _TokensSummaryCard extends StatelessWidget {
  final int total, served;
  final Color teal, surface, textDark, textMid, textLight;

  const _TokensSummaryCard({
    required this.total,
    required this.served,
    required this.teal,
    required this.surface,
    required this.textDark,
    required this.textMid,
    required this.textLight,
  });

  @override
  Widget build(BuildContext context) {
    final revenue = total * 10;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: teal.withOpacity(0.12),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [teal.withOpacity(0.08), teal.withOpacity(0.03)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: teal.withOpacity(0.12))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: teal.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.confirmation_number_rounded,
                        color: teal, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Token Summary",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                            letterSpacing: -0.3)),
                    Text("PKR 10 per token",
                        style: TextStyle(
                            fontSize: 12,
                            color: teal,
                            fontWeight: FontWeight.w600)),
                  ]),
                ]),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: teal,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: teal.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("₨$revenue",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                      Text("Revenue",
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Expanded(
                  child: _BigStatTile(
                icon: Icons.confirmation_number_rounded,
                label: "Total Issued",
                value: "$total",
                color: teal,
                bgColor: teal.withOpacity(0.08),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: _BigStatTile(
                icon: Icons.check_circle_rounded,
                label: "Served",
                value: "$served",
                color: const Color(0xFF00897B),
                bgColor: const Color(0xFF00897B).withOpacity(0.08),
              )),
            ]),
          ),
        ],
      ),
    );
  }
}

class _DonationsSummaryCard extends StatelessWidget {
  final int pending, approved;
  final double totalAmount;
  final Color surface, textDark, textMid, textLight;

  const _DonationsSummaryCard({
    required this.pending,
    required this.approved,
    required this.totalAmount,
    required this.surface,
    required this.textDark,
    required this.textMid,
    required this.textLight,
  });

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF8E24AA);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: purple.withOpacity(0.12),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [purple.withOpacity(0.08), purple.withOpacity(0.03)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border:
                  Border(bottom: BorderSide(color: purple.withOpacity(0.12))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: purple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.volunteer_activism_rounded,
                        color: purple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Donations",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                            letterSpacing: -0.3)),
                    Text("All contributions",
                        style: const TextStyle(
                            fontSize: 12,
                            color: purple,
                            fontWeight: FontWeight.w600)),
                  ]),
                ]),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: purple,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: purple.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("₨${totalAmount.toStringAsFixed(0)}",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                      Text("Total",
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Expanded(
                  child: _BigStatTile(
                icon: Icons.pending_rounded,
                label: "Pending",
                value: "$pending",
                color: const Color(0xFFF39C12),
                bgColor: const Color(0xFFF39C12).withOpacity(0.08),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: _BigStatTile(
                icon: Icons.check_circle_rounded,
                label: "Approved",
                value: "$approved",
                color: const Color(0xFF27AE60),
                bgColor: const Color(0xFF27AE60).withOpacity(0.08),
              )),
            ]),
          ),
        ],
      ),
    );
  }
}

class _BigStatTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color, bgColor;

  const _BigStatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, color: color, height: 1.0)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color.withOpacity(0.65))),
      ]),
    );
  }
}

class _TokensScreen extends StatelessWidget {
  final String userName;
  final String? branchId;
  final String today;
  final DateFormat displayFormat;
  final TextEditingController quantityController;
  final double pricePerToken;
  final VoidCallback onGenerate;
  final Animation<double> fabPulseAnim;
  final Future<Map<String, int>> Function() getTodayStats;
  final void Function(int) onSelectQty;
  final VoidCallback onLogout;
  final Color teal, tealDark, tealDeep, tealLight, accent, bg, surface;
  final Color textDark, textMid, textLight;

  const _TokensScreen({
    required this.userName,
    required this.branchId,
    required this.today,
    required this.displayFormat,
    required this.quantityController,
    required this.pricePerToken,
    required this.onGenerate,
    required this.fabPulseAnim,
    required this.getTodayStats,
    required this.onSelectQty,
    required this.onLogout,
    required this.teal,
    required this.tealDark,
    required this.tealDeep,
    required this.tealLight,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.textDark,
    required this.textMid,
    required this.textLight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tealDeep, tealDark, teal],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Issue Tokens",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4)),
                          const SizedBox(height: 2),
                          Text("PKR ${pricePerToken.toInt()} per token",
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                      GestureDetector(
                        onTap: onLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.logout_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text("Logout",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FutureBuilder<Map<String, int>>(
                    future: getTodayStats(),
                    builder: (ctx, snap) {
                      final total = snap.data?['total'] ?? 0;
                      final served = snap.data?['served'] ?? 0;
                      final pending = total - served;
                      final totalAmount = total * 10;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.14)),
                        ),
                        child: Row(
                          children: [
                            _sStat("Total", "$total",
                                Icons.confirmation_number_rounded,
                                const Color(0xFF80DEEA)),
                            Container(
                              width: 1,
                              height: 36,
                              color: Colors.white.withOpacity(0.14),
                            ),
                            _sStat("Pending", "$pending",
                                Icons.hourglass_empty_rounded,
                                const Color(0xFFFFB74D)),
                            Container(
                              width: 1,
                              height: 36,
                              color: Colors.white.withOpacity(0.14),
                            ),
                            _sStat("Served", "$served",
                                Icons.check_circle_rounded,
                                const Color(0xFFA5D6A7)),
                            Container(
                              width: 1,
                              height: 36,
                              color: Colors.white.withOpacity(0.14),
                            ),
                            _sStat("Amount", "₨$totalAmount",
                                Icons.currency_rupee_rounded,
                                const Color(0xFFFFD54F)),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: tealLight,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: teal.withOpacity(0.20)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 11, color: teal),
                        const SizedBox(width: 6),
                        Text(
                          displayFormat.format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text("QUICK SELECT",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: textLight,
                        letterSpacing: 1.3)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [1, 2, 3, 4, 5].map((qty) {
                    return _QuickChipEP(
                      qty: qty,
                      selected: quantityController.text == qty.toString(),
                      onTap: () => onSelectQty(qty),
                      teal: teal,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                Text("CUSTOM QUANTITY",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: textLight,
                        letterSpacing: 1.3)),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: teal.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textDark),
                    decoration: InputDecoration(
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: teal.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.confirmation_number_outlined,
                              color: teal, size: 18),
                        ),
                      ),
                      suffixText: () {
                        final n = int.tryParse(quantityController.text);
                        if (n == null || n <= 0) return null;
                        return "= PKR ${(n * pricePerToken).toStringAsFixed(0)}";
                      }(),
                      suffixStyle: TextStyle(
                          color: teal,
                          fontWeight: FontWeight.w800,
                          fontSize: 13),
                      hintText: "Enter quantity…",
                      hintStyle: TextStyle(
                          color: textLight,
                          fontWeight: FontWeight.normal,
                          fontSize: 14),
                      filled: true,
                      fillColor: surface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: teal, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _IssueButtonEP(
                  quantityController: quantityController,
                  pricePerToken: pricePerToken,
                  teal: teal,
                  fabPulseAnim: fabPulseAnim,
                  onPressed: onGenerate,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sStat(String label, String val, IconData icon, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(
            val,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChipEP extends StatelessWidget {
  final int qty;
  final bool selected;
  final VoidCallback onTap;
  final Color teal;

  const _QuickChipEP({
    required this.qty,
    required this.selected,
    required this.onTap,
    required this.teal,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 58,
        height: 64,
        decoration: BoxDecoration(
          color: selected ? teal : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? teal : const Color(0xFFDEECEA), width: 1.5),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: teal.withOpacity(0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Center(
          child: Text("$qty",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : const Color(0xFF3D5754))),
        ),
      ),
    );
  }
}

class _IssueButtonEP extends StatelessWidget {
  final TextEditingController quantityController;
  final double pricePerToken;
  final Color teal;
  final Animation<double> fabPulseAnim;
  final VoidCallback onPressed;

  const _IssueButtonEP({
    required this.quantityController,
    required this.pricePerToken,
    required this.teal,
    required this.fabPulseAnim,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final qty = int.tryParse(quantityController.text) ?? 0;
    final total = (qty * pricePerToken).toStringAsFixed(0);

    return ScaleTransition(
      scale: fabPulseAnim,
      child: Container(
        width: double.infinity,
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [teal, Color.lerp(teal, Colors.black, 0.15)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: teal.withOpacity(0.38),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPressed,
            splashColor: Colors.white.withOpacity(0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_rounded,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Issue ${quantityController.text.isEmpty ? '0' : quantityController.text} "
                        "Token${qty != 1 ? 's' : ''}",
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.2),
                      ),
                      if (qty > 0)
                        Text("Total · PKR $total",
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.65))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}