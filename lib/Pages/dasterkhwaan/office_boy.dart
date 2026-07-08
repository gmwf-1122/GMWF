// lib/pages/dasterkhwaan/office_boy.dart
//
// Redesign: Refined Luxury Fintech aesthetic
// Palette  : Deep forest green hero · mint accent · white surfaces
// Typography: Google Fonts – DM Serif Display (headings) + DM Sans (body)
//
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../widgets/gmwf_loading_view.dart';
import '../donations/donations_screen.dart';
import '../donations/donations_shared.dart';
import '../../services/donations_local_storage.dart';

// ─────────────────────────── Design Tokens ──────────────────────────────────

abstract class _DS {
  // Surfaces
  static const Color bg       = Color(0xFFF4F7F6);
  static const Color surface  = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFEDF2F1);
  static const Color border   = Color(0xFFE2ECEA);
  static const Color border2  = Color(0xFFC8D9D6);

  // Brand greens
  static const Color sage     = Color(0xFF1A3530);
  static const Color sage2    = Color(0xFF243D38);
  static const Color mint     = Color(0xFF00C9A7);
  static const Color mint2    = Color(0xFF00E8C1);
  static const Color mintBg   = Color(0xFFE6FDF8);

  // Semantic
  static const Color amber    = Color(0xFFD97706);
  static const Color amberBg  = Color(0xFFFFFBEB);
  static const Color green    = Color(0xFF1A9966);
  static const Color greenBg  = Color(0xFFEAF7F0);
  static const Color red      = Color(0xFFE04444);
  static const Color redBg    = Color(0xFFFEF0F0);
  static const Color purple   = Color(0xFF7C3AED);
  static const Color purpleBg = Color(0xFFF0EBFE);
  static const Color purpleDark = Color(0xFF2D1B69);

  // Text
  static const Color ink      = Color(0xFF0A0F0E);
  static const Color ink2     = Color(0xFF2D3B38);
  static const Color ink3     = Color(0xFF6B8480);

  // Radius
  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r22 = 22;
  static const double rPill = 100;
}

// ─────────────────────────── Text Styles ────────────────────────────────────

abstract class _TS {
  static TextStyle displayLg(Color c) => GoogleFonts.dmSerifDisplay(
      fontSize: 28, color: c, height: 1.1);

  static TextStyle displayMd(Color c) => GoogleFonts.dmSerifDisplay(
      fontSize: 22, color: c, height: 1.2);

  static TextStyle label({Color c = _DS.ink3, double size = 10}) =>
      GoogleFonts.dmSans(
          fontSize: size, fontWeight: FontWeight.w600,
          letterSpacing: 1.2, color: c);

  static TextStyle body({Color? c, double size = 14, FontWeight w = FontWeight.w400}) =>
      GoogleFonts.dmSans(fontSize: size, fontWeight: w, color: c ?? _DS.ink);

  static TextStyle num({Color? c, double size = 22}) =>
      GoogleFonts.dmSans(fontSize: size, fontWeight: FontWeight.w600, color: c ?? _DS.ink, height: 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOT WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class DasterkhwaanOfficeBoy extends StatefulWidget {
  static const String routeName = '/dasterkhwaan-office-boy';
  final String? branchId;
  final String? userName;
  final String? role;

  const DasterkhwaanOfficeBoy({
    super.key,
    this.branchId,
    this.userName,
    this.role,
  });

  @override
  State<DasterkhwaanOfficeBoy> createState() => _DasterkhwaanOfficeBoyState();
}

class _DasterkhwaanOfficeBoyState extends State<DasterkhwaanOfficeBoy>
    with TickerProviderStateMixin {
  int _currentNav = 0;
  String _userName = 'User';
  String? _branchId;

  final _qtyCtrl = TextEditingController(text: '1');
  final double _pricePerToken = 10.0;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  final DateFormat _dateFmt    = DateFormat('yyyy-MM-dd');
  final DateFormat _displayFmt = DateFormat('EEE, dd MMM yyyy');
  late final String today      = _dateFmt.format(DateTime.now());

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
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
            _userName = data['username'] ??
                user.email?.split('@').first ??
                'Office Boy';
            _branchId = branch.id;
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
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(today);
  }

  Future<Map<String, dynamic>> _getTodayStats() async {
    if (_branchId == null) return {'total': 0, 'served': 0, 'donations': 0, 'donationAmount': 0.0};
    
    // ── 1. Tokens (Firestore) ──────────────────────────────────────────
    final snap = await _dayDoc.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final totalTokens = data['totalTokens'] as int? ?? 0;
    final servedTokens = data['servedTokens'] as int? ?? 0;

    // ── 2. Donations (Local + Cloud) ───────────────────────────────────
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    
    // a. Get Local (Hive) - Instant feedback for 'Pending Upload'
    final localDonations = DonationsLocalStorage.getAllDonations(_branchId!)
        .where((d) => d.date == today && d.collectorId == uid);
    
    // b. Get Cloud (Firestore)
    final donSnap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('donations')
        .where('branchId', isEqualTo: _branchId)
        .where('date', isEqualTo: today)
        .where('collectorId', isEqualTo: uid)
        .get();
    
    // c. Merge and deduplicate (using localId/firestoreId)
    final Map<String, double> uniqueDonations = {};
    for (var d in localDonations) {
      uniqueDonations[d.localId] = d.amount;
    }
    for (var d in donSnap.docs) {
      final data = d.data();
      final lid  = data['localId'] as String? ?? d.id;
      uniqueDonations[lid] = (data['amount'] as num? ?? 0).toDouble();
    }

    double donTotal = 0;
    uniqueDonations.forEach((_, amt) => donTotal += amt);

    return {
      'total': totalTokens,
      'served': servedTokens,
      'donations': uniqueDonations.length,
      'donationAmount': donTotal,
    };
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
        'time':   FieldValue.serverTimestamp(),
        'served': false,
      });
    }
    batch.set(dayRef, {'totalTokens': FieldValue.increment(quantity)},
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
          width: 26, height: 26,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(
            isError ? Icons.close_rounded : Icons.check_rounded,
            color: Colors.white, size: 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white)),
        ),
      ]),
      backgroundColor: isError ? _DS.red : _DS.sage,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DS.r14)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DS.bg,
      body: IndexedStack(
        index: _currentNav,
        children: [
          _HomeScreen(
            userName:     _userName,
            role:         widget.role,
            branchId:     _branchId,
            today:        today,
            getTodayStats: _getTodayStats,
            onGoTokens:   () => setState(() => _currentNav = 1),
            onGoHistory:  () => setState(() => _currentNav = 2),
            onGoDonation: () => setState(() => _currentNav = 3),
            onLogout:     _logout,
            heroFade:     _fadeAnim,
            pricePerToken: _pricePerToken,
          ),
          _TokensScreen(
            userName:           _userName,
            branchId:           _branchId,
            today:              today,
            displayFormat:      _displayFmt,
            quantityController: _qtyCtrl,
            pricePerToken:      _pricePerToken,
            onGenerate:         _generateTokens,
            pulseAnim:          _pulseAnim,
            getTodayStats:      _getTodayStats,
            onLogout:           _logout,
            onSelectQty: (qty) {
              _qtyCtrl.text = qty.toString();
              setState(() {});
            },
          ),
          _branchId == null
              ? const GmwfLoadingView()
              : _HistoryScreen(
                  branchId:     _branchId!,
                  dateFmt:      _dateFmt,
                  onLogout:     _logout,
                  pricePerToken: _pricePerToken,
                ),
          // 3 – Donations
          _branchId == null
              ? const GmwfLoadingView()
              : DonationsScreen.embedded(
                  branchId: _branchId!,
                  username: _userName,
                  userId:   FirebaseAuth.instance.currentUser?.uid ?? '',
                  role:     UserRole.officeBoy,
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

  Widget _buildBottomNav() {
    const labels = ['Home', 'Tokens', 'History', 'Donation'];
    const icons  = [
      Icons.home_rounded,
      Icons.credit_card_rounded,
      Icons.access_time_rounded,
      Icons.volunteer_activism_rounded,
    ];

    return Container(
      decoration: BoxDecoration(
        color: _DS.surface,
        border: Border(top: BorderSide(color: _DS.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(4, (idx) {
              final sel = _currentNav == idx;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _currentNav = idx);
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? _DS.sage : Colors.transparent,
                    borderRadius: BorderRadius.circular(_DS.r14),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icons[idx],
                        size: 20,
                        color: sel ? Colors.white : _DS.ink3),
                    if (sel) ...[
                      const SizedBox(width: 7),
                      Text(labels[idx],
                          style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
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
  final String? role;
  final String? branchId;
  final String today;
  final Future<Map<String, dynamic>> Function() getTodayStats;
  final VoidCallback onGoTokens, onGoHistory, onGoDonation, onLogout;
  final Animation<double> heroFade;
  final double pricePerToken;

  const _HomeScreen({
    required this.userName,
    this.role,
    required this.branchId,
    required this.today,
    required this.getTodayStats,
    required this.onGoTokens,
    required this.onGoHistory,
    required this.onGoDonation,
    required this.onLogout,
    required this.heroFade,
    required this.pricePerToken,
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

        // ── Hero header ────────────────────────────────────────────────────
        SliverToBoxAdapter(
            child: _HeroHeader(
              greeting:  _greeting(),
              userName:  userName,
              onLogout:  onLogout,
              badgeLabel: 'Office Boy',
            ),
          ),

        // ── Today stats row ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: FutureBuilder<Map<String, dynamic>>(
            future: getTodayStats(),
            builder: (_, snap) {
              final total  = snap.data?['total']  ?? 0;
              final served = snap.data?['served'] ?? 0;
              final pending = total - served;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(children: [
                  _StatChip(value: '$total',   label: 'Issued',  color: _DS.mint),
                  const SizedBox(width: 8),
                  _StatChip(value: '$pending', label: 'Pending', color: _DS.amber),
                  const SizedBox(width: 8),
                  _StatChip(value: '$served',  label: 'Served',  color: _DS.green),
                ]),
              );
            },
          ),
        ),

        // ── Revenue band ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: FutureBuilder<Map<String, dynamic>>(
            future: getTodayStats(),
            builder: (_, snap) {
              final total   = snap.data?['total'] ?? 0;
              final revenue = total * pricePerToken;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _RevenueBand(
                  revenue: revenue,
                  pricePerToken: pricePerToken,
                ),
              );
            },
          ),
        ),

        // ── Quick Actions ─────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel('Quick Actions'),
                const SizedBox(height: 12),
                _ActionCardWide(
                  icon:      Icons.credit_card_rounded,
                  iconColor: _DS.mint,
                  iconBg:    _DS.mintBg,
                  title:     'Issue Tokens',
                  subtitle:  'Generate meal tokens for guests',
                  urdu:      'کھانے کا ٹوکن جاری کریں',
                  onTap:     onGoTokens,
                ),
                const SizedBox(height: 10),
                _ActionCardWide(
                  icon:      Icons.volunteer_activism_rounded,
                  iconColor: _DS.amber,
                  iconBg:    _DS.amberBg,
                  title:     'Record Donation',
                  subtitle:  'Collect and save new contributions',
                  urdu:      'عطیہ جمع کریں',
                  onTap:     onGoDonation,
                ),
                const SizedBox(height: 10),
                _ActionCardWide(
                  icon:      Icons.calendar_month_rounded,
                  iconColor: _DS.purple,
                  iconBg:    _DS.purpleBg,
                  title:     'Daily History',
                  subtitle:  'Tokens & donations by date',
                  urdu:      'روزانہ کا ریکارڈ دیکھیں',
                  onTap:     onGoHistory,
                ),
              ],
            ),
          ),
        ),

        // ── Today's Donation summary ─────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          sliver: SliverToBoxAdapter(
            child: FutureBuilder<Map<String, dynamic>>(
              future: getTodayStats(),
              builder: (_, snap) {
                final count  = snap.data?['donations'] ?? 0;
                final amount = snap.data?['donationAmount'] ?? 0.0;
                return _DonationSummaryCard(
                  count: count,
                  amount: amount,
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HEADER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _HeroHeader extends StatelessWidget {
  final String greeting;
  final String userName;
  final VoidCallback onLogout;
  final String badgeLabel;
  final List<Color> gradientColors;

  const _HeroHeader({
    required this.greeting,
    required this.userName,
    required this.onLogout,
    required this.badgeLabel,
    this.gradientColors = const [_DS.sage, _DS.sage2],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(children: [
          // Decorative circles
          Positioned(
            top: -50, right: -30,
            child: Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _DS.mint.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -60, left: -20,
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _DS.mint.withValues(alpha: 0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: logo + logout
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Logo pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(_DS.r14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 0.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/logo/gmwf.png',
                            width: 42, height: 42,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                                Icons.restaurant_rounded,
                                color: Colors.white70, size: 24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Office',
                            style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    // Logout
                    _LogoutButton(onTap: onLogout),
                  ],
                ),
                const SizedBox(height: 28),
                Text(greeting,
                    style: GoogleFonts.dmSans(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w400)),
                const SizedBox(height: 4),
                Text(userName,
                    style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.1)),
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _DS.mint.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(_DS.rPill),
                      border: Border.all(
                          color: _DS.mint.withValues(alpha: 0.25), width: 0.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 5, height: 5,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: _DS.mint),
                      ),
                      const SizedBox(width: 6),
                      Text(badgeLabel,
                          style: GoogleFonts.dmSans(
                              color: _DS.mint,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('EEE, dd MMM').format(DateTime.now()),
                    style: GoogleFonts.dmSans(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11),
                  ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Logout Button ──────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: _DS.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(_DS.r12),
            border: Border.all(
                color: _DS.red.withValues(alpha: 0.25), width: 0.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.logout_rounded,
                color: Color(0xFFFF8080), size: 15),
            const SizedBox(width: 5),
            Text('Logout',
                style: GoogleFonts.dmSans(
                    color: const Color(0xFFFF8080),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

// ─── Stat Chip ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatChip({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: _DS.surface,
            borderRadius: BorderRadius.circular(_DS.r16),
            border: Border.all(color: _DS.border, width: 0.5),
          ),
          child: Column(children: [
            Text(value,
                style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: color,
                    height: 1.0)),
            const SizedBox(height: 4),
            Text(label.toUpperCase(),
                style: GoogleFonts.dmSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _DS.ink3,
                    letterSpacing: 0.4)),
          ]),
        ),
      );
}

class _DonationSummaryCard extends StatelessWidget {
  final int count;
  final double amount;
  const _DonationSummaryCard({required this.count, required this.amount});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _DS.surface,
          borderRadius: BorderRadius.circular(_DS.r22),
          border: Border.all(color: _DS.border, width: 0.5),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _DS.amberBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.volunteer_activism_rounded,
                color: _DS.amber, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's Donations",
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _DS.ink)),
                Text('$count contributions recorded',
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: _DS.ink3)),
              ],
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('PKR ${amount.toStringAsFixed(0)}',
                style: GoogleFonts.dmSerifDisplay(
                    fontSize: 20, color: _DS.amber)),
            Text('TOTAL COLLECTED',
                style: GoogleFonts.dmSans(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: _DS.amber.withValues(alpha: 0.6))),
          ]),
        ]),
      );
}

// ─── Revenue Band ─────────────────────────────────────────────────────────────

class _RevenueBand extends StatelessWidget {
  final double revenue, pricePerToken;
  const _RevenueBand({required this.revenue, required this.pricePerToken});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: _DS.sage,
          borderRadius: BorderRadius.circular(_DS.r22),
        ),
        child: Stack(children: [
          Positioned(
            top: -30, right: -20,
            child: Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _DS.mint.withValues(alpha: 0.07)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Today's Revenue",
                    style: GoogleFonts.dmSans(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('PKR ${revenue.toStringAsFixed(0)}',
                    style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white, fontSize: 26)),
              ]),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _DS.mint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(_DS.rPill),
                  border: Border.all(
                      color: _DS.mint.withValues(alpha: 0.25), width: 0.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.toll_rounded,
                      color: _DS.mint, size: 13),
                  const SizedBox(width: 5),
                  Text('PKR ${pricePerToken.toInt()} / token',
                      style: GoogleFonts.dmSans(
                          color: _DS.mint,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        ]),
      );
}

// ─── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.dmSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.3,
            color: _DS.ink3),
      );
}

// ─── Action Card Wide ─────────────────────────────────────────────────────────

class _ActionCardWide extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String title, subtitle, urdu;
  final VoidCallback onTap;

  const _ActionCardWide({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.urdu,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DS.surface,
            borderRadius: BorderRadius.circular(_DS.r22),
            border: Border.all(color: _DS.border, width: 0.5),
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(_DS.r14)),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _DS.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: _DS.ink3)),
                  const SizedBox(height: 5),
                  Text(urdu,
                      style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: iconColor.withValues(alpha: 0.7))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: _DS.border2, size: 15),
          ]),
        ),
      );
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
  final Future<Map<String, dynamic>> Function() getTodayStats;
  final void Function(int) onSelectQty;

  const _TokensScreen({
    required this.userName,
    required this.branchId,
    required this.today,
    required this.displayFormat,
    required this.quantityController,
    required this.pricePerToken,
    required this.onGenerate,
    required this.pulseAnim,
    required this.getTodayStats,
    required this.onSelectQty,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A3530), Color(0xFF243D38)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Stack(children: [
              Positioned(
                top: -40, right: -30,
                child: Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _DS.mint.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Issue Tokens',
                                style: GoogleFonts.dmSerifDisplay(
                                    color: Colors.white, fontSize: 24)),
                            Text(
                              'PKR ${pricePerToken.toInt()} per token · Branch',
                              style: GoogleFonts.dmSans(
                                  color: Colors.white.withValues(alpha: 0.40),
                                  fontSize: 11),
                            ),
                          ],
                        ),
                        _LogoutButton(onTap: onLogout),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Inline stats strip
                    FutureBuilder<Map<String, dynamic>>(
                      future: getTodayStats(),
                      builder: (_, snap) {
                        final total  = snap.data?['total']  ?? 0;
                        final served = snap.data?['served'] ?? 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(_DS.r16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 0.5),
                          ),
                          child: Row(children: [
                            _InlineStat('Total',   '$total',
                                Icons.credit_card_rounded,
                                const Color(0xFF80DEEA)),
                            _divider(),
                            _InlineStat('Pending', '${total - served}',
                                Icons.hourglass_empty_rounded,
                                const Color(0xFFFFCC80)),
                            _divider(),
                            _InlineStat('Served',  '$served',
                                Icons.check_circle_rounded,
                                const Color(0xFFA5D6A7)),
                            _divider(),
                            _InlineStat('PKR',
                                '${(total * pricePerToken).toStringAsFixed(0)}',
                                Icons.account_balance_wallet_rounded,
                                const Color(0xFFCE93D8)),
                          ]),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),

      // Body
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date pill (centered)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _DS.mintBg,
                    borderRadius: BorderRadius.circular(_DS.rPill),
                    border: Border.all(
                        color: _DS.mint.withValues(alpha: 0.25), width: 0.5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 11, color: _DS.mint),
                    const SizedBox(width: 6),
                    Text(
                      displayFormat.format(DateTime.now()),
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _DS.mint),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 24),

              // Quick select
              _SectionLabel('Quick Select'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [1, 2, 3, 4, 5].map((qty) => _QuickChip(
                  qty: qty,
                  selected: quantityController.text == qty.toString(),
                  onTap: () => onSelectQty(qty),
                )).toList(),
              ),
              const SizedBox(height: 24),

              // Custom quantity
              _SectionLabel('Custom Quantity'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: _DS.surface,
                  borderRadius: BorderRadius.circular(_DS.r22),
                  border: Border.all(color: _DS.border, width: 0.5),
                ),
                child: TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _DS.ink),
                  decoration: InputDecoration(
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _DS.mintBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.credit_card_rounded,
                            color: _DS.mint, size: 17),
                      ),
                    ),
                    suffixText: () {
                      final n = int.tryParse(quantityController.text);
                      if (n == null || n <= 0) return null;
                      return '= PKR ${(n * pricePerToken).toStringAsFixed(0)}';
                    }(),
                    suffixStyle: GoogleFonts.dmSans(
                        color: _DS.mint,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                    hintText: 'Enter quantity…',
                    hintStyle: GoogleFonts.dmSans(
                        color: _DS.ink3, fontSize: 14),
                    filled: true,
                    fillColor: _DS.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_DS.r22),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_DS.r22),
                        borderSide: const BorderSide(
                            color: _DS.mint, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Issue button
              _IssueButton(
                quantityController: quantityController,
                pricePerToken:      pricePerToken,
                pulseAnim:          pulseAnim,
                onPressed:          onGenerate,
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _InlineStat(
      String label, String val, IconData icon, Color color) =>
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 4),
          Text(val,
              style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          Text(label,
              style: GoogleFonts.dmSans(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 9,
                  fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _divider() => Container(
      width: 0.5, height: 34,
      color: Colors.white.withValues(alpha: 0.12));
}

// ─── Quick Chip ───────────────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  final int qty;
  final bool selected;
  final VoidCallback onTap;

  const _QuickChip({
    required this.qty,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 58, height: 60,
          decoration: BoxDecoration(
            color: selected ? _DS.sage : _DS.surface,
            borderRadius: BorderRadius.circular(_DS.r16),
            border: Border.all(
              color: selected ? _DS.sage : _DS.border,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Center(
            child: Text(
              '$qty',
              style: GoogleFonts.dmSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : _DS.ink2),
            ),
          ),
        ),
      );
}

// ─── Issue Button ─────────────────────────────────────────────────────────────

class _IssueButton extends StatelessWidget {
  final TextEditingController quantityController;
  final double pricePerToken;
  final Animation<double> pulseAnim;
  final VoidCallback onPressed;

  const _IssueButton({
    required this.quantityController,
    required this.pricePerToken,
    required this.pulseAnim,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final qty   = int.tryParse(quantityController.text) ?? 0;
    final total = (qty * pricePerToken).toStringAsFixed(0);
    return ScaleTransition(
      scale: pulseAnim,
      child: Container(
        width: double.infinity, height: 62,
        decoration: BoxDecoration(
          color: _DS.sage,
          borderRadius: BorderRadius.circular(_DS.r22),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(_DS.r22),
            onTap: onPressed,
            splashColor: Colors.white.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_rounded,
                        size: 17, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Issue ${quantityController.text.isEmpty ? "0" : quantityController.text}'
                        ' Token${qty != 1 ? "s" : ""}',
                        style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                      if (qty > 0)
                        Text('Total · PKR $total',
                            style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.45))),
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

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryScreen extends StatefulWidget {
  final String branchId;
  final DateFormat dateFmt;
  final VoidCallback onLogout;
  final double pricePerToken;

  const _HistoryScreen({
    required this.branchId,
    required this.dateFmt,
    required this.onLogout,
    required this.pricePerToken,
  });

  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen> {
  DateTime _selectedDate = DateTime.now();

  Future<Map<String, dynamic>> _fetchDayData(String dateKey) async {
    final tokensSnap = await FirebaseFirestore.instance
        .collection('branches').doc(widget.branchId)
        .collection('dasterkhwaan').doc(dateKey)
        .collection('tokens')
        .get();

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    
    // a. Get Local (Hive)
    final localList = DonationsLocalStorage.getAllDonations(widget.branchId)
        .where((d) => d.date == dateKey && d.collectorId == uid)
        .toList();

    // b. Get Cloud (Global Collection)
    final donationsSnap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('donations')
        .where('branchId', isEqualTo: widget.branchId)
        .where('date', isEqualTo: dateKey)
        .where('collectorId', isEqualTo: uid)
        .get();

    // c. Merge and deduplicate
    final List<Map<String, dynamic>> mergedDonations = [];
    final Set<String> seenIds = {};

    for (var d in localList) {
      mergedDonations.add({
        'donorName':  d.donorName,
        'amount':     d.amount,
        'type':       d.categoryId,
        'status':     d.status,
        'syncStatus': d.syncStatus,
        'localId':    d.localId,
        'time':       DateTime.tryParse(d.timestamp ?? ''),
      });
      seenIds.add(d.localId);
    }

    for (var d in donationsSnap.docs) {
      final data = d.data();
      final lid = data['localId'] as String? ?? d.id;
      if (!seenIds.contains(lid)) {
        mergedDonations.add({
          ...data,
          'donorName':  data['donorName']  ?? 'Valued Donor',
          'amount':     (data['amount']    as num? ?? 0.0).toDouble(),
          'type':       data['categoryId'] ?? 'GMWF',
          'status':     data['status']     ?? 'pending',
          'time':       (data['time']      as Timestamp?)?.toDate(),
        });
      }
    }

    final totalTokens  = tokensSnap.docs.length;
    final servedTokens = tokensSnap.docs
        .where((d) => (d.data())['served'] == true)
        .length;
    final totalRevenue = totalTokens * widget.pricePerToken;

    final tokenList = tokensSnap.docs
        .map((d) {
          final data = d.data();
          return {
            'number':     data['number'] as int? ?? 0,
            'served':     data['served'] as bool? ?? false,
            'time':       (data['time'] as Timestamp?)?.toDate(),
            'servedTime': (data['servedTime'] as Timestamp?)?.toDate(),
          };
        })
        .toList()
      ..sort((a, b) =>
          (a['number'] as int).compareTo(b['number'] as int));

    final donationList = mergedDonations;
    final totalDonations = donationList.fold<double>(
        0.0, (sum, d) => sum + (d['amount'] as num? ?? 0).toDouble());

    return {
      'totalTokens':    totalTokens,
      'servedTokens':   servedTokens,
      'totalRevenue':   totalRevenue,
      'tokenList':      tokenList,
      'donationList':   donationList,
      'totalDonations': totalDonations,
    };
  }

  @override
  Widget build(BuildContext context) {
    final todayStr   = widget.dateFmt.format(DateTime.now());
    final dateKey    = widget.dateFmt.format(_selectedDate);
    final isToday    = dateKey == todayStr;
    final displayDate = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Column(children: [
      // ── Purple header ──────────────────────────────────────────────────
      Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2D1B69), Color(0xFF4C1D95)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Daily History',
                              style: GoogleFonts.dmSerifDisplay(
                                  color: Colors.white, fontSize: 24)),
                          Text('Tokens & donations by date',
                              style: GoogleFonts.dmSans(
                                  color: Colors.white.withValues(alpha: 0.40),
                                  fontSize: 11)),
                        ],
                      ),
                      _LogoutButton(onTap: widget.onLogout),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Date navigator
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(_DS.r14),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 0.5),
                    ),
                    child: Row(children: [
                      _DateNavBtn(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => setState(() => _selectedDate =
                            _selectedDate.subtract(
                                const Duration(days: 1))),
                      ),
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
                                  colorScheme: const ColorScheme.light(
                                      primary: _DS.purple),
                                  textButtonTheme: TextButtonThemeData(
                                    style: TextButton.styleFrom(
                                        foregroundColor: _DS.purple),
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                            }
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.calendar_today_rounded,
                                    color: Colors.white, size: 13),
                                const SizedBox(width: 7),
                                Text(
                                  isToday
                                      ? 'Today · $displayDate'
                                      : displayDate,
                                  style: GoogleFonts.dmSans(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _DateNavBtn(
                        icon: Icons.chevron_right_rounded,
                        onTap: isToday
                            ? null
                            : () => setState(() => _selectedDate =
                                _selectedDate.add(
                                    const Duration(days: 1))),
                        disabled: isToday,
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),

      // ── Body ──────────────────────────────────────────────────────────
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          key: ValueKey(dateKey),
          future: _fetchDayData(dateKey),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: _DS.purple, strokeWidth: 2));
            }
            if (snap.hasError) {
              return Center(
                  child: Text('Error: ${snap.error}',
                      style: _TS.body(c: _DS.ink3)));
            }
            final d              = snap.data!;
            final totalTokens   = d['totalTokens']    as int;
            final servedTokens  = d['servedTokens']   as int;
            final totalRevenue  = d['totalRevenue']   as double;
            final tokenList     = d['tokenList']
                as List<Map<String, dynamic>>;
            final donationList  = d['donationList']
                as List<Map<String, dynamic>>;
            final totalDonations = d['totalDonations'] as double;

            if (totalTokens == 0 && donationList.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_note_rounded,
                        size: 72,
                        color: _DS.purple.withValues(alpha: 0.15)),
                    const SizedBox(height: 14),
                    Text('No records for $displayDate',
                        style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _DS.ink3)),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                // Token summary
                _HistSectionCard(
                  icon:  Icons.credit_card_rounded,
                  color: _DS.mint,
                  title: 'Token Summary',
                  child: Column(children: [
                    Row(children: [
                      _HistStatTile('Issued',
                          '$totalTokens',  _DS.mint),
                      const SizedBox(width: 8),
                      _HistStatTile('Served',
                          '$servedTokens', _DS.green),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _HistStatTile('Pending',
                          '${totalTokens - servedTokens}',
                          _DS.amber),
                      const SizedBox(width: 8),
                      _HistStatTile('Revenue',
                          'PKR ${totalRevenue.toStringAsFixed(0)}',
                          _DS.purple,
                          smallVal: true),
                    ]),
                    const SizedBox(height: 16),
                    // Progress
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Serving progress',
                            style: GoogleFonts.dmSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _DS.ink3)),
                        Text(
                          totalTokens > 0
                              ? '${((servedTokens / totalTokens) * 100).toStringAsFixed(0)}%'
                              : '0%',
                          style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _DS.mint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: totalTokens > 0
                            ? servedTokens / totalTokens
                            : 0,
                        minHeight: 6,
                        backgroundColor:
                            _DS.mint.withValues(alpha: 0.1),
                        valueColor:
                            const AlwaysStoppedAnimation(_DS.mint),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // Token list
                if (tokenList.isNotEmpty)
                  _HistSectionCard(
                    icon:  Icons.list_alt_rounded,
                    color: _DS.ink3,
                    title: 'Tokens (${tokenList.length})',
                    child: Column(
                      children: tokenList.take(20).map((t) {
                        final served = t['served'] as bool;
                        final time   = t['time']   as DateTime?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: served
                                    ? _DS.greenBg
                                    : _DS.amberBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text('#${t['number']}',
                                    style: GoogleFonts.dmSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: served
                                            ? _DS.green
                                            : _DS.amber)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                time != null
                                    ? 'Issued at ${DateFormat('hh:mm a').format(time)}'
                                    : 'Issued',
                                style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: _DS.ink3),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: served
                                    ? _DS.greenBg
                                    : _DS.amberBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                served ? 'Served' : 'Pending',
                                style: GoogleFonts.dmSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: served
                                        ? _DS.green
                                        : _DS.amber),
                              ),
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 12),

                // Donations
                _HistSectionCard(
                  icon:  Icons.favorite_rounded,
                  color: _DS.purple,
                  title: 'Donations (${donationList.length})',
                  child: donationList.isEmpty
                      ? Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No donations recorded for this date.',
                            style: GoogleFonts.dmSans(
                                color: _DS.ink3, fontSize: 13),
                          ),
                        )
                      : Column(children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _DS.purpleBg,
                              borderRadius:
                                  BorderRadius.circular(_DS.r12),
                            ),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Collected',
                                    style: GoogleFonts.dmSans(
                                        fontWeight: FontWeight.w600,
                                        color: _DS.purple,
                                        fontSize: 13)),
                                Text(
                                  'PKR ${totalDonations.toStringAsFixed(0)}',
                                  style: GoogleFonts.dmSerifDisplay(
                                      color: _DS.purple,
                                      fontSize: 20),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...donationList.map((don) {
                            final status = don['status']?.toString() ?? 'pending';
                            final isApproved = status == 'approved';
                            final isRejected = status == 'rejected';
                            final statusColor = isApproved
                                ? _DS.green
                                : isRejected
                                    ? _DS.red
                                    : _DS.amber;
                            final statusBg = isApproved
                                ? _DS.greenBg
                                : isRejected
                                    ? _DS.redBg
                                    : _DS.amberBg;
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: _DS.purpleBg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      (don['donorName']?.toString() ?? 'D')
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: GoogleFonts.dmSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: _DS.purple),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        don['donorName']?.toString() ?? 'Valued Donor',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _DS.ink),
                                      ),
                                      Text(
                                        '${don['type'] ?? 'General'} · PKR ${(don['amount'] as num? ?? 0).toDouble().toStringAsFixed(0)}',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 11,
                                            color: _DS.ink3),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: Text(status,
                                      style: GoogleFonts.dmSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
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
}

// ─── Date Nav Button ──────────────────────────────────────────────────────────

class _DateNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  const _DateNavBtn({
    required this.icon,
    this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          width: 38, height: 38, margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: disabled
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_DS.r12),
          ),
          child: Icon(icon,
              color: disabled
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.white,
              size: 20),
        ),
      );
}

// ─── History Section Card ─────────────────────────────────────────────────────

class _HistSectionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  const _HistSectionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _DS.surface,
          borderRadius: BorderRadius.circular(_DS.r22),
          border: Border.all(color: _DS.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(_DS.r12),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _DS.ink)),
            ]),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

// ─── Hist Stat Tile ────────────────────────────────────────────────────────────

class _HistStatTile extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool smallVal;

  const _HistStatTile(this.label, this.value, this.color,
      {this.smallVal = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(_DS.r12),
          ),
          child: Column(children: [
            Text(value,
                style: GoogleFonts.dmSans(
                    fontSize: smallVal ? 15 : 20,
                    fontWeight: FontWeight.w600,
                    color: color,
                    height: 1.0)),
            const SizedBox(height: 4),
            Text(label.toUpperCase(),
                style: GoogleFonts.dmSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.65),
                    letterSpacing: 0.4)),
          ]),
        ),
      );
}