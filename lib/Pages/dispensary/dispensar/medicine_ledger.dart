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
  final bool isEmbedded;

  const MedicineLedgerPage({
    super.key,
    required this.branchId,
    this.initialMedicine,
    this.isEmbedded = false,
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
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedMed = widget.initialMedicine;
    _initData();
  }

  Future<void> _initData() async {
    await _loadMedicines();
    _loadReport();
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
    final monthStr = DateFormat('yyyy-MM').format(_selectedMonth);
    if (_selectedMed == null) {
      return '${widget.branchId}_all_meds_$monthStr';
    }
    final medId = _selectedMed!['id'] ?? _selectedMed!['docId'] ?? _selectedMed!['medicineId'] ?? _selectedMed!['name'];
    return '${widget.branchId}_${medId}_$monthStr';
  }

  Future<void> _loadReport({bool forceRecalculate = false}) async {
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
      final medId = _selectedMed != null ? (_selectedMed!['id'] ?? _selectedMed!['docId'] ?? '') : '';
      final selectedType = _selectedMed != null ? (_selectedMed!['type'] ?? '').toString().toLowerCase() : '';
      final isSelectedMedSyringe = _selectedMed != null ? selectedType.contains('syringe') : false;
      final selectedYear = _selectedMonth.year;
      final selectedMonthVal = _selectedMonth.month;

      // 1. Query Logs (Additions, Registrations, Edits) from inventory_log (All-Time and filter in memory)
      final List<Future<QuerySnapshot>> logQueries = [];
      if (_selectedMed != null) {
        if (medId.isNotEmpty) {
          logQueries.add(FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory_log')
              .where('medicineId', isEqualTo: medId)
              .get());
          logQueries.add(FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory_log')
              .where('docId', isEqualTo: medId)
              .get());
          logQueries.add(FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory_log')
              .where('newId', isEqualTo: medId)
              .get());
          logQueries.add(FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory_log')
              .where('oldId', isEqualTo: medId)
              .get());
        } else {
          logQueries.add(FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory_log')
              .where('medicineName', isEqualTo: _selectedMed!['name'])
              .get());
        }
      } else {
        // Query all logs when no specific medicine is selected
        logQueries.add(FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory_log')
            .get());
      }

      final snapshots = await Future.wait(logQueries);
      final Map<String, DocumentSnapshot> uniqueDocs = {};
      for (final snap in snapshots) {
        for (final doc in snap.docs) {
          uniqueDocs[doc.id] = doc;
        }
      }

      double totalAdded = 0;
      double totalAdjusted = 0; // Absolute value of manual edits
      List<Map<String, dynamic>> logs = [];

      for (final doc in uniqueDocs.values) {
        final d = doc.data() as Map<String, dynamic>;
        final q = d['quantityAdded'];
        final qty = (q is num ? q.toDouble() : double.tryParse(q?.toString() ?? '') ?? 0.0);
        final ts = (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        final action = d['action'] ?? '';
        final medName = d['medicineName'] ?? d['name'] ?? 'Unknown Medicine';
        
        // Only include inventory logs matching the selected month
        if (ts.year == selectedYear && ts.month == selectedMonthVal) {
          if (action == 'edit_stock' || action == 'medicine_edited') {
            totalAdjusted += qty;
            logs.add({
              'type': qty >= 0 ? 'added' : 'removed',
              'qty': qty.abs(),
              'date': ts,
              'user': d['performedByName'] ?? d['performedBy'] ?? 'Admin',
              'msg': '${action == 'medicine_edited' ? 'Medicine Edited' : 'Manual Adjustment'} ($medName)',
              'medicineName': medName,
            });
          } else {
            totalAdded += qty;
            logs.add({
              'type': 'added',
              'qty': qty,
              'date': ts,
              'user': d['performedByName'] ?? d['performedBy'] ?? 'Unknown',
              'msg': '${(action == 'medicine_registered_directly' || action == 'medicine_registered') ? 'Initial Registration' : 'Restock'} ($medName)',
              'medicineName': medName,
            });
          }
        }
      }

      // Determine days to fetch in the selected month
      final List<DateTime> daysToFetch = [];
      DateTime start = DateTime(selectedYear, selectedMonthVal, 1);
      DateTime end = DateTime(selectedYear, selectedMonthVal + 1, 1).subtract(const Duration(seconds: 1));
      final today = DateTime.now();
      if (end.isAfter(today)) {
        end = today;
      }
      for (DateTime curr = start; curr.isBefore(end.add(const Duration(seconds: 1))); curr = curr.add(const Duration(days: 1))) {
        daysToFetch.add(curr);
      }

      // 2. Query Removals (Dispensing) over the selected month
      double totalRemoved = 0;

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
              
              bool isMatch = false;
              final rxName = rx['name'] ?? '';
              
              if (_selectedMed != null) {
                // Check inventoryId first, fallback to name matching
                final String rxId = (rx['inventoryId'] ?? rx['medicineId'] ?? rx['id'] ?? '').toString();
                if (medId.isNotEmpty && rxId.isNotEmpty && rxId == medId) {
                  isMatch = true;
                } else {
                  final nameMatch = rx['name'] == _selectedMed!['name'];
                  final typeMatch = rx['type'] == _selectedMed!['type'];
                  final doseMatch = rx['dose'] == _selectedMed!['dose'];
                  isMatch = nameMatch && typeMatch && doseMatch;
                }
              } else {
                // If no specific medicine is selected, match all
                isMatch = true;
              }

              if (isMatch) {
                final dQty = d['daysOfMedicine'];
                final days = (dQty is num ? dQty.toDouble() : double.tryParse(dQty?.toString() ?? '') ?? 1.0);
                final perDayRaw = rx['quantity'] ?? rx['qty'] ?? 0;
                final perDay = perDayRaw is num ? perDayRaw.toDouble() : double.tryParse(perDayRaw.toString()) ?? 0.0;
                
                final isInj = (rx['type']?.toString().toLowerCase().contains('injection') ?? false) || 
                              (rx['type']?.toString().toLowerCase().contains('drip') ?? false);
                
                final qty = isInj ? perDay : (perDay * days);
                dayTotalRemoved += qty;

                final patientName = d['patientName'] ?? d['name'] ?? 'Unknown Patient';
                final patientCnic = d['patientCnic'] ?? d['cnic'] ?? '';
                final age = d['patientAge'] ?? d['age'] ?? '';
                final gender = d['patientGender'] ?? d['gender'] ?? '';

                final dispensedAtStr = d['dispensedAt']?.toString() ?? d['createdAt']?.toString();
                DateTime logDate = curr;
                if (dispensedAtStr != null) {
                  final parsed = DateTime.tryParse(dispensedAtStr);
                  if (parsed != null) {
                    logDate = parsed.toLocal();
                  }
                }

                dayLogs.add({
                  'type': 'removed',
                  'qty': qty,
                  'date': logDate,
                  'user': d['dispenserName'] ?? 'Unknown',
                  'msg': 'Dispensed',
                  'medicineName': rxName,
                  'patientName': patientName,
                  'patientCnic': patientCnic,
                  'age': age,
                  'gender': gender,
                  'serial': d['serial'] ?? '',
                  'days': days.toInt(),
                });
              } else if (_selectedMed != null && isSelectedMedSyringe) {
                final typeStr = rx['type']?.toString().toLowerCase() ?? '';
                final isInjOrDrip = typeStr.contains('injection') || typeStr.contains('drip');
                final isRxSyringe = typeStr.contains('syringe');
                if (isInjOrDrip && !isRxSyringe) {
                  final perDayRaw = rx['quantity'] ?? rx['qty'] ?? 1;
                  final perDay = perDayRaw is num ? perDayRaw.toDouble() : double.tryParse(perDayRaw.toString()) ?? 1.0;
                  dayTotalRemoved += perDay;

                  final patientName = d['patientName'] ?? d['name'] ?? 'Unknown Patient';
                  final patientCnic = d['patientCnic'] ?? d['cnic'] ?? '';
                  final age = d['patientAge'] ?? d['age'] ?? '';
                  final gender = d['patientGender'] ?? d['gender'] ?? '';

                  final dispensedAtStr = d['dispensedAt']?.toString() ?? d['createdAt']?.toString();
                  DateTime logDate = curr;
                  if (dispensedAtStr != null) {
                    final parsed = DateTime.tryParse(dispensedAtStr);
                    if (parsed != null) {
                      logDate = parsed.toLocal();
                    }
                  }

                  dayLogs.add({
                    'type': 'removed',
                    'qty': perDay,
                    'date': logDate,
                    'user': d['dispenserName'] ?? 'Unknown',
                    'msg': 'Auto-deducted Syringe (Token: ${d['serial']})',
                    'medicineName': rxName,
                    'patientName': patientName,
                    'patientCnic': patientCnic,
                    'age': age,
                    'gender': gender,
                    'serial': d['serial'] ?? '',
                    'days': 1,
                  });
                }
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
      double currentStock = 0;
      if (_selectedMed != null) {
        final smQty = _selectedMed!['quantity'];
        currentStock = (smQty is num ? smQty.toDouble() : double.tryParse(smQty?.toString() ?? '') ?? 0.0);
      } else {
        for (final med in _allMedicines) {
          final smQty = med['quantity'];
          currentStock += (smQty is num ? smQty.toDouble() : double.tryParse(smQty?.toString() ?? '') ?? 0.0);
        }
      }

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
        'month': DateFormat('MMMM yyyy').format(_selectedMonth),
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
          if (!widget.isEmbedded)
            _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildFilters()),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: _teal)))
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
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: _teal),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                    _reportData = null;
                  });
                  _loadReport();
                },
              ),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedMonth,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDatePickerMode: DatePickerMode.year,
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedMonth = DateTime(picked.year, picked.month);
                        _reportData = null;
                      });
                      _loadReport();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _teal.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _teal.withValues(alpha: 0.1)),
                    ),
                    child: Text(
                      DateFormat('MMMM yyyy').format(_selectedMonth),
                      style: const TextStyle(color: _tealDark, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: _teal),
                onPressed: _selectedMonth.year == DateTime.now().year && _selectedMonth.month == DateTime.now().month
                    ? null
                    : () {
                        setState(() {
                          _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                          _reportData = null;
                        });
                        _loadReport();
                      },
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

  Widget _buildConsolidatedBreakdown(Map<String, dynamic> report) {
    if (_selectedMed != null) return const SizedBox.shrink();

    final logs = (report['logs'] as List?) ?? [];
    
    // Group by medicine name
    final Map<String, Map<String, dynamic>> groups = {};
    for (final l in logs) {
      final name = l['medicineName']?.toString() ?? 'Unknown Medicine';
      final type = l['type']?.toString() ?? 'removed';
      final qty = (l['qty'] as num?)?.toDouble() ?? 0.0;
      final patientId = l['patientCnic'] ?? l['patientName'] ?? '';
      
      groups.putIfAbsent(name, () => {
        'added': 0.0,
        'removed': 0.0,
        'patients': <String>{},
      });
      
      if (type == 'added') {
        groups[name]!['added'] = (groups[name]!['added'] as double) + qty;
      } else {
        groups[name]!['removed'] = (groups[name]!['removed'] as double) + qty;
        if (patientId.toString().isNotEmpty) {
          (groups[name]!['patients'] as Set<String>).add(patientId.toString());
        }
      }
    }

    if (groups.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: const Icon(Icons.analytics_rounded, color: _teal),
          title: const Text(
            'Medicine Breakdown Summary',
            style: TextStyle(fontWeight: FontWeight.bold, color: _tealDark, fontSize: 15),
          ),
          subtitle: Text('${groups.length} medicines moved this month'),
          children: [
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final name = groups.keys.elementAt(index);
                final counts = groups[name]!;
                final added = counts['added'] as double;
                final removed = counts['removed'] as double;
                final patientSet = counts['patients'] as Set<String>;
                final net = added - removed;

                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: _textDark, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (added > 0)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _teal.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '+${added.toStringAsFixed(0)} units',
                                    style: const TextStyle(color: _teal, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              if (removed > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '-${removed.toStringAsFixed(0)} units (${patientSet.length} patient${patientSet.length == 1 ? '' : 's'})',
                                    style: const TextStyle(color: _red, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          net >= 0 ? '+${net.toStringAsFixed(0)}' : net.toStringAsFixed(0),
                          style: TextStyle(
                            color: net >= 0 ? _teal : _red,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const Text('Net change', style: TextStyle(color: _textLight, fontSize: 10)),
                      ],
                    ),
                  ],
                );
              },
            ),
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
        _buildConsolidatedBreakdown(report),
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
          ...logs.map((log) => _buildLogTile(log)),
        const SizedBox(height: 100), // Space for FAB
      ]),
    );
  }

  Widget _buildSummaryCards(Map<String, dynamic> report) {
    final ta = report['totalAdded'];
    final added = (ta is num ? ta.toDouble() : double.tryParse(ta?.toString() ?? '') ?? 0.0);
    final tr = report['totalRemoved'];
    final removed = (tr is num ? tr.toDouble() : double.tryParse(tr?.toString() ?? '') ?? 0.0);
    final net = added - removed;
    final tAdj = report['totalAdjusted'];
    final adjusted = (tAdj is num ? tAdj.toDouble() : double.tryParse(tAdj?.toString() ?? '') ?? 0.0);

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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(
                  isAdded 
                      ? (log['msg'] ?? '') 
                      : 'Dispensed ${log['medicineName'] ?? ''} to ${log['patientName'] ?? 'Unknown Patient'}', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _textDark, fontSize: 14),
                ),
                const SizedBox(height: 4),
                if (!isAdded) ...[
                  if (log['patientCnic'] != null && log['patientCnic'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('CNIC: ${log['patientCnic']}', style: const TextStyle(color: _textLight, fontSize: 11)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'Token: ${log['serial']} • Age: ${log['age']} • Gender: ${log['gender']}',
                      style: const TextStyle(color: _textLight, fontSize: 11),
                    ),
                  ),
                ],
                Text(
                  isAdded ? 'By ${log['user']}' : 'Dispenser: ${log['user']}', 
                  style: const TextStyle(color: _textLight, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
              Text(DateFormat('dd MMM hh:mm a').format(date), style: const TextStyle(color: _textLight, fontSize: 11)),
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
                itemCount: _allMedicines.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _teal.withValues(alpha: 0.1),
                        child: const Icon(Icons.apps_rounded, size: 16, color: _teal),
                      ),
                      title: const Text('All Medicines', style: TextStyle(fontWeight: FontWeight.bold, color: _tealDark)),
                      subtitle: const Text('Show ledger for all stock items'),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _selectedMed = null;
                          _reportData = null;
                        });
                        _loadReport();
                      },
                    );
                  }
                  final med = _allMedicines[i - 1];
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
