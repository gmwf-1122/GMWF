import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../../constants/colors.dart';
import '../../../services/donations_local_storage.dart';
import '../../../theme/role_theme_provider.dart';
import '../donations_shared.dart';

class AddDonationDialog extends StatefulWidget {
  final String branchId;
  final String branchName;
  final String currentUsername;
  final String userId;
  final UserRole currentUserRole;

  const AddDonationDialog({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.currentUsername,
    required this.userId,
    required this.currentUserRole,
  });

  @override
  State<AddDonationDialog> createState() => _AddDonationDialogState();
}

class _AddDonationDialogState extends State<AddDonationDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // Donor Fields
  final _phoneCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _donorIdCtrl = TextEditingController();
  DonorRecord? _selectedDonor;
  bool _isNewDonor = false;
  bool _isAnonymous = false;

  // Donation Fields
  final _amountCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();
  final _goodsItemCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _probableAmountCtrl = TextEditingController();

  DonationCategory _category = DonationCategory.gmwf;
  GmwfSubCategory? _gmwfSub = GmwfSubCategory.general;
  DonationSubtype? _subtype;
  String _paymentMethod = 'Cash';
  String _entryType = 'cash'; // 'cash' or 'goods'

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _donorIdCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _goodsItemCtrl.dispose();
    _unitCtrl.dispose();
    _probableAmountCtrl.dispose();
    super.dispose();
  }

  void _onPhoneChanged(String val) {
    if (val.length >= 10) {
      final donor = DonationsLocalStorage.findDonorByPhone(val);
      if (donor != null) {
        setState(() {
          _selectedDonor = donor;
          _nameCtrl.text = donor.name;
          _donorIdCtrl.text = donor.id;
          _isNewDonor = false;
        });
      } else {
        if (_selectedDonor != null) {
          setState(() {
            _selectedDonor = null;
            _nameCtrl.clear();
            _donorIdCtrl.clear();
            _isNewDonor = true;
          });
        }
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isAnonymous && _nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Donor name is required.');
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final data = {
        'donorName': _isAnonymous ? 'Anonymous' : _nameCtrl.text.trim(),
        'phone': _isAnonymous ? '' : _phoneCtrl.text.trim(),
        'donorId': _isAnonymous ? '' : _donorIdCtrl.text.trim(),
        'isAnonymous': _isAnonymous,
        'amount': double.tryParse(_amountCtrl.text) ?? 0.0,
        'probableAmount': double.tryParse(_probableAmountCtrl.text),
        'categoryId': _category.name,
        'gmwfSubCategoryId': _gmwfSub?.name,
        'subtypeId': _subtype?.name,
        'entryType': _entryType,
        'goodsItem': _goodsItemCtrl.text.trim(),
        'unit': _unitCtrl.text.trim(),
        'paymentMethod': _paymentMethod,
        'notes': _notesCtrl.text.trim(),
        'recordedBy': widget.currentUsername,
        'collectorId': widget.userId,
        'status': kStatusPending, // Branch adds as pending by default
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'timestamp': DateTime.now().toIso8601String(),
        'branchName': widget.branchName,
      };

      final record = await DonationsLocalStorage.saveDonation(
        branchId: widget.branchId,
        data: data,
      );

      if (mounted) Navigator.pop(context, record);
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Text('New Donation Record', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.gray900)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                          ]),
                        ),

                      // ── Donor Information ──
                      const Text('DONOR DETAILS', 
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.gray400, letterSpacing: 1)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Checkbox(
                            value: _isAnonymous, 
                            onChanged: (v) => setState(() => _isAnonymous = v ?? false),
                            activeColor: AppColors.primary,
                          ),
                          const Text('Anonymous Donation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      
                      if (!_isAnonymous) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildTextField(
                                label: 'Phone Number',
                                controller: _phoneCtrl,
                                icon: Icons.phone_android_rounded,
                                hint: '03xx-xxxxxxx',
                                onChanged: _onPhoneChanged,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: _buildTextField(
                                label: 'Donor Name',
                                controller: _nameCtrl,
                                icon: Icons.person_outline_rounded,
                                hint: 'Enter name',
                                required: true,
                              ),
                            ),
                          ],
                        ),
                        if (_selectedDonor != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Row(children: [
                              const Icon(Icons.verified_rounded, color: Colors.green, size: 14),
                              const SizedBox(width: 6),
                              Text('Found existing donor: ${_selectedDonor!.id}', 
                                style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                      ],

                      const SizedBox(height: 32),
                      
                      // ── Donation Type ──
                      const Text('DONATION CATEGORY', 
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.gray400, letterSpacing: 1)),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          _typeChip(DonationCategory.gmwf),
                          const SizedBox(width: 10),
                          _typeChip(DonationCategory.jamia),
                        ],
                      ),

                      if (_category == DonationCategory.gmwf) ...[
                        const SizedBox(height: 20),
                        const Text('Department / Sub-Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _buildGmwfSubGrid(),
                      ],

                      const SizedBox(height: 20),
                      const Text('Purpose / Sub-Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _buildSubtypeGrid(),

                      const SizedBox(height: 32),
                      
                      // ── Amount & Mode ──
                      const Text('AMOUNT & PAYMENT', 
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.gray400, letterSpacing: 1)),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          _entryTypeChip('cash', 'Cash (PKR)', Icons.payments_rounded),
                          const SizedBox(width: 10),
                          _entryTypeChip('goods', 'Goods / Ajnas', Icons.inventory_2_rounded),
                        ],
                      ),

                      const SizedBox(height: 20),
                      if (_entryType == 'cash')
                        _buildTextField(
                          label: 'Amount (PKR)',
                          controller: _amountCtrl,
                          icon: Icons.account_balance_wallet_rounded,
                          hint: '0.00',
                          keyboardType: TextInputType.number,
                          required: true,
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildTextField(
                                label: 'Item Name',
                                controller: _goodsItemCtrl,
                                icon: Icons.shopping_bag_outlined,
                                hint: 'e.g. Flour',
                                required: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTextField(
                                label: 'Unit',
                                controller: _unitCtrl,
                                hint: 'kg/pc',
                              ),
                            ),
                          ],
                        ),
                      
                      if (_entryType == 'goods') ...[
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: 'Estimated Value (Optional)',
                          controller: _probableAmountCtrl,
                          icon: Icons.calculate_outlined,
                          hint: '0.00',
                          keyboardType: TextInputType.number,
                        ),
                      ],

                      const SizedBox(height: 20),
                      const Text('Payment Method', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _buildPaymentMethodSelector(),

                      const SizedBox(height: 20),
                      _buildTextField(
                        label: 'Notes',
                        controller: _notesCtrl,
                        icon: Icons.notes_rounded,
                        hint: 'Any additional details...',
                        maxLines: 2,
                      ),
                      
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.gray200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: AppColors.gray300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.gray600, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('Save Record', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    String? hint,
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gray700)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          onChanged: onChanged,
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, size: 18, color: AppColors.gray400) : null,
            filled: true,
            fillColor: AppColors.gray50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _typeChip(DonationCategory cat) {
    final sel = _category == cat;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _category = cat;
          _subtype = null;
          if (cat == DonationCategory.jamia) {
            _gmwfSub = null;
          } else {
            _gmwfSub ??= GmwfSubCategory.general;
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sel ? cat.color.withValues(alpha: 0.1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? cat.color : AppColors.gray200, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(cat.icon, color: sel ? cat.color : AppColors.gray400, size: 24),
              const SizedBox(height: 6),
              Text(cat.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sel ? cat.color : AppColors.gray600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryTypeChip(String type, String label, IconData icon) {
    final sel = _entryType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _entryType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? AppColors.primary : AppColors.gray200, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: sel ? AppColors.primary : AppColors.gray400),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: sel ? AppColors.primary : AppColors.gray600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGmwfSubGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: GmwfSubCategory.values.map((s) {
        final sel = _gmwfSub == s;
        return FilterChip(
          label: Text(s.label),
          selected: sel,
          onSelected: (v) => setState(() {
            _gmwfSub = s;
            _subtype = null;
          }),
          selectedColor: s.color.withValues(alpha: 0.2),
          checkmarkColor: s.color,
          labelStyle: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? s.color : AppColors.gray600),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: sel ? s.color : AppColors.gray200)),
        );
      }).toList(),
    );
  }

  Widget _buildSubtypeGrid() {
    final list = subtypesFor(category: _category, entryType: DonationEntryType.cash, gmwfSub: _gmwfSub);
    if (list.isEmpty) return const Text('N/A', style: TextStyle(color: AppColors.gray400, fontSize: 12));
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: list.map((s) {
        final sel = _subtype == s;
        return FilterChip(
          label: Text(s.label),
          selected: sel,
          onSelected: (v) => setState(() => _subtype = s),
          selectedColor: s.color.withValues(alpha: 0.2),
          checkmarkColor: s.color,
          labelStyle: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? s.color : AppColors.gray600),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: sel ? s.color : AppColors.gray200)),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethodSelector() {
    final methods = ['Cash', 'Cheque', 'Bank Deposit'];
    return Row(
      children: methods.map((m) {
        final sel = _paymentMethod == m;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(m),
              selected: sel,
              onSelected: (v) { if (v) setState(() => _paymentMethod = m); },
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(color: sel ? Colors.white : AppColors.gray700, fontSize: 12, fontWeight: FontWeight.w700),
              backgroundColor: AppColors.gray100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide.none),
              showCheckmark: false,
            ),
          ),
        );
      }).toList(),
    );
  }
}
