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
import '../models/module_registry.dart';
import '../services/home_dashboard_service.dart';
import 'dashboard_widgets.dart';
import '../pages/office/finance_page.dart';
import '../pages/madrassa/madrassa_dashboard.dart';

// ════════════════════════════════════════════════════════════════════════
// 1. Compact stat tile w/ "vs yesterday" delta
// ════════════════════════════════════════════════════════════════════════

class HomeStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? prefix;
  final IconData icon;
  final Color color;
  final double? deltaPct; // null = no yesterday data ("New today")

  const HomeStatTile({
    super.key,
    required this.label,
    required this.value,
    this.prefix,
    required this.icon,
    required this.color,
    this.deltaPct,
  });

  @override
  Widget build(BuildContext context) {
    final hasDelta = deltaPct != null;
    final isUp = hasDelta && deltaPct! >= 0;
    final deltaColor = !hasDelta
        ? DS.neutral
        : (isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DS.s2, vertical: DS.s2 - 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(DS.r1)),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: DS.s1 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: DS.neutral, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (prefix != null)
                    Text(prefix!,
                        style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w700)),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: const TextStyle(
                              color: Color(0xFF111827), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(!hasDelta
                      ? Icons.fiber_new_rounded
                      : (isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                      size: 11, color: deltaColor),
                  const SizedBox(width: 2),
                  Text(!hasDelta ? 'New today' : '${deltaPct!.abs().toStringAsFixed(0)}% vs yesterday',
                      style: TextStyle(color: deltaColor, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeStatTileRow extends StatelessWidget {
  final List<HomeStatTile> tiles;
  const HomeStatTileRow({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(
          children: tiles.map((tile) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: tile,
            ),
          )).toList(),
        );
      }
      final cols = c.maxWidth < 480 ? 2 : 3;
      return GridView.count(
        crossAxisCount: cols,
        crossAxisSpacing: DS.s2,
        mainAxisSpacing: DS.s2,
        childAspectRatio: cols == 2 ? 1.6 : 1.5,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: tiles,
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
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 6;
    const strokeW = 34.0;
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

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Patients by Category',
            style: TextStyle(color: Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: DS.s2),
        if (total == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No patients yet today', style: TextStyle(color: DS.neutral, fontSize: 12))),
          )
        else
          LayoutBuilder(builder: (context, c) {
            final isWide = c.maxWidth >= 420;
            final donut = _FlatAnimatedDonut(
              size: isWide ? 150 : 130,
              values: [s.zakat.toDouble(), s.nonZakat.toDouble(), s.gmwf.toDouble()],
              colors: [t.zakat, t.nonZakat, t.gmwf],
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$total', style: TextStyle(color: t.textPrimary, fontSize: 24, fontWeight: FontWeight.w900)),
                const Text('patients', style: TextStyle(color: DS.neutral, fontSize: 11)),
              ]),
            );
            final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _flatLegendRow(t.zakat, 'Zakat', s.zakat, zPct),
              const SizedBox(height: 10),
              _flatLegendRow(t.nonZakat, 'Non-Zakat', s.nonZakat, nPct),
              const SizedBox(height: 10),
              _flatLegendRow(t.gmwf, 'GMWF', s.gmwf, gPct),
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
        Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF374151), fontSize: 12, fontWeight: FontWeight.w600))),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Branch Performance Today',
              style: TextStyle(color: Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: DS.s2),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: DS.border, width: 1.0)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('Branch', style: TextStyle(color: DS.neutral, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
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
                child: Text('No branches to show', style: TextStyle(color: DS.neutral, fontSize: 12)),
              ),
            )
          else
            ...rows.take(5).toList().asMap().entries.map((e) {
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

              return InkWell(
                onTap: onTapBranch != null ? () => onTapBranch!(row.id) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: DS.border, width: 0.5)),
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
                                style: const TextStyle(color: Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w700),
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
                              Text(fmtNum(don), style: const TextStyle(color: Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800)),
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
                              Text(fmtNum(pats), style: const TextStyle(color: Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800)),
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
                              Text(fmtNum(rev), style: const TextStyle(color: Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800)),
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

  const HomeBestBranchSpotlight({
    super.key,
    required this.branchName,
    required this.revenue,
    required this.donations,
    required this.patients,
    required this.growthPct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasGrowth = growthPct != null;
    final isUp = hasGrowth && growthPct! >= 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF115E59)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(DS.r2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F766E).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
                // Trophy icon with glow
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFFFBBF24),
                    size: 36,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24, height: 1),
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
              valueColor: hasGrowth ? (isUp ? const Color(0xFF34D399) : const Color(0xFFF87171)) : Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(IconData icon, String label, String value, {Color valueColor = Colors.white}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
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
    
    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patients by Category',
              style: TextStyle(color: Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
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
                                    style: const TextStyle(
                                      color: Color(0xFF111827),
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
                  style: const TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w900),
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

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
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
              const Text('Recent Donations',
                  style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              Text('View all', style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: DS.s2),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: DS.border, width: 1.0))),
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
              final donorName = match?.group(1)?.trim() ?? 'Anonymous';
              final amt = a.amount ?? 0.0;
              final timeStr = DateFormat('hh:mm a').format(a.timestamp);

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: DS.border, width: 0.5))),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(donorName, style: const TextStyle(color: Color(0xFF111827), fontSize: 11.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
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

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
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
              const Text('Recent Patients',
                  style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              Text('View all', style: TextStyle(color: t.accent, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: DS.s2),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: DS.border, width: 1.0))),
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

              Color badgeBg = const Color(0xFFECFDF5);
              Color badgeText = const Color(0xFF047857);
              if (category.toLowerCase() == 'non-zakat') {
                badgeBg = const Color(0xFFEFF6FF);
                badgeText = const Color(0xFF1D4ED8);
              } else if (category.toLowerCase() == 'gmwf') {
                badgeBg = const Color(0xFFFEF3C7);
                badgeText = const Color(0xFFD97706);
              }

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: DS.border, width: 0.5))),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pId, style: const TextStyle(color: Color(0xFF111827), fontSize: 11, fontWeight: FontWeight.w700)),
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

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weekly Progress Trends',
                        style: TextStyle(color: Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    SizedBox(height: 2),
                    Text('Metrics for the last 5 weeks',
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
                          style: const TextStyle(color: Color(0xFF111827), fontSize: 11, fontWeight: FontWeight.w700),
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

  _MultiLineChartPainter({
    required this.points,
    required this.accentColor,
    required this.maxMoney,
    required this.maxTokens,
    required this.maxEmployees,
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
      ..color = DS.border
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

    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patients by Branch (Today)',
              style: TextStyle(color: Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
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
                          style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11, fontWeight: FontWeight.w700),
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
                                    color: const Color(0xFFF3F4F6),
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
                          style: const TextStyle(color: Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w900),
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
    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
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
              const Text('Recent Activity',
                  style: TextStyle(color: Color(0xFF111827), fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
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
                                  style: const TextStyle(color: Color(0xFF111827), fontSize: 11.5, fontWeight: FontWeight.w700),
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
      {'id': 'donations', 'label': 'Add Donation', 'icon': Icons.volunteer_activism_rounded, 'color': const Color(0xFF10B981)},
      {'id': 'patients_registration', 'label': 'Add Patient', 'icon': Icons.person_add_rounded, 'color': const Color(0xFF8B5CF6)},
      {'id': 'pharmacy', 'label': 'Dispensary', 'icon': Icons.medication_outlined, 'color': const Color(0xFF3B82F6)},
      {'id': 'employee_attendance', 'label': 'Staff Attendance', 'icon': Icons.co_present_rounded, 'color': const Color(0xFF6366F1)},
      {'id': 'student_attendance', 'label': 'Student Attend.', 'icon': Icons.how_to_reg_rounded, 'color': const Color(0xFFEC4899)},
      {'id': 'madrassa_report', 'label': 'Madrassa Report', 'icon': Icons.assignment_rounded, 'color': const Color(0xFF14B8A6)},
      {'id': 'finance', 'label': 'Finance & HR', 'icon': Icons.monetization_on_rounded, 'color': const Color(0xFFEF4444)},
      {'id': 'executive_dashboard', 'label': 'Reports', 'icon': Icons.analytics_rounded, 'color': const Color(0xFFF59E0B)},
      {'id': 'branches', 'label': 'Branches', 'icon': Icons.store_outlined, 'color': const Color(0xFF0D9488)},
    ];

    final activeActions = targetActions.where((action) {
      if (action['id'] == 'employee_attendance') {
        return availableModules.any((m) => m.id == 'finance');
      }
      if (action['id'] == 'student_attendance' || action['id'] == 'madrassa_report') {
        return availableModules.any((m) => m.id == 'madrassa');
      }
      return availableModules.any((m) => m.id == action['id'] || (action['id'] == 'patients_registration' && m.id == 'patient_register_standalone'));
    }).toList();

    return Container(
      padding: const EdgeInsets.all(DS.s2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DS.r2),
        border: Border.all(color: DS.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick Actions',
              style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: DS.s1),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.45,
              ),
              itemCount: activeActions.length,
              itemBuilder: (context, index) {
                final action = activeActions[index];
                final mainModuleId = (action['id'] == 'employee_attendance')
                    ? 'finance'
                    : ((action['id'] == 'student_attendance' || action['id'] == 'madrassa_report')
                        ? 'madrassa'
                        : action['id']);
                final baseModule = availableModules.firstWhere(
                  (m) => m.id == mainModuleId || (mainModuleId == 'patients_registration' && m.id == 'patient_register_standalone'),
                  orElse: () => availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                );
                
                // Construct custom copy of the module with modified builder
                var module = baseModule;
                if (action['id'] == 'employee_attendance') {
                  module = baseModule.copyWith(
                    title: 'Employee Attendance',
                    builder: (context, data) => FinancePage(
                      branchId: data['branchId'] ?? 'all',
                      isAdmin: true,
                      initialTabIndex: 0,
                    ),
                  );
                } else if (action['id'] == 'student_attendance') {
                  module = baseModule.copyWith(
                    title: 'Student Attendance',
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
                } else if (action['id'] == 'madrassa_report') {
                  module = baseModule.copyWith(
                    title: 'Madrassa Report',
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
                        initialIndex: isAdmin ? 3 : 2,
                      );
                    },
                  );
                }
                
                final color = action['color'] as Color;

                return InkWell(
                  onTap: () => onOpenModule(module),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action['icon'] as IconData, color: color, size: 18),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              action['label'] as String,
                              style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800),
                            ),
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
  final role = (userData['role'] as String? ?? 'unknown').toLowerCase();
  final isGlobal = ['ceo', 'chairman', 'global user'].contains(role);
  final isFullExec = ['admin', 'global admin', 'ceo', 'chairman', 'global user', 'manager', 'hq manager'].contains(role);
  final isGlobalExec = isGlobal || isFullExec;
  
  final String userBranchId = (userData['branchId'] as String? ?? '').toLowerCase().trim();
  
  if (isGlobalExec) {
    // 1. Get all branch IDs
    final branchIds = RecentActivityService.getAllBranchIds();
    
    // 2. Fetch today-vs-yesterday per branch
    final Map<String, TodayVsYesterday> statsMap = await fetchTodayVsYesterdayPerBranch(branchIds);
    
    // 3. Build branch rows for table
    final List<HomeBranchRow> branchRows = [];
    final List<BranchStats> todayStatsList = [];
    final List<BranchStats> yesterdayStatsList = [];
    
    statsMap.forEach((bId, value) {
      final bName = RecentActivityService.resolveBranchName(bId);
      branchRows.add(HomeBranchRow(
        id: bId,
        name: bName,
        today: value.today,
        yesterday: value.yesterday,
      ));
      todayStatsList.add(value.today);
      yesterdayStatsList.add(value.yesterday);
    });
    
    // Aggregate overall today and yesterday stats
    final todayCombined = combineBranchStats(todayStatsList);
    final yesterdayCombined = combineBranchStats(yesterdayStatsList);
    
    // 4. Fetch 7-day chart points
    final chartPoints = await fetchChartPoints(branchIds, weeks: 5);
    
    // 5. Fetch recent activity (cross-branch)
    final recentActivities = RecentActivityService.getRecentActivity(limit: 15);
    
    return SnapshotDashboardData(
      todayCombined: todayCombined,
      yesterdayCombined: yesterdayCombined,
      branchRows: branchRows,
      chartPoints: chartPoints,
      recentActivities: recentActivities,
    );
  } else {
    // Branch-locked role
    final String branchId = userBranchId.isNotEmpty ? userBranchId : 'gujrat';
    
    // 1. Fetch today vs yesterday stats for this single branch
    final todayStats = await fetchBranchStats(branchId);
    final yesterdayStats = await fetchHistoricalDayStats(branchId, DateTime.now().subtract(const Duration(days: 1)));
    
    // 2. Fetch 7-day chart points
    final chartPoints = await fetchChartPoints([branchId], weeks: 5);
    
    // 3. Fetch recent activity (branch-locked)
    final recentActivities = RecentActivityService.getRecentActivity(branchId: branchId, limit: 15);
    
    return SnapshotDashboardData(
      todayCombined: todayStats,
      yesterdayCombined: yesterdayStats,
      branchRows: [], // empty as we hide the branch table
      chartPoints: chartPoints,
      recentActivities: recentActivities,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 10. Home Snapshot Dashboard (Today-Only Widget)
// ════════════════════════════════════════════════════════════════════════

final snapshotDashboardDataProvider = FutureProvider.family<SnapshotDashboardData, Map<String, dynamic>>((ref, userData) async {
  return fetchSnapshotDashboardData(userData);
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
  void _refresh() {
    ref.invalidate(snapshotDashboardDataProvider(widget.userData));
  }

  @override
  Widget build(BuildContext context) {
    final double hPad = widget.isDesktop ? 36 : 20;


    final asyncData = ref.watch(snapshotDashboardDataProvider(widget.userData));

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

        // Build the 5 stat tiles
        final donationsTile = HomeStatTile(
          label: 'Donations Today',
          value: fmtNum(today.donations),
          prefix: 'Rs ',
          icon: Icons.volunteer_activism_rounded,
          color: const Color(0xFF10B981),
          deltaPct: yesterday.donations == 0 ? null : ((today.donations - yesterday.donations) / yesterday.donations) * 100,
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
        );

        final patientsRevTile = HomeStatTile(
          label: 'Patients Revenue Today',
          value: fmtNum(today.dispensaryRevenue),
          prefix: 'Rs ',
          icon: Icons.payments_rounded,
          color: const Color(0xFFF59E0B),
          deltaPct: yesterday.dispensaryRevenue == 0 ? null : ((today.dispensaryRevenue - yesterday.dispensaryRevenue) / yesterday.dispensaryRevenue) * 100,
        );

        final overallRev = today.donations + today.dispensaryRevenue;
        final yOverallRev = yesterday.donations + yesterday.dispensaryRevenue;
        final overallRevTile = HomeStatTile(
          label: 'Overall Revenue',
          value: fmtNum(overallRev),
          prefix: 'Rs ',
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF6366F1),
          deltaPct: yOverallRev == 0 ? null : ((overallRev - yOverallRev) / yOverallRev) * 100,
        );

        final madrassaTile = HomeStatTile(
          label: 'Madrassa Attendance',
          value: fmtNum(today.prescribed),
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF0D9488),
          deltaPct: yesterday.prescribed == 0 ? null : ((today.prescribed - yesterday.prescribed) / yesterday.prescribed) * 100,
        );

        final List<HomeStatTile> statTiles = [
          donationsTile,
          patientsTile,
          patientsRevTile,
          overallRevTile,
          madrassaTile,
        ];

        HomeBranchRow? bestBranch;
        if (data.branchRows.isNotEmpty) {
          final sorted = List<HomeBranchRow>.from(data.branchRows)
            ..sort((a, b) => b.today.dispensaryRevenue.compareTo(a.today.dispensaryRevenue));
          if (sorted.isNotEmpty && sorted.first.today.dispensaryRevenue > 0) {
            bestBranch = sorted.first;
          }
        }

        // Layout rows
        final row2 = SizedBox(
          height: 370,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: HomePatientsByCategoryDonut(t: widget.t, s: today)),
              const SizedBox(width: DS.s2),
              Expanded(flex: 4, child: HomeBranchPerformanceTable(
                t: widget.t,
                rows: data.branchRows,
                onTapBranch: (bId) {
                  final branchesModule = widget.availableModules.firstWhere(
                    (m) => m.id == 'branches',
                    orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                  );
                  widget.onOpenModule(branchesModule);
                },
              )),
              const SizedBox(width: DS.s2),
              Expanded(
                flex: 3,
                child: bestBranch == null
                    ? const SizedBox.shrink()
                    : HomeBestBranchSpotlight(
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
                      ),
              ),
            ],
          ),
        );

        final row3 = SizedBox(
          height: 340,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 9, child: HomeRevenueLineChart(points: data.chartPoints, t: widget.t)),
              const SizedBox(width: DS.s2),
              Expanded(flex: 5, child: HomePatientsByBranchBarChart(t: widget.t, rows: data.branchRows)),
              const SizedBox(width: DS.s2),
              Expanded(flex: 6, child: HomeRecentActivityFeed(
                activities: data.recentActivities,
                t: widget.t,
                availableModules: widget.availableModules,
                onOpenModule: widget.onOpenModule,
              )),
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

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Today\'s Snapshot',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              HomeStatTileRow(tiles: statTiles),
              const SizedBox(height: DS.s3),
              if (widget.isDesktop) ...[
                row2,
                const SizedBox(height: DS.s3),
                row3,
                const SizedBox(height: DS.s3),
                row4,
              ] else ...[
                HomePatientsByCategoryDonut(t: widget.t, s: today),
                const SizedBox(height: DS.s2),
                HomeBranchPerformanceTable(
                  t: widget.t,
                  rows: data.branchRows,
                  onTapBranch: (bId) {
                    final branchesModule = widget.availableModules.firstWhere(
                      (m) => m.id == 'branches',
                      orElse: () => widget.availableModules.firstWhere((m) => m.id == 'executive_dashboard'),
                    );
                    widget.onOpenModule(branchesModule);
                  },
                ),
                const SizedBox(height: DS.s2),
                if (bestBranch != null)
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
                  ),
                const SizedBox(height: DS.s2),
                HomeRevenueLineChart(points: data.chartPoints, t: widget.t),
                const SizedBox(height: DS.s2),
                HomePatientsByBranchBarChart(t: widget.t, rows: data.branchRows),
                const SizedBox(height: DS.s2),
                HomeRecentActivityFeed(
                  activities: data.recentActivities,
                  t: widget.t,
                  availableModules: widget.availableModules,
                  onOpenModule: widget.onOpenModule,
                ),
                const SizedBox(height: DS.s2),
                HomeRecentDonationsTable(activities: data.recentActivities, t: widget.t),
                const SizedBox(height: DS.s2),
                HomeRecentPatientsTable(activities: data.recentActivities, t: widget.t),
                const SizedBox(height: DS.s2),
                QuickActionsRow(
                  availableModules: widget.availableModules,
                  t: widget.t,
                  onOpenModule: widget.onOpenModule,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}