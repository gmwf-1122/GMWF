// lib/pages/donations/donation_boxes_screen.dart
//
// Full UI for Donation Box management:
//  - Box Registry List (with overdue indicators)
//  - Register Box Dialog
//  - Box Detail View (info + opening history timeline)
//  - Open Box Dialog
//  - Yearly Report Dialog with Excel download

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/donation_box_models.dart';
import '../../services/donation_box_storage.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../constants/colors.dart';
import 'donations_shared.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DONATION BOXES WIDGET (embeddable in tab)
// ─────────────────────────────────────────────────────────────────────────────

class DonationBoxesWidget extends StatefulWidget {
  final String branchId;
  final String branchName;
  final String username;
  final UserRole role;

  const DonationBoxesWidget({
    super.key,
    required this.branchId,
    required this.branchName,
    this.username = '',
    this.role = UserRole.staff,
  });

  @override
  State<DonationBoxesWidget> createState() => _DonationBoxesWidgetState();
}

class _DonationBoxesWidgetState extends State<DonationBoxesWidget> {
  List<DonationBox> _boxes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBoxes();
  }

  @override
  void didUpdateWidget(DonationBoxesWidget old) {
    super.didUpdateWidget(old);
    if (old.branchId != widget.branchId) _loadBoxes();
  }

  Future<void> _loadBoxes() async {
    setState(() => _loading = true);
    try {
      await DonationBoxStorage.init();
      if (widget.branchId.isNotEmpty && widget.branchId != 'all') {
        await DonationBoxStorage.downloadBoxes(widget.branchId);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _boxes = DonationBoxStorage.getBoxes(widget.branchId);
      _loading = false;
    });
  }

  void _refresh() {
    setState(() {
      _boxes = DonationBoxStorage.getBoxes(widget.branchId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: t.accent),
      );
    }

    return CustomScrollView(
      slivers: [
        // ── Header ────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 24, isMobile ? 16 : 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(t, isMobile),
                const SizedBox(height: 16),
                _buildSummaryCards(t, isMobile),
                const SizedBox(height: 20),
                Text(
                  'REGISTERED BOXES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: t.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // ── Box List ─────────────────────────────────────────────────────
        if (_boxes.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(t),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, index) => _BoxCard(
                  box: _boxes[index],
                  onTap: () => _showBoxDetail(_boxes[index]),
                  onOpenBox: () => _showOpenBoxDialog(_boxes[index]),
                ),
                childCount: _boxes.length,
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHeader(RoleThemeData t, bool isMobile) {
    final currentYear = DateTime.now().year;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Donation Boxes',
                style: TextStyle(
                  fontSize: isMobile ? 22 : 28,
                  fontWeight: FontWeight.w900,
                  color: t.textPrimary,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_boxes.length} box${_boxes.length == 1 ? '' : 'es'} registered',
                style: TextStyle(
                  fontSize: 13,
                  color: t.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // ── 12-Month Annual Report Button ──
        OutlinedButton.icon(
          onPressed: () async {
            if (_boxes.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No donation boxes to export')),
              );
              return;
            }
            await DonationBoxStorage.exportAllBoxesYearlyReport(
              branchId: widget.branchId,
              branchName: widget.branchName,
              year: currentYear,
            );
          },
          icon: Icon(Icons.table_chart_rounded, size: 16, color: t.accent),
          label: Text(
            isMobile ? '12M Report' : 'Annual Excel ($currentYear)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: t.accent,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: t.accent.withValues(alpha: 0.5)),
            backgroundColor: t.accent.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(width: 10),
        _RegisterBoxButton(
          onTap: () => _showRegisterBoxDialog(),
          isMobile: isMobile,
        ),
      ],
    );
  }

  Widget _buildSummaryCards(RoleThemeData t, bool isMobile) {
    final activeCount = _boxes.where((b) => b.isActive).length;
    final overdueCount = _boxes.where((b) => b.isActive && b.isOverdue).length;
    final totalCollected = DonationBoxStorage.getOpenings(widget.branchId)
        .fold<double>(0, (sum, o) => sum + o.amount);
    final fmt = NumberFormat('#,##0');

    final cards = [
      _SummaryMiniCard(
        label: 'Active',
        value: '$activeCount',
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFF047857),
        t: t,
      ),
      _SummaryMiniCard(
        label: 'Overdue',
        value: '$overdueCount',
        icon: Icons.warning_amber_rounded,
        color: overdueCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
        t: t,
      ),
      _SummaryMiniCard(
        label: 'Collected',
        value: 'PKR ${fmt.format(totalCollected)}',
        icon: Icons.payments_rounded,
        color: const Color(0xFF1D4ED8),
        t: t,
      ),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: cards.map((c) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(width: 160, child: c),
          )).toList(),
        ),
      );
    }

    return Row(
      children: cards.map((c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: c,
        ),
      )).toList(),
    );
  }

  Widget _buildEmptyState(RoleThemeData t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2_rounded, size: 44, color: t.accent.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 24),
            Text(
              'No Donation Boxes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: t.textPrimary, letterSpacing: -0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Register your first donation box to start tracking collections.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.textTertiary, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showRegisterBoxDialog,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Register Box', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ══════════════════════════════════════════════════════════════════════════

  void _showRegisterBoxDialog() {
    final numberCtrl = TextEditingController(
      text: DonationBoxStorage.suggestNextBoxNumber(widget.branchId),
    );
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final t = RoleThemeScope.dataOf(ctx);
        return Dialog(
          backgroundColor: t.bgCard,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.add_box_rounded, size: 22, color: t.accent),
                        ),
                        const SizedBox(width: 14),
                        Text('Register New Box', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: t.textPrimary, letterSpacing: -0.5)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DialogField(label: 'Box Number', controller: numberCtrl, hint: 'BOX-001', t: t),
                    const SizedBox(height: 14),
                    _DialogField(label: 'Holder Name *', controller: nameCtrl, hint: 'Person who keeps the box', t: t),
                    const SizedBox(height: 14),
                    _DialogField(label: 'Phone', controller: phoneCtrl, hint: '03xx-xxxxxxx', t: t, keyboardType: TextInputType.phone),
                    const SizedBox(height: 14),
                    _DialogField(label: 'Address', controller: addressCtrl, hint: 'Shop / House address', t: t, maxLines: 2),
                    const SizedBox(height: 14),
                    _DialogField(label: 'Notes', controller: notesCtrl, hint: 'Optional notes', t: t, maxLines: 2),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.textSecondary,
                              side: BorderSide(color: t.bgRule),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Holder name is required'), backgroundColor: Colors.red),
                                );
                                return;
                              }
                              final box = DonationBoxStorage.createBox(
                                boxNumber: numberCtrl.text.trim(),
                                holderName: nameCtrl.text.trim(),
                                holderPhone: phoneCtrl.text.trim(),
                                holderAddress: addressCtrl.text.trim(),
                                branchId: widget.branchId,
                                branchName: widget.branchName,
                                notes: notesCtrl.text.trim(),
                              );
                              await DonationBoxStorage.saveBox(box);
                              if (ctx.mounted) Navigator.pop(ctx);
                              _refresh();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Box ${box.boxNumber} registered'), backgroundColor: Colors.green),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Register', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showOpenBoxDialog(DonationBox box) {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        final t = RoleThemeScope.dataOf(ctx);
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: t.bgCard,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF047857).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.lock_open_rounded, size: 22, color: Color(0xFF047857)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Open Box', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: t.textPrimary)),
                                Text(box.boxNumber, style: TextStyle(fontSize: 13, color: t.textTertiary, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Date picker
                      Text('Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.textSecondary)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: t.bgCardAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: t.bgRule),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 16, color: t.accent),
                              const SizedBox(width: 10),
                              Text(
                                DateFormat('dd MMM yyyy').format(selectedDate),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary),
                              ),
                              const Spacer(),
                              Icon(Icons.edit_rounded, size: 14, color: t.textTertiary),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _DialogField(label: 'Amount (PKR) *', controller: amountCtrl, hint: '0', t: t, keyboardType: TextInputType.number),
                      const SizedBox(height: 14),
                      _DialogField(label: 'Notes', controller: notesCtrl, hint: 'Optional', t: t),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: t.textSecondary,
                                side: BorderSide(color: t.bgRule),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                if (selectedDate.isAfter(DateTime.now())) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Cannot record donation box openings for future dates'), backgroundColor: Colors.red),
                                  );
                                  return;
                                }
                                final amt = double.tryParse(amountCtrl.text.trim().replaceAll(',', ''));
                                if (amt == null || amt < 0) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Enter a valid amount'), backgroundColor: Colors.red),
                                  );
                                  return;
                                }
                                final opening = DonationBoxStorage.createOpening(
                                  boxId: box.id,
                                  boxNumber: box.boxNumber,
                                  openDate: DateFormat('yyyy-MM-dd').format(selectedDate),
                                  amount: amt,
                                  collectedBy: widget.username,
                                  branchId: widget.branchId,
                                  branchName: widget.branchName,
                                  notes: notesCtrl.text.trim(),
                                );
                                await DonationBoxStorage.saveOpening(opening);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _refresh();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Box ${box.boxNumber} opened — PKR ${NumberFormat('#,##0').format(amt)}'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF047857),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Record Opening', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBoxDetail(DonationBox box) {
    showDialog(
      context: context,
      builder: (ctx) => _BoxDetailDialog(
        box: box,
        branchId: widget.branchId,
        username: widget.username,
        onOpenBox: () {
          Navigator.pop(ctx);
          _showOpenBoxDialog(box);
        },
        onRefresh: _refresh,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOX CARD
// ─────────────────────────────────────────────────────────────────────────────

class _BoxCard extends StatefulWidget {
  final DonationBox box;
  final VoidCallback onTap;
  final VoidCallback onOpenBox;

  const _BoxCard({required this.box, required this.onTap, required this.onOpenBox});

  @override
  State<_BoxCard> createState() => _BoxCardState();
}

class _BoxCardState extends State<_BoxCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final box = widget.box;
    final fmt = NumberFormat('#,##0');

    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;

    if (!box.isActive) {
      statusColor = const Color(0xFF6B7280);
      statusLabel = 'Inactive';
      statusIcon = Icons.pause_circle_rounded;
    } else if (box.isOverdue) {
      statusColor = const Color(0xFFDC2626);
      statusLabel = 'Overdue ${box.daysSinceLastOpened ?? 30}d';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = const Color(0xFF047857);
      statusLabel = box.lastOpenedDate != null ? '${box.daysSinceLastOpened}d ago' : 'New';
      statusIcon = Icons.check_circle_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isHovered ? t.accent.withValues(alpha: 0.03) : t.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isHovered ? t.accent.withValues(alpha: 0.2) : t.bgRule,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.04 : 0.02),
                  blurRadius: _isHovered ? 12 : 6,
                  offset: Offset(0, _isHovered ? 4 : 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Box number badge
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: statusColor.withValues(alpha: 0.15)),
                  ),
                  child: Center(
                    child: Text(
                      box.boxNumber.replaceAll('BOX-', ''),
                      style: GoogleFonts.dmMono(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        box.holderName,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: t.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        box.holderAddress.isNotEmpty ? box.holderAddress : box.holderPhone,
                        style: TextStyle(fontSize: 12, color: t.textTertiary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 11, color: statusColor),
                                const SizedBox(width: 4),
                                Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                              ],
                            ),
                          ),
                          if (box.lastOpenedAmount != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              'PKR ${fmt.format(box.lastOpenedAmount)}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Open button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onOpenBox,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFF047857)),
                          const SizedBox(width: 6),
                          Text(
                            'Open',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOX DETAIL DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _BoxDetailDialog extends StatefulWidget {
  final DonationBox box;
  final String branchId;
  final String username;
  final VoidCallback onOpenBox;
  final VoidCallback onRefresh;

  const _BoxDetailDialog({
    required this.box,
    required this.branchId,
    required this.username,
    required this.onOpenBox,
    required this.onRefresh,
  });

  @override
  State<_BoxDetailDialog> createState() => _BoxDetailDialogState();
}

class _BoxDetailDialogState extends State<_BoxDetailDialog> {
  late List<BoxOpening> _openings;
  int _reportYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _openings = DonationBoxStorage.getOpeningsForBox(widget.box.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final box = widget.box;
    final fmt = NumberFormat('#,##0');
    final totalCollected = _openings.fold<double>(0, (sum, o) => sum + o.amount);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      backgroundColor: t.bgCard,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.bgRule)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        box.boxNumber.replaceAll('BOX-', ''),
                        style: GoogleFonts.dmMono(fontSize: 18, fontWeight: FontWeight.w800, color: t.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(box.boxNumber, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: t.textPrimary)),
                        Text(box.holderName, style: TextStyle(fontSize: 13, color: t.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: t.textTertiary),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info section
                    _InfoRow(label: 'Holder', value: box.holderName, icon: Icons.person_rounded, t: t),
                    if (box.holderPhone.isNotEmpty) _InfoRow(label: 'Phone', value: box.holderPhone, icon: Icons.phone_rounded, t: t),
                    if (box.holderAddress.isNotEmpty) _InfoRow(label: 'Address', value: box.holderAddress, icon: Icons.location_on_rounded, t: t),
                    _InfoRow(label: 'Registered', value: box.registeredDate, icon: Icons.calendar_today_rounded, t: t),
                    _InfoRow(label: 'Total Collected', value: 'PKR ${fmt.format(totalCollected)}', icon: Icons.payments_rounded, t: t),
                    _InfoRow(label: 'Times Opened', value: '${_openings.length}', icon: Icons.lock_open_rounded, t: t),

                    const SizedBox(height: 20),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onOpenBox,
                            icon: const Icon(Icons.lock_open_rounded, size: 18),
                            label: const Text('Open Box', style: TextStyle(fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF047857),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showYearlyReport(),
                            icon: Icon(Icons.download_rounded, size: 18, color: t.accent),
                            label: Text('Yearly Report', style: TextStyle(fontWeight: FontWeight.w800, color: t.accent)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: t.accent.withValues(alpha: 0.3)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Opening history
                    Text('OPENING HISTORY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: t.textTertiary, letterSpacing: 1.2)),
                    const SizedBox(height: 12),

                    if (_openings.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: t.bgCardAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text('No openings recorded yet', style: TextStyle(color: t.textTertiary, fontSize: 13)),
                        ),
                      )
                    else
                      ..._openings.take(20).map((o) => _OpeningTimelineItem(opening: o, t: t)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showYearlyReport() {
    showDialog(
      context: context,
      builder: (ctx) {
        final t = RoleThemeScope.dataOf(ctx);
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final report = DonationBoxStorage.getYearlyReport(widget.box.id, _reportYear);
            final fmt = NumberFormat('#,##0');
            final totalAmount = report.fold<double>(0, (sum, r) => sum + r.amount);
            final openedCount = report.where((r) => r.wasOpened).length;

            return Dialog(
              backgroundColor: t.bgCard,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 500, maxHeight: MediaQuery.of(ctx).size.height * 0.8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                      child: Row(
                        children: [
                          Icon(Icons.analytics_rounded, color: t.accent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${widget.box.boxNumber} — $_reportYear Report',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: t.textPrimary),
                            ),
                          ),
                          // Year picker
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: t.bgCardAlt,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.bgRule),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () => setDialogState(() => _reportYear--),
                                  child: Icon(Icons.chevron_left_rounded, size: 20, color: t.textSecondary),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('$_reportYear', style: TextStyle(fontWeight: FontWeight.w800, color: t.textPrimary, fontSize: 14)),
                                ),
                                InkWell(
                                  onTap: _reportYear < DateTime.now().year ? () => setDialogState(() => _reportYear++) : null,
                                  child: Icon(Icons.chevron_right_rounded, size: 20, color: _reportYear < DateTime.now().year ? t.textSecondary : t.textTertiary.withValues(alpha: 0.3)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: t.bgRule, height: 1),
                    // Report grid
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // Summary bar
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: t.accent.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: t.accent.withValues(alpha: 0.12)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Column(children: [
                                    Text('Opened', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: t.textTertiary)),
                                    const SizedBox(height: 4),
                                    Text('$openedCount / 12', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: t.accent)),
                                  ]),
                                  Container(width: 1, height: 32, color: t.bgRule),
                                  Column(children: [
                                    Text('Total', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: t.textTertiary)),
                                    const SizedBox(height: 4),
                                    Text('PKR ${fmt.format(totalAmount)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: t.textPrimary)),
                                  ]),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Monthly rows
                            ...report.map((r) {
                              final Color rowColor = r.wasOpened
                                  ? const Color(0xFF047857).withValues(alpha: 0.06)
                                  : const Color(0xFFDC2626).withValues(alpha: 0.04);
                              final Color textColor = r.wasOpened
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFDC2626);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: rowColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 80,
                                      child: Text(r.monthName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
                                    ),
                                    Icon(
                                      r.wasOpened ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                      size: 16,
                                      color: textColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      r.wasOpened ? 'OPENED' : 'NOT OPENED',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textColor),
                                    ),
                                    const Spacer(),
                                    if (r.wasOpened)
                                      Text(
                                        'PKR ${fmt.format(r.amount)}',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t.textPrimary),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    // Footer
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.bgRule)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: t.textSecondary,
                                side: BorderSide(color: t.bgRule),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await DonationBoxStorage.exportBoxYearlyReport(widget.box, _reportYear);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Report exported'), backgroundColor: Colors.green),
                                  );
                                }
                              },
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Download Excel', style: TextStyle(fontWeight: FontWeight.w800)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final RoleThemeData t;

  const _SummaryMiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.bgRule),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: t.textTertiary, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterBoxButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isMobile;

  const _RegisterBoxButton({required this.onTap, required this.isMobile});

  @override
  State<_RegisterBoxButton> createState() => _RegisterBoxButtonState();
}

class _RegisterBoxButtonState extends State<_RegisterBoxButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: widget.isMobile ? 14 : 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isHovered
                  ? [t.accent, t.accent.withValues(alpha: 0.85)]
                  : [t.accent.withValues(alpha: 0.9), t.accent],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: t.accent.withValues(alpha: _isHovered ? 0.35 : 0.15),
                blurRadius: _isHovered ? 16 : 8,
                offset: Offset(0, _isHovered ? 6 : 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              if (!widget.isMobile) ...[
                const SizedBox(width: 8),
                const Text('Register Box', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final RoleThemeData t;
  final TextInputType? keyboardType;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;

  const _DialogField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.t,
    this.keyboardType,
    this.maxLines = 1,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters ??
              (keyboardType == TextInputType.phone
                  ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]
                  : (keyboardType == TextInputType.number
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : null)),
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: t.textTertiary, fontWeight: FontWeight.w400),
            filled: true,
            fillColor: t.bgCardAlt,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.bgRule),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.bgRule),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.accent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final RoleThemeData t;

  const _InfoRow({required this.label, required this.value, required this.icon, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: t.accent),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.textTertiary)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _OpeningTimelineItem extends StatelessWidget {
  final BoxOpening opening;
  final RoleThemeData t;

  const _OpeningTimelineItem({required this.opening, required this.t});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    final date = DateTime.tryParse(opening.openDate);
    final dateLabel = date != null ? DateFormat('dd MMM yyyy').format(date) : opening.openDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF047857),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.3), width: 2),
                ),
              ),
              Container(width: 2, height: 30, color: t.bgRule),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.bgCardAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
                        if (opening.collectedBy.isNotEmpty)
                          Text('by ${opening.collectedBy}', style: TextStyle(fontSize: 11, color: t.textTertiary)),
                        if (opening.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(opening.notes, style: TextStyle(fontSize: 11, color: t.textTertiary, fontStyle: FontStyle.italic)),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'PKR ${fmt.format(opening.amount)}',
                    style: GoogleFonts.dmMono(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF047857)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
