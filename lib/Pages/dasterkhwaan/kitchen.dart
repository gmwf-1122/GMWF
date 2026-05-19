// lib/pages/dasterkhwaan/kitchen.dart
//
// Main kitchen panel — initialises state, loads Firebase data, and
// builds the 4-tab scaffold.  All dialog/sheet logic lives in:
//   • widgets/cook_dialog.dart   — food logging (cook / received / saved)
//   • widgets/stock_dialogs.dart — inventory add / adjust

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/stock_item.dart';
import 'widgets/cook_dialog.dart';
import 'widgets/stock_dialogs.dart';
import '../../widgets/global_module_wrapper.dart';

export 'widgets/cook_dialog.dart'
    show
        kPrimary,
        kAccent,
        kSuccess,
        kWarning,
        kInfo,
        kPurple,
        kTeal,
        kSurface,
        kCardBg,
        kTextDark,
        kTextMid,
        kTextLight;

class DasterkhwaanKitchen extends StatefulWidget {
  static const String routeName = '/dasterkhwaan-kitchen';
  final String? branchId;
  final String? username;
  /// Which bottom-nav tab to start on: 0=Tokens 1=Cooking 2=Inventory 3=History
  final int initialTab;

  const DasterkhwaanKitchen({
    super.key,
    this.branchId,
    this.username,
    this.initialTab = 0,
  });

  @override
  State<DasterkhwaanKitchen> createState() => _DasterkhwaanKitchenState();
}

class _DasterkhwaanKitchenState extends State<DasterkhwaanKitchen>
    with SingleTickerProviderStateMixin {
  late int _currentNav;
  String _username = 'Kitchen Staff';
  String? _branchId;

  final DateFormat _dateFmt    = DateFormat('yyyy-MM-dd');
  final DateFormat _displayFmt = DateFormat('dd MMM yyyy');
  late final String today = _dateFmt.format(DateTime.now());

  List<StockItem> _allStockItems = [];
  bool _stockLoaded = false;

  late AnimationController _animCtrl;

  // ── Default stock seeds ──────────────────────────────────────────────────
  static const List<Map<String, String>> _defaultStockItems = [
    {'name': 'Piyaz',        'unit': 'kg'},
    {'name': 'Tamatar',      'unit': 'kg'},
    {'name': 'Aloo',         'unit': 'kg'},
    {'name': 'Gobi',         'unit': 'kg'},
    {'name': 'Matar',        'unit': 'kg'},
    {'name': 'Palak',        'unit': 'kg'},
    {'name': 'Shaljam',      'unit': 'kg'},
    {'name': 'Band Gobi',    'unit': 'kg'},
    {'name': 'Phool Gobi',   'unit': 'kg'},
    {'name': 'Kheera',       'unit': 'kg'},
    {'name': 'Turai',        'unit': 'kg'},
    {'name': 'Karela',       'unit': 'kg'},
    {'name': 'Baingan',      'unit': 'kg'},
    {'name': 'Arvi',         'unit': 'kg'},
    {'name': 'Methi',        'unit': 'kg'},
    {'name': 'Sarson',       'unit': 'kg'},
    {'name': 'Gajar',        'unit': 'kg'},
    {'name': 'Mooli',        'unit': 'kg'},
    {'name': 'Shimla Mirch', 'unit': 'kg'},
    {'name': 'Bara Gosht',   'unit': 'kg'},
    {'name': 'Chota Gosht',  'unit': 'kg'},
    {'name': 'Murgh',        'unit': 'kg'},
    {'name': 'Keema',        'unit': 'kg'},
    {'name': 'Machli',       'unit': 'kg'},
    {'name': 'Anda',         'unit': 'piece'},
    {'name': 'Chawal',       'unit': 'kg'},
    {'name': 'Daal Masoor',  'unit': 'kg'},
    {'name': 'Daal Chana',   'unit': 'kg'},
    {'name': 'Daal Mash',    'unit': 'kg'},
    {'name': 'Daal Moong',   'unit': 'kg'},
    {'name': 'Maida',        'unit': 'kg'},
    {'name': 'Atta',         'unit': 'kg'},
    {'name': 'Suji',         'unit': 'kg'},
    {'name': 'Besan',        'unit': 'kg'},
    {'name': 'Ghee',         'unit': 'kg'},
    {'name': 'Oil',          'unit': 'liter'},
    {'name': 'Makhan',       'unit': 'kg'},
    {'name': 'Masala',       'unit': 'gram'},
    {'name': 'Namak',        'unit': 'kg'},
    {'name': 'Hari Mirch',   'unit': 'kg'},
    {'name': 'Lal Mirch',    'unit': 'gram'},
    {'name': 'Haldi',        'unit': 'gram'},
    {'name': 'Zeera',        'unit': 'gram'},
    {'name': 'Dhania',       'unit': 'gram'},
    {'name': 'Garam Masala', 'unit': 'gram'},
    {'name': 'Adrak',        'unit': 'kg'},
    {'name': 'Lehsan',       'unit': 'kg'},
    {'name': 'Pudina',       'unit': 'gram'},
    {'name': 'Limu',         'unit': 'piece'},
    {'name': 'Dahi',         'unit': 'kg'},
    {'name': 'Doodh',        'unit': 'liter'},
    {'name': 'Paneer',       'unit': 'kg'},
    {'name': 'Malai',        'unit': 'kg'},
    {'name': 'Khajoor',      'unit': 'kg'},
    {'name': 'Chini',        'unit': 'kg'},
    {'name': 'Chai Patti',   'unit': 'gram'},
    {'name': 'Paani',        'unit': 'liter'},
    {'name': 'Imli',         'unit': 'gram'},
    {'name': 'Sirka',        'unit': 'liter'},
    {'name': 'Soya Sauce',   'unit': 'liter'},
    {'name': 'Ketchup',      'unit': 'liter'},
    {'name': 'Bread',        'unit': 'piece'},
    {'name': 'Roti',         'unit': 'piece'},
  ];

  @override
  void initState() {
    super.initState();
    _currentNav = widget.initialTab;
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();

    if (widget.branchId != null) {
      _branchId = widget.branchId;
      _username = widget.username ?? 'Kitchen Staff';
      _loadAllStockItems().then((_) => _applyPreviousDaySaved());
    } else {
      _loadUserAndBranch();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Firebase helpers ─────────────────────────────────────────────────────

  Future<void> _loadUserAndBranch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final branches =
        await FirebaseFirestore.instance.collection('branches').get();
    for (final branch in branches.docs) {
      final doc =
          await branch.reference.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _username = data['username'] ??
              user.email?.split('@').first ??
              'Kitchen Staff';
          _branchId = branch.id;
        });
        await _loadAllStockItems();
        await _applyPreviousDaySaved();
        return;
      }
    }
  }

  Future<void> _loadAllStockItems() async {
    if (_branchId == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan_stock')
        .orderBy('name')
        .get();

    List<StockItem> items =
        snap.docs.map((e) => StockItem.fromMap(e.data(), e.id)).toList();

    if (items.isEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in _defaultStockItems) {
        batch.set(
          FirebaseFirestore.instance
              .collection('branches')
              .doc(_branchId)
              .collection('dasterkhwaan_stock')
              .doc(item['name']!),
          {
            'name':        item['name'],
            'quantity':    0.0,
            'unit':        item['unit'],
            'lastUpdated': FieldValue.serverTimestamp(),
          },
        );
      }
      await batch.commit();
      final newSnap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId)
          .collection('dasterkhwaan_stock')
          .orderBy('name')
          .get();
      items = newSnap.docs
          .map((e) => StockItem.fromMap(e.data(), e.id))
          .toList();
    }

    setState(() {
      _allStockItems = items..sort((a, b) => a.name.compareTo(b.name));
      _stockLoaded   = true;
    });
  }

  Future<void> _applyPreviousDaySaved() async {
    if (_branchId == null) return;
    final yesterday = _dateFmt
        .format(DateTime.now().subtract(const Duration(days: 1)));
    final dayRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan')
        .doc(yesterday);

    final daySnap = await dayRef.get();
    if (!daySnap.exists) return;
    final dayData = daySnap.data()!;
    if (dayData['savedCarriedOver'] == true) return;

    final cookingSnap =
        await dayRef.collection('cooking_sessions').get();
    if (cookingSnap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    bool hasCarryOver = false;

    for (final doc in cookingSnap.docs) {
      final data    = doc.data();
      final savedKg = (data['savedKg'] as num? ?? 0).toDouble();
      if (savedKg <= 0) continue;
      hasCarryOver = true;
      final dish    = (data['dish'] as String? ?? 'Saved Food').trim();
      final stockRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId)
          .collection('dasterkhwaan_stock')
          .doc('Saved: $dish');
      batch.set(
        stockRef,
        {
          'name':        'Saved: $dish',
          'quantity':    FieldValue.increment(savedKg),
          'unit':        'kg',
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    if (hasCarryOver) {
      batch.update(dayRef, {'savedCarriedOver': true});
      await batch.commit();
      await _loadAllStockItems();
    } else {
      await dayRef.update({'savedCarriedOver': true});
    }
  }

  Future<void> _adjustStock(String itemName, double delta) async {
    final ref = FirebaseFirestore.instance
        .collection('branches')
        .doc(_branchId)
        .collection('dasterkhwaan_stock')
        .doc(itemName);
    await ref.update({
      'quantity':    FieldValue.increment(delta),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
    final idx = _allStockItems.indexWhere((i) => i.name == itemName);
    if (idx != -1) {
      setState(() {
        _allStockItems[idx].quantity    += delta;
        _allStockItems[idx].lastUpdated  = Timestamp.now();
      });
    }
  }

  DocumentReference<Map<String, dynamic>> _dayDoc(String date) =>
      FirebaseFirestore.instance
          .collection('branches')
          .doc(_branchId!)
          .collection('dasterkhwaan')
          .doc(date);

  CollectionReference<Map<String, dynamic>> _tokensCol(String date) =>
      _dayDoc(date).collection('tokens');

  CollectionReference<Map<String, dynamic>> _cookingCol(String date) =>
      _dayDoc(date).collection('cooking_sessions');

  // ── Token serving ────────────────────────────────────────────────────────

  Future<void> _serveToken(String tokenId, int tokenNumber) async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kSuccess.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.restaurant_rounded,
                color: kSuccess, size: 22),
          ),
          const SizedBox(width: 12),
          Text('Serve Token #$tokenNumber',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        content: const Text('Mark this token as served?',
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccess,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              HapticFeedback.mediumImpact();
              final batch = FirebaseFirestore.instance.batch();
              batch.update(_tokensCol(today).doc(tokenId), {
                'served':     true,
                'servedTime': FieldValue.serverTimestamp(),
              });
              batch.set(
                _dayDoc(today),
                {'servedTokens': FieldValue.increment(1)},
                SetOptions(merge: true),
              );
              await batch.commit();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Token #$tokenNumber served ✓'),
                  backgroundColor: kSuccess,
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              }
            },
            child: const Text('Confirm Serve',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCookSession(
      String docId, Map<String, dynamic> data) async {
    final isReceived  = data['isReceivedFood'] as bool? ?? false;
    final isSavedFood = data['isSavedFood']    as bool? ?? false;
    final batch       = FirebaseFirestore.instance.batch();

    // Only restore stock for cooked-in-house sessions
    if (!isReceived && !isSavedFood) {
      final ingredients = List<Map<String, dynamic>>.from(
          (data['ingredients'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)));
      for (final ing in ingredients) {
        batch.update(
          FirebaseFirestore.instance
              .collection('branches')
              .doc(_branchId)
              .collection('dasterkhwaan_stock')
              .doc(ing['name'] as String),
          {
            'quantity':    FieldValue.increment((ing['qty'] as num).toDouble()),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
        );
      }
    }

    batch.delete(_cookingCol(today).doc(docId));
    await batch.commit();
    await _loadAllStockItems();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isSavedFood
            ? 'Saved food entry deleted'
            : isReceived
                ? 'Entry deleted'
                : 'Cooking session deleted — stock restored'),
        backgroundColor: kSuccess,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_branchId == null) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)],
            ),
          ),
          child: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const CircularProgressIndicator(
                    color: kWarning, strokeWidth: 3),
              ),
              const SizedBox(height: 32),
              Text('Loading Kitchen Panel…',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Preparing your workspace',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kSurface,
      floatingActionButton: _currentNav == 1
          ? FloatingActionButton.extended(
              onPressed: () => showFoodTypeChooser(
                context,
                allStockItems: _allStockItems,
                stockLoaded:   _stockLoaded,
                branchId:      _branchId!,
                today:         today,
                onDone:        _loadAllStockItems,
              ),
              backgroundColor: kWarning,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Log Food',
                  style:
                      TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: IndexedStack(
        index: _currentNav,
        children: [
          _TokensTab(
            branchId:   _branchId!,
            today:      today,
            tokensCol:  _tokensCol(today),
            serveToken: _serveToken,
            username:   _username,
            onLogout:   _logout,
          ),
          _CookingTab(
            branchId:   _branchId!,
            today:      today,
            cookingCol: _cookingCol(today),
            onAdd: () => showFoodTypeChooser(
              context,
              allStockItems: _allStockItems,
              stockLoaded:   _stockLoaded,
              branchId:      _branchId!,
              today:         today,
              onDone:        _loadAllStockItems,
            ),
            onEdit: (data, id) {
              final isSaved = data['isSavedFood'] as bool? ?? false;
              if (isSaved) {
                showSavedFoodDialog(
                  context,
                  existing:      data,
                  docId:         id,
                  allStockItems: _allStockItems,
                  stockLoaded:   _stockLoaded,
                  branchId:      _branchId!,
                  today:         today,
                  onDone:        _loadAllStockItems,
                );
              } else {
                showCookDialog(
                  context,
                  existing:      data,
                  docId:         id,
                  allStockItems: _allStockItems,
                  stockLoaded:   _stockLoaded,
                  branchId:      _branchId!,
                  today:         today,
                  onDone:        _loadAllStockItems,
                );
              }
            },
            onDelete: _deleteCookSession,
            username: _username,
            onLogout: _logout,
          ),
          _InventoryTab(
            branchId:      _branchId!,
            allStockItems: _allStockItems,
            stockLoaded:   _stockLoaded,
            onRefresh:     _loadAllStockItems,
            onAddNew: () => showAddStockDialog(
              context,
              branchId:      _branchId!,
              allStockItems: _allStockItems,
              onDone:        _loadAllStockItems,
            ),
            onEdit: (item) => showAddStockDialog(
              context,
              editItem:      item,
              branchId:      _branchId!,
              allStockItems: _allStockItems,
              onDone:        _loadAllStockItems,
            ),
            onAdjust: (item, {required bool isAdd}) =>
                showAdjustStockDialog(
              context,
              item,
              isAdd:    isAdd,
              branchId: _branchId!,
              onAdjust: _adjustStock,
            ),
            username: _username,
            onLogout: _logout,
          ),
          _HistoryTab(
            branchId:   _branchId!,
            dateFmt:    _dateFmt,
            displayFmt: _displayFmt,
            username:   _username,
            onLogout:   _logout,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const items = [
      _NavItem(Icons.confirmation_number_rounded, 'Tokens',    kSuccess),
      _NavItem(Icons.soup_kitchen_rounded,         'Cooking',   kWarning),
      _NavItem(Icons.inventory_2_rounded,          'Inventory', kInfo),
      _NavItem(Icons.history_rounded,              'History',   kPurple),
    ];
    return Container(
      decoration: BoxDecoration(
        color: kCardBg,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (idx) {
              final item     = items[idx];
              final selected = _currentNav == idx;
              return GestureDetector(
                onTap: () {
                  setState(() => _currentNav = idx);
                  HapticFeedback.selectionClick();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? item.color.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(item.icon,
                        color: selected ? item.color : kTextLight,
                        size: 24),
                    const SizedBox(height: 4),
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: selected ? item.color : kTextLight)),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  const _NavItem(this.icon, this.label, this.color);
}

// ═══════════════════════════════════════════════════════════════════════════
// TOKENS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _TokensTab extends StatelessWidget {
  final String branchId, today, username;
  final CollectionReference<Map<String, dynamic>> tokensCol;
  final Function(String, int) serveToken;
  final VoidCallback onLogout;

  const _TokensTab({
    required this.branchId,
    required this.today,
    required this.tokensCol,
    required this.serveToken,
    required this.username,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (!GlobalModuleWrapper.isWrapped(context))
        _buildHeader(context),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: tokensCol.snapshots(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: kSuccess, strokeWidth: 2));
            }
            if (snap.hasError) {
              return Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Colors.red.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text('Could not load tokens',
                      style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 8),
                  Text('${snap.error}',
                      style: TextStyle(
                          color: Colors.grey[400], fontSize: 11)),
                ]),
              );
            }
            final allDocs = snap.data?.docs ?? [];
            final pending = allDocs
                .where((d) =>
                    (d.data() as Map<String, dynamic>)['served'] == false)
                .toList()
              ..sort((a, b) {
                final aNum = (a.data() as Map)['number'] as int? ?? 0;
                final bNum = (b.data() as Map)['number'] as int? ?? 0;
                return aNum.compareTo(bNum);
              });

            if (pending.isEmpty) {
              return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                Icon(Icons.check_circle_outline,
                    size: 80, color: kSuccess.withValues(alpha: 0.25)),
                const SizedBox(height: 16),
                const Text('All tokens served!',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kTextLight)),
                const SizedBox(height: 6),
                const Text('No pending tokens',
                    style: TextStyle(fontSize: 14, color: kTextLight)),
              ]));
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: pending.length,
              itemBuilder: (_, i) {
                final e    = pending[i].data() as Map<String, dynamic>;
                final time = (e['time'] as Timestamp?)?.toDate() ?? DateTime.now();
                final number = e['number'] as int? ?? (i + 1);
                return _TokenCard(
                    number: number,
                    time: time,
                    onServe: () => serveToken(pending[i].id, number));
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF16A34A), kSuccess],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Row(children: [
                if (Navigator.canPop(context)) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 8),
                ],
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Active Tokens',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5)),
                  Text(username,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ]),
              ]),
              _logoutBtn(onLogout),
            ]),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(branchId)
                  .collection('dasterkhwaan')
                  .doc(today)
                  .collection('tokens')
                  .snapshots(),
              builder: (_, snap) {
                final all     = snap.data?.docs ?? [];
                final pending = all
                    .where((d) => (d.data() as Map)['served'] == false)
                    .length;
                final served  = all.length - pending;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                    _statBadge(Icons.hourglass_top_rounded, 'Pending',
                        '$pending', const Color(0xFFFFD54F)),
                    Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.2)),
                    _statBadge(Icons.check_circle_rounded, 'Served',
                        '$served', const Color(0xFF86EFAC)),
                    Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withValues(alpha: 0.2)),
                    _statBadge(Icons.confirmation_number_rounded, 'Total',
                        '${all.length}', Colors.white),
                  ]),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statBadge(
          IconData icon, String label, String value, Color color) =>
      Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 5),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]);
}

class _TokenCard extends StatelessWidget {
  final int number;
  final DateTime time;
  final VoidCallback onServe;
  const _TokenCard(
      {required this.number,
      required this.time,
      required this.onServe});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: kSuccess.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF16A34A), kSuccess],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
                child: Text('#$number',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900))),
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            const Text('Token Ready',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kTextDark)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.access_time_rounded,
                  size: 13, color: kTextLight),
              const SizedBox(width: 4),
              Text(DateFormat('hh:mm a').format(time),
                  style: const TextStyle(
                      fontSize: 12,
                      color: kTextLight,
                      fontWeight: FontWeight.w600)),
            ]),
          ])),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccess,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: onServe,
            child: const Text('Serve',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COOKING TAB
// ═══════════════════════════════════════════════════════════════════════════

class _CookingTab extends StatelessWidget {
  final String branchId, today, username;
  final CollectionReference<Map<String, dynamic>> cookingCol;
  final VoidCallback onAdd;
  final Function(Map<String, dynamic>, String) onEdit;
  final Function(String, Map<String, dynamic>) onDelete;
  final VoidCallback onLogout;

  const _CookingTab({
    required this.branchId,
    required this.today,
    required this.username,
    required this.cookingCol,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (!GlobalModuleWrapper.isWrapped(context))
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFFD97706), kWarning],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Row(children: [
                    if (Navigator.canPop(context)) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Food Log',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5)),
                      Text(username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                  _logoutBtn(onLogout),
                ]),
                const SizedBox(height: 14),
                StreamBuilder<QuerySnapshot>(
                  stream: cookingCol.snapshots(),
                  builder: (_, snap) {
                    final docs = snap.data?.docs ?? [];
                    double totalUsed = 0, totalSaved = 0, totalWasted = 0;
                    for (final d in docs) {
                      final data = d.data() as Map<String, dynamic>;
                      totalUsed   += (data['usedKg']   as num? ?? 0).toDouble();
                      totalSaved  += (data['savedKg']  as num? ?? 0).toDouble();
                      totalWasted += (data['wastedKg'] as num? ?? 0).toDouble();
                    }
                    return FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('branches')
                          .doc(branchId)
                          .collection('dasterkhwaan')
                          .doc(today)
                          .collection('tokens')
                          .where('served', isEqualTo: true)
                          .get(),
                      builder: (_, tsnap) {
                        final totalServedTokens =
                            tsnap.data?.docs.length ?? 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
                              children: [
                            _cookStat('Used',
                                '${totalUsed.toStringAsFixed(1)} kg',
                                Icons.whatshot_rounded),
                            _vDiv(),
                            _cookStat('Served',
                                '$totalServedTokens tokens',
                                Icons.confirmation_number_rounded),
                            _vDiv(),
                            _cookStat('Saved',
                                '${totalSaved.toStringAsFixed(1)} kg',
                                Icons.save_rounded),
                            _vDiv(),
                            _cookStat('Wasted',
                                '${totalWasted.toStringAsFixed(1)} kg',
                                Icons.delete_outline_rounded),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ]),
            ),
          ),
        ),
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: cookingCol
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: kWarning, strokeWidth: 2));
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                Icon(Icons.soup_kitchen_rounded,
                    size: 80, color: kWarning.withValues(alpha: 0.25)),
                const SizedBox(height: 16),
                const Text('No food logged yet',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: kTextLight)),
                const SizedBox(height: 8),
                const Text('Tap + to log cooked or received food',
                    style: TextStyle(fontSize: 13, color: kTextLight)),
              ]));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final time =
                    (data['createdAt'] as Timestamp?)?.toDate() ??
                        DateTime.now();
                return _CookingCard(
                  data:     data,
                  time:     time,
                  onEdit:   () => onEdit(data, docs[i].id),
                  onDelete: () => _confirmDelete(context, docs[i].id, data),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  void _confirmDelete(
      BuildContext context, String docId, Map<String, dynamic> data) {
    final isReceived  = data['isReceivedFood'] as bool? ?? false;
    final isSavedFood = data['isSavedFood']    as bool? ?? false;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: kAccent),
          SizedBox(width: 8),
          Text('Delete Entry?',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Text(
          isSavedFood
              ? 'Delete this saved food entry?'
              : isReceived
                  ? 'Delete "${data['dish']}"?'
                  : 'Delete "${data['dish']}"? Ingredients will be restored to stock.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              Navigator.pop(context);
              onDelete(docId, data);
            },
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _cookStat(String label, String value, IconData icon) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(height: 5),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ]);

  Widget _vDiv() =>
      Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.2));
}

// ── Cooking card ─────────────────────────────────────────────────────────────

class _CookingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime time;
  final VoidCallback onEdit, onDelete;

  const _CookingCard(
      {required this.data,
      required this.time,
      required this.onEdit,
      required this.onDelete});

  String _fmt(num? v) {
    final d = (v ?? 0).toDouble();
    return d == d.roundToDouble()
        ? d.toInt().toString()
        : d.toStringAsFixed(1);
  }

  bool get _isReceived  => data['isReceivedFood'] as bool? ?? false;
  bool get _isSavedFood => data['isSavedFood']    as bool? ?? false;

  bool get _quantitiesMissing =>
      (data['usedKg']   as num? ?? 0) == 0 &&
      (data['savedKg']  as num? ?? 0) == 0 &&
      (data['wastedKg'] as num? ?? 0) == 0;

  Color get _typeColor {
    if (_isSavedFood) return kTeal;
    if (_isReceived)  return kPurple;
    return kWarning;
  }

  IconData get _typeIcon {
    if (_isSavedFood) return Icons.recycling_rounded;
    if (_isReceived)  return Icons.delivery_dining_rounded;
    return Icons.soup_kitchen_rounded;
  }

  String get _typeLabel {
    if (_isSavedFood) return 'Saved Food';
    if (_isReceived)  return 'Received';
    return 'Cooked';
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = List<Map<String, dynamic>>.from(
        (data['ingredients'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
    final source = data['source'] as String? ?? '';
    // For saved food, strip the "Saved: " prefix for display
    final displayDish = _isSavedFood
        ? (data['dish'] as String? ?? '—').replaceFirst('Saved: ', '')
        : (data['dish'] as String? ?? '—');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: _quantitiesMissing
            ? Border.all(color: _typeColor.withValues(alpha: 0.5), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: _typeColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(_typeIcon, color: _typeColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Row(children: [
                Expanded(
                  child: Text(displayDish,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kTextDark)),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    _typeLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _typeColor),
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Text(DateFormat('hh:mm a · dd MMM').format(time),
                    style: const TextStyle(
                        fontSize: 11, color: kTextLight)),
                if (_quantitiesMissing) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Tap Edit to add quantities',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _typeColor)),
                  ),
                ],
              ]),
            ])),
            IconButton(
              icon: const Icon(Icons.edit_rounded,
                  size: 18, color: kInfo),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded,
                  size: 18, color: kAccent),
              onPressed: onDelete,
            ),
          ]),
        ),

        // Source row (received / saved food)
        if (source.isNotEmpty && source != 'Carry-over')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Icon(Icons.store_rounded, size: 13, color: _typeColor),
              const SizedBox(width: 5),
              Text(source,
                  style: TextStyle(
                      fontSize: 12,
                      color: _typeColor,
                      fontWeight: FontWeight.w600)),
            ]),
          ),

        // Saved food carry-over label
        if (_isSavedFood)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              const Icon(Icons.recycling_rounded, size: 13, color: kTeal),
              const SizedBox(width: 5),
              const Text('Carry-over from previous day',
                  style: TextStyle(
                      fontSize: 12,
                      color: kTeal,
                      fontWeight: FontWeight.w600)),
            ]),
          ),

        // Quantity stats
        if (!_quantitiesMissing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              _statChip('${_fmt(data['usedKg'] as num?)} kg',
                  'Used', _typeColor),
              const SizedBox(width: 8),
              _statChip('${_fmt(data['savedKg'] as num?)} kg',
                  'Saved', kInfo),
              const SizedBox(width: 8),
              _statChip('${_fmt(data['wastedKg'] as num?)} kg',
                  'Wasted', kAccent),
            ]),
          ),

        // Served info
        if (!_quantitiesMissing)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kSuccess.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kSuccess.withValues(alpha: 0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.confirmation_number_rounded,
                    color: kSuccess, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Served count comes from the Tokens tab automatically',
                    style: TextStyle(
                        fontSize: 11,
                        color: kSuccess,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ),

        // Saved carry-over reminder
        if (!_quantitiesMissing &&
            (data['savedKg'] as num? ?? 0) > 0 &&
            !_isSavedFood)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kInfo.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kInfo.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.schedule_rounded,
                    color: kInfo, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_fmt(data['savedKg'] as num?)} kg saved → carries over to tomorrow\'s inventory',
                    style: const TextStyle(
                        fontSize: 11,
                        color: kInfo,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ),

        // Ingredients (cooked only)
        if (!_isReceived && !_isSavedFood && ingredients.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text('INGREDIENTS USED',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: kTextLight,
                    letterSpacing: 1.0)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ingredients
                  .map((ing) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(
                            '${ing['name']}: ${_fmt(ing['qty'] as num?)} ${ing['unit']}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kTextMid)),
                      ))
                  .toList(),
            ),
          ),
        ],

        // Notes
        if ((data['notes'] as String? ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(data['notes'] as String,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ),
          ),

        const SizedBox(height: 14),
      ]),
    );
  }

  Widget _statChip(String value, String label, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.7))),
          ]),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// INVENTORY TAB
// ═══════════════════════════════════════════════════════════════════════════

class _InventoryTab extends StatefulWidget {
  final String branchId, username;
  final List<StockItem> allStockItems;
  final bool stockLoaded;
  final VoidCallback onRefresh, onAddNew, onLogout;
  final Function(StockItem) onEdit;
  final Function(StockItem, {required bool isAdd}) onAdjust;

  const _InventoryTab({
    required this.branchId,
    required this.allStockItems,
    required this.stockLoaded,
    required this.onRefresh,
    required this.onAddNew,
    required this.onEdit,
    required this.onAdjust,
    required this.username,
    required this.onLogout,
  });

  @override
  State<_InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<_InventoryTab> {
  final _searchCtrl   = TextEditingController();
  bool _showLowOnly   = false;
  bool _showSavedOnly = false;

  @override
  Widget build(BuildContext context) {
    var items = _searchCtrl.text.isEmpty
        ? widget.allStockItems
        : widget.allStockItems
            .where((i) => i.name
                .toLowerCase()
                .contains(_searchCtrl.text.toLowerCase()))
            .toList();
    if (_showLowOnly)   items = items.where((i) => i.quantity <= 2).toList();
    if (_showSavedOnly) items = items.where((i) => i.name.startsWith('Saved:')).toList();

    final lowStock      = widget.allStockItems.where((i) => i.quantity <= 2).length;
    final criticalStock = widget.allStockItems.where((i) => i.quantity == 0).length;
    final savedItems    = widget.allStockItems.where((i) => i.name.startsWith('Saved:')).length;

    return Column(children: [
      if (!GlobalModuleWrapper.isWrapped(context))
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF1D4ED8), kInfo],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Inventory',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5)),
                    Text(
                        '${widget.allStockItems.length} items · $savedItems saved carry-overs',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12)),
                  ]),
                  Row(children: [
                    GestureDetector(
                      onTap: widget.onAddNew,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: const Row(children: [
                          Icon(Icons.add_rounded,
                              color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('Add',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _logoutBtn(widget.onLogout),
                  ]),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: _invStat('$lowStock', 'Low Stock',
                          Icons.warning_rounded,
                          const Color(0xFFFFD54F))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _invStat('$criticalStock', 'Out of Stock',
                          Icons.error_rounded,
                          const Color(0xFFFCA5A5))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _invStat('$savedItems', 'Saved Items',
                          Icons.save_rounded,
                          const Color(0xFF93C5FD))),
                ]),
              ]),
            ),
          ),
        ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search inventory…',
                prefixIcon: const Icon(Icons.search,
                    color: kTextLight, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        })
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 13, horizontal: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _showLowOnly = !_showLowOnly;
              if (_showLowOnly) _showSavedOnly = false;
            }),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _showLowOnly ? kWarning : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Icon(Icons.warning_rounded,
                  color: _showLowOnly ? Colors.white : kTextLight,
                  size: 20),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _showSavedOnly = !_showSavedOnly;
              if (_showSavedOnly) _showLowOnly = false;
            }),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _showSavedOnly ? kTeal : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Icon(Icons.recycling_rounded,
                  color: _showSavedOnly ? Colors.white : kTextLight,
                  size: 20),
            ),
          ),
        ]),
      ),

      Expanded(
        child: !widget.stockLoaded
            ? const Center(
                child: CircularProgressIndicator(
                    color: kInfo, strokeWidth: 2))
            : items.isEmpty
                ? Center(
                    child: Text(
                    _showLowOnly
                        ? 'No low-stock items!'
                        : _showSavedOnly
                            ? 'No saved food carry-overs yet'
                            : 'No items found',
                    style: const TextStyle(
                        fontSize: 15, color: kTextLight),
                  ))
                : RefreshIndicator(
                    onRefresh: () async => widget.onRefresh(),
                    color: kInfo,
                    child: ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return _InventoryCard(
                          item:       item,
                          isLow:      item.quantity <= 2 && item.quantity > 0,
                          isCritical: item.quantity == 0,
                          isSaved:    item.name.startsWith('Saved:'),
                          onAdd:    () => widget.onAdjust(item, isAdd: true),
                          onRemove: () => widget.onAdjust(item, isAdd: false),
                          onEdit:   () => widget.onEdit(item),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }

  Widget _invStat(
          String value, String label, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _InventoryCard extends StatelessWidget {
  final StockItem item;
  final bool isLow, isCritical, isSaved;
  final VoidCallback onAdd, onRemove, onEdit;
  const _InventoryCard({
    required this.item,
    required this.isLow,
    required this.isCritical,
    required this.isSaved,
    required this.onAdd,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor   = kSuccess;
    IconData statusIcon = Icons.check_circle_rounded;
    if (isSaved) {
      statusColor = kTeal;
      statusIcon  = Icons.recycling_rounded;
    } else if (isCritical) {
      statusColor = kAccent;
      statusIcon  = Icons.error_rounded;
    } else if (isLow) {
      statusColor = kWarning;
      statusIcon  = Icons.warning_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: (isCritical || isLow || isSaved)
                ? statusColor.withValues(alpha: 0.3)
                : Colors.transparent),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13)),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(item.name,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: kTextDark)),
            const SizedBox(height: 2),
            Text(
                'Updated ${DateFormat('dd MMM, hh:mm a').format(item.lastUpdated.toDate())}',
                style: const TextStyle(
                    fontSize: 10, color: kTextLight)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text('${item.quantity} ${item.unit}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: statusColor)),
          ),
          const SizedBox(width: 6),
          Column(children: [
            _miniBtn(Icons.add_rounded,    const Color(0xFF1D4ED8), onAdd),
            const SizedBox(height: 3),
            _miniBtn(Icons.remove_rounded, kAccent,                 onRemove),
            const SizedBox(height: 3),
            _miniBtn(Icons.edit_rounded,   kPurple,                 onEdit),
          ]),
        ]),
      ),
    );
  }

  Widget _miniBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY TAB
// ═══════════════════════════════════════════════════════════════════════════

class _HistoryTab extends StatefulWidget {
  final String branchId, username;
  final DateFormat dateFmt, displayFmt;
  final VoidCallback onLogout;

  const _HistoryTab({
    required this.branchId,
    required this.dateFmt,
    required this.displayFmt,
    required this.username,
    required this.onLogout,
  });

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  DateTime _selectedDate = DateTime.now();

  Future<Map<String, dynamic>> _fetchDayData(String dateKey) async {
    final dayDoc = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('dasterkhwaan')
        .doc(dateKey)
        .get();
    final dayData    = dayDoc.data() ?? {};
    final tokensSnap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('dasterkhwaan')
        .doc(dateKey)
        .collection('tokens')
        .get();
    final cookingSnap = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('dasterkhwaan')
        .doc(dateKey)
        .collection('cooking_sessions')
        .get();

    final totalTokens  = tokensSnap.docs.length;
    final servedTokens = tokensSnap.docs
        .where((d) => (d.data())['served'] == true)
        .length;
    final sessions = cookingSnap.docs.map((d) {
      final data = d.data();
      return {
        'dish':           data['dish'] ?? '—',
        'isReceivedFood': data['isReceivedFood'] as bool? ?? false,
        'isSavedFood':    data['isSavedFood']    as bool? ?? false,
        'source':         data['source'] ?? '',
        'usedKg':         (data['usedKg']   as num? ?? data['cookedKg'] as num? ?? 0).toDouble(),
        'savedKg':        (data['savedKg']  as num? ?? 0).toDouble(),
        'wastedKg':       (data['wastedKg'] as num? ?? 0).toDouble(),
        'notes':          data['notes'] ?? '',
        'ingredients':    data['ingredients'] ?? [],
      };
    }).toList();

    return {
      'menu':         dayData['menu'] ?? '',
      'totalTokens':  totalTokens,
      'servedTokens': servedTokens,
      'sessions':     sessions,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dateKey     = widget.dateFmt.format(_selectedDate);
    final displayDate = widget.displayFmt.format(_selectedDate);
    final isToday     = dateKey == widget.dateFmt.format(DateTime.now());

    return Column(children: [
      if (!GlobalModuleWrapper.isWrapped(context))
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF7C3AED), kPurple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Row(children: [
                    if (Navigator.canPop(context)) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Daily History',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5)),
                      Text(widget.username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                  _logoutBtn(widget.onLogout),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    _dateNavBtn(
                      Icons.chevron_left_rounded,
                      () => setState(() => _selectedDate =
                          _selectedDate.subtract(const Duration(days: 1))),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                            builder: (ctx, child) => Theme(
                              data: ThemeData.light().copyWith(
                                  colorScheme: const ColorScheme.light(
                                      primary: kPurple)),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                          }
                        },
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                            const Icon(Icons.calendar_today_rounded,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(
                                isToday
                                    ? 'Today — $displayDate'
                                    : displayDate,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14)),
                          ]),
                        ),
                      ),
                    ),
                    _dateNavBtn(
                      Icons.chevron_right_rounded,
                      isToday
                          ? null
                          : () => setState(() => _selectedDate =
                              _selectedDate.add(const Duration(days: 1))),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          key: ValueKey(dateKey),
          future: _fetchDayData(dateKey),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: kPurple, strokeWidth: 2));
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final d            = snap.data!;
            final menu         = d['menu'] as String;
            final totalTokens  = d['totalTokens'] as int;
            final servedTokens = d['servedTokens'] as int;
            final sessions =
                d['sessions'] as List<Map<String, dynamic>>;

            if (totalTokens == 0 &&
                sessions.isEmpty &&
                menu.isEmpty) {
              return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                Icon(Icons.event_note_rounded,
                    size: 80, color: kPurple.withValues(alpha: 0.2)),
                const SizedBox(height: 16),
                Text('No records for $displayDate',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kTextLight)),
              ]));
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _sectionCard(
                  icon: Icons.confirmation_number_rounded,
                  iconColor: kSuccess,
                  title: 'Token Summary',
                  child: Row(children: [
                    Expanded(child: _histStat('Total',
                        '$totalTokens',
                        Icons.confirmation_number_rounded,
                        kSuccess)),
                    Expanded(child: _histStat('Served',
                        '$servedTokens',
                        Icons.check_circle_rounded, kInfo)),
                    Expanded(child: _histStat('Pending',
                        '${totalTokens - servedTokens}',
                        Icons.hourglass_top_rounded, kWarning)),
                  ]),
                ),
                const SizedBox(height: 14),
                if (menu.isNotEmpty) ...[
                  _sectionCard(
                    icon: Icons.restaurant_menu_rounded,
                    iconColor: kWarning,
                    title: 'Menu',
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(menu,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                              height: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (sessions.isNotEmpty) ...[
                  Text('FOOD LOG (${sessions.length})',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: kTextLight,
                          letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  ...sessions.map((s) => _HistCookCard(session: s)),
                ],
              ],
            );
          },
        ),
      ),
    ]);
  }

  Widget _dateNavBtn(IconData icon, VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: onTap == null
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon,
              color: onTap == null
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white,
              size: 20),
        ),
      );

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 18)),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kTextDark)),
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      );

  Widget _histStat(
          String label, String value, IconData icon, Color color) =>
      Column(children: [
        Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18)),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kTextLight)),
      ]);
}

class _HistCookCard extends StatelessWidget {
  final Map<String, dynamic> session;
  const _HistCookCard({required this.session});

  String _fmt(num? v) {
    final d = (v ?? 0).toDouble();
    return d == d.roundToDouble()
        ? d.toInt().toString()
        : d.toStringAsFixed(1);
  }

  bool get _isReceived  => session['isReceivedFood'] as bool? ?? false;
  bool get _isSavedFood => session['isSavedFood']    as bool? ?? false;

  Color get _typeColor {
    if (_isSavedFood) return kTeal;
    if (_isReceived)  return kPurple;
    return kWarning;
  }

  IconData get _typeIcon {
    if (_isSavedFood) return Icons.recycling_rounded;
    if (_isReceived)  return Icons.delivery_dining_rounded;
    return Icons.soup_kitchen_rounded;
  }

  String get _typeLabel {
    if (_isSavedFood) return 'Saved Food';
    if (_isReceived)  return 'Received';
    return 'Cooked';
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = List<Map<String, dynamic>>.from(
        (session['ingredients'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
    final source      = session['source'] as String? ?? '';
    final displayDish = _isSavedFood
        ? (session['dish'] as String).replaceFirst('Saved: ', '')
        : session['dish'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _typeColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: _typeColor.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          Icon(_typeIcon, color: _typeColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(displayDish,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: kTextDark))),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _typeLabel,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _typeColor),
            ),
          ),
        ]),
        if (_isSavedFood) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.recycling_rounded, size: 12, color: kTeal),
            const SizedBox(width: 4),
            const Text('Carry-over from previous day',
                style: TextStyle(
                    fontSize: 11,
                    color: kTeal,
                    fontWeight: FontWeight.w600)),
          ]),
        ] else if (_isReceived && source.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.store_rounded, size: 12, color: kPurple),
            const SizedBox(width: 4),
            Text(source,
                style: const TextStyle(
                    fontSize: 11,
                    color: kPurple,
                    fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 10),
        Row(children: [
          _chip('${_fmt(session['usedKg'] as num?)} kg',
              'Used', _typeColor),
          const SizedBox(width: 6),
          _chip('${_fmt(session['savedKg'] as num?)} kg',
              'Saved', kInfo),
          const SizedBox(width: 6),
          _chip('${_fmt(session['wastedKg'] as num?)} kg',
              'Wasted', kAccent),
        ]),
        if (!_isReceived && !_isSavedFood && ingredients.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: ingredients
                .map((ing) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                          '${ing['name']}: ${_fmt(ing['qty'] as num?)} ${ing['unit']}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kTextMid)),
                    ))
                .toList(),
          ),
        ],
        if ((session['notes'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(session['notes'] as String,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF64748B))),
        ],
      ]),
    );
  }

  Widget _chip(String value, String label, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 9,
                    color: color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═══════════════════════════════════════════════════════════════════════════

Widget _logoutBtn(VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(14)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.logout_rounded, color: Colors.white, size: 16),
          SizedBox(width: 6),
          Text('Logout',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ]),
      ),
    );
