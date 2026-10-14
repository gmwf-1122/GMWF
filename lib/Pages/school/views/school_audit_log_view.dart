// lib/pages/school/views/school_audit_log_view.dart

import 'package:flutter/material.dart';
import 'package:gmwf/design/design_system.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../../services/local_storage_service.dart';
import '../utils/school_local_storage.dart';
import '../utils/school_auth_helper.dart';
import '../theme/school_theme.dart';

class SchoolAuditLogView extends StatelessWidget {
  final String branchId;
  final String userRole;

  const SchoolAuditLogView({
    super.key,
    required this.branchId,
    this.userRole = 'School Admin',
  }); 

  @override
  Widget build(BuildContext context) {
    if (SchoolAuthHelper.isTeacher(userRole)) {
      return const SchoolAccessDenied(
        title: 'Audit Trail Restricted',
        message: 'The institutional audit trail contains confidential administrative logs and is reserved strictly for School Principal and Administration.',
      );
    }

    return FutureBuilder<void>(
      future: SchoolLocalStorage.ensureBoxesOpen(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: context.adapt(SchoolTheme.bgLight),
            body: Center(child: CircularProgressIndicator(color: context.adapt(SchoolTheme.primary))),
          );
        }

        return Scaffold(
          backgroundColor: context.adapt(SchoolTheme.bgLight),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'School Audit Trail & Activity Log',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.adapt(SoftPalette.slate900),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Track all modifications, admissions, daily logs, and library operations across the school module.',
                  style: TextStyle(color: context.adapt(SoftPalette.gray500), fontSize: 14),
                ),
                const SizedBox(height: 20),

                Expanded(
                  child: ValueListenableBuilder<Box>(
                    valueListenable: Hive.box(LocalStorageService.schoolAuditLogsBox).listenable(),
                    builder: (context, box, _) {
                      final logs = SchoolLocalStorage.getAuditLogsCached(branchId);

                      if (logs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_rounded, size: 64, color: context.adapt(SoftPalette.gray150)),
                              const SizedBox(height: 12),
                              Text(
                                'No audit log entries recorded yet.',
                                style: TextStyle(color: context.adapt(SoftPalette.gray350), fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Actions in student registry, attendance, and library will be logged here.',
                                style: TextStyle(color: context.adapt(SoftPalette.gray350)),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final entry = logs[index];
                          final action = (entry['action'] ?? 'ACTION').toString();
                          final user = (entry['user'] ?? 'System').toString();
                          final details = (entry['details'] ?? '').toString();
                          final tsStr = (entry['timestamp'] ?? '').toString();

                          DateTime? dt;
                          if (tsStr.isNotEmpty) {
                            dt = DateTime.tryParse(tsStr);
                          }

                          final timeFormatted = dt != null
                              ? DateFormat('dd MMM yyyy, hh:mm a').format(dt)
                              : 'Recent';

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.adapt(SoftPalette.gray50),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.adapt(SoftPalette.gray100)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: context.adapt(SoftPalette.sky700).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.security_rounded, color: context.adapt(SoftPalette.sky700), size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: context.adapt(SoftPalette.slate150),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              action,
                                              style: TextStyle(
                                                color: context.adapt(SoftPalette.indigo600),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'By $user',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: context.adapt(SoftPalette.slate700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        details,
                                        style: TextStyle(color: context.adapt(SoftPalette.gray550), fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  timeFormatted,
                                  style: TextStyle(color: context.adapt(SoftPalette.gray350), fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
