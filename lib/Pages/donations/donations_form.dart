// lib/pages/donations/donations_form.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/donations_local_storage.dart';
import '../../services/local_storage_service.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import 'donations_shared.dart';
import 'donations_screen.dart';
import 'credit_ledger.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ADD DONATION FORM
// ═════════════════════════════════════════════════════════════════════════════

class AddDonationForm extends StatefulWidget {
  final DonationCategory               category;
  final ValueChanged<DonationCategory> onCatChanged;
  final String today, username, branchId, branchName, userId;
  final UserRole role;
  final dynamic col;
  final Future<String> Function() nextReceiptNumber;

  const AddDonationForm({
    super.key,
    required this.category,
    required this.onCatChanged,
    required this.col,
    required this.today,
    required this.username,
    required this.branchId,
    required this.branchName,
    required this.userId,
    required this.role,
    required this.nextReceiptNumber,
  });

  @override
  State<AddDonationForm> createState() => _AddDonationFormState();
}

class _AddDonationFormState extends State<AddDonationForm> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _amtCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _itemCtrl  = TextEditingController();
  final _qtyCtrl   = TextEditingController();
  final _probCtrl  = TextEditingController();

  // FocusScope node isolates all focus traversal inside the form —
  // Tab / next can never escape into the sidebar.
  final _scopeNode  = FocusScopeNode();
  final _nameFocus  = FocusNode();
  final _phoneFocus = FocusNode();
  final _amtFocus   = FocusNode();
  final _notesFocus = FocusNode();
  final _itemFocus  = FocusNode();
  final _qtyFocus   = FocusNode();
  final _probFocus  = FocusNode();

  DonationEntryType  _entryType     = DonationEntryType.cash;
  GmwfSubCategory    _gmwfSub       = GmwfSubCategory.general;
  late DonationSubtype _selectedSubtype;
  String             _unit          = 'kg';
  PaymentMethod      _paymentMethod = PaymentMethod.cash;
  bool               _saving        = false;
  bool               _isOnline      = true;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _selectedSubtype = _defaultSubtype();
    _checkConnectivity();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((r) {
      if (r.isEmpty || !mounted) return;
      setState(() => _isOnline = r.first != ConnectivityResult.none);
    });
  }

  Future<void> _checkConnectivity() async {
    final r = await Connectivity().checkConnectivity();
    if (r.isNotEmpty && mounted) {
      setState(() => _isOnline = r.first != ConnectivityResult.none);
    }
  }

  @override
  void didUpdateWidget(AddDonationForm old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) {
      setState(() {
        _entryType       = DonationEntryType.cash;
        _gmwfSub         = GmwfSubCategory.general;
        _selectedSubtype = _defaultSubtype();
      });
      _amtCtrl.clear(); _itemCtrl.clear();
      _qtyCtrl.clear(); _probCtrl.clear();
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _amtCtrl, _notesCtrl,
                     _itemCtrl, _qtyCtrl, _probCtrl]) c.dispose();
    for (final f in [_nameFocus, _phoneFocus, _amtFocus, _notesFocus,
                     _itemFocus, _qtyFocus, _probFocus]) f.dispose();
    _scopeNode.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  bool get _isGoods => _entryType.isGoods;

  List<DonationSubtype> get _currentSubtypes => subtypesFor(
    category:  widget.category,
    entryType: _entryType,
    gmwfSub:   widget.category == DonationCategory.gmwf ? _gmwfSub : null,
  );

  DonationSubtype _defaultSubtype() {
    final subs = subtypesFor(
      category:  widget.category,
      entryType: _entryType,
      gmwfSub:   widget.category == DonationCategory.gmwf ? _gmwfSub : null,
    );
    return subs.isNotEmpty ? subs.first : DonationSubtype.general;
  }

  void _onEntryTypeChanged(DonationEntryType et) {
    setState(() { _entryType = et; _selectedSubtype = _defaultSubtype(); });
    _amtCtrl.clear(); _itemCtrl.clear();
    _qtyCtrl.clear(); _probCtrl.clear();
  }

  void _onGmwfSubChanged(GmwfSubCategory sub) {
    setState(() { _gmwfSub = sub; _selectedSubtype = _defaultSubtype(); });
  }

  void _clearForm() {
    for (final c in [_nameCtrl, _phoneCtrl, _amtCtrl, _notesCtrl,
                     _itemCtrl, _qtyCtrl, _probCtrl]) c.clear();
    if (mounted) {
      setState(() {
        _entryType       = DonationEntryType.cash;
        _gmwfSub         = GmwfSubCategory.general;
        _paymentMethod   = PaymentMethod.cash;
        _selectedSubtype = _defaultSubtype();
      });
      _nameFocus.requestFocus();
    }
  }

  Future<String> _getReceiptNumber() async {
    try { return await LocalStorageService.nextReceiptNumber(widget.branchId); }
    catch (_) { return 'TEMP-${DateTime.now().millisecondsSinceEpoch}'; }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isGoods && _itemCtrl.text.trim().isEmpty) {
      _snack('Item name is required', DS.statusRejected); return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final receiptNo = await _getReceiptNumber();
      if (!mounted) return;
      final now       = DateTime.now();
      final dateStr   = DateFormat('yyyy-MM-dd').format(now);
      final timestamp = now.toIso8601String();
      final amount    = double.tryParse(
          (_isGoods ? _qtyCtrl : _amtCtrl).text.trim()) ?? 0.0;

      final data = <String, dynamic>{
        'categoryId':    widget.category.name,
        'categoryLabel': widget.category.label,
        'entryType':     _entryType.name,
        'donorName':     _nameCtrl.text.trim(),
        'phone':         _phoneCtrl.text.trim(),
        'amount':        amount,
        'unit':          _isGoods ? _unit : 'PKR',
        'notes':         _notesCtrl.text.trim(),
        'date':          dateStr,
        'timestamp':     timestamp,
        'receiptNo':     receiptNo,
        'recordedBy':    widget.username,
        'collectorId':   widget.userId,
        'collectorRole': widget.role.displayLabel,
        'branchId':      widget.branchId,
        'branchName':    widget.branchName,
        'status':        _isGoods ? kStatusApproved : kStatusPending,
        'creditApplied': false,
        'createdAt':     timestamp,
      };

      if (!_isGoods) {
        data['paymentMethod'] = _paymentMethod.label;
        data['subtypeId']     = _selectedSubtype.name;
        data['subtypeLabel']  = _selectedSubtype.label;
      }
      if (widget.category == DonationCategory.gmwf) {
        data['gmwfSubCategoryId']    = _gmwfSub.name;
        data['gmwfSubCategoryLabel'] = _gmwfSub.label;
      }
      if (_isGoods) {
        final item = _itemCtrl.text.trim();
        if (item.isNotEmpty) data['goodsItem'] = item;
        final prob = double.tryParse(_probCtrl.text.trim());
        if (prob != null) data['probableAmount'] = prob;
      }

      await DonationsLocalStorage.saveDonation(
          branchId: widget.branchId, data: data);

      if (!_isGoods && widget.role.isOfficeBoy && amount > 0) {
        try {
          await CreditLedgerService(widget.branchId).officeBoyAutoCredit(
            fromUserId:   widget.userId,
            fromUsername: widget.username,
            amount:       amount,
            categoryId:   widget.category.name,
            subtypeId:    _selectedSubtype.name,
            branchName:   widget.branchName,
            receiptNo:    receiptNo,
            notes:        _notesCtrl.text.trim(),
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _saving = false);
      _clearForm();
      final creditNote = (!_isGoods && widget.role.isOfficeBoy && amount > 0)
          ? ' · Credit sent' : '';
      _snack('✅ Receipt $receiptNo saved$creditNote', DonDS.teal);
    } catch (e, st) {
      debugPrint('[Form] ❌ $e\n$st');
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString();
      _snack('Save failed: ${msg.substring(0, msg.length.clamp(0, 120))}',
          DS.statusRejected);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rMd)),
      duration: const Duration(seconds: 4),
    ));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t   = RoleThemeScope.dataOf(context);
    final cat = widget.category;

    // For GMWF cash, use the sub-category colour as accent
    final Color accent = (!_isGoods && cat == DonationCategory.gmwf)
        ? _gmwfSub.color : cat.color;

    return FocusScope(
      node: _scopeNode,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── CARD 1: Category ──────────────────────────────────────────
            _FCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FL('CATEGORY'),
                const SizedBox(height: 8),
                Row(
                  children: DonationCategory.values.map((c) {
                    final sel  = c == cat;
                    final last = c == DonationCategory.values.last;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onCatChanged(c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(right: last ? 0 : 10),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: sel ? c.color : t.bgCardAlt,
                            borderRadius: BorderRadius.circular(DS.rLg),
                            border: Border.all(
                                color: sel ? c.color : t.bgRule),
                            boxShadow: sel
                                ? [BoxShadow(
                                    color: c.color.withOpacity(0.25),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))]
                                : null,
                          ),
                          child: Column(children: [
                            Icon(c.icon, size: 22,
                                color: sel ? Colors.white : t.textTertiary),
                            const SizedBox(height: 5),
                            Text(c.shortLabel,
                                style: DS.label(
                                        color: sel
                                            ? Colors.white
                                            : t.textTertiary)
                                    .copyWith(
                                        fontSize: 11, letterSpacing: 0.4)),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // GMWF sub-programme
                if (cat == DonationCategory.gmwf) ...[
                  const SizedBox(height: 14),
                  _FL('PROGRAMME'),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2, shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8, mainAxisSpacing: 8,
                    childAspectRatio: 3.2,
                    children: GmwfSubCategory.values.map((sub) {
                      final sel = sub == _gmwfSub;
                      return GestureDetector(
                        onTap: () => _onGmwfSubChanged(sub),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: sel ? sub.color : t.bgCardAlt,
                            borderRadius: BorderRadius.circular(DS.rMd),
                            border: Border.all(
                                color: sel ? sub.color : t.bgRule),
                            boxShadow: sel
                                ? [BoxShadow(
                                    color: sub.color.withOpacity(0.22),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2))]
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10),
                            child: Row(children: [
                              Icon(sub.icon, size: 14,
                                  color: sel ? Colors.white : sub.color),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(sub.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: DS.label(
                                            color: sel
                                                ? Colors.white
                                                : t.textPrimary)
                                        .copyWith(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.1)),
                              ),
                            ]),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // Donation type toggle
                const SizedBox(height: 14),
                _FL('TYPE'),
                const SizedBox(height: 8),
                Row(
                  children: DonationEntryType.values.map((et) {
                    final sel  = et == _entryType;
                    final last = et == DonationEntryType.values.last;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _onEntryTypeChanged(et),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: EdgeInsets.only(right: last ? 0 : 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: sel
                                ? accent.withOpacity(0.07)
                                : t.bgCardAlt,
                            borderRadius: BorderRadius.circular(DS.rLg),
                            border: Border.all(
                                color: sel ? accent : t.bgRule,
                                width: sel ? 1.5 : 1),
                          ),
                          child: Row(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 16, height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                    color: sel
                                        ? accent
                                        : t.textTertiary.withOpacity(0.4),
                                    width: sel ? 5 : 1.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(et.icon, size: 14,
                                color: sel ? accent : t.textTertiary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(et.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: DS.body(
                                          color: sel
                                              ? accent
                                              : t.textSecondary)
                                      .copyWith(
                                          fontSize: 12.5,
                                          fontWeight: sel
                                              ? FontWeight.w700
                                              : FontWeight.w500)),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            )),
            const SizedBox(height: 10),

            // ── CARD 2: Donor info ────────────────────────────────────────
            _FCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FL('DONOR'),
                const SizedBox(height: 8),
                _FF(
                  controller: _nameCtrl, focusNode: _nameFocus,
                  hint: 'Full name',
                  icon: Icons.person_outline_rounded, accent: accent,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _scopeNode.nextFocus(),
                  validator: (v) =>
                      v?.trim().isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                _FF(
                  controller: _phoneCtrl, focusNode: _phoneFocus,
                  hint: 'Phone (optional) — 03XX-XXXXXXX',
                  icon: Icons.phone_outlined, accent: accent,
                  keyboardType: TextInputType.phone,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _scopeNode.nextFocus(),
                  formatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (v.trim().length != 11) return 'Must be 11 digits';
                    return null;
                  },
                ),
              ],
            )),
            const SizedBox(height: 10),

            // ── CARD 3: Goods details (conditional) ───────────────────────
            if (_isGoods) ...[
              _FCard(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FL('GOODS DETAILS'),
                  const SizedBox(height: 8),
                  _FF(
                    controller: _itemCtrl, focusNode: _itemFocus,
                    hint: 'Item — e.g. Rice, Wheat, Cooking Oil',
                    icon: Icons.inventory_2_outlined, accent: accent,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _scopeNode.nextFocus(),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _FF(
                        controller: _qtyCtrl, focusNode: _qtyFocus,
                        hint: 'Quantity',
                        icon: Icons.scale_outlined, accent: accent,
                        keyboardType: const TextInputType
                            .numberWithOptions(decimal: true),
                        textCapitalization: TextCapitalization.none,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _scopeNode.nextFocus(),
                        validator: (v) =>
                            v?.trim().isEmpty ?? true ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _UnitPicker(
                        value: _unit, color: accent,
                        onChanged: (v) =>
                            setState(() => _unit = v ?? _unit)),
                  ]),
                  const SizedBox(height: 10),
                  _FF(
                    controller: _probCtrl, focusNode: _probFocus,
                    hint: 'Estimated value PKR (optional)',
                    icon: Icons.payments_outlined, accent: accent,
                    keyboardType: TextInputType.number,
                    textCapitalization: TextCapitalization.none,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _scopeNode.nextFocus(),
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ],
              )),
              const SizedBox(height: 10),
            ],

            // ── CARD 4: Sub-type + Amount + Payment (cash only) ───────────
            if (!_isGoods) ...[
              _FCard(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sub-type — REPLACED WITH DROPDOWN
                  if (_currentSubtypes.isNotEmpty) ...[
                    _FL('SUB-TYPE'),
                    const SizedBox(height: 8),
                    _SubtypeDropdown(
                      subtypes:  _currentSubtypes,
                      selected:  _selectedSubtype,
                      accent:    accent,
                      onChanged: (st) =>
                          setState(() => _selectedSubtype = st!),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Amount
                  _FL('AMOUNT (PKR)'),
                  const SizedBox(height: 8),
                  _FF(
                    controller: _amtCtrl, focusNode: _amtFocus,
                    hint: 'Enter amount',
                    icon: Icons.payments_rounded, accent: accent,
                    keyboardType: TextInputType.number,
                    textCapitalization: TextCapitalization.none,
                    // done closes keyboard, never escapes scope
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),

                  // Payment method — three equal columns in one row
                  _FL('PAYMENT METHOD'),
                  const SizedBox(height: 8),
                  _PaymentRow(
                    selected:    _paymentMethod,
                    onChanged:   (pm) =>
                        setState(() => _paymentMethod = pm),
                    accentColor: accent,
                  ),
                ],
              )),
              const SizedBox(height: 10),
            ],

            // ── CARD 5: Notes ─────────────────────────────────────────────
            _FCard(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FL('NOTES (OPTIONAL)'),
                const SizedBox(height: 8),
                _FF(
                  controller: _notesCtrl, focusNode: _notesFocus,
                  hint: 'Any remarks or additional info',
                  icon: Icons.notes_rounded, accent: accent,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            )),
            const SizedBox(height: 16),

            // ── SUBMIT ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DS.rLg)),
                  elevation: 0,
                  shadowColor: accent.withOpacity(0.4),
                ),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add_circle_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          widget.role.isOfficeBoy && !_isGoods
                              ? 'Save & Send to Manager'
                              : _isGoods
                                  ? 'Save Goods Donation'
                                  : 'Save Donation',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ]),
              ),
            ),
            const SizedBox(height: 10),

            // ── Status row ────────────────────────────────────────────────
            Row(children: [
              Icon(
                  _isOnline
                      ? Icons.wifi_rounded
                      : Icons.cloud_off_rounded,
                  size: 11,
                  color: _isOnline ? DonDS.teal : DS.gold600),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                    _isOnline
                        ? 'Online — syncs automatically'
                        : 'Offline — saved locally',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: _isOnline ? DonDS.teal : DS.gold600)),
              ),
              if (widget.role.isOfficeBoy && !_isGoods) ...[
                Icon(Icons.arrow_upward_rounded,
                    size: 10, color: DS.sapphire500),
                const SizedBox(width: 3),
                Text('Auto-credit',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: DS.sapphire700)),
              ],
            ]),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Form field label
class _FL extends StatelessWidget {
  final String text;
  const _FL(this.text);
  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Text(text,
        style: DS.label(color: t.textTertiary)
            .copyWith(fontSize: 9.5, letterSpacing: 1.1));
  }
}

/// Card container
class _FCard extends StatelessWidget {
  final Widget child;
  const _FCard({required this.child});
  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        t.bgCard,
        borderRadius: BorderRadius.circular(DS.rLg),
        border:       Border.all(color: t.bgRule),
        boxShadow: const [BoxShadow(
            color: Color(0x07000000),
            blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

/// Form field
class _FF extends StatelessWidget {
  final TextEditingController      controller;
  final FocusNode?                 focusNode;
  final String                     hint;
  final IconData                   icon;
  final Color                      accent;
  final TextInputType?             keyboardType;
  final List<TextInputFormatter>?  formatters;
  final String? Function(String?)? validator;
  final int                        maxLines;
  final TextCapitalization         textCapitalization;
  final TextInputAction?           textInputAction;
  final ValueChanged<String>?      onSubmitted;

  const _FF({
    required this.controller,
    this.focusNode,
    required this.hint,
    required this.icon,
    required this.accent,
    this.keyboardType,
    this.formatters,
    this.validator,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.words,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return TextFormField(
      controller:         controller,
      focusNode:          focusNode,
      onFieldSubmitted:   onSubmitted,
      keyboardType:       keyboardType,
      inputFormatters:    formatters,
      validator:          validator,
      maxLines:           maxLines,
      textCapitalization: textCapitalization,
      textInputAction:    textInputAction,
      autocorrect:        false,
      enableSuggestions:
          keyboardType == TextInputType.name || keyboardType == null,
      style: DS.body(color: t.textPrimary)
          .copyWith(fontWeight: FontWeight.w500, fontSize: 15),
      decoration: InputDecoration(
        hintText:   hint,
        hintStyle:  DS.body(color: t.textTertiary).copyWith(fontSize: 14),
        prefixIcon: Icon(icon, color: accent, size: 18),
        filled:     true,
        fillColor:  t.bgCardAlt,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
            borderSide: BorderSide(color: t.bgRule)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
            borderSide: BorderSide(color: t.bgRule)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
            borderSide: BorderSide(color: accent, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
            borderSide: BorderSide(color: t.danger)),
        errorStyle:     DS.caption(color: t.danger),
        contentPadding: const EdgeInsets.symmetric(
            vertical: 13, horizontal: 16),
      ),
    );
  }
}

/// Sub-type dropdown — REPLACED CHIPS
class _SubtypeDropdown extends StatelessWidget {
  final List<DonationSubtype>          subtypes;
  final DonationSubtype                selected;
  final Color                          accent;
  final ValueChanged<DonationSubtype?> onChanged;
  
  const _SubtypeDropdown({
    required this.subtypes,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color:        t.bgCardAlt,
        borderRadius: BorderRadius.circular(DS.rMd),
        border:       Border.all(color: t.bgRule),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DonationSubtype>(
          value:         selected,
          isExpanded:    true,
          style:         DS.body(color: t.textPrimary).copyWith(fontWeight: FontWeight.w600),
          dropdownColor: t.bgCard,
          icon:          Icon(Icons.keyboard_arrow_down_rounded, color: accent),
          items: subtypes.map((st) => DropdownMenuItem(
            value: st,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(st.icon, size: 14, color: st.color),
              const SizedBox(width: 10),
              Text(st.label, style: TextStyle(color: st.color, fontWeight: FontWeight.w600)),
            ]),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Payment method — three equal columns
class _PaymentRow extends StatelessWidget {
  final PaymentMethod               selected;
  final ValueChanged<PaymentMethod> onChanged;
  final Color                       accentColor;
  const _PaymentRow({
    required this.selected, required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Row(
      children: PaymentMethod.values.map((pm) {
        final sel  = pm == selected;
        final last = pm == PaymentMethod.values.last;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(pm),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(right: last ? 0 : 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 10),
              decoration: BoxDecoration(
                color: sel
                    ? accentColor.withOpacity(0.10)
                    : t.bgCardAlt,
                borderRadius: BorderRadius.circular(DS.rMd),
                border: Border.all(
                    color: sel ? accentColor : t.bgRule,
                    width: sel ? 1.5 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(pm.icon, size: 16,
                    color: sel ? accentColor : t.textTertiary),
                const SizedBox(height: 4),
                Text(pm.label,
                    textAlign: TextAlign.center,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: DS.label(
                            color: sel ? accentColor : t.textTertiary)
                        .copyWith(
                            letterSpacing: 0.2, fontSize: 10,
                            fontWeight: sel
                                ? FontWeight.w700 : FontWeight.w500)),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Unit dropdown
class _UnitPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  final Color color;
  const _UnitPicker({
    required this.value, required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color:        t.bgCardAlt,
        borderRadius: BorderRadius.circular(DS.rMd),
        border:       Border.all(color: t.bgRule),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: false,
          style: DS.body(color: t.textPrimary)
              .copyWith(fontWeight: FontWeight.w500),
          dropdownColor: t.bgCard,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: color),
          items: kUnits.map((u) =>
              DropdownMenuItem(value: u, child: Text(u))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}