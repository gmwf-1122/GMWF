// lib/pages/donations/donations_dashboard.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../services/donations_local_storage.dart';
import '../../services/local_storage_service.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import 'donations_shared.dart';
import 'donations_screen.dart';
import 'donations_form.dart';

double _toAmt(dynamic v) {
  if (v == null)   return 0.0;
  if (v is num)    return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI ROW
// ─────────────────────────────────────────────────────────────────────────────

class MiniKpiRow extends StatelessWidget {
  final String   branchId, today;
  final UserRole role;
  const MiniKpiRow({super.key,
      required this.branchId, required this.today, required this.role});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DonationsLocalStorage.streamDonationsForDate(branchId, today),
      builder: (_, snap) {
        final docs  = snap.data ?? [];
        final count = docs.length;
        final total = docs.fold<double>(0, (s, d) {
          final isGoods = (d['entryType'] as String? ?? '') == 'goods';
          return isGoods ? s : s + _toAmt(d['amount']);
        });
        String fmt(double v) {
          if (v >= 1e6)  return '${(v / 1e6).toStringAsFixed(1)}M';
          if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
          return v.toStringAsFixed(0);
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [DonDS.headerTop, DonDS.headerBot],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(DS.rLg),
            boxShadow: [BoxShadow(
                color: DonDS.teal.withOpacity(0.12),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            _kpiCell(Icons.receipt_long_rounded, '$count',
                "Today's Records", DonDS.tealLight),
            _kpiDiv(),
            _kpiCell(Icons.payments_rounded, 'PKR ${fmt(total)}',
                'Cash Collected', DonDS.amber),
            _kpiDiv(),
            _kpiCell(Icons.calendar_today_rounded,
                DateFormat('dd MMM').format(DateTime.now()),
                'Date', const Color(0xFF94B4B4)),
          ]),
        );
      },
    );
  }

  Widget _kpiDiv() => Container(
      width: 1, height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: DonDS.headerBorder);

  Widget _kpiCell(IconData icon, String val, String lbl, Color accent) =>
      Expanded(child: Column(children: [
        Icon(icon, color: accent, size: 13),
        const SizedBox(height: 4),
        Text(val, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: val.length > 7 ? 11 : 14,
                fontWeight: FontWeight.w800,
                color: DonDS.onDark,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 2),
        Text(lbl, textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600,
                color: DonDS.onDarkSub, letterSpacing: 0.2)),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD TAB
// ─────────────────────────────────────────────────────────────────────────────

class DashboardTab extends StatefulWidget {
  final String branchId, username, branchName, userId, today;
  final CollectionReference         col;
  final UserRole                    role;
  final Future<String> Function()   nextReceiptNumber;
  final DonationCategory            selectedCategory;
  final ValueChanged<DonationCategory> onCatChanged;

  const DashboardTab({super.key,
    required this.branchId,   required this.username,
    required this.branchName, required this.userId,
    required this.col,        required this.today,
    required this.role,       required this.nextReceiptNumber,
    required this.selectedCategory, required this.onCatChanged,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late String _from, _to;
  DonationCategory?  _filterCat;
  GmwfSubCategory?   _filterGmwfSub;
  late Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _from   = widget.today;
    _to     = widget.today;
    _stream = DonationsLocalStorage.streamAllDonations(widget.branchId);
  }

  @override
  void didUpdateWidget(DashboardTab old) {
    super.didUpdateWidget(old);
    if (old.branchId != widget.branchId) {
      setState(() {
        _stream        = DonationsLocalStorage.streamAllDonations(widget.branchId);
        _from          = widget.today;
        _to            = widget.today;
        _filterGmwfSub = null;
      });
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final init = DateTime.tryParse(isFrom ? _from : _to) ?? DateTime.now();
    final p    = await showDatePicker(
      context: context, initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (p == null || !mounted) return;
    final s = DateFormat('yyyy-MM-dd').format(p);
    setState(() {
      if (isFrom) {
        _from = s;
        if (_from.compareTo(_to) > 0) _to = s;
      } else {
        _to = s;
        if (_to.compareTo(_from) < 0) _from = s;
      }
    });
  }

  void _reset() => setState(() { _from = widget.today; _to = widget.today; });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return _ErrorView(error: '${snap.error}');

        final all = snap.data ?? [];

        // Role filter
        final roleFilt = widget.role.isOfficeBoy
            ? all.where((d) =>
                (d['recordedBy'] as String? ?? '').toLowerCase() ==
                widget.username.toLowerCase()).toList()
            : all;

        // Date filter
        final dateFilt = roleFilt.where((d) {
          final date = (d['date'] as String?) ?? '';
          if (_from.isNotEmpty && date.compareTo(_from) < 0) return false;
          if (_to.isNotEmpty   && date.compareTo(_to)   > 0) return false;
          return true;
        }).toList();

        // Category filter
        final catFilt = _filterCat == null
            ? dateFilt
            : dateFilt.where((d) =>
                (d['categoryId'] as String?) == _filterCat!.name).toList();

        // GMWF sub-category filter
        final donations = _filterGmwfSub == null
            ? catFilt
            : catFilt.where((d) =>
                (d['gmwfSubCategoryId'] as String?) ==
                _filterGmwfSub!.name).toList();

        final form = AddDonationForm(
          category:          widget.selectedCategory,
          onCatChanged:      widget.onCatChanged,
          col:               widget.col,
          today:             widget.today,
          username:          widget.username,
          branchId:          widget.branchId,
          branchName:        widget.branchName,
          userId:            widget.userId,
          role:              widget.role,
          nextReceiptNumber: widget.nextReceiptNumber,
        );

        final showGmwfSubs =
            _filterCat == DonationCategory.gmwf || _filterCat == null;

        return Container(
          color: t.bg,
          child: LayoutBuilder(builder: (_, box) {
            if (box.maxWidth >= 700) {
              return _WideLayout(
                branchId: widget.branchId, today: widget.today,
                role: widget.role, form: form, donations: donations,
                activeCat: widget.selectedCategory,
                filterCat: _filterCat,
                onFilter: (c) => setState(() {
                  _filterCat     = c;
                  _filterGmwfSub = null;
                }),
                filterGmwfSub: _filterGmwfSub,
                onGmwfFilter:  (s) => setState(() => _filterGmwfSub = s),
                showGmwfSubs:  showGmwfSubs,
                col: widget.col, from: _from, to: _to,
                onFrom: () => _pickDate(true),
                onTo:   () => _pickDate(false),
                onReset: _reset, branchName: widget.branchName,
              );
            }
            return _NarrowLayout(
              branchId: widget.branchId, today: widget.today,
              role: widget.role, form: form, donations: donations,
              activeCat: widget.selectedCategory,
              filterCat: _filterCat,
              onFilter: (c) => setState(() {
                _filterCat     = c;
                _filterGmwfSub = null;
              }),
              filterGmwfSub: _filterGmwfSub,
              onGmwfFilter:  (s) => setState(() => _filterGmwfSub = s),
              showGmwfSubs:  showGmwfSubs,
              col: widget.col, from: _from, to: _to,
              onFrom: () => _pickDate(true),
              onTo:   () => _pickDate(false),
              onReset: _reset, branchName: widget.branchName,
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final String branchId, today, branchName, from, to;
  final UserRole role;
  final Widget   form;
  final List<Map<String, dynamic>> donations;
  final DonationCategory   activeCat;
  final DonationCategory?  filterCat;
  final GmwfSubCategory?   filterGmwfSub;
  final bool               showGmwfSubs;
  final ValueChanged<DonationCategory?>  onFilter;
  final ValueChanged<GmwfSubCategory?>   onGmwfFilter;
  final CollectionReference col;
  final VoidCallback onFrom, onTo, onReset;

  const _WideLayout({
    required this.branchId,   required this.today,
    required this.branchName, required this.role,
    required this.form,       required this.donations,
    required this.activeCat,  required this.filterCat,
    required this.filterGmwfSub, required this.showGmwfSubs,
    required this.onFilter,   required this.onGmwfFilter,
    required this.col,        required this.from, required this.to,
    required this.onFrom,     required this.onTo, required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // LEFT: KPI + form
      SizedBox(
        width: 420,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: MiniKpiRow(branchId: branchId, today: today, role: role),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 32),
            child: form,
          )),
        ]),
      ),
      Container(width: 1, color: t.bgRule),
      // RIGHT: sticky filters + list
      Expanded(child: _RightList(
        donations: donations, branchId: branchId,
        activeCat: activeCat, filterCat: filterCat,
        filterGmwfSub: filterGmwfSub, showGmwfSubs: showGmwfSubs,
        onFilter: onFilter, onGmwfFilter: onGmwfFilter,
        col: col, from: from, to: to, today: today,
        onFrom: onFrom, onTo: onTo, onReset: onReset,
        branchName: branchName, hPad: 14, rPad: 20,
      )),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NARROW LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final String branchId, today, branchName, from, to;
  final UserRole role;
  final Widget   form;
  final List<Map<String, dynamic>> donations;
  final DonationCategory   activeCat;
  final DonationCategory?  filterCat;
  final GmwfSubCategory?   filterGmwfSub;
  final bool               showGmwfSubs;
  final ValueChanged<DonationCategory?>  onFilter;
  final ValueChanged<GmwfSubCategory?>   onGmwfFilter;
  final CollectionReference col;
  final VoidCallback onFrom, onTo, onReset;

  const _NarrowLayout({
    required this.branchId,   required this.today,
    required this.branchName, required this.role,
    required this.form,       required this.donations,
    required this.activeCat,  required this.filterCat,
    required this.filterGmwfSub, required this.showGmwfSubs,
    required this.onFilter,   required this.onGmwfFilter,
    required this.col,        required this.from, required this.to,
    required this.onFrom,     required this.onTo, required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t    = RoleThemeScope.dataOf(context);
    final cat  = filterCat ?? activeCat;
    final items = _buildItems(donations);

    return CustomScrollView(
      cacheExtent: 400,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _NarrowHeaderDelegate(
            bgColor:       t.bg,
            branchId:      branchId, today: today, role: role,
            from: from,    to: to,
            onFrom: onFrom, onTo: onTo, onReset: onReset,
            filterCat: filterCat,   onFilter: onFilter,
            filterGmwfSub: filterGmwfSub,
            onGmwfFilter:  onGmwfFilter,
            showGmwfSubs:  showGmwfSubs,
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: form,
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _SummaryCard(donations: donations, category: cat,
              filterGmwfSub: filterGmwfSub),
        )),
        SliverToBoxAdapter(child: _SectionHeader(
          cat: cat, count: donations.length,
          from: from, to: to, today: today, hPad: 16,
          filterGmwfSub: filterGmwfSub,
        )),
        if (donations.isEmpty)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _EmptyState(cat: cat),
          ))
        else
          _DonationSliver(
            items: items, donations: donations,
            branchId: branchId, col: col, activeCat: activeCat,
            branchName: branchName, today: today,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT LIST (wide)
// ─────────────────────────────────────────────────────────────────────────────

class _RightList extends StatelessWidget {
  final List<Map<String, dynamic>> donations;
  final String branchId, from, to, today, branchName;
  final DonationCategory   activeCat;
  final DonationCategory?  filterCat;
  final GmwfSubCategory?   filterGmwfSub;
  final bool               showGmwfSubs;
  final ValueChanged<DonationCategory?>  onFilter;
  final ValueChanged<GmwfSubCategory?>   onGmwfFilter;
  final CollectionReference col;
  final VoidCallback onFrom, onTo, onReset;
  final double hPad, rPad;

  const _RightList({
    required this.donations,      required this.branchId,
    required this.activeCat,      required this.filterCat,
    required this.filterGmwfSub,  required this.showGmwfSubs,
    required this.onFilter,       required this.onGmwfFilter,
    required this.col,            required this.from,
    required this.to,             required this.today,
    required this.onFrom,         required this.onTo,
    required this.onReset,        required this.branchName,
    required this.hPad,           required this.rPad,
  });

  @override
  Widget build(BuildContext context) {
    final t    = RoleThemeScope.dataOf(context);
    final cat  = filterCat ?? activeCat;
    final items = _buildItems(donations);

    return CustomScrollView(
      cacheExtent: 400,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _WideRightHeaderDelegate(
            bgColor: t.bg, hPad: hPad, rPad: rPad,
            from: from, to: to, today: today,
            onFrom: onFrom, onTo: onTo, onReset: onReset,
            filterCat: filterCat,  onFilter: onFilter,
            filterGmwfSub: filterGmwfSub,
            onGmwfFilter:  onGmwfFilter,
            showGmwfSubs:  showGmwfSubs,
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: EdgeInsets.fromLTRB(hPad, 8, rPad, 0),
          child: _SummaryCard(donations: donations, category: cat,
              filterGmwfSub: filterGmwfSub),
        )),
        SliverToBoxAdapter(child: _SectionHeader(
          cat: cat, count: donations.length,
          from: from, to: to, today: today, hPad: hPad,
          filterGmwfSub: filterGmwfSub,
        )),
        if (donations.isEmpty)
          SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: _EmptyState(cat: cat),
          ))
        else
          _DonationSliver(
            items: items, donations: donations,
            branchId: branchId, col: col, activeCat: activeCat,
            branchName: branchName, today: today,
            padding: EdgeInsets.fromLTRB(hPad, 0, rPad, 32),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NARROW HEADER DELEGATE
// base 196 + 38 when gmwf subs shown
// ─────────────────────────────────────────────────────────────────────────────

class _NarrowHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Color    bgColor;
  final String   branchId, today, from, to;
  final UserRole role;
  final VoidCallback onFrom, onTo, onReset;
  final DonationCategory?               filterCat;
  final GmwfSubCategory?                filterGmwfSub;
  final bool                            showGmwfSubs;
  final ValueChanged<DonationCategory?> onFilter;
  final ValueChanged<GmwfSubCategory?>  onGmwfFilter;

  double get _h => showGmwfSubs ? 234.0 : 196.0;

  const _NarrowHeaderDelegate({
    required this.bgColor,    required this.branchId,
    required this.today,      required this.role,
    required this.from,       required this.to,
    required this.onFrom,     required this.onTo, required this.onReset,
    required this.filterCat,  required this.onFilter,
    required this.filterGmwfSub, required this.onGmwfFilter,
    required this.showGmwfSubs,
  });

  @override double get minExtent => _h;
  @override double get maxExtent => _h;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) {
    final shadow = overlaps || shrink > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: _h,
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: shadow
            ? [const BoxShadow(color: Color(0x14000000),
                blurRadius: 10, offset: Offset(0, 4))]
            : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: MiniKpiRow(branchId: branchId, today: today, role: role),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _DateBar(from: from, to: to, today: today,
              onFrom: onFrom, onTo: onTo, onReset: onReset),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: _CategoryChips(filterCat: filterCat, onChanged: onFilter),
        ),
        if (showGmwfSubs) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: _GmwfSubChips(
                filterSub: filterGmwfSub, onChanged: onGmwfFilter),
          ),
        ] else
          const SizedBox(height: 10),
      ]),
    );
  }

  @override
  bool shouldRebuild(_NarrowHeaderDelegate o) =>
      o.bgColor != bgColor || o.from != from || o.to != to ||
      o.filterCat != filterCat || o.filterGmwfSub != filterGmwfSub ||
      o.showGmwfSubs != showGmwfSubs || o.branchId != branchId;
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE RIGHT HEADER DELEGATE
// base 108 + 38 when gmwf subs shown
// ─────────────────────────────────────────────────────────────────────────────

class _WideRightHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Color  bgColor;
  final double hPad, rPad;
  final String from, to, today;
  final VoidCallback onFrom, onTo, onReset;
  final DonationCategory?               filterCat;
  final GmwfSubCategory?                filterGmwfSub;
  final bool                            showGmwfSubs;
  final ValueChanged<DonationCategory?> onFilter;
  final ValueChanged<GmwfSubCategory?>  onGmwfFilter;

  double get _h => showGmwfSubs ? 150.0 : 108.0;

  const _WideRightHeaderDelegate({
    required this.bgColor,   required this.hPad,  required this.rPad,
    required this.from,      required this.to,    required this.today,
    required this.onFrom,    required this.onTo,  required this.onReset,
    required this.filterCat, required this.onFilter,
    required this.filterGmwfSub, required this.onGmwfFilter,
    required this.showGmwfSubs,
  });

  @override double get minExtent => _h;
  @override double get maxExtent => _h;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) {
    final shadow = overlaps || shrink > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: _h,
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: shadow
            ? [const BoxShadow(color: Color(0x10000000),
                blurRadius: 8, offset: Offset(0, 3))]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(hPad, 8, rPad, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DateBar(from: from, to: to, today: today,
              onFrom: onFrom, onTo: onTo, onReset: onReset),
          const SizedBox(height: 8),
          _CategoryChips(filterCat: filterCat, onChanged: onFilter),
          if (showGmwfSubs) ...[
            const SizedBox(height: 6),
            _GmwfSubChips(
                filterSub: filterGmwfSub, onChanged: onGmwfFilter),
          ],
        ]),
      ),
    );
  }

  @override
  bool shouldRebuild(_WideRightHeaderDelegate o) =>
      o.bgColor != bgColor || o.from != from || o.to != to ||
      o.filterCat != filterCat || o.filterGmwfSub != filterGmwfSub ||
      o.showGmwfSubs != showGmwfSubs || o.hPad != hPad;
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

List<_Item> _buildItems(List<Map<String, dynamic>> donations) {
  final items = <_Item>[];
  String? last;
  for (int i = 0; i < donations.length; i++) {
    final dk = donations[i]['date'] as String? ?? '';
    if (dk != last) { last = dk; items.add(_Item.sep(dk)); }
    items.add(_Item.tile(i));
  }
  return items;
}

class _Item {
  final bool isSep; final String? dateKey; final int? index;
  const _Item.sep(String k) : isSep = true,  dateKey = k,    index = null;
  const _Item.tile(int i)   : isSep = false, dateKey = null, index = i;
}

// ─────────────────────────────────────────────────────────────────────────────
// DONATION SLIVER
// ─────────────────────────────────────────────────────────────────────────────

class _DonationSliver extends StatelessWidget {
  final List<_Item>                items;
  final List<Map<String, dynamic>> donations;
  final String              branchId, branchName, today;
  final CollectionReference col;
  final DonationCategory    activeCat;
  final EdgeInsets          padding;

  const _DonationSliver({
    required this.items,      required this.donations,
    required this.branchId,   required this.col,
    required this.activeCat,  required this.branchName,
    required this.today,      required this.padding,
  });

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: padding,
    sliver: SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, idx) {
          final item = items[idx];
          if (item.isSep) {
            return _DateSep(dateKey: item.dateKey!, today: today);
          }
          final d   = donations[item.index!];
          final cat = DonationCategory.values
              .firstWhereOrNull(
                  (c) => c.name == (d['categoryId'] as String?)) ??
              activeCat;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DonationTile(
                data: d, branchId: branchId, col: col,
                category: cat, branchName: branchName),
          );
        },
        childCount: items.length,
        addRepaintBoundaries: true, addAutomaticKeepAlives: false,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DATE BAR
// ─────────────────────────────────────────────────────────────────────────────

class _DateBar extends StatelessWidget {
  final String from, to, today;
  final VoidCallback onFrom, onTo, onReset;
  const _DateBar({required this.from, required this.to, required this.today,
      required this.onFrom, required this.onTo, required this.onReset});

  String _p(String d) {
    try { return DateFormat('dd MMM').format(DateTime.parse(d)); }
    catch (_) { return d; }
  }
  bool get _isToday => from == today && to == today;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: t.bgCard,
          borderRadius: BorderRadius.circular(DS.rMd),
          border: Border.all(color: t.bgRule),
          boxShadow: DS.shadowSm),
      child: Row(children: [
        Icon(Icons.date_range_rounded, size: 14, color: DonDS.teal),
        const SizedBox(width: 8),
        _pill(t, 'From', from, onFrom),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Icon(Icons.arrow_forward_rounded,
              size: 11, color: t.textTertiary),
        ),
        _pill(t, 'To', to, onTo),
        const Spacer(),
        if (!_isToday)
          GestureDetector(
            onTap: onReset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: DonDS.teal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(DS.rSm),
                  border: Border.all(color: DonDS.teal.withOpacity(0.25))),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.today_rounded, size: 10, color: DonDS.teal),
                SizedBox(width: 3),
                Text('Today',
                    style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: DonDS.teal)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _pill(RoleThemeData t, String lbl, String date, VoidCallback tap) =>
      GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
              color: t.bgCardAlt,
              borderRadius: BorderRadius.circular(DS.rSm),
              border: Border.all(color: t.bgRule)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$lbl: ',
                style: DS.label(color: t.textTertiary)
                    .copyWith(fontSize: 9)),
            Text(_p(date),
                style: DS.label(color: t.textPrimary)
                    .copyWith(fontSize: 11)),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 11, color: DonDS.teal),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORY CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final DonationCategory?               filterCat;
  final ValueChanged<DonationCategory?> onChanged;
  const _CategoryChips({required this.filterCat, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _Chip(label: 'All', icon: Icons.grid_view_rounded,
            color: DonDS.teal,
            sel: filterCat == null, onTap: () => onChanged(null)),
        ...DonationCategory.values.map((cat) {
          final sel = filterCat == cat;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _Chip(
                label: cat.label, icon: cat.icon, color: cat.color,
                sel: sel, onTap: () => onChanged(sel ? null : cat)),
          );
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GMWF SUB-CATEGORY CHIPS
// ─────────────────────────────────────────────────────────────────────────────

class _GmwfSubChips extends StatelessWidget {
  final GmwfSubCategory?               filterSub;
  final ValueChanged<GmwfSubCategory?> onChanged;
  const _GmwfSubChips({required this.filterSub, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        // Small "GMWF:" label prefix
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: DS.emerald100,
            borderRadius: BorderRadius.circular(DS.rSm),
          ),
          child: const Text('GMWF',
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800,
                  color: DS.emerald600, letterSpacing: 0.8)),
        ),
        ...GmwfSubCategory.values.map((sub) {
          final sel  = filterSub == sub;
          final last = sub == GmwfSubCategory.values.last;
          return Padding(
            padding: EdgeInsets.only(right: last ? 0 : 6),
            child: GestureDetector(
              onTap: () => onChanged(sel ? null : sub),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? sub.color : t.bgCard,
                  borderRadius: BorderRadius.circular(DS.rSm),
                  border: Border.all(
                      color: sel ? sub.color : t.bgRule,
                      width: sel ? 1.5 : 1),
                  boxShadow: sel
                      ? [BoxShadow(color: sub.color.withOpacity(0.2),
                          blurRadius: 4, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(sub.icon, size: 11,
                      color: sel ? Colors.white : sub.color),
                  const SizedBox(width: 5),
                  Text(sub.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? Colors.white : sub.color)),
                ]),
              ),
            ),
          );
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label; final IconData icon;
  final Color color;  final bool sel;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.icon,
      required this.color, required this.sel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? color : t.bgCard,
          borderRadius: BorderRadius.circular(DS.rXl),
          border: Border.all(color: sel ? color : t.bgRule),
          boxShadow: sel
              ? [BoxShadow(color: color.withOpacity(0.22),
                  blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: sel ? Colors.white : color),
          const SizedBox(width: 6),
          Text(label,
              style: DS.label(color: sel ? Colors.white : color)
                  .copyWith(fontSize: 12,
                      fontWeight: sel
                          ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final DonationCategory  cat;
  final GmwfSubCategory?  filterGmwfSub;
  final int    count;
  final String from, to, today;
  final double hPad;
  const _SectionHeader({
    required this.cat, required this.count,
    required this.from, required this.to, required this.today,
    this.hPad = 16, this.filterGmwfSub,
  });

  String _p(String d) {
    try { return DateFormat('dd MMM yy').format(DateTime.parse(d)); }
    catch (_) { return d; }
  }

  @override
  Widget build(BuildContext context) {
    final t   = RoleThemeScope.dataOf(context);
    final sub = from == to
        ? (from == today ? 'Today' : _p(from))
        : '${_p(from)} – ${_p(to)}';
    final accent = filterGmwfSub?.color ?? cat.color;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 6),
      child: Row(children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(filterGmwfSub != null
              ? '${filterGmwfSub!.label} Transactions'
              : 'Transactions',
              style: DS.heading(color: t.textPrimary)),
          Text(sub, style: DS.caption(color: t.textTertiary)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color:        accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(DS.rSm),
              border: Border.all(color: accent.withOpacity(0.25))),
          child: Text('$count records',
              style: DS.label(color: accent)
                  .copyWith(letterSpacing: 0.3)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final List<Map<String, dynamic>> donations;
  final DonationCategory           category;
  final GmwfSubCategory?           filterGmwfSub;
  const _SummaryCard({
    required this.donations, required this.category,
    this.filterGmwfSub,
  });

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    double total = 0, approved = 0, pending = 0;
    int cashCnt = 0, goodsCnt = 0;
    for (final d in donations) {
      final amt     = _toAmt(d['amount']);
      final isGoods = (d['entryType'] as String? ?? '') == 'goods';
      final status  = d['status'] as String? ?? kStatusPending;
      if (!isGoods) {
        total += amt; cashCnt++;
        if (status == kStatusApproved)     approved += amt;
        else if (status == kStatusPending) pending  += amt;
      } else { goodsCnt++; }
    }
    final pct   = total > 0 ? (approved / total).clamp(0.0, 1.0) : 0.0;
    final color = filterGmwfSub?.color ?? category.color;

    return Container(
      margin:  const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: color.withOpacity(0.18)),
          boxShadow:    DS.shadowSm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(DS.rSm)),
            child: Icon(Icons.analytics_rounded, color: color, size: 14)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Summary', style: DS.subheading(color: t.textPrimary)),
            Text('${donations.length} donation'
                '${donations.length != 1 ? "s" : ""}',
                style: DS.caption(color: t.textTertiary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('PKR ${fmtNum(total)}',
                style: DS.mono(color: color, size: 17)),
            Text('Cash total',
                style: DS.caption(color: t.textTertiary)),
          ]),
        ]),
        if (cashCnt > 0) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Approval rate',
                  style: DS.label(color: t.textTertiary)),
              Text('${(pct * 100).round()}%',
                  style: DS.label(color: DS.statusApproved)
                      .copyWith(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct, minHeight: 6,
              backgroundColor: DS.statusPending.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation(DS.statusApproved),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatPill('Approved', 'PKR ${fmtNum(approved)}',
                  DS.statusApproved),
              const SizedBox(width: 8),
              _StatPill('Pending',  'PKR ${fmtNum(pending)}',
                  DS.statusPending),
              if (goodsCnt > 0) ...[
                const SizedBox(width: 8),
                _StatPill('Goods', '$goodsCnt items', DS.plum500),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label, value; final Color color;
  const _StatPill(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
        color:        color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(DS.rSm),
        border:       Border.all(color: color.withOpacity(0.20))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: DS.label(color: color).copyWith(fontSize: 9)),
      const SizedBox(height: 3),
      Text(value, style: DS.mono(color: color, size: 12),
          overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DATE SEPARATOR
// ─────────────────────────────────────────────────────────────────────────────

class _DateSep extends StatelessWidget {
  final String dateKey, today;
  const _DateSep({required this.dateKey, required this.today});

  String get _lbl {
    try {
      final d    = DateTime.parse(dateKey);
      final tDay = DateTime.parse(today);
      final diff = tDay.difference(d).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      if (diff < 7)  return DateFormat('EEEE').format(d);
      return DateFormat('dd MMM yyyy').format(d);
    } catch (_) { return dateKey; }
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: Container(height: 0.5, color: t.bgRule)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
              color:        t.bgCard,
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: t.bgRule),
              boxShadow:    DS.shadowSm),
          child: Text(_lbl,
              style: DS.label(color: t.textTertiary)
                  .copyWith(fontSize: 10, letterSpacing: 0.4)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 0.5, color: t.bgRule)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final DonationCategory cat;
  const _EmptyState({required this.cat});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: t.bgRule)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: cat.color.withOpacity(0.07), shape: BoxShape.circle),
          child: Icon(Icons.receipt_long_rounded,
              size: 30, color: cat.color.withOpacity(0.4)),
        ),
        const SizedBox(height: 16),
        Text('No Transactions',
            style: DS.subheading(color: t.textTertiary)),
        const SizedBox(height: 4),
        Text('No records for the selected date range',
            style: DS.caption(color: t.textTertiary)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ERROR VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded, size: 48,
            color: DS.statusRejected.withOpacity(0.5)),
        const SizedBox(height: 16),
        Text('Could not load donations',
            style: DS.subheading(color: t.textSecondary)),
        const SizedBox(height: 6),
        Text(error, textAlign: TextAlign.center,
            style: DS.caption(color: t.textTertiary)),
      ]),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DONATION TILE
// ─────────────────────────────────────────────────────────────────────────────

class _DonationTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final String               branchId, branchName;
  final CollectionReference  col;
  final DonationCategory     category;
  const _DonationTile({
    required this.data,       required this.branchId,
    required this.col,        required this.category,
    required this.branchName,
  });

  @override
  State<_DonationTile> createState() => _DonationTileState();
}

class _DonationTileState extends State<_DonationTile> {
  bool _exp = false;

  @override
  Widget build(BuildContext context) {
    final t         = RoleThemeScope.dataOf(context);
    final d         = widget.data;
    final cat       = widget.category;
    final amt       = (d['amount'] as num?)?.toDouble() ?? 0;
    final prob      = (d['probableAmount'] as num?)?.toDouble();
    final isGoods   = (d['entryType'] as String? ?? '') == 'goods';
    final receiptNo = d['receiptNo']  as String? ?? '';
    final donor     = d['donorName']  as String? ?? '-';
    final phone     = d['phone']      as String? ?? '';
    final subId     = d['subtypeId']  as String?;
    final gmwfSubId = d['gmwfSubCategoryId'] as String?;
    final goodsItem = d['goodsItem']  as String? ?? '';
    final notes     = d['notes']      as String? ?? '';
    final status    = d['status']     as String? ?? kStatusPending;
    final unit      = d['unit']       as String? ?? '';
    final recorder  = d['recordedBy'] as String? ?? '';
    final colRole   = d['collectorRole'] as String? ?? '';

    final subtype = subId != null
        ? DonationSubtype.values.firstWhereOrNull((s) => s.name == subId)
        : null;
    final gmwfSub = gmwfSubId != null
        ? GmwfSubCategory.values.firstWhereOrNull((s) => s.name == gmwfSubId)
        : null;

    final Color accent =
        (!isGoods && cat == DonationCategory.gmwf && gmwfSub != null)
            ? gmwfSub.color : cat.color;

    final amtDisplay = isGoods
        ? (prob != null ? 'PKR ${fmtNum(prob)}'
            : '${amt % 1 == 0 ? amt.toInt() : amt} $unit')
        : 'PKR ${fmtNum(amt)}';

    String? collectorLabel;
    if (colRole.isNotEmpty && colRole != 'Staff' && recorder.isNotEmpty) {
      collectorLabel = '$colRole: $recorder';
    } else if (recorder.isNotEmpty) {
      collectorLabel = recorder;
    }

    return Container(
      decoration: BoxDecoration(
          color:        t.bgCard,
          borderRadius: BorderRadius.circular(DS.rLg),
          border:       Border.all(color: t.bgRule),
          boxShadow:    DS.shadowSm),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Top stripe
        Container(
          height: 3,
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.4)])),
        ),

        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: accent.withOpacity(0.4)),
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Receipt badge
                Container(
                  constraints: const BoxConstraints(minWidth: 46),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                      color: accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(DS.rMd),
                      border: Border.all(color: accent.withOpacity(0.18))),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text('RCT', style: DS.label(color: accent)
                        .copyWith(fontSize: 7)),
                    const SizedBox(height: 2),
                    Text(receiptNo.isNotEmpty
                            ? receiptNo.split('-').last : '-',
                        style: DS.mono(color: accent, size: 13)
                            .copyWith(height: 1.2)),
                  ]),
                ),
                const SizedBox(width: 10),

                // Info column
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(donor,
                      style: DS.subheading(color: t.textPrimary)
                          .copyWith(fontSize: 14.5)),
                  const SizedBox(height: 2),
                  if (receiptNo.isNotEmpty)
                    Text(receiptNo,
                        style: DS.caption(color: t.textTertiary)
                            .copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 9.5)),
                  if (collectorLabel != null) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.badge_outlined, size: 10,
                          color: t.textTertiary),
                      const SizedBox(width: 4),
                      if (colRole.isNotEmpty && colRole != 'Staff') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _roleColor(colRole).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _roleColor(colRole).withOpacity(0.3)),
                          ),
                          child: Text(colRole,
                              style: DS.label(color: _roleColor(colRole))
                                  .copyWith(fontSize: 8)),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(child: Text(collectorLabel,
                          style: DS.caption(color: t.textTertiary)
                              .copyWith(fontSize: 10),
                          overflow: TextOverflow.ellipsis)),
                    ]),
                  ],
                  const SizedBox(height: 5),
                  Wrap(spacing: 5, runSpacing: 4, children: [
                    _CatBadge(cat: cat),
                    if (gmwfSub != null) _GmwfSubBadge(sub: gmwfSub),
                    if (isGoods) _GoodsBadge(),
                    if (subtype != null) DSSubtypeBadge(subtype: subtype),
                    if ((d['paymentMethod'] as String? ?? 'Cash') != 'Cash')
                      _MetaPill(icon: Icons.credit_card_rounded,
                          label: d['paymentMethod'] as String,
                          color: DonDS.teal),
                    if (phone.isNotEmpty)
                      _MetaPill(icon: Icons.phone_outlined,
                          label: phone, color: t.textTertiary),
                    if (goodsItem.isNotEmpty)
                      _MetaPill(icon: Icons.inventory_2_outlined,
                          label: goodsItem, color: accent),
                  ]),
                ])),

                // Amount + status
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(amtDisplay,
                      style: DS.mono(color: accent, size: 15)),
                  if (!isGoods) ...[
                    const SizedBox(height: 5),
                    DSStatusBadge(status: status),
                  ],
                ]),
              ]),
            )),
          ]),
        ),

        // Notes
        if (notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: t.bgCardAlt,
                  borderRadius: BorderRadius.circular(DS.rSm),
                  border: Border.all(color: t.bgRule)),
              child: Text(notes,
                  style: DS.caption(color: t.textSecondary)
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                DSActionButton(icon: Icons.print_rounded, label: 'Print',
                    color: accent,
                    onTap: () => printReceiptPdf(d, receiptNo)),
                const SizedBox(width: 6),
                DSActionButton(icon: Icons.download_rounded, label: 'PDF',
                    color: DonDS.teal,
                    onTap: () =>
                        downloadReceiptPdf(d, receiptNo, context)),
                const SizedBox(width: 6),
                DSActionButton(
                    assetImage: 'assets/icons/WA.png',
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    disabled: phone.isEmpty,
                    onTap: () => shareReceiptWhatsApp(
                        d, receiptNo, phone, widget.branchName)),
                const SizedBox(width: 6),
                DSActionButton(icon: Icons.sms_rounded, label: 'SMS',
                    color: accent, disabled: phone.isEmpty,
                    onTap: () => sendSmsThankYou(
                          phone, donor, cat, amt,
                          unit.isEmpty ? 'PKR' : unit,
                          receiptNo, widget.branchName,
                          subtype: subtype, gmwfSub: gmwfSub,
                          paymentMethod:
                              d['paymentMethod'] as String? ?? 'Cash',
                          isGoods: isGoods,
                        )),
              ]),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              GestureDetector(
                onTap: () => setState(() => _exp = !_exp),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                      color: t.bgCardAlt,
                      borderRadius: BorderRadius.circular(DS.rSm),
                      border: Border.all(color: t.bgRule)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_exp ? 'Less' : 'Details',
                        style: DS.label(color: t.textTertiary)
                            .copyWith(fontSize: 11)),
                    const SizedBox(width: 3),
                    Icon(_exp
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 14, color: t.textTertiary),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _confirmDelete(context),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: DS.statusRejected.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(DS.rSm),
                      border: Border.all(
                          color: DS.statusRejected.withOpacity(0.25))),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 16, color: DS.statusRejected),
                ),
              ),
            ]),
          ]),
        ),

        // Expanded details
        if (_exp)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
            decoration: BoxDecoration(
                color:  t.bgCardAlt,
                border: Border(top: BorderSide(color: t.bgRule))),
            child: Wrap(spacing: 22, runSpacing: 10, children: [
              _Cell('Receipt No', receiptNo.isNotEmpty ? receiptNo : '-'),
              _Cell('Category', cat.label),
              if (gmwfSub != null) _Cell('Programme', gmwfSub.label),
              if (subtype  != null) _Cell('Sub-Type', subtype.label),
              _Cell('Entry', isGoods ? 'Goods / Ajnas' : 'Cash'),
              _Cell('Recorded By', recorder.isNotEmpty ? recorder : '-'),
              if (colRole.isNotEmpty) _Cell('Collector Role', colRole),
              _Cell('Date', d['date'] as String? ?? '-'),
              if (d['paymentMethod'] != null && !isGoods)
                _Cell('Payment', d['paymentMethod'] as String),
              if (!isGoods)
                _Cell('Status',
                    status[0].toUpperCase() + status.substring(1)),
              if (isGoods && prob != null)
                _Cell('Est. Value', 'PKR ${fmtNum(prob)}'),
              _Cell('Sync',
                  (d['syncStatus'] as String? ?? 'pending') == 'pending'
                      ? '⏳ Queued' : '✅ Synced'),
            ]),
          ),
      ]),
    );
  }

  Color _roleColor(String r) {
    switch (r.toLowerCase().trim()) {
      case 'chairman':   return DS.gold500;
      case 'manager':    return DS.emerald500;
      case 'office boy': return DS.sapphire500;
      default:           return DS.ink500;
    }
  }

  void _confirmDelete(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rXl)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color:        t.bgCard,
              borderRadius: BorderRadius.circular(DS.rXl),
              border:       Border.all(color: t.bgRule)),
          child: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove Transaction',
                  style: DS.heading(color: t.textPrimary)),
              const SizedBox(height: 10),
              Text('This will permanently delete this donation record.',
                  style: DS.body(color: t.textSecondary)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: t.textSecondary,
                      side: BorderSide(color: t.bgRule),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DS.rMd)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: DS.statusRejected,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DS.rMd)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _doDelete();
                  },
                  child: const Text('Delete',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doDelete() async {
    try {
      final hiveKey = widget.data['hiveKey'] as String?;
      if (hiveKey == null || hiveKey.isEmpty) return;
      await DonationsLocalStorage.deleteDonation(
          hiveKey, widget.branchId);
    } catch (e) { debugPrint('[Tile] Delete error: $e'); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MICRO WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _CatBadge extends StatelessWidget {
  final DonationCategory cat;
  const _CatBadge({required this.cat});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color:        cat.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: cat.color.withOpacity(0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(cat.icon, size: 9, color: cat.color),
      const SizedBox(width: 4),
      Text(cat.shortLabel,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: cat.color, letterSpacing: 0.3)),
    ]),
  );
}

class _GmwfSubBadge extends StatelessWidget {
  final GmwfSubCategory sub;
  const _GmwfSubBadge({required this.sub});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color:        sub.lightColor,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: sub.color.withOpacity(0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(sub.icon, size: 9, color: sub.color),
      const SizedBox(width: 4),
      Text(sub.label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              color: sub.color, letterSpacing: 0.3)),
    ]),
  );
}

class _GoodsBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color:        DS.plum100,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: DS.plum500.withOpacity(0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: const [
      Icon(Icons.inventory_2_rounded, size: 9, color: DS.plum700),
      SizedBox(width: 4),
      Text('Goods', style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700,
          color: DS.plum700, letterSpacing: 0.3)),
    ]),
  );
}

class _MetaPill extends StatelessWidget {
  final IconData icon; final String label; final Color? color;
  const _MetaPill({required this.icon, required this.label, this.color});
  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final c = color ?? t.textTertiary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: c),
      const SizedBox(width: 4),
      Text(label, style: DS.caption(color: c)),
    ]);
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
      Text(value,
          style: DS.subheading(color: t.textPrimary)
              .copyWith(fontSize: 12.5)),
    ]);
  }
}