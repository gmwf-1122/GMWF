// lib/pages/dispensary/widgets/pharmacy_pane_layout_dialog.dart
//
// Modal dialog allowing the user to view all available 3-column pharmacy layouts
// and directly select their preferred order (Tokens, Register/Vitals, Dispense).

import 'package:flutter/material.dart';
import '../../../../design/design_system.dart';
import '../../../../services/dispensary_preferences_service.dart';

class PharmacyPaneLayoutDialog extends StatefulWidget {
  final String? userId;
  final ValueChanged<String>? onSelected;

  const PharmacyPaneLayoutDialog({
    super.key,
    this.userId,
    this.onSelected,
  });

  /// Opens the selection dialog and returns the selected layout id if changed.
  static Future<String?> show(
    BuildContext context, {
    String? userId,
    ValueChanged<String>? onSelected,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PharmacyPaneLayoutDialog(
        userId: userId,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<PharmacyPaneLayoutDialog> createState() => _PharmacyPaneLayoutDialogState();
}

class _PharmacyPaneLayoutDialogState extends State<PharmacyPaneLayoutDialog> {
  late String _selectedOrder;

  @override
  void initState() {
    super.initState();
    _selectedOrder = DispensaryPreferencesService.getPharmacyPaneOrder(widget.userId);
  }

  Future<void> _selectLayout(String layoutId, String title) async {
    setState(() => _selectedOrder = layoutId);
    await DispensaryPreferencesService.setPharmacyPaneOrder(layoutId, explicitUserKey: widget.userId);
    AppToast.show(
      message: 'Columns updated: $title',
      kind: GToastKind.success,
    );
    widget.onSelected?.call(layoutId);
    if (mounted) {
      Navigator.of(context).pop(layoutId);
    }
  }

  List<_PaneInfo> _resolvePanes(String id) {
    switch (id) {
      case DispensaryPreferencesService.paneLayoutTokensDispenseReception:
        return const [
          _PaneInfo('Tokens List', Icons.receipt_long_rounded, SoftPalette.emerald500),
          _PaneInfo('Dispense Form', Icons.medication_outlined, SoftPalette.teal600),
          _PaneInfo('Register / Vitals', Icons.person_outline_rounded, SoftPalette.sky500),
        ];
      case DispensaryPreferencesService.paneLayoutReceptionTokensDispense:
        return const [
          _PaneInfo('Register / Vitals', Icons.person_outline_rounded, SoftPalette.sky500),
          _PaneInfo('Tokens List', Icons.receipt_long_rounded, SoftPalette.emerald500),
          _PaneInfo('Dispense Form', Icons.medication_outlined, SoftPalette.teal600),
        ];
      case DispensaryPreferencesService.paneLayoutReceptionDispenseTokens:
        return const [
          _PaneInfo('Register / Vitals', Icons.person_outline_rounded, SoftPalette.sky500),
          _PaneInfo('Dispense Form', Icons.medication_outlined, SoftPalette.teal600),
          _PaneInfo('Tokens List', Icons.receipt_long_rounded, SoftPalette.emerald500),
        ];
      case DispensaryPreferencesService.paneLayoutDispenseTokensReception:
        return const [
          _PaneInfo('Dispense Form', Icons.medication_outlined, SoftPalette.teal600),
          _PaneInfo('Tokens List', Icons.receipt_long_rounded, SoftPalette.emerald500),
          _PaneInfo('Register / Vitals', Icons.person_outline_rounded, SoftPalette.sky500),
        ];
      case DispensaryPreferencesService.paneLayoutDispenseReceptionTokens:
        return const [
          _PaneInfo('Dispense Form', Icons.medication_outlined, SoftPalette.teal600),
          _PaneInfo('Register / Vitals', Icons.person_outline_rounded, SoftPalette.sky500),
          _PaneInfo('Tokens List', Icons.receipt_long_rounded, SoftPalette.emerald500),
        ];
      case DispensaryPreferencesService.paneLayoutTokensReceptionDispense:
      default:
        return const [
          _PaneInfo('Tokens List', Icons.receipt_long_rounded, SoftPalette.emerald500),
          _PaneInfo('Register / Vitals', Icons.person_outline_rounded, SoftPalette.sky500),
          _PaneInfo('Dispense Form', Icons.medication_outlined, SoftPalette.teal600),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final layouts = DispensaryPreferencesService.availablePaneLayouts;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? SoftPalette.slate900 : SoftPalette.gray50,
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (isDark ? SoftPalette.teal550 : SoftPalette.emerald600).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.view_column_rounded,
                      size: 24,
                      color: isDark ? SoftPalette.emerald300 : SoftPalette.emerald600,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pharmacy Column Layout',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? SoftPalette.gray50 : SoftPalette.slate900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Select your preferred panel arrangement for the single-screen desk',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? SoftPalette.slate350 : SoftPalette.slate550,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    color: isDark ? SoftPalette.slate400 : SoftPalette.slate500,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Available options list
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: layouts.map((layout) {
                      final id = layout['id']!;
                      final title = layout['title']!;
                      final subtitle = layout['subtitle']!;
                      final isSelected = _selectedOrder == id;
                      final isDefault = id == DispensaryPreferencesService.paneLayoutTokensReceptionDispense;
                      final panes = _resolvePanes(id);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => _selectLayout(id, title),
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark
                                      ? SoftPalette.teal550.withValues(alpha: 0.2)
                                      : SoftPalette.green100m.withValues(alpha: 0.7))
                                  : (isDark ? SoftPalette.slate800 : SoftPalette.gray100),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? (isDark ? SoftPalette.emerald350 : SoftPalette.emerald550)
                                    : (isDark ? SoftPalette.slate700 : SoftPalette.slate200),
                                width: isSelected ? 1.8 : 1.0,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: SoftPalette.emerald550.withValues(alpha: isDark ? 0.25 : 0.12),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                      size: 20,
                                      color: isSelected
                                          ? (isDark ? SoftPalette.emerald300 : SoftPalette.emerald600)
                                          : (isDark ? SoftPalette.slate500 : SoftPalette.slate400),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: isDark ? SoftPalette.gray50 : SoftPalette.slate900,
                                            ),
                                          ),
                                          if (isDefault) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: isDark ? SoftPalette.slate700 : SoftPalette.slate200,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Default',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? SoftPalette.slate300 : SoftPalette.slate600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.only(left: 30),
                                  child: Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? SoftPalette.slate350 : SoftPalette.slate600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Visual preview sequence badges
                                Padding(
                                  padding: const EdgeInsets.only(left: 30),
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < panes.length; i++) ...[
                                        _buildPaneBadge(panes[i], isDark),
                                        if (i < panes.length - 1)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 11,
                                              color: isDark ? SoftPalette.slate500 : SoftPalette.slate400,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => _selectLayout(
                      DispensaryPreferencesService.paneLayoutTokensReceptionDispense,
                      'List · Token · Dispense (Default)',
                    ),
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('Reset to Default'),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? SoftPalette.slate400 : SoftPalette.slate600,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_selectedOrder),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? SoftPalette.teal550 : SoftPalette.emerald600,
                      foregroundColor: SoftPalette.gray50,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaneBadge(_PaneInfo pane, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: pane.color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: pane.color.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pane.icon, size: 11, color: pane.color),
          const SizedBox(width: 4),
          Text(
            pane.name,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: pane.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaneInfo {
  final String name;
  final IconData icon;
  final Color color;

  const _PaneInfo(this.name, this.icon, this.color);
}
