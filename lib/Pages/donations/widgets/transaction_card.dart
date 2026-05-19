// lib/pages/donations/widgets/transaction_card.dart
//
// TransactionCard — updated with:
//   • "EDITED" badge when donation.isEdited == true
//   • Edit button in the details dialog (for canApprove roles)
//   • Edit history panel inside the details dialog
//   • Branch name shown properly in PDF receipt

import 'package:flutter/material.dart';
import '../../../constants/colors.dart';
import '../../../models/donation_models.dart';
import '../donations_shared.dart';
import '../donors_registry.dart';
import 'edit_donation_dialog.dart';
import 'package:intl/intl.dart';
import '../../../services/donations_local_storage.dart';

class TransactionCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEdited ? Colors.orange.shade200 : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: displayColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                    child: Icon(displayIcon, color: displayColor, size: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: displayColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getCategoryLabel(),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: displayColor, letterSpacing: 0.5),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isEdited) ...[
                          const SizedBox(width: 6),
                          const EditedBadge(),
                        ],
                      ]),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              donation.donorName, 
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gray900, letterSpacing: -0.2),
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
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.gray900, fontFamily: 'DMMono'),
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
    );
  }

  String _getCategoryLabel() {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isReceived ? AppColors.primary.withValues(alpha: 0.1) : AppColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isReceived ? AppColors.primary.withValues(alpha: 0.2) : AppColors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isReceived ? Icons.verified_rounded : Icons.pending_rounded, size: 10, color: isReceived ? AppColors.primary : AppColors.amber),
          const SizedBox(width: 4),
          Text(
            isReceived ? 'RECEIVED' : 'PENDING',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: isReceived ? AppColors.primary : AppColors.amber, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(BuildContext context, String dateStr) {
    showDialog(
      context: context,
      builder: (ctx) => _DonationDetailsDialog(
        donation: donation,
        dateStr: dateStr,
        currentUserRole: currentUserRole,
        currentUsername: currentUsername,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isReceived ? AppColors.primary.withValues(alpha: 0.1) : AppColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isReceived ? AppColors.primary.withValues(alpha: 0.2) : AppColors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isReceived ? Icons.verified_rounded : Icons.pending_rounded, size: 10, color: isReceived ? AppColors.primary : AppColors.amber),
        const SizedBox(width: 4),
        Text(
          isReceived ? 'RECEIVED' : 'PENDING',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: isReceived ? AppColors.primary : AppColors.amber, letterSpacing: 0.5),
        ),
      ]),
    );
  }

  Widget _detailBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.gray400, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gray800)),
      ],
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _donation;
    final isEdited = d.isEdited;
    final hasHistory = (d.editHistory?.isNotEmpty ?? false);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 420,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: d.isGoods ? Colors.blue.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(d.isGoods ? 'GOODS' : 'CASH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: d.isGoods ? Colors.blue : AppColors.primary, letterSpacing: 1)),
                  ),
                  Row(children: [
                    if (isEdited)
                      const Padding(padding: EdgeInsets.only(right: 8), child: EditedBadge()),
                    _statusPill(d.isGoods ? DonationStatus.received : d.status),
                  ]),
                ],
              ),

              const SizedBox(height: 20),

              // Amount / Goods
              if (d.isGoods)
                Text((d.probableAmount ?? 0) > 0 ? '${d.goodsItem ?? 'Goods'} (Est. PKR ${NumberFormat('#,##0').format(d.probableAmount)})' : d.goodsItem ?? 'Goods', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.gray900), textAlign: TextAlign.center)
              else
                Text('PKR ${NumberFormat('#,##0').format(d.amount)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1B5E20), fontFamily: 'DMMono')),
              const SizedBox(height: 8),
              Text('Receipt: ${cleanReceiptNumber(d.receiptNo)}', style: const TextStyle(fontSize: 13, color: AppColors.gray500, fontFamily: 'DMMono')),

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

              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: AppColors.gray200)),

              // Details Grid
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _detailBlock('Donor Name', d.donorName)),
                Expanded(child: _detailBlock('Phone', d.phone.isEmpty ? 'N/A' : d.phone)),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _detailBlock('Category', widget.categoryLabel)),
                Expanded(child: _detailBlock('Date', widget.dateStr)),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _detailBlock('Branch', d.branchName.isNotEmpty ? d.branchName : (d.branchId.isNotEmpty ? d.branchId : 'N/A'))),
                Expanded(child: _detailBlock('Collected By', d.recordedBy.isEmpty ? 'Unknown' : d.recordedBy)),
              ]),
              if (d.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _detailBlock('Notes', d.notes)),
                  const Spacer(),
                ]),
              ],

              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1, color: AppColors.gray200)),

              // Actions
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    _actionBtn(Icons.share_rounded, 'Share', AppColors.primary, () => showReceiptShareSheet(context, d.toMap())),
                    const SizedBox(width: 12),
                    _actionBtn(Icons.picture_as_pdf_rounded, 'PDF', Colors.redAccent, () => downloadReceiptPdf(d, context)),
                    const SizedBox(width: 12),
                    if (d.status == DonationStatus.pending && widget.currentUserRole.canMarkReceived) ...[
                      _actionBtn(Icons.check_circle_rounded, 'Received', Colors.green, () async {
                        await DonationsLocalStorage.updateDonationStatus(
                          branchId: d.branchId, localId: d.localId, date: d.date, newStatus: DonationStatus.received, firestoreId: d.firestoreId,
                        );
                        if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as Received'))); }
                      }),
                      const SizedBox(width: 12),
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
                      const SizedBox(width: 12),
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
                      const SizedBox(width: 12),
                    if (widget.currentUserRole.isChairman || widget.currentUserRole.isHqManager) ...[
                      _actionBtn(Icons.delete_forever_rounded, 'Delete', Colors.red, () => _confirmDelete(context)),
                      const SizedBox(width: 12),
                    ],
                    ],
                    _actionBtn(Icons.close_rounded, 'Close', AppColors.gray500, () => Navigator.pop(context)),
                    const SizedBox(width: 20),
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