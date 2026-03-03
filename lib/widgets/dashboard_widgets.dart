// lib/widgets/dashboard_widgets.dart
// Premium shared dashboard components
// Bento grid layout · Original donut chart · Branch cards with donations & tokens
// Chairman insights · Animated counts · Progress bars
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

// ── Number formatters ─────────────────────────────────────────────────────────
String fmtPKR(int n) {
  if (n >= 10000000) return 'PKR ${(n / 10000000).toStringAsFixed(1)}Cr';
  if (n >= 100000)   return 'PKR ${(n / 100000).toStringAsFixed(1)}L';
  if (n >= 1000)     return 'PKR ${(n / 1000).toStringAsFixed(1)}K';
  return 'PKR $n';
}

String fmtNum(int n) {
  if (n >= 10000000) return '${(n / 10000000).toStringAsFixed(1)}Cr';
  if (n >= 100000)   return '${(n / 100000).toStringAsFixed(1)}L';
  if (n >= 1000)     return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

String fmtPKRDouble(double n) {
  if (n >= 10000000) return 'PKR ${(n / 10000000).toStringAsFixed(1)}Cr';
  if (n >= 100000)   return 'PKR ${(n / 100000).toStringAsFixed(1)}L';
  if (n >= 1000)     return 'PKR ${(n / 1000).toStringAsFixed(1)}K';
  return 'PKR ${n.toStringAsFixed(0)}';
}

// ── Firestore data model ──────────────────────────────────────────────────────
class BranchStats {
  final int zakat, nonZakat, gmwf, dasterkhwaan, donations, dispensed, prescribed;
  const BranchStats({
    this.zakat = 0, this.nonZakat = 0, this.gmwf = 0,
    this.dasterkhwaan = 0, this.donations = 0,
    this.dispensed = 0, this.prescribed = 0,
  });
  int get tokens              => zakat + nonZakat + gmwf;
  int get dispensaryRevenue   => zakat * 20 + nonZakat * 100;
  int get dasterkhwaanRevenue => dasterkhwaan * 10;
  int get totalRevenue        => dispensaryRevenue + dasterkhwaanRevenue + donations;
}

Future<BranchStats> fetchBranchStats(String branchId) async {
  try {
    final df  = DateFormat('ddMMyy');
    final now = DateTime.now();
    final ds  = df.format(DateTime(now.year, now.month, now.day));
    final base = FirebaseFirestore.instance
        .collection('branches').doc(branchId).collection('serials').doc(ds);

    final counts = await Future.wait([
      base.collection('zakat').count().get(),
      base.collection('non-zakat').count().get(),
      base.collection('gmwf').count().get(),
      base.collection('dasterkhwan').count().get(),
    ]);
    final z   = counts[0].count ?? 0;
    final nz  = counts[1].count ?? 0;
    final gm  = counts[2].count ?? 0;
    final das = counts[3].count ?? 0;

    final dispSnap = await FirebaseFirestore.instance
        .collection('branches/$branchId/dispensary/$ds/$ds').count().get();
    final dispensed = dispSnap.count ?? 0;

    final snaps = await Future.wait([
      base.collection('zakat').get(),
      base.collection('non-zakat').get(),
      base.collection('gmwf').get(),
    ]);
    final presRoot = FirebaseFirestore.instance
        .collection('branches').doc(branchId).collection('prescriptions');
    final Map<String, String> sid = {};
    for (final s in snaps) {
      for (final doc in s.docs) {
        final data   = doc.data();
        final serial = data['serial']?.toString();
        if (serial == null) continue;
        final cnic  = data['cnic']?.toString()?.trim() ?? '';
        final gcnic = data['guardianCnic']?.toString()?.trim() ?? '';
        final id    = cnic.isNotEmpty ? cnic : gcnic.isNotEmpty ? gcnic : '';
        if (id.isNotEmpty) sid[serial] = id;
      }
    }
    int prescribed = 0;
    if (sid.isNotEmpty) {
      final ps = await Future.wait(sid.entries.map((e) =>
          presRoot.doc(e.value).collection('prescriptions').doc(e.key).get()));
      prescribed = ps.where((s) => s.exists).length;
    }

    int donations = 0;
    try {
      final donSnap = await FirebaseFirestore.instance
          .collection('branches').doc(branchId).collection('donations')
          .where('date', isEqualTo: ds).get();
      for (final doc in donSnap.docs) {
        donations += ((doc.data()['amount'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}

    return BranchStats(
      zakat: z, nonZakat: nz, gmwf: gm,
      dasterkhwaan: das, donations: donations,
      dispensed: dispensed, prescribed: prescribed,
    );
  } catch (_) {
    return const BranchStats();
  }
}

Future<BranchStats> fetchAllBranchesStats(List<String> ids) async {
  final results = await Future.wait(ids.map(fetchBranchStats));
  int z = 0, nz = 0, gm = 0, das = 0, don = 0, disp = 0, presc = 0;
  for (final r in results) {
    z += r.zakat; nz += r.nonZakat; gm += r.gmwf;
    das += r.dasterkhwaan; don += r.donations;
    disp += r.dispensed; presc += r.prescribed;
  }
  return BranchStats(
    zakat: z, nonZakat: nz, gmwf: gm, dasterkhwaan: das,
    donations: don, dispensed: disp, prescribed: presc,
  );
}

// ── Loading card ──────────────────────────────────────────────────────────────
class DashLoadingCard extends StatelessWidget {
  final RoleThemeData t;
  final double height;
  const DashLoadingCard({super.key, required this.t, required this.height});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: t.bgCard,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: t.bgRule),
    ),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: t.accent)),
  );
}

// ── Section heading ───────────────────────────────────────────────────────────
class DashHeading extends StatelessWidget {
  final String text;
  final RoleThemeData t;
  const DashHeading(this.text, {super.key, required this.t});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 4, height: 20,
        decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 10),
    Text(text, style: TextStyle(
        color: t.textPrimary, fontSize: 18,
        fontWeight: FontWeight.w800, letterSpacing: -0.3)),
  ]);
}

// ── Animated count-up ─────────────────────────────────────────────────────────
class _AnimatedCount extends StatefulWidget {
  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;
  const _AnimatedCount({required this.value, required this.style,
      this.prefix = '', this.suffix = ''});
  @override
  State<_AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<_AnimatedCount>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final v = (widget.value * _anim.value).toInt();
      String s;
      if (widget.value >= 10000000)
        s = '${(v / 10000000).toStringAsFixed(1)}Cr';
      else if (widget.value >= 100000)
        s = '${(v / 100000).toStringAsFixed(1)}L';
      else if (widget.value >= 1000)
        s = '${(v / 1000).toStringAsFixed(1)}K';
      else
        s = NumberFormat('#,##0', 'en_US').format(v);
      return Text('${widget.prefix}$s${widget.suffix}', style: widget.style);
    },
  );
}

// ── Animated progress bar ─────────────────────────────────────────────────────
class _AnimatedProgressBar extends StatefulWidget {
  final double value;
  final Color color;
  final Color? backgroundColor;
  final double height;
  const _AnimatedProgressBar({
    required this.value, required this.color,
    this.backgroundColor, this.height = 8,
  });
  @override
  State<_AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<_AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: LinearProgressIndicator(
        value: (widget.value * _anim.value).clamp(0.0, 1.0),
        minHeight: widget.height,
        backgroundColor: widget.backgroundColor ?? widget.color.withOpacity(0.15),
        valueColor: AlwaysStoppedAnimation(widget.color),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════════
// ORIGINAL DONUT CHART (reverted — percentage labels on arcs)
// ════════════════════════════════════════════════════════════════════════════════

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double progress;

  _DonutPainter({required this.values, required this.colors, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (a, b) => a + b);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 6;
    const strokeW = 44.0;
    const gap = 0.022;

    double startAngle = -pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final sweep = (values[i] / total) * 2 * pi * progress - gap;
      if (sweep <= 0) {
        startAngle += (values[i] / total) * 2 * pi * progress;
        continue;
      }

      paint.color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gap / 2, sweep, false, paint,
      );

      // Percentage label on arc
      final pct = (values[i] / total * 100).round();
      if (pct >= 5 && progress > 0.65) {
        final midAngle = startAngle + gap / 2 + sweep / 2;
        final lx = center.dx + radius * cos(midAngle);
        final ly = center.dy + radius * sin(midAngle);
        final tp = TextPainter(
          text: TextSpan(
            text: '$pct%',
            style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w800),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
      }
      startAngle += (values[i] / total) * 2 * pi * progress;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.progress != progress;
}

class _AnimatedDonut extends StatefulWidget {
  final List<double> values;
  final List<Color> colors;
  final Widget center;
  final double size;
  const _AnimatedDonut({required this.values, required this.colors,
      required this.center, this.size = 190});
  @override
  State<_AnimatedDonut> createState() => _AnimatedDonutState();
}

class _AnimatedDonutState extends State<_AnimatedDonut>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 1300), vsync: this);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => SizedBox(
      width: widget.size, height: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _DonutPainter(
              values: widget.values, colors: widget.colors, progress: _anim.value),
        ),
        widget.center,
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════════
// HERO BANNER — Purple gradient
// ════════════════════════════════════════════════════════════════════════════════

class HeroBanner extends StatefulWidget {
  final RoleThemeData t;
  final String username;
  final String roleLabel;
  final BranchStats stats;

  const HeroBanner({
    super.key,
    required this.t,
    required this.username,
    required this.roleLabel,
    required this.stats,
  });
  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final completionPct = s.tokens > 0
        ? (s.dispensed / s.tokens * 100).clamp(0, 100).toDouble()
        : 0.0;

    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF6B48FF), Color(0xFF8B6FFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(
            color: const Color(0xFF6B48FF).withOpacity(0.35),
            blurRadius: 32, offset: const Offset(0, 12),
          )],
        ),
        child: Stack(children: [
          Positioned(right: -20, top: -20,
            child: Container(width: 130, height: 130,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07)))),
          Positioned(right: 50, top: 25,
            child: Container(width: 65, height: 65,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05)))),

          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Welcome, ${widget.username}',
                    style: const TextStyle(color: Colors.white, fontSize: 24,
                        fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text('Patient Processing Overview – Today',
                    style: TextStyle(color: Colors.white.withOpacity(0.75),
                        fontSize: 13)),
              ])),
            ]),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _AnimatedCount(value: s.tokens,
                    style: const TextStyle(color: Colors.white, fontSize: 42,
                        fontWeight: FontWeight.w900, height: 1.0)),
                const SizedBox(height: 4),
                Text('Total Patients',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
              ])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${completionPct.toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 42,
                        fontWeight: FontWeight.w900, height: 1.0)),
                const SizedBox(height: 4),
                Text('Completion Rate',
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: completionPct / 100,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.20),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.check_circle_rounded, color: Colors.white.withOpacity(0.80), size: 14),
              const SizedBox(width: 5),
              Text('${s.dispensed} processed',
                  style: TextStyle(color: Colors.white.withOpacity(0.80), fontSize: 12)),
              const Spacer(),
              Text(DateFormat('d MMM yyyy').format(DateTime.now()),
                  style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12)),
            ]),
          ]),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CHAIRMAN INSIGHTS CARD — directly below hero
// Overall Performance (purple gradient) + Top Performer (orange-red gradient)
// Shows: Total Revenue, Total Patients, Total Donations, Food Tokens
// ════════════════════════════════════════════════════════════════════════════════

class ChairmanInsightsCard extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  final String topBranchName;
  final String topBranchLocation;
  final int topBranchRevenue;
  final int topBranchPatients;
  final int targetRevenue;

  const ChairmanInsightsCard({
    super.key,
    required this.t,
    required this.s,
    required this.topBranchName,
    this.topBranchLocation = '',
    required this.topBranchRevenue,
    required this.topBranchPatients,
    this.targetRevenue = 21000000,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final isWide = constraints.maxWidth > 600;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3,
              child: _OverallPerformanceCard(s: s)),
          const SizedBox(width: 14),
          Expanded(flex: 2,
              child: _TopPerformerCard(
                  name: topBranchName, location: topBranchLocation,
                  revenue: topBranchRevenue, patients: topBranchPatients)),
        ]);
      }
      return Column(children: [
        _OverallPerformanceCard(s: s),
        const SizedBox(height: 14),
        _TopPerformerCard(name: topBranchName, location: topBranchLocation,
            revenue: topBranchRevenue, patients: topBranchPatients),
      ]);
    });
  }
}

class _OverallPerformanceCard extends StatelessWidget {
  final BranchStats s;
  const _OverallPerformanceCard({required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFA855F7)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.30),
            blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          const Icon(Icons.workspace_premium_rounded, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          const Text('Overall Performance',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.trending_up_rounded, color: Colors.white, size: 12),
              SizedBox(width: 4),
              Text('+12% growth', style: TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 20),

        // Row 1: Total Revenue + Total Patients
        Row(children: [
          Expanded(child: _statBlock(
            label: 'Total Revenue',
            child: _AnimatedCount(value: s.totalRevenue,
                style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 20,
                    fontWeight: FontWeight.w900, height: 1.1)),
          )),
          Expanded(child: _statBlock(
            label: 'Total Patients',
            child: _AnimatedCount(value: s.tokens,
                style: const TextStyle(color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.w900, height: 1.1)),
          )),
        ]),
        const SizedBox(height: 14),

        // Row 2: Total Donations + Food Tokens
        Row(children: [
          Expanded(child: _statBlock(
            label: 'Donations',
            child: _AnimatedCount(value: s.donations,
                style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 20,
                    fontWeight: FontWeight.w900, height: 1.1)),
          )),
          Expanded(child: _statBlock(
            label: 'Food Tokens',
            child: _AnimatedCount(value: s.dasterkhwaan,
                style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 20,
                    fontWeight: FontWeight.w900, height: 1.1)),
          )),
        ]),
      ]),
    );
  }

  Widget _statBlock({required String label, required Widget child}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)),
        const SizedBox(height: 4),
        child,
      ]);
}

class _TopPerformerCard extends StatelessWidget {
  final String name, location;
  final int revenue, patients;
  const _TopPerformerCard({required this.name, required this.location,
      required this.revenue, required this.patients});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.30),
          blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.bolt_rounded, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text('Top Performer', style: TextStyle(
            color: Colors.white.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 14),
      Text(name.isEmpty ? '—' : name,
          style: const TextStyle(color: Colors.white, fontSize: 22,
              fontWeight: FontWeight.w900, height: 1.1)),
      if (location.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(location, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
      ],
      const SizedBox(height: 16),
      _row('Revenue', fmtPKR(revenue)),
      const SizedBox(height: 10),
      _row('Patients', '$patients'),
    ]),
  );

  Widget _row(String label, String value) => Row(children: [
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13)),
    const Spacer(),
    Text(value, style: const TextStyle(
        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
  ]);
}

// ════════════════════════════════════════════════════════════════════════════════
// BENTO GRID — Patient distribution donut + 4 metric tiles
// ════════════════════════════════════════════════════════════════════════════════

class BentoStatsGrid extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  final int branchCount;
  final String topBranchName;
  final int targetRevenue;

  const BentoStatsGrid({
    super.key,
    required this.t,
    required this.s,
    required this.branchCount,
    required this.topBranchName,
    this.targetRevenue = 21000000,
  });

  @override
  Widget build(BuildContext context) {
    final completionPct = s.tokens > 0
        ? (s.dispensed / s.tokens * 100).clamp(0, 100).toDouble()
        : 0.0;

    return LayoutBuilder(builder: (_, c) {
      final isWide = c.maxWidth > 620;

      if (isWide) {
        // Wide: donut on left (spans 2 rows) + 4 tiles on right in 2x2
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Donut card — tall
          SizedBox(
            width: c.maxWidth * 0.42,
            child: _DonutCard(t: t, s: s),
          ),
          const SizedBox(width: 14),
          // 2x2 metric grid
          Expanded(child: Column(children: [
            Row(children: [
              Expanded(child: _BentoTile(
                icon: Icons.track_changes_rounded,
                iconBg: const Color(0xFFF0EDFF),
                iconColor: const Color(0xFF7C3AED),
                value: '${completionPct.toStringAsFixed(0)}%',
                label: 'Avg. Achievement',
              )),
              const SizedBox(width: 12),
              Expanded(child: _BentoTile(
                icon: Icons.location_city_rounded,
                iconBg: const Color(0xFFECFDF5),
                iconColor: const Color(0xFF059669),
                value: topBranchName.isNotEmpty
                    ? topBranchName.split(' ').first
                    : '—',
                label: 'Top Branch',
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _BentoTile(
                icon: Icons.store_rounded,
                iconBg: const Color(0xFFEFF6FF),
                iconColor: const Color(0xFF3B82F6),
                value: '$branchCount/$branchCount',
                label: 'Active Branches',
              )),
              const SizedBox(width: 12),
              Expanded(child: _BentoTile(
                icon: Icons.account_balance_wallet_rounded,
                iconBg: const Color(0xFFFFF7ED),
                iconColor: const Color(0xFFD97706),
                value: fmtPKR(targetRevenue),
                label: 'Total Target',
              )),
            ]),
          ])),
        ]);
      }

      // Narrow: stacked
      return Column(children: [
        _DonutCard(t: t, s: s),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _BentoTile(
              icon: Icons.track_changes_rounded,
              iconBg: const Color(0xFFF0EDFF),
              iconColor: const Color(0xFF7C3AED),
              value: '${completionPct.toStringAsFixed(0)}%',
              label: 'Avg. Achievement',
            ),
            _BentoTile(
              icon: Icons.location_city_rounded,
              iconBg: const Color(0xFFECFDF5),
              iconColor: const Color(0xFF059669),
              value: topBranchName.isNotEmpty
                  ? topBranchName.split(' ').first : '—',
              label: 'Top Branch',
            ),
            _BentoTile(
              icon: Icons.store_rounded,
              iconBg: const Color(0xFFEFF6FF),
              iconColor: const Color(0xFF3B82F6),
              value: '$branchCount/$branchCount',
              label: 'Active Branches',
            ),
            _BentoTile(
              icon: Icons.account_balance_wallet_rounded,
              iconBg: const Color(0xFFFFF7ED),
              iconColor: const Color(0xFFD97706),
              value: fmtPKR(targetRevenue),
              label: 'Total Target',
            ),
          ],
        ),
      ]);
    });
  }
}

// ── Donut card (bento left panel) ─────────────────────────────────────────────
class _DonutCard extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  const _DonutCard({required this.t, required this.s});

  @override
  Widget build(BuildContext context) {
    final total = s.tokens;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.bgRule),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Patient Distribution',
            style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),

        if (total == 0)
          Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('No patients today', style: TextStyle(color: t.textTertiary)),
          ))
        else
          Center(
            child: _AnimatedDonut(
              size: 185,
              values: [s.zakat.toDouble(), s.nonZakat.toDouble(), s.gmwf.toDouble()],
              colors: [t.zakat, t.nonZakat, t.gmwf],
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                _AnimatedCount(value: total,
                    style: TextStyle(color: t.textPrimary, fontSize: 24,
                        fontWeight: FontWeight.w900)),
                Text('patients', style: TextStyle(color: t.textTertiary, fontSize: 11)),
              ]),
            ),
          ),

        const SizedBox(height: 18),
        // Legend
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _dot(t.zakat, 'Zakat'),
          const SizedBox(width: 18),
          _dot(t.nonZakat, 'Non-Zakat'),
          const SizedBox(width: 18),
          _dot(t.gmwf, 'GMWF'),
        ]),
      ]),
    );
  }

  Widget _dot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 9, height: 9,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
        color: const Color(0xFF4B5563))),
  ]);
}

// ── Single bento tile ─────────────────────────────────────────────────────────
class _BentoTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String value, label;

  const _BentoTile({
    required this.icon, required this.iconBg, required this.iconColor,
    required this.value, required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
          blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 18)),
      const Spacer(),
      Text(value,
          style: TextStyle(
              fontSize: value.length > 7 ? 15 : 22,
              fontWeight: FontWeight.w800, color: const Color(0xFF111827), height: 1.1),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF),
          fontWeight: FontWeight.w500)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════════════
// KPI TILES ROW
// ════════════════════════════════════════════════════════════════════════════════

class KpiTilesRow extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  final int branchCount;
  const KpiTilesRow({super.key, required this.t, required this.s, required this.branchCount});

  @override
  Widget build(BuildContext context) {
    final completionPct = s.tokens > 0 ? (s.dispensed / s.tokens * 100) : 0.0;
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth < 500 ? 2 : 4;
      return GridView.count(
        crossAxisCount: cols,
        crossAxisSpacing: 12, mainAxisSpacing: 12,
        childAspectRatio: cols == 2 ? 1.55 : 1.75,
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        children: [
          _KpiCard(t: t, icon: Icons.people_rounded, color: t.zakat,
              label: 'Total Patients',
              child: _AnimatedCount(value: s.tokens,
                  style: TextStyle(color: t.zakat, fontSize: 28,
                      fontWeight: FontWeight.w900, height: 1.1))),
          _KpiCard(t: t, icon: Icons.check_circle_rounded, color: t.nonZakat,
              label: 'Completed',
              child: _AnimatedCount(value: s.dispensed,
                  style: TextStyle(color: t.nonZakat, fontSize: 28,
                      fontWeight: FontWeight.w900, height: 1.1))),
          _KpiCard(t: t, icon: Icons.trending_up_rounded, color: t.gmwf,
              label: 'Avg. Completion',
              child: Text('${completionPct.toStringAsFixed(1)}%',
                  style: TextStyle(color: t.gmwf, fontSize: 28,
                      fontWeight: FontWeight.w900, height: 1.1))),
          _KpiCard(t: t, icon: Icons.store_rounded, color: t.accentLight,
              label: 'Active Branches',
              child: _AnimatedCount(value: branchCount,
                  style: TextStyle(color: t.accentLight, fontSize: 28,
                      fontWeight: FontWeight.w900, height: 1.1))),
        ],
      );
    });
  }
}

class _KpiCard extends StatelessWidget {
  final RoleThemeData t;
  final IconData icon;
  final Color color;
  final String label;
  final Widget child;
  const _KpiCard({required this.t, required this.icon, required this.color,
      required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: t.bgCard,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withOpacity(0.20)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
          blurRadius: 12, offset: const Offset(0, 3))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18)),
      const Spacer(),
      child,
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: t.textTertiary, fontSize: 11)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════════════
// TOP BRANCH BANNER
// ════════════════════════════════════════════════════════════════════════════════

class TopBranchBanner extends StatelessWidget {
  final RoleThemeData t;
  final String branchName;
  final int revenue;
  final int patients;
  const TopBranchBanner({super.key, required this.t, required this.branchName,
      required this.revenue, required this.patients});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [t.accentLight, t.accent],
        begin: Alignment.centerLeft, end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: t.accent.withOpacity(0.30),
          blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 28)),
      const SizedBox(width: 18),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.20),
              borderRadius: BorderRadius.circular(6)),
          child: const Text('TOP PERFORMING BRANCH – TODAY',
              style: TextStyle(color: Colors.white, fontSize: 9,
                  fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 8),
        Text(branchName, style: const TextStyle(
            color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.attach_money_rounded, color: Colors.white70, size: 15),
          const SizedBox(width: 4),
          Text(fmtPKR(revenue), style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          const Icon(Icons.people_rounded, color: Colors.white70, size: 15),
          const SizedBox(width: 4),
          Text('$patients patients', style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ])),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════════════
// GRAND TOTALS CARD
// ════════════════════════════════════════════════════════════════════════════════

class GrandTotalsCard extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  const GrandTotalsCard({super.key, required this.t, required this.s});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: t.bgCard, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: t.bgRule),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
          blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: t.accentMuted, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.analytics_outlined, color: t.accent, size: 18)),
        const SizedBox(width: 10),
        Text("Today's Overview", style: TextStyle(
            color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(DateFormat('dd MMM yyyy').format(DateTime.now()),
            style: TextStyle(color: t.textTertiary, fontSize: 12)),
      ]),
      const SizedBox(height: 18),
      _AnimatedCount(value: s.totalRevenue, prefix: 'PKR ',
          style: TextStyle(color: t.accent, fontSize: 32,
              fontWeight: FontWeight.w900, letterSpacing: -1)),
      const SizedBox(height: 2),
      Text('Total Revenue (Dispensary + Dasterkhwaan + Donations)',
          style: TextStyle(color: t.textTertiary, fontSize: 11)),
      const SizedBox(height: 18),
      Divider(height: 1, color: t.bgRule),
      const SizedBox(height: 14),
      Row(children: [
        _revPill(Icons.local_pharmacy_outlined, 'Dispensary',
            fmtPKR(s.dispensaryRevenue), t.accentLight),
        _vDiv(),
        _revPill(Icons.restaurant_outlined, 'Dasterkhwaan',
            fmtPKR(s.dasterkhwaanRevenue), t.zakat),
        _vDiv(),
        _revPill(Icons.volunteer_activism_rounded, 'Donations',
            fmtPKR(s.donations), const Color(0xFF6A1B9A)),
      ]),
      const SizedBox(height: 18),
      Divider(height: 1, color: t.bgRule),
      const SizedBox(height: 14),
      Row(children: [
        _kpiPill('Zakat', s.zakat, t.zakat),
        _vDiv(),
        _kpiPill('Non-Zakat', s.nonZakat, t.nonZakat),
        _vDiv(),
        _kpiPill('GMWF', s.gmwf, t.gmwf),
        _vDiv(),
        _kpiPill('Food Tokens', s.dasterkhwaan, t.accentLight),
      ]),
    ]),
  );

  Widget _revPill(IconData icon, String label, String val, Color color) =>
      Expanded(child: Column(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(height: 5),
        Text(val, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center,
            style: TextStyle(color: t.textTertiary, fontSize: 10)),
      ]));

  Widget _kpiPill(String label, int count, Color color) =>
      Expanded(child: Column(children: [
        _AnimatedCount(value: count,
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center,
            style: TextStyle(color: t.textTertiary, fontSize: 10)),
      ]));

  Widget _vDiv() => Container(width: 1, height: 36, color: t.bgRule,
      margin: const EdgeInsets.symmetric(horizontal: 4));
}

// ════════════════════════════════════════════════════════════════════════════════
// PATIENT DISTRIBUTION CARD (kept for admin/manager screens that use it directly)
// ════════════════════════════════════════════════════════════════════════════════

class PatientDistributionCard extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  const PatientDistributionCard({super.key, required this.t, required this.s});

  @override
  Widget build(BuildContext context) {
    final total = s.tokens;
    final zPct  = total > 0 ? (s.zakat    / total * 100).round() : 0;
    final nPct  = total > 0 ? (s.nonZakat / total * 100).round() : 0;
    final gPct  = total > 0 ? (s.gmwf     / total * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.bgRule),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: t.accentMuted, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.donut_large_rounded, color: t.accent, size: 18)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Patient Type Distribution – Today',
                style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Total across all branches',
                style: TextStyle(color: t.textTertiary, fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 24),
        if (total == 0)
          Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No patients today', style: TextStyle(color: t.textTertiary)),
          ))
        else
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _AnimatedDonut(
              size: 185,
              values: [s.zakat.toDouble(), s.nonZakat.toDouble(), s.gmwf.toDouble()],
              colors: [t.zakat, t.nonZakat, t.gmwf],
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                _AnimatedCount(value: total,
                    style: TextStyle(color: t.textPrimary, fontSize: 24,
                        fontWeight: FontWeight.w900)),
                Text('patients', style: TextStyle(color: t.textTertiary, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 24),
            Expanded(child: Column(children: [
              _legendRow(t.zakat,    'Zakat',     s.zakat,    zPct,
                  'PKR ${s.zakat * 20}',     '@PKR 20'),
              const SizedBox(height: 10),
              _legendRow(t.nonZakat, 'Non-Zakat', s.nonZakat, nPct,
                  'PKR ${s.nonZakat * 100}', '@PKR 100'),
              const SizedBox(height: 10),
              _legendRow(t.gmwf,     'GMWF',      s.gmwf,     gPct,
                  'Free',                    'No charge'),
            ])),
          ]),
      ]),
    );
  }

  Widget _legendRow(Color c, String label, int count, int pct,
      String rev, String rate) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.withOpacity(0.06), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.18)),
        ),
        child: Row(children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(
              color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$count', style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w800)),
            Text(rev, style: TextStyle(color: c.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
            child: Text('$pct%', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

// ════════════════════════════════════════════════════════════════════════════════
// SERVICE REVENUE CARD
// ════════════════════════════════════════════════════════════════════════════════

class ServiceRevenueCard extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  const ServiceRevenueCard({super.key, required this.t, required this.s});

  @override
  Widget build(BuildContext context) {
    const dasColor = Color(0xFF0891B2);
    const donColor = Color(0xFF6A1B9A);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.bgRule),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Services & Donations',
            style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        _svcRow(Icons.restaurant_outlined, dasColor, 'Dasterkhwaan Food Tokens',
            '${s.dasterkhwaan} tokens · × PKR 10', s.dasterkhwaanRevenue),
        const SizedBox(height: 10),
        Divider(height: 1, color: t.bgRule),
        const SizedBox(height: 10),
        _svcRow(Icons.volunteer_activism_rounded, donColor, 'Donations Collected',
            'Cash & transfers · today', s.donations),
        const SizedBox(height: 14),
        Divider(height: 1, color: t.bgRule),
        const SizedBox(height: 10),
        Row(children: [
          Text('Services Total', style: TextStyle(
              color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          _AnimatedCount(value: s.dasterkhwaanRevenue + s.donations, prefix: 'PKR ',
              style: TextStyle(color: t.accent, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }

  Widget _svcRow(IconData icon, Color color, String title, String sub, int amount) =>
      Row(children: [
        Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: t.textTertiary, fontSize: 11)),
        ])),
        _AnimatedCount(value: amount, prefix: 'PKR ',
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      ]);
}

// ════════════════════════════════════════════════════════════════════════════════
// BRANCH SUMMARY CARD — with donations + food tokens rows
// ════════════════════════════════════════════════════════════════════════════════

class BranchSummaryCard extends StatelessWidget {
  final RoleThemeData t;
  final String branchId;
  final String branchName;
  final String? location;
  final int? revenueTarget;

  const BranchSummaryCard({
    super.key,
    required this.t,
    required this.branchId,
    required this.branchName,
    this.location,
    this.revenueTarget = 3000000,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<BranchStats>(
    future: fetchBranchStats(branchId),
    builder: (_, snap) {
      final loading = snap.connectionState == ConnectionState.waiting;
      final s = snap.data ?? const BranchStats();
      final target = revenueTarget ?? 3000000;
      final achPct = target > 0
          ? (s.totalRevenue / target * 100).clamp(0, 100).toDouble()
          : 0.0;

      return AnimatedOpacity(
        opacity: loading ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          decoration: BoxDecoration(
            color: t.bgCard, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.bgRule),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 16, offset: const Offset(0, 5))],
          ),
          child: loading
              ? SizedBox(height: 90, child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: t.accent)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // ── Header ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: t.accentMuted.withOpacity(0.35),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      border: Border(bottom: BorderSide(color: t.bgRule)),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(branchName, style: TextStyle(
                            color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                        if (location != null && location!.isNotEmpty)
                          Row(children: [
                            Icon(Icons.location_on_outlined, size: 11, color: t.textTertiary),
                            const SizedBox(width: 3),
                            Text(location!, style: TextStyle(
                                color: t.textTertiary, fontSize: 11)),
                          ]),
                      ])),
                      // Token badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: t.accent.withOpacity(0.35),
                              blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: _AnimatedCount(value: s.tokens,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 14, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),

                  // ── Body ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      // Patient type row
                      Row(children: [
                        _typeCol(Icons.mosque_rounded,                   t.zakat,    'Zakat',    s.zakat),
                        const SizedBox(width: 16),
                        _typeCol(Icons.account_balance_wallet_outlined,  t.nonZakat, 'Non-Z',    s.nonZakat),
                        const SizedBox(width: 16),
                        _typeCol(Icons.favorite_rounded,                 t.gmwf,     'GMWF',     s.gmwf),
                        const Spacer(),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          _AnimatedCount(value: s.dispensaryRevenue, prefix: 'PKR ',
                              style: TextStyle(color: t.accent, fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                          Text('dispensary', style: TextStyle(color: t.textTertiary, fontSize: 10)),
                        ]),
                      ]),

                      // Distribution bar
                      if (s.tokens > 0) ...[
                        const SizedBox(height: 12),
                        _AnimatedDistBar(
                          zakat: s.zakat, nonZakat: s.nonZakat, gmwf: s.gmwf,
                          colorZ: t.zakat, colorNZ: t.nonZakat, colorG: t.gmwf,
                        ),
                      ],

                      const SizedBox(height: 16),
                      Divider(height: 1, color: t.bgRule),
                      const SizedBox(height: 14),

                      // Revenue progress bar
                      Row(children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 13, color: t.textTertiary),
                        const SizedBox(width: 6),
                        Text('Revenue', style: TextStyle(
                            color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        _AnimatedCount(value: s.totalRevenue,
                            style: TextStyle(color: t.accent, fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 6),
                      _AnimatedProgressBar(value: achPct / 100, color: t.accent),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text('Target: ${fmtPKR(target)}',
                            style: TextStyle(color: t.textTertiary, fontSize: 10)),
                        const Spacer(),
                        Text('${achPct.toStringAsFixed(0)}%',
                            style: TextStyle(color: t.accent, fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ]),

                      const SizedBox(height: 14),
                      Divider(height: 1, color: t.bgRule),
                      const SizedBox(height: 12),

                      // Donations + Food tokens + Total row
                      Row(children: [
                        _svcChip(Icons.restaurant_outlined, const Color(0xFF0891B2),
                            'Food Tokens',
                            s.dasterkhwaan > 0
                                ? '${s.dasterkhwaan} · ${fmtPKR(s.dasterkhwaanRevenue)}'
                                : '—'),
                        const SizedBox(width: 12),
                        _svcChip(Icons.volunteer_activism_rounded,
                            const Color(0xFF6A1B9A),
                            'Donations',
                            s.donations > 0 ? fmtPKR(s.donations) : '—'),
                        const Spacer(),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('Total', style: TextStyle(
                              color: t.textTertiary, fontSize: 10, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          _AnimatedCount(value: s.totalRevenue, prefix: 'PKR ',
                              style: TextStyle(color: t.accent, fontSize: 15,
                                  fontWeight: FontWeight.w900)),
                        ]),
                      ]),
                    ]),
                  ),
                ]),
        ),
      );
    },
  );

  Widget _typeCol(IconData icon, Color color, String label, int count) =>
      Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: t.textTertiary, fontSize: 10)),
        const SizedBox(height: 2),
        _AnimatedCount(value: count,
            style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
      ]);

  Widget _svcChip(IconData icon, Color color, String label, String value) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 14)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 11,
              fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ]);
}

// ── Animated distribution bar ─────────────────────────────────────────────────
class _AnimatedDistBar extends StatefulWidget {
  final int zakat, nonZakat, gmwf;
  final Color colorZ, colorNZ, colorG;
  const _AnimatedDistBar({required this.zakat, required this.nonZakat, required this.gmwf,
      required this.colorZ, required this.colorNZ, required this.colorG});
  @override
  State<_AnimatedDistBar> createState() => _AnimatedDistBarState();
}

class _AnimatedDistBarState extends State<_AnimatedDistBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final total = widget.zakat + widget.nonZakat + widget.gmwf;
    if (total == 0) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(children: [
          if (widget.zakat    > 0) Expanded(flex: widget.zakat,    child: Container(height: 7, color: widget.colorZ)),
          if (widget.nonZakat > 0) Expanded(flex: widget.nonZakat, child: Container(height: 7, color: widget.colorNZ)),
          if (widget.gmwf     > 0) Expanded(flex: widget.gmwf,     child: Container(height: 7, color: widget.colorG)),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// DONATIONS SUMMARY CARD
// ════════════════════════════════════════════════════════════════════════════════

class DonationsSummaryCard extends StatelessWidget {
  final RoleThemeData t;
  final List<Map<String, dynamic>> branches;
  final int totalDonations;
  const DonationsSummaryCard({super.key, required this.t,
      required this.branches, required this.totalDonations});

  @override
  Widget build(BuildContext context) {
    const donColor = Color(0xFF6A1B9A);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: donColor.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: donColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.volunteer_activism_rounded, color: donColor, size: 18)),
          const SizedBox(width: 10),
          Text('Total Donations', style: TextStyle(
              color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          _AnimatedCount(value: totalDonations, prefix: 'PKR ',
              style: const TextStyle(color: donColor, fontSize: 18, fontWeight: FontWeight.w900)),
        ]),
        if (branches.isNotEmpty) ...[
          const SizedBox(height: 14),
          Divider(height: 1, color: t.bgRule),
          const SizedBox(height: 10),
          ...branches.where((b) => (b['donations'] as int) > 0).map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 6, height: 6,
                  decoration: BoxDecoration(color: donColor.withOpacity(0.5),
                      shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(b['name'] as String,
                  style: TextStyle(color: t.textSecondary, fontSize: 13))),
              Text(fmtPKR(b['donations'] as int),
                  style: const TextStyle(color: donColor, fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ]),
          )),
        ],
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// BRANCH PERFORMANCE HEADER
// ════════════════════════════════════════════════════════════════════════════════

class BranchPerformanceHeader extends StatelessWidget {
  final RoleThemeData t;
  final int branchCount;
  const BranchPerformanceHeader({super.key, required this.t, required this.branchCount});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text('Branch Performance', style: TextStyle(
        color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
    const Spacer(),
    Text('$branchCount branches', style: TextStyle(
        color: t.textTertiary, fontSize: 13, fontWeight: FontWeight.w500)),
  ]);
}