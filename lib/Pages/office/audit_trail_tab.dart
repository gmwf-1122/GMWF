// lib/pages/office/audit_trail_tab.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/local_storage_service.dart';
import '../../services/sync_service.dart';
import 'shared_widgets.dart';

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
  bool _showConflicts = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveConflict(Map<String, dynamic> conflict, bool useLocal) async {
    final String entityId = conflict['entityId']?.toString() ?? '';
    final String entityType = conflict['entityType']?.toString() ?? '';
    final String branchId = conflict['branchId']?.toString() ?? widget.branchId;
    final Map<String, dynamic> localData = Map<String, dynamic>.from(conflict['local'] as Map);
    final Map<String, dynamic> remoteData = Map<String, dynamic>.from(conflict['remote'] as Map);

    try {
      if (useLocal) {
        localData['syncStatus'] = 'pending';
        localData['updatedAt'] = DateTime.now().toUtc().toIso8601String();
        localData['sync_version'] = (localData['sync_version'] as int? ?? 0) + 1;

        if (entityType == 'employee') {
          await Hive.box(LocalStorageService.employeesBox).put(entityId, localData);
        } else if (entityType == 'loan') {
          await Hive.box(LocalStorageService.financeLoansBox).put(entityId, localData);
        } else if (entityType == 'expense') {
          await Hive.box(LocalStorageService.expensesBox).put(entityId, localData);
        } else if (entityType == 'ledger') {
          await Hive.box(LocalStorageService.salaryLedgerBox).put(entityId, localData);
        }
      } else {
        remoteData['syncStatus'] = 'synced';

        if (entityType == 'employee') {
          await Hive.box(LocalStorageService.employeesBox).put(entityId, remoteData);
        } else if (entityType == 'loan') {
          await Hive.box(LocalStorageService.financeLoansBox).put(entityId, remoteData);
        } else if (entityType == 'expense') {
          await Hive.box(LocalStorageService.expensesBox).put(entityId, remoteData);
        } else if (entityType == 'ledger') {
          await Hive.box(LocalStorageService.salaryLedgerBox).put(entityId, remoteData);
        }
      }

      final settingsBox = Hive.box(LocalStorageService.financeSettingsBox);
      final conflicts = List<Map<String, dynamic>>.from(
        (settingsBox.get('sync_conflicts') as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      conflicts.removeWhere((c) => c['entityId'] == entityId && c['entityType'] == entityType);
      await settingsBox.put('sync_conflicts', conflicts);
      await settingsBox.flush();

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('sync_conflicts')
          .doc(entityId)
          .update({'status': 'resolved', 'resolvedWith': useLocal ? 'local' : 'remote'});

      if (mounted) {
        showCustomSnackBar(context, 'Conflict resolved using ${useLocal ? "local" : "cloud"} version.');
        setState(() {});
      }
      SyncService().triggerUpload();
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(context, 'Failed to resolve: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tOriginal = RoleThemeScope.dataOf(context);
    final t = RoleThemeData(
      roleLabel: tOriginal.roleLabel,
      isDarkCanvas: false,
      bg: const Color(0xFFF8FAFC),
      bgCard: Colors.white,
      bgCardAlt: const Color(0xFFF1F5F9),
      bgRule: const Color(0xFFE2E8F0),
      accent: const Color(0xFF10B981),
      accentLight: const Color(0xFF34D399),
      accentMuted: const Color(0xFFD1FAE5),
      accentGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
      glassTint: const Color(0x1A10B981),
      textPrimary: const Color(0xFF111827),
      textSecondary: const Color(0xFF6B7280),
      textTertiary: const Color(0xFF9CA3AF),
      danger: const Color(0xFFEF4444),
      zakat: tOriginal.zakat,
      nonZakat: tOriginal.nonZakat,
      gmwf: tOriginal.gmwf,
      cardFillTokens: tOriginal.cardFillTokens,
      cardFillPrescriptions: tOriginal.cardFillPrescriptions,
      cardFillDispensary: tOriginal.cardFillDispensary,
      chartBar1: tOriginal.chartBar1,
      chartBar2: tOriginal.chartBar2,
      chartBar3: tOriginal.chartBar3,
      chartGrid: tOriginal.chartGrid,
    );

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(
        children: [
          // Segmented Tab Switcher
          ValueListenableBuilder(
            valueListenable: Hive.box(LocalStorageService.financeSettingsBox).listenable(),
            builder: (ctx, Box settingsBox, _) {
              final conflictsList = List<Map<String, dynamic>>.from(
                (settingsBox.get('sync_conflicts') as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
              );
              final conflictCount = conflictsList.length;

              return Container(
                color: t.bgCard,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      height: 34,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: t.bgCardAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: Row(
                        children: [
                          _buildToggleButton('Audit Logs', !_showConflicts, 0, t),
                          _buildToggleButton('Conflicts Review', _showConflicts, conflictCount, t),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          if (!_showConflicts) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: t.bgCard,
                border: Border(bottom: BorderSide(color: t.bgRule, width: 0.5)),
              ),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: t.bgCardAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.bgRule),
                ),
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

                      Color actionColor = Colors.blue;
                      IconData actionIcon = Icons.edit_rounded;
                      if (act == 'CREATE') {
                        actionColor = Colors.green;
                        actionIcon = Icons.add_circle_outline_rounded;
                      } else if (act == 'DELETE' || act == 'VOID') {
                        actionColor = Colors.red;
                        actionIcon = Icons.remove_circle_outline_rounded;
                      } else if (act == 'TRANSFER') {
                        actionColor = Colors.purple;
                        actionIcon = Icons.swap_horiz_rounded;
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Column(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: actionColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: actionColor.withValues(alpha: 0.3), width: 1),
                                  ),
                                  child: Icon(actionIcon, color: actionColor, size: 14),
                                ),
                                if (idx < logs.length - 1)
                                  Container(
                                    width: 2,
                                    height: 80,
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
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: t.bgRule, width: 0.75),
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
            ),
          ] else ...[
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: Hive.box(LocalStorageService.financeSettingsBox).listenable(),
                builder: (ctx, Box settingsBox, _) {
                  final conflicts = List<Map<String, dynamic>>.from(
                    (settingsBox.get('sync_conflicts') as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
                  );

                  if (conflicts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done_outlined, size: 48, color: t.accent),
                          const SizedBox(height: 12),
                          Text('No sync conflicts detected. Clean sync state.', style: TextStyle(color: t.textSecondary, fontSize: 13)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: conflicts.length,
                    itemBuilder: (ctx, idx) {
                      final conflict = conflicts[idx];
                      final entityId = conflict['entityId'] as String;
                      final entityType = conflict['entityType'] as String;
                      final local = Map<String, dynamic>.from(conflict['local'] as Map);
                      final remote = Map<String, dynamic>.from(conflict['remote'] as Map);

                      final diffs = <Map<String, dynamic>>[];
                      final allKeys = {...local.keys, ...remote.keys};
                      for (final k in allKeys) {
                        if (['syncStatus', 'updatedAt', 'sync_version', 'lastSyncedAt', 'markedAt', 'createdAt'].contains(k)) {
                          continue;
                        }
                        final lv = local[k];
                        final rv = remote[k];
                        if (lv != rv) {
                          diffs.add({
                            'field': k,
                            'local': lv,
                            'remote': rv,
                          });
                        }
                      }

                      return Card(
                        color: t.bgCard,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: t.bgRule)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: t.danger, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${entityType.toUpperCase()} Conflict',
                                    style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'ID: $entityId',
                                    style: TextStyle(color: t.textTertiary, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'A concurrent edit was detected. Resolve the differences below by selecting which version is correct:',
                                style: TextStyle(color: t.textSecondary, fontSize: 11),
                              ),
                              const SizedBox(height: 14),
                              
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(6)),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 2, child: Text('Field', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                                    Expanded(flex: 3, child: Text('Local Client Value', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10))),
                                    Expanded(flex: 3, child: Text('Cloud Server Value', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10))),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),

                              ...diffs.map((d) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          d['field'].toString(),
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          d['local']?.toString() ?? 'null',
                                          style: const TextStyle(color: Colors.green, fontSize: 11),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          d['remote']?.toString() ?? 'null',
                                          style: const TextStyle(color: Colors.blue, fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),

                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.green,
                                        side: const BorderSide(color: Colors.green, width: 0.5),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _resolveConflict(conflict, true),
                                      child: const Text('Keep Local (Cloud Overwrite)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.blue,
                                        side: const BorderSide(color: Colors.blue, width: 0.5),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _resolveConflict(conflict, false),
                                      child: const Text('Accept Cloud (Discard Local)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool active, int count, RoleThemeData t) {
    final String displayLabel = count > 0 ? '$label ($count)' : label;

    return InkWell(
      onTap: () => setState(() => _showConflicts = label == 'Conflicts Review'),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? (label == 'Conflicts Review' && count > 0 ? t.danger : t.accent) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: (label == 'Conflicts Review' && count > 0 ? t.danger : t.accent).withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          displayLabel,
          style: TextStyle(
            color: active ? Colors.white : t.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
