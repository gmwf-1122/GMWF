import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import '../utils/madrassa_local_storage.dart';
import '../../../../widgets/app_feedback.dart';
import '../madrassa_strings.dart';

void showChangeStudentBranchDialog(
  BuildContext context, {
  required Map<String, dynamic> student,
  required String currentBranch,
  required String username,
  required String role,
  VoidCallback? onTransferred,
}) {
  final studentName = (student['name'] ?? 'Student').toString();
  final rollNumber = (student['rollNumber'] ?? '-').toString();
  final studentId = (student['id'] ?? student['studentId'] ?? '').toString();
  final initialBranch = MadrassaLocalStorage.normalizeBranch(
    (student['branchId'] ?? student['branch'] ?? currentBranch).toString(),
  );

  final availableBranches = MadrassaLocalStorage.getAvailableBranchesForSelection();
  String selectedBranch = initialBranch;
  if (!availableBranches.any((b) => b['id'] == selectedBranch) && availableBranches.isNotEmpty) {
    selectedBranch = availableBranches.first['id']!;
  }

  bool isTransferring = false;
  String? errorMessage;

  showDialog(
    context: context,
    barrierDismissible: !isTransferring,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDs) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bg = isDark ? SoftPalette.slate800 : SoftPalette.gray50;
        final cardBg = isDark ? SoftPalette.slate900 : SoftPalette.gray100;
        final textPrimary = isDark ? SoftPalette.gray50 : SoftPalette.gray900;
        final textMuted = isDark ? SoftPalette.slate400 : SoftPalette.slate600;

        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SoftPalette.indigo500.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: SoftPalette.indigo500,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.isUrdu ? 'طالب علم کی برانچ تبدیل کریں' : 'Change Student Branch',
                      style: context.urduStyle(
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.isUrdu ? 'صرف ہیڈ کوارٹر مینیجر (HQ Manager)' : 'HQ Manager Authorization',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: SoftPalette.indigo500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Student info card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? SoftPalette.slate700 : SoftPalette.slate200,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: SoftPalette.teal550.withValues(alpha: 0.15),
                        child: Text(
                          studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S',
                          style: const TextStyle(
                            color: SoftPalette.teal550,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Roll #: $rollNumber • ${student['class'] ?? 'Hifz'}',
                              style: TextStyle(fontSize: 12, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: SoftPalette.amber400.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SoftPalette.amber400.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          initialBranch.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? SoftPalette.amber200 : SoftPalette.amber700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Destination branch selector
                Text(
                  context.isUrdu ? 'نئی برانچ منتخب کریں:' : 'Select Target Branch:',
                  style: context.urduStyle(
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  decoration: BoxDecoration(
                    color: isDark ? SoftPalette.slate900 : SoftPalette.gray50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: SoftPalette.indigo500.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedBranch,
                      isExpanded: true,
                      dropdownColor: bg,
                      icon: const Icon(Icons.arrow_drop_down_rounded, color: SoftPalette.indigo500),
                      items: availableBranches.map((b) {
                        final isCurrent = b['id'] == initialBranch;
                        return DropdownMenuItem<String>(
                          value: b['id']!,
                          child: Row(
                            children: [
                              Icon(
                                Icons.apartment_rounded,
                                size: 16,
                                color: isCurrent ? SoftPalette.slate400 : SoftPalette.indigo500,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  b['name']! + (isCurrent ? ' (Current / موجودہ)' : ''),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isCurrent ? FontWeight.normal : FontWeight.bold,
                                    color: isCurrent ? textMuted : textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: isTransferring
                          ? null
                          : (val) {
                              if (val != null) {
                                setDs(() {
                                  selectedBranch = val;
                                  errorMessage = null;
                                });
                              }
                            },
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SoftPalette.teal550.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SoftPalette.teal550.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: SoftPalette.teal550),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.isUrdu
                              ? 'طالب علم صرف اپنی نئی منتخب شدہ برانچ میں نظر آئے گا اور پرانی برانچ کے ریکارڈز صاف کر دیے جائیں گے۔'
                              : 'Student will strictly appear only in the selected branch roster and daily logs. Old branch cache and references will be purged.',
                          style: context.urduStyle(
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? SoftPalette.teal200 : SoftPalette.teal800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: SoftPalette.red400, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isTransferring ? null : () => Navigator.pop(ctx),
              child: Text(
                context.l.cancel,
                style: TextStyle(color: textMuted),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: SoftPalette.indigo550,
                foregroundColor: SoftPalette.gray50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isTransferring
                  ? null
                  : () async {
                      if (selectedBranch == initialBranch) {
                        setDs(() => errorMessage = context.isUrdu
                            ? 'براہ کرم کوئی مختلف برانچ منتخب کریں'
                            : 'Please select a different branch to transfer');
                        return;
                      }

                      setDs(() {
                        isTransferring = true;
                        errorMessage = null;
                      });

                      try {
                        await MadrassaLocalStorage.transferStudentBranch(
                          oldBranch: initialBranch,
                          newBranch: selectedBranch,
                          studentId: studentId,
                          studentData: student,
                          editorUsername: username,
                          editorRole: role,
                        );

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          AppFeedback.showSuccess(
                            context,
                            context.isUrdu
                                ? 'طالب علم کی برانچ کامیابی سے تبدیل ہو گئی'
                                : 'Student transferred to ${selectedBranch.toUpperCase()} successfully!',
                            subtitle: 'Student roster updated and old branch records purged.',
                          );
                          onTransferred?.call();
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDs(() {
                            isTransferring = false;
                            errorMessage = 'Failed to transfer: $e';
                          });
                        }
                      }
                    },
              icon: isTransferring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: SoftPalette.gray50),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                context.isUrdu ? 'برانچ تبدیل کریں' : 'Transfer Student',
                style: context.urduStyle(
                  style: const TextStyle(fontWeight: FontWeight.bold, color: SoftPalette.gray50),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
