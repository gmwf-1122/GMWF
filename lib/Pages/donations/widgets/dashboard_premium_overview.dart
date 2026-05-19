import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../constants/colors.dart';
import '../../../models/donation_models.dart';
import '../donations_shared.dart';
import '../donors_registry.dart';
import '../global_audit_trail.dart';
import 'dashboard_stat_card.dart';
import 'dashboard_action_tile.dart';

class DashboardPremiumOverview extends StatelessWidget {
  final List<DonationRecord> currentDonations;
  final String branchName;
  final String branchId;
  final UserRole role;
  final VoidCallback onAddTap;
  final VoidCallback onExportTap;
  final VoidCallback onSummaryTap;
  final bool isAnalyticsActive;

  const DashboardPremiumOverview({
    super.key,
    required this.currentDonations,
    required this.branchName,
    required this.branchId,
    required this.role,
    required this.onAddTap,
    required this.onExportTap,
    required this.onSummaryTap,
    required this.isAnalyticsActive,
  });

  @override
  Widget build(BuildContext context) {
    double total = 0, received = 0, pending = 0;
    for (var d in currentDonations) {
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      total += amt;
      if (d.status == DonationStatus.received) {
        received += amt;
      } else {
        pending += amt;
      }
    }
    final fmt = NumberFormat('#,##0');

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 650;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Donations Overview',
                      style: TextStyle(
                          fontSize: isMobile ? 24 : 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.gray900,
                          letterSpacing: -0.8),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      branchName,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.gray500,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 16),
                ScaleButton(
                  onTap: onAddTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.gray200),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_rounded, size: 18, color: AppColors.gray800),
                        SizedBox(width: 8),
                        Text('Add New Donation',
                            style: TextStyle(
                                color: AppColors.gray800,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          if (isMobile)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  SizedBox(width: 180, child: DashboardStatCard(label: 'TOTAL VOLUME', value: fmt.format(total), icon: Icons.bar_chart_rounded, accentColor: const Color(0xFF1A237E), barColor: const Color(0xFF1A237E))),
                  const SizedBox(width: 12),
                  SizedBox(width: 180, child: DashboardStatCard(label: 'RECEIVED', value: fmt.format(received), icon: Icons.check_rounded, accentColor: const Color(0xFF00897B), barColor: const Color(0xFFB2DFDB))),
                  const SizedBox(width: 12),
                  SizedBox(width: 180, child: DashboardStatCard(label: 'PENDING', value: fmt.format(pending), icon: Icons.hourglass_bottom_rounded, accentColor: const Color(0xFFF57C00), barColor: const Color(0xFFFFCC80))),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(child: DashboardStatCard(label: 'TOTAL VOLUME', value: fmt.format(total), icon: Icons.bar_chart_rounded, accentColor: const Color(0xFF1A237E), barColor: const Color(0xFF1A237E))),
                const SizedBox(width: 16),
                Expanded(child: DashboardStatCard(label: 'RECEIVED', value: fmt.format(received), icon: Icons.check_rounded, accentColor: const Color(0xFF00897B), barColor: const Color(0xFFB2DFDB))),
                const SizedBox(width: 16),
                Expanded(child: DashboardStatCard(label: 'PENDING', value: fmt.format(pending), icon: Icons.hourglass_bottom_rounded, accentColor: const Color(0xFFF57C00), barColor: const Color(0xFFFFCC80))),
              ],
            ),
          const SizedBox(height: 16),
          if (isMobile)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  SizedBox(width: 120, child: DashboardActionTile(
                    icon: Icons.people_alt_rounded, label: 'Donors', color: const Color(0xFF5E35B1),
                    onTap: () => showDialog(context: context, builder: (_) => DonorRegistryDialog(branchId: branchId, branchName: branchName)),
                  )),
                  const SizedBox(width: 10),
                  SizedBox(width: 120, child: DashboardActionTile(
                    icon: Icons.file_download_rounded, label: 'Export', color: const Color(0xFF2E7D32),
                    onTap: onExportTap,
                  )),
                  const SizedBox(width: 10),
                  SizedBox(width: 120, child: DashboardActionTile(
                    icon: Icons.show_chart_rounded, label: 'Summary', color: const Color(0xFF1565C0),
                    onTap: onSummaryTap, isActive: isAnalyticsActive,
                  )),
                  if (role.canSeeAllBranches) ...[
                    const SizedBox(width: 10),
                    SizedBox(width: 140, child: DashboardActionTile(
                      icon: Icons.history_rounded, label: 'Global Audit', color: const Color(0xFFE65100),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalAuditTrailScreen(role: role))),
                    )),
                  ],
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(child: DashboardActionTile(
                  icon: Icons.people_alt_rounded, label: 'Donors', color: const Color(0xFF5E35B1),
                  onTap: () => showDialog(context: context, builder: (_) => DonorRegistryDialog(branchId: branchId, branchName: branchName)),
                )),
                const SizedBox(width: 12),
                Expanded(child: DashboardActionTile(
                  icon: Icons.file_download_rounded, label: 'Export', color: const Color(0xFF2E7D32),
                  onTap: onExportTap,
                )),
                const SizedBox(width: 12),
                Expanded(child: DashboardActionTile(
                  icon: Icons.show_chart_rounded, label: 'Summary', color: const Color(0xFF1565C0),
                  onTap: onSummaryTap, isActive: isAnalyticsActive,
                )),
                if (role.canSeeAllBranches) ...[
                  const SizedBox(width: 12),
                  Expanded(child: DashboardActionTile(
                    icon: Icons.history_rounded, label: 'Global Audit', color: const Color(0xFFE65100),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalAuditTrailScreen(role: role))),
                  )),
                ],
              ],
            ),
        ],
      );
    });
  }
}
