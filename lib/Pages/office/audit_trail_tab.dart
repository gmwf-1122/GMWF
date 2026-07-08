// lib/pages/office/audit_trail_tab.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/role_theme_provider.dart';
import '../../services/finance_local_storage.dart';

class AuditTrailTab extends StatefulWidget {
  final String branchId;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const AuditTrailTab({
    super.key,
    required this.branchId,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  State<AuditTrailTab> createState() => _AuditTrailTabState();
}

class _AuditTrailTabState extends State<AuditTrailTab> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return Column(
      children: [
        Container(
          color: t.bgCard,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Container(
            height: 38,
            decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Filter logs by employee name, CNIC, or action...',
                hintStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                prefixIcon: Icon(Icons.search, color: t.textTertiary, size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (val) {
                widget.onSearchChanged(val);
                setState(() {});
              },
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: FinanceLocalStorage.auditLogsBox.listenable(),
            builder: (ctx, Box box, _) {
              final logs = FinanceLocalStorage.getAuditLogs(widget.branchId, searchQuery: _searchCtrl.text);
              if (logs.isEmpty) {
                return Center(
                  child: Text('No audit logs recorded for this branch.', style: TextStyle(color: t.textTertiary, fontSize: 12)),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: logs.length,
                itemBuilder: (c, idx) {
                  final log = logs[idx];
                  final entity = log['entityType']?.toString().toUpperCase() ?? '';
                  final act = log['action']?.toString().toUpperCase() ?? '';
                  final date = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(log['timestamp']));
                  final reason = log['reason'] ?? '';

                  Color actionColor = t.isDarkCanvas ? Colors.blue[300]! : Colors.blue;
                  IconData actionIcon = Icons.edit_rounded;
                  if (act == 'CREATE') {
                    actionColor = t.isDarkCanvas ? Colors.green[300]! : Colors.green;
                    actionIcon = Icons.add_circle_outline_rounded;
                  } else if (act == 'DELETE' || act == 'VOID') {
                    actionColor = t.isDarkCanvas ? Colors.red[300]! : Colors.red;
                    actionIcon = Icons.remove_circle_outline_rounded;
                  } else if (act == 'TRANSFER') {
                    actionColor = t.isDarkCanvas ? Colors.purple[300]! : Colors.purple;
                    actionIcon = Icons.swap_horiz_rounded;
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Timeline indicator column
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Column(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: actionColor.withOpacity(0.12),
                                shape: BoxShape.circle,
                                border: Border.all(color: actionColor.withOpacity(0.3), width: 1),
                              ),
                              child: Icon(actionIcon, color: actionColor, size: 14),
                            ),
                            if (idx < logs.length - 1)
                              Container(
                                width: 2,
                                height: 80, // connection to next timeline node
                                color: t.bgRule,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          color: t.bgCard,
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: t.bgRule, width: 0.5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(6)),
                                      child: Text('$entity • $act', style: TextStyle(color: t.textSecondary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                    ),
                                    Text(date, style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (reason.toString().isNotEmpty) ...[
                                  Text(reason, style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('User: ${log['performedBy']}', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                    if (log['approvedBy'] != null)
                                      Text('Approved: ${log['approvedBy']}', style: TextStyle(color: t.textTertiary, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                if (log['fieldChanges'] != null && (log['fieldChanges'] as List).isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Divider(color: t.bgRule, height: 1),
                                  const SizedBox(height: 8),
                                  ...(log['fieldChanges'] as List).map((ch) {
                                    final c = Map<String, dynamic>.from(ch as Map);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                                      child: Text(
                                        '• ${c['field']}: "${c['oldValue'] ?? ""}" ➔ "${c['newValue'] ?? ""}"',
                                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: t.textSecondary),
                                      ),
                                    );
                                  }),
                                ]
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        )
      ],
    );
  }
}
