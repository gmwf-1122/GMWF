import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../constants/colors.dart';
import '../../../models/donation_models.dart';
import '../../../services/donations_local_storage.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/role_theme_provider.dart';
import '../donations_shared.dart';

class AddDonationWizard extends StatefulWidget {
  final String branchId;
  final String branchName;
  final String currentUsername;
  final String userId;
  final UserRole currentUserRole;

  const AddDonationWizard({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.currentUsername,
    required this.userId,
    required this.currentUserRole,
  });

  @override
  State<AddDonationWizard> createState() => _AddDonationWizardState();
}

class _AddDonationWizardState extends State<AddDonationWizard> {
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentStep = 0;
  final int _totalSteps = 4;

  final _formKeyIdentity = GlobalKey<FormState>();
  final _formKeyDetails  = GlobalKey<FormState>();

  // Step 1: Identity
  final _phoneCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _donorIdCtrl = TextEditingController();
  DonorRecord? _selectedDonor;
  List<DonorRecord> _searchResults = [];
  bool _isAnonymous = false;

  // Step 2: Category
  DonationCategory _category = DonationCategory.gmwf;
  GmwfSubCategory? _gmwfSub = GmwfSubCategory.general;
  DonationSubtype? _subtype;

  // Step 3: Contribution
  final _amountCtrl = TextEditingController();
  final _goodsItemCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _probableAmountCtrl = TextEditingController();
  String _entryType = 'cash'; // 'cash' or 'goods'
  String _paymentMethod = 'Cash';
  final _notesCtrl = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _donorIdCtrl.dispose();
    _amountCtrl.dispose();
    _goodsItemCtrl.dispose();
    _unitCtrl.dispose();
    _probableAmountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onPhoneChanged(String val) {
    if (val.length >= 7) {
      final donor = DonationsLocalStorage.findDonorByPhone(val);
      if (donor != null) {
        setState(() {
          _selectedDonor = donor;
          _nameCtrl.text = donor.name;
          _donorIdCtrl.text = donor.id;
          _searchResults = [];
        });
      }
    }
  }

  void _onNameChanged(String val) {
    if (_selectedDonor != null && val != _selectedDonor!.name) {
      setState(() {
        _selectedDonor = null;
        _donorIdCtrl.clear();
      });
    }

    if (val.length >= 3) {
      final results = DonationsLocalStorage.findDonorsByName(val);
      setState(() {
        _searchResults = results.where((d) => d.id != _donorIdCtrl.text).toList();
      });
    } else {
      setState(() {
        _searchResults = [];
      });
    }
  }

  void _selectDonor(DonorRecord donor) {
    setState(() {
      _selectedDonor = donor;
      _nameCtrl.text = donor.name;
      _phoneCtrl.text = donor.phones.isNotEmpty ? donor.phones.first : '';
      _donorIdCtrl.text = donor.id;
      _searchResults = [];
    });
  }

  void _nextStep() {
    setState(() => _error = null);

    if (_currentStep == 0) {
      if (!_isAnonymous) {
        if (_nameCtrl.text.trim().isEmpty) {
          _setError('Donor name is required for registered entries');
          return;
        }
        if (!(_formKeyIdentity.currentState?.validate() ?? false)) return;
      }
    }
    if (_currentStep == 1) {
      if (_category == DonationCategory.gmwf && _gmwfSub == null) {
        _setError('Please select a department (e.g. Madrisa, School)');
        return;
      }
      if (_subtype == null) {
        _setError('Please select a purpose/sub-type (e.g. Zakat, General)');
        return;
      }
    }
    if (_currentStep == 2) {
      if (!(_formKeyDetails.currentState?.validate() ?? false)) {
        _setError('Please fill in all required contribution details');
        return;
      }
    }

    if (_currentStep < _totalSteps - 1) {
      setState(() { _currentStep++; });
      _scrollController.jumpTo(0);
      _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    } else {
      _submit();
    }
  }

  void _setError(String msg) {
    setState(() => _error = msg);
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() { _currentStep--; _error = null; });
      _scrollController.jumpTo(0);
      _pageController.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
    }
  }

  Future<void> _submit() async {
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
        'recordedByRole': widget.currentUserRole.name,
        // If HQ Manager or Chairman is adding, it defaults to received.
        // Otherwise (Manager, OB, Staff) it defaults to pending.
        'status': widget.currentUserRole.canMarkReceived ? DonationStatus.received : DonationStatus.pending,
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
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: 600,
        height: 700,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            children: [
              _buildHeader(t),
              _buildProgressBar(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _stepIdentity(),
                    _stepCategory(),
                    _stepContribution(),
                    _stepConfirmation(),
                  ],
                ),
              ),
              _buildFooter(t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.volunteer_activism_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New Donation Entry', 
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.gray900, letterSpacing: -0.5)),
                    Text(widget.branchName, 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray400)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppColors.gray400),
                style: IconButton.styleFrom(backgroundColor: AppColors.gray100),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildStepProgress(),
        ],
      ),
    );
  }

  Widget _buildStepProgress() {
    final steps = [
      {'label': 'Identity', 'icon': Icons.person_outline_rounded},
      {'label': 'Allocation', 'icon': Icons.category_outlined},
      {'label': 'Details', 'icon': Icons.receipt_long_rounded},
      {'label': 'Confirm', 'icon': Icons.check_circle_outline_rounded},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(steps.length, (i) {
        final isActive = i == _currentStep;
        final isCompleted = i < _currentStep;
        
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isCompleted ? AppColors.primary : (isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.white),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (isActive || isCompleted) ? AppColors.primary : AppColors.gray200,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isCompleted 
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                        : Text('${i + 1}', style: TextStyle(
                            fontSize: 14, 
                            fontWeight: FontWeight.w900, 
                            color: isActive ? AppColors.primary : AppColors.gray400
                          )),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(steps[i]['label'] as String, style: TextStyle(
                    fontSize: 10, 
                    fontWeight: FontWeight.w800, 
                    color: (isActive || isCompleted) ? AppColors.gray900 : AppColors.gray400,
                    letterSpacing: 0.5
                  )),
                ],
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20, left: 8, right: 8),
                    color: isCompleted ? AppColors.primary : AppColors.gray100,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return 'Donor Identity';
      case 1: return 'Allocation';
      case 2: return 'Contribution Details';
      case 3: return 'Confirmation';
      default: return '';
    }
  }

  Widget _buildProgressBar() => const SizedBox.shrink(); // Replaced by _buildStepProgress

  Widget _buildFooter(RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.gray50.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: AppColors.gray100)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _saving ? null : _prevStep,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                side: const BorderSide(color: AppColors.gray300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Back', style: TextStyle(color: AppColors.gray700, fontWeight: FontWeight.w700)),
            ),
          const Spacer(),
          ElevatedButton(
            onPressed: _saving ? null : _nextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_currentStep == _totalSteps - 1 ? 'Finish & Save' : 'Continue', 
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  // ── STEP 1: IDENTITY ───────────────────────────────────────────────────────

  Widget _stepIdentity() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKeyIdentity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'WHO IS DONATING?'),
            if (_error != null) _buildErrorBanner(),
            const SizedBox(height: 24),
            
            _buildSelectionCard(
              title: 'Anonymous Donor',
              subtitle: 'Do not record any personal identification',
              icon: Icons.no_accounts_rounded,
              isSelected: _isAnonymous,
              onTap: () => setState(() => _isAnonymous = true),
            ),
            const SizedBox(height: 12),
            _buildSelectionCard(
              title: 'Registered / Identified',
              subtitle: 'Record name and contact details',
              icon: Icons.person_search_rounded,
              isSelected: !_isAnonymous,
              onTap: () => setState(() => _isAnonymous = false),
            ),

            if (!_isAnonymous) ...[
              const SizedBox(height: 32),
              const Text('Search or Add New Donor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gray700)),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Phone Number (Optional)',
                controller: _phoneCtrl,
                icon: Icons.phone_android_rounded,
                hint: '03xx-xxxxxxx',
                onChanged: _onPhoneChanged,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Full Name',
                controller: _nameCtrl,
                icon: Icons.person_outline_rounded,
                hint: 'Enter donor name',
                required: true,
                onChanged: _onNameChanged,
              ),
              if (_searchResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.gray200),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _searchResults.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final d = _searchResults[i];
                      return ListTile(
                        onTap: () => _selectDonor(d),
                        leading: const Icon(Icons.person_rounded, size: 20, color: AppColors.gray400),
                        title: Text(d.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        subtitle: Text(d.phones.isNotEmpty ? d.phones.first : 'No phone', style: const TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.gray300),
                      );
                    },
                  ),
                ),
              if (_selectedDonor != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade100)),
                  child: Row(children: [
                    const Icon(Icons.verified_user_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Selected: ${_selectedDonor!.name} (${_selectedDonor!.id})', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13))),
                  ]),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ── STEP 2: CATEGORY ───────────────────────────────────────────────────────

  Widget _stepCategory() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'WHERE SHOULD THIS GO?'),
          if (_error != null) _buildErrorBanner(),
          const SizedBox(height: 24),
          
          Row(
            children: [
              Expanded(child: _categoryCard(DonationCategory.gmwf)),
              const SizedBox(width: 16),
              Expanded(child: _categoryCard(DonationCategory.jamia)),
            ],
          ),

          if (_category == DonationCategory.gmwf) ...[
            const SizedBox(height: 32),
            const Text('Department', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gray700)),
            const SizedBox(height: 12),
            _buildGmwfSubGrid(),
          ],

          const SizedBox(height: 32),
          const Text('Specific Purpose', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gray700)),
          const SizedBox(height: 12),
          _buildSubtypeGrid(),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _error = null),
            icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.red),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── STEP 3: CONTRIBUTION ───────────────────────────────────────────────────

  Widget _stepContribution() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKeyDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'WHAT IS BEING DONATED?'),
            if (_error != null) _buildErrorBanner(),
            const SizedBox(height: 24),
            
            Row(
              children: [
                _entryTypeButton('cash', 'Cash (PKR)', Icons.payments_rounded),
                const SizedBox(width: 12),
                _entryTypeButton('goods', 'Goods / Ajnas', Icons.inventory_2_rounded),
              ],
            ),

            const SizedBox(height: 32),
            if (_entryType == 'cash') ...[
              _buildTextField(
                label: 'Amount (PKR)',
                controller: _amountCtrl,
                icon: Icons.account_balance_wallet_rounded,
                hint: '0.00',
                keyboardType: TextInputType.number,
                required: true,
              ),
              const SizedBox(height: 24),
              const Text('Payment Method', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gray700)),
              const SizedBox(height: 12),
              _buildPaymentMethodSelector(),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      label: 'Item Name',
                      controller: _goodsItemCtrl,
                      icon: Icons.shopping_bag_outlined,
                      hint: 'e.g. Flour Bag',
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
              const SizedBox(height: 20),
              _buildTextField(
                label: 'Estimated Value (Optional)',
                controller: _probableAmountCtrl,
                icon: Icons.calculate_outlined,
                hint: '0.00',
                keyboardType: TextInputType.number,
              ),
            ],

            const SizedBox(height: 32),
            _buildTextField(
              label: 'Additional Notes',
              controller: _notesCtrl,
              icon: Icons.notes_rounded,
              hint: 'Any specific instructions...',
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  // ── STEP 4: CONFIRMATION ────────────────────────────────────────────────────

  Widget _stepConfirmation() {
    final amt = double.tryParse(_amountCtrl.text) ?? 0;
    final prob = double.tryParse(_probableAmountCtrl.text) ?? 0;
    
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: 'REVIEW DETAILS'),
          if (_error != null) _buildErrorBanner(),
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gray200),
            ),
            child: Column(
              children: [
                _confirmRow('Donor', _isAnonymous ? 'Anonymous' : _nameCtrl.text),
                if (!_isAnonymous && _phoneCtrl.text.isNotEmpty) _confirmRow('Contact', _phoneCtrl.text),
                _confirmRow('Branch', widget.branchName),
                const Divider(height: 32),
                _confirmRow('Category', _category.label),
                if (_gmwfSub != null) _confirmRow('Dept', _gmwfSub!.label),
                _confirmRow('Purpose', _subtype?.label ?? 'General'),
                const Divider(height: 32),
                if (_entryType == 'cash')
                  _confirmRow('Amount', 'PKR ${NumberFormat('#,##0').format(amt)}', isBold: true, color: AppColors.primary)
                else ...[
                  _confirmRow('Goods', _goodsItemCtrl.text),
                  if (prob > 0) _confirmRow('Est. Value', 'PKR ${NumberFormat('#,##0').format(prob)}'),
                ],
                _confirmRow('Method', _paymentMethod),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── HELPER WIDGETS ─────────────────────────────────────────────────────────

  Widget _confirmRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.gray500, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(
            fontSize: 14, 
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700, 
            color: color ?? AppColors.gray900
          )),
        ],
      ),
    );
  }

  Widget _buildSelectionCard({required String title, required String subtitle, required IconData icon, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.gray200, width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.gray100, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: isSelected ? AppColors.primary : AppColors.gray400),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: isSelected ? AppColors.primary : AppColors.gray900)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.gray500, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _categoryCard(DonationCategory cat) {
    final sel = _category == cat;
    return GestureDetector(
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
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: sel ? cat.color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? cat.color : AppColors.gray200, width: 2),
        ),
        child: Column(
          children: [
            Icon(cat.icon, color: sel ? cat.color : AppColors.gray400, size: 32),
            const SizedBox(height: 12),
            Text(cat.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: sel ? cat.color : AppColors.gray700)),
          ],
        ),
      ),
    );
  }

  Widget _entryTypeButton(String type, String label, IconData icon) {
    final sel = _entryType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _entryType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? AppColors.primary : AppColors.gray200, width: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: sel ? AppColors.primary : AppColors.gray400),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: sel ? AppColors.primary : AppColors.gray600)),
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
        return ChoiceChip(
          label: Text(s.label),
          selected: sel,
          onSelected: (v) => setState(() { _gmwfSub = s; _subtype = null; }),
          selectedColor: s.color,
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sel ? Colors.white : AppColors.gray600),
          backgroundColor: AppColors.gray100,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          showCheckmark: false,
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
        return ChoiceChip(
          label: Text(s.label),
          selected: sel,
          onSelected: (v) => setState(() => _subtype = s),
          selectedColor: s.color,
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sel ? Colors.white : AppColors.gray600),
          backgroundColor: AppColors.gray100,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          showCheckmark: false,
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
              labelStyle: TextStyle(color: sel ? Colors.white : AppColors.gray700, fontSize: 12, fontWeight: FontWeight.w800),
              backgroundColor: AppColors.gray100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              showCheckmark: false,
            ),
          ),
        );
      }).toList(),
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
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gray700)),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          onChanged: onChanged,
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.gray300, fontSize: 14),
            prefixIcon: icon != null ? Icon(icon, size: 20, color: AppColors.gray400) : null,
            filled: true,
            fillColor: AppColors.gray50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.gray400, letterSpacing: 1.5));
}
