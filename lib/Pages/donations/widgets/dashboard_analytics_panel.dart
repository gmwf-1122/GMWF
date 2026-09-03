import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  String? _selectedTrendKey;

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

    // ── Calculate reference date from the latest donation in dataset ──────────
    DateTime refDate = DateTime.now();
    DateTime? latestDate;
    for (var d in widget.currentDonations) {
      final date = DateTime.tryParse(d.date);
      if (date != null) {
        if (latestDate == null || date.isAfter(latestDate)) {
          latestDate = date;
        }
      }
    }
    if (latestDate != null) {
      refDate = latestDate;
    }

    // ── Calculations ──────────────────────────────────────────────────────────
    double totalAmt = 0;
    double totalCash = 0;
    double totalGoods = 0;
    int totalCount = widget.currentDonations.length;
    final Map<String, double> catTotals = {};
    final Map<String, double> subCatTotals = {};
    final Map<String, double> natureTotals = {}; // By DonationSubtype
    final Map<String, double> branchTotals = {};
    final Map<String, double> trendTotals = {};
    // Category breakdown per trend key: key -> { categoryId -> amount }
    final Map<String, Map<String, double>> trendCatBreakdown = {};
    
    // Donor Ranking data
    final Map<String, ({
      String name,
      String phone,
      double total,
      double cashTotal,
      double goodsTotal,
      DateTime firstSeen,
      int count
    })> donorStats = {};
    
    // ── Pre-populate Trends with zeros based on reference date ────────────────
    switch (_selectedPeriod) {
      case TrendPeriod.day:
        for (int i = 1; i <= 7; i++) {
          trendTotals[i.toString()] = 0;
        }
        break;
      case TrendPeriod.week:
        final daysInMonth = DateTime(refDate.year, refDate.month + 1, 0).day;
        for (int i = 1; i <= daysInMonth; i++) {
          trendTotals[i.toString().padLeft(2, '0')] = 0;
        }
        break;
      case TrendPeriod.month:
        for (int i = 1; i <= 12; i++) {
          trendTotals[i.toString().padLeft(2, '0')] = 0;
        }
        break;
      case TrendPeriod.year:
        final centerYear = refDate.year;
        for (int i = centerYear - 4; i <= centerYear; i++) {
          trendTotals[i.toString()] = 0;
        }
        break;
    }

    for (var d in widget.currentDonations) {
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      totalAmt += amt;
      final isGoods = d.isGoods;
      if (isGoods) {
        totalGoods += d.probableAmount ?? 0.0;
      } else {
        totalCash += d.amount;
      }
      catTotals[d.categoryId] = (catTotals[d.categoryId] ?? 0) + amt;
      
      // Donor grouping
      final date = DateTime.tryParse(d.date) ?? DateTime.now();
      final donorId = d.donorId.isEmpty ? 'anon_${d.donorName}_${d.phone}' : d.donorId;
      final existing = donorStats[donorId] ?? (
        name: d.donorName,
        phone: d.phone,
        total: 0.0,
        cashTotal: 0.0,
        goodsTotal: 0.0,
        firstSeen: date,
        count: 0
      );
      
      donorStats[donorId] = (
        name: existing.name,
        phone: existing.phone,
        total: existing.total + amt,
        cashTotal: existing.cashTotal + (isGoods ? 0.0 : amt),
        goodsTotal: existing.goodsTotal + (isGoods ? amt : 0.0),
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
      
      // Trend grouping with correct date range checks
      bool includeInTrend = false;
      String? groupKey;
      switch (_selectedPeriod) {
        case TrendPeriod.day:
          final startOfWeek = refDate.subtract(Duration(days: refDate.weekday - 1));
          final startOfWeekDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
          final dateOnly = DateTime(date.year, date.month, date.day);
          final diffDays = dateOnly.difference(startOfWeekDate).inDays;
          if (diffDays >= 0 && diffDays < 7) {
            includeInTrend = true;
            groupKey = date.weekday.toString();
          }
          break;
        case TrendPeriod.week:
          if (date.year == refDate.year && date.month == refDate.month) {
            includeInTrend = true;
            groupKey = date.day.toString().padLeft(2, '0');
          }
          break;
        case TrendPeriod.month:
          if (date.year == refDate.year) {
            includeInTrend = true;
            groupKey = date.month.toString().padLeft(2, '0');
          }
          break;
        case TrendPeriod.year:
          includeInTrend = true;
          groupKey = date.year.toString();
          break;
      }
      if (includeInTrend && groupKey != null) {
        if (trendTotals.containsKey(groupKey)) {
          trendTotals[groupKey] = (trendTotals[groupKey] ?? 0) + amt;
        }
        // Track category breakdown per trend key
        trendCatBreakdown.putIfAbsent(groupKey, () => {});
        trendCatBreakdown[groupKey]![d.categoryId] = (trendCatBreakdown[groupKey]![d.categoryId] ?? 0) + amt;
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: isMobile ? 16 : 32),
      child: Container(
        width: 1100,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.94),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.2), blurRadius: 40, offset: const Offset(0, 20)),
          ],
        ),
        child: Column(
          children: [
            _DialogHeader(branchName: widget.branchName),

            // ── Scrollable Body ─────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 16 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Smart Insights ──────────────────────────────────────
                    _InsightsPanel(
                      totalAmt: totalAmt,
                      totalCash: totalCash,
                      totalGoods: totalGoods,
                      avgDonation: avgDonation,
                      catTotals: catTotals,
                      donations: widget.currentDonations,
                    ),
                    const SizedBox(height: 24),

                    // ── KPI Cards ───────────────────────────────────────────
                    if (isMobile)
                      Column(
                        children: [
                          _KPICard(
                            label: 'TOTAL REVENUE',
                            value: 'PKR ${NumberFormat('#,###').format(totalAmt)}',
                            subValue: 'Cash: PKR ${NumberFormat('#,###').format(totalCash)} | Goods: PKR ${NumberFormat('#,###').format(totalGoods)}',
                            icon: Icons.payments_rounded,
                            color: const Color(0xFF0F172A),
                            isPrimary: true,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _KPICard(
                                label: 'TOTAL RECEIPTS',
                                value: totalCount.toString(),
                                icon: Icons.receipt_long_rounded,
                                color: const Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 12),
                              _KPICard(
                                label: 'AVERAGE VALUE',
                                value: 'PKR ${NumberFormat('#,###').format(avgDonation)}',
                                icon: Icons.analytics_rounded,
                                color: const Color(0xFF0D9488),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          _KPICard(
                            label: 'TOTAL REVENUE',
                            value: 'PKR ${NumberFormat('#,###').format(totalAmt)}',
                            subValue: 'Cash: PKR ${NumberFormat('#,###').format(totalCash)} | Goods: PKR ${NumberFormat('#,###').format(totalGoods)}',
                            icon: Icons.payments_rounded,
                            color: const Color(0xFF0F172A),
                            isPrimary: true,
                          ),
                          const SizedBox(width: 24),
                          _KPICard(
                            label: 'TOTAL RECEIPTS',
                            value: totalCount.toString(),
                            icon: Icons.receipt_long_rounded,
                            color: const Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 24),
                          _KPICard(
                            label: 'AVERAGE VALUE',
                            value: 'PKR ${NumberFormat('#,###').format(avgDonation)}',
                            icon: Icons.analytics_rounded,
                            color: const Color(0xFF0D9488),
                          ),
                        ],
                      ),
                    const SizedBox(height: 28),

                    // ── Chart Rows / Columns ─────────────────────────────
                    if (isMobile)
                      Column(
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
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () {
                              if (_selectedTrendKey != null) {
                                setState(() => _selectedTrendKey = null);
                              }
                            },
                            behavior: HitTestBehavior.translucent,
                            child: _ChartSection(
                              title: 'Contribution Trends',
                              subtitle: _selectedPeriod == TrendPeriod.day
                                  ? 'Active week — Mon to Sun'
                                  : _selectedPeriod == TrendPeriod.week
                                      ? 'Active month — ${DateFormat('MMMM yyyy').format(refDate)}'
                                      : _selectedPeriod == TrendPeriod.month
                                          ? 'Active year — ${refDate.year}'
                                          : 'All time record',
                              trailing: Row(
                                children: TrendPeriod.values.map((p) {
                                  final isActive = _selectedPeriod == p;
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedPeriod = p;
                                      _selectedTrendKey = null;
                                    }),
                                    child: Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isActive ? AppColors.primary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isActive ? AppColors.primary : (isDark ? const Color(0xFF475569) : AppColors.gray200)),
                                      ),
                                      child: Text(
                                        p.name.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: isActive ? Colors.white : (isDark ? const Color(0xFF94A3B8) : AppColors.gray500),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              child: Column(
                                children: [
                                  _TrendLineChart(
                                    sortedTrends: sortedTrends,
                                    period: _selectedPeriod,
                                    referenceDate: refDate,
                                    selectedKey: _selectedTrendKey,
                                    onPointSelected: (key) {
                                      setState(() {
                                        _selectedTrendKey = _selectedTrendKey == key ? null : key;
                                      });
                                    },
                                  ),
                                  if (_selectedTrendKey != null && trendTotals.containsKey(_selectedTrendKey)) ...[
                                    const SizedBox(height: 16),
                                    _TrendSelectionSummary(
                                      selectedKey: _selectedTrendKey!,
                                      period: _selectedPeriod,
                                      selectedTotal: trendTotals[_selectedTrendKey!] ?? 0,
                                      catBreakdown: trendCatBreakdown[_selectedTrendKey!] ?? {},
                                      allTrendTotals: trendTotals,
                                      referenceDate: refDate,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    else
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
                                GestureDetector(
                                  onTap: () {
                                  if (_selectedTrendKey != null) {
                                    setState(() => _selectedTrendKey = null);
                                  }
                                },
                                behavior: HitTestBehavior.translucent,
                                child: _ChartSection(
                                  title: 'Contribution Trends',
                                  subtitle: _selectedPeriod == TrendPeriod.day
                                      ? 'Active week — Mon to Sun'
                                      : _selectedPeriod == TrendPeriod.week
                                          ? 'Active month — ${DateFormat('MMMM yyyy').format(refDate)}'
                                          : _selectedPeriod == TrendPeriod.month
                                              ? 'Active year — ${refDate.year}'
                                              : 'All time record',
                                  trailing: Row(
                                    children: TrendPeriod.values.map((p) {
                                      final isActive = _selectedPeriod == p;
                                      return GestureDetector(
                                        onTap: () => setState(() {
                                          _selectedPeriod = p;
                                          _selectedTrendKey = null;
                                        }),
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
                                  child: Column(
                                    children: [
                                      _TrendLineChart(
                                        sortedTrends: sortedTrends,
                                        period: _selectedPeriod,
                                        referenceDate: refDate,
                                        selectedKey: _selectedTrendKey,
                                        onPointSelected: (key) {
                                          setState(() {
                                            _selectedTrendKey = _selectedTrendKey == key ? null : key;
                                          });
                                        },
                                      ),
                                      if (_selectedTrendKey != null && trendTotals.containsKey(_selectedTrendKey)) ...[
                                        const SizedBox(height: 16),
                                        _TrendSelectionSummary(
                                          selectedKey: _selectedTrendKey!,
                                          period: _selectedPeriod,
                                          selectedTotal: trendTotals[_selectedTrendKey!] ?? 0,
                                          catBreakdown: trendCatBreakdown[_selectedTrendKey!] ?? {},
                                          allTrendTotals: trendTotals,
                                          referenceDate: refDate,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF334155) : AppColors.gray100, width: 1.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.insights_rounded, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Intelligence Dashboard',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : AppColors.gray900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(branchName.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDark ? const Color(0xFF94A3B8) : AppColors.gray500, letterSpacing: 1)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : AppColors.gray400, size: 26),
          ),
        ],
      ),
    );
  }
}

class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final IconData icon;
  final Color color;
  final bool isPrimary;

  const _KPICard({
    required this.label,
    required this.value,
    this.subValue,
    required this.icon,
    required this.color,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isPrimary
            ? (isDark ? const Color(0xFF1E1B4B) : color)
            : (isDark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPrimary
              ? (isDark ? const Color(0xFF6366F1) : color)
              : (isDark ? const Color(0xFF334155) : AppColors.gray200.withValues(alpha: 0.6)),
        ),
        boxShadow: [
          BoxShadow(
            color: isPrimary
                ? color.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPrimary ? Colors.white.withValues(alpha: 0.15) : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: isPrimary ? Colors.white : color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.8)
                        : (isDark ? const Color(0xFF94A3B8) : AppColors.gray500),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isPrimary
                          ? Colors.white
                          : (isDark ? Colors.white : AppColors.gray900),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (subValue != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subValue!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isPrimary
                          ? Colors.white.withValues(alpha: 0.7)
                          : (isDark ? const Color(0xFF94A3B8) : AppColors.gray500),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : AppColors.gray200.withValues(alpha: 0.6)),
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
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.gray900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.gray500,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 20),
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
          Text('PKR ${NumberFormat('#,###').format(amount)}', style: GoogleFonts.dmMono(fontSize: isSmall ? 11 : 12, fontWeight: FontWeight.w700, color: AppColors.gray900)),
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
  final DateTime referenceDate;
  final String? selectedKey;
  final ValueChanged<String>? onPointSelected;

  const _TrendLineChart({
    required this.sortedTrends,
    required this.period,
    required this.referenceDate,
    this.selectedKey,
    this.onPointSelected,
  });

  int? get _selectedIndex {
    if (selectedKey == null) return null;
    for (int i = 0; i < sortedTrends.length; i++) {
      if (sortedTrends[i].key == selectedKey) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (sortedTrends.isEmpty) return const SizedBox(height: 200, child: Center(child: Text('No trend data')));

    final selIdx = _selectedIndex;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.lineBarSpots != null && response!.lineBarSpots!.isNotEmpty) {
                final idx = response.lineBarSpots!.first.spotIndex;
                if (idx >= 0 && idx < sortedTrends.length) {
                  onPointSelected?.call(sortedTrends[idx].key);
                }
              }
            },
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
                      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      final dIdx = int.tryParse(key) ?? 1;
                      label = days[(dIdx - 1) % 7];
                      break;
                    case TrendPeriod.week:
                      label = '${DateFormat('MMM').format(referenceDate)} ${int.tryParse(key) ?? key}';
                      break;
                    case TrendPeriod.month:
                      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                      final mIdx = int.tryParse(key) ?? 1;
                      label = months[(mIdx - 1) % 12];
                      break;
                    case TrendPeriod.year:
                      label = key;
                      break;
                  }
                  
                  final isSelected = selIdx == idx;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.gray400,
                        fontSize: isSelected ? 11 : 10,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      ),
                    ),
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
                getDotPainter: (spot, percent, barData, index) {
                  final isSelected = selIdx == index;
                  return FlDotCirclePainter(
                    radius: isSelected ? 7 : 4,
                    color: isSelected ? AppColors.primary : Colors.white,
                    strokeWidth: isSelected ? 3 : 2,
                    strokeColor: isSelected ? const Color(0xFF0F172A) : AppColors.primary,
                  );
                },
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
          extraLinesData: selIdx != null
              ? ExtraLinesData(verticalLines: [
                  VerticalLine(
                    x: selIdx!.toDouble(),
                    color: AppColors.primary.withValues(alpha: 0.3),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ])
              : const ExtraLinesData(),
        ),
      ),
    );
  }
}

class _TrendSelectionSummary extends StatelessWidget {
  final String selectedKey;
  final TrendPeriod period;
  final double selectedTotal;
  final Map<String, double> catBreakdown;
  final Map<String, double> allTrendTotals;
  final DateTime referenceDate;

  const _TrendSelectionSummary({
    required this.selectedKey,
    required this.period,
    required this.selectedTotal,
    required this.catBreakdown,
    required this.allTrendTotals,
    required this.referenceDate,
  });

  String get _periodLabel {
    switch (period) {
      case TrendPeriod.day:
        final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        final idx = int.tryParse(selectedKey) ?? 1;
        return days[(idx - 1) % 7];
      case TrendPeriod.week:
        return '${DateFormat('MMMM').format(referenceDate)} ${int.tryParse(selectedKey) ?? selectedKey}';
      case TrendPeriod.month:
        final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
        final idx = int.tryParse(selectedKey) ?? 1;
        return '${months[(idx - 1) % 12]} ${referenceDate.year}';
      case TrendPeriod.year:
        return 'Year $selectedKey';
    }
  }

  String? get _previousKey {
    final keys = allTrendTotals.keys.toList()..sort();
    final idx = keys.indexOf(selectedKey);
    if (idx > 0) return keys[idx - 1];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final prevKey = _previousKey;
    final prevTotal = prevKey != null ? (allTrendTotals[prevKey] ?? 0) : 0.0;
    final diff = selectedTotal - prevTotal;
    final diffPercent = prevTotal > 0 ? (diff / prevTotal) * 100 : 0.0;
    final isUp = diff >= 0;

    final sortedCats = catBreakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final allTotal = allTrendTotals.values.fold(0.0, (sum, v) => sum + v);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF0F172A), const Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: period label + total
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _periodLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PKR ${NumberFormat('#,###').format(selectedTotal)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              // Difference badge
              if (prevKey != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isUp ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFEF4444).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        color: isUp ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${isUp ? '+' : ''}${diffPercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: isUp ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          // Difference from previous period
          if (prevKey != null) ...[
            const SizedBox(height: 12),
            Text(
              '${isUp ? '+' : ''}PKR ${NumberFormat('#,###').format(diff)} vs previous',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],

          // Category breakdown
          if (sortedCats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('CATEGORY BREAKDOWN', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 10),
            ...sortedCats.map((e) {
              final cat = DonationCategory.values.firstWhere((c) => c.name == e.key, orElse: () => DonationCategory.all);
              final percent = selectedTotal > 0 ? (e.value / selectedTotal) * 100 : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(cat.label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      'PKR ${NumberFormat('#,###').format(e.value)}',
                      style: GoogleFonts.dmMono(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${percent.toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          // Share of all-time total
          if (allTotal > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: selectedTotal / allTotal,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(selectedTotal / allTotal * 100).toStringAsFixed(1)}% of total period contributions',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}


class _InsightsPanel extends StatelessWidget {
  final double totalAmt;
  final double totalCash;
  final double totalGoods;
  final double avgDonation;
  final Map<String, double> catTotals;
  final List<DonationRecord> donations;

  const _InsightsPanel({
    required this.totalAmt,
    required this.totalCash,
    required this.totalGoods,
    required this.avgDonation,
    required this.catTotals,
    required this.donations,
  });

  @override
  Widget build(BuildContext context) {
    String topCatName = 'N/A';
    if (catTotals.isNotEmpty) {
      final sorted = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      topCatName = DonationCategory.values.firstWhere((c) => c.name == sorted.first.key, orElse: () => DonationCategory.all).label;
    }

    // ── Group donations by calendar year ─────────────────────────────────────
    final Map<int, double> yearlyTotals = {};
    for (var d in donations) {
      final date = DateTime.tryParse(d.date) ?? DateTime.now();
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      yearlyTotals[date.year] = (yearlyTotals[date.year] ?? 0.0) + amt;
    }

    final sortedYears = yearlyTotals.keys.toList()..sort();

    // ── Build historical insights ────────────────────────────────────────────
    final List<String> historicalPoints = [];
    for (var year in sortedYears) {
      historicalPoints.add('$year: PKR ${NumberFormat('#,###').format(yearlyTotals[year]!)}');
    }
    final historyText = historicalPoints.isNotEmpty
        ? 'Historical Collections: ${historicalPoints.join(' | ')}'
        : 'No historical collections recorded.';

    // ── Estimate next year collections (YoY Growth Forecasting) ──────────────
    String forecastText = '';
    final nextYear = DateTime.now().year + 1;
    if (sortedYears.length >= 2) {
      final List<double> growthRates = [];
      for (int i = 0; i < sortedYears.length - 1; i++) {
        final prevVal = yearlyTotals[sortedYears[i]] ?? 0.0;
        final newVal = yearlyTotals[sortedYears[i + 1]] ?? 0.0;
        if (prevVal > 0) {
          growthRates.add((newVal - prevVal) / prevVal);
        }
      }
      final double avgGrowth = growthRates.isNotEmpty
          ? growthRates.reduce((a, b) => a + b) / growthRates.length
          : 0.05; // 5% default growth rate
      
      final currentYear = DateTime.now().year;
      final currentYearTotal = yearlyTotals[currentYear] ?? (yearlyTotals[sortedYears.last] ?? 0.0);
      final nextYearEst = currentYearTotal * (1 + avgGrowth);
      final pctString = (avgGrowth * 100).toStringAsFixed(1);
      final sign = avgGrowth >= 0 ? '+' : '';
      forecastText = 'Estimated collection for year $nextYear: PKR ${NumberFormat('#,###').format(nextYearEst)} (${sign}${pctString}% projected trend).';
    } else {
      final currentYear = DateTime.now().year;
      final currentYearTotal = yearlyTotals[currentYear] ?? 0.0;
      final nextYearEst = currentYearTotal > 0 ? currentYearTotal * 1.05 : avgDonation * 50;
      forecastText = 'Estimated collection for year $nextYear: PKR ${NumberFormat('#,###').format(nextYearEst)} (estimated with baseline 5% growth).';
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
          _InsightItem(
            icon: Icons.payments_rounded,
            text: 'Consolidated breakdown: PKR ${NumberFormat('#,###').format(totalCash)} in cash contributions and PKR ${NumberFormat('#,###').format(totalGoods)} in goods/ajnas estimated value.',
            color: Colors.lightGreenAccent,
          ),
          _InsightItem(icon: Icons.history_rounded, text: historyText, color: Colors.cyanAccent),
          _InsightItem(icon: Icons.online_prediction_rounded, text: forecastText, color: Colors.purpleAccent),
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
              Text('PKR ${NumberFormat('#,###').format(e.value)}', style: GoogleFonts.dmMono(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gray900)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DonorRankingList extends StatelessWidget {
  final List<MapEntry<String, ({String name, String phone, double total, double cashTotal, double goodsTotal, DateTime firstSeen, int count})>> sortedDonors;
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
                    Text(data.name.isEmpty ? 'Walk-in Donor' : data.name.toUpperCase(), 
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
                      style: GoogleFonts.dmMono(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.gray900)),
                  Text(
                    'Cash: PKR ${NumberFormat('#,###').format(data.cashTotal)} · Goods: PKR ${NumberFormat('#,###').format(data.goodsTotal)}',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.gray500),
                  ),
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
