import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:gmwf/design/components/app_toast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../madrassa_strings.dart';
import 'madrassa_common_widgets.dart';
import '../../../theme/app_theme.dart';
import '../dialogs/enrollment_dialog.dart';
import '../utils/madrassa_local_storage.dart';
import '../../../widgets/media_upload_tile.dart';
import '../../../realtime/realtime_manager.dart';
import '../../../realtime/realtime_events.dart';
import '../../../services/local_storage_service.dart';
import '../../../services/sync_service.dart';
import 'dart:async';

class StatusActionMenu extends StatelessWidget {
  final dynamic student;
  final String branchId;
  final bool isAdmin;
  final RoleThemeData t;
  final String username;
  final String role;

  const StatusActionMenu({
    super.key,
    required this.student,
    required this.branchId,
    required this.isAdmin,
    required this.t,
    required this.username,
    required this.role,
  });

  Map<String, dynamic> _getStudentData() {
    if (student is DocumentSnapshot) {
      return _asStringMap((student as DocumentSnapshot).data()) ?? <String, dynamic>{};
    } else {
      return _asStringMap(student) ?? <String, dynamic>{};
    }
  }

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    final sData = _getStudentData();
    final studentId = student is DocumentSnapshot ? (student as DocumentSnapshot).id : (student as Map)['id'].toString();
    final currentStatus = sData['status'] ?? 'active';
    if (newStatus == currentStatus) return;

    String statusLabelEn = '';
    if (newStatus == 'active') {
      statusLabelEn = context.l.statusActive;
    } else if (newStatus == 'archived') {
      statusLabelEn = context.l.statusArchived;
    } else if (newStatus == 'hifz_completed') {
      statusLabelEn = context.l.statusHifzCompleted;
    } else if (newStatus == 'nazra_completed') {
      statusLabelEn = context.l.statusNazraCompleted;
    } else if (newStatus == 'left') {
      statusLabelEn = context.l.statusLeft;
    } else if (newStatus == 'dropped') {
      statusLabelEn = context.isUrdu ? 'خارج' : 'Dropped Out';
    }

    // Statuses that carry their own event date, and the Firestore field it's stored in
    const dateFieldForStatus = {
      'archived': 'archivedDate',
      'hifz_completed': 'hifzCompletionDate',
      'nazra_completed': 'nazraCompletionDate',
      'left': 'leftDate',
      'dropped': 'droppedDate',
    };
    final isUnarchive = newStatus == 'active';
    final requiresDate = dateFieldForStatus.containsKey(newStatus);
    final dateFieldName = dateFieldForStatus[newStatus];

    String dialogTitle;
    if (isUnarchive) {
      dialogTitle = context.l.unarchiveStudent;
    } else if (newStatus == 'hifz_completed') {
      dialogTitle = context.isUrdu ? 'حفظ کی تکمیل' : 'Mark Hifz Completed';
    } else if (newStatus == 'nazra_completed') {
      dialogTitle = context.l.markNazraCompleted;
    } else if (newStatus == 'left') {
      dialogTitle = context.isUrdu ? 'طالب علم چھوڑ گیا' : 'Mark as Left';
    } else if (newStatus == 'dropped') {
      dialogTitle = context.isUrdu ? 'طالب علم خارج' : 'Mark as Dropped Out';
    } else {
      dialogTitle = context.l.archiveStudent;
    }

    Color confirmColor;
    if (isUnarchive) {
      confirmColor = SoftPalette.green400;
    } else if (newStatus == 'hifz_completed') {
      confirmColor = SoftPalette.indigo550;
    } else if (newStatus == 'nazra_completed') {
      confirmColor = SoftPalette.teal500;
    } else if (newStatus == 'left') {
      confirmColor = SoftPalette.red400;
    } else if (newStatus == 'dropped') {
      confirmColor = SoftPalette.red400;
    } else {
      confirmColor = SoftPalette.amber300;
    }

    final reasonCtrl = TextEditingController();
    // Required statuses default to today; unarchive starts empty (optional, opt-in)
    DateTime? selectedDate = requiresDate ? DateTime.now() : null;
    String? hifzCertBase64 = sData['hifzCertificateUrl'] ?? sData['hifzCertificateBase64'];
    String? nazraCertBase64 = sData['nazraCertificateUrl'] ?? sData['nazraCertificateBase64'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) {
          return AlertDialog(
            backgroundColor: t.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              dialogTitle,
              style: context.urduStyle(style: TextStyle(fontWeight: FontWeight.bold, color: t.textPrimary)),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l.confirmAction.replaceAll('{action}', statusLabelEn).replaceAll('{name}', sData['name'] ?? ''),
                    style: context.urduStyle(style: TextStyle(color: t.textSecondary)),
                  ),
                  if (requiresDate || isUnarchive) ...[
                    const SizedBox(height: 16),
                    Text(
                      isUnarchive
                          ? (ctx.isUrdu ? 'دوبارہ فعال ہونے کی تاریخ (اختیاری)' : 'Reactivation Date (optional)')
                          : (ctx.isUrdu ? 'واقعہ کی تاریخ' : 'Event Date'),
                      style: context.urduStyle(
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ctx.adapt(SoftPalette.teal550)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: selectedDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setDs(() => selectedDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: t.bgRule),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today_outlined, size: 16, color: ctx.adapt(SoftPalette.teal550)),
                                  const SizedBox(width: 10),
                                  Text(
                                    selectedDate != null
                                        ? DateFormat('d MMM yyyy').format(selectedDate!)
                                        : (ctx.isUrdu ? 'کوئی تاریخ منتخب نہیں' : 'No date selected'),
                                    style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Only unarchive can clear back to "no date" — required statuses always keep one
                        if (isUnarchive && selectedDate != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.clear, size: 18, color: ctx.adapt(SoftPalette.gray350)),
                            tooltip: 'Clear',
                            onPressed: () => setDs(() => selectedDate = null),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (newStatus == 'hifz_completed') ...[
                    const SizedBox(height: 16),
                    MediaUploadTile(
                      label: 'Certificate of Hifz Completion',
                      icon: Icons.workspace_premium_outlined,
                      initialValue: hifzCertBase64,
                      isDocument: true,
                      onChanged: (val) => setDs(() => hifzCertBase64 = val),
                    ),
                  ],
                  if (newStatus == 'nazra_completed') ...[
                    const SizedBox(height: 16),
                    MediaUploadTile(
                      label: context.l.nazraCertificate,
                      icon: Icons.menu_book_rounded,
                      initialValue: nazraCertBase64,
                      isDocument: true,
                      onChanged: (val) => setDs(() => nazraCertBase64 = val),
                    ),
                  ],
                  const SizedBox(height: 20),
                  buildTf(
                    reasonCtrl,
                    'Custom Reason / Additional Notes',
                    Icons.comment,
                    context,
                    hint: 'e.g. Moved to another city',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.l.cancel, style: context.urduStyle())),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: SoftPalette.gray50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(context.l.confirm, style: context.urduStyle()),
              ),
            ],
          );
        },
      ),
    );

    if (confirm == true) {
      final now = Timestamp.now();
      final customReason = reasonCtrl.text.trim();
      String baseReason = statusLabelEn;
      if (requiresDate && selectedDate != null) {
        baseReason = '$statusLabelEn on ${DateFormat('d MMM yyyy').format(selectedDate!)}';
      }
      final finalReason = customReason.isEmpty ? baseReason : '$baseReason: $customReason';

      final updates = <String, dynamic>{
        'status': newStatus,
        'batch': newStatus,
        if (newStatus == 'hifz_completed' && hifzCertBase64 != null) ...{
          'hifzCertificateUrl': hifzCertBase64,
          'hifzCertificateBase64': hifzCertBase64,
        },
        if (newStatus == 'nazra_completed' && nazraCertBase64 != null) ...{
          'nazraCertificateUrl': nazraCertBase64,
          'nazraCertificateBase64': nazraCertBase64,
        },
        'auditLog': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'type': 'status_change',
            'date': now,
            'reason': finalReason,
          }
        ]),
      };

      if (requiresDate && dateFieldName != null && selectedDate != null) {
        updates[dateFieldName] = Timestamp.fromDate(selectedDate!);
      }
      if (isUnarchive && selectedDate != null) {
        updates['reactivatedDate'] = Timestamp.fromDate(selectedDate!);
      }

      if (newStatus == 'left' || newStatus == 'dropped' || newStatus == 'archived') {
        // Full offboard: Hive first, unenroll PIN, revoke app access, broadcast & queue
        await MadrassaLocalStorage.deleteOrOffboardStudentLocalAndSync(
          branchId: branchId,
          studentId: studentId,
          status: newStatus,
          reason: finalReason,
          effectiveDate: selectedDate,
        );
      } else {
        // Active, Hifz completed, or Nazra completed: instant local Hive cache update & flush
        final studentCache = MadrassaLocalStorage.getStudentCached(branchId, studentId) ?? Map<String, dynamic>.from(sData);
        studentCache['status'] = newStatus;
        studentCache['batch'] = newStatus;
        if (newStatus == 'hifz_completed' && hifzCertBase64 != null) {
          studentCache['hifzCertificateUrl'] = hifzCertBase64;
          studentCache['hifzCertificateBase64'] = hifzCertBase64;
        }
        if (newStatus == 'nazra_completed' && nazraCertBase64 != null) {
          studentCache['nazraCertificateUrl'] = nazraCertBase64;
          studentCache['nazraCertificateBase64'] = nazraCertBase64;
        }
        if (requiresDate && dateFieldName != null && selectedDate != null) {
          studentCache[dateFieldName] = selectedDate!.toIso8601String();
        }
        studentCache['lastUpdatedAt'] = DateTime.now().toIso8601String();
        studentCache['syncStatus'] = 'pending';

        final auditList = List<Map<String, dynamic>>.from(
          (studentCache['auditLog'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
        auditList.add({
          'status': newStatus,
          'type': 'status_change',
          'date': (selectedDate ?? DateTime.now()).toIso8601String(),
          'reason': finalReason,
        });
        studentCache['auditLog'] = auditList;

        await MadrassaLocalStorage.cacheStudent(branchId, studentId, studentCache);

        // Broadcast LAN
        try {
          final payload = RealtimeEvents.payload(
            type: RealtimeEvents.saveMadrassaStudent,
            data: {
              ...studentCache,
              'studentId': studentId,
            },
            branchId: branchId,
          );
          RealtimeManager().sendMessage(payload);
        } catch (e) {
          debugPrint('[MadrassaStatusMenu] LAN broadcast error: $e');
        }

        // Always enqueue sync
        try {
          await LocalStorageService.enqueueSync({
            'type': 'save_madrassa_student',
            'branchId': branchId,
            'studentId': studentId,
            'data': studentCache,
          });
          unawaited(SyncService().triggerUpload());
        } catch (e) {
          debugPrint('[MadrassaStatusMenu] enqueueSync error: $e');
        }
      }

      // Calculate active tenure duration
      final joinDate = _parseDateTime(sData['joinDate']);
      final durationStr = _formatDuration(joinDate, selectedDate ?? DateTime.now());
      String statusDetail = '';
      if (newStatus == 'hifz_completed') {
        statusDetail = 'Hifz Completed in $durationStr';
      } else if (newStatus == 'archived') {
        statusDetail = 'Moved to Archive after $durationStr of active study';
      } else if (newStatus == 'left') {
        statusDetail = 'Marked as Left after $durationStr';
      } else if (newStatus == 'dropped') {
        statusDetail = 'Expelled / Dropped Out after $durationStr';
      } else if (newStatus == 'active') {
        statusDetail = 'Reactivated into Active classes';
      }

      final auditMsg = '${sData['name'] ?? 'Student'} status changed from ${currentStatus.toUpperCase()} to ${newStatus.toUpperCase()} ($statusDetail). Note: $finalReason';

      // Centralized Audit Log
      await MadrassaAuditService.logAction(
        branchId: branchId,
        editor: username,
        role: role,
        type: 'status_change',
        message: auditMsg,
        studentId: studentId,
        studentName: sData['name'],
      );
    }
  }

  String _formatDuration(DateTime start, DateTime end) {
    int years = end.year - start.year;
    int months = end.month - start.month;
    int days = end.day - start.day;

    if (days < 0) {
      months -= 1;
      final prevMonth = DateTime(end.year, end.month, 0);
      days += prevMonth.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }

    final parts = <String>[];
    if (years > 0) parts.add('$years ${years == 1 ? "year" : "years"}');
    if (months > 0) parts.add('$months ${months == 1 ? "month" : "months"}');
    if (days > 0 || parts.isEmpty) parts.add('$days ${days == 1 ? "day" : "days"}');
    return parts.join(', ');
  }

  void _showHistoryDialog(BuildContext context) {
    final sData = _getStudentData();
    final name = sData['name'] ?? '';
    final joinDate = _parseDateTime(sData['joinDate']);

    final rawAudit = sData['auditLog'];
    final auditListRaw = rawAudit is List ? rawAudit : [];
    final auditList = List<Map<String, dynamic>>.from(
      auditListRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
    );

    // Sort audit list chronologically (oldest first for a sequential timeline)
    auditList.sort((a, b) {
      final aDate = _parseDateTime(a['date']);
      final bDate = _parseDateTime(b['date']);
      return aDate.compareTo(bDate);
    });

    final durationStr = _formatDuration(joinDate, DateTime.now());

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            context.l.auditLog,
            style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Student: $name',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Duration: $durationStr',
                  style: TextStyle(color: ctx.adapt(SoftPalette.gray500), fontSize: 13),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                if (auditList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No history records found.'),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: auditList.length,
                      itemBuilder: (context, idx) {
                        final log = auditList[idx];
                        final logStatus = log['status'] ?? 'unknown';
                        final logType = log['type'] ?? 'info';
                        final logDate = _parseDateTime(log['date']);
                        final logReason = log['reason'] ?? '';

                        Color dotColor = context.adapt(SoftPalette.gray350);
                        IconData icon = Icons.circle;
                        if (logStatus == 'active' || logType == 'enrollment' || logType == 'rejoin_approval') {
                          dotColor = context.adapt(SoftPalette.teal550); // Teal
                          icon = Icons.check_circle_outline;
                        } else if (logStatus == 'left' || logType == 'rejoin_rejection') {
                          dotColor = context.adapt(SoftPalette.red400);
                          icon = Icons.error_outline;
                        } else if (logStatus == 'archived') {
                          dotColor = context.adapt(SoftPalette.amber300);
                          icon = Icons.archive_outlined;
                        } else if (logStatus == 'hifz_completed') {
                          dotColor = context.adapt(SoftPalette.indigo550); // Purple
                          icon = Icons.stars_outlined;
                        } else if (logStatus == 'dropped') {
                          dotColor = context.adapt(SoftPalette.red400);
                          icon = Icons.remove_circle_outline;
                        }

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                children: [
                                  Icon(icon, color: dotColor, size: 22),
                                  if (idx < auditList.length - 1)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        color: context.adapt(SoftPalette.gray150),
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${logStatus.toUpperCase()} (${logType.replaceAll('_', ' ')})',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: dotColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        logReason,
                                        style: TextStyle(fontSize: 12, color: context.adapt(SoftPalette.gray900A87)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('dd MMMM yyyy, hh:mm a').format(logDate),
                                        style: TextStyle(
                                          color: context.adapt(SoftPalette.gray350),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  bool get _isHQManager {
    final r = role.toLowerCase().trim();
    return r.contains('hqmanager') ||
        r.contains('hq manager') ||
        r.contains('hq_manager') ||
        r == 'hq' ||
        r.contains('chairman');
  }

  Future<void> _confirmDeleteStudent(BuildContext context) async {
    final sData = _getStudentData();
    final studentName = sData['name'] ?? 'Student';
    final studentId = student is DocumentSnapshot ? (student as DocumentSnapshot).id : (student as Map)['id'].toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ctx.adapt(SoftPalette.red400).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_forever, color: ctx.adapt(SoftPalette.red400), size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              ctx.isUrdu ? 'طالب علم ڈیلیٹ کریں؟' : 'Delete Student?',
              style: ctx.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Text(
          ctx.isUrdu
              ? 'کیا آپ واقعی $studentName کو مستقل طور پر ڈیلیٹ کرنا چاہتے ہیں؟ یہ عمل واپس نہیں لیا جا سکتا۔'
              : 'Are you sure you want to permanently delete $studentName? This action cannot be undone and will permanently remove all student records.',
          style: ctx.urduStyle(style: const TextStyle(fontSize: 14)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.isUrdu ? 'منسوخ کریں' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SoftPalette.red400,
              foregroundColor: SoftPalette.gray50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.isUrdu ? 'ڈیلیٹ کریں' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MadrassaLocalStorage.permanentlyDeleteStudent(
        branchId: branchId,
        studentId: studentId,
      );
      await MadrassaAuditService.logAction(
        branchId: branchId,
        editor: username,
        role: role,
        type: 'delete_student',
        message: 'Student $studentName permanently deleted by $username ($role).',
        studentId: studentId,
        studentName: studentName,
      );
      if (context.mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(
            content: Text('$studentName deleted successfully'),
            backgroundColor: SoftPalette.red400,
          ),
        );
      }
    }
  }

  Future<void> _showRevertQaidaDialog(BuildContext context) async {
    final sData = _getStudentData();
    final studentId = student is DocumentSnapshot ? (student as DocumentSnapshot).id : (student as Map)['id'].toString();
    final studentName = sData['name'] ?? 'Student';
    String selectedLesson = '21';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isUrdu = ctx.isUrdu;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: dialogCtx.adapt(SoftPalette.amber200).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.undo_rounded, color: dialogCtx.adapt(SoftPalette.orange350), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isUrdu ? 'قاعدہ تکمیل منسوخ کریں' : 'Revert Qaida Completion',
                      style: ctx.urduStyle(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUrdu
                        ? 'کیا آپ $studentName کے لیے قاعدہ کی تکمیل منسوخ کرنا چاہتے ہیں؟ موجودہ تختی / سبق منتخب کریں:'
                        : 'Revert accidental Qaida completion for $studentName. Select current lesson to resume from:',
                    style: ctx.urduStyle(style: TextStyle(fontSize: 13, color: dialogCtx.adapt(SoftPalette.gray900A87))),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isUrdu ? 'سبق / تختی:' : 'Qaida Lesson (1–21):',
                    style: ctx.urduStyle(style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dialogCtx.adapt(SoftPalette.gray350))),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: dialogCtx.adapt(SoftPalette.gray150)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedLesson,
                        isExpanded: true,
                        items: [
                          for (int i = 21; i >= 1; i--)
                            DropdownMenuItem<String>(
                              value: '$i',
                              child: Text(
                                isUrdu ? 'سبق $i (تختی $i)' : 'Lesson $i',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedLesson = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(isUrdu ? 'منسوخ' : 'Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SoftPalette.orange350,
                    foregroundColor: SoftPalette.gray50,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(isUrdu ? 'منسوخ اور محفوظ کریں' : 'Revert & Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm == true) {
      final studentCache = MadrassaLocalStorage.getStudentCached(branchId, studentId) ?? Map<String, dynamic>.from(sData);
      studentCache['qaidaCompleted'] = false;
      studentCache['qaidaSabak'] = selectedLesson;
      studentCache['lastUpdatedAt'] = DateTime.now().toIso8601String();

      final auditList = List<Map<String, dynamic>>.from(
        (studentCache['auditLog'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      auditList.add({
        'status': studentCache['status'] ?? 'active',
        'type': 'qaida_reverted',
        'date': DateTime.now().toIso8601String(),
        'reason': 'Reverted Qaida completion to Lesson $selectedLesson',
      });
      studentCache['auditLog'] = auditList;
      studentCache['lastUpdatedAt'] = DateTime.now().toIso8601String();
      studentCache['syncStatus'] = 'pending';

      await MadrassaLocalStorage.cacheStudent(branchId, studentId, studentCache);

      if (student is Map) {
        (student as Map)['qaidaCompleted'] = false;
        (student as Map)['qaidaSabak'] = selectedLesson;
      }

      // Broadcast LAN
      try {
        final payload = RealtimeEvents.payload(
          type: RealtimeEvents.saveMadrassaStudent,
          data: {
            ...studentCache,
            'studentId': studentId,
          },
          branchId: branchId,
        );
        RealtimeManager().sendMessage(payload);
      } catch (e) {
        debugPrint('[MadrassaStatusMenu] LAN broadcast error: $e');
      }

      // Enqueue sync & upload
      try {
        await LocalStorageService.enqueueSync({
          'type': 'save_madrassa_student',
          'branchId': branchId,
          'studentId': studentId,
          'data': studentCache,
        });
        unawaited(SyncService().triggerUpload());
      } catch (e) {
        debugPrint('[MadrassaStatusMenu] enqueueSync error: $e');
      }

      await MadrassaAuditService.logAction(
        branchId: branchId,
        editor: username,
        role: role,
        type: 'qaida_reverted',
        message: 'Reverted Qaida completion for $studentName to Lesson $selectedLesson by $username ($role).',
        studentId: studentId,
        studentName: studentName,
      );

      if (context.mounted) {
        AppToast.showSnackBar(context, 
          SnackBar(
            content: Text(
              context.isUrdu
                  ? '$studentName کے لیے قاعدہ تکمیل منسوخ ہو گئی (سبق $selectedLesson)'
                  : 'Qaida completion reverted for $studentName to Lesson $selectedLesson',
            ),
            backgroundColor: SoftPalette.orange350,
          ),
        );
      }
    }
  }

  bool _isNazraStudent(Map<String, dynamic> sData) {
    return (sData['isNazra'] == true) ||
        (sData['program']?.toString().toLowerCase() == 'nazra') ||
        (sData['class']?.toString().toLowerCase() == 'nazra') ||
        (sData['course']?.toString().toLowerCase() == 'nazra') ||
        (sData['category']?.toString().toLowerCase() == 'nazra') ||
        LocalStorageService.isMadrassaNazraOnly(branchId);
  }

  @override
  Widget build(BuildContext context) {
    final sData = _getStudentData();
    final status = sData['status'] ?? 'active';
    final isNazra = _isNazraStudent(sData);
    final isQaidaCompleted = sData['qaidaCompleted'] == true || sData['qaidaSabak'] == 'completed';

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: t.textTertiary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (val) {
        if (val == 'edit') {
          showAddStudentDialog(
            context,
            branchId,
            student: student,
            username: username,
            role: role,
          );
        } else if (val == 'revert_qaida') {
          _showRevertQaidaDialog(context);
        } else if (val == 'history') {
          _showHistoryDialog(context);
        } else if (val == 'delete_student') {
          _confirmDeleteStudent(context);
        } else {
          _updateStatus(context, val);
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ctx.adapt(SoftPalette.indigo550).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_rounded, size: 16, color: ctx.adapt(SoftPalette.indigo550)),
              ),
              const SizedBox(width: 10),
              Text(
                'Edit Student Profile',
                style: context.urduStyle(style: TextStyle(fontWeight: FontWeight.bold, color: ctx.adapt(SoftPalette.indigo550), fontSize: 13)),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (status != 'active')
          PopupMenuItem(
            value: 'active',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ctx.adapt(SoftPalette.green400).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.check_circle_rounded, size: 16, color: ctx.adapt(SoftPalette.green400)),
                ),
                const SizedBox(width: 10),
                Text(context.l.statusActive, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ],
            ),
          ),
        if (status == 'active') ...[
          if (!isNazra)
            PopupMenuItem(
              value: 'hifz_completed',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: ctx.adapt(SoftPalette.indigo550).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.workspace_premium_rounded, size: 16, color: ctx.adapt(SoftPalette.indigo550)),
                  ),
                  const SizedBox(width: 10),
                  Text(context.l.statusHifzCompleted, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                ],
              ),
            ),
          if (isNazra) ...[
            PopupMenuItem(
              value: 'nazra_completed',
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: ctx.adapt(SoftPalette.teal500).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.menu_book_rounded, size: 16, color: ctx.adapt(SoftPalette.teal500)),
                  ),
                  const SizedBox(width: 10),
                  Text(context.l.statusNazraCompleted, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                ],
              ),
            ),
            if (isQaidaCompleted)
              PopupMenuItem(
                value: 'revert_qaida',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: ctx.adapt(SoftPalette.amber200).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.undo_rounded, size: 16, color: ctx.adapt(SoftPalette.orange350)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      context.isUrdu ? 'قاعدہ تکمیل منسوخ کریں' : 'Revert Qaida Completion',
                      style: context.urduStyle(style: TextStyle(fontWeight: FontWeight.w600, color: ctx.adapt(SoftPalette.orange350), fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
          PopupMenuItem(
            value: 'left',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ctx.adapt(SoftPalette.red400).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.exit_to_app_rounded, size: 16, color: ctx.adapt(SoftPalette.red400)),
                ),
                const SizedBox(width: 10),
                Text(context.l.statusLeft, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'dropped',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ctx.adapt(SoftPalette.red400).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person_off_rounded, size: 16, color: ctx.adapt(SoftPalette.red400)),
                ),
                const SizedBox(width: 10),
                Text(context.isUrdu ? 'خارج' : 'Dropped Out', style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'archived',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ctx.adapt(SoftPalette.amber300).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.archive_rounded, size: 16, color: ctx.adapt(SoftPalette.amber300)),
                ),
                const SizedBox(width: 10),
                Text(context.l.statusArchived, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'history',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ctx.adapt(SoftPalette.gray350).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.history_rounded, size: 16, color: ctx.adapt(SoftPalette.gray350)),
              ),
              const SizedBox(width: 10),
              Text('Audit & Status History', style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
            ],
          ),
        ),
        if (_isHQManager) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete_student',
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ctx.adapt(SoftPalette.red400).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.delete_forever_rounded, size: 16, color: ctx.adapt(SoftPalette.red400)),
                ),
                const SizedBox(width: 10),
                Text(
                  context.isUrdu ? 'طالب علم ڈیلیٹ کریں' : 'Delete Student',
                  style: context.urduStyle(
                    style: TextStyle(fontWeight: FontWeight.bold, color: ctx.adapt(SoftPalette.red400), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

Map<String, dynamic>? _asStringMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

DateTime _parseDateTime(dynamic val) {
  if (val == null) return DateTime.now();
  if (val is Timestamp) return val.toDate();
  if (val is String) {
    return DateTime.tryParse(val) ?? DateTime.now();
  }
  if (val is DateTime) return val;
  return DateTime.now();
}