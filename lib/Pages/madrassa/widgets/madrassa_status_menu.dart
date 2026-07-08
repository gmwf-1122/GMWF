import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../madrassa_strings.dart';
import 'madrassa_common_widgets.dart';
import '../../../theme/app_theme.dart';
import '../dialogs/enrollment_dialog.dart';

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
    } else if (newStatus == 'left') {
      statusLabelEn = context.l.statusLeft;
    }

    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          newStatus == 'active' ? context.l.unarchiveStudent : context.l.archiveStudent,
          style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l.confirmAction.replaceAll('{action}', statusLabelEn).replaceAll('{name}', sData['name'] ?? ''),
              style: context.urduStyle(),
            ),
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
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l.cancel, style: context.urduStyle())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'active' ? Colors.green : Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(context.l.confirm, style: context.urduStyle()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final now = Timestamp.now();
      final customReason = reasonCtrl.text.trim();
      final finalReason = customReason.isEmpty ? statusLabelEn : '$statusLabelEn: $customReason';

      final updates = <String, dynamic>{
        'status': newStatus,
        'auditLog': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'type': 'status_change',
            'date': now,
            'reason': finalReason,
          }
        ]),
      };
      if (newStatus == 'hifz_completed') {
        updates['hifzCompletionDate'] = now;
      }
      final docRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_students')
          .doc(studentId);
      await docRef.update(updates);

      // Centralized Audit Log
      await MadrassaAuditService.logAction(
        branchId: branchId,
        editor: username,
        role: role,
        type: 'status_change',
        message: 'Status of student ${sData['name'] ?? ''} changed from $currentStatus to $newStatus. Reason: $finalReason',
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
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
                        final logDateTs = log['date'] as Timestamp?;
                        final logDate = logDateTs?.toDate() ?? DateTime.now();
                        final logReason = log['reason'] ?? '';

                        Color dotColor = Colors.grey;
                        IconData icon = Icons.circle;
                        if (logStatus == 'active' || logType == 'enrollment' || logType == 'rejoin_approval') {
                          dotColor = const Color(0xFF008080); // Teal
                          icon = Icons.check_circle_outline;
                        } else if (logStatus == 'left' || logType == 'rejoin_rejection') {
                          dotColor = Colors.redAccent;
                          icon = Icons.error_outline;
                        } else if (logStatus == 'archived') {
                          dotColor = Colors.orange;
                          icon = Icons.archive_outlined;
                        } else if (logStatus == 'hifz_completed') {
                          dotColor = const Color(0xFF4C4DDC); // Purple
                          icon = Icons.stars_outlined;
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
                                        color: Colors.grey[300],
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
                                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('dd MMMM yyyy, hh:mm a').format(logDate),
                                        style: TextStyle(
                                          color: Colors.grey[500],
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

  @override
  Widget build(BuildContext context) {
    final sData = _getStudentData();
    final status = sData['status'] ?? 'active';

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
        } else if (val == 'history') {
          _showHistoryDialog(context);
        } else {
          _updateStatus(context, val);
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'edit',
          child: Text('Edit Student Data', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4C4DDC))),
        ),
        const PopupMenuDivider(),
        if (status != 'active')
          PopupMenuItem(
            value: 'active',
            child: Text(context.l.statusActive, style: context.urduStyle()),
          ),
        if (status == 'active') ...[
          PopupMenuItem(
            value: 'archived',
            child: Text(context.l.statusArchived, style: context.urduStyle()),
          ),
          PopupMenuItem(
            value: 'hifz_completed',
            child: Text(context.l.statusHifzCompleted, style: context.urduStyle()),
          ),
          PopupMenuItem(
            value: 'left',
            child: Text(context.l.statusLeft, style: context.urduStyle()),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'history',
          child: Row(
            children: [
              const Icon(Icons.history, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text('View Status History', style: context.urduStyle()),
            ],
          ),
        ),
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
