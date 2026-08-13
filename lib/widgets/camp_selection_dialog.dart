// lib/widgets/camp_selection_dialog.dart

import 'package:flutter/material.dart';

class CampSelectionDialog extends StatelessWidget {
  final List<String> assignedCamps;
  final String? currentCamp;
  final ValueChanged<String> onSelected;
  final bool isDismissible;

  const CampSelectionDialog({
    super.key,
    required this.assignedCamps,
    this.currentCamp,
    required this.onSelected,
    this.isDismissible = false,
  });

  static const Map<String, String> _knownLabels = {
    'kapayya': 'Kapayya Dispensary',
    'haji_camp': 'Haji Camp Dispensary',
  };

  static String getLabel(String id) {
    final key = id.trim().toLowerCase();
    if (_knownLabels.containsKey(key)) return _knownLabels[key]!;
    return id.split('_').map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = Container(
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.local_hospital_rounded, color: colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Active Facility',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Which camp facility are you working at right now?',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (isDismissible)
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: assignedCamps.map((campId) {
                  final isSelected = campId.toLowerCase().trim() == currentCamp?.toLowerCase().trim();
                  final label = getLabel(campId);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.12)
                          : theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.2),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          onSelected(campId);
                          if (isDismissible && Navigator.canPop(context)) {
                            Navigator.of(context).pop();
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  label,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? colorScheme.primary : theme.textTheme.titleMedium?.color,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 24),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );

    if (isDismissible) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: content,
          ),
        ),
      ),
    );
  }

  static Future<void> showSwitchCampDialog(BuildContext context, {
    required List<String> assignedCamps,
    required String? currentCamp,
    required ValueChanged<String> onSelected,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CampSelectionDialog(
        assignedCamps: assignedCamps,
        currentCamp: currentCamp,
        onSelected: onSelected,
        isDismissible: true,
      ),
    );
  }
}
