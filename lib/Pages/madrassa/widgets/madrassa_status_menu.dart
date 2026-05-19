import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../madrassa_strings.dart';
import 'madrassa_common_widgets.dart';
import '../../../theme/app_theme.dart';
import '../dialogs/enrollment_dialog.dart';

class StatusActionMenu extends StatelessWidget {
  final QueryDocumentSnapshot student;
  final String branchId;
  final bool isAdmin;
  final RoleThemeData t;

  const StatusActionMenu({
    super.key,
    required this.student,
    required this.branchId,
    required this.isAdmin,
    required this.t,
  });

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    final sData = student.data() as Map<String, dynamic>;
    final currentStatus = sData['status'] ?? 'active';
    if (newStatus == currentStatus) return;

    String statusLabelEn = '';
    
    if (newStatus == 'active') {
      statusLabelEn = MStr.en.statusActive;
    } else if (newStatus == 'archived') {
      statusLabelEn = MStr.en.statusArchived;
    } else if (newStatus == 'hifz_completed') {
      statusLabelEn = MStr.en.statusHifzCompleted;
    } else if (newStatus == 'left') {
      statusLabelEn = MStr.en.statusLeft;
    }

    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          newStatus == 'active' ? MStr.en.unarchiveStudent : MStr.en.archiveStudent,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              MStr.en.confirmAction.replaceAll('{action}', statusLabelEn).replaceAll('{name}', sData['name'] ?? ''),
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
              child: Text(MStr.en.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'active' ? Colors.green : Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(MStr.en.confirm),
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
      await student.reference.update(updates);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sData = student.data() as Map<String, dynamic>;
    final status = sData['status'] ?? 'active';

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: t.textTertiary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (val) {
        if (val == 'edit') {
          showAddStudentDialog(context, branchId, student: student);
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
            child: Text(MStr.en.statusActive),
          ),
        if (status == 'active') ...[
          PopupMenuItem(
            value: 'archived',
            child: Text(MStr.en.statusArchived),
          ),
          PopupMenuItem(
            value: 'hifz_completed',
            child: Text(MStr.en.statusHifzCompleted),
          ),
          PopupMenuItem(
            value: 'left',
            child: Text(MStr.en.statusLeft),
          ),
        ],
      ],
    );
  }
}
