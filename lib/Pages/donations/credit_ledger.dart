// lib/pages/donations/credit_ledger.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../services/local_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart';
import 'donations_shared.dart';
import 'donations_screen.dart';

class CreditLedgerService {
  final String branchId;
  CreditLedgerService(this.branchId);

  Future<String> officeBoyAutoCredit({
    required String fromUserId,
    required String fromUsername,
    required double amount,
    required String categoryId,
    required String subtypeId,
    required String branchName,
    required String receiptNo,
    String notes = '',
  }) async {
    return LocalStorageService.saveCreditEntry(
      branchId: branchId,
      data: {
        'type':         'donation_collection',
        'fromRole':     'Office Boy',
        'toRole':       'Manager',
        'fromUserId':   fromUserId,
        'fromUsername': fromUsername,
        'amount':       amount,
        'categoryId':   categoryId,
        'subtypeId':    subtypeId,
        'branchName':   branchName,
        'receiptNo':    receiptNo,
        'notes':        notes,
        'status':       kStatusPending,
        'date':         DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'timestamp':    DateTime.now().toIso8601String(),
      },
    );
  }


  Future<void> managerApproveOBCredit(
    String hiveKey,
    String managerUsername,
    String managerUserId,
  ) async {
    await LocalStorageService.updateCreditStatus(
      hiveKey,
      status:        kStatusApproved,
      actorUsername: managerUsername,
      branchId:      branchId,
    );

    final box = Hive.box(LocalStorageService.creditsBox);
    final raw = box.get(hiveKey);
    if (raw == null) return;
    final obData = Map<String, dynamic>.from(raw as Map);

    await LocalStorageService.saveCreditEntry(
      branchId: branchId,
      data: {
        'type':            'manager_forwarding',
        'fromRole':        'Manager',
        'toRole':          'Chairman',
        'fromUserId':      managerUserId,
        'fromUsername':    managerUsername,
        'amount':          obData['amount']      ?? 0.0,
        'categoryId':      obData['categoryId']  ?? '',
        'subtypeId':       obData['subtypeId']   ?? '',
        'branchName':      obData['branchName']  ?? '',
        'receiptNo':       obData['receiptNo']   ?? '',
        'notes':           obData['notes']       ?? '',
        'status':          kStatusPending,
        'date':            DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'timestamp':       DateTime.now().toIso8601String(),
        'collectedBy':     obData['fromUsername'] ?? '',
        'collectedByRole': 'Office Boy',
        'originalHiveKey': hiveKey,
      },
    );
  }

  Future<void> managerRejectOBCredit(
      String hiveKey, String managerUsername, String reason) async {
    await LocalStorageService.updateCreditStatus(
      hiveKey,
      status:          kStatusRejected,
      actorUsername:   managerUsername,
      branchId:        branchId,
      rejectionReason: reason,
    );
  }

  Future<void> chairmanApproveManagerCredit(
      String hiveKey, String chairmanUsername) async {
    await LocalStorageService.updateCreditStatus(
      hiveKey,
      status:        kStatusApproved,
      actorUsername: chairmanUsername,
      branchId:      branchId,
    );
  }

  Future<void> chairmanRejectManagerCredit(
      String hiveKey, String chairmanUsername, String reason) async {
    await LocalStorageService.updateCreditStatus(
      hiveKey,
      status:          kStatusRejected,
      actorUsername:   chairmanUsername,
      branchId:        branchId,
      rejectionReason: reason,
    );
  }

  // ── Hive streams — no Firestore listeners, works fully offline ──────────────

  Stream<List<Map<String, dynamic>>> watchAllForManager() =>
      LocalStorageService.streamCredits(branchId: branchId, toRole: 'Manager');

  Stream<List<Map<String, dynamic>>> watchAllForChairman() =>
      LocalStorageService.streamCredits(branchId: branchId, toRole: 'Chairman');

  Stream<List<Map<String, dynamic>>> watchManagerOwnCredits(String managerUserId) {
    if (managerUserId.isEmpty) return const Stream.empty();
    return LocalStorageService.streamCredits(
        branchId: branchId, toRole: 'Chairman', fromUserId: managerUserId);
  }

  Stream<List<Map<String, dynamic>>> watchOfficeBoyCredits(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return LocalStorageService.streamCredits(
        branchId: branchId, fromUserId: userId);
  }
}

class ManagerCreditsDashboard extends StatefulWidget {
  final String branchId, username, branchName, userId;

  const ManagerCreditsDashboard({
    super.key,
    required this.branchId,
    required this.username,
    required this.branchName,
    required this.userId,
  });

  @override
  State<ManagerCreditsDashboard> createState() => _ManagerCreditsDashboardState();
}

class _ManagerCreditsDashboardState
    extends State<ManagerCreditsDashboard> with SingleTickerProviderStateMixin {
  bool _showPendingOnly = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t       = RoleThemeScope.dataOf(context);
    final service = CreditLedgerService(widget.branchId);

    return Column(children: [
      Container(
        color:   t.bg,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(children: [
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Credit Approvals', style: DS.heading(color: t.textPrimary)),
              Text('Office Boy → Manager handoffs',
                  style: DS.caption(color: t.textTertiary)),
            ]),
            const Spacer(),
            _PendingToggle(
              active: _showPendingOnly,
              onTap:  () => setState(() => _showPendingOnly = !_showPendingOnly),
            ),
          ]),
          const SizedBox(height: 10),
          TabBar(
            controller:           _tabController,
            labelColor:           t.accent,
            unselectedLabelColor: t.textTertiary,
            indicatorColor:       t.accent,
            tabs: const [Tab(text: 'Pending Approvals'), Tab(text: 'My Credits')],
          ),
        ]),
      ),

      Expanded(
        child: TabBarView(
          controller: _tabController,
          physics:    const NeverScrollableScrollPhysics(),
          children: [
            _ManagerApprovalTab(
              service:         service,
              branchId:        widget.branchId,
              username:        widget.username,
              userId:          widget.userId,
              branchName:      widget.branchName,
              showPendingOnly: _showPendingOnly,
            ),
            _ManagerOwnCreditsTab(
              service:  service,
              branchId: widget.branchId,
              userId:   widget.userId,
            ),
          ],
        ),
      ),
    ]);
  }
}


class _ManagerApprovalTab extends StatelessWidget {
  final CreditLedgerService service;
  final String branchId, username, userId, branchName;
  final bool showPendingOnly;

  const _ManagerApprovalTab({
    required this.service, required this.branchId, required this.username,
    required this.userId,  required this.branchName, required this.showPendingOnly,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 8),
      _CreditSummaryRow(branchId: branchId, toRole: 'Manager'),
      const SizedBox(height: 4),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: service.watchAllForManager(),
          builder: (context, snap) {
            if (snap.hasError) return _ErrorView(error: '${snap.error}');
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            final all  = snap.data!;
            final docs = showPendingOnly
                ? all.where((d) => (d['status'] as String? ?? '') == kStatusPending).toList()
                : all;

            if (docs.isEmpty) return _EmptyCredits(pending: showPendingOnly, roleFrom: 'Office Boy');

            return ListView.separated(
              padding:          const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount:        docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _CreditTile(
                data:       docs[i],
                hiveKey:    docs[i]['hiveKey'] as String? ?? '',
                service:    service,
                username:   username,
                userId:     userId,
                branchName: branchName,
                isManager:  true,
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _ManagerOwnCreditsTab extends StatelessWidget {
  final CreditLedgerService service;
  final String branchId, userId;

  const _ManagerOwnCreditsTab({
    required this.service, required this.branchId, required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    return Column(children: [
      Container(
        margin:  const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        DS.sapphire100,
          borderRadius: BorderRadius.circular(DS.rMd),
          border: Border.all(color: DS.sapphire500.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: DS.sapphire700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These are credits you have forwarded to the Chairman '
              'after approving Office Boy submissions.',
              style: DS.caption(color: DS.sapphire700).copyWith(fontSize: 11),
            ),
          ),
        ]),
      ),
      _CreditSummaryRow(branchId: branchId, toRole: 'Chairman', filterUserId: userId),
      const SizedBox(height: 8),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: service.watchManagerOwnCredits(userId),
          builder: (context, snap) {
            if (snap.hasError) return _ErrorView(error: '${snap.error}');
            final docs = snap.data ?? [];
            if (docs.isEmpty) return _EmptyCredits(pending: false, roleFrom: 'you');

            return ListView.separated(
              padding:          const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount:        docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _ManagerOwnCreditCard(data: docs[i], t: t),
            );
          },
        ),
      ),
    ]);
  }
}

class _ManagerOwnCreditCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final RoleThemeData t;
  const _ManagerOwnCreditCard({required this.data, required this.t});

  @override
  Widget build(BuildContext context) {
    final d           = data;
    final amt         = (d['amount']     as num?)?.toDouble() ?? 0.0;
    final stat        = d['status']      as String? ?? kStatusPending;
    final catId       = d['categoryId']  as String? ?? '';
    final catE        = DonationCategory.values.firstWhereOrNull((c) => c.name == catId) ?? DonationCategory.jamia;
    final receiptNo   = d['receiptNo']   as String? ?? '';
    final dateRaw     = d['date']        as String? ?? '';
    final collectedBy = d['collectedBy'] as String? ?? '';
    final syncSt      = d['syncStatus']  as String? ?? 'synced';
    String dl = dateRaw;
    try { dl = DateFormat('dd MMM yyyy').format(DateTime.parse(dateRaw)); } catch (_) {}

    return Container(
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(DS.rMd),
        border: Border.all(color: t.bgRule), boxShadow: DS.shadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: catE.lightColor, shape: BoxShape.circle),
            child: Icon(catE.icon, color: catE.color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(catE.label, style: DS.subheading(color: t.textPrimary).copyWith(fontSize: 12.5)),
              if (receiptNo.isNotEmpty)
                Text(receiptNo, style: DS.caption(color: t.textTertiary).copyWith(fontSize: 9.5, fontWeight: FontWeight.w700)),
              Text(dl, style: DS.caption(color: t.textTertiary).copyWith(fontSize: 10)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('PKR ${fmtNum(amt)}', style: DS.mono(color: catE.color, size: 13)),
            const SizedBox(height: 4),
            DSStatusBadge(status: stat),
          ]),
        ]),
        if (collectedBy.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.person_outline_rounded, size: 10, color: t.textTertiary),
            const SizedBox(width: 4),
            Text('Collected by Office Boy: $collectedBy',
                style: DS.caption(color: t.textTertiary).copyWith(fontSize: 10)),
          ]),
        ],
        if (syncSt == 'pending') ...[const SizedBox(height: 6), _SyncPendingChip()],
      ]),
    );
  }
}


class ChairmanCreditApprovalSection extends StatelessWidget {
  final String branchId, branchName, username;

  const ChairmanCreditApprovalSection({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    final t       = RoleThemeScope.dataOf(context);
    final service = CreditLedgerService(branchId);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Credit Approvals', style: DS.heading(color: t.textPrimary)),
            Text('Manager → Chairman submissions', style: DS.caption(color: t.textTertiary)),
          ]),
          const Spacer(),
          _PendingCountBadge(branchId: branchId, toRole: 'Chairman'),
        ]),
      ),
      _CreditSummaryRow(branchId: branchId, toRole: 'Chairman'),
      const SizedBox(height: 8),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: service.watchAllForChairman(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!;
            if (docs.isEmpty) return _EmptyCredits(pending: false, roleFrom: 'Manager');
            return ListView.separated(
              padding:          const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount:        docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _CreditTile(
                data:       docs[i],
                hiveKey:    docs[i]['hiveKey'] as String? ?? '',
                service:    service,
                username:   username,
                userId:     '',
                branchName: branchName,
                isManager:  false,
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// OFFICE BOY CREDITS VIEW
// ════════════════════════════════════════════════════════════════════════════════

class OfficeBoyCreditsView extends StatelessWidget {
  final String branchId, userId;

  const OfficeBoyCreditsView({super.key, required this.branchId, required this.userId});

  @override
  Widget build(BuildContext context) {
    final t       = RoleThemeScope.dataOf(context);
    final service = CreditLedgerService(branchId);

    return Column(children: [
      Container(
        margin:  const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DS.sapphire100, borderRadius: BorderRadius.circular(DS.rMd),
          border: Border.all(color: DS.sapphire500.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: DS.sapphire700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Credits track your money handoff to the Manager. '
              'All donations remain visible in the Donations tab.',
              style: DS.caption(color: DS.sapphire700).copyWith(fontSize: 11),
            ),
          ),
        ]),
      ),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: service.watchOfficeBoyCredits(userId),
          builder: (context, snap) {
            if (snap.hasError) return _ErrorView(error: '${snap.error}');
            final docs = snap.data ?? [];
            if (docs.isEmpty) return _EmptyCredits(pending: false, roleFrom: 'you');

            return ListView.separated(
              padding:          const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount:        docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d       = docs[i];
                final amt     = (d['amount']    as num?)?.toDouble() ?? 0.0;
                final stat    = d['status']     as String? ?? kStatusPending;
                final catId   = d['categoryId'] as String? ?? '';
                final catE    = DonationCategory.values.firstWhereOrNull((c) => c.name == catId) ?? DonationCategory.jamia;
                final recNo   = d['receiptNo']  as String? ?? '';
                final dateRaw = d['date']       as String? ?? '';
                final syncSt  = d['syncStatus'] as String? ?? 'synced';
                String dl = dateRaw;
                try { dl = DateFormat('dd MMM yyyy').format(DateTime.parse(dateRaw)); } catch (_) {}

                return Container(
                  padding:    const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.bgCard, borderRadius: BorderRadius.circular(DS.rMd),
                    border: Border.all(color: t.bgRule), boxShadow: DS.shadowSm,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: catE.lightColor, shape: BoxShape.circle),
                        child: Icon(catE.icon, color: catE.color, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(catE.label, style: DS.subheading(color: t.textPrimary).copyWith(fontSize: 12.5)),
                          if (recNo.isNotEmpty)
                            Text(recNo, style: DS.caption(color: t.textTertiary).copyWith(fontSize: 9.5, fontWeight: FontWeight.w700)),
                          Text(dl, style: DS.caption(color: t.textTertiary).copyWith(fontSize: 10)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('PKR ${fmtNum(amt)}', style: DS.mono(color: catE.color, size: 13)),
                        const SizedBox(height: 4),
                        DSStatusBadge(status: stat),
                      ]),
                    ]),
                    if (syncSt == 'pending') ...[const SizedBox(height: 6), _SyncPendingChip()],
                  ]),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// CREDIT TILE — takes Map from Hive (not QueryDocumentSnapshot)
// ════════════════════════════════════════════════════════════════════════════════

class _CreditTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final String               hiveKey;
  final CreditLedgerService  service;
  final String               username, userId, branchName;
  final bool                 isManager;

  const _CreditTile({
    required this.data, required this.hiveKey, required this.service,
    required this.username, required this.userId, required this.branchName,
    required this.isManager,
  });

  @override
  State<_CreditTile> createState() => _CreditTileState();
}

class _CreditTileState extends State<_CreditTile> {
  bool _expanded   = false;
  bool _actionBusy = false;

  @override
  Widget build(BuildContext context) {
    final t         = RoleThemeScope.dataOf(context);
    final d         = widget.data;
    final catId     = d['categoryId']   as String? ?? '';
    final cat       = DonationCategory.values.firstWhereOrNull((c) => c.name == catId) ?? DonationCategory.jamia;
    final amt       = (d['amount']      as num?)?.toDouble() ?? 0.0;
    final status    = d['status']       as String? ?? kStatusPending;
    final fromUser  = d['fromUsername'] as String? ?? '-';
    final fromRole  = d['fromRole']     as String? ?? '';
    final collected = d['collectedBy']  as String? ?? '';
    final receiptNo = d['receiptNo']    as String? ?? '';
    final dateRaw   = d['date']         as String? ?? '';
    final notes     = d['notes']        as String? ?? '';
    final subtypeId = d['subtypeId']    as String?;
    final syncSt    = d['syncStatus']   as String? ?? 'synced';

    String dl = dateRaw;
    try { dl = DateFormat('dd MMM yyyy').format(DateTime.parse(dateRaw)); } catch (_) {}

    final subtype    = subtypeId != null ? DonationSubtype.values.firstWhereOrNull((s) => s.name == subtypeId) : null;
    final isPending  = status == kStatusPending;
    final isApproved = status == kStatusApproved;
    final isRejected = status == kStatusRejected;
    final pillColor  = fromRole == 'Office Boy' ? DS.plum700    : DS.sapphire700;
    final pillBg     = fromRole == 'Office Boy' ? DS.plum100    : DS.sapphire100;
    final pillIcon   = fromRole == 'Office Boy' ? Icons.badge_outlined : Icons.account_balance_rounded;

    Color borderColor() {
      if (isPending)  return DS.statusPending.withOpacity(0.30);
      if (isApproved) return DS.statusApproved.withOpacity(0.30);
      return DS.statusRejected.withOpacity(0.30);
    }

    return Container(
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(DS.rMd),
        border: Border.all(color: borderColor()), boxShadow: DS.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [

        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: cat.color),
            Container(width: 48, color: cat.lightColor,
                child: Center(child: Icon(cat.icon, color: cat.color, size: 17))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    _RolePill(label: fromRole, icon: pillIcon, color: pillColor, bg: pillBg),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(fromUser,
                          style: DS.subheading(color: t.textPrimary).copyWith(fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('PKR ${fmtNum(amt)}', style: DS.mono(color: cat.color, size: 13)),
                  ]),

                  if (collected.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.person_outline_rounded, size: 10, color: t.textTertiary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('Originally collected by Office Boy: $collected',
                            style: DS.caption(color: t.textTertiary).copyWith(fontSize: 10),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ],

                  const SizedBox(height: 4),

                  Row(children: [
                    _CatBadge(cat: cat),
                    if (subtype != null) ...[const SizedBox(width: 5), DSSubtypeBadge(subtype: subtype)],
                    const Spacer(),
                    DSStatusBadge(status: status),
                  ]),

                  const SizedBox(height: 5),

                  Row(children: [
                    Icon(Icons.calendar_today_rounded, size: 9, color: t.textTertiary),
                    const SizedBox(width: 3),
                    Text(dl, style: DS.caption(color: t.textTertiary).copyWith(fontSize: 9.5)),
                    if (receiptNo.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.receipt_rounded, size: 9, color: t.textTertiary),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(receiptNo,
                            style: DS.caption(color: t.textTertiary).copyWith(fontSize: 9.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    const Spacer(),
                    if (syncSt == 'pending') ...[
                      Icon(Icons.cloud_upload_outlined, size: 9, color: DS.statusPending.withOpacity(0.6)),
                      const SizedBox(width: 3),
                    ],
                    _ExpandToggle(expanded: _expanded, color: t.accent,
                        onTap: () => setState(() => _expanded = !_expanded)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),

        if (_expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: t.bgCardAlt,
              border: Border(top: BorderSide(color: t.bgRule)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _InfoBanner(text: 'Credit approval tracks money handoff only. The donation remains in the list regardless.'),
              const SizedBox(height: 10),

              Wrap(spacing: 7, runSpacing: 7, children: [
                DSActionButton(icon: Icons.print_rounded,    label: 'Print',        color: DS.plum700,  onTap: () => printReceiptPdf(d, receiptNo)),
                DSActionButton(icon: Icons.download_rounded, label: 'Download PDF', color: DS.navy700,  onTap: () => downloadReceiptPdf(d, receiptNo, context)),
                if (isPending) ...[
                  DSActionButton(icon: Icons.check_circle_rounded, label: widget.isManager ? 'Approve & Forward' : 'Approve',
                      color: DS.statusApproved, disabled: _actionBusy, onTap: _approve),
                  DSActionButton(icon: Icons.cancel_rounded, label: 'Reject',
                      color: DS.statusRejected, disabled: _actionBusy, onTap: _promptReject),
                ],
              ]),

              if (isApproved) ...[
                const SizedBox(height: 10),
                _ApprovedBanner(text: 'Approved by ${d['approvedBy'] ?? '-'}${widget.isManager ? '  ·  Forwarded to Chairman.' : ''}'),
              ],
              if (isRejected) ...[
                const SizedBox(height: 10),
                _RejectedBanner(by: d['rejectedBy'] as String? ?? '-', reason: d['rejectionReason'] as String? ?? ''),
              ],
              if (syncSt == 'pending') ...[const SizedBox(height: 10), _SyncPendingChip()],
              if (notes.isNotEmpty) ...[const SizedBox(height: 10), _NotesBanner(notes: notes)],

              const SizedBox(height: 10),

              Wrap(spacing: 20, runSpacing: 8, children: [
                _Cell('Receipt No', receiptNo.isNotEmpty ? receiptNo : '-'),
                _Cell('Category',   cat.label),
                if (subtype != null) _Cell('Type', subtype.label),
                _Cell('Submitted By', '$fromRole: $fromUser'),
                if (collected.isNotEmpty) _Cell('Collected By', 'Office Boy: $collected'),
                _Cell('Date',   dl),
                _Cell('Status', status[0].toUpperCase() + status.substring(1)),
                if (d['approvedBy']      != null) _Cell('Approved By', d['approvedBy'] as String),
                if (d['rejectedBy']      != null) _Cell('Rejected By', d['rejectedBy'] as String),
                if (d['rejectionReason'] != null) _Cell('Reason',      d['rejectionReason'] as String),
                _Cell('Sync', syncSt == 'pending' ? '⏳ Queued' : '✅ Synced'),
              ]),
            ]),
          ),
      ]),
    );
  }

  Future<void> _approve() async {
    if (_actionBusy || widget.hiveKey.isEmpty) return;
    setState(() => _actionBusy = true);
    try {
      if (widget.isManager) {
        await widget.service.managerApproveOBCredit(widget.hiveKey, widget.username, widget.userId);
        if (mounted) _snack('✅  Approved & forwarded to Chairman', DS.statusApproved);
      } else {
        await widget.service.chairmanApproveManagerCredit(widget.hiveKey, widget.username);
        if (mounted) _snack('✅  Credit approved', DS.statusApproved);
      }
    } catch (e) {
      if (mounted) _snack('Approval failed: $e', DS.statusRejected);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _promptReject() async {
    if (_actionBusy || widget.hiveKey.isEmpty) return;
    final reason = await _showRejectDialog(context);
    if (reason == null) return;
    setState(() => _actionBusy = true);
    try {
      if (widget.isManager) {
        await widget.service.managerRejectOBCredit(widget.hiveKey, widget.username, reason);
      } else {
        await widget.service.chairmanRejectManagerCredit(widget.hiveKey, widget.username, reason);
      }
      if (mounted) _snack('❌  Credit rejected', DS.statusRejected);
    } catch (e) {
      debugPrint('[Reject] $e');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: color,
      behavior:        SnackBarBehavior.floating,
      margin:          const EdgeInsets.all(16),
      shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMd)),
    ));
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// REJECT DIALOG
// ════════════════════════════════════════════════════════════════════════════════

Future<String?> _showRejectDialog(BuildContext context) async {
  final t          = RoleThemeScope.dataOf(context);
  final reasonCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rXl)),
      child: Container(
        padding:    const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: t.bgCard, borderRadius: BorderRadius.circular(DS.rXl),
          border: Border.all(color: t.bgRule),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reject Credit', style: DS.heading(color: t.textPrimary)),
          const SizedBox(height: 6),
          Text('This only affects money tracking — the donation stays in the list.',
              style: DS.caption(color: t.textSecondary).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text('Reason:', style: DS.body(color: t.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: reasonCtrl,
            maxLines:   2,
            decoration: InputDecoration(
              hintText: 'Enter reason for rejection',
              hintStyle: DS.body(color: t.textTertiary),
              filled:    true, fillColor: t.bgCardAlt,
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(DS.rMd), borderSide: BorderSide(color: t.bgRule)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.rMd), borderSide: BorderSide(color: t.bgRule)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(DS.rMd), borderSide: const BorderSide(color: DS.statusRejected, width: 1.5)),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                    foregroundColor: t.textSecondary,
                    side:    BorderSide(color: t.bgRule),
                    shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMd)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: DS.statusRejected, foregroundColor: Colors.white,
                    shape:     RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMd)),
                    padding:   const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0),
                child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );

  if (confirmed != true) return null;
  return reasonCtrl.text.trim();
}

// ════════════════════════════════════════════════════════════════════════════════
// SMALL REUSABLE WIDGETS
// ════════════════════════════════════════════════════════════════════════════════

class _PendingToggle extends StatelessWidget {
  final bool active; final VoidCallback onTap;
  const _PendingToggle({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? DS.gold100 : t.bgCard,
          borderRadius: BorderRadius.circular(DS.rMd),
          border: Border.all(color: active ? DS.statusPending.withOpacity(0.4) : t.bgRule),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hourglass_top_rounded, size: 12,
              color: active ? DS.statusPending : t.textTertiary),
          const SizedBox(width: 5),
          Text(active ? 'Pending only' : 'All credits',
              style: DS.label(color: active ? DS.statusPending : t.textTertiary).copyWith(fontSize: 10.5)),
        ]),
      ),
    );
  }
}

class _PendingCountBadge extends StatelessWidget {
  final String branchId, toRole;
  const _PendingCountBadge({required this.branchId, required this.toRole});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: LocalStorageService.streamCredits(branchId: branchId, toRole: toRole),
      builder: (context, snap) {
        final count = snap.data
                ?.where((d) => (d['status'] as String? ?? '') == kStatusPending)
                .length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: DS.gold100, borderRadius: BorderRadius.circular(99),
            border: Border.all(color: DS.statusPending.withOpacity(0.3)),
          ),
          child: Text('$count pending',
              style: DS.label(color: DS.statusPending).copyWith(fontSize: 10)),
        );
      },
    );
  }
}

class _CreditSummaryRow extends StatelessWidget {
  final String  branchId, toRole;
  final String? filterUserId;
  const _CreditSummaryRow({required this.branchId, required this.toRole, this.filterUserId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: LocalStorageService.streamCredits(
          branchId: branchId, toRole: toRole, fromUserId: filterUserId),
      builder: (context, snap) {
        double pending = 0, approved = 0, rejected = 0;
        for (final d in snap.data ?? []) {
          final amt = (d['amount'] as num?)?.toDouble() ?? 0.0;
          final st  = d['status'] as String? ?? kStatusPending;
          if      (st == kStatusApproved) approved += amt;
          else if (st == kStatusRejected) rejected += amt;
          else                            pending  += amt;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _SummaryCell('Pending',  fmtNum(pending),  DS.statusPending,  DS.gold100),
            const SizedBox(width: 8),
            _SummaryCell('Approved', fmtNum(approved), DS.statusApproved, DS.emerald100),
            const SizedBox(width: 8),
            _SummaryCell('Rejected', fmtNum(rejected), DS.statusRejected, DS.crimson100),
          ]),
        );
      },
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String label, value; final Color color, bg;
  const _SummaryCell(this.label, this.value, this.color, this.bg);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(DS.rSm),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Text(label, style: DS.label(color: color).copyWith(fontSize: 9)),
        const SizedBox(height: 2),
        Text('PKR $value', style: DS.mono(color: color, size: 11), overflow: TextOverflow.ellipsis),
      ]),
    ),
  );
}

class _SyncPendingChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: DS.gold100, borderRadius: BorderRadius.circular(99),
      border: Border.all(color: DS.statusPending.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.cloud_upload_outlined, size: 10, color: DS.statusPending),
      const SizedBox(width: 4),
      Text('Saved locally · will sync when online',
          style: DS.label(color: DS.statusPending).copyWith(fontSize: 9.5)),
    ]),
  );
}

class _RolePill extends StatelessWidget {
  final String label; final IconData icon; final Color color, bg;
  const _RolePill({required this.label, required this.icon, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: bg, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.30))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 9, color: color),
      const SizedBox(width: 4),
      Text(label, style: DS.label(color: color).copyWith(fontSize: 9, letterSpacing: 0.3)),
    ]),
  );
}

class _CatBadge extends StatelessWidget {
  final DonationCategory cat;
  const _CatBadge({required this.cat});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: cat.lightColor, borderRadius: BorderRadius.circular(99),
      border: Border.all(color: cat.color.withOpacity(0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(cat.icon, size: 9, color: cat.color),
      const SizedBox(width: 4),
      Text(cat.shortLabel, style: DS.label(color: cat.color).copyWith(fontSize: 9, letterSpacing: 0.3)),
    ]),
  );
}

class _ExpandToggle extends StatelessWidget {
  final bool expanded; final Color color; final VoidCallback onTap;
  const _ExpandToggle({required this.expanded, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(expanded ? 'Less' : 'Details', style: DS.label(color: color).copyWith(fontSize: 9.5)),
      Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 12, color: color),
    ]),
  );
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: DS.sapphire100, borderRadius: BorderRadius.circular(DS.rSm),
      border: Border.all(color: DS.sapphire500.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, size: 14, color: DS.sapphire700),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: DS.caption(color: DS.sapphire700).copyWith(fontSize: 10))),
    ]),
  );
}

class _ApprovedBanner extends StatelessWidget {
  final String text;
  const _ApprovedBanner({required this.text});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: DS.emerald100, borderRadius: BorderRadius.circular(DS.rSm),
      border: Border.all(color: DS.statusApproved.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.check_circle_rounded, size: 13, color: DS.statusApproved),
      const SizedBox(width: 6),
      Expanded(child: Text(text,
          style: DS.caption(color: DS.emerald700).copyWith(fontWeight: FontWeight.w600, fontSize: 10))),
    ]),
  );
}

class _RejectedBanner extends StatelessWidget {
  final String by, reason;
  const _RejectedBanner({required this.by, required this.reason});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: DS.crimson100, borderRadius: BorderRadius.circular(DS.rSm),
      border: Border.all(color: DS.statusRejected.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.cancel_rounded, size: 13, color: DS.statusRejected),
      const SizedBox(width: 6),
      Expanded(child: Text(
          'Rejected by $by${reason.isNotEmpty ? "  ·  $reason" : ""}',
          style: DS.caption(color: DS.crimson700).copyWith(fontWeight: FontWeight.w600, fontSize: 10))),
    ]),
  );
}

class _NotesBanner extends StatelessWidget {
  final String notes;
  const _NotesBanner({required this.notes});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.bgCard, borderRadius: BorderRadius.circular(DS.rSm),
        border: Border.all(color: t.bgRule)),
      child: Text('📝 $notes',
          style: DS.caption(color: t.textTertiary).copyWith(fontStyle: FontStyle.italic)),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label, value;
  const _Cell(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: DS.label(color: t.textTertiary)),
      const SizedBox(height: 3),
      Text(value, style: DS.subheading(color: t.textPrimary).copyWith(fontSize: 12.5)),
    ]);
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: DS.statusRejected.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text('Could not load credits', style: DS.subheading(color: t.textSecondary)),
          const SizedBox(height: 6),
          Text(error, textAlign: TextAlign.center, style: DS.caption(color: t.textTertiary)),
        ]),
      ),
    );
  }
}

class _EmptyCredits extends StatelessWidget {
  final bool pending; final String roleFrom;
  const _EmptyCredits({required this.pending, required this.roleFrom});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline_rounded, size: 44, color: DS.emerald500.withOpacity(0.35)),
        const SizedBox(height: 12),
        Text(pending ? 'No pending credits' : 'No credits yet',
            style: DS.subheading(color: t.textTertiary)),
        const SizedBox(height: 4),
        Text(
            pending ? 'All credits have been actioned'
                    : 'Credits appear here once $roleFrom records a donation.',
            textAlign: TextAlign.center,
            style: DS.caption(color: t.textTertiary)),
      ]),
    );
  }
}