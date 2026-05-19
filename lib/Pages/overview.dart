// lib/pages/overview.dart
// Unified sidebar-less dashboard for executive roles.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/role_theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/scroll_reveal.dart';
import 'branches.dart';
import 'donations/donations_shared.dart' as don;
import 'donations/global_audit_trail.dart';
import '../services/donations_local_storage.dart';
import 'donations/donations_screen.dart' show DonDS;

class OverviewScreen extends StatefulWidget {
  final String username;
  final bool isEmbedded;
  final String? initialBranchId;
  const OverviewScreen({
    super.key,
    this.username = 'User',
    this.isEmbedded = false,
    this.initialBranchId,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // If an initial branch ID is provided (e.g., for Branch Managers/Supervisors),
    // we default the dashboard filter to that branch.
    if (widget.initialBranchId != null &&
        widget.initialBranchId != 'all' &&
        widget.initialBranchId != 'unknown') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dashboardController.setBranch(widget.initialBranchId!);
      });
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final role = RoleThemeScope.roleOf(context);

    final content = ValueListenableBuilder<DashboardFilter>(
      valueListenable: dashboardController,
      builder: (context, filter, child) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('branches').snapshots(),
          builder: (context, branchSnap) {
            final branches = branchSnap.hasData
                ? branchSnap.data!.docs.map((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return <String, dynamic>{
                      'id': d.id,
                      'name': data['name'] as String? ?? d.id
                    };
                  }).toList()
                : <Map<String, dynamic>>[];

            return Column(
              children: [
                GlobalFilterBar(controller: dashboardController, branches: branches),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: DS.s3, vertical: DS.s3),
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _OverviewHeader(
                                t: t,
                                username: widget.username,
                                roleName: role.name.toUpperCase()),
                            const SizedBox(height: DS.s3),

                            // -- High Authority Donation Intelligence --
                            if (role.name.toLowerCase().contains('chairman') || 
                                role.name.toLowerCase().contains('hq') || 
                                role.name.toLowerCase().contains('admin'))
                              _DonationIntelligenceSection(t: t, branches: branches, filter: filter),

                            const SizedBox(height: DS.s3),

                            ExecutiveTopBranchFetcher(
                              t: t,
                              branches: branches,
                              onGoToBranch: (id) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Branches(
                                      initialBranchId: id,
                                      isManager: false,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: DS.s4),

                            // -- KPIs --
                            _buildKPIOverview(branches, filter),
                            const SizedBox(height: DS.s4),

                            // ── Branch Performance Breakdown ─────────────────────────
                            DashSectionHeader(
                              title: 'Branch Performance Breakdown',
                              subtitle:
                                  'Detailed operational and financial metrics per branch',
                            ),
                            const SizedBox(height: DS.s2),
                            ScrollReveal(
                                delay: const Duration(milliseconds: 280),
                                child: BranchPerformanceTable(
                                  t: t,
                                  branches: branches,
                                  onGoToBranch: (id) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => Branches(
                                          initialBranchId: id,
                                          isManager: false,
                                        ),
                                      ),
                                    );
                                  },
                                )),
                            const SizedBox(height: DS.s4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (widget.isEmbedded) return content;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.accent,
        elevation: 4,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
        title: Row(children: [
          Image.asset('assets/logo/gmwf-1.png', height: 26, width: 26),
          const SizedBox(width: 10),
          Text(
            role.name.toUpperCase(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 3),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 22),
            onPressed: _logout,
          ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: t.bgRule)),
      ),
      body: content,
    );
  }

  Widget _buildKPIOverview(
      List<Map<String, dynamic>> branches, DashboardFilter filter) {
    final ids = branches.map((b) => b['id'] as String).toList();
    if (filter.timeRange == TimeRange.today) {
      return StreamBuilder<BranchStats>(
        stream: streamAllBranchesStats(ids, filter: filter),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return DashLoadingCard(t: RoleThemeScope.dataOf(context), height: 260);
          }
          final s = snap.data ?? const BranchStats();
          return _buildInnerKPI(context, s, branches.length);
        },
      );
    } else {
      return FutureBuilder<BranchStats>(
        future: fetchAllBranchesStats(ids, filter: filter),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return DashLoadingCard(t: RoleThemeScope.dataOf(context), height: 260);
          }
          final s = snap.data ?? const BranchStats();
          return _buildInnerKPI(context, s, branches.length);
        },
      );
    }
  }

  Widget _buildInnerKPI(BuildContext context, BranchStats s, int branchCount) {
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ActionableKPICard(
                    label: 'Total Revenue',
                    value: fmtNum(s.totalRevenue),
                    prefix: 'PKR ',
                    icon: Icons.payments_rounded,
                    color: DS.green,
                    isPrimary: true,
                    insight: s.totalRevenue > 0
                        ? 'Peak performance reached'
                        : '⚠️ No revenue today',
                  ),
                ),
                const SizedBox(width: DS.s2),
                Expanded(
                  child: ActionableKPICard(
                    label: 'Total Patients',
                    value: fmtNum(s.tokens),
                    icon: Icons.people_alt_rounded,
                    color: DS.blue,
                    isPrimary: true,
                    insight: '${branchCount} active branches',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DS.s2),
            Row(
              children: [
                Expanded(
                  child: ActionableKPICard(
                    label: 'Tokens Served',
                    value: fmtNum(s.dasterkhwaanServed),
                    icon: Icons.restaurant_rounded,
                    color: DS.orange,
                    insight: '${s.dasterkhwaan} tokens issued',
                  ),
                ),
                const SizedBox(width: DS.s2),
                Expanded(
                  child: ActionableKPICard(
                    label: 'Donations',
                    value: fmtNum(s.donations),
                    prefix: 'PKR ',
                    icon: Icons.volunteer_activism_rounded,
                    color: DS.purple,
                    insight: 'Today\'s contributions',
                  ),
                ),
              ],
            ),
            const SizedBox(height: DS.s2),
            // Common chart for all executive roles
            PatientDistributionCard(t: RoleThemeScope.dataOf(context), s: s),
          ],
        );
  }
}

class _OverviewHeader extends StatelessWidget {
  final RoleThemeData t;
  final String username;
  final String roleName;
  const _OverviewHeader(
      {required this.t, required this.username, required this.roleName});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(DS.s2 + 4),
        decoration: BoxDecoration(
          color: t.bgCard,
          borderRadius: BorderRadius.circular(DS.r3),
          border: Border.all(color: const Color(0xFFEDD88A), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: t.accent.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 6))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(DS.s1 + 2),
            decoration: BoxDecoration(
              color: t.accentMuted,
              borderRadius: BorderRadius.circular(DS.r1 + 4),
              border: Border.all(color: const Color(0xFFEDD88A), width: 1.5),
            ),
            child: Image.asset('assets/logo/gmwf-1.png', height: 36, width: 36),
          ),
          const SizedBox(width: DS.s2),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: DS.s1, vertical: 3),
                  decoration: BoxDecoration(
                      color: t.accentMuted,
                      borderRadius: BorderRadius.circular(DS.r2),
                      border: Border.all(color: const Color(0xFFEDD88A))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.workspace_premium_rounded,
                        color: t.accent, size: 11),
                    const SizedBox(width: 5),
                    Text(roleName,
                        style: TextStyle(
                            color: t.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5)),
                  ]),
                ),
                const SizedBox(height: 6),
                Text(username,
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.0)),
                Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                    style: TextStyle(color: t.textTertiary, fontSize: 12)),
              ])),
        ]),
      );
}

// ── Donation Intelligence Section for HQ/Chairman ─────────────────────────────

class _DonationIntelligenceSection extends StatelessWidget {
  final RoleThemeData t;
  final List<Map<String, dynamic>> branches;
  final DashboardFilter filter;

  const _DonationIntelligenceSection({
    required this.t,
    required this.branches,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    // We fetch ALL donations from local storage (synced from FS)
    final allDonations = DonationsLocalStorage.getAllDonations('all');
    
    // Filter by date range if not 'today'
    final range = _resolveFilter(filter);
    final filtered = allDonations.where((d) {
      try {
        final dt = DateTime.parse(d.date);
        return !dt.isBefore(range.start) && !dt.isAfter(range.end.add(const Duration(hours: 23, minutes: 59)));
      } catch (_) { return false; }
    }).toList();

    // Aggregates
    double totalJamia = 0;
    double totalGmwf = 0;
    final Map<String, double> subCatTotals = {};
    final Map<String, double> branchTotals = {};
    final Map<String, double> donorTotals = {};
    final Map<String, String> donorNames = {};

    for (var d in filtered) {
      final amt = (d.amount > 0 ? d.amount : d.probableAmount) ?? 0.0;
      if (d.categoryId == 'jamia') totalJamia += amt;
      else if (d.categoryId == 'gmwf') totalGmwf += amt;

      if (d.gmwfSubCategoryId != null) {
        subCatTotals[d.gmwfSubCategoryId!] = (subCatTotals[d.gmwfSubCategoryId!] ?? 0) + amt;
      }
      
      branchTotals[d.branchId] = (branchTotals[d.branchId] ?? 0) + amt;
      
      if (d.donorId.isNotEmpty) {
        donorTotals[d.donorId] = (donorTotals[d.donorId] ?? 0) + amt;
        donorNames[d.donorId] = d.donorName;
      }
    }

    final topDonors = donorTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final sortedBranches = branchTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashSectionHeader(
          title: 'Donation Intelligence',
          subtitle: 'HQ-level insights into global contribution trends',
          actions: [
            TextButton.icon(
              onPressed: () {
                final role = RoleThemeScope.roleOf(context);
                final userRole = don.UserRoleX.fromString(role.name);
                Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalAuditTrailScreen(role: userRole)));
              },
              icon: const Icon(Icons.history_rounded, size: 16),
              label: const Text('Audit Trail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                foregroundColor: t.accent,
                backgroundColor: t.accentMuted,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.r1)),
              ),
            ),
          ],
        ),
        const SizedBox(height: DS.s2),
        
        // 1. Hero Summary Cards (responsive layout)
        if (isMobile) ...[
          _DonationStatCard(
            label: 'Jamia / Masjid',
            value: totalJamia.toInt(),
            color: don.DS.sapphire500,
            icon: Icons.mosque_rounded,
            t: t,
          ),
          const SizedBox(height: DS.s2),
          _DonationStatCard(
            label: 'GMWF General',
            value: totalGmwf.toInt(),
            color: don.DS.emerald500,
            icon: Icons.volunteer_activism_rounded,
            t: t,
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: _DonationStatCard(
                  label: 'Jamia / Masjid',
                  value: totalJamia.toInt(),
                  color: don.DS.sapphire500,
                  icon: Icons.mosque_rounded,
                  t: t,
                ),
              ),
              const SizedBox(width: DS.s2),
              Expanded(
                child: _DonationStatCard(
                  label: 'GMWF General',
                  value: totalGmwf.toInt(),
                  color: don.DS.emerald500,
                  icon: Icons.volunteer_activism_rounded,
                  t: t,
                ),
              ),
            ],
          ),
        const SizedBox(height: DS.s3),

        // 2. Branch & Category Distribution
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final content = [
            _DistributionCard(
              title: 'Branch Performance',
              data: sortedBranches.take(5).map((e) {
                final bName = branches.firstWhereOrNull((b) => b['id'] == e.key)?['name'] ?? e.key.toUpperCase();
                return _DistItem(label: bName, value: e.value, color: don.DS.sapphire500);
              }).toList(),
              t: t,
            ),
            const SizedBox(width: DS.s2, height: DS.s2),
            _DistributionCard(
              title: 'Department Shares',
              data: subCatTotals.entries.map((e) {
                final sub = don.GmwfSubCategory.values.firstWhereOrNull((s) => s.name == e.key);
                return _DistItem(
                  label: sub?.label ?? e.key.toUpperCase(),
                  value: e.value,
                  color: sub?.color ?? don.DS.ink500,
                );
              }).toList(),
              t: t,
            ),
          ];
          
          if (isWide) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: content[0]),
            content[1],
            Expanded(child: content[2]),
          ]);
          return Column(children: [content[0], content[1], content[2]]);
        }),
        
        const SizedBox(height: DS.s3),

        // 3. Top Donors List
        _TopDonorsCard(topDonors: topDonors.take(5).toList(), names: donorNames, t: t),
      ],
    );
  }

  DateTimeRange _resolveFilter(DashboardFilter filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (filter.timeRange) {
      case TimeRange.today: return DateTimeRange(start: today, end: today);
      case TimeRange.week:  return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case TimeRange.month: return DateTimeRange(start: today.subtract(const Duration(days: 30)), end: today);
      case TimeRange.custom: return filter.customRange ?? DateTimeRange(start: today, end: today);
    }
  }
}

class _DonationStatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final RoleThemeData t;

  const _DonationStatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DS.s2 + 4),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(DS.r3),
        border: Border.all(color: t.bgRule),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(DS.r1 + 4)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: DS.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: t.textTertiary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                AnimatedCount(
                  value: value,
                  prefix: 'PKR ',
                  style: TextStyle(color: t.textPrimary, fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistItem {
  final String label;
  final double value;
  final Color color;
  _DistItem({required this.label, required this.value, required this.color});
}

class _DistributionCard extends StatelessWidget {
  final String title;
  final List<_DistItem> data;
  final RoleThemeData t;

  const _DistributionCard({required this.title, required this.data, required this.t});

  @override
  Widget build(BuildContext context) {
    final total = data.fold(0.0, (sum, item) => sum + item.value);
    
    return Container(
      padding: const EdgeInsets.all(DS.s3),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(DS.r4),
        border: Border.all(color: t.bgRule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: DS.s3),
          if (total == 0)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No data for this period', style: TextStyle(color: DS.neutral, fontSize: 12)),
            ))
          else
            ...data.map((item) {
              final pct = (item.value / total);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(fmtPKR(item.value.toInt()), style: const TextStyle(color: DS.neutral, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedProgressBar(value: pct, color: item.color, height: 4),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _TopDonorsCard extends StatelessWidget {
  final List<MapEntry<String, double>> topDonors;
  final Map<String, String> names;
  final RoleThemeData t;

  const _TopDonorsCard({required this.topDonors, required this.names, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DS.s3),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(DS.r4),
        border: Border.all(color: t.bgRule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: don.DS.gold500, size: 20),
              const SizedBox(width: 8),
              Text('Top Contributors (Global)', style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: DS.s3),
          if (topDonors.isEmpty)
            const Center(child: Text('No donor data available', style: TextStyle(color: DS.neutral, fontSize: 12)))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topDonors.length,
              separatorBuilder: (_, __) => Divider(color: t.bgRule, height: 24),
              itemBuilder: (context, i) {
                final entry = topDonors[i];
                final name = names[entry.key] ?? 'Unknown Donor';
                final isMobile = MediaQuery.of(context).size.width < 600;
                return Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: t.accentMuted, shape: BoxShape.circle),
                      child: Center(child: Text('${i + 1}', style: TextStyle(color: t.accent, fontWeight: FontWeight.w900, fontSize: 13))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(color: t.textPrimary, fontSize: isMobile ? 12 : 13, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text('Donor ID: ${entry.key}', style: TextStyle(color: t.textTertiary, fontSize: isMobile ? 9 : 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmtPKR(entry.value.toInt()), style: TextStyle(color: don.DS.emerald600, fontSize: isMobile ? 12 : 14, fontWeight: FontWeight.w900)),
                        Text(isMobile ? 'Total' : 'Total Contributions', style: const TextStyle(color: DS.neutral, fontSize: 9, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
