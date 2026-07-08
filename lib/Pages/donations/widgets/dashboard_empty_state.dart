import 'package:flutter/material.dart';
import '../../../constants/colors.dart';
import '../donations_shared.dart';

class DashboardEmptyState extends StatelessWidget {
  final DonationCategory selectedCategory;
  final DonationSubtype? selectedSubtype;
  final GmwfSubCategory? selectedGmwfSub;
  final bool isSearchActive;
  final String paymentMethodFilter;
  final double? minAmount;
  final double? maxAmount;
  final VoidCallback onClearFilters;
  final VoidCallback onAddTap;

  const DashboardEmptyState({
    super.key,
    required this.selectedCategory,
    required this.selectedSubtype,
    required this.selectedGmwfSub,
    required this.isSearchActive,
    required this.paymentMethodFilter,
    required this.minAmount,
    required this.maxAmount,
    required this.onClearFilters,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.03),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.receipt_long_rounded,
                      size: 40, color: AppColors.primary.withValues(alpha: 0.2)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text('No Transactions Found',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.gray900,
                    letterSpacing: -0.5)),
            const SizedBox(height: 8),
            const Text(
              'We couldn\'t find any donations matching your current filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: AppColors.gray500, height: 1.5),
            ),
            const SizedBox(height: 32),
            if (selectedCategory != DonationCategory.all ||
                selectedSubtype != null ||
                selectedGmwfSub != null ||
                isSearchActive ||
                paymentMethodFilter != 'All' ||
                minAmount != null ||
                maxAmount != null)
              _EmptyStateActionButton(
                onTap: onClearFilters,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off_rounded,
                        size: 18, color: Colors.white),
                    SizedBox(width: 10),
                    Text('Clear All Filters',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              )
            else
              _EmptyStateActionButton(
                onTap: onAddTap,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Record First Donation',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateActionButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _EmptyStateActionButton({
    required this.onTap,
    required this.child,
  });

  @override
  State<_EmptyStateActionButton> createState() => _EmptyStateActionButtonState();
}

class _EmptyStateActionButtonState extends State<_EmptyStateActionButton> {
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: _isHovered ? AppColors.primaryMid : AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: _isHovered ? 0.35 : 0.2),
                  blurRadius: _isHovered ? 16 : 10,
                  offset: _isHovered ? const Offset(0, 6) : const Offset(0, 4),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
