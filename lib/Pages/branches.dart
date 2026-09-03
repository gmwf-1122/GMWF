// lib/pages/branches.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/camp_session_service.dart';
import '../services/user_theme_service.dart';
import '../providers/branches_providers.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';

import 'dispensary/dispensar/inventory.dart';
import 'office/finance_page.dart';
import 'branches_register.dart';
import 'dispensary/patient_detail_screen.dart';
import 'settings/biometric_device_manager_page.dart';
import '../services/local_storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _resolvePatientCampLabel(Map<String, dynamic> p, String branchId) {
  final parts = <String>[];

  // 1. Resolve Camp / Facility
  final cId = (p['dispensaryId'] ?? p['campId'] ?? p['subDispensaryId'])?.toString().trim();
  if (cId != null && cId.isNotEmpty && cId != 'all' && cId != 'main') {
    parts.add(CampSessionService.getCampLabel(cId));
  } else {
    final serial = (p['serial'] ?? p['id'] ?? '').toString();
    final sParts = serial.split('-');
    if (sParts.length > 2) {
      final tag = sParts[1].toUpperCase();
      if (tag == 'SADD' || tag == 'SAD' || tag == 'SADDAR' || tag == 'KAP' || tag == 'KAPAYYA') {
        parts.add('Saddar Dispensary');
      } else if (tag == 'HC' || tag == 'HAJI' || tag == 'HAJICAMP') {
        parts.add('Haji Camp Dispensary');
      } else if (tag == 'GRT' || tag == 'GJT') {
        parts.add('Gujrat Main');
      } else if (tag.isNotEmpty) {
        parts.add(tag);
      }
    }
  }

  // 2. Resolve Shift / Session
  final sess = (p['session'] ?? p['shift'] ?? p['campSession'])?.toString().toLowerCase().trim();
  if (sess == 'morning') {
    parts.add('🌅 Morning');
  } else if (sess == 'evening') {
    parts.add('🌆 Evening');
  } else if (sess == 'night') {
    parts.add('🌙 Night');
  } else if (sess != null && sess.isNotEmpty && sess != 'day' && sess != 'all') {
    parts.add(sess[0].toUpperCase() + sess.substring(1));
  } else {
    final dispAt = p['dispensedAt'] ?? p['createdAt'] ?? p['time'];
    DateTime? dt;
    if (dispAt is DateTime) {
      dt = dispAt;
    } else if (dispAt is String) {
      dt = DateTime.tryParse(dispAt);
    }
    if (dt != null) {
      if (dt.hour >= 6 && dt.hour < 14) {
        parts.add('🌅 Morning');
      } else if (dt.hour >= 14 && dt.hour < 22) {
        parts.add('🌆 Evening');
      } else {
        parts.add('🌙 Night');
      }
    }
  }

  if (parts.isEmpty) {
    final bName = branchId.isNotEmpty ? branchId[0].toUpperCase() + branchId.substring(1) : 'Main';
    parts.add('$bName Facility');
  }

  return parts.join(' • ');
}

String _formatCnic(String raw) {
  final clean = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.length == 13) {
    return '${clean.substring(0, 5)}-${clean.substring(5, 12)}-${clean.substring(12)}';
  }
  return raw;
}

// ─────────────────────────────────────────────────────────────────────────────
// Branches Main Widget
// ─────────────────────────────────────────────────────────────────────────────

class Branches extends ConsumerStatefulWidget {
  final bool showRegisterButton;
  final String? branchId;
  final bool? isManager;
  final String? initialBranchId;
  final bool? flagReverted;

  const Branches({
    super.key,
    this.showRegisterButton = true,
    this.branchId,
    this.isManager,
    this.initialBranchId,
    this.flagReverted,
  });

  @override
  ConsumerState<Branches> createState() => _BranchesState();
}

class _BranchesState extends ConsumerState<Branches> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _recordStage(Map<String, dynamic> record) {
    final status = (record['status'] ?? '').toString().toLowerCase().trim();
    final dispenseStatus = (record['dispenseStatus'] ?? '').toString().toLowerCase().trim();

    if (status == 'dispensed' || dispenseStatus == 'dispensed' || record['dispensedAt'] != null) {
      return 'dispensed';
    }
    if (status == 'prescribed' ||
        status == 'completed' ||
        status == 'waiting_for_dispense' ||
        status == 'waiting_to_dispense' ||
        dispenseStatus == 'waiting_for_dispense' ||
        dispenseStatus == 'waiting_to_dispense' ||
        dispenseStatus == 'waiting') {
      return 'waiting_dispensary';
    }
    return 'waiting_doctor';
  }

  int _compareRecords(Map<String, dynamic> left, Map<String, dynamic> right) {
    String valueOf(Map<String, dynamic> record) {
      switch (_sortField) {
        case 'name':
          return (record['name'] ?? record['patientName'] ?? '').toString().toLowerCase();
        case 'status':
          return _recordStage(record);
        case 'type':
          return (record['type'] ?? record['queueType'] ?? '').toString().toLowerCase();
        case 'facility':
          return (record['campId'] ?? record['dispensaryId'] ?? record['dispensaryTag'] ?? '').toString().toLowerCase();
        case 'token':
        default:
          return (record['serial'] ?? record['id'] ?? '').toString().toLowerCase();
      }
    }

    final result = valueOf(left).compareTo(valueOf(right));
    return _sortAscending ? result : -result;
  }

  String? _selectedBranchId;
  String _selectedBranchName = 'Branch';
  String _searchQuery = '';
  String _sortField = 'token';
  bool _sortAscending = true;
  int _currentPage = 1;
  int _rowsPerPage = 10;
  String _chartRange = '7d'; // '7d', '14d', '30d', 'month'
  String _selectedCampFilter = 'all'; // 'all', 'haji', 'saddar'
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic> _computeRealPerformanceData(String branchId, String range) {
    int numDays = 7;
    if (range == '14d') numDays = 14;
    if (range == '30d') numDays = 30;
    if (range == 'month') numDays = DateTime.now().day.clamp(1, 31);

    final now = DateTime.now();
    final days = <DateTime>[];
    for (int i = numDays - 1; i >= 0; i--) {
      days.add(DateTime(now.year, now.month, now.day).subtract(Duration(days: i)));
    }

    final tokensList = List<double>.filled(numDays, 0.0);
    final prescList = List<double>.filled(numDays, 0.0);
    final dispList = List<double>.filled(numDays, 0.0);

    final dfDdmmyy = DateFormat('ddMMyy');
    final dfYmd = DateFormat('yyyy-MM-dd');
    final dfLabel = DateFormat('d MMM');

    final dateIndexMap = <String, int>{};
    final labels = <String>[];
    for (int i = 0; i < days.length; i++) {
      dateIndexMap[dfDdmmyy.format(days[i])] = i;
      dateIndexMap[dfYmd.format(days[i])] = i;
      labels.add(dfLabel.format(days[i]));
    }

    final targetB = branchId.toLowerCase().trim();

    try {
      if (Hive.isBoxOpen(LocalStorageService.entriesBox)) {
        final box = Hive.box(LocalStorageService.entriesBox);
        for (final val in box.values) {
          if (val is! Map) continue;
          final b = (val['branchId'] ?? '').toString().toLowerCase().trim();
          if (targetB != 'all' && b.isNotEmpty && !b.contains(targetB) && !targetB.contains(b)) {
            continue;
          }
          if (_selectedCampFilter != 'all') {
            final serial = (val['serial'] ?? val['id'] ?? '').toString().toUpperCase();
            final camp = (val['campId'] ?? val['dispensaryId'] ?? val['dispensaryTag'] ?? '').toString().toLowerCase();
            if (_selectedCampFilter == 'haji') {
              if (!serial.contains('-HAJI') && !serial.contains('HAJI-') && !camp.contains('haji')) continue;
            } else if (_selectedCampFilter == 'saddar') {
              if (!serial.contains('-SADD') && !serial.contains('SADD-') && !camp.contains('saddar') && !camp.contains('kapaya')) continue;
            }
          }

          final dk = (val['dateKey'] ?? val['date'] ?? '').toString().trim();
          final idx = dateIndexMap[dk];
          if (idx != null) {
            tokensList[idx] += 1.0;
            final status = (val['status'] ?? '').toString().toLowerCase();
            final dStatus = (val['dispenseStatus'] ?? '').toString().toLowerCase();
            if (status == 'completed' || status == 'prescribed' || dStatus == 'dispensed' || val['dispensedAt'] != null) {
              prescList[idx] += 1.0;
            }
            if (dStatus == 'dispensed' || status == 'dispensed' || val['dispensedAt'] != null) {
              dispList[idx] += 1.0;
            }
          }
        }
      }
    } catch (_) {}

    return {
      'tokens': tokensList,
      'prescriptions': prescList,
      'dispensary': dispList,
      'labels': labels,
    };
  }

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.branchId ?? widget.initialBranchId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showDateRangePicker(BuildContext context, RoleThemeData t) async {
    final isDark = t.isDarkCanvas || UserThemeService.isDarkMode();
    final currentRange = ref.read(branchDateRangeProvider);
    final initialDateRange = DateTimeRange(
      start: currentRange.start ?? DateTime.now(),
      end: currentRange.end ?? DateTime.now(),
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: t.accent,
              brightness: isDark ? Brightness.dark : Brightness.light,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(branchDateRangeProvider.notifier).state = DateRange(
        start: picked.start,
        end: picked.end,
      );
      setState(() => _currentPage = 1);
    }
  }

  void _showFilterModal(BuildContext context, RoleThemeData t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final typeFilter = ref.watch(branchTypeFilterProvider);
            final shiftFilter = ref.watch(branchShiftFilterProvider);
            final mDay = ref.watch(branchMultiDayFilterProvider);
            final mVisit = ref.watch(branchMultiVisitFilterProvider);

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Filter Records", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
                      TextButton(
                        onPressed: () {
                          ref.read(branchTypeFilterProvider.notifier).state = null;
                          ref.read(branchShiftFilterProvider.notifier).state = null;
                          ref.read(branchMultiDayFilterProvider.notifier).state = false;
                          ref.read(branchMultiVisitFilterProvider.notifier).state = false;
                          setState(() {
                            _sortField = 'token';
                            _sortAscending = true;
                            _currentPage = 1;
                          });
                          setModalState(() {});
                        },
                        child: Text("Reset All", style: TextStyle(color: t.accent, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Queue Type", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildModalChip("All Types", typeFilter == null, () {
                        ref.read(branchTypeFilterProvider.notifier).state = null;
                        setModalState(() {});
                        setState(() => _currentPage = 1);
                      }, t),
                      _buildModalChip("Zakat", typeFilter == 'zakat', () {
                        ref.read(branchTypeFilterProvider.notifier).state = 'zakat';
                        setModalState(() {});
                        setState(() => _currentPage = 1);
                      }, t),
                      _buildModalChip("Non-Zakat", typeFilter == 'non-zakat', () {
                        ref.read(branchTypeFilterProvider.notifier).state = 'non-zakat';
                        setModalState(() {});
                        setState(() => _currentPage = 1);
                      }, t),
                      _buildModalChip("GMWF", typeFilter == 'gmwf', () {
                        ref.read(branchTypeFilterProvider.notifier).state = 'gmwf';
                        setModalState(() {});
                        setState(() => _currentPage = 1);
                      }, t),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Sort Records", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _sortField,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: t.bg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.bgRule)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'token', child: Text('Token number')),
                            DropdownMenuItem(value: 'name', child: Text('Patient name')),
                            DropdownMenuItem(value: 'status', child: Text('Status')),
                            DropdownMenuItem(value: 'type', child: Text('Queue type')),
                            DropdownMenuItem(value: 'facility', child: Text('Facility')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _sortField = value;
                              _currentPage = 1;
                            });
                            setModalState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: _sortAscending ? 'Ascending' : 'Descending',
                        onPressed: () {
                          setState(() {
                            _sortAscending = !_sortAscending;
                            _currentPage = 1;
                          });
                          setModalState(() {});
                        },
                        icon: Icon(_sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: t.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text("Shift", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildModalChip("All Shifts", shiftFilter == null, () {
                        ref.read(branchShiftFilterProvider.notifier).state = null;
                        setModalState(() {});
                        setState(() => _currentPage = 1);
                      }, t),
                      _buildModalChip("Morning", shiftFilter == 'morning', () {
                        ref.read(branchShiftFilterProvider.notifier).state = 'morning';
                        setModalState(() {});
                        setState(() => _currentPage = 1);
                      }, t),
                      _buildModalChip("Evening", shiftFilter == 'evening', () {
                        ref.read(branchShiftFilterProvider.notifier).state = 'evening';
                        setModalState(() {});
                        setState(() => _currentPage = 1);
                      }, t),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilterChip(
                          label: const Text("Multi-Day Course"),
                          selected: mDay,
                          onSelected: (val) {
                            ref.read(branchMultiDayFilterProvider.notifier).state = val;
                            setModalState(() {});
                            setState(() => _currentPage = 1);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilterChip(
                          label: const Text("Frequent Visits (2+)"),
                          selected: mVisit,
                          onSelected: (val) {
                            ref.read(branchMultiVisitFilterProvider.notifier).state = val;
                            setModalState(() {});
                            setState(() => _currentPage = 1);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Apply Filters", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalChip(String label, bool isSelected, VoidCallback onTap, RoleThemeData t) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: t.accent.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? t.accent : t.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      backgroundColor: t.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: isSelected ? t.accent : t.bgRule),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<Box>(
      valueListenable: UserThemeService.listenable(),
      builder: (context, _, child) {
        final t = RoleThemeScope.dataOf(context);
        final branchesAsync = ref.watch(branchesListProvider);

        return Scaffold(
          backgroundColor: t.bg,
          body: branchesAsync.when(
            loading: () => Center(child: CircularProgressIndicator(color: t.accent)),
            error: (e, _) => Center(child: Text('Error loading branches: $e', style: TextStyle(color: t.danger))),
            data: (branchMaps) {
              if (branchMaps.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.store_rounded, size: 48, color: t.bgRule),
                    const SizedBox(height: 16),
                    Text("No branches found", style: TextStyle(color: t.textTertiary, fontSize: 16)),
                    if (widget.showRegisterButton) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BranchesRegister())),
                        icon: const Icon(Icons.add_business_rounded),
                        label: const Text("Register New Branch"),
                      ),
                    ],
                  ]),
                );
              }

              // Resolve active branch
              var activeId = _selectedBranchId;
              if (activeId == null || activeId.isEmpty) {
                final externalTabId = ref.watch(selectedBranchTabIdProvider);
                if (externalTabId != null && externalTabId.isNotEmpty) {
                  activeId = externalTabId;
                } else {
                  activeId = branchMaps.first['id'] as String;
                }
              }

              final matchIdx = branchMaps.indexWhere((m) {
                final id = (m['id'] as String).toLowerCase().trim();
                final target = activeId!.toLowerCase().trim();
                return id == target || id.contains(target) || target.contains(id);
              });

              final currentBranch = matchIdx != -1 ? branchMaps[matchIdx] : branchMaps.first;
              final branchId = currentBranch['id'] as String;
              _selectedBranchName = currentBranch['name'] as String;

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, t, branchMaps, branchId),
                    const SizedBox(height: 20),
                    _buildMetricsCards(context, t, branchId),
                    const SizedBox(height: 20),
                    _buildMiddleSection(context, t, branchId),
                    const SizedBox(height: 24),
                    _buildPatientRecordsSection(context, t, branchId),
                    const SizedBox(height: 40),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. Top Header Bar
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, RoleThemeData t, List<Map<String, dynamic>> branches, String currentBranchId) {
    final role = LocalStorageService.getActiveUserRole().toLowerCase().trim();
    final canSwitchBranches = widget.isManager != true ||
        role.contains('chairman') ||
        role.contains('hq manager') ||
      role.replaceAll(RegExp(r'[^a-z]'), '') == 'hqmanager' ||
        role.contains('global admin');
    final dateRange = ref.watch(branchDateRangeProvider);
    String dateRangeLabel = 'Today';
    if (dateRange.start != null && dateRange.end != null) {
      final df = DateFormat('dd MMM');
      dateRangeLabel = '${df.format(dateRange.start!)} - ${df.format(dateRange.end!)}';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              "$_selectedBranchName Overview",
                              style: TextStyle(
                                fontSize: isNarrow ? 20 : 24,
                                fontWeight: FontWeight.w800,
                                color: t.textPrimary,
                                letterSpacing: -0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (branches.length > 1 && canSwitchBranches) ...[
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.textSecondary),
                              tooltip: 'Switch Branch',
                              onSelected: (bId) {
                                setState(() {
                                  _selectedBranchId = bId;
                                  _currentPage = 1;
                                });
                                ref.read(selectedBranchTabIdProvider.notifier).state = bId;
                              },
                              itemBuilder: (ctx) => branches.map((b) => PopupMenuItem(
                                value: b['id'] as String,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.store_rounded,
                                      size: 16,
                                      color: b['id'] == currentBranchId ? t.accent : t.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      b['name'] as String,
                                      style: TextStyle(
                                        fontWeight: b['id'] == currentBranchId ? FontWeight.bold : FontWeight.normal,
                                        color: b['id'] == currentBranchId ? t.accent : t.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Monitor performance and operations across all departments.",
                        style: TextStyle(fontSize: 13, color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (!isNarrow) _buildHeaderActionButtons(context, t, dateRangeLabel),
              ],
            ),
            if (isNarrow) ...[
              const SizedBox(height: 14),
              _buildHeaderActionButtons(context, t, dateRangeLabel),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHeaderActionButtons(BuildContext context, RoleThemeData t, String dateRangeLabel) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Date Range Selector
        OutlinedButton.icon(
          onPressed: () => _showDateRangePicker(context, t),
          icon: Icon(Icons.calendar_today_rounded, size: 14, color: t.textSecondary),
          label: Text(dateRangeLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.textPrimary)),
          style: OutlinedButton.styleFrom(
            backgroundColor: t.bgCard,
            side: BorderSide(color: t.bgRule),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),

        // + New Branch Button
        if (widget.showRegisterButton)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BranchesRegister())),
            icon: Icon(Icons.add_business_rounded, size: 16, color: t.accent),
            label: Text("New Branch", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accent)),
            style: OutlinedButton.styleFrom(
              backgroundColor: t.accent.withValues(alpha: 0.08),
              side: BorderSide(color: t.accent.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),

        // + New Token Button
        ElevatedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PatientDetailScreen(
                patientId: '',
                isOnline: true,
                localBox: Hive.box('local_patients'),
                branchId: _selectedBranchId ?? 'karachi',
                doctorId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
                isAdmin: true,
              ),
            ),
          ),
          icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
          label: const Text("New Token", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. Top 3 KPI Summary Cards (Tokens, Prescriptions, Dispensary)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildMetricsCards(BuildContext context, RoleThemeData t, String branchId) {
    final summaryAsync = ref.watch(serialsSummaryProvider(branchId));
    final data = summaryAsync.value ?? {};

    final totalTokens = data['total'] ?? 0;
    final zakatTokens = data['v1'] ?? 0;
    final nonZakatTokens = data['v2'] ?? 0;
    final gmwfTokens = data['v3'] ?? 0;

    final prescribed = data['presc_prescribed'] ?? 0;
    final waitingDoctor = data['presc_waiting'] ?? 0;

    final dispensed = data['disp_dispensed'] ?? 0;
    final pendingDisp = data['disp_pending'] ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 800 ? (constraints.maxWidth - 32) / 3 : constraints.maxWidth;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildKpiCard(
                title: "Total Tokens",
                mainCount: "$totalTokens",
                trendText: "+12% vs yesterday",
                isPositiveTrend: true,
                badgeColor: const Color(0xFF6366F1),
                badgeIcon: Icons.people_alt_rounded,
                subItems: [
                  {'label': 'Zakat', 'val': '$zakatTokens'},
                  {'label': 'Non-Zakat', 'val': '$nonZakatTokens'},
                  {'label': 'GMWF', 'val': '$gmwfTokens'},
                ],
                t: t,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildKpiCard(
                title: "Total Prescriptions",
                mainCount: "$prescribed",
                trendText: "+8% vs yesterday",
                isPositiveTrend: true,
                badgeColor: const Color(0xFF10B981),
                badgeIcon: Icons.assignment_rounded,
                subItems: [
                  {'label': 'Waiting', 'val': '$waitingDoctor'},
                  {'label': 'Prescribed', 'val': '$prescribed'},
                ],
                t: t,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildKpiCard(
                title: "Total Dispensary",
                mainCount: "$dispensed",
                trendText: "+5% vs yesterday",
                isPositiveTrend: true,
                badgeColor: const Color(0xFFF59E0B),
                badgeIcon: Icons.medication_liquid_rounded,
                subItems: [
                  {'label': 'Pending', 'val': '$pendingDisp'},
                  {'label': 'Dispensed', 'val': '$dispensed'},
                ],
                t: t,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String mainCount,
    required String trendText,
    required bool isPositiveTrend,
    required Color badgeColor,
    required IconData badgeIcon,
    required List<Map<String, String>> subItems,
    required RoleThemeData t,
  }) {
    final isDark = t.isDarkCanvas || UserThemeService.isDarkMode();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(badgeIcon, color: badgeColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          mainCount,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: t.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPositiveTrend ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPositiveTrend ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                size: 10,
                                color: isPositiveTrend ? const Color(0xFF10B981) : Colors.red,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                trendText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isPositiveTrend ? const Color(0xFF10B981) : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 50,
                height: 28,
                child: CustomPaint(painter: _SparklinePainter(color: badgeColor)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: t.bg.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: subItems.map((item) {
                return Column(
                  children: [
                    Text(item['label'] ?? '', style: TextStyle(fontSize: 11, color: t.textTertiary)),
                    const SizedBox(height: 2),
                    Text(
                      item['val'] ?? '0',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.textPrimary),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. Middle Section (Performance Overview Multi-line Chart & Quick Actions)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildMiddleSection(BuildContext context, RoleThemeData t, String branchId) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isStacked = constraints.maxWidth < 950;

        if (isStacked) {
          return Column(
            children: [
              _buildPerformanceChartCard(context, t, branchId),
              const SizedBox(height: 16),
              _buildQuickActionsCard(context, t, branchId),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _buildPerformanceChartCard(context, t, branchId)),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: _buildQuickActionsCard(context, t, branchId)),
          ],
        );
      },
    );
  }

  Widget _buildPerformanceChartCard(BuildContext context, RoleThemeData t, String branchId) {
    final isDark = t.isDarkCanvas || UserThemeService.isDarkMode();
    final perfData = _computeRealPerformanceData(branchId, _chartRange);
    final tokensData = (perfData['tokens'] as List<double>?) ?? [];
    final prescData = (perfData['prescriptions'] as List<double>?) ?? [];
    final dispData = (perfData['dispensary'] as List<double>?) ?? [];
    final labels = (perfData['labels'] as List<String>?) ?? [];

    final tokensTotal = tokensData.fold<double>(0.0, (a, b) => a + b).toInt();
    final prescTotal = prescData.fold<double>(0.0, (a, b) => a + b).toInt();
    final dispTotal = dispData.fold<double>(0.0, (a, b) => a + b).toInt();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Performance Overview",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedCampFilter == 'haji'
                        ? "Haji Camp Dispensary Data"
                        : (_selectedCampFilter == 'saddar' ? "Saddar Dispensary Data" : "Collective Branch Performance"),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.accent),
                  ),
                ],
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _chartRange,
                  dropdownColor: t.bgCard,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: t.textSecondary),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textPrimary),
                  items: const [
                    DropdownMenuItem(value: '7d', child: Text("Last 7 Days")),
                    DropdownMenuItem(value: '14d', child: Text("Last 14 Days")),
                    DropdownMenuItem(value: '30d', child: Text("Last 30 Days")),
                    DropdownMenuItem(value: 'month', child: Text("This Month")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _chartRange = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildChartLegend("Tokens: $tokensTotal", const Color(0xFF6366F1), t),
              const SizedBox(width: 14),
              _buildChartLegend("Prescriptions: $prescTotal", const Color(0xFF10B981), t),
              const SizedBox(width: 14),
              _buildChartLegend("Dispensed: $dispTotal", const Color(0xFFF59E0B), t),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _PerformanceMultiLinePainter(
                theme: t,
                tokensColor: const Color(0xFF6366F1),
                prescriptionsColor: const Color(0xFF10B981),
                dispensaryColor: const Color(0xFFF59E0B),
                tokensData: tokensData,
                prescriptionsData: prescData,
                dispensaryData: dispData,
                dateLabels: labels,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(String label, Color color, RoleThemeData t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.textSecondary)),
      ],
    );
  }

  Widget _buildQuickActionsCard(BuildContext context, RoleThemeData t, String branchId) {
    final isDark = t.isDarkCanvas || UserThemeService.isDarkMode();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Quick Actions",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.textPrimary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  icon: Icons.inventory_2_rounded,
                  title: "Inventory",
                  subtitle: "Manage stock",
                  accentColor: const Color(0xFF6366F1),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InventoryPage(branchId: branchId))),
                  t: t,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  icon: Icons.account_balance_wallet_rounded,
                  title: "Finance",
                  subtitle: "View transactions",
                  accentColor: const Color(0xFFF59E0B),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FinancePage(branchId: branchId))),
                  t: t,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  icon: Icons.fingerprint_rounded,
                  title: "Biometrics",
                  subtitle: "Live punches",
                  accentColor: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BiometricDeviceManagerPage())),
                  t: t,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  icon: Icons.person_add_alt_1_rounded,
                  title: "Add Patient",
                  subtitle: "New registration",
                  accentColor: const Color(0xFF10B981),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PatientDetailScreen(
                        patientId: '',
                        isOnline: true,
                        localBox: Hive.box('local_patients'),
                        branchId: branchId,
                        doctorId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
                        isAdmin: true,
                      ),
                    ),
                  ),
                  t: t,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required VoidCallback onTap,
    required RoleThemeData t,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: t.bg.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.bgRule),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 10, color: t.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. All Branch Patient Records Section (Table, Filter Tabs, Search & Pagination)
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildPatientRecordsSection(BuildContext context, RoleThemeData t, String branchId) {
    final isDark = t.isDarkCanvas || UserThemeService.isDarkMode();
    final dispState = ref.watch(dispensaryProvider(branchId));
    final allList = dispState.records;

    final typeFilter = ref.watch(branchTypeFilterProvider);
    final shiftFilter = ref.watch(branchShiftFilterProvider);
    final mDay = ref.watch(branchMultiDayFilterProvider);
    final mVisit = ref.watch(branchMultiVisitFilterProvider);
    final stageFilter = ref.watch(branchStageFilterProvider);

    // Filter list
    final filtered = allList.where((p) {
      // Camp filter (Haji Camp vs Saddar Camp vs All)
      if (_selectedCampFilter != 'all') {
        final serial = (p['serial'] ?? p['id'] ?? '').toString().toUpperCase();
        final camp = (p['campId'] ?? p['dispensaryId'] ?? p['dispensaryTag'] ?? '').toString().toLowerCase();
        if (_selectedCampFilter == 'haji') {
          if (!serial.contains('-HAJI') && !serial.contains('HAJI-') && !camp.contains('haji')) return false;
        } else if (_selectedCampFilter == 'saddar') {
          if (!serial.contains('-SADD') && !serial.contains('SADD-') && !camp.contains('saddar') && !camp.contains('kapaya')) return false;
        }
      }

      // Type
      if (typeFilter != null && p['type']?.toString().toLowerCase() != typeFilter) return false;

      // Shift
      if (shiftFilter != null) {
        final sess = (p['session'] ?? p['shift'] ?? '').toString().toLowerCase().trim();
        if (sess.isNotEmpty && sess != shiftFilter) return false;
      }

      // Multi-Day
      if (mDay) {
        final days = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
        if (days <= 1) return false;
      }

      // Multi-Visit
      if (mVisit) {
        final visits = (p['totalVisits'] as num?)?.toInt() ?? 0;
        if (visits <= 1) return false;
      }

      // Search Query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final qClean = q.replaceAll('-', '').replaceAll(' ', '');
        final name = (p['name'] ?? '').toString().toLowerCase();
        final serial = (p['serial'] ?? p['id'] ?? '').toString().toLowerCase();
        final cnic = (p['displayCnic'] ?? p['cnic'] ?? p['patientCnic'] ?? p['guardianCnic'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll('-', '')
            .replaceAll(' ', '');
        final phone = (p['phone'] ?? p['patientPhone'] ?? '')
            .toString()
            .toLowerCase()
            .replaceAll('-', '')
            .replaceAll(' ', '');
        if (!name.contains(q) && !serial.contains(q) && !cnic.contains(qClean) && !phone.contains(qClean)) {
          return false;
        }
      }

      // Stage Filter
      if (stageFilter == 'waiting_doctor') {
        return _recordStage(p) == 'waiting_doctor';
      } else if (stageFilter == 'waiting_dispensary') {
        return _recordStage(p) == 'waiting_dispensary';
      } else if (stageFilter == 'dispensed') {
        return _recordStage(p) == 'dispensed';
      }

      return true;
    }).toList()
      ..sort(_compareRecords);

    // Stage counts with camp filter applied
    final campFilteredAllList = allList.where((p) {
      if (_selectedCampFilter == 'all') return true;
      final serial = (p['serial'] ?? p['id'] ?? '').toString().toUpperCase();
      final camp = (p['campId'] ?? p['dispensaryId'] ?? p['dispensaryTag'] ?? '').toString().toLowerCase();
      if (_selectedCampFilter == 'haji') {
        return serial.contains('-HAJI') || serial.contains('HAJI-') || camp.contains('haji');
      } else if (_selectedCampFilter == 'saddar') {
        return serial.contains('-SADD') || serial.contains('SADD-') || camp.contains('saddar') || camp.contains('kapaya');
      }
      return true;
    }).toList();

    final waitingDoctorCount = campFilteredAllList.where((p) => _recordStage(p) == 'waiting_doctor').length;
    final waitingDispCount = campFilteredAllList.where((p) => _recordStage(p) == 'waiting_dispensary').length;
    final dispensedCount = campFilteredAllList.where((p) => _recordStage(p) == 'dispensed').length;

    // Pagination slice
    final totalRecords = filtered.length;
    final totalPages = (totalRecords / _rowsPerPage).ceil().clamp(1, 999999);
    final safePage = _currentPage.clamp(1, totalPages);
    final startIndex = (safePage - 1) * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalRecords);
    final paginatedList = totalRecords > 0 ? filtered.sublist(startIndex, endIndex) : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.bgRule, width: 1),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Text(
            "All Branch Patient Records",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: t.textPrimary),
          ),
          if (dispState.isSyncing) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: t.bgRule,
                color: t.accent,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Karachi Camp Selector (Collective vs Haji Camp vs Saddar)
          if (branchId.toLowerCase().contains('karachi') || branchId.toLowerCase() == 'all') ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildCampFilterChip('All Karachi (Collective)', _selectedCampFilter == 'all', () {
                  setState(() { _selectedCampFilter = 'all'; _currentPage = 1; });
                }, const Color(0xFF0D9488), t),
                _buildCampFilterChip('Haji Camp Dispensary', _selectedCampFilter == 'haji', () {
                  setState(() { _selectedCampFilter = 'haji'; _currentPage = 1; });
                }, const Color(0xFF6366F1), t),
                _buildCampFilterChip('Saddar Dispensary', _selectedCampFilter == 'saddar', () {
                  setState(() { _selectedCampFilter = 'saddar'; _currentPage = 1; });
                }, const Color(0xFFF59E0B), t),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Stage Pills & Search Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 850;

              final filterPills = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStageTabPill("All Records", allList.length, stageFilter == 'all', () {
                    ref.read(branchStageFilterProvider.notifier).state = 'all';
                    setState(() => _currentPage = 1);
                  }, const Color(0xFF6366F1), t),
                  _buildStageTabPill("Waiting for Doctor", waitingDoctorCount, stageFilter == 'waiting_doctor', () {
                    ref.read(branchStageFilterProvider.notifier).state = 'waiting_doctor';
                    setState(() => _currentPage = 1);
                  }, const Color(0xFFF59E0B), t),
                  _buildStageTabPill("Waiting for Dispensary", waitingDispCount, stageFilter == 'waiting_dispensary', () {
                    ref.read(branchStageFilterProvider.notifier).state = 'waiting_dispensary';
                    setState(() => _currentPage = 1);
                  }, const Color(0xFF3B82F6), t),
                  _buildStageTabPill("Dispensed", dispensedCount, stageFilter == 'dispensed', () {
                    ref.read(branchStageFilterProvider.notifier).state = 'dispensed';
                    setState(() => _currentPage = 1);
                  }, const Color(0xFF10B981), t),
                ],
              );

              final searchBarAndFilters = Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.bgRule),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 16, color: t.textTertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(fontSize: 12, color: t.textPrimary),
                              decoration: InputDecoration(
                                hintText: "Search by token, patient name, CNIC, or phone...",
                                hintStyle: TextStyle(fontSize: 12, color: t.textTertiary),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _searchQuery = val.trim();
                                  _currentPage = 1;
                                });
                              },
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _currentPage = 1;
                                });
                              },
                              child: Icon(Icons.close_rounded, size: 16, color: t.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _showFilterModal(context, t),
                    icon: Icon(Icons.tune_rounded, size: 14, color: t.textSecondary),
                    label: Text("Filters", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.textPrimary)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: t.bg,
                      side: BorderSide(color: t.bgRule),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    filterPills,
                    const SizedBox(height: 12),
                    searchBarAndFilters,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: filterPills),
                  const SizedBox(width: 16),
                  SizedBox(width: 340, child: searchBarAndFilters),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          // Records Table
          if (dispState.isSyncing && allList.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(40), child: CircularProgressIndicator(color: t.accent)))
          else if (filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.person_search_rounded, size: 40, color: t.textTertiary),
                    const SizedBox(height: 10),
                    Text("No matching records found", style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )
          else
            _buildRecordsTable(context, t, paginatedList, branchId),

          const SizedBox(height: 16),

          // Pagination Footer
          if (filtered.isNotEmpty)
            _buildPaginationFooter(context, t, totalRecords, safePage, totalPages, startIndex, endIndex),
        ],
      ),
    );
  }

  Widget _buildStageTabPill(String label, int count, bool isSelected, VoidCallback onTap, Color activeColor, RoleThemeData t) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : t.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor.withValues(alpha: 0.5) : t.bgRule,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : t.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? activeColor.withValues(alpha: 0.2) : t.bgRule.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "$count",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? activeColor : t.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsTable(BuildContext context, RoleThemeData t, List<Map<String, dynamic>> records, String branchId) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.bgRule),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(t.bg.withValues(alpha: 0.8)),
          headingTextStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: t.textSecondary, letterSpacing: 0.3),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 58,
          columnSpacing: 20,
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text("TOKEN #")),
            DataColumn(label: Text("PATIENT NAME")),
            DataColumn(label: Text("CNIC")),
            DataColumn(label: Text("PHONE NUMBER")),
            DataColumn(label: Text("TYPE")),
            DataColumn(label: Text("STATUS")),
            DataColumn(label: Text("FACILITY & SHIFT")),
            DataColumn(label: Text("RELATIONS / COURSE")),
            DataColumn(label: Text("ACTIONS")),
          ],
          rows: records.map((p) {
            final pid = p['patientId']?.toString() ?? p['id']?.toString() ?? '';
            final tokenSerial = p['serial']?.toString() ?? p['id']?.toString() ?? 'TK-000';
            final name = p['name']?.toString() ?? 'Unknown Patient';
            final age = p['age']?.toString() ?? '';
            final gender = p['gender']?.toString() ?? '';
            final rawPhone = (p['phone'] ?? p['patientPhone'] ?? '').toString().trim();
            final hasPhone = rawPhone.isNotEmpty && rawPhone != 'N/A' && rawPhone != '-';
            final stage = _recordStage(p);
            final statusColor = stage == 'dispensed'
              ? const Color(0xFF10B981)
              : stage == 'waiting_dispensary'
                ? const Color(0xFF3B82F6)
                : const Color(0xFFF59E0B);
            final statusLabel = stage == 'dispensed'
              ? 'Dispensed'
              : stage == 'waiting_dispensary'
                ? 'Waiting for Dispensary'
                : 'Waiting for Doctor';

            final rawCnic = (p['displayCnic'] ?? p['cnic'] ?? p['patientCnic'] ?? p['guardianCnic'] ?? '').toString().trim();
            final hasCnic = rawCnic.isNotEmpty && rawCnic != 'N/A' && rawCnic != '0000000000000' && rawCnic != '-';
            final formattedCnic = hasCnic ? _formatCnic(rawCnic) : '—';
            final isChild = p['isChild'] == true ||
                ((p['guardianCnic'] ?? '').toString().isNotEmpty && (p['patientCnic'] ?? p['cnic'] ?? '').toString().isEmpty);

            final type = (p['type'] ?? 'zakat').toString().toLowerCase();

            Color typeColor;
            if (type == 'zakat') {
              typeColor = const Color(0xFF6366F1);
            } else if (type == 'non-zakat') {
              typeColor = const Color(0xFF3B82F6);
            } else if (type == 'gmwf') {
              typeColor = const Color(0xFF10B981);
            } else {
              typeColor = t.textSecondary;
            }

            final campLabel = _resolvePatientCampLabel(p, branchId);
            final days = (p['daysOfMedicine'] as num?)?.toInt() ?? 1;
            final visits = (p['totalVisits'] as num?)?.toInt() ?? 1;
            final isFrequent = p['frequentFlag'] == true;

            return DataRow(
              cells: [
                // 1. Token #
                DataCell(
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: tokenSerial));
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied token: $tokenSerial'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        tokenSerial,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.textPrimary),
                      ),
                    ),
                  ),
                ),

                // 2. Patient Name & Age/Gender
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.textPrimary)),
                          if (isFrequent) const Padding(padding: EdgeInsets.only(left: 4), child: Text('🔥', style: TextStyle(fontSize: 11))),
                        ],
                      ),
                      if (age.isNotEmpty && age != 'N/A' || gender.isNotEmpty && gender != 'N/A')
                        Text(
                          [
                            if (age.isNotEmpty && age != 'N/A') '$age yrs',
                            if (gender.isNotEmpty && gender != 'N/A') gender,
                          ].join(' • '),
                          style: TextStyle(fontSize: 10, color: t.textTertiary),
                        ),
                    ],
                  ),
                ),

                // 3. CNIC
                DataCell(
                  hasCnic
                      ? InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: rawCnic));
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied CNIC: $formattedCnic'),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.badge_outlined, size: 13, color: t.accent),
                                const SizedBox(width: 5),
                                Text(
                                  formattedCnic,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: t.textPrimary,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                if (isChild) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: t.accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Guardian',
                                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: t.accent),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : Text('—', style: TextStyle(fontSize: 12, color: t.textTertiary)),
                ),

                // 4. Phone Number
                DataCell(
                  hasPhone
                      ? InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: rawPhone));
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied Phone: $rawPhone'),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.phone_rounded, size: 12, color: Color(0xFF10B981)),
                                const SizedBox(width: 5),
                                Text(
                                  rawPhone,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Text('—', style: TextStyle(fontSize: 12, color: t.textTertiary)),
                ),

                // 5. Type Badge
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      type.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: typeColor),
                    ),
                  ),
                ),

                // 6. Status
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),

                // 7. Facility & Shift
                DataCell(
                  Text(campLabel, style: TextStyle(fontSize: 11, color: t.textSecondary)),
                ),

                // 8. Relations / Course
                DataCell(
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (visits > 1)
                        Text('$visits+ Visits', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.textPrimary))
                      else
                        Text('1st Visit', style: TextStyle(fontSize: 11, color: t.textTertiary)),
                      if (days > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('$days d course', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                        ),
                    ],
                  ),
                ),

                // 8. Actions
                DataCell(
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, size: 18, color: t.textSecondary),
                    onSelected: (val) {
                      if (val == 'view') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PatientDetailScreen(
                              patientId: pid,
                              isOnline: true,
                              localBox: Hive.box('local_patients'),
                              branchId: branchId,
                              doctorId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
                              isAdmin: true,
                            ),
                          ),
                        );
                      } else if (val == 'copy') {
                        Clipboard.setData(ClipboardData(text: tokenSerial));
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied $tokenSerial'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else if (val == 'copy_cnic' && hasCnic) {
                        Clipboard.setData(ClipboardData(text: rawCnic));
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied CNIC: $formattedCnic'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else if (val == 'copy_phone' && hasPhone) {
                        Clipboard.setData(ClipboardData(text: rawPhone));
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied Phone: $rawPhone'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.person_rounded, size: 16), SizedBox(width: 8), Text("View Profile")])),
                      const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.copy_rounded, size: 16), SizedBox(width: 8), Text("Copy Token")])),
                      if (hasCnic)
                        const PopupMenuItem(value: 'copy_cnic', child: Row(children: [Icon(Icons.badge_outlined, size: 16), SizedBox(width: 8), Text("Copy CNIC")])),
                      if (hasPhone)
                        const PopupMenuItem(value: 'copy_phone', child: Row(children: [Icon(Icons.phone_rounded, size: 16), SizedBox(width: 8), Text("Copy Phone")])),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPaginationFooter(BuildContext context, RoleThemeData t, int totalRecords, int currentPage, int totalPages, int startIdx, int endIdx) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Showing info
        Text(
          "Showing ${startIdx + 1} to $endIdx of $totalRecords records",
          style: TextStyle(fontSize: 12, color: t.textTertiary),
        ),

        // Page buttons & Page Size selector
        Row(
          children: [
            // Page buttons
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              onPressed: currentPage > 1 ? () => setState(() => _currentPage--) : null,
              color: t.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            for (int p = 1; p <= totalPages && p <= 5; p++) ...[
              InkWell(
                onTap: () => setState(() => _currentPage = p),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p == currentPage ? t.accent.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: p == currentPage ? t.accent : Colors.transparent),
                  ),
                  child: Text(
                    "$p",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: p == currentPage ? FontWeight.bold : FontWeight.normal,
                      color: p == currentPage ? t.accent : t.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              onPressed: currentPage < totalPages ? () => setState(() => _currentPage++) : null,
              color: t.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 12),

            // Rows per page selector
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _rowsPerPage,
                dropdownColor: t.bgCard,
                icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: t.textSecondary),
                style: TextStyle(fontSize: 11, color: t.textPrimary),
                items: const [
                  DropdownMenuItem(value: 10, child: Text("10 / page")),
                  DropdownMenuItem(value: 25, child: Text("25 / page")),
                  DropdownMenuItem(value: 50, child: Text("50 / page")),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _rowsPerPage = val;
                      _currentPage = 1;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCampFilterChip(String label, bool isSelected, VoidCallback onTap, Color color, RoleThemeData t) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : t.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : t.bgRule,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: isSelected ? color : t.textTertiary, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painters for Sparklines and Performance Charts
// ─────────────────────────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final Color color;
  const _SparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.3, size.height * 0.8, size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.7, size.height * 0.1, size.width, size.height * 0.2);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PerformanceMultiLinePainter extends CustomPainter {
  final RoleThemeData theme;
  final Color tokensColor;
  final Color prescriptionsColor;
  final Color dispensaryColor;
  final List<double> tokensData;
  final List<double> prescriptionsData;
  final List<double> dispensaryData;
  final List<String> dateLabels;

  const _PerformanceMultiLinePainter({
    required this.theme,
    required this.tokensColor,
    required this.prescriptionsColor,
    required this.dispensaryColor,
    required this.tokensData,
    required this.prescriptionsData,
    required this.dispensaryData,
    required this.dateLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = theme.bgRule.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    // Draw horizontal grid lines
    const gridLines = 4;
    final yStep = (size.height - 24) / gridLines;
    for (int i = 0; i <= gridLines; i++) {
      final y = i * yStep;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (tokensData.isEmpty) return;

    double maxVal = 1.0;
    for (final v in [...tokensData, ...prescriptionsData, ...dispensaryData]) {
      if (v > maxVal) maxVal = v;
    }

    List<double> normalize(List<double> raw) {
      return raw.map((v) => (1.0 - ((v / maxVal) * 0.85 + 0.05)).clamp(0.05, 0.95)).toList();
    }

    final normTokens = normalize(tokensData);
    final normPresc = normalize(prescriptionsData);
    final normDisp = normalize(dispensaryData);

    _drawSmoothCurve(canvas, size, normTokens, tokensColor, true);
    _drawSmoothCurve(canvas, size, normPresc, prescriptionsColor, true);
    _drawSmoothCurve(canvas, size, normDisp, dispensaryColor, true);

    // Draw bottom date labels
    if (dateLabels.isNotEmpty) {
      final int step = (dateLabels.length / 6).ceil().clamp(1, 10);
      final double xStep = size.width / (dateLabels.length - 1).clamp(1, 9999);

      for (int i = 0; i < dateLabels.length; i += step) {
        final tp = TextPainter(
          text: TextSpan(
            text: dateLabels[i],
            style: TextStyle(fontSize: 9, color: theme.textTertiary),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        final double xPos = (i * xStep - (tp.width / 2)).clamp(0.0, size.width - tp.width);
        tp.paint(canvas, Offset(xPos, size.height - 12));
      }
    }
  }

  void _drawSmoothCurve(Canvas canvas, Size size, List<double> normalizedPoints, Color color, bool fillArea) {
    if (normalizedPoints.isEmpty) return;

    final h = size.height - 24;
    final xStep = size.width / (normalizedPoints.length - 1);

    final path = Path();
    final fillPath = Path();

    path.moveTo(0, normalizedPoints[0] * h);
    fillPath.moveTo(0, h);
    fillPath.lineTo(0, normalizedPoints[0] * h);

    for (int i = 0; i < normalizedPoints.length - 1; i++) {
      final x1 = i * xStep;
      final y1 = normalizedPoints[i] * h;
      final x2 = (i + 1) * xStep;
      final y2 = normalizedPoints[i + 1] * h;

      final cx1 = x1 + (x2 - x1) / 2;
      final cy1 = y1;
      final cx2 = x1 + (x2 - x1) / 2;
      final cy2 = y2;

      path.cubicTo(cx1, cy1, cx2, cy2, x2, y2);
      fillPath.cubicTo(cx1, cy1, cx2, cy2, x2, y2);
    }

    fillPath.lineTo(size.width, h);
    fillPath.close();

    if (fillArea) {
      final gradientPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, h));
      canvas.drawPath(fillPath, gradientPaint);
    }

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Draw dots
    final dotPaint = Paint()..color = color;
    final dotWhite = Paint()..color = Colors.white;
    for (int i = 0; i < normalizedPoints.length; i++) {
      final x = i * xStep;
      final y = normalizedPoints[i] * h;
      canvas.drawCircle(Offset(x, y), 3.5, dotWhite);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}