// lib/pages/donations/widgets/edit_donation_dialog.dart
//
// Edit Donation Dialog
// ─────────────────────────────────────────────────────────────────────────────
// • Loads existing donation data
// • Allows editing amount, category, subtype, notes, payment method
// • Requires a reason for the edit
// • Saves original data in editHistory array on the record
// • Updates Firestore + local storage atomically

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../constants/colors.dart';
import '../../../models/donation_models.dart';
import '../../../services/donations_local_storage.dart';
import '../donations_shared.dart';

class EditDonationDialog extends StatefulWidget {
  final DonationRecord donation;
  final String currentUsername;
  final UserRole currentUserRole;

  const EditDonationDialog({
    super.key,
    required this.donation,
    required this.currentUsername,
    required this.currentUserRole,
  });

  @override
  State<EditDonationDialog> createState() => _EditDonationDialogState();
}

class _EditDonationDialogState extends State<EditDonationDialog> {
  final _formKey  = GlobalKey<FormState>();
  final _donorNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _estimatedAmountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final _goodsCtrl  = TextEditingController();

  DonationCategory? _selectedCategory;
  GmwfSubCategory?  _selectedGmwfSub;
  DonationSubtype?  _selectedSubtype;
  String _paymentMethod = 'Cash';
  bool   _saving        = false;
  String? _errorMessage;
  DateTime? _selectedDate;
  final _bookReceiptNoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.donation;
    _donorNameCtrl.text = d.donorName;
    _phoneCtrl.text = d.phone;
    _amountCtrl.text  = d.amount > 0 ? d.amount.toStringAsFixed(d.amount % 1 == 0 ? 0 : 2) : '';
    final prob = d.probableAmount ?? 0.0;
    _estimatedAmountCtrl.text = prob > 0 ? prob.toStringAsFixed(prob % 1 == 0 ? 0 : 2) : '';
    if (d.isGoods && d.amount > 0 && prob == 0) {
      _estimatedAmountCtrl.text = d.amount.toStringAsFixed(d.amount % 1 == 0 ? 0 : 2);
    }
    _notesCtrl.text   = d.notes;
    _goodsCtrl.text   = d.goodsItem ?? '';
    _paymentMethod    = d.paymentMethod.isNotEmpty ? d.paymentMethod : 'Cash';
    _selectedCategory = d.category == DonationCategory.all ? DonationCategory.gmwf : d.category;
    _selectedGmwfSub  = d.gmwfSubCategory;
    _selectedSubtype  = d.subtype;
    _selectedDate     = DateTime.tryParse(d.date) ?? DateTime.now();
    _bookReceiptNoCtrl.text = d.bookReceiptNo ?? '';
  }

  @override
  void dispose() {
    _donorNameCtrl.dispose();
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    _estimatedAmountCtrl.dispose();
    _reasonCtrl.dispose();
    _notesCtrl.dispose();
    _goodsCtrl.dispose();
    _bookReceiptNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_reasonCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please provide a reason for this edit.');
      return;
    }

    setState(() { _saving = true; _errorMessage = null; });

    try {
      final d   = widget.donation;
      final now = DateTime.now().toIso8601String();

      // Snapshot of original values for the audit trail
      final originalSnapshot = {
        'amount':           d.amount,
        'probableAmount':   d.probableAmount,
        'donorName':        d.donorName,
        'phone':            d.phone,
        'categoryId':       d.categoryId,
        'gmwfSubCategoryId': d.gmwfSubCategoryId,
        'subtypeId':        d.subtypeId,
        'paymentMethod':    d.paymentMethod,
        'notes':            d.notes,
        'goodsItem':        d.goodsItem,
        'branchName':       d.branchName,
        'date':             d.date,
        'bookReceiptNo':    d.bookReceiptNo,
      };

      final editEntry = {
        'originalData': originalSnapshot,
        'reason':       _reasonCtrl.text.trim(),
        'editedBy':     widget.currentUsername,
        'editedAt':     now,
        'changes':      _buildChangeList(d),
      };

      // Compute new values
      final newDonorName = _donorNameCtrl.text.trim();
      final newDonorNameNorm = newDonorName.toLowerCase();
      final bool newIsAnonymous = newDonorNameNorm == 'anonymous' || newDonorNameNorm == 'valued donor' || newDonorNameNorm == 'walk-in donor';
      final newPhone = _phoneCtrl.text.trim();

      final newAmount    = d.isGoods ? 0.0 : (double.tryParse(_amountCtrl.text) ?? d.amount);
      final newProbable  = d.isGoods ? (double.tryParse(_estimatedAmountCtrl.text) ?? 0.0) : d.probableAmount;
      final newCatId     = _selectedCategory?.name ?? d.categoryId;
      final newGmwfSubId = _selectedGmwfSub?.name;
      final newSubtypeId = _selectedSubtype?.name;
      final newPayment   = _paymentMethod;
      final newNotes     = _notesCtrl.text.trim();
      final newGoodsItem = _goodsCtrl.text.trim();
      final newDate      = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : d.date;
      final newBookRcpt  = _bookReceiptNoCtrl.text.trim();
      final updatedHistory = [...(d.editHistory ?? []), editEntry];
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      final updatedFields = <String, dynamic>{
        'amount':           newAmount,
        if (d.isGoods) 'probableAmount': newProbable,
        'donorName':        newDonorName,
        'isAnonymous':      newIsAnonymous,
        'phone':            newPhone,
        'categoryId':       newCatId,
        'gmwfSubCategoryId': newGmwfSubId,
        'subtypeId':        newSubtypeId,
        'paymentMethod':    newPayment,
        'notes':            newNotes,
        'date':             newDate,
        'bookReceiptNo':    newBookRcpt.isNotEmpty ? newBookRcpt : null,
        if (d.isGoods) 'goodsItem': newGoodsItem,
        'editedAt':         now,
        'editedBy':         widget.currentUsername,
        'editReason':       _reasonCtrl.text.trim(),
        'isEdited':         true,
        'editHistory':      updatedHistory,
        'lastUpdatedAt':    nowUtc,
      };

      // If donor is not anonymous/guest, update the donor registry name and phone
      final donorId = d.donorId;
      if (donorId.isNotEmpty && donorId != 'anonymous' && !donorId.startsWith('guest_')) {
        final active = DonationsLocalStorage.getDonorById(donorId);
        if (active != null) {
          var updatedDonor = active;
          bool changed = false;
          if (active.name != newDonorName) {
            updatedDonor = updatedDonor.copyWith(name: newDonorName);
            changed = true;
          }
          if (newPhone.isNotEmpty && !active.phones.contains(newPhone)) {
            updatedDonor = updatedDonor.copyWith(phones: [...active.phones, newPhone]);
            changed = true;
          }
          if (changed) {
            await DonationsLocalStorage.saveDonor(updatedDonor);
          }
        }
      }

      // ── Firestore update ────────────────────────────────────────────────
      if (d.firestoreId != null && d.firestoreId!.isNotEmpty) {
        final docRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(d.branchId)
            .collection('donations')
            .doc(d.firestoreId);

        // Build the complete updated map from the donation record and edited fields
        final fullMap = {
          ...d.toMap(),
          ...updatedFields,
        }
          ..remove('id')
          ..remove('hiveKey')
          ..remove('syncStatus')
          ..remove('firestoreId')
          ..remove('editHistory');

        await docRef.set({
          ...fullMap,
          'editHistory': FieldValue.arrayUnion([editEntry]),
        }, SetOptions(merge: true));
      }

      // ── Local Hive update ───────────────────────────────────────────────
      await DonationsLocalStorage.updateDonationField(
        d.hiveKey,
        updatedFields,
        branchId: d.branchId,
      );

      if (mounted) {
        Navigator.pop(context, true); // true = refresh needed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Donation updated successfully'),
            ]),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _errorMessage = 'Failed to save: $e';
      });
    }
  }

  List<Map<String, dynamic>> _buildChangeList(DonationRecord d) {
    final changes = <Map<String, dynamic>>[];

    final newDonorName = _donorNameCtrl.text.trim();
    if (newDonorName != d.donorName) {
      changes.add({'field': 'donorName', 'label': 'Donor Name', 'old': d.donorName, 'new': newDonorName});
    }

    final newPhone = _phoneCtrl.text.trim();
    if (newPhone != d.phone) {
      changes.add({'field': 'phone', 'label': 'Phone', 'old': d.phone, 'new': newPhone});
    }

    final newAmt = double.tryParse(_amountCtrl.text) ?? d.amount;
    if (!d.isGoods && newAmt != d.amount) {
      changes.add({'field': 'amount', 'label': 'Amount', 'old': d.amount, 'new': newAmt});
    }
    final newProbable = double.tryParse(_estimatedAmountCtrl.text) ?? 0.0;
    if (d.isGoods && newProbable != (d.probableAmount ?? 0.0)) {
      changes.add({'field': 'probableAmount', 'label': 'Est. Value', 'old': d.probableAmount ?? 0.0, 'new': newProbable});
    }
    final newCat = _selectedCategory?.name ?? d.categoryId;
    if (newCat != d.categoryId) {
      changes.add({'field': 'categoryId', 'label': 'Category', 'old': d.categoryId, 'new': newCat});
    }
    final newSub = _selectedGmwfSub?.name;
    if (newSub != d.gmwfSubCategoryId) {
      changes.add({'field': 'gmwfSubCategoryId', 'label': 'Programme', 'old': d.gmwfSubCategoryId ?? '', 'new': newSub ?? ''});
    }
    final newType = _selectedSubtype?.name;
    if (newType != d.subtypeId) {
      changes.add({'field': 'subtypeId', 'label': 'Purpose', 'old': d.subtypeId ?? '', 'new': newType ?? ''});
    }
    if (_paymentMethod != d.paymentMethod && !d.isGoods) {
      changes.add({'field': 'paymentMethod', 'label': 'Payment', 'old': d.paymentMethod, 'new': _paymentMethod});
    }
    final newDateStr = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : d.date;
    if (newDateStr != d.date) {
      changes.add({'field': 'date', 'label': 'Date', 'old': d.date, 'new': newDateStr});
    }
    final newBook = _bookReceiptNoCtrl.text.trim();
    if (newBook != (d.bookReceiptNo ?? '')) {
      changes.add({'field': 'bookReceiptNo', 'label': 'Book Receipt #', 'old': d.bookReceiptNo ?? '', 'new': newBook});
    }
    if (_notesCtrl.text.trim() != d.notes) {
      changes.add({'field': 'notes', 'label': 'Notes', 'old': d.notes, 'new': _notesCtrl.text.trim()});
    }
    if (d.isGoods && _goodsCtrl.text.trim() != (d.goodsItem ?? '')) {
      changes.add({'field': 'goodsItem', 'label': 'Goods', 'old': d.goodsItem ?? '', 'new': _goodsCtrl.text.trim()});
    }
    return changes;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.donation;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 680),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24)],
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade800, Colors.amber.shade600],
                ),
              ),
              child: Row(children: [
                const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Edit Donation',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text(
                      'Receipt: ${cleanReceiptNumber(d.receiptNo)}  •  ${d.donorName}  •  ${d.branchName.isNotEmpty ? d.branchName : d.branchId}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),

            // ── Scrollable body ──────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!,
                                style: TextStyle(color: Colors.red.shade800, fontSize: 12))),
                          ]),
                        ),
                      ],

                      // Reason (required — most prominent)
                      _sectionLabel('Reason for Edit *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _reasonCtrl,
                        maxLines: 2,
                        decoration: _inputDecoration(
                          hint: 'e.g. Amount was entered incorrectly, wrong category selected…',
                          icon: Icons.report_problem_rounded,
                          iconColor: Colors.orange.shade700,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
                      ),

                      const SizedBox(height: 16),
                      // Donor Name (required)
                      _sectionLabel('Donor Name *'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _donorNameCtrl,
                        decoration: _inputDecoration(
                          hint: 'Donor Name',
                          icon: Icons.person_rounded,
                          iconColor: AppColors.primary,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Donor Name is required' : null,
                      ),

                      const SizedBox(height: 16),
                      // Donor Phone (optional)
                      _sectionLabel('Donor Phone'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                        decoration: _inputDecoration(
                          hint: 'Donor Phone (e.g. 03001234567)',
                          icon: Icons.phone_rounded,
                          iconColor: AppColors.primary,
                        ),
                      ),

                      const SizedBox(height: 20),
                      const Divider(color: AppColors.gray100),
                      const SizedBox(height: 16),

                      // Amount (cash only)
                      if (!d.isGoods) ...[
                        _sectionLabel('Amount (PKR)'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'DMMono',
                              color: AppColors.primary),
                          decoration: _inputDecoration(
                              hint: '0.00',
                              icon: Icons.payments_rounded,
                              iconColor: AppColors.primary),
                          validator: (v) =>
                              (v == null || v.isEmpty || (double.tryParse(v) ?? 0) <= 0)
                                  ? 'Enter valid amount'
                                  : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Goods item
                      if (d.isGoods) ...[
                        _sectionLabel('Goods Description'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _goodsCtrl,
                          decoration: _inputDecoration(
                              hint: 'e.g. 50kg Flour, 2 Fans',
                              icon: Icons.inventory_2_rounded,
                              iconColor: Colors.blue.shade700),
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Estimated Amount (PKR)'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _estimatedAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                          ],
                          decoration: _inputDecoration(
                              hint: '0.00',
                              icon: Icons.payments_rounded,
                              iconColor: Colors.green.shade700),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Category
                      _sectionLabel('Category'),
                      const SizedBox(height: 8),
                      Row(
                        children: DonationCategory.values
                            .where((c) => c != DonationCategory.all)
                            .map((cat) {
                          final sel = _selectedCategory == cat;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _selectedCategory = cat;
                                _selectedGmwfSub  = null;
                                _selectedSubtype  = null;
                              }),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel ? cat.lightColor : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: sel ? cat.color : AppColors.gray200,
                                      width: sel ? 2 : 1),
                                ),
                                child: Column(children: [
                                  Icon(cat.icon,
                                      color: sel ? cat.color : AppColors.gray400, size: 20),
                                  const SizedBox(height: 4),
                                  Text(cat.label,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: sel ? cat.color : AppColors.gray600)),
                                ]),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      // GMWF sub-category
                      if (_selectedCategory == DonationCategory.gmwf) ...[
                        const SizedBox(height: 14),
                        _sectionLabel('GMWF Programme'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: GmwfSubCategory.values.map((sub) {
                            final sel = _selectedGmwfSub == sub;
                            return ChoiceChip(
                              label: Text(sub.label),
                              selected: sel,
                              onSelected: (v) => setState(() {
                                _selectedGmwfSub = v ? sub : null;
                                _selectedSubtype = null;
                              }),
                              selectedColor: sub.lightColor,
                              labelStyle: TextStyle(
                                  color: sel ? sub.color : AppColors.gray600,
                                  fontWeight: sel ? FontWeight.w700 : null,
                                  fontSize: 12),
                            );
                          }).toList(),
                        ),
                      ],

                      // Subtype
                      if (_selectedCategory != null) ...[
                        const SizedBox(height: 14),
                        _sectionLabel('Purpose / Subtype'),
                        const SizedBox(height: 8),
                        Builder(builder: (_) {
                          final subtypes = subtypesFor(
                            category: _selectedCategory!,
                            entryType: d.isGoods
                                ? DonationEntryType.goods
                                : DonationEntryType.cash,
                            gmwfSub: _selectedGmwfSub,
                          );
                          if (subtypes.isEmpty) {
                            return const Text('No subtypes for this selection.',
                                style: TextStyle(fontSize: 12, color: AppColors.gray400));
                          }
                          return Wrap(
                            spacing: 8, runSpacing: 8,
                            children: subtypes.map((st) {
                              final sel = _selectedSubtype == st;
                              return ChoiceChip(
                                label: Text(st.label),
                                selected: sel,
                                onSelected: (v) =>
                                    setState(() => _selectedSubtype = v ? st : null),
                                selectedColor: st.color.withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                    color: sel ? st.color : AppColors.gray600,
                                    fontWeight: sel ? FontWeight.w700 : null,
                                    fontSize: 12),
                              );
                            }).toList(),
                          );
                        }),
                      ],

                      // Payment method (cash only)
                      if (!d.isGoods) ...[
                        const SizedBox(height: 16),
                        _sectionLabel('Payment Method'),
                        const SizedBox(height: 8),
                        Row(
                          children: ['Cash', 'Cheque', 'Bank Transfer'].map((m) =>
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _paymentMethod = m),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _paymentMethod == m
                                        ? AppColors.primary
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: _paymentMethod == m
                                            ? AppColors.primary
                                            : AppColors.gray200),
                                  ),
                                  child: Center(
                                    child: Text(m,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _paymentMethod == m
                                                ? Colors.white
                                                : AppColors.gray600)),
                                  ),
                                ),
                              ),
                            )).toList(),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionLabel('Donation Date'),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _selectedDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (picked != null) {
                                      setState(() => _selectedDate = picked);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: AppColors.gray50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.gray200),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.gray500),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat('dd MMM yyyy').format(_selectedDate ?? DateTime.now()),
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionLabel('Book Receipt # (Manual)'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _bookReceiptNoCtrl,
                                  decoration: _inputDecoration(
                                    hint: 'e.g. B-12345',
                                    icon: Icons.confirmation_number_outlined,
                                    iconColor: AppColors.gray500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Notes
                      const SizedBox(height: 16),
                      _sectionLabel('Notes (Optional)'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: _inputDecoration(
                            hint: 'Any notes or clarification…',
                            icon: Icons.notes_rounded,
                            iconColor: AppColors.gray500),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom actions ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.gray100))),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.gray700),
      );

  InputDecoration _inputDecoration(
      {required String hint, required IconData icon, Color? iconColor}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.gray400, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: iconColor ?? AppColors.gray500),
      filled: true,
      fillColor: AppColors.gray50,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray200)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDITED BADGE — shown on TransactionCard when donation.isEdited == true
// ─────────────────────────────────────────────────────────────────────────────

class EditedBadge extends StatelessWidget {
  const EditedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.edit_rounded, size: 8, color: Colors.orange.shade700),
        const SizedBox(width: 3),
        Text(
          'EDITED',
          style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: Colors.orange.shade800,
              letterSpacing: 0.5),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT HISTORY VIEWER — shown inside the details dialog
// ─────────────────────────────────────────────────────────────────────────────

class EditHistoryViewer extends StatelessWidget {
  final DonationRecord donation;
  const EditHistoryViewer({super.key, required this.donation});

  @override
  Widget build(BuildContext context) {
    final history = donation.editHistory ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Container(
          margin: const EdgeInsets.only(top: 16, bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(Icons.history_rounded, color: Colors.orange.shade700, size: 16),
            const SizedBox(width: 8),
            Text(
              'Edit History (${history.length} edit${history.length > 1 ? 's' : ''})',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.orange.shade800),
            ),
          ]),
        ),

        ...history.asMap().entries.map((e) {
          final idx     = e.key;
          final hist    = e.value;
          final changes = (hist['changes'] as List?)
                  ?.whereType<Map>()
                  .map((c) => Map<String, dynamic>.from(c))
                  .toList() ??
              [];
          final reason   = hist['reason']    as String? ?? 'No reason provided';
          final editedBy = hist['editedBy']  as String? ?? 'Unknown';
          final editedAt = hist['editedAt']  as String? ?? '';

          String fmtDate(String? raw) {
            try {
              return DateFormat('dd MMM yyyy, hh:mm a')
                  .format(DateTime.parse(raw ?? ''));
            } catch (_) {
              return raw ?? '';
            }
          }

          String fmtVal(dynamic v) {
            if (v is double || v is int) {
              return 'PKR ${NumberFormat('#,##0').format(v)}';
            }
            return v?.toString() ?? '';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade100),
              boxShadow: [
                BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.05), blurRadius: 8)
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Edit header row
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('Edit ${idx + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(fmtDate(editedAt),
                          style:
                              TextStyle(fontSize: 11, color: Colors.orange.shade700))),
                  Text('by $editedBy',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800)),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Reason
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.gray50,
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Icon(Icons.chat_bubble_outline_rounded,
                          size: 13, color: AppColors.gray500),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(reason,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.gray700,
                                  fontStyle: FontStyle.italic))),
                    ]),
                  ),

                  if (changes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Changes made:',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gray600)),
                    const SizedBox(height: 6),
                    ...changes.map((ch) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        SizedBox(
                          width: 70,
                          child: Text(
                            (ch['label'] as String? ?? '').toUpperCase(),
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gray400),
                          ),
                        ),
                        Expanded(
                          child: Wrap(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border:
                                      Border.all(color: Colors.red.shade100)),
                              child: Text(fmtVal(ch['old']),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.red.shade700,
                                      decoration: TextDecoration.lineThrough)),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.arrow_forward_rounded,
                                  size: 12, color: AppColors.gray400),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border:
                                      Border.all(color: Colors.green.shade100)),
                              child: Text(fmtVal(ch['new']),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        ),
                      ]),
                    )),
                  ],
                ]),
              ),
            ]),
          );
        }),
      ],
    );
  }
}