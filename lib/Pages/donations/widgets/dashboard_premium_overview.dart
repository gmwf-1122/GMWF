import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../constants/colors.dart';
import '../../../models/donation_models.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/role_theme_provider.dart';
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
  final VoidCallback? onImportTap;

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
    this.onImportTap,
  });

  @override
  Widget build(BuildContext context) {
    double total = 0, received = 0, pending = 0;
    int receivedCount = 0;
    int pendingCount = 0;

    for (var d in currentDonations) {
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      total += amt;
      if (d.status == DonationStatus.received) {
        received += amt;
        receivedCount++;
      } else {
        pending += amt;
        pendingCount++;
      }
    }
    final fmt = NumberFormat('#,##0');

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 750;
      final t = RoleThemeScope.dataOf(context);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Action Buttons Row (Matching branches.dart action buttons) ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _buildActionPill(
                  context: context,
                  t: t,
                  icon: Icons.add_circle_rounded,
                  label: 'New Receipt',
                  color: t.accent,
                  isPrimary: true,
                  onTap: onAddTap,
                ),
                const SizedBox(width: 10),
                _buildActionPill(
                  context: context,
                  t: t,
                  icon: Icons.people_alt_rounded,
                  label: 'Donors Registry',
                  color: const Color(0xFF6366F1),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => DonorRegistryDialog(branchId: branchId, branchName: branchName),
                  ),
                ),
                const SizedBox(width: 10),
                _buildActionPill(
                  context: context,
                  t: t,
                  icon: Icons.file_download_rounded,
                  label: 'Export Excel',
                  color: const Color(0xFF10B981),
                  onTap: onExportTap,
                ),
                const SizedBox(width: 10),
                _buildActionPill(
                  context: context,
                  t: t,
                  icon: Icons.analytics_rounded,
                  label: 'Analytics Summary',
                  color: const Color(0xFF0EA5E9),
                  isActive: isAnalyticsActive,
                  onTap: onSummaryTap,
                ),
                if (role.canSeeAllBranches) ...[
                  const SizedBox(width: 10),
                  _buildActionPill(
                    context: context,
                    t: t,
                    icon: Icons.history_rounded,
                    label: 'Global Audit Trail',
                    color: const Color(0xFFF59E0B),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GlobalAuditTrailScreen(role: role)),
                    ),
                  ),
                ],
                if (onImportTap != null) ...[
                  const SizedBox(width: 10),
                  _buildActionPill(
                    context: context,
                    t: t,
                    icon: Icons.file_upload_rounded,
                    label: 'Import Excel',
                    color: const Color(0xFF8B5CF6),
                    onTap: onImportTap!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── 3 Summary KPI Cards ──
          if (isMobile)
            Column(
              children: [
                DashboardStatCard(
                  label: 'TOTAL VOLUME',
                  value: fmt.format(total),
                  icon: Icons.account_balance_wallet_rounded,
                  accentColor: const Color(0xFF6366F1),
                  barColor: const Color(0xFF6366F1),
                  trendText: '${currentDonations.length} records recorded',
                ),
                const SizedBox(height: 12),
                DashboardStatCard(
                  label: 'RECEIVED',
                  value: fmt.format(received),
                  icon: Icons.check_circle_rounded,
                  accentColor: const Color(0xFF10B981),
                  barColor: const Color(0xFF10B981),
                  trendText: '$receivedCount verified received',
                ),
                const SizedBox(height: 12),
                DashboardStatCard(
                  label: 'PENDING VERIFICATION',
                  value: fmt.format(pending),
                  icon: Icons.hourglass_top_rounded,
                  accentColor: const Color(0xFFF59E0B),
                  barColor: const Color(0xFFF59E0B),
                  trendText: '$pendingCount pending clearing',
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: DashboardStatCard(
                    label: 'TOTAL VOLUME',
                    value: fmt.format(total),
                    icon: Icons.account_balance_wallet_rounded,
                    accentColor: const Color(0xFF6366F1),
                    barColor: const Color(0xFF6366F1),
                    trendText: '${currentDonations.length} records recorded',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DashboardStatCard(
                    label: 'RECEIVED',
                    value: fmt.format(received),
                    icon: Icons.check_circle_rounded,
                    accentColor: const Color(0xFF10B981),
                    barColor: const Color(0xFF10B981),
                    trendText: '$receivedCount verified received',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DashboardStatCard(
                    label: 'PENDING VERIFICATION',
                    value: fmt.format(pending),
                    icon: Icons.hourglass_top_rounded,
                    accentColor: const Color(0xFFF59E0B),
                    barColor: const Color(0xFFF59E0B),
                    trendText: '$pendingCount pending clearing',
                  ),
                ),
              ],
            ),
        ],
      );
    });
  }

  Widget _buildActionPill({
    required BuildContext context,
    required RoleThemeData t,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isActive = false,
    bool isPrimary = false,
  }) {
    final bgColor = isPrimary
        ? color
        : isActive
            ? color.withValues(alpha: 0.15)
            : t.bgCard;
    final borderColor = isPrimary ? color : (isActive ? color : t.bgRule);
    final fgColor = isPrimary ? Colors.white : t.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: fgColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
