import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../constants/colors.dart';
import '../../../models/donation_models.dart';
import '../donations_shared.dart';

enum TrendPeriod { day, week, month, year }
enum DonorSort { contribution, oldest }

class AnalyticsInsightsDialog extends StatefulWidget {
  final List<DonationRecord> currentDonations;
  final String branchName;
  final UserRole role;

  const AnalyticsInsightsDialog({
    super.key,
    required this.currentDonations,
    required this.branchName,
    required this.role,
  });

  @override
  State<AnalyticsInsightsDialog> createState() => _AnalyticsInsightsDialogState();
}

class _AnalyticsInsightsDialogState extends State<AnalyticsInsightsDialog> {
  TrendPeriod _selectedPeriod = TrendPeriod.month;
  DonorSort _donorSort = DonorSort.contribution;

  @override
  Widget build(BuildContext context) {
    if (widget.currentDonations.isEmpty) {
      return AlertDialog(
        title: const Text('No Data'),
        content: const Text('There are no donations to analyze in the current selection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      );
    }

    // ── Calculations ──────────────────────────────────────────────────────────
    double totalAmt = 0;
    int totalCount = widget.currentDonations.length;
    final Map<String, double> catTotals = {};
    final Map<String, double> subCatTotals = {};
    final Map<String, double> natureTotals = {}; // By DonationSubtype
    final Map<String, double> branchTotals = {};
    final Map<String, double> trendTotals = {};
    
    // Donor Ranking data
    final Map<String, ({String name, String phone, double total, DateTime firstSeen, int count})> donorStats = {};
    
    // ── Pre-populate Trends with zeros ────────────────────────────────────────
    switch (_selectedPeriod) {
      case TrendPeriod.day:
        for (int i = 1; i <= 7; i++) {
          trendTotals[i.toString()] = 0;
        }
        break;
      case TrendPeriod.week:
        for (int i = 1; i <= 31; i++) {
          trendTotals[i.toString().padLeft(2, '0')] = 0;
        }
        break;
      case TrendPeriod.month:
        for (int i = 1; i <= 12; i++) {
          trendTotals[i.toString().padLeft(2, '0')] = 0;
        }
        break;
      case TrendPeriod.year:
        final currentYear = DateTime.now().year;
        for (int i = currentYear - 4; i <= currentYear; i++) {
          trendTotals[i.toString()] = 0;
        }
        break;
    }

    for (var d in widget.currentDonations) {
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      totalAmt += amt;
      catTotals[d.categoryId] = (catTotals[d.categoryId] ?? 0) + amt;
      
      // Donor grouping
      final date = DateTime.tryParse(d.date) ?? DateTime.now();
      final donorId = d.donorId.isEmpty ? 'anon_${d.donorName}_${d.phone}' : d.donorId;
      final existing = donorStats[donorId] ?? (name: d.donorName, phone: d.phone, total: 0.0, firstSeen: date, count: 0);
      
      donorStats[donorId] = (
        name: existing.name,
        phone: existing.phone,
        total: existing.total + amt,
        firstSeen: date.isBefore(existing.firstSeen) ? date : existing.firstSeen,
        count: existing.count + 1,
      );

      // Target Program Distribution
      if (d.categoryId == DonationCategory.gmwf.name && d.gmwfSubCategoryId != null) {
        subCatTotals[d.gmwfSubCategoryId!] = (subCatTotals[d.gmwfSubCategoryId!] ?? 0) + amt;
      } else if (d.categoryId == DonationCategory.jamia.name && d.subtypeId != null) {
        if (d.subtypeId == DonationSubtype.construction.name || d.subtypeId == DonationSubtype.maintenance.name) {
          subCatTotals['jamia_${d.subtypeId}'] = (subCatTotals['jamia_${d.subtypeId}'] ?? 0) + amt;
        }
      }

      // Nature of Donation
      if (d.subtypeId != null) natureTotals[d.subtypeId!] = (natureTotals[d.subtypeId!] ?? 0) + amt;
      branchTotals[d.branchName] = (branchTotals[d.branchName] ?? 0) + amt;
      
      // Trend grouping
      String groupKey;
      switch (_selectedPeriod) {
        case TrendPeriod.day:
          groupKey = date.weekday.toString();
          break;
        case TrendPeriod.week:
          groupKey = date.day.toString().padLeft(2, '0');
          break;
        case TrendPeriod.month:
          groupKey = date.month.toString().padLeft(2, '0');
          break;
        case TrendPeriod.year:
          groupKey = date.year.toString();
          break;
      }
      if (trendTotals.containsKey(groupKey)) {
        trendTotals[groupKey] = (trendTotals[groupKey] ?? 0) + amt;
      }
    }

    final avgDonation = totalCount > 0 ? totalAmt / totalCount : 0.0;
    final sortedBranches = branchTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final sortedTrends = trendTotals.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    
    // Sort Donors
    final sortedDonors = donorStats.entries.toList();
    if (_donorSort == DonorSort.contribution) {
      sortedDonors.sort((a, b) => b.value.total.compareTo(a.value.total));
    } else {
      sortedDonors.sort((a, b) => a.value.firstSeen.compareTo(b.value.firstSeen));
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 1100,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 40, offset: const Offset(0, 20)),
          ],
        ),
        child: Column(
          children: [
            _DialogHeader(branchName: widget.branchName),

            // ── Scrollable Body ─────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Smart Insights ──────────────────────────────────────
                    _InsightsPanel(
                      totalAmt: totalAmt,
                      avgDonation: avgDonation,
                      catTotals: catTotals,
                    ),
                    const SizedBox(height: 32),

                    // ── KPI Cards ───────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _KPICard(
                            label: 'TOTAL REVENUE',
                            value: 'PKR ${NumberFormat('#,###').format(totalAmt)}',
                            icon: Icons.payments_rounded,
                            color: const Color(0xFF0F172A),
                            isPrimary: true,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _KPICard(
                            label: 'TOTAL RECEIPTS',
                            value: totalCount.toString(),
                            icon: Icons.receipt_long_rounded,
                            color: const Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _KPICard(
                            label: 'AVERAGE VALUE',
                            value: 'PKR ${NumberFormat('#,###').format(avgDonation)}',
                            icon: Icons.analytics_rounded,
                            color: const Color(0xFF0D9488),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Left Column: Categories & Branches ────────────────
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ChartSection(
                                title: 'Allocation Breakdown',
                                subtitle: 'Comprehensive program distribution',
                                child: _CombinedDonutChart(
                                  catTotals: catTotals,
                                  subCatTotals: subCatTotals,
                                  natureTotals: natureTotals,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),

                        // ── Right Column: Trends & Donors ─────────────────────
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ChartSection(
                                title: 'Contribution Trends',
                                subtitle: _selectedPeriod == TrendPeriod.day
                                    ? 'This week — Mon to Sun'
                                    : _selectedPeriod == TrendPeriod.week
                                        ? 'This month — ${DateFormat('MMMM yyyy').format(DateTime.now())}'
                                        : _selectedPeriod == TrendPeriod.month
                                            ? 'This year — ${DateTime.now().year}'
                                            : 'All time record',
                                trailing: Row(
                                  children: TrendPeriod.values.map((p) {
                                    final isActive = _selectedPeriod == p;
                                    return GestureDetector(
                                      onTap: () => setState(() => _selectedPeriod = p),
                                      child: Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isActive ? AppColors.primary : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: isActive ? AppColors.primary : AppColors.gray200),
                                        ),
                                        child: Text(
                                          p.name.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: isActive ? Colors.white : AppColors.gray500,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                child: _TrendLineChart(sortedTrends: sortedTrends, period: _selectedPeriod),
                              ),
                              const SizedBox(height: 24),
                              _ChartSection(
                                title: 'Top Donors',
                                subtitle: 'Largest contributors to the cause',
                                trailing: Wrap(
                                  spacing: 8,
                                  children: [
                                    _FilterTab(
                                      label: 'MOST',
                                      isActive: _donorSort == DonorSort.contribution,
                                      onTap: () => setState(() => _donorSort = DonorSort.contribution),
                                    ),
                                    _FilterTab(
                                      label: 'OLDEST',
                                      isActive: _donorSort == DonorSort.oldest,
                                      onTap: () => setState(() => _donorSort = DonorSort.oldest),
                                    ),
                                  ],
                                ),
                                child: _DonorRankingList(sortedDonors: sortedDonors),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final String branchName;
  const _DialogHeader({required this.branchName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 32, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(bottom: BorderSide(color: AppColors.gray100, width: 1.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.insights_rounded, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Intelligence Dashboard', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.gray900, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(branchName.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.gray500, letterSpacing: 1)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: AppColors.gray400, size: 28),
          ),
        ],
      ),
    );
  }
}

class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isPrimary;

  const _KPICard({required this.label, required this.value, required this.icon, required this.color, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isPrimary ? color : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isPrimary ? color : AppColors.gray200.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(color: isPrimary ? color.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isPrimary ? Colors.white.withValues(alpha: 0.15) : color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: isPrimary ? Colors.white : color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isPrimary ? Colors.white.withValues(alpha: 0.8) : AppColors.gray500, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: isPrimary ? Colors.white : AppColors.gray900, letterSpacing: -0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  const _ChartSection({required this.title, required this.subtitle, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gray200.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.gray900)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
                ],
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class _CombinedDonutChart extends StatelessWidget {
  final Map<String, double> catTotals;
  final Map<String, double> subCatTotals;
  final Map<String, double> natureTotals;

  const _CombinedDonutChart({required this.catTotals, required this.subCatTotals, required this.natureTotals});

  @override
  Widget build(BuildContext context) {
    final total = catTotals.values.fold(0.0, (sum, v) => sum + v);
    if (total == 0) return const Center(child: Text('No data for allocation'));

    final List<PieChartSectionData> sections = [];
    for (var entry in catTotals.entries) {
      final cat = DonationCategory.values.firstWhere((c) => c.name == entry.key, orElse: () => DonationCategory.all);
      final percent = (entry.value / total) * 100;
      
      sections.add(PieChartSectionData(
        color: cat.color,
        value: entry.value,
        title: '${percent.toStringAsFixed(0)}%',
        radius: 60,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 45, sectionsSpace: 3)),
        ),
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Major Categories
            const Text('MAJOR CATEGORIES', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.gray400, letterSpacing: 1)),
            const SizedBox(height: 12),
            ...catTotals.entries.map((e) {
              final cat = DonationCategory.values.firstWhere((c) => c.name == e.key, orElse: () => DonationCategory.all);
              return _LegendRow(label: cat.label, amount: e.value, color: cat.color);
            }),
            
            if (subCatTotals.isNotEmpty) ...[
              const Divider(height: 32, color: AppColors.gray100),
              const Text('DETAILED PROGRAM BREAKDOWN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.gray400, letterSpacing: 1)),
              const SizedBox(height: 12),
              ...subCatTotals.entries.map((e) {
                final String label;
                final Color color;
                if (e.key.startsWith('jamia_')) {
                  final subId = e.key.replaceFirst('jamia_', '');
                  final sub = DonationSubtype.values.firstWhere((s) => s.name == subId, orElse: () => DonationSubtype.general);
                  label = 'Jamia: ${sub.label}';
                  color = sub.color;
                } else {
                  final sub = GmwfSubCategory.values.firstWhere((s) => s.name == e.key, orElse: () => GmwfSubCategory.general);
                  label = sub.label;
                  color = sub.color;
                }
                return _LegendRow(label: label, amount: e.value, color: color, isSmall: true);
              }),
            ],

            if (natureTotals.isNotEmpty) ...[
              const Divider(height: 32, color: AppColors.gray100),
              const Text('NATURE OF CONTRIBUTIONS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.gray400, letterSpacing: 1)),
              const SizedBox(height: 12),
              ...(natureTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) {
                final sub = DonationSubtype.values.firstWhere((s) => s.name == e.key, orElse: () => DonationSubtype.general);
                return _LegendRow(label: sub.label, amount: e.value, color: sub.color, isSmall: true);
              }),
            ],
          ],
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isSmall;

  const _LegendRow({required this.label, required this.amount, required this.color, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isSmall ? 8 : 12),
      child: Row(
        children: [
          Container(width: isSmall ? 8 : 12, height: isSmall ? 8 : 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: isSmall ? 11 : 13, fontWeight: isSmall ? FontWeight.w500 : FontWeight.w700, color: AppColors.gray700))),
          Text('PKR ${NumberFormat('#,###').format(amount)}', style: TextStyle(fontSize: isSmall ? 11 : 12, fontWeight: FontWeight.w700, color: AppColors.gray900, fontFamily: 'DMMono')),
        ],
      ),
    );
  }
}

class _BranchPerformanceList extends StatelessWidget {
  final List<MapEntry<String, double>> sortedBranches;
  const _BranchPerformanceList({required this.sortedBranches});

  @override
  Widget build(BuildContext context) {
    if (sortedBranches.isEmpty) return const Text('No branch data available');
    final max = sortedBranches.first.value;

    return Column(
      children: sortedBranches.take(5).map((e) {
        final percent = max > 0 ? e.value / max : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gray800)),
                  Text('PKR ${NumberFormat('#,###').format(e.value)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary.withValues(alpha: 0.8)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TrendLineChart extends StatelessWidget {
  final List<MapEntry<String, double>> sortedTrends;
  final TrendPeriod period;
  const _TrendLineChart({required this.sortedTrends, required this.period});

  @override
  Widget build(BuildContext context) {
    if (sortedTrends.isEmpty) return const SizedBox(height: 200, child: Center(child: Text('No trend data')));

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => const Color(0xFF1E293B),
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    'PKR ${NumberFormat('#,###').format(spot.y)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  );
                }).toList();
              },
            ),
          ),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (val, meta) => Text(
                  val >= 1000 ? '${(val / 1000).toStringAsFixed(0)}K' : val.toStringAsFixed(0),
                  style: const TextStyle(color: AppColors.gray400, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: period == TrendPeriod.week ? 3 : 1,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= sortedTrends.length) return const SizedBox.shrink();
                  
                  final key = sortedTrends[idx].key;
                  String label = key;
                  
                  switch (period) {
                    case TrendPeriod.day:
                      // key is weekday string '1'..'7'
                      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      final dIdx = int.tryParse(key) ?? 1;
                      label = days[(dIdx - 1) % 7];
                      break;
                    case TrendPeriod.week:
                      // key is day string '01'..'31'
                      label = '${DateFormat('MMM').format(DateTime.now())} ${int.tryParse(key) ?? key}';
                      break;
                    case TrendPeriod.month:
                      // key is month string '01'..'12'
                      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                      final mIdx = int.tryParse(key) ?? 1;
                      label = months[(mIdx - 1) % 12];
                      break;
                    case TrendPeriod.year:
                      label = key;
                      break;
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(label, style: const TextStyle(color: AppColors.gray400, fontSize: 10, fontWeight: FontWeight.w600)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: sortedTrends.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList(),
              isCurved: true,
              color: AppColors.primary,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: Colors.white, strokeWidth: 2, strokeColor: AppColors.primary),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  final double totalAmt;
  final double avgDonation;
  final Map<String, double> catTotals;

  const _InsightsPanel({required this.totalAmt, required this.avgDonation, required this.catTotals});

  @override
  Widget build(BuildContext context) {
    String topCatName = 'N/A';
    if (catTotals.isNotEmpty) {
      final sorted = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      topCatName = DonationCategory.values.firstWhere((c) => c.name == sorted.first.key, orElse: () => DonationCategory.all).label;
    }

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.amber, size: 20),
              ),
              const SizedBox(width: 16),
              const Text('Smart Insights', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
            ],
          ),
          const SizedBox(height: 24),
          _InsightItem(icon: Icons.trending_up_rounded, text: 'The highest contribution comes from $topCatName.', color: Colors.blueAccent),
          _InsightItem(icon: Icons.lightbulb_outline_rounded, text: 'Average contribution per receipt is PKR ${NumberFormat('#,###').format(avgDonation)}.', color: Colors.amberAccent),
          _InsightItem(icon: Icons.verified_user_rounded, text: 'Total consolidated revenue reached PKR ${NumberFormat('#,###').format(totalAmt)}.', color: const Color(0xFF34D399)),
        ],
      ),
    );
  }
}

class _InsightItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InsightItem({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w500, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _SubCategoryBarChart extends StatelessWidget {
  final Map<String, double> subCatTotals;
  const _SubCategoryBarChart({required this.subCatTotals});

  @override
  Widget build(BuildContext context) {
    final sorted = subCatTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = sorted.isEmpty ? 0.0 : sorted.first.value;

    return Column(
      children: sorted.take(6).map((e) {
        final String label;
        final IconData icon;
        final Color color;

        if (e.key.startsWith('jamia_')) {
          final subId = e.key.replaceFirst('jamia_', '');
          final sub = DonationSubtype.values.firstWhere((s) => s.name == subId, orElse: () => DonationSubtype.general);
          label = 'Jamia: ${sub.label}';
          icon = sub.icon;
          color = sub.color;
        } else {
          final sub = GmwfSubCategory.values.firstWhere((s) => s.name == e.key, orElse: () => GmwfSubCategory.general);
          label = sub.label;
          icon = sub.icon;
          color = sub.color;
        }

        final percent = max > 0 ? e.value / max : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray700)),
                        Text('PKR ${NumberFormat('#,###').format(e.value)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray900)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 4,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.7)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _NatureBreakdownChart extends StatelessWidget {
  final Map<String, double> natureTotals;
  const _NatureBreakdownChart({required this.natureTotals});

  @override
  Widget build(BuildContext context) {
    final sorted = natureTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    return Column(
      children: sorted.map((e) {
        final sub = DonationSubtype.values.firstWhere((s) => s.name == e.key, orElse: () => DonationSubtype.general);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: sub.color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(sub.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.gray600))),
              Text('PKR ${NumberFormat('#,###').format(e.value)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gray900, fontFamily: 'DMMono')),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DonorRankingList extends StatelessWidget {
  final List<MapEntry<String, ({String name, String phone, double total, DateTime firstSeen, int count})>> sortedDonors;
  const _DonorRankingList({required this.sortedDonors});

  @override
  Widget build(BuildContext context) {
    if (sortedDonors.isEmpty) return const Text('No donor data');

    return Column(
      children: sortedDonors.take(5).map((e) {
        final data = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.name.isEmpty ? 'Anonymous' : data.name.toUpperCase(), 
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.gray900),
                        overflow: TextOverflow.ellipsis),
                    Text('${data.count} donations · Joined ${DateFormat('MMM yyyy').format(data.firstSeen)}', 
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.gray400)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('PKR ${NumberFormat('#,###').format(data.total)}', 
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.gray900, fontFamily: 'DMMono')),
                  const Text('total contribution', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.gray400)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterTab({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? AppColors.primary : AppColors.gray200),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: isActive ? Colors.white : AppColors.gray500,
          ),
        ),
      ),
    );
  }
}
