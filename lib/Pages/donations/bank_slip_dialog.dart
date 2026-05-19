// lib/pages/donations/bank_slip_dialog.dart
//
// Donor-centric Weekly Bank Slip Generator
// Allows selecting a donor and generates a slip based on their weekly donations.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gmwf/pages/donations/donations_shared.dart';
import 'package:gmwf/theme/role_theme_provider.dart';
import 'package:gmwf/services/donations_local_storage.dart';
import 'package:gmwf/models/donation_models.dart';
// FIX: Import DonDS from donations_screen
import 'package:gmwf/pages/donations/donations_screen.dart' show DonDS;
import 'package:share_plus/share_plus.dart';

class BankSlipDialog extends StatefulWidget {
  final String branchId;
  final String branchName;
  final String userId;
  final String username;

  const BankSlipDialog({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.userId,
    required this.username,
  });

  @override
  State<BankSlipDialog> createState() => _BankSlipDialogState();
}

class _BankSlipDialogState extends State<BankSlipDialog> {
  // ── Step control ─────────────────────────────────────────────────────────
  int _step = 0; // 0 = select donor, 1 = configure slip

  // ── Donor selection ───────────────────────────────────────────────────────
  DonorRecord? _selectedDonor;
  final _donorSearch = TextEditingController();
  String _donorQuery = '';

  // ── Week ─────────────────────────────────────────────────────────────────
  DateTime _monday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
  List<Map<String, dynamic>> _weeklyDonations = [];
  double _totalAmount = 0.0;
  bool _loading = false;

  // ── Form ──────────────────────────────────────────────────────────────────
  final _bankCtrl   = TextEditingController();
  final _accCtrl    = TextEditingController();
  final _slipCtrl   = TextEditingController();
  final _dateCtrl   = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  final _notesCtrl  = TextEditingController();
  final _formKey    = GlobalKey<FormState>();

  @override
  void dispose() {
    _donorSearch.dispose();
    _bankCtrl.dispose(); _accCtrl.dispose();
    _slipCtrl.dispose(); _dateCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWeekData(DonorRecord donor) async {
    setState(() => _loading = true);
    final sunday = _monday.add(const Duration(days: 6));
    final from   = DateFormat('yyyy-MM-dd').format(_monday);
    final to     = DateFormat('yyyy-MM-dd').format(sunday);
    final phone  = donor.phone.replaceAll(RegExp(r'\D'), '');
    final all = DonationsLocalStorage.getAllDonations(widget.branchId);
    _weeklyDonations = all.map((d) => d.toMap()).where((d) {
      final date    = (d['date']   as String?) ?? '';
      final status  = (d['status'] as String?) ?? '';
      final isGoods = (d['entryType'] as String? ?? '') == 'goods';
      final dPhone  = (d['phone']  as String? ?? '').replaceAll(RegExp(r'\D'), '');
      return !isGoods &&
             status == 'received' &&
             dPhone == phone &&
             date.compareTo(from) >= 0 &&
             date.compareTo(to)   <= 0;
    }).toList();

    _totalAmount = _weeklyDonations.fold(0.0,
        (sum, d) => sum + ((d['amount'] as num?)?.toDouble() ?? 0.0));
    setState(() => _loading = false);
  }

  void _changeWeek(int weeks) {
    setState(() => _monday = _monday.add(Duration(days: weeks * 7)));
    if (_selectedDonor != null) _loadWeekData(_selectedDonor!);
  }

  void _selectDonor(DonorRecord donor) {
    setState(() {
      _selectedDonor = donor;
      _step = 1;
    });
    _loadWeekData(donor);
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 540,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(DS.r2xl),
          border: Border.all(color: t.bgRule),
          boxShadow: DS.shadowXl,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF92400E),
                    DonDS.amber.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.rMd),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Weekly Bank Slip',
                          style: DS.display(color: Colors.white).copyWith(fontSize: 20)),
                      Text(
                        _step == 0
                            ? 'Step 1: Select a Donor'
                            : 'Step 2: Configure & Generate',
                        style: DS.caption(color: Colors.white.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
                if (_step == 1)
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: Colors.white.withValues(alpha: 0.8)),
                    onPressed: () => setState(() { _step = 0; _selectedDonor = null; }),
                    tooltip: 'Back to donor selection',
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.8)),
                ),
              ]),
            ),

            // ── Step indicator ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              color: t.bgCard,
              child: Row(children: [
                _StepDot(num: 1, active: _step == 0, done: _step > 0, color: DonDS.amber),
                Expanded(child: Container(height: 2, color: _step > 0 ? DonDS.amber : t.bgRule)),
                _StepDot(num: 2, active: _step == 1, done: false, color: DonDS.amber),
              ]),
            ),

            // ── Body ──────────────────────────────────────────────────────
            Expanded(
              child: _step == 0
                  ? _DonorSelector(
                      search: _donorSearch,
                      query: _donorQuery,
                      onQueryChanged: (q) => setState(() => _donorQuery = q),
                      onSelect: _selectDonor,
                      branchId: widget.branchId,
                    )
                  : _SlipForm(
                      donor:          _selectedDonor!,
                      monday:         _monday,
                      weeklyDonations: _weeklyDonations,
                      totalAmount:    _totalAmount,
                      loading:        _loading,
                      onChangeWeek:   _changeWeek,
                      bankCtrl:       _bankCtrl,
                      accCtrl:        _accCtrl,
                      slipCtrl:       _slipCtrl,
                      dateCtrl:       _dateCtrl,
                      notesCtrl:      _notesCtrl,
                      formKey:        _formKey,
                      onSave:         _save,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final slip = BankSlip(
      id:            'BS-${DateTime.now().millisecondsSinceEpoch}',
      branchId:      widget.branchId,
      weekStart:     DateFormat('yyyy-MM-dd').format(_monday),
      weekEnd:       DateFormat('yyyy-MM-dd').format(_monday.add(const Duration(days: 6))),
      amount:        _totalAmount,
      bankName:      _bankCtrl.text,
      accountNumber: _accCtrl.text,
      slipNumber:    _slipCtrl.text,
      depositDate:   _dateCtrl.text,
      imagePath:     '',
      uploadedBy:    widget.username,
      createdAt:     DateTime.now().toIso8601String(),
      notes:         _notesCtrl.text,
      donorId:       _selectedDonor?.id ?? '',
      donorName:     _selectedDonor?.name ?? '',
    );

    try {
      await DonationsLocalStorage.saveBankSlip(slip);
      
      // Auto-open PDF preview
      await _generateAndViewPdf(slip);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Bank slip saved & PDF generated!'),
            ]),
            backgroundColor: DonDS.teal,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rMd)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _generateAndViewPdf(BankSlip slip) async {
    final phone = _selectedDonor!.phone.replaceAll(RegExp(r'\D'), '');
    final all = DonationsLocalStorage.getAllDonations(widget.branchId);
    final items = all.where((it) {
      return (it.phone.replaceAll(RegExp(r'\D'), '') == phone) &&
             (it.date.compareTo(slip.weekStart) >= 0) &&
             (it.date.compareTo(slip.weekEnd) <= 0) &&
             it.isReceived && it.isCash;
    }).toList();

    try {
      final bytes = await buildBankSlipPdf(slip: slip, items: items);
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: 'GMWF-BankSlip-${slip.slipNumber}.pdf', mimeType: 'application/pdf')],
        text: 'Weekly Bank Slip - ${slip.donorName}',
      );
    } catch (e) {
      debugPrint('[BankSlipPDF] Error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — DONOR SELECTOR
// ─────────────────────────────────────────────────────────────────────────────

class _DonorSelector extends StatelessWidget {
  final TextEditingController search;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<DonorRecord> onSelect;
  final String branchId;

  const _DonorSelector({
    required this.search,
    required this.query,
    required this.onQueryChanged,
    required this.onSelect,
    required this.branchId,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Column(children: [
      // Search box
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: TextField(
          controller: search,
          style: DS.body(color: t.textPrimary),
          onChanged: (v) => onQueryChanged(v.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Search donor by name or phone…',
            hintStyle: DS.body(color: t.textTertiary),
            prefixIcon: Icon(Icons.search_rounded, color: t.textTertiary, size: 18),
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, size: 14, color: t.textTertiary),
                    onPressed: () { search.clear(); onQueryChanged(''); },
                  )
                : null,
            filled: true,
            fillColor: t.bgCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DS.rLg),
              borderSide: BorderSide(color: t.bgRule),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DS.rLg),
              borderSide: BorderSide(color: t.bgRule),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DS.rLg),
              borderSide: const BorderSide(color: DonDS.amber, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      // List
      Expanded(
        child: StreamBuilder<List<DonorRecord>>(
          stream: DonationsLocalStorage.streamAllDonors(branchId),
          builder: (context, snap) {
            final all = snap.data ?? [];
            final filtered = query.isEmpty
                ? all
                : all.where((d) =>
                    d.name.toLowerCase().contains(query) ||
                    d.phone.toLowerCase().contains(query)).toList();

            if (filtered.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    query.isEmpty
                        ? 'No donors registered yet.\nAdd a donation with a phone number to auto-register.'
                        : 'No results for "$query"',
                    textAlign: TextAlign.center,
                    style: DS.body(color: t.textTertiary),
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = filtered[i];
                final color = _avatarColor(d.name);
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DS.rLg),
                    onTap: () => onSelect(d),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.bgCard,
                        borderRadius: BorderRadius.circular(DS.rLg),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: Row(children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(_initials(d.name),
                                style: DS.heading(color: color).copyWith(fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name, style: DS.heading(color: t.textPrimary).copyWith(fontSize: 14)),
                              Text(d.phone.isNotEmpty ? d.phone : '—',
                                  style: DS.caption(color: t.textTertiary).copyWith(fontSize: 11)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: DonDS.amber.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(DS.rSm),
                            border: Border.all(color: DonDS.amber.withValues(alpha: 0.2)),
                          ),
                          // FIX: remove const — DonDS.amber is not a const
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.arrow_forward_rounded, size: 12, color: DonDS.amber),
                            const SizedBox(width: 4),
                            Text('Select', style: DS.label(color: DonDS.amber).copyWith(fontSize: 11)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Color _avatarColor(String name) {
    final colors = [DonDS.teal, DonDS.amber, const Color(0xFF7C3AED), const Color(0xFF059669)];
    return colors[name.length % colors.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — SLIP FORM
// ─────────────────────────────────────────────────────────────────────────────

class _SlipForm extends StatelessWidget {
  final DonorRecord donor;
  final DateTime monday;
  final List<Map<String, dynamic>> weeklyDonations;
  final double totalAmount;
  final bool loading;
  final ValueChanged<int> onChangeWeek;
  final TextEditingController bankCtrl, accCtrl, slipCtrl, dateCtrl, notesCtrl;
  final GlobalKey<FormState> formKey;
  final VoidCallback onSave;

  const _SlipForm({
    required this.donor,
    required this.monday,
    required this.weeklyDonations,
    required this.totalAmount,
    required this.loading,
    required this.onChangeWeek,
    required this.bankCtrl,
    required this.accCtrl,
    required this.slipCtrl,
    required this.dateCtrl,
    required this.notesCtrl,
    required this.formKey,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final t      = RoleThemeScope.dataOf(context);
    final sunday = monday.add(const Duration(days: 6));
    final weekStr = '${DateFormat("dd MMM").format(monday)} – ${DateFormat("dd MMM yyyy").format(sunday)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Donor highlight card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DonDS.amber.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(DS.rLg),
              border: Border.all(color: DonDS.amber.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DonDS.amber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                // FIX: remove const — DonDS.amber is not a compile-time constant
                child: Icon(Icons.person_rounded, color: DonDS.amber, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Generating slip for', style: DS.label(color: t.textTertiary).copyWith(fontSize: 10)),
                    Text(donor.name, style: DS.heading(color: t.textPrimary).copyWith(fontSize: 16)),
                    if (donor.phone.isNotEmpty)
                      Text(donor.phone, style: DS.caption(color: t.textTertiary)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Week Selector
          Container(
            decoration: BoxDecoration(
              color: t.bgCard,
              borderRadius: BorderRadius.circular(DS.rLg),
              border: Border.all(color: t.bgRule),
            ),
            child: Row(children: [
              IconButton(onPressed: () => onChangeWeek(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Column(children: [
                  Text('Week', style: DS.label(color: t.textTertiary).copyWith(fontSize: 10)),
                  Text(weekStr, style: DS.heading(color: t.textPrimary).copyWith(fontSize: 13)),
                ]),
              ),
              IconButton(onPressed: () => onChangeWeek(1), icon: const Icon(Icons.chevron_right)),
            ]),
          ),
          const SizedBox(height: 20),

          // Summary card
          if (loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF92400E), DonDS.amber.withValues(alpha: 0.9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(DS.rLg),
                boxShadow: DS.shadowMd,
              ),
              child: Column(children: [
                Text('WEEKLY COLLECTION',
                    style: DS.label(color: Colors.white.withValues(alpha: 0.75)).copyWith(letterSpacing: 1.4, fontSize: 9)),
                const SizedBox(height: 6),
                Text(
                  'PKR ${NumberFormat('#,###').format(totalAmount)}',
                  style: DS.display(color: Colors.white).copyWith(fontSize: 28),
                ),
                const SizedBox(height: 6),
                Text(
                  '${weeklyDonations.length} transactions verified as received',
                  style: DS.caption(color: Colors.white.withValues(alpha: 0.8)).copyWith(fontSize: 11),
                ),
              ]),
            ),

            if (weeklyDonations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.bgCard,
                    borderRadius: BorderRadius.circular(DS.rMd),
                    border: Border.all(color: t.bgRule),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: DonDS.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No received cash donations for this donor in the selected week.',
                        style: DS.caption(color: t.textSecondary).copyWith(fontSize: 11),
                      ),
                    ),
                  ]),
                ),
              ),

            const SizedBox(height: 24),

            // Form fields
            Form(
              key: formKey,
              child: Column(
                children: [
                  _Field('Bank Name', bankCtrl, Icons.business_rounded, context),
                  const SizedBox(height: 14),
                  _Field('Account Number', accCtrl, Icons.account_circle_rounded, context),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _Field('Slip Number', slipCtrl, Icons.confirmation_num_rounded, context)),
                    const SizedBox(width: 12),
                    Expanded(child: _Field('Deposit Date', dateCtrl, Icons.calendar_today_rounded, context)),
                  ]),
                  const SizedBox(height: 14),
                  _Field('Notes (Optional)', notesCtrl, Icons.notes_rounded, context, optional: true, maxLines: 2),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: totalAmount > 0 ? onSave : null,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                label: const Text('Save & Preview PDF',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DonDS.amber,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: DonDS.amber.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.rLg)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _Field(
    String label,
    TextEditingController ctrl,
    IconData icon,
    BuildContext context, {
    bool optional = false,
    int maxLines = 1,
  }) {
    final t = RoleThemeScope.dataOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: DS.label(color: t.textSecondary)),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        style: DS.body(color: t.textPrimary),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 16, color: t.textTertiary),
          filled: true,
          fillColor: t.bgCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
            borderSide: BorderSide(color: t.bgRule),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
            borderSide: BorderSide(color: t.bgRule),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
            borderSide: const BorderSide(color: DonDS.amber, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        validator: (v) => (!optional && (v == null || v.isEmpty)) ? 'Required' : null,
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP DOT INDICATOR
// ─────────────────────────────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final int num;
  final bool active, done;
  final Color color;
  const _StepDot({required this.num, required this.active, required this.done, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final bg = done ? color : (active ? color : t.bgRule);
    final fg = (active || done) ? Colors.white : t.textTertiary;
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: done
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
            : Text('$num', style: DS.heading(color: fg).copyWith(fontSize: 12)),
      ),
    );
  }
}
