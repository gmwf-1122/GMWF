// lib/widgets/home_snapshot_widgets.dart
//
// Phase 1 widgets for the new "Home" snapshot (Today-only, no filter bar).
// Kept in its own file so global_modular_dashboard.dart and
// dashboard_widgets.dart don't need full rewrites — this only reads their
// public API (BranchStats, DS, fmtNum, fmtPKR, RoleThemeData).

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import '../models/module_registry.dart';
import '../services/home_dashboard_service.dart';
import 'dashboard_widgets.dart';
import '../pages/office/finance_page.dart';
import '../pages/madrassa/madrassa_dashboard.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/local_storage_service.dart';
import '../pages/school/utils/school_local_storage.dart';
import '../pages/school/school_dashboard.dart';
import '../pages/users.dart';

// ════════════════════════════════════════════════════════════════════════
// 1. Compact stat tile w/ "vs yesterday" delta
// ════════════════════════════════════════════════════════════════════════

class HomeStatTile extends StatefulWidget {
  final String label;
  final String value;
  final String? prefix;
  final IconData icon;
  final Color color;
  final double? deltaPct; // null = no yesterday data ("New today")
  final VoidCallback? onTap;

  const HomeStatTile({
    super.key,
    required this.label,
    required this.value,
    this.prefix,
    required this.icon,
    required this.color,
    this.deltaPct,
    this.onTap,
  });

  @override
  State<HomeStatTile> createState() => _HomeStatTileState();
}

class _HomeStatTileState extends State<HomeStatTile> with SingleTickerProviderStateMixin {
  bool _hov = false;
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _pressScale = Tween<double>(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final hasDelta = widget.deltaPct != null;
    final isUp = hasDelta && widget.deltaPct! >= 0;
    final deltaColor = !hasDelta
        ? DS.neutral
        : (isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626));
    final isDark = t.isDarkCanvas;

    final Color categoryColor = widget.color;
    final categoryGradient = LinearGradient(
      colors: [categoryColor.withValues(alpha: 0.85), categoryColor],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final tileContent = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutQuart,
      decoration: BoxDecoration(
        color: isDark 
            ? (_hov ? const Color(0xFF1F2937) : const Color(0xFF0F172A))
            : (_hov ? Colors.white : t.bgCard),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _hov
              ? categoryColor.withValues(alpha: 0.6)
              : (isDark ? const Color(0xFF1E293B) : t.bgRule),
          width: _hov ? 2.0 : 1.2,
        ),
        boxShadow: _hov
            ? Neumorphic3DStyle.raisedShadows(isDark: isDark, depth: 1.25, accentColor: categoryColor, showGlow: true)
            : Neumorphic3DStyle.raisedShadows(isDark: isDark, depth: 0.9),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.8),
        child: Stack(
          children: [
            // Background radial glow on hover
            if (_hov)
              Positioned(
                top: -35, right: -35,
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        categoryColor.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            
            // Top accent indicator line
            Positioned(
              left: 0, right: 0, top: 0,
              height: 3,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [categoryColor, categoryColor.withValues(alpha: 0.3)],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon container with dynamic rotation on hover
                  AnimatedRotation(
                    turns: _hov ? 0.03 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: _hov ? categoryGradient : null,
                        color: !_hov 
                            ? (isDark ? const Color(0xFF1E293B) : categoryColor.withValues(alpha: 0.1)) 
                            : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.icon,
                        color: _hov ? Colors.white : categoryColor,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Text fields
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: isDark ? t.textSecondary : const Color(0xFF6B7280),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (widget.prefix != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Text(
                                  widget.prefix!,
                                  style: TextStyle(
                                    color: categoryColor.withValues(alpha: 0.8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.value,
                                  style: TextStyle(
                                    color: isDark ? t.textPrimary : const Color(0xFF111827),
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.4,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              !hasDelta
                                  ? Icons.fiber_new_rounded
                                  : (isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                              size: 10,
                              color: deltaColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              !hasDelta ? 'New today' : '${widget.deltaPct!.abs().toStringAsFixed(0)}% vs yesterday',
                              style: TextStyle(color: deltaColor, fontSize: 8.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hov = true),
        onExit: (_) => setState(() {
          _hov = false;
          _pressCtrl.reverse();
        }),
        child: GestureDetector(
          onTapDown: (_) => _pressCtrl.forward(),
          onTapUp: (_) => _pressCtrl.reverse(),
          onTapCancel: () => _pressCtrl.reverse(),
          onTap: widget.onTap,
          child: ScaleTransition(
            scale: _pressScale,
            child: tileContent,
          ),
        ),
      );
    }
    return tileContent;
  }
}

class HomeStatTileRow extends StatelessWidget {
  final List<HomeStatTile> tiles;
  const HomeStatTileRow({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      int cols = 6;
      double aspectRatio = 2.15;

      if (c.maxWidth < 600) {
        cols = 2;
        aspectRatio = 1.85;
      } else if (c.maxWidth < 1100) {
        cols = 6;
        aspectRatio = 1.95;
      } else {
        cols = 6;
        aspectRatio = 2.25;
      }

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tiles.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: aspectRatio,
        ),
        itemBuilder: (context, index) => tiles[index],
      );
    });
  }
}

// ════════════════════════════════════════════════════════════════════════
// 2. Patients-by-category donut — flat-row legend (mockup style)
//    Local copy of the donut painter since the original is private to
//    dashboard_widgets.dart (Dart privacy is per-file).
// ════════════════════════════════════════════════════════════════════════

class _FlatDonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double progress;
  _FlatDonutPainter({required this.values, required this.colors, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (a, b) => a + b);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 6;
    const strokeW = 34.0;
    const gap = 0.022;
    double startAngle = -pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.butt;

    if (total == 0) {
      paint.color = Colors.grey.withValues(alpha: 0.18);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), 0, 2 * pi, false, paint);
      return;
    }

    for (int i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final sweep = (values[i] / total) * 2 * pi * progress - gap;
      if (sweep <= 0) {
        startAngle += (values[i] / total) * 2 * pi * progress;
        continue;
      }
      paint.color = colors[i];
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle + gap / 2, sweep, false, paint);
      startAngle += (values[i] / total) * 2 * pi * progress;
    }
  }

  @override
  bool shouldRepaint(_FlatDonutPainter old) => old.progress != progress;
}

class _FlatAnimatedDonut extends StatefulWidget {
  final List<double> values;
  final List<Color> colors;
  final Widget center;
  final double size;
  const _FlatAnimatedDonut({required this.values, required this.colors, required this.center, this.size = 150});

  @override
  State<_FlatAnimatedDonut> createState() => _FlatAnimatedDonutState();
}

class _FlatAnimatedDonutState extends State<_FlatAnimatedDonut> with SingleTickerProviderStateMixin {
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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _FlatDonutPainter(values: widget.values, colors: widget.colors, progress: _anim.value)),
            widget.center,
          ]),
        ),
      );
}

class HomePatientDonutCard extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;
  const HomePatientDonutCard({super.key, required this.t, required this.s});

  @override
  Widget build(BuildContext context) {
    final total = s.tokens;
    final zPct = total > 0 ? (s.zakat / total * 100).round() : 0;
    final nPct = total > 0 ? (s.nonZakat / total * 100).round() : 0;
    final gPct = total > 0 ? (s.gmwf / total * 100).round() : 0;

    final values = total == 0 ? [0.0] : [s.zakat.toDouble(), s.nonZakat.toDouble(), s.gmwf.toDouble()];
    final colors = total == 0 
        ? [Colors.grey.shade300] 
        : [t.zakat, t.nonZakat, t.gmwf];

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: t.bgRule),
        boxShadow: Neumorphic3DStyle.raisedShadows(isDark: t.isDarkCanvas, depth: 0.9),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Patients by Category',
            style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: DS.s2),
        LayoutBuilder(builder: (context, c) {
          final isWide = c.maxWidth >= 420;
          final donut = _FlatAnimatedDonut(
            size: isWide ? 150 : 130,
            values: values,
            colors: colors,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$total', style: TextStyle(color: total == 0 ? t.textTertiary : t.textPrimary, fontSize: 24, fontWeight: FontWeight.w900)),
              const Text('patients', style: TextStyle(color: DS.neutral, fontSize: 11)),
            ]),
          );
          final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _flatLegendRow(total == 0 ? Colors.grey.shade400 : t.zakat, 'Zakat', s.zakat, zPct),
            const SizedBox(height: 10),
            _flatLegendRow(total == 0 ? Colors.grey.shade400 : t.nonZakat, 'Non-Zakat', s.nonZakat, nPct),
            const SizedBox(height: 10),
            _flatLegendRow(total == 0 ? Colors.grey.shade400 : t.gmwf, 'GMWF', s.gmwf, gPct),
          ]);
          if (isWide) {
            return Row(children: [donut, const SizedBox(width: DS.s3), Expanded(child: legend)]);
          }
          return Column(children: [Center(child: donut), const SizedBox(height: DS.s2), legend]);
        }),
      ]),
    );
  }

  Widget _flatLegendRow(Color color, String label, int count, int pct) => Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(color: color == Colors.grey.shade400 ? Colors.grey.shade500 : const Color(0xFF374151), fontSize: 12, fontWeight: FontWeight.w600))),
        Text('$count', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(width: 6),
        Text('$pct%', style: const TextStyle(color: DS.neutral, fontSize: 11)),
      ]);
}



class HomeBranchRow {
  final String id;
  final String name;
  final BranchStats today;
  final BranchStats yesterday;
  const HomeBranchRow({required this.id, required this.name, required this.today, required this.yesterday});
}

class HomeBranchPerformanceTable extends StatelessWidget {
  final RoleThemeData t;
  final List<HomeBranchRow> rows; // pass pre-sorted
  final void Function(String branchId)? onTapBranch;

  const HomeBranchPerformanceTable({super.key, required this.t, required this.rows, this.onTapBranch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: t.bgRule),
        boxShadow: Neumorphic3DStyle.raisedShadows(isDark: t.isDarkCanvas, depth: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dispensaries & Camps Performance Today',
              style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: DS.s2),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.bgRule, width: 1.0)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('Dispensary / Camp', style: TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
                Expanded(
                  flex: 2,
                  child: Center(child: Text('Donations (Rs)', style: TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w700))),
                ),
                Expanded(
                  flex: 2,
                  child: Center(child: Text('Patients', style: TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w700))),
                ),
                Expanded(
                  flex: 2,
                  child: Center(child: Text('Revenue (Rs)', style: TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w700))),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No dispensaries or camps to show', style: TextStyle(color: DS.neutral, fontSize: 12)),
              ),
            )
          else
            ...rows.toList().asMap().entries.map((e) {
              final i = e.key;
              final row = e.value;
              
              // Compute donations, patients, revenue and their deltas
              final don = row.today.donations;
              final yDon = row.yesterday.donations;
              final double? donDelta = yDon == 0 ? null : ((don - yDon) / yDon) * 100;

              final pats = row.today.zakat + row.today.nonZakat + row.today.gmwf;
              final yPats = row.yesterday.zakat + row.yesterday.nonZakat + row.yesterday.gmwf;
              final double? patsDelta = yPats == 0 ? null : ((pats - yPats) / yPats) * 100;

              final rev = row.today.dispensaryRevenue;
              final yRev = row.yesterday.dispensaryRevenue;
              final double? revDelta = yRev == 0 ? null : ((rev - yRev) / yRev) * 100;

              final bool isDark = t.isDarkCanvas;

              return InkWell(
                onTap: onTapBranch != null ? () => onTapBranch!(row.id) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: isDark ? t.bgRule : DS.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      // Branch name with rank
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            _RankBadge(rank: i + 1),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                row.name,
                                style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Donations
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(fmtNum(don), style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800)),
                              if (donDelta != null) _deltaIndicator(donDelta),
                            ],
                          ),
                        ),
                      ),
                      // Patients
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(fmtNum(pats), style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800)),
                              if (patsDelta != null) _deltaIndicator(patsDelta),
                            ],
                          ),
                        ),
                      ),
                      // Revenue
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(fmtNum(rev), style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800)),
                              if (revDelta != null) _deltaIndicator(revDelta),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          // View all branches link
          Center(
            child: TextButton(
              onPressed: () {
                if (onTapBranch != null) onTapBranch!('all');
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View all branches', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: t.accent, size: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deltaIndicator(double delta) {
    final isUp = delta >= 0;
    final color = isUp ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 9, color: color),
        const SizedBox(width: 2),
        Text('${delta.abs().toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final isTop = rank == 1;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isTop ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : DS.neutralBg,
        shape: BoxShape.circle,
        border: Border.all(color: isTop ? const Color(0xFFF59E0B) : DS.border),
      ),
      child: Center(
          child: Text('$rank',
              style: TextStyle(
                  color: isTop ? const Color(0xFFC2760C) : DS.neutral, fontSize: 10, fontWeight: FontWeight.w800))),
    );
  }
}

class HomeBestBranchSpotlight extends StatelessWidget {
  final String branchName;
  final int revenue;
  final int donations;
  final int patients;
  final double? growthPct;
  final VoidCallback onTap;
  final RoleThemeData? t;

  const HomeBestBranchSpotlight({
    super.key,
    required this.branchName,
    required this.revenue,
    required this.donations,
    required this.patients,
    required this.growthPct,
    required this.onTap,
    this.t,
  });

  @override
  Widget build(BuildContext context) {
    final hasGrowth = growthPct != null;
    final isUp = hasGrowth && growthPct! >= 0;

    final accent1 = t?.accent ?? const Color(0xFF0F766E);
    final accent2 = Color.lerp(accent1, Colors.black, 0.35) ?? const Color(0xFF0B524D);
    final accent3 = Color.lerp(accent1, Colors.black, 0.55) ?? const Color(0xFF073834);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent1, accent2, accent3],
            stops: const [0.0, 0.55, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(DS.r2),
          boxShadow: [
            BoxShadow(
              color: accent1.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Best Branch Today',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        branchName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Top Performer',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // 3D Golden trophy on solid 100% white circle
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFFFFF176),
                        Color(0xFFF59E0B),
                        Color(0xFFB45309),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white30, height: 1),
            const SizedBox(height: 14),
            // Details list
            _metricRow(Icons.payments_outlined, 'Revenue', fmtPKR(revenue)),
            const SizedBox(height: 10),
            _metricRow(Icons.volunteer_activism_outlined, 'Donations', fmtPKR(donations)),
            const SizedBox(height: 10),
            _metricRow(Icons.people_alt_outlined, 'Patients', patients.toString()),
            const SizedBox(height: 10),
            _metricRow(
              Icons.trending_up_rounded,
              'Growth',
              hasGrowth
                  ? '${isUp ? '+' : ''}${growthPct!.toStringAsFixed(0)}% vs yesterday'
                  : 'No data for yesterday',
              valueColor: hasGrowth
                  ? (isUp ? const Color(0xFFD1FAE5) : const Color(0xFFFFE4E6))
                  : Colors.white.withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(IconData icon, String label, String value, {Color valueColor = Colors.white}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 16),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.90), fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class HomePatientsByCategoryDonut extends StatelessWidget {
  final RoleThemeData t;
  final BranchStats s;

  const HomePatientsByCategoryDonut({super.key, required this.t, required this.s});

  @override
  Widget build(BuildContext context) {
    final int total = s.zakat + s.nonZakat + s.gmwf;
    final bool isDark = t.isDarkCanvas;
    
    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: isDark ? t.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: isDark ? t.bgRule : DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Patients by Category',
              style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: DS.s2),
          Expanded(
            child: total == 0
                ? const Center(
                    child: Text('No patients today', style: TextStyle(color: DS.neutral, fontSize: 12)),
                  )
                : Row(
                    children: [
                      // Legend column
                      Expanded(
                        flex: 6,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _donutLegendItem('Zakat', s.zakat, total, const Color(0xFF10B981), Icons.assignment_ind_rounded),
                            const SizedBox(height: 8),
                            _donutLegendItem('Non-Zakat', s.nonZakat, total, const Color(0xFF3B82F6), Icons.badge_rounded),
                            const SizedBox(height: 8),
                            _donutLegendItem('GMWF', s.gmwf, total, const Color(0xFFF59E0B), Icons.child_care_rounded),
                          ],
                        ),
                      ),
                      const SizedBox(width: DS.s2),
                      // Donut ring
                      Expanded(
                        flex: 5,
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: CustomPaint(
                            painter: _DonutChartPainter(
                              zakat: s.zakat.toDouble(),
                              nonZakat: s.nonZakat.toDouble(),
                              gmwf: s.gmwf.toDouble(),
                              total: total.toDouble(),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    total.toString(),
                                    style: TextStyle(
                                      color: isDark ? t.textPrimary : const Color(0xFF111827),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Total Patients',
                                    style: TextStyle(
                                      color: DS.neutral,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _donutLegendItem(String label, int val, int total, Color color, IconData icon) {
    final double pct = total == 0 ? 0.0 : (val / total) * 100;
    final bool isDark = t.isDarkCanvas;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: DS.neutral, fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  val.toString(),
                  style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double zakat;
  final double nonZakat;
  final double gmwf;
  final double total;

  _DonutChartPainter({
    required this.zakat,
    required this.nonZakat,
    required this.gmwf,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius - 10);
    
    final paintZ = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final paintNz = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final paintGm = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    double startAngle = -pi / 2;

    if (zakat > 0) {
      final sweepZ = (zakat / total) * 2 * pi;
      canvas.drawArc(rect, startAngle + 0.05, sweepZ - 0.1, false, paintZ);
      startAngle += sweepZ;
    }

    if (nonZakat > 0) {
      final sweepNz = (nonZakat / total) * 2 * pi;
      canvas.drawArc(rect, startAngle + 0.05, sweepNz - 0.1, false, paintNz);
      startAngle += sweepNz;
    }

    if (gmwf > 0) {
      final sweepGm = (gmwf / total) * 2 * pi;
      canvas.drawArc(rect, startAngle + 0.05, sweepGm - 0.1, false, paintGm);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class HomeRecentDonationsTable extends StatelessWidget {
  final List<RecentActivity> activities;
  final RoleThemeData t;

  const HomeRecentDonationsTable({super.key, required this.activities, required this.t});

  @override
  Widget build(BuildContext context) {
    final donations = activities.where((a) => a.type == 'donation').toList();
    final bool isDark = t.isDarkCanvas;

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: isDark ? t.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: isDark ? t.bgRule : DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Donations',
                  style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              Text('View all', style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: DS.s2),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? t.bgRule : DS.border, width: 1.0))),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Donor', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Center(child: Text('Amount', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700)))),
                Expanded(flex: 3, child: Text('Branch', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Center(child: Text('Time', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700)))),
              ],
            ),
          ),
          if (donations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No recent donations', style: TextStyle(color: DS.neutral, fontSize: 11))),
            )
          else
            ...donations.take(4).map((a) {
              final match = RegExp(r'Received from ([^(]+)').firstMatch(a.subtitle);
              final donorName = match?.group(1)?.trim() ?? 'Walk-in Donor';
              final amt = a.amount ?? 0.0;
              final timeStr = DateFormat('hh:mm a').format(a.timestamp);

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? t.bgRule : DS.border, width: 0.5))),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(donorName, style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 11.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text('Rs ${fmtNum(amt.toInt())}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(a.branchName, style: const TextStyle(color: DS.neutral, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(timeStr, style: const TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class HomeRecentPatientsTable extends StatelessWidget {
  final List<RecentActivity> activities;
  final RoleThemeData t;

  const HomeRecentPatientsTable({super.key, required this.activities, required this.t});

  @override
  Widget build(BuildContext context) {
    final tokens = activities.where((a) => a.type == 'token').toList();
    final bool isDark = t.isDarkCanvas;

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: isDark ? t.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: isDark ? t.bgRule : DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Patients',
                  style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              Text('View all', style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: DS.s2),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? t.bgRule : DS.border, width: 1.0))),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Patient ID', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Center(child: Text('Category', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700)))),
                Expanded(flex: 3, child: Text('Branch', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Center(child: Text('Time', style: TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w700)))),
              ],
            ),
          ),
          if (tokens.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No recent patients', style: TextStyle(color: DS.neutral, fontSize: 11))),
            )
          else
            ...tokens.take(4).map((a) {
              final match = RegExp(r'Patient: ([^\(]+)\s*\(([^)]+)\)').firstMatch(a.subtitle);
              final pName = match?.group(1)?.trim() ?? 'Patient';
              final category = match?.group(2)?.trim() ?? 'ZAKAT';
              
              final hash = a.id.hashCode.abs() % 10000;
              final pId = 'P-${hash.toString().padLeft(5, '0')}';
              
              final timeStr = DateFormat('hh:mm a').format(a.timestamp);

              Color badgeBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5);
              Color badgeText = isDark ? const Color(0xFF34D399) : const Color(0xFF047857);
              if (category.toLowerCase() == 'non-zakat') {
                badgeBg = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF);
                badgeText = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
              } else if (category.toLowerCase() == 'gmwf') {
                badgeBg = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
                badgeText = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
              }

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? t.bgRule : DS.border, width: 0.5))),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pId, style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 11, fontWeight: FontWeight.w700)),
                          Text(pName, style: const TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(color: badgeText, fontSize: 8.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(a.branchName, style: const TextStyle(color: DS.neutral, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(timeStr, style: const TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 5. Patients Revenue Line Chart (CustomPainter)
// ════════════════════════════════════════════════════════════════════════

class HomeRevenueLineChart extends StatefulWidget {
  final List<HomeLineChartPoint> points;
  final RoleThemeData t;
  const HomeRevenueLineChart({super.key, required this.points, required this.t});

  @override
  State<HomeRevenueLineChart> createState() => _HomeRevenueLineChartState();
}

class _HomeRevenueLineChartState extends State<HomeRevenueLineChart> {
  int? hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(DS.r2),
          border: Border.all(color: DS.border),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final double maxMoney = widget.points.isEmpty 
        ? 100 
        : max(100.0, max(
            widget.points.map((p) => p.patientsRevenue.toDouble()).reduce(max),
            widget.points.map((p) => p.donations.toDouble()).reduce(max),
          )) * 1.15;
          
    final double maxTokens = widget.points.isEmpty
        ? 10
        : max(10.0, widget.points.map((p) => p.tokens.toDouble()).reduce(max)) * 1.15;

    final double maxEmployees = widget.points.isEmpty
        ? 10
        : max(10.0, widget.points.map((p) => p.employeesPresent.toDouble()).reduce(max)) * 1.15;

    final bool isDark = widget.t.isDarkCanvas;

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: isDark ? widget.t.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: isDark ? widget.t.bgRule : DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weekly Progress Trends',
                        style: TextStyle(color: isDark ? widget.t.textPrimary : const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    const Text('Metrics for the last 5 weeks',
                        style: TextStyle(color: DS.neutral, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              if (hoveredIndex != null && hoveredIndex! < widget.points.length) ...[
                Builder(
                  builder: (context) {
                    final pt = widget.points[hoveredIndex!];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Week ending ${DateFormat('d MMM').format(pt.date)}',
                          style: TextStyle(color: isDark ? widget.t.textPrimary : const Color(0xFF111827), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _hoverPill('Donations', fmtPKR(pt.donations), const Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            _hoverPill('Patients Rev', fmtPKR(pt.patientsRevenue), widget.t.accent),
                            const SizedBox(width: 4),
                            _hoverPill('Tokens', pt.tokens.toString(), const Color(0xFF3B82F6)),
                            const SizedBox(width: 4),
                            _hoverPill('Staff', pt.employeesPresent.toString(), const Color(0xFF8B5CF6)),
                          ],
                        ),
                      ],
                    );
                  }
                ),
              ],
            ],
          ),
          const SizedBox(height: DS.s2),
          SizedBox(
            height: 180,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                return GestureDetector(
                  onPanUpdate: (details) {
                    final localPos = details.localPosition;
                    final dx = localPos.dx;
                    final stepX = width / (widget.points.length - 1);
                    int index = (dx / stepX).round().clamp(0, widget.points.length - 1);
                    if (hoveredIndex != index) {
                      setState(() {
                        hoveredIndex = index;
                      });
                    }
                  },
                  onPanEnd: (_) {
                    setState(() {
                      hoveredIndex = null;
                    });
                  },
                  onTapDown: (details) {
                    final localPos = details.localPosition;
                    final dx = localPos.dx;
                    final stepX = width / (widget.points.length - 1);
                    int index = (dx / stepX).round().clamp(0, widget.points.length - 1);
                    setState(() {
                      hoveredIndex = index;
                    });
                  },
                  child: CustomPaint(
                    size: Size(width, constraints.maxHeight),
                    painter: _MultiLineChartPainter(
                      points: widget.points,
                      accentColor: widget.t.accent,
                      maxMoney: maxMoney,
                      maxTokens: maxTokens,
                      maxEmployees: maxEmployees,
                      hoveredIndex: hoveredIndex,
                      isDark: isDark,
                      gridColor: isDark ? widget.t.bgRule : DS.border,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem('Donations', const Color(0xFF10B981)),
                const SizedBox(width: 12),
                _legendItem('Patients Revenue', widget.t.accent),
                const SizedBox(width: 12),
                _legendItem('Tokens Issued', const Color(0xFF3B82F6)),
                const SizedBox(width: 12),
                _legendItem('Employees Present', const Color(0xFF8B5CF6)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hoverPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 3),
          Text(value, style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 3,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _MultiLineChartPainter extends CustomPainter {
  final List<HomeLineChartPoint> points;
  final Color accentColor;
  final double maxMoney;
  final double maxTokens;
  final double maxEmployees;
  final int? hoveredIndex;
  final bool isDark;
  final Color gridColor;

  _MultiLineChartPainter({
    required this.points,
    required this.accentColor,
    required this.maxMoney,
    required this.maxTokens,
    required this.maxEmployees,
    required this.isDark,
    required this.gridColor,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final width = size.width;
    final chartHeight = size.height - 24;
    final len = points.length;
    final double stepX = width / (len - 1);

    double getX(int i) => i * stepX;
    
    double getYMoney(double val) {
      final ratio = val / maxMoney;
      return chartHeight - (ratio * chartHeight);
    }

    double getYTokens(double val) {
      final ratio = val / maxTokens;
      return chartHeight - (ratio * chartHeight);
    }

    double getYEmployees(double val) {
      final ratio = val / maxEmployees;
      return chartHeight - (ratio * chartHeight);
    }

    // 1. Draw Grid Lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    
    const int gridCount = 4;
    for (int i = 0; i <= gridCount; i++) {
      final y = chartHeight * i / gridCount;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    final donColor = const Color(0xFF10B981);
    final tokColor = const Color(0xFF3B82F6);
    final empColor = const Color(0xFF8B5CF6);

    // 2. Draw Lines (Donations, Patients Rev, Tokens, Employees)
    _drawLine(canvas, points.map((p) => p.donations.toDouble()).toList(), donColor, stepX, chartHeight, maxMoney);
    _drawLine(canvas, points.map((p) => p.patientsRevenue.toDouble()).toList(), accentColor, stepX, chartHeight, maxMoney);
    _drawLine(canvas, points.map((p) => p.tokens.toDouble()).toList(), tokColor, stepX, chartHeight, maxTokens);
    _drawLine(canvas, points.map((p) => p.employeesPresent.toDouble()).toList(), empColor, stepX, chartHeight, maxEmployees);

    // 3. Draw X-axis labels (Day names like Mon, Tue, Wed...)
    final textStyle = const TextStyle(
      color: DS.neutral,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

    for (int i = 0; i < len; i++) {
      final x = getX(i);
      final weekLabel = DateFormat('d/M').format(points[i].date);
      
      final textSpan = TextSpan(text: weekLabel, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(x - (textPainter.width / 2), chartHeight + 8),
      );
    }

    // 4. Draw hover highlights
    if (hoveredIndex != null) {
      final hIdx = hoveredIndex!;
      final hX = getX(hIdx);

      // Draw vertical reference line
      final linePaintRef = Paint()
        ..color = DS.neutral.withValues(alpha: 0.25)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(hX, 0), Offset(hX, chartHeight), linePaintRef);

      _drawHoverCircle(canvas, hX, getYMoney(points[hIdx].donations.toDouble()), donColor);
      _drawHoverCircle(canvas, hX, getYMoney(points[hIdx].patientsRevenue.toDouble()), accentColor);
      _drawHoverCircle(canvas, hX, getYTokens(points[hIdx].tokens.toDouble()), tokColor);
      _drawHoverCircle(canvas, hX, getYEmployees(points[hIdx].employeesPresent.toDouble()), empColor);
    }
  }

  void _drawLine(Canvas canvas, List<double> values, Color color, double stepX, double height, double maxLimit) {
    final path = Path();
    final fillPath = Path();

    double getY(double val) {
      final ratio = val / maxLimit;
      return height - (ratio * height);
    }

    path.moveTo(0, getY(values[0]));
    fillPath.moveTo(0, height);
    fillPath.lineTo(0, getY(values[0]));

    for (int i = 0; i < values.length - 1; i++) {
      final x1 = i * stepX;
      final y1 = getY(values[i]);
      final x2 = (i + 1) * stepX;
      final y2 = getY(values[i + 1]);
      final cx = (x1 + x2) / 2;

      path.cubicTo(cx, y1, cx, y2, x2, y2);
      fillPath.cubicTo(cx, y1, cx, y2, x2, y2);
    }

    fillPath.lineTo((values.length - 1) * stepX, height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, (values.length - 1) * stepX, height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
  }

  void _drawHoverCircle(Canvas canvas, double x, double y, Color color) {
    final circleOuter = Paint()..color = color.withValues(alpha: 0.25);
    canvas.drawCircle(Offset(x, y), 7.0, circleOuter);

    final circleInner = Paint()..color = color;
    canvas.drawCircle(Offset(x, y), 3.5, circleInner);
  }

  @override
  bool shouldRepaint(_MultiLineChartPainter oldDelegate) =>
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.maxMoney != maxMoney ||
      oldDelegate.maxTokens != maxTokens ||
      oldDelegate.maxEmployees != maxEmployees;
}

// ════════════════════════════════════════════════════════════════════════
// 6. Patients by Branch Horizontal Bar Chart
// ════════════════════════════════════════════════════════════════════════

class HomePatientsByBranchBarChart extends StatelessWidget {
  final RoleThemeData t;
  final List<HomeBranchRow> rows;
  const HomePatientsByBranchBarChart({super.key, required this.t, required this.rows});

  @override
  Widget build(BuildContext context) {
    final sortedRows = List<HomeBranchRow>.from(rows)
      ..sort((a, b) => b.today.tokens.compareTo(a.today.tokens));

    final maxTokens = sortedRows.isEmpty
        ? 1
        : max(1, sortedRows.map((r) => r.today.tokens).reduce(max));
    final bool isDark = t.isDarkCanvas;

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: isDark ? t.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: isDark ? t.bgRule : DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Patients by Branch (Today)',
              style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: DS.s2),
          if (sortedRows.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No patient data today', style: TextStyle(color: DS.neutral, fontSize: 12)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: min(5, sortedRows.length),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final row = sortedRows[i];
                  final val = row.today.tokens;
                  final double pct = val / maxTokens;
                  
                  return Row(
                    children: [
                      // Branch name
                      SizedBox(
                        width: 110,
                        child: Text(
                          row.name,
                          style: TextStyle(color: isDark ? t.textSecondary : const Color(0xFF4B5563), fontSize: 11, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Bar
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: isDark ? t.bg : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: pct.clamp(0.02, 1.0),
                                  child: Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                                      ),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Value
                      SizedBox(
                        width: 24,
                        child: Text(
                          val.toString(),
                          style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w900),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 7. Recent Live Activity Feed
// ════════════════════════════════════════════════════════════════════════

class HomeRecentActivityFeed extends StatelessWidget {
  final List<RecentActivity> activities;
  final RoleThemeData t;
  final List<AppModule> availableModules;
  final void Function(AppModule) onOpenModule;

  const HomeRecentActivityFeed({
    super.key,
    required this.activities,
    required this.t,
    required this.availableModules,
    required this.onOpenModule,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = t.isDarkCanvas;

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: isDark ? t.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: isDark ? t.bgRule : DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Activity',
                  style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              InkWell(
                onTap: () {
                  final reportsModule = availableModules.firstWhere(
                    (m) => m.id == 'executive_dashboard',
                    orElse: () => availableModules.firstWhere((m) => m.id == 'branches'),
                  );
                  onOpenModule(reportsModule);
                },
                child: Text('View all', style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: DS.s2),
          if (activities.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No recent activity records', style: TextStyle(color: DS.neutral, fontSize: 12)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: min(4, activities.length),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final act = activities[i];
                  final isDon = act.type == 'donation';
                  final isToken = act.type == 'token';
                  
                  // Configure color and icons to match the mockup
                  Color iconColor = const Color(0xFF3B82F6); // Blue for Token/Default
                  IconData iconData = Icons.confirmation_number_rounded;
                  
                  if (isDon) {
                    iconColor = const Color(0xFF10B981); // Green for Donations
                    iconData = Icons.volunteer_activism_rounded;
                  } else if (act.type == 'reception' || act.title.contains('Register') || act.title.contains('Patient')) {
                    iconColor = const Color(0xFF8B5CF6); // Purple for Patient Register
                    iconData = Icons.person_add_rounded;
                  } else if (act.type == 'revenue' || act.title.contains('Revenue') || act.title.contains('Record')) {
                    iconColor = const Color(0xFFF59E0B); // Orange for Revenue
                    iconData = Icons.payments_rounded;
                  }

                  return InkWell(
                    onTap: () {
                      final targetModuleId = isDon ? 'donations' : (isToken ? 'token_generation' : 'executive_dashboard');
                      final module = availableModules.firstWhere(
                        (m) => m.id == targetModuleId,
                        orElse: () => availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                      );
                      onOpenModule(module);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              iconData,
                              color: iconColor,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  act.title,
                                  style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 11.5, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  act.subtitle,
                                  style: const TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('hh:mm a').format(act.timestamp),
                            style: const TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

}

// ════════════════════════════════════════════════════════════════════════
// 8. Quick Actions Row
// ════════════════════════════════════════════════════════════════════════

class QuickActionsRow extends StatelessWidget {
  final List<AppModule> availableModules;
  final RoleThemeData t;
  final void Function(AppModule) onOpenModule;

  const QuickActionsRow({
    super.key,
    required this.availableModules,
    required this.t,
    required this.onOpenModule,
  });

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> targetActions = [
      {'id': 'branches', 'label': 'Branches Summary', 'icon': Icons.store_outlined, 'color': const Color(0xFF0D9488)},
      {'id': 'employee_attendance', 'label': 'Staff Attendance', 'icon': Icons.badge_outlined, 'color': const Color(0xFF6366F1)},
      {'id': 'madrassa_attendance', 'label': 'Madrassa Attend.', 'icon': Icons.how_to_reg_rounded, 'color': const Color(0xFFEC4899)},
      {'id': 'madrassa_students', 'label': 'Madrassa Students', 'icon': Icons.groups_rounded, 'color': const Color(0xFF14B8A6)},
      {'id': 'school_attendance', 'label': 'School Students', 'icon': Icons.school_rounded, 'color': const Color(0xFF10B981)},
      {'id': 'school_teacher_attendance', 'label': 'School Faculty', 'icon': Icons.co_present_rounded, 'color': const Color(0xFF8B5CF6)},
      {'id': 'office_boy', 'label': 'Food Tokens', 'icon': Icons.room_service_rounded, 'color': const Color(0xFFF59E0B)},
      {'id': 'dasterkhwaan_inventory', 'label': 'Dasterkhawaan Stock', 'icon': Icons.inventory_2_outlined, 'color': const Color(0xFFD97706)},
      {'id': 'inventory', 'label': 'Med Inventory', 'icon': Icons.medication_liquid_rounded, 'color': const Color(0xFF0284C7)},
      {'id': 'finance', 'label': 'Finance & HR', 'icon': Icons.monetization_on_rounded, 'color': const Color(0xFFEF4444)},
      {'id': 'donations', 'label': 'Add Donation', 'icon': Icons.volunteer_activism_rounded, 'color': const Color(0xFF059669)},
      {'id': 'patients_registration', 'label': 'Add Patient', 'icon': Icons.person_add_rounded, 'color': const Color(0xFF7C3AED)},
    ];

    final activeActions = targetActions.where((action) {
      if (action['id'] == 'employee_attendance') {
        return availableModules.any((m) => m.id == 'finance');
      }
      if (action['id'] == 'madrassa_attendance' || action['id'] == 'madrassa_students' || action['id'] == 'add_student' || action['id'] == 'madrassa_report') {
        return availableModules.any((m) => m.id == 'madrassa');
      }
      if (action['id'] == 'school_attendance' || action['id'] == 'school_teacher_attendance' || action['id'] == 'school') {
        return availableModules.any((m) => m.id == 'school' || m.id == 'school_attendance' || m.id == 'school_teacher_attendance' || m.id == 'school_module');
      }
      return availableModules.any((m) => m.id == action['id'] || (action['id'] == 'patients_registration' && m.id == 'patient_register_standalone'));
    }).toList();

    final bool isDark = t.isDarkCanvas;

    return Container(
      padding: const EdgeInsets.all(DS.s2),
      decoration: BoxDecoration(
        color: isDark ? t.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: isDark ? t.bgRule : DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = MediaQuery.of(context).size.width > 900 ? 6 : (MediaQuery.of(context).size.width > 600 ? 4 : 3);
          final rowCount = (activeActions.length / crossAxisCount).ceil();
          final availableHeight = constraints.maxHeight - 36;
          final calcExtent = ((availableHeight - (rowCount - 1) * 8) / rowCount).clamp(54.0, 84.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick Actions',
                  style: TextStyle(color: isDark ? t.textPrimary : const Color(0xFF111827), fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              const SizedBox(height: DS.s2),
              Expanded(
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: calcExtent,
                  ),
                  itemCount: activeActions.length,
                  itemBuilder: (context, index) {
                    final action = activeActions[index];
                    final mainModuleId = (action['id'] == 'employee_attendance')
                        ? 'finance'
                        : ((action['id'] == 'madrassa_attendance' || action['id'] == 'madrassa_students' || action['id'] == 'add_student' || action['id'] == 'madrassa_report')
                            ? 'madrassa'
                            : ((action['id'] == 'school_attendance' || action['id'] == 'school_teacher_attendance' || action['id'] == 'school')
                                ? 'school_module'
                                : action['id']));
                    final baseModule = availableModules.firstWhere(
                      (m) => m.id == mainModuleId || (mainModuleId == 'patients_registration' && m.id == 'patient_register_standalone') || (mainModuleId == 'school_module' && (m.id == 'school_attendance' || m.id == 'school_teacher_attendance' || m.id == 'school_module')),
                      orElse: () => availableModules.firstWhere((m) => m.id == mainModuleId, orElse: () => availableModules.first),
                    );
                    
                    // Construct custom copy of the module with modified builder
                    var module = baseModule;
                    if (action['id'] == 'employee_attendance') {
                      module = baseModule.copyWith(
                        title: 'Employee Attendance',
                        builder: (context, data) => FinancePage(
                          branchId: data['branchId'] ?? 'all',
                          isAdmin: true,
                          initialTabIndex: 1,
                        ),
                      );
                    } else if (action['id'] == 'madrassa_students') {
                      module = baseModule.copyWith(
                        title: 'Madrassa Students',
                        builder: (context, data) {
                          final branchId = data['branchId'] ?? 'unknown';
                          final username = data['name'] ?? data['username'] ?? 'User';
                          final role = (data['role'] as String? ?? 'madrassa admin').toLowerCase();
                          final isAdmin = role.contains('admin') || role.contains('chairman') || role.contains('ceo') || role.contains('hq');
                          return MadrassaDashboard(
                            branchId: branchId,
                            username: username,
                            role: role,
                            isAdmin: isAdmin,
                            initialIndex: isAdmin ? 2 : 1,
                          );
                        },
                      );
                    } else if (action['id'] == 'madrassa_attendance') {
                      module = baseModule.copyWith(
                        title: 'Madrassa Attendance',
                        builder: (context, data) {
                          final branchId = data['branchId'] ?? 'unknown';
                          final username = data['name'] ?? data['username'] ?? 'User';
                          final role = (data['role'] as String? ?? 'madrassa admin').toLowerCase();
                          final isAdmin = role.contains('admin') || role.contains('chairman') || role.contains('ceo') || role.contains('hq');
                          return MadrassaDashboard(
                            branchId: branchId,
                            username: username,
                            role: role,
                            isAdmin: isAdmin,
                            initialIndex: isAdmin ? 1 : 0,
                          );
                        },
                      );
                    } else if (action['id'] == 'school_attendance') {
                      module = baseModule.copyWith(
                        title: 'School Student Attendance',
                        builder: (context, data) => SchoolDashboard(
                          branchId: data['branchId'] ?? 'all',
                          username: data['name'] ?? data['username'] ?? 'User',
                          role: data['role'] ?? 'School Admin',
                          initialTabIndex: 1,
                        ),
                      );
                    } else if (action['id'] == 'school_teacher_attendance') {
                      module = baseModule.copyWith(
                        title: 'School Faculty Attendance',
                        builder: (context, data) => SchoolDashboard(
                          branchId: data['branchId'] ?? 'all',
                          username: data['name'] ?? data['username'] ?? 'User',
                          role: data['role'] ?? 'School Admin',
                          initialTabIndex: 2,
                        ),
                      );
                    }
                    
                    final color = action['color'] as Color;

                    return InkWell(
                      onTap: () => onOpenModule(module),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: color.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(action['icon'] as IconData, color: color, size: 22),
                            const SizedBox(height: 4),
                            Flexible(
                              child: Text(
                                action['label'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 9. Snapshot Dashboard Data Model and Loader
// ════════════════════════════════════════════════════════════════════════

class SnapshotDashboardData {
  final BranchStats todayCombined;
  final BranchStats yesterdayCombined;
  final List<HomeBranchRow> branchRows;
  final List<HomeLineChartPoint> chartPoints;
  final List<RecentActivity> recentActivities;

  SnapshotDashboardData({
    required this.todayCombined,
    required this.yesterdayCombined,
    required this.branchRows,
    required this.chartPoints,
    required this.recentActivities,
  });
}

Future<SnapshotDashboardData> fetchSnapshotDashboardData(Map<String, dynamic> userData) async {
  final role = (userData['role'] as String? ?? 'unknown').toLowerCase().trim();
  final String userBranchId = (userData['branchId'] as String? ?? '').toLowerCase().trim();

  final isBranchScoped = (userBranchId.isNotEmpty && userBranchId != 'all' && userBranchId != 'global') ||
                         role == 'branch manager' || role == 'branch_manager' || role == 'bm' || role.contains('branch manager') || role == 'supervisor';

  final isGlobal = ['ceo', 'chairman', 'global user', 'global', 'global admin'].contains(role);
  final isFullExec = ['admin', 'global admin', 'ceo', 'chairman', 'global user', 'hq manager', 'hqmanager', 'hq_manager', 'hq'].contains(role);
  final isGlobalExec = (isGlobal || isFullExec) && !isBranchScoped;
  
  if (isGlobalExec) {
    // 1. Get all branch IDs
    final branchIds = await RecentActivityService.getAllBranchIdsAsync();
    
    // 2. Fetch today-vs-yesterday per branch
    final Map<String, TodayVsYesterday> statsMap = await fetchTodayVsYesterdayPerBranch(branchIds);
    
    // 3. Build branch/camp rows for table
    final List<HomeBranchRow> branchRows = [];
    final List<BranchStats> todayStatsList = [];
    final List<BranchStats> yesterdayStatsList = [];
    
    final karachiCamps = await fetchKarachiCampBreakdown();

    statsMap.forEach((bId, value) {
      if (bId == 'karachi') {
        branchRows.add(HomeBranchRow(
          id: 'karachi_haji',
          name: 'Karachi — Haji Camp Dispensary',
          today: BranchStats(
            zakat: karachiCamps.hajiCampZakat,
            nonZakat: karachiCamps.hajiCampNonZakat,
            gmwf: karachiCamps.hajiCampGmwf,
            prescribed: value.today.prescribed,
            dispensaryRevenue: karachiCamps.hajiCampRevenue,
            donations: 0,
          ),
          yesterday: value.yesterday,
        ));

        branchRows.add(HomeBranchRow(
          id: 'karachi_kapaya',
          name: 'Karachi — Kapaya Dispensary',
          today: BranchStats(
            zakat: karachiCamps.kapayaZakat,
            nonZakat: karachiCamps.kapayaNonZakat,
            gmwf: karachiCamps.kapayaGmwf,
            prescribed: value.today.prescribed,
            dispensaryRevenue: karachiCamps.kapayaRevenue,
            donations: value.today.donations,
          ),
          yesterday: value.yesterday,
        ));
      } else {
        final bName = RecentActivityService.resolveBranchName(bId);
        branchRows.add(HomeBranchRow(
          id: bId,
          name: bName,
          today: value.today,
          yesterday: value.yesterday,
        ));
      }
      todayStatsList.add(value.today);
      yesterdayStatsList.add(value.yesterday);
    });
    
    // Aggregate overall today and yesterday stats
    final todayCombined = combineBranchStats(todayStatsList);
    final yesterdayCombined = combineBranchStats(yesterdayStatsList);
    
    // 4. Fetch 7-day chart points
    final chartPoints = await fetchChartPoints(branchIds, weeks: 5);
    
    // 5. Fetch recent activity (cross-branch)
    final recentActivities = await RecentActivityService.getRecentActivityAsync(limit: 15);
    
    return SnapshotDashboardData(
      todayCombined: todayCombined,
      yesterdayCombined: yesterdayCombined,
      branchRows: branchRows,
      chartPoints: chartPoints,
      recentActivities: recentActivities,
    );
  } else {
    // Branch-locked role
    final String branchId = userBranchId.isNotEmpty ? userBranchId : 'karachi';
    
    // 1. Fetch today vs yesterday stats for this single branch
    final todayStats = await fetchBranchStats(branchId);
    final yesterdayStats = await fetchHistoricalDayStats(branchId, DateTime.now().subtract(const Duration(days: 1)));
    
    // 2. Build branchRows for single branch/camps
    final List<HomeBranchRow> branchRows = [];
    if (branchId == 'karachi') {
      final karachiCamps = await fetchKarachiCampBreakdown();
      branchRows.add(HomeBranchRow(
        id: 'karachi_haji',
        name: 'Karachi — Haji Camp Dispensary',
        today: BranchStats(
          zakat: karachiCamps.hajiCampZakat,
          nonZakat: karachiCamps.hajiCampNonZakat,
          gmwf: karachiCamps.hajiCampGmwf,
          prescribed: todayStats.prescribed,
          dispensaryRevenue: karachiCamps.hajiCampRevenue,
          donations: 0,
        ),
        yesterday: yesterdayStats,
      ));

      branchRows.add(HomeBranchRow(
        id: 'karachi_kapaya',
        name: 'Karachi — Kapaya Dispensary',
        today: BranchStats(
          zakat: karachiCamps.kapayaZakat,
          nonZakat: karachiCamps.kapayaNonZakat,
          gmwf: karachiCamps.kapayaGmwf,
          prescribed: todayStats.prescribed,
          dispensaryRevenue: karachiCamps.kapayaRevenue,
          donations: todayStats.donations,
        ),
        yesterday: yesterdayStats,
      ));
    } else {
      final bName = RecentActivityService.resolveBranchName(branchId);
      branchRows.add(HomeBranchRow(
        id: branchId,
        name: bName,
        today: todayStats,
        yesterday: yesterdayStats,
      ));
    }
    
    // 3. Fetch 7-day chart points
    final chartPoints = await fetchChartPoints([branchId], weeks: 5);
    
    // 4. Fetch recent activity (branch-locked)
    final recentActivities = await RecentActivityService.getRecentActivityAsync(branchId: branchId, limit: 15);
    
    return SnapshotDashboardData(
      todayCombined: todayStats,
      yesterdayCombined: yesterdayStats,
      branchRows: branchRows,
      chartPoints: chartPoints,
      recentActivities: recentActivities,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 10. Home Snapshot Dashboard (Today-Only Widget)
// ════════════════════════════════════════════════════════════════════════

class _DashboardUserKey {
  final String uid;
  final String role;
  final String branchId;
  final Map<String, dynamic> userData;

  const _DashboardUserKey({
    required this.uid,
    required this.role,
    required this.branchId,
    required this.userData,
  });

  factory _DashboardUserKey.fromMap(Map<String, dynamic> map) {
    return _DashboardUserKey(
      uid: (map['uid'] ?? '').toString(),
      role: (map['role'] ?? '').toString().toLowerCase().trim(),
      branchId: (map['branchId'] ?? '').toString().toLowerCase().trim(),
      userData: map,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DashboardUserKey &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          role == other.role &&
          branchId == other.branchId;

  @override
  int get hashCode => uid.hashCode ^ role.hashCode ^ branchId.hashCode;
}

final snapshotDashboardDataProvider = FutureProvider.family<SnapshotDashboardData, _DashboardUserKey>((ref, key) async {
  return fetchSnapshotDashboardData(key.userData);
});

class HomeSnapshotDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic> userData;
  final RoleThemeData t;
  final List<AppModule> availableModules;
  final void Function(AppModule) onOpenModule;
  final bool isDesktop;
  final VoidCallback onViewReports;

  const HomeSnapshotDashboard({
    super.key,
    required this.userData,
    required this.t,
    required this.availableModules,
    required this.onOpenModule,
    required this.isDesktop,
    required this.onViewReports,
  });

  @override
  ConsumerState<HomeSnapshotDashboard> createState() => _HomeSnapshotDashboardState();
}

class _HomeSnapshotDashboardState extends ConsumerState<HomeSnapshotDashboard> {
  _DashboardUserKey get _userKey => _DashboardUserKey.fromMap(widget.userData);

  void _refresh() {
    ref.invalidate(snapshotDashboardDataProvider(_userKey));
  }

  @override
  Widget build(BuildContext context) {
    final double hPad = widget.isDesktop ? 36 : 20;

    final asyncData = ref.watch(snapshotDashboardDataProvider(_userKey));

    return asyncData.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 80.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, stack) => Padding(
        padding: EdgeInsets.all(hPad),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text('Failed to load snapshot dashboard: $err',
                  style: const TextStyle(color: DS.neutral, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        final today = data.todayCombined;
        final yesterday = data.yesterdayCombined;

        // Build the stat tiles with direct navigation & accurate count logic
        void tryOpenModule(String id) {
          final String mainModuleId = (id == 'employee_attendance')
              ? 'finance'
              : ((id == 'madrassa_attendance' || id == 'madrassa_students' || id == 'madrassa_report')
                  ? 'madrassa'
                  : ((id == 'school_attendance' || id == 'school_teacher_attendance')
                      ? 'school_module'
                      : id));

          final baseModule = widget.availableModules.firstWhere(
            (m) => m.id == mainModuleId || (mainModuleId == 'patients_list' && m.id == 'patient_register_standalone') || (mainModuleId == 'school_module' && (m.id == 'school_attendance' || m.id == 'school_teacher_attendance' || m.id == 'school_module')),
            orElse: () => ModuleRegistry.allModules.firstWhere((m) => m.id == mainModuleId, orElse: () => ModuleRegistry.allModules.first),
          );

          var module = baseModule;
          if (id == 'employee_attendance') {
            module = baseModule.copyWith(
              title: 'Employee Attendance',
              builder: (context, data) => FinancePage(
                branchId: data['branchId'] ?? 'all',
                isAdmin: true,
                initialTabIndex: 1,
              ),
            );
          } else if (id == 'madrassa_attendance') {
            module = baseModule.copyWith(
              title: 'Madrassa Daily Log',
              builder: (context, data) => MadrassaDashboard(
                branchId: data['branchId'] ?? 'all',
                username: data['name'] ?? data['username'] ?? 'User',
                role: data['role'] ?? 'Admin',
                initialIndex: 1,
              ),
            );
          } else if (id == 'madrassa_students') {
            module = baseModule.copyWith(
              title: 'Madrassa Students',
              builder: (context, data) => MadrassaDashboard(
                branchId: data['branchId'] ?? 'all',
                username: data['name'] ?? data['username'] ?? 'User',
                role: data['role'] ?? 'Admin',
                initialIndex: 2,
              ),
            );
          } else if (id == 'school_attendance') {
            module = baseModule.copyWith(
              title: 'School Student Attendance',
              builder: (context, data) => SchoolDashboard(
                branchId: data['branchId'] ?? 'all',
                username: data['name'] ?? data['username'] ?? 'User',
                role: data['role'] ?? 'School Admin',
                initialTabIndex: 1,
              ),
            );
          } else if (id == 'school_teacher_attendance') {
            module = baseModule.copyWith(
              title: 'School Faculty Attendance',
              builder: (context, data) => SchoolDashboard(
                branchId: data['branchId'] ?? 'all',
                username: data['name'] ?? data['username'] ?? 'User',
                role: data['role'] ?? 'School Admin',
                initialTabIndex: 2,
              ),
            );
          } else if (id == 'users') {
            module = baseModule.id == 'users'
                ? baseModule
                : AppModule(
                    id: 'users',
                    title: 'User Management',
                    description: 'Manage system users, roles, and online presence',
                    icon: Icons.people_alt_rounded,
                    category: ModuleCategory.office,
                    builder: (context, data) => UsersScreen(
                      branchId: data['branchId'] ?? 'all',
                      currentUserRole: data['role']?.toString() ?? 'chairman',
                    ),
                  );
          }
          widget.onOpenModule(module);
        }

        final donationsTile = HomeStatTile(
          label: 'Donations Today',
          value: fmtNum(today.donations),
          prefix: 'Rs ',
          icon: Icons.volunteer_activism_rounded,
          color: const Color(0xFF10B981),
          deltaPct: yesterday.donations == 0 ? null : ((today.donations - yesterday.donations) / yesterday.donations) * 100,
          onTap: () => tryOpenModule('donations'),
        );

        final patientsTile = HomeStatTile(
          label: 'Patients Today',
          value: fmtNum(today.zakat + today.nonZakat + today.gmwf),
          icon: Icons.people_alt_rounded,
          color: const Color(0xFF8B5CF6),
          deltaPct: (yesterday.zakat + yesterday.nonZakat + yesterday.gmwf) == 0 
              ? null 
              : (((today.zakat + today.nonZakat + today.gmwf) - (yesterday.zakat + yesterday.nonZakat + yesterday.gmwf)) / 
                 (yesterday.zakat + yesterday.nonZakat + yesterday.gmwf)) * 100,
          onTap: () => tryOpenModule('patients_list'),
        );



        // overallRevTile removed per request

        final madrassaTile = HomeStatTile(
          label: 'Madrassa Attendance',
          value: fmtNum(today.prescribed),
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF0D9488),
          deltaPct: yesterday.prescribed == 0 ? null : ((today.prescribed - yesterday.prescribed) / yesterday.prescribed) * 100,
          onTap: () => tryOpenModule('madrassa_attendance'),
        );

        final todayDateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
        int empPresentCount = 0;
        try {
          if (Hive.isBoxOpen(LocalStorageService.attendanceBox)) {
            final box = Hive.box(LocalStorageService.attendanceBox);
            for (final key in box.keys) {
              final keyStr = key.toString();
              if (keyStr.endsWith('_$todayDateKey') || keyStr.endsWith(todayDateKey)) {
                final val = box.get(key);
                if (val is Map) {
                  final status = val['status']?.toString().toLowerCase();
                  if (status == 'present' || status == 'late' || status == 'overtime') {
                    empPresentCount++;
                  }
                }
              }
            }
          }
        } catch (_) {}

        final employeeAttendanceTile = HomeStatTile(
          label: 'Employee Attendance',
          value: fmtNum(empPresentCount),
          icon: Icons.co_present_rounded,
          color: const Color(0xFF3F82F6),
          onTap: () => tryOpenModule('employee_attendance'),
        );

        final studentPresentCount = SchoolLocalStorage.getPresentStudentsCount('all', todayDateKey);
        final teacherPresentCount = SchoolLocalStorage.getPresentTeachersCount('all', todayDateKey);

        final schoolStudentsTile = HomeStatTile(
          label: 'School Students',
          value: fmtNum(studentPresentCount),
          icon: Icons.school_rounded,
          color: const Color(0xFF10B981),
          onTap: () => tryOpenModule('school_attendance'),
        );

        final schoolTeachersTile = HomeStatTile(
          label: 'School Teachers',
          value: fmtNum(teacherPresentCount),
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: () => tryOpenModule('school_teacher_attendance'),
        );

        int onlineUsersCount = 1;
        try {
          if (Hive.isBoxOpen(LocalStorageService.usersBox)) {
            final uBox = Hive.box(LocalStorageService.usersBox);
            int count = 0;
            for (final u in uBox.values) {
              if (u is Map) {
                final isOnline = u['isOnline'] == true;
                final rawDate = u['lastOnlineAt'] ?? u['lastLoginAt'] ?? u['updatedAt'];
                bool recent = false;
                if (rawDate is String && rawDate.isNotEmpty) {
                  final dt = DateTime.tryParse(rawDate);
                  if (dt != null && DateTime.now().difference(dt).inMinutes <= 15) recent = true;
                }
                if (isOnline || recent) count++;
              }
            }
            if (count > 0) onlineUsersCount = count;
          }
        } catch (_) {}

        final onlineUsersTile = HomeStatTile(
          label: 'Online Users',
          value: fmtNum(onlineUsersCount),
          icon: Icons.wifi_tethering_rounded,
          color: const Color(0xFF06B6D4),
          onTap: () => tryOpenModule('users'),
        );

        final userRoleStr = (widget.userData['role'] as String? ?? '').toLowerCase().trim();
        final isBranchManager = userRoleStr == 'branch manager' || userRoleStr == 'branch_manager' || userRoleStr.contains('branch manager');
        final userBranchId = (widget.userData['branchId'] as String? ?? '').toLowerCase().trim();

        // Filter and sort branch rows by performance today
        final activeBranchRows = data.branchRows.where((row) {
          final pats = row.today.zakat + row.today.nonZakat + row.today.gmwf;
          return row.today.donations > 0 || pats > 0 || row.today.dispensaryRevenue > 0;
        }).toList();

        final displayBranchRows = activeBranchRows.isNotEmpty ? activeBranchRows : data.branchRows;

        final sortedBranchRows = List<HomeBranchRow>.from(displayBranchRows)
          ..sort((a, b) {
            final aPats = a.today.zakat + a.today.nonZakat + a.today.gmwf;
            final bPats = b.today.zakat + b.today.nonZakat + b.today.gmwf;
            final aScore = a.today.donations + a.today.dispensaryRevenue + aPats * 100;
            final bScore = b.today.donations + b.today.dispensaryRevenue + bPats * 100;
            if (bScore != aScore) {
              return bScore.compareTo(aScore);
            }
            return a.name.compareTo(b.name);
          });

        HomeBranchRow? bestBranch;
        if (sortedBranchRows.isNotEmpty && !isBranchManager) {
          final top = sortedBranchRows.first;
          final pats = top.today.zakat + top.today.nonZakat + top.today.gmwf;
          if (top.today.donations > 0 || pats > 0 || top.today.dispensaryRevenue > 0) {
            bestBranch = top;
          }
        }

        final topRow = sortedBranchRows.isNotEmpty ? sortedBranchRows.first : null;

        final activeBranchTile = HomeStatTile(
          label: isBranchManager ? (userBranchId.contains('karachi') ? 'Top Camp Today' : 'Active Branch') : 'Top Branch Today',
          value: topRow != null ? topRow.name : RecentActivityService.resolveBranchName(userBranchId.isNotEmpty ? userBranchId : 'Karachi'),
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFF0D9488),
          onTap: () => tryOpenModule('branches'),
        );

        final branchesSummaryTile = HomeStatTile(
          label: 'Top Branch Today',
          value: topRow != null ? topRow.name : (bestBranch != null ? bestBranch.name : 'Karachi'),
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFF0D9488),
          onTap: () => tryOpenModule('branches'),
        );

        final dasterkhwaanTokensTile = HomeStatTile(
          label: 'Dasterkhawaan Tokens',
          value: 'Tokens',
          icon: Icons.room_service_rounded,
          color: const Color(0xFFF59E0B),
          onTap: () => tryOpenModule('office_boy'),
        );

        final dasterkhwaanStockTile = HomeStatTile(
          label: 'Dasterkhawaan Stock',
          value: 'Stock',
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFFD97706),
          onTap: () => tryOpenModule('dasterkhwaan_inventory'),
        );

        final List<HomeStatTile> statTiles = [
          if (!isBranchManager) branchesSummaryTile else activeBranchTile,
          donationsTile,
          patientsTile,
          madrassaTile,
          employeeAttendanceTile,
          schoolStudentsTile,
          schoolTeachersTile,
          dasterkhwaanTokensTile,
          dasterkhwaanStockTile,
          onlineUsersTile,
        ];

        // Layout rows
        final row2 = SizedBox(
          height: 380,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: HomeRevenueLineChart(points: data.chartPoints, t: widget.t)),
              const SizedBox(width: DS.s2),
              Expanded(flex: 3, child: HomePatientsByBranchBarChart(t: widget.t, rows: data.branchRows)),
              const SizedBox(width: DS.s2),
              Expanded(
                flex: 3,
                child: HomeRecentActivityFeed(
                  activities: data.recentActivities,
                  t: widget.t,
                  availableModules: widget.availableModules,
                  onOpenModule: widget.onOpenModule,
                ),
              ),
            ],
          ),
        );

        final row3 = SizedBox(
          height: 360,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: HomePatientsByCategoryDonut(t: widget.t, s: today)),
              const SizedBox(width: DS.s2),
              Expanded(
                flex: 5,
                child: HomeBranchPerformanceTable(
                  t: widget.t,
                  rows: sortedBranchRows,
                  onTapBranch: (bId) {
                    final branchesModule = widget.availableModules.firstWhere(
                      (m) => m.id == 'branches',
                      orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                    );
                    widget.onOpenModule(branchesModule);
                  },
                ),
              ),
              if (bestBranch != null) ...[
                const SizedBox(width: DS.s2),
                Expanded(
                  flex: 4,
                  child: HomeBestBranchSpotlight(
                    branchName: bestBranch.name,
                    revenue: bestBranch.today.dispensaryRevenue,
                    donations: bestBranch.today.donations,
                    patients: bestBranch.today.zakat + bestBranch.today.nonZakat + bestBranch.today.gmwf,
                    growthPct: bestBranch.yesterday.dispensaryRevenue == 0
                        ? null
                        : ((bestBranch.today.dispensaryRevenue - bestBranch.yesterday.dispensaryRevenue) /
                                bestBranch.yesterday.dispensaryRevenue) *
                            100,
                    onTap: () {
                      final branchesModule = widget.availableModules.firstWhere(
                        (m) => m.id == 'branches',
                        orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                      );
                      widget.onOpenModule(branchesModule);
                    },
                    t: widget.t,
                  ),
                ),
              ],
            ],
          ),
        );

        final row4 = SizedBox(
          height: 295,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: HomeRecentDonationsTable(activities: data.recentActivities, t: widget.t)),
              const SizedBox(width: DS.s2),
              Expanded(flex: 4, child: HomeRecentPatientsTable(activities: data.recentActivities, t: widget.t)),
              const SizedBox(width: DS.s2),
              Expanded(flex: 3, child: QuickActionsRow(
                availableModules: widget.availableModules,
                t: widget.t,
                onOpenModule: widget.onOpenModule,
              )),
            ],
          ),
        );

        final roleStr = (widget.userData['role'] ?? widget.userData['userRole'] ?? '').toString().toLowerCase();
        final isGlobalExecutive = roleStr.contains('ceo') || roleStr.contains('chairman') || roleStr.contains('hq') || roleStr.contains('global');

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today\'s Snapshot',
                    style: TextStyle(
                      color: widget.t.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              if (widget.isDesktop) ...[
                HomeStatTileRow(tiles: statTiles),
                const SizedBox(height: DS.s3),
                row3,
                const SizedBox(height: DS.s3),
                if (!isGlobalExecutive) ...[
                  KarachiCampSnapshotWidget(t: widget.t),
                  const SizedBox(height: DS.s3),
                ],
                row2,
                const SizedBox(height: DS.s3),
                row4,
                if (isGlobalExecutive) ...[
                  const SizedBox(height: DS.s3),
                  KarachiCampSnapshotWidget(t: widget.t),
                ],
              ] else ...[
                SizedBox(
                  height: 270,
                  child: QuickActionsRow(
                    availableModules: widget.availableModules,
                    t: widget.t,
                    onOpenModule: widget.onOpenModule,
                  ),
                ),
                const SizedBox(height: DS.s2),
                HomeStatTileRow(tiles: statTiles),
                const SizedBox(height: DS.s2),
                if (!isGlobalExecutive) ...[
                  KarachiCampSnapshotWidget(t: widget.t),
                  const SizedBox(height: DS.s2),
                ],
                if (bestBranch != null) ...[
                  HomeBestBranchSpotlight(
                    branchName: bestBranch.name,
                    revenue: bestBranch.today.dispensaryRevenue,
                    donations: bestBranch.today.donations,
                    patients: bestBranch.today.zakat + bestBranch.today.nonZakat + bestBranch.today.gmwf,
                    growthPct: bestBranch.yesterday.dispensaryRevenue == 0
                        ? null
                        : ((bestBranch.today.dispensaryRevenue - bestBranch.yesterday.dispensaryRevenue) /
                                bestBranch.yesterday.dispensaryRevenue) *
                            100,
                    onTap: () {
                      final branchesModule = widget.availableModules.firstWhere(
                        (m) => m.id == 'branches',
                        orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                      );
                      widget.onOpenModule(branchesModule);
                    },
                    t: widget.t,
                  ),
                  const SizedBox(height: DS.s2),
                ],
                SizedBox(height: 240, child: HomePatientsByCategoryDonut(t: widget.t, s: today)),
                const SizedBox(height: DS.s2),
                HomeBranchPerformanceTable(
                  t: widget.t,
                  rows: sortedBranchRows,
                  onTapBranch: (bId) {
                    final branchesModule = widget.availableModules.firstWhere(
                      (m) => m.id == 'branches',
                      orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                    );
                    widget.onOpenModule(branchesModule);
                  },
                ),
                const SizedBox(height: DS.s2),
                HomeRevenueLineChart(points: data.chartPoints, t: widget.t),
                const SizedBox(height: DS.s2),
                SizedBox(height: 240, child: HomePatientsByBranchBarChart(t: widget.t, rows: data.branchRows)),
                const SizedBox(height: DS.s2),
                if (isGlobalExecutive) ...[
                  KarachiCampSnapshotWidget(t: widget.t),
                  const SizedBox(height: DS.s2),
                ],
                const SizedBox(height: DS.s2),
                if (bestBranch != null) ...[
                  HomeBestBranchSpotlight(
                    branchName: bestBranch.name,
                    revenue: bestBranch.today.dispensaryRevenue,
                    donations: bestBranch.today.donations,
                    patients: bestBranch.today.zakat + bestBranch.today.nonZakat + bestBranch.today.gmwf,
                    growthPct: bestBranch.yesterday.dispensaryRevenue == 0
                        ? null
                        : ((bestBranch.today.dispensaryRevenue - bestBranch.yesterday.dispensaryRevenue) /
                                bestBranch.yesterday.dispensaryRevenue) *
                            100,
                    onTap: () {
                      final branchesModule = widget.availableModules.firstWhere(
                        (m) => m.id == 'branches',
                        orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                      );
                      widget.onOpenModule(branchesModule);
                    },
                    t: widget.t,
                  ),
                  const SizedBox(height: DS.s2),
                ],
                SizedBox(height: 240, child: HomePatientsByCategoryDonut(t: widget.t, s: today)),
                const SizedBox(height: DS.s2),
                HomeBranchPerformanceTable(
                  t: widget.t,
                  rows: sortedBranchRows,
                  onTapBranch: (bId) {
                    final branchesModule = widget.availableModules.firstWhere(
                      (m) => m.id == 'branches',
                      orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                    );
                    widget.onOpenModule(branchesModule);
                  },
                ),
                const SizedBox(height: DS.s2),
                HomeRevenueLineChart(points: data.chartPoints, t: widget.t),
                const SizedBox(height: DS.s2),
                SizedBox(height: 240, child: HomePatientsByBranchBarChart(t: widget.t, rows: data.branchRows)),
                const SizedBox(height: DS.s2),
                SizedBox(
                  height: 330,
                  child: HomeRecentActivityFeed(
                    activities: data.recentActivities,
                    t: widget.t,
                    availableModules: widget.availableModules,
                    onOpenModule: widget.onOpenModule,
                  ),
                ),
                const SizedBox(height: DS.s2),
                HomeRecentDonationsTable(activities: data.recentActivities, t: widget.t),
                const SizedBox(height: DS.s2),
                HomeRecentPatientsTable(activities: data.recentActivities, t: widget.t),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 10. Karachi Dual-Camp Live Snapshot Widget
// ════════════════════════════════════════════════════════════════════════

class KarachiCampSnapshotWidget extends StatefulWidget {
  final RoleThemeData t;
  const KarachiCampSnapshotWidget({super.key, required this.t});

  @override
  State<KarachiCampSnapshotWidget> createState() => _KarachiCampSnapshotWidgetState();
}

class _KarachiCampSnapshotWidgetState extends State<KarachiCampSnapshotWidget> {
  late Future<KarachiCampBreakdown> _breakdownFuture;

  @override
  void initState() {
    super.initState();
    _breakdownFuture = fetchKarachiCampBreakdown();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.t.isDarkCanvas;
    return FutureBuilder<KarachiCampBreakdown>(
      future: _breakdownFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const KarachiCampBreakdown(
          hajiCampPatients: 0, hajiCampZakat: 0, hajiCampNonZakat: 0, hajiCampGmwf: 0,
          kapayaPatients: 0, kapayaZakat: 0, kapayaNonZakat: 0, kapayaGmwf: 0,
        );

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.t.bgCard,
            borderRadius: BorderRadius.circular(DS.r2),
            border: Border.all(color: widget.t.bgRule),
            boxShadow: Neumorphic3DStyle.raisedShadows(isDark: isDark, depth: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_city_rounded, color: Color(0xFF0D9488), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Karachi Branch — Dual Dispensary Camps Breakdown',
                        style: TextStyle(
                          color: widget.t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Combined: ${data.totalPatients} Patients Today',
                      style: const TextStyle(
                        color: Color(0xFF0D9488),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildCampCard(
                      title: 'Kapaya Dispensary',
                      total: data.kapayaPatients,
                      revenue: data.kapayaRevenue,
                      zakat: data.kapayaZakat,
                      nonZakat: data.kapayaNonZakat,
                      gmwf: data.kapayaGmwf,
                      morningTotal: data.kapayaMorningPatients,
                      morningZakat: data.kapayaMorningZakat,
                      morningNonZakat: data.kapayaMorningNonZakat,
                      morningGmwf: data.kapayaMorningGmwf,
                      eveningTotal: data.kapayaEveningPatients,
                      eveningZakat: data.kapayaEveningZakat,
                      eveningNonZakat: data.kapayaEveningNonZakat,
                      eveningGmwf: data.kapayaEveningGmwf,
                      badgeColor: const Color(0xFF7C3AED),
                      icon: Icons.local_hospital_rounded,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCampCard(
                      title: 'Haji Camp Dispensary',
                      total: data.hajiCampPatients,
                      revenue: data.hajiCampRevenue,
                      zakat: data.hajiCampZakat,
                      nonZakat: data.hajiCampNonZakat,
                      gmwf: data.hajiCampGmwf,
                      morningTotal: data.hajiCampMorningPatients,
                      morningZakat: data.hajiCampMorningZakat,
                      morningNonZakat: data.hajiCampMorningNonZakat,
                      morningGmwf: data.hajiCampMorningGmwf,
                      eveningTotal: data.hajiCampEveningPatients,
                      eveningZakat: data.hajiCampEveningZakat,
                      eveningNonZakat: data.hajiCampEveningNonZakat,
                      eveningGmwf: data.hajiCampEveningGmwf,
                      badgeColor: const Color(0xFF2563EB),
                      icon: Icons.campaign_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCampCard({
    required String title,
    required int total,
    required int revenue,
    required int zakat,
    required int nonZakat,
    required int gmwf,
    required int morningTotal,
    required int morningZakat,
    required int morningNonZakat,
    required int morningGmwf,
    required int eveningTotal,
    required int eveningZakat,
    required int eveningNonZakat,
    required int eveningGmwf,
    required Color badgeColor,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: isDark ? 0.15 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: badgeColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$total Patients',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Rs $revenue',
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Morning Session Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wb_sunny_rounded, color: Colors.amber, size: 13),
                          SizedBox(width: 3),
                          Text(
                            'Morning',
                            style: TextStyle(color: Colors.amber, fontSize: 10.5, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$morningTotal Patients',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Z: $morningZakat   NZ: $morningNonZakat   G: $morningGmwf',
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade300 : const Color(0xFF475569),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(height: 1, color: Colors.black12),
                const SizedBox(height: 6),
                // Evening Session Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nights_stay_rounded, color: Colors.indigoAccent, size: 13),
                          SizedBox(width: 3),
                          Text(
                            'Evening',
                            style: TextStyle(color: Colors.indigoAccent, fontSize: 10.5, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$eveningTotal Patients',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Z: $eveningZakat   NZ: $eveningNonZakat   G: $eveningGmwf',
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade300 : const Color(0xFF475569),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Total category summary line
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Total Categories: ',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Zakat: $zakat | Non-Zakat: $nonZakat | GMWF: $gmwf',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}