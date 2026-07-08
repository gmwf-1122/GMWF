// lib/pages/donations/widgets/transaction_card.dart
//
// TransactionCard — updated with:
//   • "EDITED" badge when donation.isEdited == true
//   • Edit button in the details dialog (for canApprove roles)
//   • Edit history panel inside the details dialog
//   • Branch name shown properly in PDF receipt

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../constants/colors.dart';
import '../../../models/donation_models.dart';
import '../donations_shared.dart';
import '../donors_registry.dart';
import 'edit_donation_dialog.dart';
import 'package:intl/intl.dart';
import '../../../services/donations_local_storage.dart';

class TransactionCard extends StatefulWidget {
  final DonationRecord donation;
  final UserRole currentUserRole;
  final VoidCallback onTap;
  final String currentUsername;

  const TransactionCard({
    super.key,
    required this.donation,
    required this.currentUserRole,
    required this.onTap,
    this.currentUsername = '',
  });

  @override
  State<TransactionCard> createState() => _TransactionCardState();
}

class _TransactionCardState extends State<TransactionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final donation = widget.donation;
    final cat = donation.category;
    final displayDate = donation.timestamp != null
        ? DateTime.parse(donation.timestamp!)
        : (int.tryParse(donation.localId) != null && int.parse(donation.localId) > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(int.parse(donation.localId))
            : DateTime.parse(donation.date));

    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(displayDate);
    final displayColor = donation.subtype?.color ?? cat.color;
    final displayIcon  = donation.subtype?.icon  ?? cat.icon;
    final isEdited = donation.isEdited;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        transform: Matrix4.identity()..scale(_isHovered ? 1.015 : 1.0),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? displayColor.withValues(alpha: 0.5)
                : (isEdited ? Colors.orange.shade200 : const Color(0x0A000000)),
            width: _isHovered || isEdited ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? displayColor.withValues(alpha: 0.12)
                  : displayColor.withValues(alpha: 0.04),
              blurRadius: _isHovered ? 16 : 10,
              offset: Offset(0, _isHovered ? 6 : 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.01),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showDetailsDialog(context, dateStr),
            borderRadius: BorderRadius.circular(16),
            hoverColor: displayColor.withValues(alpha: 0.02),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Category Icon with Gradient background
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          displayColor.withValues(alpha: 0.15),
                          displayColor.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(displayIcon, color: displayColor, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: displayColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: displayColor.withValues(alpha: 0.15),
                                  width: 1.0,
                                ),
                              ),
                              child: Text(
                                _getCategoryLabel(),
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: displayColor, letterSpacing: 0.6),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isEdited) ...[
                              const SizedBox(width: 6),
                              const EditedBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                donation.donorName, 
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.gray900, letterSpacing: -0.2),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (donation.donorId != 'anonymous' && !donation.donorId.startsWith('guest_') && donation.donorName.trim().isNotEmpty && donation.phone.trim().isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${cleanReceiptNumber(donation.receiptNo)} • ${donation.branchName.isNotEmpty ? donation.branchName : donation.branchId}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.gray500),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (donation.isGoods)
                        Text(
                          (donation.probableAmount ?? 0) > 0 ? '${donation.goodsItem ?? 'Goods'} (Est. PKR ${NumberFormat('#,##0').format(donation.probableAmount)})' : (donation.goodsItem ?? 'Goods'),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cat.color),
                        )
                      else
                        Text(
                          'PKR ${NumberFormat('#,##0').format(donation.amount)}',
                          style: GoogleFonts.dmMono(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.gray900),
                        ),
                      const SizedBox(height: 6),
                      _statusPill(donation.isGoods ? DonationStatus.received : donation.status),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getCategoryLabel() {
    final donation = widget.donation;
    String label = donation.category.shortLabel.toUpperCase();
    if (donation.gmwfSubCategory != null) {
      label += ' - ${donation.gmwfSubCategory!.label.toUpperCase()}';
    }
    if (donation.subtype != null) {
      label += ' (${donation.subtype!.label.toUpperCase()})';
    }
    return label;
  }

  Widget _statusPill(String status) {
    final isReceived = status == DonationStatus.received;
    final Color bgColor = isReceived 
        ? const Color(0xFF10B981).withValues(alpha: 0.08)
        : const Color(0xFFF59E0B).withValues(alpha: 0.08);
    final Color borderClr = isReceived
        ? const Color(0xFF10B981).withValues(alpha: 0.2)
        : const Color(0xFFF59E0B).withValues(alpha: 0.2);
    final Color textClr = isReceived
        ? const Color(0xFF065F46)
        : const Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderClr),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReceived ? Icons.verified_rounded : Icons.hourglass_bottom_rounded, 
            size: 10, 
            color: textClr,
          ),
          const SizedBox(width: 4),
          Text(
            isReceived ? 'RECEIVED' : 'PENDING',
            style: TextStyle(
              fontSize: 9, 
              fontWeight: FontWeight.w900, 
              color: textClr, 
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(BuildContext context, String dateStr) {
    showDialog(
      context: context,
      builder: (ctx) => _DonationDetailsDialog(
        donation: widget.donation,
        dateStr: dateStr,
        currentUserRole: widget.currentUserRole,
        currentUsername: widget.currentUsername,
        categoryLabel: _getCategoryLabel(),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// DETAILS DIALOG — extracted as StatefulWidget to support edit navigation
// ─────────────────────────────────────────────────────────────────────────────

class _DonationDetailsDialog extends StatefulWidget {
  final DonationRecord donation;
  final String dateStr;
  final UserRole currentUserRole;
  final String currentUsername;
  final String categoryLabel;

  const _DonationDetailsDialog({
    required this.donation,
    required this.dateStr,
    required this.currentUserRole,
    required this.currentUsername,
    required this.categoryLabel,
  });

  @override
  State<_DonationDetailsDialog> createState() => _DonationDetailsDialogState();
}

class _DonationDetailsDialogState extends State<_DonationDetailsDialog> {
  bool _showHistory = false;
  late DonationRecord _donation;

  @override
  void initState() {
    super.initState();
    _donation = widget.donation;
  }

  Widget _statusPill(String status) {
    final isReceived = status == DonationStatus.received;
    final Color bgColor = isReceived 
        ? const Color(0xFF10B981).withOpacity(0.06)
        : const Color(0xFFF59E0B).withOpacity(0.06);
    final Color borderClr = isReceived
        ? const Color(0xFF10B981).withOpacity(0.15)
        : const Color(0xFFF59E0B).withOpacity(0.15);
    final Color textClr = isReceived
        ? const Color(0xFF047857)
        : const Color(0xFFD97706);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderClr, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReceived ? Icons.verified_rounded : Icons.hourglass_bottom_rounded, 
            size: 11, 
            color: textClr,
          ),
          const SizedBox(width: 4),
          Text(
            isReceived ? 'RECEIVED' : 'PENDING',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9, 
              fontWeight: FontWeight.w800, 
              color: textClr, 
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: AppColors.gray400,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.gray800,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ScaleButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withOpacity(0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _donation;
    final isEdited = d.isEdited;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 16,
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: d.isGoods ? Colors.blue.withOpacity(0.06) : AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: d.isGoods ? Colors.blue.withOpacity(0.15) : AppColors.primary.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      d.isGoods ? 'GOODS' : 'CASH', 
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9, 
                        fontWeight: FontWeight.w800, 
                        color: d.isGoods ? Colors.blue : AppColors.primary, 
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  Row(children: [
                    if (isEdited)
                      const Padding(padding: EdgeInsets.only(right: 8), child: EditedBadge()),
                    _statusPill(d.isGoods ? DonationStatus.received : d.status),
                  ]),
                ],
              ),

              const SizedBox(height: 24),

              // Sophisticated Geometric Amount Header (replacing old green monospace)
              if (d.isGoods)
                Text(
                  (d.probableAmount ?? 0) > 0 
                      ? '${d.goodsItem ?? 'Goods'} (Est. PKR ${NumberFormat('#,##0').format(d.probableAmount)})' 
                      : d.goodsItem ?? 'Goods', 
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22, 
                    fontWeight: FontWeight.w800, 
                    color: AppColors.gray900,
                    letterSpacing: -0.5,
                  ), 
                  textAlign: TextAlign.center,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'PKR ',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gray500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      NumberFormat('#,##0').format(d.amount),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gray900,
                        letterSpacing: -1.0,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                'RECEIPT: ${cleanReceiptNumber(d.receiptNo)}', 
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, 
                  fontWeight: FontWeight.w700,
                  color: AppColors.gray400,
                  letterSpacing: 0.8,
                ),
              ),

              // Edited notice banner
              if (isEdited) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() => _showHistory = !_showHistory),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.edit_rounded, size: 13, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('This donation was edited', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
                          if (d.editReason?.isNotEmpty == true)
                            Text('Reason: ${d.editReason}', style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                          if (d.editedBy?.isNotEmpty == true)
                            Text('By ${d.editedBy} ${d.editedAt != null ? "on ${DateFormat('dd MMM yyyy').format(DateTime.tryParse(d.editedAt!) ?? DateTime.now())}" : ""}',
                                style: TextStyle(fontSize: 10, color: Colors.orange.shade600)),
                        ]),
                      ),
                      Icon(_showHistory ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: Colors.orange.shade700),
                    ]),
                  ),
                ),

                // Edit history collapsible
                if (_showHistory)
                  EditHistoryViewer(donation: d),
              ],

              const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Divider(height: 1, color: AppColors.gray200)),

              // Details Grid
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _detailBlock('Donor Name', d.donorName)),
                Expanded(child: _detailBlock('Phone', d.phone.isEmpty ? 'N/A' : d.phone)),
              ]),
              const SizedBox(height: 18),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _detailBlock('Category', widget.categoryLabel)),
                Expanded(child: _detailBlock('Date', widget.dateStr)),
              ]),
              const SizedBox(height: 18),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _detailBlock('Branch', d.branchName.isNotEmpty ? d.branchName : (d.branchId.isNotEmpty ? d.branchId : 'N/A'))),
                Expanded(child: _detailBlock('Collected By', d.recordedBy.isEmpty ? 'Unknown' : d.recordedBy)),
              ]),
              if (d.bookReceiptNo != null && d.bookReceiptNo!.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _detailBlock('Book Receipt #', d.bookReceiptNo!)),
                  const Spacer(),
                ]),
              ],
              if (d.notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: _detailBlock('Notes', d.notes)),
                  const Spacer(),
                ]),
              ],

              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: AppColors.gray200)),

              // Actions capsule toolbar dock
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _actionBtn(Icons.share_rounded, 'Share', AppColors.primary, () => showReceiptShareSheet(context, d.toMap())),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.picture_as_pdf_rounded, 'PDF', Colors.redAccent, () => downloadReceiptPdf(d, context)),
                    const SizedBox(width: 8),
                    if (d.status == DonationStatus.pending && widget.currentUserRole.canMarkReceived) ...[
                      _actionBtn(Icons.check_circle_rounded, 'Received', Colors.green, () async {
                        await DonationsLocalStorage.updateDonationStatus(
                          branchId: d.branchId, localId: d.localId, date: d.date, newStatus: DonationStatus.received, firestoreId: d.firestoreId,
                        );
                        if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as Received'))); }
                      }),
                      const SizedBox(width: 8),
                    ],
                    if (d.donorId != 'anonymous' && !d.donorId.startsWith('guest_') && widget.currentUserRole.canApprove) ...[
                      _actionBtn(Icons.person_rounded, 'Edit Donor', Colors.indigo, () async {
                        Navigator.pop(context);
                        final donors = DonationsLocalStorage.getAllDonors('all');
                        final matches = donors.where((donor) => donor.id == d.donorId).toList();
                        if (matches.isNotEmpty && context.mounted) {
                          showEditDonorDialog(context, matches.first);
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donor details not available locally')));
                        }
                      }),
                      const SizedBox(width: 8),
                    ],
                    if (widget.currentUserRole.canApprove) ...[
                      _actionBtn(Icons.edit_rounded, 'Edit', Colors.orange.shade700, () async {
                        Navigator.pop(context);
                        await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => EditDonationDialog(
                            donation: d,
                            currentUsername: widget.currentUsername,
                            currentUserRole: widget.currentUserRole,
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                    ],
                    if (widget.currentUserRole.isChairman || widget.currentUserRole.isHqManager) ...[
                      _actionBtn(Icons.delete_forever_rounded, 'Delete', Colors.red, () => _confirmDelete(context)),
                      const SizedBox(width: 8),
                    ],
                    _actionBtn(Icons.close_rounded, 'Close', AppColors.gray500, () => Navigator.pop(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Donation?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will permanently remove the donation record. This action cannot be undone.'),
            const SizedBox(height: 16),
            const Text('Reason for Deletion:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: 'Enter reason here...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide a reason for deletion'), backgroundColor: Colors.orange),
                );
                return;
              }

              Navigator.pop(ctx); // Close confirmation
              Navigator.pop(context); // Close details dialog
              
              await DonationsLocalStorage.deleteDonation(
                _donation.hiveKey,
                _donation.branchId,
                reason: reason,
                userId: widget.currentUsername, // Use username as ID if ID is missing
                username: widget.currentUsername,
              );
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Donation deleted successfully'), backgroundColor: Colors.red),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}