// lib/pages/dispensary/dispensar/medicine_ledger.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gmwf/services/local_storage_service.dart';
import 'dart:async';

class MedicineLedgerPage extends StatefulWidget {
  final String branchId;
  final Map<String, dynamic>? initialMedicine;

  const MedicineLedgerPage({
    super.key,
    required this.branchId,
    this.initialMedicine,
  });

  @override
  State<MedicineLedgerPage> createState() => _MedicineLedgerPageState();
}

class _MedicineLedgerPageState extends State<MedicineLedgerPage> {
  // ── Palette ───────────────────────────────────────────────────────────────
  static const _teal = Color(0xFF00695C);
  static const _tealDark = Color(0xFF004D40);
  static const _bg = Color(0xFFF0F4F4);
  static const _white = Colors.white;
  static const _textDark = Color(0xFF1B2631);
  static const _textMid = Color(0xFF4A5568);
  static const _textLight = Color(0xFF718096);
  static const _accent = Color(0xFF26A69A);
  static const _red = Color(0xFFD32F2F);
  static const _orange = Color(0xFFE65100);

  // ── State ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _selectedMed;
  bool _isLoading = false;
  Map<String, dynamic>? _reportData;
  List<Map<String, dynamic>> _allMedicines = [];
  bool _isSearchingMeds = false;

  @override
  void initState() {
    super.initState();
    _selectedMed = widget.initialMedicine;
    _loadMedicines();
    if (_selectedMed != null) {
      _loadReport();
    }
  }

  // ── Data Fetching ──────────────────────────────────────────────────────────
  Future<void> _loadMedicines() async {
    setState(() => _isSearchingMeds = true);
    try {
      final items = LocalStorageService.getAllLocalStockItems(branchId: widget.branchId);
      setState(() {
        _allMedicines = items.toList()
          ..sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
        _isSearchingMeds = false;
      });
    } catch (e) {
      debugPrint('Error loading medicines: $e');
      setState(() => _isSearchingMeds = false);
    }
  }

  String _cacheKey() {
    if (_selectedMed == null) return '';
    final medId = _selectedMed!['id'] ?? _selectedMed!['docId'] ?? _selectedMed!['medicineId'] ?? _selectedMed!['name'];
    return '${widget.branchId}_${medId}_all_time';
  }

  Future<void> _loadReport({bool forceRecalculate = false}) async {
    if (_selectedMed == null) return;
    setState(() => _isLoading = true);

    final key = _cacheKey();
    if (!forceRecalculate) {
      final cached = Hive.box(LocalStorageService.reportsCacheBox).get(key);
      if (cached != null) {
        setState(() {
          _reportData = Map<String, dynamic>.from(cached as Map);
          _isLoading = false;
        });
        return;
      }
    }

    try {
      final medId = _selectedMed!['id'] ?? _selectedMed!['docId'] ?? '';
      
      // 1. Query Logs (Additions, Registrations, Edits) from inventory_log (All-Time)
      // We will try by medicineId first
      QuerySnapshot additionsSnap;
      if (medId.isNotEmpty) {
        additionsSnap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory_log')
            .where('medicineId', isEqualTo: medId)
            .get();
      } else {
        additionsSnap = await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory_log')
            .where('medicineName', isEqualTo: _selectedMed!['name'])
            .get();
      }

      double totalAdded = 0;
      double totalAdjusted = 0; // Absolute value of manual edits
      List<Map<String, dynamic>> logs = [];
      DateTime? earliestDate;

      for (final doc in additionsSnap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        final qty = (d['quantityAdded'] as num?)?.toDouble() ?? 0.0;
        final ts = (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        final action = d['action'] ?? '';
        
        if (earliestDate == null || ts.isBefore(earliestDate)) {
          earliestDate = ts;
        }
        
        if (action == 'edit_stock') {
           totalAdjusted += qty;
           logs.add({
             'type': qty >= 0 ? 'added' : 'removed',
             'qty': qty.abs(),
             'date': ts,
             'user': d['performedByName'] ?? 'Admin',
             'msg': 'Manual Adjustment',
           });
        } else {
           totalAdded += qty;
           logs.add({
             'type': 'added',
             'qty': qty,
             'date': ts,
             'user': d['performedByName'] ?? 'Unknown',
             'msg': action == 'medicine_registered_directly' ? 'Initial Registration' : 'Restock',
           });
        }
      }

      // Determine search range for dispensing
      DateTime searchStart = earliestDate ?? DateTime.now().subtract(const Duration(days: 90));

      searchStart = DateTime(searchStart.year, searchStart.month, searchStart.day);
      final todayMidnight = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);

      // 2. Query Removals (Dispensing) over the identified lifetime
      double totalRemoved = 0;
      
      final List<DateTime> daysToFetch = [];
      for (DateTime curr = searchStart; curr.isBefore(todayMidnight); curr = curr.add(const Duration(days: 1))) {
        daysToFetch.add(curr);
      }

      // Fetch days in parallel to drastically improve speed
      final fetchFutures = daysToFetch.map((curr) async {
        final dateKey = DateFormat('ddMMyy').format(curr);
        
        try {
          final dailySnap = await FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('dispensary')
              .doc(dateKey)
              .collection(dateKey)
              .get();

          double dayTotalRemoved = 0;
          List<Map<String, dynamic>> dayLogs = [];

          for (final doc in dailySnap.docs) {
            final d = doc.data();
            final prescriptions = (d['prescriptions'] as List?) ?? [];
            for (final rx in prescriptions) {
              if (rx is! Map) continue;
              // Check inventoryId first, fallback to name matching
              final String rxId = (rx['inventoryId'] ?? rx['medicineId'] ?? rx['id'] ?? '').toString();
              bool isMatch = false;
              
              if (medId.isNotEmpty && rxId.isNotEmpty && rxId == medId) {
                isMatch = true;
              } else {
                final nameMatch = rx['name'] == _selectedMed!['name'];
                final typeMatch = rx['type'] == _selectedMed!['type'];
                final doseMatch = rx['dose'] == _selectedMed!['dose'];
                isMatch = nameMatch && typeMatch && doseMatch;
              }

              if (isMatch) {
                final days = (d['daysOfMedicine'] as num?)?.toDouble() ?? 1.0;
                final perDayRaw = rx['quantity'] ?? rx['qty'] ?? 0;
                final perDay = perDayRaw is num ? perDayRaw.toDouble() : double.tryParse(perDayRaw.toString()) ?? 0.0;
                
                final isInj = (rx['type']?.toString().toLowerCase().contains('injection') ?? false) || 
                              (rx['type']?.toString().toLowerCase().contains('drip') ?? false);
                
                final qty = isInj ? perDay : (perDay * days);
                dayTotalRemoved += qty;

                dayLogs.add({
                  'type': 'removed',
                  'qty': qty,
                  'date': curr,
                  'user': d['dispenserName'] ?? 'Unknown',
                  'msg': 'Dispensed (Token: ${d['serial']})',
                  'days': days.toInt(),
                });
              }
            }
          }
          return {'removed': dayTotalRemoved, 'logs': dayLogs};
        } catch (e) {
          debugPrint('Error fetching dispensary date $dateKey: $e');
          return {'removed': 0.0, 'logs': []};
        }
      });

      final results = await Future.wait(fetchFutures);
      for (final res in results) {
        totalRemoved += res['removed'] as double;
        logs.addAll(res['logs'] as List<Map<String, dynamic>>);
      }


      // 4. Get Current Remaining
      final currentStock = (_selectedMed!['quantity'] as num?)?.toDouble() ?? 0.0;

      // 5. Finalize Report
      // Sort logs by date descending
      logs.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

      final report = {
        'totalAdded': totalAdded,
        'totalAdjusted': totalAdjusted,
        'totalRemoved': totalRemoved,
        'remaining': currentStock,
        'logs': logs.map((l) => {
          ...l,
          'date': (l['date'] as DateTime).toIso8601String(),
        }).toList(),
        'calculatedAt': DateTime.now().toIso8601String(),
        'month': 'All Time History',
      };

      // Save to Hive
      await Hive.box(LocalStorageService.reportsCacheBox).put(key, report);

      if (mounted) {
        setState(() {
          _reportData = report;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error calculating report: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load report: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── UI Components ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildFilters()),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: _teal)))
          else if (_selectedMed == null)
            _buildEmptyState('Select a medicine to view its ledger')
          else if (_reportData == null)
            _buildEmptyState('No data found for this period')
          else
            _buildLedgerContent(),
        ],
      ),
      floatingActionButton: _reportData != null
          ? FloatingActionButton.extended(
              onPressed: () => _loadReport(forceRecalculate: true),
              backgroundColor: _teal,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text('Recalculate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _teal,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        title: const Text('Medicine Ledger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_tealDark, _teal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Icon(FontAwesomeIcons.fileLines, size: 120, color: Colors.white.withValues(alpha: 0.1)),
              ),
            ],
          ),
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _showMedicinePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.medication_rounded, size: 18, color: _teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedMed?['name'] ?? 'Select Medicine',
                            style: TextStyle(
                              color: _selectedMed != null ? _textDark : _textLight,
                              fontWeight: _selectedMed != null ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _teal.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.history_rounded, size: 16, color: _teal),
                      SizedBox(width: 8),
                      Text(
                        'All Time History',
                        style: TextStyle(color: _tealDark, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.query_stats_rounded, size: 80, color: Colors.grey.shade200),
            const SizedBox(height: 16),
            Text(msg, style: TextStyle(color: _textLight, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerContent() {
    final report = _reportData!;
    final logs = (report['logs'] as List?) ?? [];

    return SliverList(
      delegate: SliverChildListDelegate([
        _buildSummaryCards(report),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text('Transaction History', style: TextStyle(color: _tealDark, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        if (logs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No transactions recorded for this period', style: TextStyle(color: _textLight))),
          )
        else
          ...logs.map((log) => _buildLogTile(log)).toList(),
        const SizedBox(height: 100), // Space for FAB
      ]),
    );
  }

  Widget _buildSummaryCards(Map<String, dynamic> report) {
    final added = (report['totalAdded'] as num).toDouble();
    final removed = (report['totalRemoved'] as num).toDouble();
    final net = added - removed;
    final adjusted = (report['totalAdjusted'] as num?)?.toDouble() ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          Row(
            children: [
              _summaryCard('Added', added.toStringAsFixed(0), _teal, Icons.add_circle_outline_rounded),
              const SizedBox(width: 12),
              _summaryCard('Removed', removed.toStringAsFixed(0), _red, Icons.remove_circle_outline_rounded),
              const SizedBox(width: 12),
              _summaryCard('Adjusted', adjusted.toStringAsFixed(0), _orange, Icons.edit_note_rounded),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.inventory_2_rounded, color: _orange, size: 20),
                    SizedBox(width: 12),
                    Text('Current Live Stock', style: TextStyle(color: _textDark, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                Text(
                  report['remaining'].toStringAsFixed(0),
                  style: const TextStyle(color: _orange, fontWeight: FontWeight.w900, fontSize: 24),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: _textLight, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogTile(Map<dynamic, dynamic> log) {
    final bool isAdded = log['type'] == 'added';
    final date = DateTime.parse(log['date']);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isAdded ? _teal : _red).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAdded ? Icons.add_rounded : Icons.remove_rounded,
              color: isAdded ? _teal : _red,
              size: 18,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log['msg'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: _textDark, fontSize: 14)),
                const SizedBox(height: 2),
                Text('By ${log['user']}', style: const TextStyle(color: _textLight, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isAdded ? "+" : "-"}${log['qty']}',
                style: TextStyle(
                  color: isAdded ? _teal : _red,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(DateFormat('dd MMM').format(date), style: const TextStyle(color: _textLight, fontSize: 11)),
              if (!isAdded && log['days'] != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('${log['days']} Days', style: const TextStyle(color: _red, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showMedicinePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Choose Medicine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _tealDark)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _allMedicines.length,
                itemBuilder: (ctx, i) {
                  final med = _allMedicines[i];
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: _teal.withValues(alpha: 0.1), child: const Icon(Icons.medication_rounded, size: 16, color: _teal)),
                    title: Text(med['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${med['type']} • ${med['dose'] ?? 'No Dose'}'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _selectedMed = med;
                        _reportData = null;
                      });
                      _loadReport();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Month picker removed as data is now All-Time
}
