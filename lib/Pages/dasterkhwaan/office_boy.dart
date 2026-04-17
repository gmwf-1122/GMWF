// lib/pages/dasterkhwaan/office_boy.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/gmwf_loading_view.dart';
import '../donations/donations_screen.dart';

class DasterkhwaanOfficeBoy extends StatefulWidget {
  static const String routeName = '/dasterkhwaan-office-boy';
  final String? branchId;
  final String? userName;

  const DasterkhwaanOfficeBoy({
    super.key,
    this.branchId,
    this.userName,
  });

  @override
  State<DasterkhwaanOfficeBoy> createState() => _DasterkhwaanOfficeBoyState();
}

class _DasterkhwaanOfficeBoyState extends State<DasterkhwaanOfficeBoy>
    with TickerProviderStateMixin {
  int _currentNav = 0;
  String _userName  = 'User';
  String? _branchId;

  final _qtyCtrl       = TextEditingController(text: '1');
  final double _pricePerToken = 10.0;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  final DateFormat _dateFmt    = DateFormat('yyyy-MM-dd');
  final DateFormat _displayFmt = DateFormat('EEE, dd MMM yyyy');
  late final String today = _dateFmt.format(DateTime.now());

  // ── Palette ────────────────────────────────────────────────────────────────
  static const Color _teal      = Color(0xFF00A896);
  static const Color _tealDark  = Color(0xFF007A6E);
  static const Color _tealDeep  = Color(0xFF005A52);
  static const Color _tealLight = Color(0xFFE0F7F5);
  static const Color _accent    = Color(0xFFFFB300);
  static const Color _bg        = Color(0xFFF0F4F3);
  static const Color _surface   = Color(0xFFFFFFFF);
  static const Color _textDark  = Color(0xFF0D1F1E);
  static const Color _textMid   = Color(0xFF3D5754);
  static const Color _textLight = Color(0xFF7FA09B);

  @override
  void initState() {
    super.initState();
    _fadeCtrl  = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _pulseCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1500));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.04).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _pulseCtrl.repeat(reverse: true);

    if (widget.branchId != null) {
      _branchId = widget.branchId;
      _userName = widget.userName ?? 'Office Boy';
    } else {
      _loadUserAndBranch();
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadUserAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final branches =
          await FirebaseFirestore.instance.collection('branches').get();
      for (final branch in branches.docs) {
        final userDoc =
            await branch.reference.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          setState(() {
            _userName  = data['username'] ??
                user.email?.split('@').first ?? 'Office Boy';
            _branchId  = branch.id;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading user/branch: $e');
    }
  }

  DocumentReference get _dayDoc {
    if (_branchId == null) throw Exception('Branch not found');
    return FirebaseFirestore.instance
        .collection('branches').doc(_branchId)
        .collection('dasterkhwaan').doc(today);
  }

  Future<Map<String, int>> _getTodayStats() async {
    if (_branchId == null) return {'total': 0, 'served': 0};
    final snap = await _dayDoc.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    return {
      'total':  data['totalTokens']  as int? ?? 0,
      'served': data['servedTokens'] as int? ?? 0,
    };
  }

  Future<Map<String, dynamic>> _getDonationStats() async {
    if (_branchId == null) {
      return {'pending': 0, 'approved': 0, 'total_amount': 0.0};
    }
    try {
      final pendingSnap = await FirebaseFirestore.instance
          .collection('branches').doc(_branchId)
          .collection('donations')
          .where('status', isEqualTo: 'pending').get();
      final approvedSnap = await FirebaseFirestore.instance
          .collection('branches').doc(_branchId)
          .collection('donations')
          .where('status', isEqualTo: 'approved').get();
      double total = 0;
      for (final d in approvedSnap.docs) {
        total += ((d.data())['amount'] as num? ?? 0).toDouble();
      }
      return {
        'pending': pendingSnap.docs.length,
        'approved': approvedSnap.docs.length,
        'total_amount': total,
      };
    } catch (e) {
      debugPrint('Donation stats error: $e');
      return {'pending': 0, 'approved': 0, 'total_amount': 0.0};
    }
  }

  Future<void> _generateTokens() async {
    final quantity = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (quantity <= 0) {
      _showSnack('Enter a valid quantity', isError: true);
      return;
    }
    if (_branchId == null) {
      _showSnack('Branch not found!', isError: true);
      return;
    }
    HapticFeedback.mediumImpact();

    final tokensRef = FirebaseFirestore.instance
        .collection('branches').doc(_branchId)
        .collection('dasterkhwaan').doc(today)
        .collection('tokens');
    final dayRef = FirebaseFirestore.instance
        .collection('branches').doc(_branchId)
        .collection('dasterkhwaan').doc(today);

    final batch = FirebaseFirestore.instance.batch();
    final snap  = await tokensRef.get();
    final start = snap.size + 1;

    for (int i = 0; i < quantity; i++) {
      batch.set(tokensRef.doc(), {
        'number': start + i,
        'time': FieldValue.serverTimestamp(),
        'served': false,
      });
    }
    batch.set(dayRef,
        {'totalTokens': FieldValue.increment(quantity)},
        SetOptions(merge: true));
    await batch.commit();

    if (!mounted) return;
    _showSnack(
        '$quantity Token${quantity > 1 ? 's' : ''} Issued · PKR ${(quantity * _pricePerToken).toStringAsFixed(0)}');
    _qtyCtrl.text = '1';
    setState(() {});
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
          child: Icon(
            isError ? Icons.close_rounded : Icons.check_rounded,
            color: Colors.white, size: 15,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(msg,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white))),
      ]),
      backgroundColor: isError ? const Color(0xFFD32F2F) : _teal,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _currentNav,
        children: [
          // 0 – Home dashboard
          _HomeScreen(
            userName: _userName,
            branchId: _branchId,
            today: today,
            getTodayStats: _getTodayStats,
            getDonationStats: _getDonationStats,
            onGoTokens: () => setState(() => _currentNav = 1),
            onGoDonations: () => setState(() => _currentNav = 2),
            onGoHistory: () => setState(() => _currentNav = 3),
            onLogout: _logout,
            heroFade: _fadeAnim,
          ),
          // 1 – Token issuing
          _TokensScreen(
            userName: _userName,
            branchId: _branchId,
            today: today,
            displayFormat: _displayFmt,
            quantityController: _qtyCtrl,
            pricePerToken: _pricePerToken,
            onGenerate: _generateTokens,
            pulseAnim: _pulseAnim,
            getTodayStats: _getTodayStats,
            onLogout: _logout,
            onSelectQty: (qty) {
              _qtyCtrl.text = qty.toString();
              setState(() {});
            },
          ),
          // 2 – Donations
          _branchId == null
              ? const GmwfLoadingView()
              : DonationsScreen.embedded(
                  branchId: _branchId!,
                  username: _userName,
                  branchName: '',
                  role: UserRole.officeBoy,
                  userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                ),
          // 3 – History
          _branchId == null
              ? const GmwfLoadingView()
              : _HistoryScreen(
                  branchId: _branchId!,
                  dateFmt: _dateFmt,
                  onLogout: _logout,
                  pricePerToken: _pricePerToken,
                ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const CircularProgressIndicator(
                color: _teal,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Loading Office Boy Panel…',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Fetching branch data',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    const labels = ['Home', 'Tokens', 'Donations', 'History'];
    const icons  = [
      Icons.home_rounded,
      Icons.confirmation_number_rounded,
      Icons.volunteer_activism_rounded,
      Icons.history_rounded,
    ];

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.10),
              blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(4, (idx) {
              final sel = _currentNav == idx;
              return GestureDetector(
                onTap: () => setState(() => _currentNav = idx),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? _teal : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icons[idx], size: 22,
                        color: sel ? Colors.white : _textLight),
                    if (sel) ...[
                      const SizedBox(width: 7),
                      Text(labels[idx],
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ],
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HOME SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class _HomeScreen extends StatelessWidget {
  final String userName;
  final String? branchId;
  final String today;
  final Future<Map<String, int>> Function() getTodayStats;
  final Future<Map<String, dynamic>> Function() getDonationStats;
  final VoidCallback onGoTokens, onGoDonations, onGoHistory, onLogout;
  final Animation<double> heroFade;

  static const Color _teal      = Color(0xFF00A896);
  static const Color _tealDark  = Color(0xFF007A6E);
  static const Color _tealDeep  = Color(0xFF005A52);
  static const Color _accent    = Color(0xFFFFB300);
  static const Color _textDark  = Color(0xFF0D1F1E);
  static const Color _textLight = Color(0xFF7FA09B);
  static const Color _surface   = Color(0xFFFFFFFF);

  const _HomeScreen({
    required this.userName,
    required this.branchId,
    required this.today,
    required this.getTodayStats,
    required this.getDonationStats,
    required this.onGoTokens,
    required this.onGoDonations,
    required this.onGoHistory,
    required this.onLogout,
    required this.heroFade,
  });

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: heroFade,
      child: CustomScrollView(slivers: [
        // ── Hero header
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_tealDeep, _tealDark, _teal],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Stack(children: [
                Positioned(top: -40, right: -40,
                  child: Container(width: 200, height: 200,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      // Logo pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.20)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset('assets/logo/gmwf.png',
                                width: 22, height: 22, fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.restaurant_rounded,
                                    color: Colors.white70, size: 18)),
                          ),
                          const SizedBox(width: 8),
                          const Text('Dasterkhwaan',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      // Logout
                      GestureDetector(
                        onTap: onLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('Logout', style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800,
                                fontSize: 13)),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 28),
                    Text(_greeting(),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(userName,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 28,
                            fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.badge_rounded, color: _accent, size: 12),
                          const SizedBox(width: 5),
                          Text('Office Boy',
                              style: TextStyle(
                                  color: _accent, fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Text(DateFormat('EEE, dd MMM').format(DateTime.now()),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.50),
                              fontSize: 11, fontWeight: FontWeight.w500)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),

        // ── Quick actions
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionTitle('Quick Actions', 'Tap a card to get started'),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.confirmation_number_rounded,
                    iconColor: _teal,
                    iconBg: _teal.withOpacity(0.12),
                    title: 'Issue Tokens',
                    subtitle: 'Generate meal tokens',
                    urdu: 'کھانے کا ٹوکن',
                    onTap: onGoTokens,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.volunteer_activism_rounded,
                    iconColor: const Color(0xFF8E24AA),
                    iconBg: const Color(0xFFF3E5F5),
                    title: 'Donations',
                    subtitle: 'Record contributions',
                    urdu: 'عطیات',
                    onTap: onGoDonations,
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              _ActionCardWide(
                icon: Icons.history_rounded,
                iconColor: const Color(0xFF7C3AED),
                iconBg: const Color(0xFFEDE9FE),
                title: 'Daily History',
                subtitle: 'View tokens & donations by date',
                urdu: 'روزانہ کا ریکارڈ',
                onTap: onGoHistory,
              ),
            ]),
          ),
        ),

        // ── Today's token overview
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionTitle("Today's Tokens", null),
              const SizedBox(height: 14),
              FutureBuilder<Map<String, int>>(
                future: getTodayStats(),
                builder: (_, snap) {
                  final total  = snap.data?['total']  ?? 0;
                  final served = snap.data?['served'] ?? 0;
                  return _TokenSummaryCard(
                    total: total, served: served, teal: _teal, surface: _surface,
                    textDark: _textDark, textLight: _textLight,
                    pricePerToken: 10,
                  );
                },
              ),
            ]),
          ),
        ),

        // ── Donations overview
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionTitle('Donations Overview', null),
              const SizedBox(height: 14),
              FutureBuilder<Map<String, dynamic>>(
                future: getDonationStats(),
                builder: (_, snap) {
                  final pending     = snap.data?['pending']      ?? 0;
                  final approved    = snap.data?['approved']     ?? 0;
                  final totalAmount = (snap.data?['total_amount'] ?? 0).toDouble();
                  return _DonationSummaryCard(
                    pending: pending, approved: approved, totalAmount: totalAmount,
                    surface: _surface, textDark: _textDark, textLight: _textLight,
                  );
                },
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String title, String? subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w900,
              color: _textDark, letterSpacing: -0.3)),
      if (subtitle != null) ...[
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(fontSize: 12, color: _textLight)),
      ],
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ACTION CARDS
// ═══════════════════════════════════════════════════════════════════════════

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String title, subtitle, urdu;
  final VoidCallback onTap;

  static const Color _textDark  = Color(0xFF0D1F1E);
  static const Color _textLight = Color(0xFF7FA09B);

  const _ActionCard({
    required this.icon, required this.iconColor, required this.iconBg,
    required this.title, required this.subtitle, required this.urdu,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: iconColor.withOpacity(0.12),
                blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: _textDark)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: _textLight)),
          const SizedBox(height: 8),
          Text(urdu,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: iconColor.withOpacity(0.7))),
        ]),
      ),
    );
  }
}

class _ActionCardWide extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String title, subtitle, urdu;
  final VoidCallback onTap;

  static const Color _textDark  = Color(0xFF0D1F1E);
  static const Color _textLight = Color(0xFF7FA09B);

  const _ActionCardWide({
    required this.icon, required this.iconColor, required this.iconBg,
    required this.title, required this.subtitle, required this.urdu,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: iconColor.withOpacity(0.12),
                blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: _textDark)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: _textLight)),
              const SizedBox(height: 6),
              Text(urdu,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: iconColor.withOpacity(0.7))),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded, color: _textLight, size: 16),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUMMARY CARDS
// ═══════════════════════════════════════════════════════════════════════════

class _TokenSummaryCard extends StatelessWidget {
  final int total, served, pricePerToken;
  final Color teal, surface, textDark, textLight;

  const _TokenSummaryCard({
    required this.total, required this.served, required this.teal,
    required this.surface, required this.textDark, required this.textLight,
    required this.pricePerToken,
  });

  @override
  Widget build(BuildContext context) {
    final revenue = total * pricePerToken;
    return Container(
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: teal.withOpacity(0.12),
              blurRadius: 28, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [teal.withOpacity(0.08), teal.withOpacity(0.02)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(bottom: BorderSide(color: teal.withOpacity(0.1))),
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
                  child: Icon(Icons.confirmation_number_rounded, color: teal, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Token Summary',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900, color: textDark)),
                  Text('PKR $pricePerToken per token',
                      style: TextStyle(
                          fontSize: 12, color: teal, fontWeight: FontWeight.w600)),
                ]),
              ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: teal, borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: teal.withOpacity(0.35),
                        blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('PKR $revenue',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  Text('Revenue',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 9, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: _StatTile(
              icon: Icons.confirmation_number_rounded,
              label: 'Total Issued', value: '$total',
              color: teal, bgColor: teal.withOpacity(0.08),
            )),
            const SizedBox(width: 10),
            Expanded(child: _StatTile(
              icon: Icons.check_circle_rounded,
              label: 'Served', value: '$served',
              color: const Color(0xFF00897B),
              bgColor: const Color(0xFF00897B).withOpacity(0.08),
            )),
            const SizedBox(width: 10),
            Expanded(child: _StatTile(
              icon: Icons.hourglass_top_rounded,
              label: 'Pending', value: '${total - served}',
              color: const Color(0xFFF59E0B),
              bgColor: const Color(0xFFF59E0B).withOpacity(0.08),
            )),
          ]),
        ),
      ]),
    );
  }
}

class _DonationSummaryCard extends StatelessWidget {
  final int pending, approved;
  final double totalAmount;
  final Color surface, textDark, textLight;

  const _DonationSummaryCard({
    required this.pending, required this.approved, required this.totalAmount,
    required this.surface, required this.textDark, required this.textLight,
  });

  static const Color _purple = Color(0xFF8E24AA);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: _purple.withOpacity(0.12),
              blurRadius: 28, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [_purple.withOpacity(0.08), _purple.withOpacity(0.02)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(bottom: BorderSide(color: _purple.withOpacity(0.1))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.volunteer_activism_rounded,
                      color: _purple, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Donations',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w900, color: textDark)),
                  const Text('All contributions',
                      style: TextStyle(
                          fontSize: 12, color: _purple, fontWeight: FontWeight.w600)),
                ]),
              ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _purple, borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: _purple.withOpacity(0.35),
                        blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('PKR ${totalAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  Text('Total',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 9, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: _StatTile(
              icon: Icons.pending_rounded, label: 'Pending',
              value: '$pending',
              color: const Color(0xFFF59E0B),
              bgColor: const Color(0xFFF59E0B).withOpacity(0.08),
            )),
            const SizedBox(width: 10),
            Expanded(child: _StatTile(
              icon: Icons.check_circle_rounded, label: 'Approved',
              value: '$approved',
              color: const Color(0xFF22C55E),
              bgColor: const Color(0xFF22C55E).withOpacity(0.08),
            )),
          ]),
        ),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color, bgColor;

  const _StatTile({
    required this.icon, required this.label, required this.value,
    required this.color, required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: color, height: 1.0)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: color.withOpacity(0.65))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TOKENS SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class _TokensScreen extends StatelessWidget {
  final String userName;
  final String? branchId, today;
  final DateFormat displayFormat;
  final TextEditingController quantityController;
  final double pricePerToken;
  final VoidCallback onGenerate, onLogout;
  final Animation<double> pulseAnim;
  final Future<Map<String, int>> Function() getTodayStats;
  final void Function(int) onSelectQty;

  static const Color _teal     = Color(0xFF00A896);
  static const Color _tealDark = Color(0xFF007A6E);
  static const Color _tealDeep = Color(0xFF005A52);
  static const Color _surface  = Color(0xFFFFFFFF);
  static const Color _textDark = Color(0xFF0D1F1E);
  static const Color _textLight = Color(0xFF7FA09B);

  const _TokensScreen({
    required this.userName, required this.branchId, required this.today,
    required this.displayFormat, required this.quantityController,
    required this.pricePerToken, required this.onGenerate,
    required this.pulseAnim, required this.getTodayStats,
    required this.onSelectQty, required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [_tealDeep, _tealDark, _teal],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Issue Tokens',
                      style: TextStyle(
                          color: Colors.white, fontSize: 22,
                          fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                  Text('PKR ${pricePerToken.toInt()} per token',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.55), fontSize: 12)),
                ]),
                GestureDetector(
                  onTap: onLogout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Logout', style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              FutureBuilder<Map<String, int>>(
                future: getTodayStats(),
                builder: (_, snap) {
                  final total  = snap.data?['total']  ?? 0;
                  final served = snap.data?['served'] ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Row(children: [
                      _sStat('Total', '$total',
                          Icons.confirmation_number_rounded, const Color(0xFF80DEEA)),
                      _vDiv(),
                      _sStat('Pending', '${total - served}',
                          Icons.hourglass_empty_rounded, const Color(0xFFFFB74D)),
                      _vDiv(),
                      _sStat('Served', '$served',
                          Icons.check_circle_rounded, const Color(0xFFA5D6A7)),
                      _vDiv(),
                      _sStat('Amount', 'PKR ${total * 10}',
                          Icons.account_balance_wallet_rounded, const Color(0xFFFFD54F)),
                    ]),
                  );
                },
              ),
            ]),
          ),
        ),
      ),
      // Body
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F7F5),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _teal.withOpacity(0.20)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.calendar_today_rounded, size: 11, color: _teal),
                  const SizedBox(width: 6),
                  Text(displayFormat.format(DateTime.now()),
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
                ]),
              ),
            ),
            const SizedBox(height: 28),
            const Text('QUICK SELECT',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: _textLight, letterSpacing: 1.3)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [1, 2, 3, 4, 5].map((qty) => _QuickChip(
                qty: qty,
                selected: quantityController.text == qty.toString(),
                onTap: () => onSelectQty(qty),
                teal: _teal,
              )).toList(),
            ),
            const SizedBox(height: 28),
            const Text('CUSTOM QUANTITY',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: _textLight, letterSpacing: 1.3)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _surface, borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: _teal.withOpacity(0.08),
                      blurRadius: 20, offset: const Offset(0, 6)),
                ],
              ),
              child: TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: _textDark),
                decoration: InputDecoration(
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _teal.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.confirmation_number_outlined,
                          color: _teal, size: 18),
                    ),
                  ),
                  suffixText: () {
                    final n = int.tryParse(quantityController.text);
                    if (n == null || n <= 0) return null;
                    return '= PKR ${(n * pricePerToken).toStringAsFixed(0)}';
                  }(),
                  suffixStyle: TextStyle(
                      color: _teal, fontWeight: FontWeight.w800, fontSize: 13),
                  hintText: 'Enter quantity…',
                  hintStyle: const TextStyle(color: _textLight, fontSize: 14),
                  filled: true,
                  fillColor: _surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: _teal, width: 2)),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _IssueButton(
              quantityController: quantityController,
              pricePerToken: pricePerToken,
              teal: _teal,
              pulseAnim: pulseAnim,
              onPressed: onGenerate,
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _sStat(String label, String val, IconData icon, Color color) =>
      Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(height: 5),
        Text(val,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 9, fontWeight: FontWeight.w700)),
      ]));

  Widget _vDiv() => Container(
      width: 1, height: 36, color: Colors.white.withOpacity(0.14));
}

class _QuickChip extends StatelessWidget {
  final int qty;
  final bool selected;
  final VoidCallback onTap;
  final Color teal;

  const _QuickChip({
    required this.qty, required this.selected,
    required this.onTap, required this.teal,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 58, height: 64,
        decoration: BoxDecoration(
          color: selected ? teal : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? teal : const Color(0xFFDEECEA), width: 1.5),
          boxShadow: selected
              ? [BoxShadow(color: teal.withOpacity(0.30),
                  blurRadius: 12, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withOpacity(0.05),
                  blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Center(
          child: Text('$qty',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : const Color(0xFF3D5754))),
        ),
      ),
    );
  }
}

class _IssueButton extends StatelessWidget {
  final TextEditingController quantityController;
  final double pricePerToken;
  final Color teal;
  final Animation<double> pulseAnim;
  final VoidCallback onPressed;

  const _IssueButton({
    required this.quantityController, required this.pricePerToken,
    required this.teal, required this.pulseAnim, required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final qty   = int.tryParse(quantityController.text) ?? 0;
    final total = (qty * pricePerToken).toStringAsFixed(0);
    return ScaleTransition(
      scale: pulseAnim,
      child: Container(
        width: double.infinity, height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [teal, Color.lerp(teal, Colors.black, 0.15)!],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: teal.withOpacity(0.38),
                blurRadius: 20, offset: const Offset(0, 8)),
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
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Column(mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Issue ${quantityController.text.isEmpty ? "0" : quantityController.text} '
                    'Token${qty != 1 ? "s" : ""}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: -0.2),
                  ),
                  if (qty > 0)
                    Text('Total · PKR $total',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.65))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryScreen extends StatefulWidget {
  final String branchId;
  final DateFormat dateFmt;
  final VoidCallback onLogout;
  final double pricePerToken;

  const _HistoryScreen({
    required this.branchId, required this.dateFmt,
    required this.onLogout, required this.pricePerToken,
  });

  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  DateTime _selectedDate = DateTime.now();

  static const Color _purple    = Color(0xFF7C3AED);
  static const Color _teal      = Color(0xFF00A896);

  Future<Map<String, dynamic>> _fetchDayData(String dateKey) async {
    final tokensSnap = await FirebaseFirestore.instance
        .collection('branches').doc(widget.branchId)
        .collection('dasterkhwaan').doc(dateKey)
        .collection('tokens').get();

    final donationsSnap = await FirebaseFirestore.instance
        .collection('branches').doc(widget.branchId)
        .collection('donations')
        .where('date', isEqualTo: dateKey)
        .get();

    // Fallback: filter by timestamp if 'date' field not available
    List<QueryDocumentSnapshot> donations = donationsSnap.docs;

    final totalTokens  = tokensSnap.docs.length;
    final servedTokens = tokensSnap.docs
        .where((d) => (d.data() as Map)['served'] == true).length;
    final totalRevenue = totalTokens * widget.pricePerToken;

    // Build token list (recent 20)
    final tokenList = tokensSnap.docs
        .map((d) {
          final data = d.data() as Map<String, dynamic>;
          return {
            'number':     data['number'] as int? ?? 0,
            'served':     data['served'] as bool? ?? false,
            'time':       (data['time'] as Timestamp?)?.toDate(),
            'servedTime': (data['servedTime'] as Timestamp?)?.toDate(),
          };
        })
        .toList()
      ..sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));

    // Build donation list
    final donationList = donations.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return {
        'donorName': data['donorName'] ?? data['name'] ?? 'Unknown',
        'amount':    (data['amount'] as num? ?? 0).toDouble(),
        'type':      data['type'] ?? 'cash',
        'status':    data['status'] ?? 'pending',
        'notes':     data['notes'] ?? '',
      };
    }).toList();

    double totalDonations = donationList.fold(0.0,
        (sum, d) => sum + (d['amount'] as double));

    return {
      'totalTokens':   totalTokens,
      'servedTokens':  servedTokens,
      'totalRevenue':  totalRevenue,
      'tokenList':     tokenList,
      'donationList':  donationList,
      'totalDonations': totalDonations,
    };
  }

  @override
  Widget build(BuildContext context) {
    final today      = widget.dateFmt.format(DateTime.now());
    final dateKey    = widget.dateFmt.format(_selectedDate);
    final isToday    = dateKey == today;
    final displayDate = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Column(children: [
      // Header
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF5B21B6), _purple],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Daily History',
                      style: TextStyle(color: Colors.white, fontSize: 24,
                          fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  Text('Tokens & Donations by date',
                      style: TextStyle(
                          color: Colors.white60, fontSize: 13)),
                ]),
                GestureDetector(
                  onTap: widget.onLogout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Logout', style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              // Date navigator
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(children: [
                  _dateNavBtn(Icons.chevron_left_rounded, () =>
                    setState(() => _selectedDate =
                        _selectedDate.subtract(const Duration(days: 1)))),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now(),
                          builder: (ctx, child) => Theme(
                            data: ThemeData.light().copyWith(
                              colorScheme: const ColorScheme.light(primary: _purple),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) setState(() => _selectedDate = picked);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                color: Colors.white, size: 15),
                            const SizedBox(width: 8),
                            Text(isToday ? 'Today · $displayDate' : displayDate,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w800,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _dateNavBtn(Icons.chevron_right_rounded,
                    isToday ? null : () =>
                      setState(() => _selectedDate =
                          _selectedDate.add(const Duration(days: 1)))),
                ]),
              ),
            ]),
          ),
        ),
      ),
      // Body
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          key: ValueKey(dateKey),
          future: _fetchDayData(dateKey),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: _purple, strokeWidth: 2));
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final d             = snap.data!;
            final totalTokens   = d['totalTokens']   as int;
            final servedTokens  = d['servedTokens']  as int;
            final totalRevenue  = d['totalRevenue']  as double;
            final tokenList     = d['tokenList']     as List<Map<String, dynamic>>;
            final donationList  = d['donationList']  as List<Map<String, dynamic>>;
            final totalDonations = d['totalDonations'] as double;

            if (totalTokens == 0 && donationList.isEmpty) {
              return Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.event_note_rounded,
                      size: 80, color: _purple.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text('No records for $displayDate',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: Color(0xFF94A3B8))),
                ]),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // ── Tokens summary card
                _sectionCard(
                  icon: Icons.confirmation_number_rounded,
                  color: _teal,
                  title: 'Token Summary',
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _histStat(
                          'Total', '$totalTokens',
                          Icons.confirmation_number_rounded, _teal)),
                      Expanded(child: _histStat(
                          'Served', '$servedTokens',
                          Icons.check_circle_rounded, const Color(0xFF22C55E))),
                      Expanded(child: _histStat(
                          'Pending', '${totalTokens - servedTokens}',
                          Icons.hourglass_top_rounded, const Color(0xFFF59E0B))),
                      Expanded(child: _histStat(
                          'Revenue', 'PKR ${totalRevenue.toStringAsFixed(0)}',
                          Icons.account_balance_wallet_rounded, const Color(0xFF8B5CF6))),
                    ]),
                    // Progress bar
                    const SizedBox(height: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Serving progress',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600,
                                  color: Color(0xFF94A3B8))),
                          Text(
                            totalTokens > 0
                                ? '${((servedTokens / totalTokens) * 100).toStringAsFixed(0)}%'
                                : '0%',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800,
                                color: _teal),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: totalTokens > 0
                              ? servedTokens / totalTokens
                              : 0,
                          minHeight: 8,
                          backgroundColor: _teal.withOpacity(0.1),
                          color: _teal,
                        ),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),

                // ── Token list (collapsed, last 10)
                if (tokenList.isNotEmpty)
                  _sectionCard(
                    icon: Icons.list_alt_rounded,
                    color: const Color(0xFF475569),
                    title: 'Tokens (${tokenList.length})',
                    child: Column(
                      children: tokenList.take(20).map((t) {
                        final served = t['served'] as bool;
                        final time   = t['time'] as DateTime?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: served
                                    ? const Color(0xFF22C55E).withOpacity(0.1)
                                    : const Color(0xFFF59E0B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text('#${t['number']}',
                                    style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w800,
                                        color: served
                                            ? const Color(0xFF22C55E)
                                            : const Color(0xFFF59E0B))),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                time != null
                                    ? 'Issued at ${DateFormat('hh:mm a').format(time)}'
                                    : 'Issued',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: served
                                    ? const Color(0xFF22C55E).withOpacity(0.1)
                                    : const Color(0xFFF59E0B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                served ? 'Served' : 'Pending',
                                style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w700,
                                    color: served
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFF59E0B)),
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 14),

                // ── Donations summary
                _sectionCard(
                  icon: Icons.volunteer_activism_rounded,
                  color: const Color(0xFF8E24AA),
                  title: 'Donations (${donationList.length})',
                  child: donationList.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No donations recorded for this date.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        )
                      : Column(children: [
                          // Total
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E5F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Collected',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF8E24AA), fontSize: 14)),
                                Text('PKR ${totalDonations.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF8E24AA), fontSize: 18)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // List
                          ...donationList.map((don) {
                            final status = don['status'] as String;
                            final statusColor = status == 'approved'
                                ? const Color(0xFF22C55E)
                                : status == 'rejected'
                                    ? const Color(0xFFE8572A)
                                    : const Color(0xFFF59E0B);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8E24AA).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.person_rounded,
                                      color: Color(0xFF8E24AA), size: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                    Text(don['donorName'] as String,
                                        style: const TextStyle(
                                            fontSize: 13, fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A))),
                                    Text('${don['type']} · PKR ${(don['amount'] as double).toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            fontSize: 11, color: Color(0xFF94A3B8))),
                                  ]),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(status,
                                      style: TextStyle(
                                          fontSize: 10, fontWeight: FontWeight.w700,
                                          color: statusColor)),
                                ),
                              ]),
                            );
                          }),
                        ]),
                ),
              ],
            );
          },
        ),
      ),
    ]);
  }

  Widget _dateNavBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40, margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: onTap == null
            ? Colors.white.withOpacity(0.05)
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon,
          color: onTap == null ? Colors.white.withOpacity(0.3) : Colors.white,
          size: 20),
    ),
  );

  Widget _sectionCard({
    required IconData icon, required Color color,
    required String title, required Widget child,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 12, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A))),
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      );

  Widget _histStat(String label, String value, IconData icon, Color color) =>
      Column(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 5),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8))),
      ]);
}