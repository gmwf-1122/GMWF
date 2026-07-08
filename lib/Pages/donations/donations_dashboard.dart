import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:shimmer/shimmer.dart';
import '../../constants/colors.dart';
import 'donations_shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/transaction_card.dart';
import '../../models/donation_models.dart';
import '../../services/donations_local_storage.dart';
import '../../services/local_storage_service.dart';
import 'package:file_picker/file_picker.dart';
import 'widgets/dashboard_premium_overview.dart';
import 'widgets/dashboard_analytics_panel.dart';
import 'widgets/dashboard_empty_state.dart';
import 'donation_pagination_provider.dart';



class DashboardTab extends ConsumerStatefulWidget {
  final String branchId;
  final String username;
  final String branchName;
  final String userId;
  final dynamic col;
  final String today;
  final UserRole role;
  final Future<String> Function() nextReceiptNumber;
  final DonationCategory selectedCategory;
  final ValueChanged<DonationCategory> onCatChanged;
  final VoidCallback onAddTap;
  final Function(double total, double received, double pending, int count)? onStatsChanged;

  const DashboardTab({
    super.key,
    required this.branchId,
    required this.username,
    required this.branchName,
    required this.userId,
    required this.col,
    required this.today,
    required this.role,
    required this.nextReceiptNumber,
    required this.selectedCategory,
    required this.onCatChanged,
    required this.onAddTap,
    this.onStatsChanged,
  });

  @override
  ConsumerState<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<DashboardTab> {
  GmwfSubCategory? _selectedGmwfSub;
  DonationSubtype? _selectedSubtype;

  DateTime? _startDate;
  DateTime? _endDate;
  String _statusFilter = 'All';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchHasFocus = false;
  final ScrollController _scrollController = ScrollController();

  // Advanced filters
  String _paymentMethodFilter = 'All';
  String _entryTypeFilter = 'All';
  double? _minAmount;
  double? _maxAmount;

  // Sort mode: newestFirst (default), oldestFirst, highestAmount, lowestAmount
  String _sortMode = 'newestFirst';


  List<DonationRecord> _currentDonations = [];
  Timer? _searchDebounce;

  // ── Valid items for each dropdown ──────────────────────────────────────────
  static const _statusItems = ['All', 'Pending', 'Received'];
  static const _paymentItems = ['All', 'Cash', 'Bank Transfer', 'Cheque', 'Online'];

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _searchCtrl.addListener(_onSearchChanged);
    DonationsLocalStorage.downloadAllDonations(widget.branchId);
    // Provider will handle data loading; no need for _initStream()
  }

  void _onSearchFocusChanged() {
    setState(() {
      _searchHasFocus = _searchFocusNode.hasFocus;
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        // Local-only filtering already happens in _applyFilters() via setState.
        // No need to hit Firestore again for a text search — just rebuild.
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      DonationsLocalStorage.downloadAllDonations(widget.branchId);
    }
    if (oldWidget.branchId != widget.branchId) {
      // Only re-fetch from the provider (Firestore) when the branch actually
      // changes. Category/role changes are filtered locally in _applyFilters(),
      // so they must NOT trigger a Firestore refresh.
      ref.refresh(donationPaginationFamily(DonationFetchConfig(branchId: widget.branchId)));
    }
  }

  void _initStream() {
    // Legacy stream logic removed.
    ref.refresh(donationPaginationFamily(DonationFetchConfig(branchId: widget.branchId)));
  }

  /// Apply all active client-side filters to the raw donation list.
  List<DonationRecord> _applyFilters(List<DonationRecord> raw) {
    final q = _searchCtrl.text.toLowerCase();
    return raw.where((d) {
      // date range
      if (_startDate != null || _endDate != null) {
        final date = DateTime.tryParse(d.date) ?? DateTime.now();
        final dateOnly = DateTime(date.year, date.month, date.day);
        if (_startDate != null) {
          final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
          if (dateOnly.isBefore(start)) return false;
        }
        if (_endDate != null) {
          final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
          if (dateOnly.isAfter(end)) return false;
        }
      }
      // sync-deleted
      if (d.syncStatus == 'deleted') return false;
      // status
      if (_statusFilter != 'All' && d.status.toLowerCase() != _statusFilter.toLowerCase()) {
        return false;
      }
      // category
      if (widget.selectedCategory != DonationCategory.all &&
          d.categoryId != widget.selectedCategory.name) return false;
      // gmwf sub-category
      if (_selectedGmwfSub != null && d.gmwfSubCategoryId != _selectedGmwfSub!.name) return false;
      // subtype
      if (_selectedSubtype != null && d.subtypeId != _selectedSubtype!.name) return false;
      // search
      if (q.isNotEmpty) {
        final donorMatch = d.donorName.toLowerCase().contains(q);
        final receiptMatch = d.receiptNo.toLowerCase().contains(q);
        final goodsMatch = d.goodsItem?.toLowerCase().contains(q) ?? false;
        if (!donorMatch && !receiptMatch && !goodsMatch) return false;
      }
      // payment method
      if (_paymentMethodFilter != 'All' && d.paymentMethod != _paymentMethodFilter) return false;
      // entry type
      if (_entryTypeFilter != 'All') {
        if (d.isGoods != (_entryTypeFilter == 'Goods Only')) return false;
      }
      // amount range
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      if (_minAmount != null && amt < _minAmount!) return false;
      if (_maxAmount != null && amt > _maxAmount!) return false;
      // role-based visibility
      if (widget.role == UserRole.chairman || widget.role == UserRole.hqManager) return true;
      // Allow records without a collectorId (e.g., imported or anonymous)
      if (d.collectorId == null || d.collectorId!.isEmpty) return true;
      if (d.collectorId == widget.userId) return true;
      if (widget.role == UserRole.manager) return true;
      return false;
    }).toList()
      ..sort((a, b) {
        switch (_sortMode) {
          case 'oldestFirst':
            final c = a.date.compareTo(b.date);
            return c != 0 ? c : a.localId.compareTo(b.localId);
          case 'highestAmount':
            final amtA = a.amount > 0 ? a.amount : (a.probableAmount ?? 0.0);
            final amtB = b.amount > 0 ? b.amount : (b.probableAmount ?? 0.0);
            return amtB.compareTo(amtA);
          case 'lowestAmount':
            final amtA2 = a.amount > 0 ? a.amount : (a.probableAmount ?? 0.0);
            final amtB2 = b.amount > 0 ? b.amount : (b.probableAmount ?? 0.0);
            return amtA2.compareTo(amtB2);
          case 'newestFirst':
          default:
            final c = b.date.compareTo(a.date);
            return c != 0 ? c : b.localId.compareTo(a.localId);
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    // ConsumerStatefulWidget already provides `ref` — no nested Consumer needed.
    final donationState = ref.watch(donationPaginationFamily(DonationFetchConfig(branchId: widget.branchId)));

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >= notification.metrics.maxScrollExtent * 0.8) {
          ref.read(donationPaginationFamily(DonationFetchConfig(branchId: widget.branchId)).notifier).fetchNextPage();
        }
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Header block (overview + filters) ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DashboardPremiumOverview(
                    currentDonations: _currentDonations,
                    branchName: widget.branchName,
                    branchId: widget.branchId,
                    role: widget.role,
                    onAddTap: widget.onAddTap,
                    onExportTap: () => _showExportDialog(context, 'EXCEL'),
                    onSummaryTap: _showAnalyticsDialog,
                    isAnalyticsActive: false,
                    onImportTap: _importDonations,
                  ),
                  const SizedBox(height: 24),
                  _buildSearchAndFilterBar(),
                  _buildActiveFilterChips(),
                  const SizedBox(height: 12),
                  if (widget.branchId == 'all') _buildBranchSummary(),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'TRANSACTIONS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppColors.gray400,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Transaction list (sliver) ─────────────────────────────────────
          donationState.when(
            data: (rawDonations) {
              final donations = _applyFilters(rawDonations);

              // Update stats after frame to avoid setState-during-build.
              // IMPORTANT: only setState when the computed list actually
              // changed — otherwise this runs every single frame forever
              // (setState → rebuild → postFrameCallback → setState → ...).
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                final changed = donations.length != _currentDonations.length ||
                    !listEquals(donations, _currentDonations);

                if (changed) {
                  debugPrint('[Dashboard] raw=${rawDonations.length}, filtered=${donations.length}, _currentDonations=${_currentDonations.length}');
                  setState(() {
                    _currentDonations = donations;
                  });
                }

                double total = 0, received = 0, pending = 0;
                for (final d in donations) {
                  final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
                  total += amt;
                  if (d.status == DonationStatus.received) {
                    received += amt;
                  } else {
                    pending += amt;
                  }
                }
                widget.onStatsChanged?.call(total, received, pending, donations.length);
              });

              if (donations.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: DashboardEmptyState(
                      selectedCategory: widget.selectedCategory,
                      selectedSubtype: _selectedSubtype,
                      selectedGmwfSub: _selectedGmwfSub,
                      isSearchActive: _searchCtrl.text.isNotEmpty,
                      paymentMethodFilter: _paymentMethodFilter,
                      minAmount: _minAmount,
                      maxAmount: _maxAmount,
                      onClearFilters: () {
                        setState(() {
                          _selectedGmwfSub = null;
                          _selectedSubtype = null;
                          _searchCtrl.clear();
                          _paymentMethodFilter = 'All';
                          _entryTypeFilter = 'All';
                          _minAmount = null;
                          _maxAmount = null;
                          _startDate = null;
                          _endDate = null;
                        });
                        widget.onCatChanged(DonationCategory.all);
                      },
                      onAddTap: widget.onAddTap,
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, index) {
                      final donation = donations[index];
                      final prev = index > 0 ? donations[index - 1] : null;
                      final showHeader = prev == null || prev.date != donation.date;
                      final card = TransactionCard(
                        donation: donation,
                        currentUserRole: widget.role,
                        currentUsername: widget.username,
                        onTap: () {},
                      );
                      if (showHeader) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_buildDateHeader(donation.date), card],
                        );
                      }
                      return card;
                    },
                    childCount: donations.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (err, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Error loading donations: $err')),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  void _showAnalyticsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AnalyticsInsightsDialog(
        currentDonations: _currentDonations,
        branchName: widget.branchName,
        role: widget.role,
      ),
    );
  }

  Widget _buildDateHeader(String dateStr) {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayStr =
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    final String label;
    final bool isToday = dateStr == todayStr;
    final bool isYesterday = dateStr == yesterdayStr;

    if (isToday) {
      label = 'TODAY';
    } else if (isYesterday) {
      label = 'YESTERDAY';
    } else {
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();
      label = DateFormat('EEEE, dd MMM yyyy').format(date).toUpperCase();
    }

    final Color badgeColor;
    final Color textColor;
    
    if (isToday) {
      badgeColor = AppColors.primary.withValues(alpha: 0.1);
      textColor = AppColors.primary;
    } else if (isYesterday) {
      badgeColor = AppColors.gray500.withValues(alpha: 0.1);
      textColor = AppColors.gray700;
    } else {
      badgeColor = AppColors.gray200.withValues(alpha: 0.5);
      textColor = AppColors.gray500;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isToday ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: AppColors.gray200.withValues(alpha: 0.6),
              thickness: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // REDESIGNED EXPORT DIALOG — Excel + PDF side by side
  // ════════════════════════════════════════════════════════════════════════════

  void _showExportDialog(BuildContext context, String type) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: _ExportDialog(
          initialType: type,
          onExport: (selectedType, donations) {
            Navigator.pop(ctx);
            _runExport(selectedType, donations);
          },
          currentDonations: _currentDonations,
        ),
      ),
    );
  }

  void _runExport(String type, List<DonationRecord> list) {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data found for the selected range')));
      return;
    }
    if (type == 'EXCEL') {
      _exportToExcel(list);
    } else {
      downloadTransactionsLedgerPdf(list, widget.branchName, context);
    }
  }

  Future<void> _exportToExcel(List<DonationRecord> donations) async {
    final excel = Excel.createExcel();
    final sheet = excel['Donations'];
    excel.delete('Sheet1');

    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Receipt #'),
      TextCellValue('Donor'),
      TextCellValue('Category'),
      TextCellValue('Program'),
      TextCellValue('Type'),
      TextCellValue('Amount'),
      TextCellValue('Method'),
      TextCellValue('Recorded By'),
      TextCellValue('Branch'),
    ]);

    for (var d in donations) {
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      final String cat = d.categoryId;
      final String prog = d.gmwfSubCategoryId ?? '';
      final String sub = d.subtypeId ?? '';
      final bool isGoods = d.isGoods;

      final String finalProgram = (cat.toUpperCase() == 'JAMIA') ? '' : prog;
      final String finalType =
          (cat.toUpperCase() == 'JAMIA') ? sub : (isGoods ? (d.goodsItem ?? '') : sub);
      final String finalMethod = isGoods ? 'GOODS' : d.paymentMethod;

      sheet.appendRow([
        TextCellValue(d.date),
        TextCellValue(d.receiptNo),
        TextCellValue(d.donorName),
        TextCellValue(cat.toUpperCase()),
        TextCellValue(finalProgram),
        TextCellValue(finalType),
        DoubleCellValue(amt),
        TextCellValue(finalMethod),
        TextCellValue(d.recordedBy),
        TextCellValue(d.branchName),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Excel Report',
      fileName:
          'GMWF_Donations_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Report saved to: $outputFile'),
            backgroundColor: Colors.green));
      }
    }
  }

  Future<void> _importDonations() async {
    // Pick JSON file
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Parsed JSON Donations File',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final jsonContent = await file.readAsString();

    List<dynamic> jsonList;
    try {
      jsonList = json.decode(jsonContent) as List<dynamic>;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Invalid JSON file format: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    final total = jsonList.length;
    if (total == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No records found in selected JSON file.'),
          backgroundColor: Colors.orangeAccent,
        ));
      }
      return;
    }

    int imported = 0;
    int skipped = 0;
    String statusMessage = "Checking for existing records...";
    StateSetter? updateDialog;

    // Detect target branch from the JSON data, fallback to current widget branch
    String targetBranchId = widget.branchId;
    String targetBranchName = widget.branchName;
    if (jsonList.isNotEmpty && jsonList.first is Map) {
      final firstRecord = jsonList.first as Map;
      if (firstRecord.containsKey('branchId')) {
        targetBranchId = (firstRecord['branchId']?.toString() ?? widget.branchId).toLowerCase().trim();
      }
      if (firstRecord.containsKey('branchName')) {
        targetBranchName = firstRecord['branchName']?.toString() ?? targetBranchId;
      }
    }

    // Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            updateDialog = setStateDialog;
            final percent = total > 0 ? ((imported + skipped) / total * 100).toStringAsFixed(0) : '0';

            return PopScope(
              canPop: false,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 24),
                        Text(
                          'Importing $targetBranchName Donations',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gray900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: total > 0 ? (imported + skipped) / total : 0,
                          backgroundColor: AppColors.gray100,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Imported: $imported  •  Skipped: $skipped  of  $total',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gray700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          statusMessage,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.gray400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    try {
      final box = DonationsLocalStorage.getBox();
      final keysToDelete = <dynamic>[];
      for (var key in box.keys) {
        final keyStr = key.toString();
        if (keyStr.startsWith('${targetBranchId}_') || 
            keyStr.startsWith('${targetBranchId}__')) {
          keysToDelete.add(key);
        }
      }
      for (var k in keysToDelete) {
        await box.delete(k);
      }
      await box.flush();

      // Also clear branch donations from Firestore to prevent double counting/backfill
      final firestoreSnap = await FirebaseFirestore.instance
          .collection('branches')
          .doc(targetBranchId)
          .collection('donations')
          .get();
      for (final doc in firestoreSnap.docs) {
        await doc.reference.delete();
      }

      final branchCode = LocalStorageService.getBranchCode(targetBranchId);

      for (int i = 0; i < total; i++) {
        final recordMap = Map<String, dynamic>.from(jsonList[i] as Map);
        
        final receiptNoRaw = recordMap['receiptNo']?.toString() ?? '';
        final cleanRcpt = cleanReceiptNumber(receiptNoRaw);
        
        if (DonationsLocalStorage.isReceiptNoDuplicate(cleanRcpt)) {
          skipped++;
          continue;
        }
        
        final dateVal = recordMap['date']?.toString() ?? '';
        
        // Generate unique localId
        final sheetName = recordMap['notes']?.toString().split('sheet: ').last.split('.').first ?? 'unknown';
        final localId = "import_${branchCode}_${sheetName.toLowerCase().trim()}_${cleanRcpt.replaceAll(RegExp(r'\D'), '')}_$i";
        recordMap['localId'] = localId;
        imported++;

        // Perform save (updates existing or inserts new)
        await DonationsLocalStorage.saveDonation(
          branchId: targetBranchId,
          data: recordMap,
        );

        if (i % 25 == 0 || i == total - 1) {
          updateDialog?.call(() {
            statusMessage = "Saving receipt: $cleanRcpt";
          });
          // Yield to UI thread to paint the progress update
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
    } catch (e) {
      debugPrint("Import Error: $e");
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss progress dialog safely
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import complete! Processed $total records: $imported new, $skipped updated/overwritten in $targetBranchName branch.'),
          backgroundColor: Colors.green,
        ));
        setState(() {
          _initStream();
        });
      }
    }
  }

  void _showSyncProgress(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 24),
                Text(message,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                const Text('Communicating with Firestore...',
                    style: TextStyle(
                        color: AppColors.gray500, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    final bool hasFilters = _paymentMethodFilter != 'All' ||
        _minAmount != null ||
        _maxAmount != null ||
        _startDate != null ||
        _endDate != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _searchHasFocus
                      ? const Color(0xFF0D5C3A) // Emerald focus color
                      : const Color(0x0A000000),
                  width: _searchHasFocus ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _searchHasFocus
                        ? const Color(0xFF0D5C3A).withValues(alpha: 0.08) // Soft glowing green focus shadow
                        : Colors.black.withValues(alpha: 0.02),
                    blurRadius: _searchHasFocus ? 12 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search by donor, receipt #, or goods...',
                  hintStyle: const TextStyle(
                      fontSize: 14, color: AppColors.gray400),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.gray400, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              size: 18, color: AppColors.gray400),
                          onPressed: () => _searchCtrl.clear())
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          _HeaderActionButton(
            onTap: _showAdvancedFilterDialog,
            hasFilters: hasFilters,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasFilters
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.gray100,
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 14,
                    color: hasFilters ? AppColors.primary : AppColors.gray600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: hasFilters ? AppColors.primary : AppColors.gray700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HeaderActionButton(
            onTap: _showSortDialog,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gray100,
                  ),
                  child: const Icon(
                    Icons.swap_vert_rounded,
                    size: 14,
                    color: AppColors.gray600,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Sort',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.gray700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.gray300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            const Text('Sort By',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gray900)),
            const SizedBox(height: 16),
            _sortOption(Icons.arrow_downward_rounded, 'Newest First',
                () { setState(() => _sortMode = 'newestFirst'); Navigator.pop(context); }, isActive: _sortMode == 'newestFirst'),
            _sortOption(Icons.arrow_upward_rounded, 'Oldest First',
                () { setState(() => _sortMode = 'oldestFirst'); Navigator.pop(context); }, isActive: _sortMode == 'oldestFirst'),
            _sortOption(Icons.attach_money_rounded, 'Highest Amount',
                () { setState(() => _sortMode = 'highestAmount'); Navigator.pop(context); }, isActive: _sortMode == 'highestAmount'),
            _sortOption(Icons.money_off_rounded, 'Lowest Amount',
                () { setState(() => _sortMode = 'lowestAmount'); Navigator.pop(context); }, isActive: _sortMode == 'lowestAmount'),
          ],
        ),
      ),
    );
  }

  Widget _sortOption(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isActive ? AppColors.primary : AppColors.gray500),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      color: isActive ? AppColors.primary : AppColors.gray800)),
            ),
            if (isActive)
              const Icon(Icons.check_rounded, size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  void _showAdvancedFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Filter Records',
              style: TextStyle(fontWeight: FontWeight.w900)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Date Range',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gray500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final range = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      initialDateRange: _startDate != null && _endDate != null
                          ? DateTimeRange(
                              start: _startDate!, end: _endDate!)
                          : null,
                    );
                    if (range != null) {
                      setLocalState(() {
                        _startDate = range.start;
                        _endDate = range.end;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border.all(color: AppColors.gray200),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: AppColors.gray600),
                      const SizedBox(width: 8),
                      Text(
                        _startDate != null
                            ? '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}'
                            : 'Select Dates',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Category',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gray500)),
                const SizedBox(height: 8),
                // ── FIX: safe dropdown with validated value ────────────────
                _dropdownFilter(
                  value: _safeDropdownValue(
                    widget.selectedCategory.name,
                    DonationCategory.values.map((c) => c.name).toList(),
                    DonationCategory.all.name,
                  ),
                  items: DonationCategory.values.map((c) => c.name).toList(),
                  labels: DonationCategory.values.map((c) => c.label).toList(),
                  onChanged: (cat) {
                    if (cat != null) {
                      final category = DonationCategory.values
                          .firstWhere((e) => e.name == cat);
                      setLocalState(() => widget.onCatChanged(category));
                    }
                  },
                ),
                const SizedBox(height: 20),
                const Text('Status',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gray500)),
                const SizedBox(height: 8),
                // ── FIX: safe dropdown ─────────────────────────────────────
                _dropdownFilter(
                  value: _safeDropdownValue(
                      _statusFilter, _statusItems, 'All'),
                  items: _statusItems,
                  onChanged: (v) =>
                      setLocalState(() => _statusFilter = v!),
                ),
                const SizedBox(height: 20),
                const Text('Payment Method',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gray500)),
                const SizedBox(height: 8),
                // ── FIX: safe dropdown ─────────────────────────────────────
                _dropdownFilter(
                  value: _safeDropdownValue(
                      _paymentMethodFilter, _paymentItems, 'All'),
                  items: _paymentItems,
                  onChanged: (v) =>
                      setLocalState(() => _paymentMethodFilter = v!),
                ),
                const SizedBox(height: 20),
                const Text('Donation Entry Type',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gray500)),
                const SizedBox(height: 8),
                _dropdownFilter(
                  value: _safeDropdownValue(
                      _entryTypeFilter, const ['All', 'Cash Only', 'Goods Only'], 'All'),
                  items: const ['All', 'Cash Only', 'Goods Only'],
                  onChanged: (v) =>
                      setLocalState(() => _entryTypeFilter = v!),
                ),
                const SizedBox(height: 20),
                const Text('Amount Range (PKR)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gray500)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Min',
                            isDense: true,
                            border: OutlineInputBorder()),
                        onChanged: (v) => _minAmount = double.tryParse(v),
                        controller: TextEditingController(
                            text: _minAmount?.toString() ?? ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Max',
                            isDense: true,
                            border: OutlineInputBorder()),
                        onChanged: (v) => _maxAmount = double.tryParse(v),
                        controller: TextEditingController(
                            text: _maxAmount?.toString() ?? ''),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                  _statusFilter = 'All';
                  _paymentMethodFilter = 'All';
                  _entryTypeFilter = 'All';
                  _minAmount = null;
                  _maxAmount = null;
                  widget.onCatChanged(DonationCategory.all);
                });
                Navigator.pop(ctx);
              },
              child:
                  const Text('Reset', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  /// Ensures [value] is one of [validItems]; falls back to [fallback].
  /// This prevents the DropdownButton assertion crash.
  String _safeDropdownValue(
      String value, List<String> validItems, String fallback) {
    return validItems.contains(value) ? value : fallback;
  }


  Widget _buildActiveFilterChips() {
    final List<Widget> chips = [];
    if (_startDate != null) {
      chips.add(_activeChip('Dates', () => setState(() {
            _startDate = null;
            _endDate = null;
          })));
    }
    if (widget.selectedCategory != DonationCategory.all) {
      chips.add(_activeChip(widget.selectedCategory.label,
          () => setState(() {
                widget.onCatChanged(DonationCategory.all);
              })));
    }
    if (_statusFilter != 'All') {
      chips.add(_activeChip(_statusFilter, () => setState(() {
            _statusFilter = 'All';
          })));
    }
    if (_paymentMethodFilter != 'All') {
      chips.add(_activeChip(_paymentMethodFilter, () => setState(() {
            _paymentMethodFilter = 'All';
          })));
    }
    if (_minAmount != null || _maxAmount != null) {
      chips.add(_activeChip('Amount Range', () => setState(() {
            _minAmount = null;
            _maxAmount = null;
          })));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: chips,
      ),
    );
  }

  Widget _activeChip(String label, VoidCallback onClear) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(width: 4),
          InkWell(
              onTap: onClear,
              child: const Icon(Icons.close_rounded,
                  size: 14, color: AppColors.primary)),
        ],
      ),
    );
  }

  Widget _dropdownFilter({
    required String value,
    required List<String> items,
    List<String>? labels,
    required void Function(String?) onChanged,
  }) {
    // Guard: if value not in items, fall back to first item
    final safeValue = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.gray200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded),
          style: const TextStyle(fontSize: 14, color: AppColors.gray900),
          onChanged: onChanged,
          items: List.generate(
              items.length,
              (i) => DropdownMenuItem(
                    value: items[i],
                    child: Text(labels != null ? labels[i] : items[i]),
                  )),
        ),
      ),
    );
  }

  Widget _buildBranchSummary() {
    final Map<String, ({double received, double pending, int count})> branchData = {};
    
    for (var d in _currentDonations) {
      final amt = d.amount > 0 ? d.amount : (d.probableAmount ?? 0.0);
      final isRec = d.status.toLowerCase() == 'received';
      
      final current = branchData[d.branchName] ?? (received: 0.0, pending: 0.0, count: 0);
      branchData[d.branchName] = (
        received: current.received + (isRec ? amt : 0),
        pending: current.pending + (!isRec ? amt : 0),
        count: current.count + 1,
      );
    }

    if (branchData.isEmpty) return const SizedBox.shrink();

    final sortedBranches = branchData.entries.toList()..sort((a, b) => (b.value.received + b.value.pending).compareTo(a.value.received + a.value.pending));

    return Container(
      margin: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('BRANCH PERFORMANCE SUMMARY',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gray400,
                    letterSpacing: 1.2)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sortedBranches.length,
              itemBuilder: (context, index) {
                final entry = sortedBranches[index];
                final data = entry.value;
                return Container(
                  width: 240,
                  margin: EdgeInsets.only(right: 16, left: index == 0 ? 4 : 0),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.gray200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.business_rounded, size: 16, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(entry.key.toUpperCase(),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.gray900),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _SummaryRow(label: 'Received', value: data.received, color: AppColors.primary, isBold: true),
                      const SizedBox(height: 10),
                      _SummaryRow(label: 'Pending', value: data.pending, color: Colors.orange, isBold: false),
                      const Divider(height: 24, color: AppColors.gray100),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${data.count} entries', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.gray400)),
                          Text('PKR ${NumberFormat('#,###').format(data.received + data.pending)}', 
                              style: GoogleFonts.dmMono(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.gray900)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _SummaryRow({required String label, required double value, required Color color, required bool isBold}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.gray500, fontWeight: FontWeight.w500)),
        Text('PKR ${NumberFormat('#,###').format(value)}', 
            style: GoogleFonts.dmMono(
              fontSize: 12, 
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700, 
              color: isBold ? color : AppColors.gray700,
            )),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// REDESIGNED EXPORT DIALOG WIDGET
// ════════════════════════════════════════════════════════════════════════════════

class _ExportDialog extends StatefulWidget {
  final String initialType;
  final void Function(String type, List<DonationRecord> donations) onExport;
  final List<DonationRecord> currentDonations;

  const _ExportDialog({
    required this.initialType,
    required this.onExport,
    required this.currentDonations,
  });

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late String _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
  }

  // ── Date range options ──────────────────────────────────────────────────────
  static const _ranges = [
    _RangeOption(
        id: 'today',
        label: "Today's Data",
        sublabel: 'Only today\'s transactions',
        icon: Icons.today_rounded),
    _RangeOption(
        id: 'specific',
        label: 'Specific Date',
        sublabel: 'Pick a single date',
        icon: Icons.event_rounded),
    _RangeOption(
        id: 'range',
        label: 'Date Range',
        sublabel: 'Start date to end date',
        icon: Icons.date_range_rounded),
    _RangeOption(
        id: 'all',
        label: 'All Time',
        sublabel: 'Complete history',
        icon: Icons.all_inclusive_rounded),
  ];

  Future<void> _handleRange(_RangeOption opt) async {
    List<DonationRecord>? list;

    switch (opt.id) {
      case 'today':
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        list = widget.currentDonations.where((d) => d.date == today).toList();
        break;

      case 'specific':
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (date == null || !mounted) return;
        final ds = DateFormat('yyyy-MM-dd').format(date);
        list = widget.currentDonations.where((d) => d.date == ds).toList();
        break;

      case 'range':
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (range == null || !mounted) return;
        list = widget.currentDonations.where((d) {
          final dt = DateTime.tryParse(d.date) ?? DateTime.now();
          return dt.isAfter(range.start.subtract(const Duration(days: 1))) &&
              dt.isBefore(range.end.add(const Duration(days: 1)));
        }).toList();
        break;

      case 'all':
      default:
        list = widget.currentDonations;
        break;
    }

    widget.onExport(_selectedType, list);
    }

  @override
  Widget build(BuildContext context) {
    const excelColor = Color(0xFF217346);
    const pdfColor = Color(0xFFC62828);

    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 40,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                  bottom:
                      BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_selectedType == 'EXCEL' ? excelColor : pdfColor)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _selectedType == 'EXCEL'
                        ? Icons.table_view_rounded
                        : Icons.picture_as_pdf_rounded,
                    color:
                        _selectedType == 'EXCEL' ? excelColor : pdfColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Export Report',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.4)),
                      const SizedBox(height: 2),
                      Text(
                        _selectedType == 'EXCEL'
                            ? 'Exports as .xlsx spreadsheet'
                            : 'Exports as printable PDF',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF94A3B8), size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFE2E8F0),
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Format toggle ──────────────────────────────────────────
                const Text('FORMAT',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _formatToggleBtn(
                        label: 'Excel',
                        icon: Icons.table_view_rounded,
                        color: excelColor,
                        isSelected: _selectedType == 'EXCEL',
                        onTap: () => setState(() => _selectedType = 'EXCEL'),
                      ),
                      const SizedBox(width: 4),
                      _formatToggleBtn(
                        label: 'PDF',
                        icon: Icons.picture_as_pdf_rounded,
                        color: pdfColor,
                        isSelected: _selectedType == 'PDF',
                        onTap: () => setState(() => _selectedType = 'PDF'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Date range options ─────────────────────────────────────
                const Text('DATE RANGE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.8,
                  children: _ranges
                      .map((opt) => _rangeCard(opt))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatToggleBtn({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected ? color : const Color(0xFF94A3B8)),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? color : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rangeCard(_RangeOption opt) {
    final activeColor =
        _selectedType == 'EXCEL' ? const Color(0xFF217346) : const Color(0xFFC62828);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleRange(opt),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(opt.icon, size: 15, color: activeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(opt.label,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B))),
                    Text(opt.sublabel,
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF94A3B8)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 11, color: Color(0xFFCBD5E1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeOption {
  final String id;
  final String label;
  final String sublabel;
  final IconData icon;
  const _RangeOption({
    required this.id,
    required this.label,
    required this.sublabel,
    required this.icon,
  });
}

class _HeaderActionButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final bool hasFilters;
  final bool isActive;

  const _HeaderActionButton({
    required this.onTap,
    required this.child,
    this.hasFilters = false,
    this.isActive = false,
  });

  @override
  State<_HeaderActionButton> createState() => _HeaderActionButtonState();
}

class _HeaderActionButtonState extends State<_HeaderActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hasFilters = widget.hasFilters;
    final isActive = widget.isActive;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: ScaleButton(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: hasFilters || isActive
                  ? AppColors.primary.withValues(alpha: _isHovered ? 0.10 : 0.06)
                  : (_isHovered ? AppColors.gray50 : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasFilters || isActive
                    ? AppColors.primary
                    : (_isHovered ? AppColors.gray300 : const Color(0x0A000000)),
                width: hasFilters || isActive || _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: [
                if (hasFilters || isActive)
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: _isHovered ? 0.20 : 0.15),
                    blurRadius: _isHovered ? 14 : 10,
                    offset: _isHovered ? const Offset(0, 6) : const Offset(0, 4),
                  )
                else
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isHovered ? 0.04 : 0.02),
                    blurRadius: _isHovered ? 10 : 6,
                    offset: _isHovered ? const Offset(0, 4) : const Offset(0, 2),
                  ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}