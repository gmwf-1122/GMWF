import 'package:flutter/material.dart';
import '../../../constants/colors.dart';
import '../donations_shared.dart';

class FilterBar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;

  const FilterBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 24),
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.gray200, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedCategory,
            icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.gray500),
            isExpanded: true,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.gray800,
            ),
            onChanged: (val) {
              if (val != null) onCategoryChanged(val);
            },
            items: categories.map((catName) {
              final catEnum = DonationCategory.values.firstWhere(
                (e) => e.name == catName, 
                orElse: () => DonationCategory.gmwf
              );
              return DropdownMenuItem<String>(
                value: catName,
                child: Row(
                  children: [
                    Icon(catEnum.icon, size: 16, color: catEnum.color),
                    const SizedBox(width: 8),
                    Text(catEnum.label),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
