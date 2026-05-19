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
              ScaleButton(
                onTap: onClearFilters,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
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
                ),
              )
            else
              ScaleButton(
                onTap: onAddTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
                  ),
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
              ),
          ],
        ),
      ),
    );
  }
}
