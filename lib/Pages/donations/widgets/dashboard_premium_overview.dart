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
                _AddDonationButton(onTap: onAddTap),
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
                  if (onImportTap != null) ...[
                    const SizedBox(width: 10),
                    SizedBox(width: 130, child: DashboardActionTile(
                      icon: Icons.file_upload_rounded, label: 'Import Excel', color: Colors.teal.shade700,
                      onTap: onImportTap!,
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
                if (onImportTap != null) ...[
                  const SizedBox(width: 12),
                  Expanded(child: DashboardActionTile(
                    icon: Icons.file_upload_rounded, label: 'Import Excel', color: Colors.teal.shade700,
                    onTap: onImportTap!,
                  )),
                ],
              ],
            ),
        ],
      );
    });
  }
}

class _AddDonationButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddDonationButton({required this.onTap});

  @override
  State<_AddDonationButton> createState() => _AddDonationButtonState();
}

class _AddDonationButtonState extends State<_AddDonationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: ScaleButton(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isHovered
                    ? [AppColors.primaryMid, AppColors.primary]
                    : [AppColors.primary, AppColors.primaryMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: _isHovered ? 16 : 8,
                  offset: _isHovered ? const Offset(0, 6) : const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: _isHovered ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: AnimatedScale(
                    scale: _isHovered ? 1.2 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Add New Donation',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
