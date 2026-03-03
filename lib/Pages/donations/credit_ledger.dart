import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/donations_local_storage.dart';
import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart';
import 'donations_shared.dart';

// ════════════════════════════════════════════════════════════════════════════════
// CREDIT ROLE CONSTANTS
// ════════════════════════════════════════════════════════════════════════════════

const String kRoleOfficeBoy = 'office_boy';
const String kRoleManager   = 'manager';
const String kRoleChairman  = 'chairman';

// ════════════════════════════════════════════════════════════════════════════════
// CREDIT LEDGER SERVICE
// ════════════════════════════════════════════════════════════════════════════════

class CreditLedgerService {
  final String branchId;
  CreditLedgerService(this.branchId);

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ── OB → Manager (auto-created on every cash donation by OB) ─────────────────
  Future<String> officeBoyAutoCredit({
    required String fromUserId,
    required String fromUsername,
    required double amount,
    required String categoryId,
    required String branchName,
    required String receiptNo,
    String? subtypeId,
    String  notes = '',
  }) async {
    return DonationsLocalStorage.saveCreditEntry(
      branchId: branchId,
      data: {
        'fromRole':            kRoleOfficeBoy,
        'fromUserId':          fromUserId,
        'fromUsername':        fromUsername,
        'toRole':              kRoleManager,
        'amount':              amount,
        'categoryId':          categoryId,
        'subtypeId':           subtypeId,
        'receiptNo':           receiptNo,
        'status':              kStatusPending,
        'date':                _today,
        'timestamp':           DateTime.now().toIso8601String(),
        'notes':               notes,
        'branchName':          branchName,
        'forwardedToChairman': false,
        'approvedBy':          null,
        'approvedAt':          null,
      },
    );
  }

  // ── Manager approves OB credit AND forwards equivalent to Chairman ────────────
  //
  // Uses DonationsLocalStorage.batchCreditOps which performs a single Firestore
  // batch commit — both the OB-entry approval and the new Chairman entry are
  // written atomically, preventing partial-write data integrity issues.
  Future<void> managerApproveAndForward({
    required String obDocId,        // Firestore doc ID of the OB credit entry
    required String managerUserId,
    required String managerUsername,
    required double amount,
    required String categoryId,
    required String branchName,
    required String receiptNo,
    String? subtypeId,
    String  notes = '',
  }) async {
    final chairmanEntry = {
      'fromRole':            kRoleManager,
      'fromUserId':          managerUserId,
      'fromUsername':        managerUsername,
      'toRole':              kRoleChairman,
      'amount':              amount,
      'categoryId':          categoryId,
      'subtypeId':           subtypeId,
      'linkedObDocId':       obDocId,
      'receiptNo':           receiptNo,
      'status':              kStatusPending,
      'date':                _today,
      'timestamp':           DateTime.now().toIso8601String(),
      'notes':               notes,
      'branchName':          branchName,
      'forwardedToChairman': false,
      'approvedBy':          null,
      'approvedAt':          null,
    };

    // Atomic batch — implemented in DonationsLocalStorage.batchCreditOps
    await DonationsLocalStorage.batchCreditOps(
      branchId:     branchId,
      updateKey:    obDocId,
      updateStatus: kStatusApproved,
      approvedBy:   managerUsername,
      newEntry:     chairmanEntry,
    );
  }

  Future<void> managerRejectCredit({
    required String obDocId,
    required String managerUsername,
  }) =>
      DonationsLocalStorage.updateCreditStatus(
          obDocId,
          status:     kStatusRejected,
          approvedBy: managerUsername,
          branchId:   branchId);

  Future<void> chairmanDecide({
    required String docId,
    required String decision,
    required String chairmanUsername,
  }) =>
      DonationsLocalStorage.updateCreditStatus(
          docId,
          status:     decision,
          approvedBy: chairmanUsername,
          branchId:   branchId);

  // ── Streams ───────────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> obToManagerPending() =>
      DonationsLocalStorage.streamCreditEntries(
          branchId: branchId, toRole: kRoleManager, status: kStatusPending);

  Stream<List<Map<String, dynamic>>> managerToChairmanPending() =>
      DonationsLocalStorage.streamCreditEntries(
          branchId: branchId, toRole: kRoleChairman, status: kStatusPending);

  Stream<List<Map<String, dynamic>>> chairmanApproved() =>
      DonationsLocalStorage.streamCreditEntries(
          branchId: branchId, toRole: kRoleChairman, status: kStatusApproved);

  Stream<List<Map<String, dynamic>>> obOwnCredits(String userId) =>
      DonationsLocalStorage.streamCreditEntries(
          branchId: branchId, toRole: kRoleManager, fromUserId: userId);

  // ── Helpers ───────────────────────────────────────────────────────────────────
  static bool isSynced(Map<String, dynamic> entry) =>
      entry['syncStatus'] == 'synced';

  static bool hasPendingSync(List<Map<String, dynamic>> entries) =>
      entries.any((e) => !isSynced(e));
}

// ════════════════════════════════════════════════════════════════════════════════
// MANAGER CREDITS DASHBOARD
// ════════════════════════════════════════════════════════════════════════════════

class ManagerCreditsDashboard extends StatefulWidget {
  final String branchId, branchName, userId, username;

  const ManagerCreditsDashboard({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.userId,
    required this.username,
  });

  @override
  State<ManagerCreditsDashboard> createState() =>
      _ManagerCreditsDashboardState();
}

class _ManagerCreditsDashboardState extends State<ManagerCreditsDashboard> {
  late final CreditLedgerService _svc;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _svc = CreditLedgerService(widget.branchId);
  }

  Future<void> _approve(Map<String, dynamic> doc) async {
    final docId = doc['hiveKey'] as String? ?? '';
    if (docId.isEmpty) return;

    final ok = await _creditConfirmDialog(
      context:   context,
      isApprove: true,
      amount:    (doc['amount'] as num?)?.toDouble() ?? 0,
      fromName:  doc['fromUsername'] as String? ?? '-',
    );
    if (ok != true || !mounted) return;

    setState(() => _processing = true);
    HapticFeedback.mediumImpact();

    try {
      await _svc.managerApproveAndForward(
        obDocId:         docId,
        managerUserId:   widget.userId,
        managerUsername: widget.username,
        amount:          (doc['amount'] as num?)?.toDouble() ?? 0,
        categoryId:      doc['categoryId'] as String? ?? 'general',
        subtypeId:       doc['subtypeId']  as String?,
        branchName:      widget.branchName,
        receiptNo:       doc['receiptNo']  as String? ?? '',
        notes:           doc['notes']      as String? ?? '',
      );
      if (mounted) {
        setState(() => _processing = false);
        _showSnack(
            context, 'Credit approved and forwarded to Chairman', DS.statusApproved);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        _showSnack(context, 'Failed to approve: $e', DS.statusRejected);
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> doc) async {
    final docId = doc['hiveKey'] as String? ?? '';
    if (docId.isEmpty) return;

    final ok = await _creditConfirmDialog(
      context:   context,
      isApprove: false,
      amount:    (doc['amount'] as num?)?.toDouble() ?? 0,
      fromName:  doc['fromUsername'] as String? ?? '-',
    );
    if (ok != true || !mounted) return;

    setState(() => _processing = true);
    try {
      await _svc.managerRejectCredit(
          obDocId: docId, managerUsername: widget.username);
      if (mounted) {
        setState(() => _processing = false);
        _showSnack(context, 'Credit rejected', DS.statusRejected);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        _showSnack(context, 'Failed to reject: $e', DS.statusRejected);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(
        icon:     Icons.inbox_rounded,
        title:    'Incoming Credits',
        subtitle: 'From Office Boys — awaiting your review',
        color:    t.accent,
      ),

      StreamBuilder<List<Map<String, dynamic>>>(
        stream: _svc.obToManagerPending(),
        builder: (_, snap) {
          if (snap.hasError) {
            return _ErrorCard(
              message: 'Failed to load credits: ${snap.error}',
              icon:    Icons.error_outline_rounded,
              color:   DS.statusRejected,
            );
          }

          if (!snap.hasData) return const _LoadingRow();
          final docs = snap.data!;

          if (docs.isEmpty) {
            return _EmptyCard(
              message: 'No pending credits from office boys',
              icon:    Icons.inbox_outlined,
              color:   t.accent,
            );
          }

          double total = 0;
          for (final d in docs) total += (d['amount'] as num?)?.toDouble() ?? 0;

          return Column(children: [
            _SummaryBar(count: docs.length, total: total, color: t.accent),
            ListView.builder(
              shrinkWrap: true,
              physics:    const NeverScrollableScrollPhysics(),
              padding:    const EdgeInsets.fromLTRB(16, 8, 16, 0),
              itemCount:  docs.length,
              itemBuilder: (_, i) => _CreditReviewCard(
                data:          docs[i],
                processing:    _processing,
                approverLabel: 'Approve → Chairman',
                accentColor:   t.accent,
                onApprove:     () => _approve(docs[i]),
                onReject:      () => _reject(docs[i]),
              ),
            ),
          ]);
        },
      ),

      const SizedBox(height: 8),
      _ManagerForwardedSection(svc: _svc),
      const SizedBox(height: 24),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CHAIRMAN CREDIT APPROVAL SECTION
// ════════════════════════════════════════════════════════════════════════════════

class ChairmanCreditApprovalSection extends StatefulWidget {
  final String branchId, chairmanUsername;

  const ChairmanCreditApprovalSection({
    super.key,
    required this.branchId,
    required this.chairmanUsername,
  });

  @override
  State<ChairmanCreditApprovalSection> createState() =>
      _ChairmanCreditApprovalSectionState();
}

class _ChairmanCreditApprovalSectionState
    extends State<ChairmanCreditApprovalSection> {
  String _filter = 'pending';

  @override
  Widget build(BuildContext context) {
    final t   = RoleThemeScope.dataOf(context);
    final svc = CreditLedgerService(widget.branchId);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(
        icon:     Icons.verified_rounded,
        title:    'Credit Approvals',
        subtitle: 'Manager-forwarded credits awaiting your decision',
        color:    t.accent,
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _FilterTabBar(
          selected:  _filter,
          onChanged: (v) => setState(() => _filter = v),
          svc:       svc,
        ),
      ),

      StreamBuilder<List<Map<String, dynamic>>>(
        stream: svc.managerToChairmanPending(),
        builder: (_, pendSnap) {
          if (pendSnap.hasError) {
            return _ErrorCard(
              message: 'Failed to load pending approvals.',
              icon:    Icons.error_outline_rounded,
              color:   DS.statusRejected,
            );
          }
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: svc.chairmanApproved(),
            builder: (_, apprSnap) {
              if (apprSnap.hasError) {
                return _ErrorCard(
                  message: 'Failed to load approved credits.',
                  icon:    Icons.error_outline_rounded,
                  color:   DS.statusRejected,
                );
              }

              final pending  = pendSnap.data ?? [];
              final approved = apprSnap.data ?? [];

              List<Map<String, dynamic>> shown;
              if (_filter == 'pending')       shown = pending;
              else if (_filter == 'approved') shown = approved;
              else                            shown = [...pending, ...approved];

              if (shown.isEmpty) {
                return _EmptyCard(
                  message: _filter == 'pending'
                      ? 'No credits awaiting your approval'
                      : 'No approved credits yet',
                  icon: _filter == 'pending'
                      ? Icons.hourglass_empty_rounded
                      : Icons.check_circle_outline_rounded,
                  color: t.accent,
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics:    const NeverScrollableScrollPhysics(),
                padding:    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount:  shown.length,
                itemBuilder: (_, i) {
                  final d     = shown[i];
                  final docId = d['hiveKey'] as String? ?? '';
                  final isPending = d['status'] == kStatusPending;
                  return _ChairmanCreditCard(
                    data: d,
                    onApprove: isPending && docId.isNotEmpty
                        ? () => _chairmanDecide(context, svc, docId,
                              kStatusApproved,
                              (d['amount'] as num?)?.toDouble() ?? 0)
                        : null,
                    onReject: isPending && docId.isNotEmpty
                        ? () => _chairmanDecide(context, svc, docId,
                              kStatusRejected,
                              (d['amount'] as num?)?.toDouble() ?? 0)
                        : null,
                  );
                },
              );
            },
          );
        },
      ),
    ]);
  }

  Future<void> _chairmanDecide(
    BuildContext context,
    CreditLedgerService svc,
    String docId,
    String decision,
    double amount,
  ) async {
    final isApprove = decision == kStatusApproved;
    final ok = await _creditConfirmDialog(
      context:   context,
      isApprove: isApprove,
      amount:    amount,
      fromName:  'Manager',
    );
    if (ok == true) {
      try {
        await svc.chairmanDecide(
            docId:            docId,
            decision:         decision,
            chairmanUsername: widget.chairmanUsername);
        if (context.mounted) {
          _showSnack(
            context,
            isApprove ? 'Donation approved successfully' : 'Credit rejected',
            isApprove ? DS.statusApproved : DS.statusRejected,
          );
        }
      } catch (e) {
        if (context.mounted) {
          _showSnack(context, 'Failed: $e', DS.statusRejected);
        }
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CREDIT SUMMARY BAR
// ════════════════════════════════════════════════════════════════════════════════

class CreditSummaryBar extends StatelessWidget {
  final String branchId, role, userId;
  final Color  color;

  const CreditSummaryBar({
    super.key,
    required this.branchId,
    required this.role,
    required this.userId,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final svc = CreditLedgerService(branchId);

    if (role == kRoleOfficeBoy) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: svc.obOwnCredits(userId),
        builder: (_, snap) {
          if (snap.hasError) return const SizedBox.shrink();
          final docs       = snap.data ?? [];
          double submitted = 0, approved = 0;
          for (final d in docs) {
            final amt = (d['amount'] as num?)?.toDouble() ?? 0;
            submitted += amt;
            if (d['status'] == kStatusApproved) approved += amt;
          }
          return _BarWidget(
            label1:     'My Credits',
            val1:       'PKR ${fmtNum(submitted)}',
            label2:     'Approved',
            val2:       'PKR ${fmtNum(approved)}',
            color:      color,
            hasPending: CreditLedgerService.hasPendingSync(docs),
          );
        },
      );
    }

    if (role == kRoleManager) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: svc.obToManagerPending(),
        builder: (_, obSnap) {
          if (obSnap.hasError) return const SizedBox.shrink();
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: svc.managerToChairmanPending(),
            builder: (_, chairSnap) {
              if (chairSnap.hasError) return const SizedBox.shrink();
              final obPend    = obSnap.data    ?? [];
              final chairPend = chairSnap.data ?? [];
              double obTotal = 0, chairTotal = 0;
              for (final d in obPend)    obTotal    += (d['amount'] as num?)?.toDouble() ?? 0;
              for (final d in chairPend) chairTotal += (d['amount'] as num?)?.toDouble() ?? 0;
              return _BarWidget(
                label1:     'OB Inbox',
                val1:       'PKR ${fmtNum(obTotal)}',
                label2:     'At Chairman',
                val2:       'PKR ${fmtNum(chairTotal)}',
                color:      color,
                hasPending: CreditLedgerService.hasPendingSync(obPend),
              );
            },
          );
        },
      );
    }

    // Chairman
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: svc.managerToChairmanPending(),
      builder: (_, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        final docs  = snap.data ?? [];
        double total = 0;
        for (final d in docs) total += (d['amount'] as num?)?.toDouble() ?? 0;
        return _BarWidget(
          label1:     'Pending Approval',
          val1:       'PKR ${fmtNum(total)}',
          label2:     'Submissions',
          val2:       '${docs.length}',
          color:      color,
          hasPending: CreditLedgerService.hasPendingSync(docs),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ════════════════════════════════════════════════════════════════════════════════

class _FilterTabBar extends StatelessWidget {
  final String               selected;
  final ValueChanged<String> onChanged;
  final CreditLedgerService  svc;

  const _FilterTabBar({
    required this.selected,
    required this.onChanged,
    required this.svc,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: svc.managerToChairmanPending(),
      builder: (_, pendSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: svc.chairmanApproved(),
          builder: (_, apprSnap) {
            final pendCount = pendSnap.data?.length ?? 0;
            final apprCount = apprSnap.data?.length ?? 0;
            return Container(
              padding:    const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color:        t.bgCardAlt,
                  borderRadius: BorderRadius.circular(DS.rMd)),
              child: Row(children: [
                _tab(t, 'all',      'All',      pendCount + apprCount),
                _tab(t, 'pending',  'Pending',  pendCount),
                _tab(t, 'approved', 'Approved', apprCount),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _tab(RoleThemeData t, String value, String label, int count) {
    final isSel = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:  const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color:        isSel ? t.bgCard : Colors.transparent,
            borderRadius: BorderRadius.circular(DS.rSm),
            boxShadow:    isSel ? DS.shadowSm : [],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label,
                style: DS.label(
                        color: isSel ? t.textPrimary : t.textTertiary)
                    .copyWith(
                        letterSpacing: 0.3,
                        fontSize:      12,
                        fontWeight:    isSel ? FontWeight.w700 : FontWeight.w500)),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color:        isSel ? t.accent : t.bgRule,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$count',
                    style: DS.caption(
                            color: isSel ? Colors.white : t.textSecondary)
                        .copyWith(fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Chairman credit card ──────────────────────────────────────────────────────

class _ChairmanCreditCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback?        onApprove;
  final VoidCallback?        onReject;

  const _ChairmanCreditCard({
    required this.data,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final t        = RoleThemeScope.dataOf(context);
    final amount   = (data['amount'] as num?)?.toDouble() ?? 0;
    final from     = data['fromUsername'] as String? ?? '-';
    final notes    = data['notes']        as String? ?? '';
    final catId    = data['categoryId']   as String? ?? '';
    final subId    = data['subtypeId']    as String?;
    final ts       = data['timestamp']    as String? ?? '';
    final status   = data['status']       as String? ?? kStatusPending;
    final receiptNo = data['receiptNo']   as String? ?? '';
    final isPend   = status == kStatusPending;

    String timeStr = '';
    try {
      timeStr = DateFormat('dd MMM yyyy  •  hh:mm a').format(DateTime.parse(ts));
    } catch (_) {}

    final cat = DonationCategory.values.firstWhere(
        (c) => c.name == catId, orElse: () => DonationCategory.general);
    final subtype = subId != null
        ? DonationSubtype.values.firstWhereOrNull((s) => s.name == subId)
        : null;

    final borderColor = isPend
        ? t.accent.withOpacity(0.35)
        : DS.statusApproved.withOpacity(0.35);
    final headerBg   = isPend
        ? t.accentMuted.withOpacity(0.4)
        : DS.emerald100.withOpacity(0.5);
    final iconBg     = isPend
        ? t.accent.withOpacity(0.15)
        : DS.emerald500.withOpacity(0.12);
    final iconColor  = isPend ? t.accent : DS.emerald600;
    final amtColor   = isPend ? t.accentLight : DS.emerald700;

    return Container(
      margin:     const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: borderColor),
          boxShadow:    DS.shadowMd),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
              color:        headerBg,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(DS.rLg))),
          child: Row(children: [
            Container(
              padding:    const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color:        iconBg,
                  borderRadius: BorderRadius.circular(DS.rSm)),
              child: Icon(Icons.manage_accounts_rounded,
                  color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('From Manager: $from',
                    style: DS.subheading(color: t.textPrimary)),
                const SizedBox(height: 2),
                Text(timeStr, style: DS.caption(color: t.textTertiary)),
                if (receiptNo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Receipt: $receiptNo',
                      style: DS.caption(color: t.textTertiary)
                          .copyWith(fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('PKR ${fmtNum(amount)}',
                  style: DS.mono(color: amtColor, size: 18)),
              const SizedBox(height: 4),
              DSStatusBadge(status: status),
            ]),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (catId.isNotEmpty)
                _CategoryBadge(cat: cat),
              if (subtype != null)
                DSSubtypeBadge(subtype: subtype),
            ]),

            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width:   double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color:        t.bgCardAlt,
                    borderRadius: BorderRadius.circular(DS.rSm),
                    border:       Border.all(color: t.bgRule)),
                child: Text(notes,
                    style: DS.caption(color: t.textSecondary)
                        .copyWith(fontStyle: FontStyle.italic)),
              ),
            ],

            if (isPend && (onApprove != null || onReject != null)) ...[
              const SizedBox(height: 14),
              _ReviewActionRow(onApprove: onApprove, onReject: onReject),
            ],

            const SizedBox(height: 14),
          ]),
        ),
      ]),
    );
  }
}

// ── Manager review card ───────────────────────────────────────────────────────

class _CreditReviewCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool                 processing;
  final String               approverLabel;
  final Color                accentColor;
  final VoidCallback         onApprove;
  final VoidCallback         onReject;

  const _CreditReviewCard({
    required this.data,
    required this.processing,
    required this.approverLabel,
    required this.accentColor,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final t         = RoleThemeScope.dataOf(context);
    final amount    = (data['amount'] as num?)?.toDouble() ?? 0;
    final from      = data['fromUsername'] as String? ?? '-';
    final notes     = data['notes']        as String? ?? '';
    final catId     = data['categoryId']   as String? ?? '';
    final subId     = data['subtypeId']    as String?;
    final receiptNo = data['receiptNo']    as String? ?? '';
    final ts        = data['timestamp']    as String? ?? '';

    String timeStr = '';
    try {
      timeStr = DateFormat('dd MMM  •  hh:mm a').format(DateTime.parse(ts));
    } catch (_) {}

    final cat = DonationCategory.values.firstWhere(
        (c) => c.name == catId, orElse: () => DonationCategory.general);
    final subtype = subId != null
        ? DonationSubtype.values.firstWhereOrNull((s) => s.name == subId)
        : null;

    return Container(
      margin:     const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: accentColor.withOpacity(0.2)),
          boxShadow:    DS.shadowSm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
              color: accentColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(DS.rLg)),
              border: Border(
                  bottom: BorderSide(color: accentColor.withOpacity(0.12)))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color:        accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(DS.rSm)),
              child: Icon(Icons.person_rounded, color: accentColor, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(from, style: DS.subheading(color: t.textPrimary)),
                Text(timeStr, style: DS.caption(color: t.textTertiary)),
                if (receiptNo.isNotEmpty)
                  Text('Receipt: $receiptNo',
                      style: DS.caption(color: t.textTertiary)
                          .copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            Text('PKR ${fmtNum(amount)}',
                style: DS.mono(color: accentColor, size: 16)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (catId.isNotEmpty) _CategoryBadge(cat: cat),
              if (subtype != null)  DSSubtypeBadge(subtype: subtype),
            ]),

            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(notes,
                  style: DS.caption(color: t.textTertiary)
                      .copyWith(fontStyle: FontStyle.italic)),
            ],

            const SizedBox(height: 12),
            _ReviewActionRow(
              onApprove:    processing ? null : onApprove,
              onReject:     processing ? null : onReject,
              approveLabel: approverLabel,
              isProcessing: processing,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Review action row ─────────────────────────────────────────────────────────

class _ReviewActionRow extends StatelessWidget {
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final String        approveLabel;
  final bool          isProcessing;

  const _ReviewActionRow({
    this.onApprove,
    this.onReject,
    this.approveLabel = 'Approve Donation',
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: DS.statusRejected,
            side:    const BorderSide(color: Color(0xFFEF4444), width: 1.2),
            shape:   RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DS.rMd)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: const Color(0xFFFFF5F5),
          ),
          onPressed: onReject,
          icon:  const Icon(Icons.close_rounded, size: 16),
          label: const Text('Reject',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: DS.statusApproved,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DS.rMd)),
            padding:   const EdgeInsets.symmetric(vertical: 12),
            elevation: 0,
          ),
          onPressed: onApprove,
          icon: isProcessing
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_rounded, size: 16),
          label: Text(approveLabel,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

// ── Manager forwarded section ─────────────────────────────────────────────────

class _ManagerForwardedSection extends StatelessWidget {
  final CreditLedgerService svc;
  const _ManagerForwardedSection({required this.svc});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: svc.managerToChairmanPending(),
      builder: (_, pendSnap) {
        if (pendSnap.hasError) return const SizedBox.shrink();
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: svc.chairmanApproved(),
          builder: (_, apprSnap) {
            if (apprSnap.hasError) return const SizedBox.shrink();
            final pending  = pendSnap.data ?? [];
            final approved = apprSnap.data ?? [];
            if (pending.isEmpty && approved.isEmpty) {
              return const SizedBox.shrink();
            }

            double pendTotal = 0, appTotal = 0;
            for (final d in pending)  pendTotal += (d['amount'] as num?)?.toDouble() ?? 0;
            for (final d in approved) appTotal  += (d['amount'] as num?)?.toDouble() ?? 0;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding:    const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color:        t.bgCard,
                    borderRadius: BorderRadius.circular(DS.rLg),
                    border:       Border.all(color: t.bgRule),
                    boxShadow:    DS.shadowSm),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Forwarded to Chairman',
                      style: DS.label(color: t.textTertiary)
                          .copyWith(letterSpacing: 0.8)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _KpiTile(
                          label: 'Awaiting Chairman',
                          value: 'PKR ${fmtNum(pendTotal)}',
                          icon:  Icons.pending_actions_rounded,
                          color: DS.statusPending)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KpiTile(
                          label: 'Chairman Approved',
                          value: 'PKR ${fmtNum(appTotal)}',
                          icon:  Icons.check_circle_rounded,
                          color: DS.statusApproved)),
                  ]),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Shared micro-widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String   title, subtitle;
  final Color    color;

  const _SectionHeader({
    required this.icon,     required this.title,
    required this.subtitle, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(children: [
        Container(
          padding:    const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color:        color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(DS.rMd)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: DS.heading(color: t.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, style: DS.caption(color: t.textTertiary)),
          ]),
        ),
      ]),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final int    count;
  final double total;
  final Color  color;

  const _SummaryBar(
      {required this.count, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color:        color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(DS.rMd),
            border:       Border.all(color: color.withOpacity(0.18))),
        child: Row(children: [
          Icon(Icons.payments_rounded, color: color, size: 15),
          const SizedBox(width: 8),
          Text('$count item${count != 1 ? "s" : ""} pending review',
              style: DS.caption(color: t.textTertiary)),
          const Spacer(),
          Text('PKR ${fmtNum(total)}',
              style: DS.mono(color: color, size: 14)),
        ]),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String   label, value;
  final IconData icon;
  final Color    color;

  const _KpiTile({
    required this.label, required this.value,
    required this.icon,  required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color:        color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(DS.rMd),
          border:       Border.all(color: color.withOpacity(0.18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(height: 6),
        Text(value, style: DS.mono(color: color, size: 14)),
        const SizedBox(height: 2),
        Text(label, style: DS.caption(color: t.textTertiary)),
      ]),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String   message;
  final IconData icon;
  final Color    color;

  const _EmptyCard(
      {required this.message, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        width:   double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
            color:        t.bgCardAlt,
            borderRadius: BorderRadius.circular(DS.rLg),
            border:       Border.all(color: color.withOpacity(0.15))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color.withOpacity(0.30), size: 36),
          const SizedBox(height: 10),
          Text(message,
              style: DS.caption(color: t.textTertiary)
                  .copyWith(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String   message;
  final IconData icon;
  final Color    color;

  const _ErrorCard(
      {required this.message, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        width:   double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
            color:        color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(DS.rLg),
            border:       Border.all(color: color.withOpacity(0.25))),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: DS.caption(color: t.textSecondary)
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child:   Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: t.accent)),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final DonationCategory cat;
  const _CategoryBadge({required this.cat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color:        cat.lightColor,
          borderRadius: BorderRadius.circular(DS.rSm),
          border:       Border.all(color: cat.color.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(cat.icon, size: 11, color: cat.color),
        const SizedBox(width: 5),
        Text(cat.shortLabel,
            style: DS.label(color: cat.color)
                .copyWith(fontSize: 10, letterSpacing: 0.3)),
      ]),
    );
  }
}

class _BarWidget extends StatelessWidget {
  final String label1, val1, label2, val2;
  final Color  color;
  final bool   hasPending;

  const _BarWidget({
    required this.label1, required this.val1,
    required this.label2, required this.val2,
    required this.color,  required this.hasPending,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      margin:  const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color:        color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(DS.rMd),
          border:       Border.all(color: color.withOpacity(0.18))),
      child: Row(children: [
        _kpi(t, label1, val1),
        Container(
            height: 28, width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: color.withOpacity(0.2)),
        _kpi(t, label2, val2),
        if (hasPending) ...[
          const Spacer(),
          Icon(Icons.cloud_queue_rounded, size: 13, color: DS.statusPending),
        ],
      ]),
    );
  }

  Widget _kpi(RoleThemeData t, String label, String val) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: DS.label(color: t.textTertiary)),
        const SizedBox(height: 2),
        Text(val, style: DS.mono(color: color, size: 13)),
      ]);
}

// ════════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════════

Future<bool?> _creditConfirmDialog({
  required BuildContext context,
  required bool         isApprove,
  required double       amount,
  required String       fromName,
}) {
  final t = RoleThemeScope.dataOf(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape:     RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rXl)),
      elevation: 0,
      child: Container(
        padding:    const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color:        t.bgCard,
            borderRadius: BorderRadius.circular(DS.rXl),
            border:       Border.all(color: t.bgRule)),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding:    const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: isApprove
                        ? DS.statusApproved.withOpacity(0.10)
                        : DS.statusRejected.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(DS.rMd)),
                child: Icon(
                    isApprove
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: isApprove ? DS.statusApproved : DS.statusRejected,
                    size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                  isApprove ? 'Confirm Approval' : 'Confirm Rejection',
                  style: DS.heading(color: t.textPrimary)),
            ]),
            const SizedBox(height: 16),
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color:        t.bgCardAlt,
                  borderRadius: BorderRadius.circular(DS.rMd),
                  border:       Border.all(color: t.bgRule)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AMOUNT', style: DS.label(color: t.textTertiary)),
                const SizedBox(height: 4),
                Text('PKR ${fmtNum(amount)}',
                    style: DS.mono(color: t.textPrimary, size: 22)),
                const SizedBox(height: 8),
                Text('FROM', style: DS.label(color: t.textTertiary)),
                const SizedBox(height: 4),
                Text(fromName,
                    style: DS.subheading(color: t.textSecondary)),
              ]),
            ),
            const SizedBox(height: 16),
            Text(
              isApprove
                  ? 'This will forward the credit to the next approval level.'
                  : 'The submitter will need to resubmit after corrections.',
              style: DS.caption(color: t.textTertiary),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: t.textSecondary,
                      side: BorderSide(color: t.bgRule),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DS.rMd)),
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isApprove
                          ? DS.statusApproved
                          : DS.statusRejected,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DS.rMd)),
                      padding:   const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(isApprove ? 'Approve' : 'Reject',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ]),
          ]),
      ),
    ),
  );
}

void _showSnack(BuildContext context, String message, Color color) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content:         Text(message,
        style: const TextStyle(fontWeight: FontWeight.w600)),
    backgroundColor: color,
    behavior:        SnackBarBehavior.floating,
    margin:          const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DS.rMd)),
    duration: const Duration(seconds: 3),
  ));
}