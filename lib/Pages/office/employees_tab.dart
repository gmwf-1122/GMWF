// lib/pages/office/employees_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/local_storage_service.dart';
import '../../services/permission_service.dart';
import 'shared_widgets.dart';
import 'employee_form_sheet.dart';
import 'finance_report_helper.dart';
import 'employee_report_page.dart';

class EmployeesTab extends StatefulWidget {
  final String branchId;
  final String userRole;
  final Function(BuildContext context, String? employeeId) openEmployeeForm;
  final List<Map<String, dynamic>> branches;

  const EmployeesTab({
    super.key,
    required this.branchId,
    required this.userRole,
    required this.openEmployeeForm,
    required this.branches,
  });

  @override
  State<EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<EmployeesTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _roleFilter = 'All';
  String _deptFilter = 'All';
  String _statusFilter = 'Active';
  String _branchFilter = 'All';

  // Defaults used to decide whether a filter counts as "active" for the
  // Filters button badge + removable chip row. See redesign plan §3.C:
  // "only expand to full row width once a filter is actively applied,
  // showing it as a removable chip."
  static const String _defaultStatus = 'Active';

  String _getBranchName(String id) {
    final match = widget.branches.firstWhereOrNull((b) => b['id'] == id);
    return match != null ? (match['name']?.toString() ?? id) : id;
  }

  int get _activeFilterCount {
    int count = 0;
    if (_roleFilter != 'All') count++;
    if (_deptFilter != 'All') count++;
    if (_branchFilter != 'All') count++;
    if (_statusFilter != _defaultStatus) count++;
    return count;
  }

  String _normalizeBranchKey(Map<String, dynamic> emp) {
    final raw = emp['branchId']?.toString().trim() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'unknown' || raw.toLowerCase() == 'null') {
      return 'Unassigned';
    }
    return raw;
  }

  String _normalizeDepartmentKey(Map<String, dynamic> emp) {
    final raw = emp['department']?.toString().trim() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'unknown' || raw.toLowerCase() == 'null') {
      return 'Unassigned';
    }
    return raw;
  }

  String _displayBranchName(String branchKey) {
    if (branchKey == 'Unassigned') return 'Unassigned';
    return _getBranchName(branchKey);
  }

  Color _mutedColorForKey(String key) {
    final seed = key.hashCode;
    final hue = (seed % 360).toDouble();
    final h = (hue + 360) % 360;
    final col = HSLColor.fromAHSL(1.0, h, 0.28, 0.88).toColor();
    return col;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tOriginal = RoleThemeScope.dataOf(context);
    final t = RoleThemeData(
        roleLabel: tOriginal.roleLabel,
      isDarkCanvas: false,
        bg: const Color(0xFFFBFDFF),
        bgCard: Colors.white,
        bgCardAlt: const Color(0xFFF6F9F8),
        bgRule: const Color(0xFFF1F5F9),
        accent: const Color(0xFF0F9A7A),
        accentLight: const Color(0xFF4CB79A),
        accentMuted: const Color(0xFFE8F6F0),
      accentGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
      glassTint: const Color(0x1A10B981),
      textPrimary: const Color(0xFF111827),
      textSecondary: const Color(0xFF6B7280),
      textTertiary: const Color(0xFF9CA3AF),
      danger: const Color(0xFFEF4444),
      zakat: tOriginal.zakat,
      nonZakat: tOriginal.nonZakat,
      gmwf: tOriginal.gmwf,
      cardFillTokens: tOriginal.cardFillTokens,
      cardFillPrescriptions: tOriginal.cardFillPrescriptions,
      cardFillDispensary: tOriginal.cardFillDispensary,
      chartBar1: tOriginal.chartBar1,
      chartBar2: tOriginal.chartBar2,
      chartBar3: tOriginal.chartBar3,
      chartGrid: tOriginal.chartGrid,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: ValueListenableBuilder(
        valueListenable: FinanceLocalStorage.employeesBox.listenable(),
        builder: (context, Box box, _) {
          final query = _searchCtrl.text.trim().toLowerCase();
          final list = FinanceLocalStorage.getEmployees(widget.branchId).where((emp) {
            // Apply role
            if (_roleFilter != 'All' && emp['role'] != _roleFilter) return false;
            // Apply dept
            if (_deptFilter != 'All' && emp['department'] != _deptFilter) return false;
            // Apply branch
            if (_branchFilter != 'All') {
              final String empBranch = (emp['branchId']?.toString() ?? '').toLowerCase();
              final String selectedB = _branchFilter.toLowerCase();
              if (selectedB.contains('karachi')) {
                if (!empBranch.contains('karachi')) return false;
              } else {
                if (emp['branchId'] != _branchFilter) return false;
              }
            }
            // Apply status
            final isActive = emp['isActive'] as bool? ?? true;
            final status = emp['status'] as String? ?? (isActive ? 'Active' : 'Left');
            if (_statusFilter == 'Active' && status != 'Active') return false;
            if (_statusFilter == 'Archived' && status != 'Archived') return false;
            if (_statusFilter == 'Temporary Leave' && status != 'Temporary Leave') return false;
            if (_statusFilter == 'Left' && status != 'Left') return false;
            if (_statusFilter == 'Inactive' && status == 'Active') return false;

            if (query.isNotEmpty) {
              final name = emp['name']?.toString().toLowerCase() ?? '';
              final cnic = emp['cnic']?.toString().toLowerCase() ?? '';
              final phone = emp['phone']?.toString().toLowerCase() ?? '';
              return name.contains(query) || cnic.contains(query) || phone.contains(query);
            }
            return true;
          }).toList();

          return Column(
            children: [
              _buildFilterBar(t),
              Expanded(
                child: list.isEmpty
                    ? _buildEmptyState(t)
                    : _buildGroupedEmployeeList(t, list),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Filter bar ─────────────────────────────────────────────────────────────
  // Redesign plan §3.C: collapse the 4 always-visible dropdowns into a single
  // "Filters" button (badge shows active count). Tapping opens a compact
  // panel; whatever is actively applied shows as a removable chip below,
  // instead of eating a full row even when nothing's selected.
  Widget _buildFilterBar(RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                      height: 40,
                  decoration: BoxDecoration(
                    color: t.bgCardAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.bgRule),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(color: t.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by name, CNIC, phone...',
                      hintStyle: TextStyle(color: t.textTertiary, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: t.textTertiary, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _openFiltersSheet(context, t),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _activeFilterCount > 0 ? t.accent.withOpacity(0.12) : t.bgCardAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _activeFilterCount > 0 ? t.accent.withOpacity(0.5) : t.bgRule),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 18, color: _activeFilterCount > 0 ? t.accent : t.textSecondary),
                      const SizedBox(width: 6),
                      Text('Filters', style: TextStyle(color: _activeFilterCount > 0 ? t.accent : t.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                      if (_activeFilterCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(10)),
                          child: Text('$_activeFilterCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
               Tooltip(
                message: 'Apply Annual Increments',
                child: Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: t.accentMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.accent.withOpacity(0.3)),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.trending_up, color: t.accent, size: 20),
                    onPressed: () => _openAnnualIncrementsDialog(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => widget.openEmployeeForm(context, null),
              ),
            ],
          ),
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_roleFilter != 'All')
                  _buildFilterChip('Role: $_roleFilter', t, () => setState(() => _roleFilter = 'All')),
                if (_deptFilter != 'All')
                  _buildFilterChip('Dept: $_deptFilter', t, () => setState(() => _deptFilter = 'All')),
                if (_branchFilter != 'All')
                  _buildFilterChip('Branch: ${_getBranchName(_branchFilter)}', t, () => setState(() => _branchFilter = 'All')),
                if (_statusFilter != _defaultStatus)
                  _buildFilterChip('Status: $_statusFilter', t, () => setState(() => _statusFilter = _defaultStatus)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, RoleThemeData t, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 2, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: t.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.accent.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: t.accent, fontSize: 11, fontWeight: FontWeight.bold)),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(5.0),
              child: Icon(Icons.close_rounded, size: 13, color: t.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _openFiltersSheet(BuildContext context, RoleThemeData t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (innerCtx, setSheetState) {
            final List<String> filterDepts = ['All', 'Administration', 'Office', 'Dasterkhwaan', 'Dispensary', 'Madrassa', 'School']
              ..addAll(FinanceLocalStorage.getCustomDepartments());
            if (!filterDepts.contains(_deptFilter)) _deptFilter = 'All';

            final List<String> filterRoles = ['All'];
            if (_deptFilter == 'All') {
              final allRoles = <String>{};
              for (final d in ['Administration', 'Office', 'Dasterkhwaan', 'Dispensary', 'Madrassa', 'School']) {
                allRoles.addAll(FinanceLocalStorage.getRolesForDepartment(d));
              }
              for (final cd in FinanceLocalStorage.getCustomDepartments()) {
                allRoles.addAll(FinanceLocalStorage.getRolesForDepartment(cd));
              }
              allRoles.addAll(FinanceLocalStorage.getCustomRoles());
              filterRoles.addAll(allRoles);
            } else {
              filterRoles.addAll(FinanceLocalStorage.getRolesForDepartment(_deptFilter));
            }
            if (!filterRoles.contains(_roleFilter)) _roleFilter = 'All';

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(innerCtx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filter Employees', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary)),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            _roleFilter = 'All';
                            _deptFilter = 'All';
                            _branchFilter = 'All';
                            _statusFilter = _defaultStatus;
                          });
                          setState(() {});
                        },
                        child: Text('Reset', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  buildDropdownField(
                    label: 'Role',
                    value: _roleFilter,
                    items: filterRoles,
                    onChanged: (val) {
                      setSheetState(() => _roleFilter = val!);
                      setState(() {});
                    },
                    theme: t,
                  ),
                  buildDropdownField(
                    label: 'Department',
                    value: _deptFilter,
                    items: filterDepts,
                    onChanged: (val) {
                      setSheetState(() {
                        _deptFilter = val!;
                        _roleFilter = 'All';
                      });
                      setState(() {});
                    },
                    theme: t,
                  ),
                  if (widget.branches.length > 1)
                    StatefulBuilder(
                      builder: (filterBranchCtx, setFilterBranchState) {
                        final allBranches = FinanceLocalStorage.getAllBranches(widget.branches)
                            .where((b) {
                              final id = b['id']?.toString() ?? '';
                              return id != 'karachi-2' && id != 'karachi2';
                            }).toList();
                        
                        final List<String> dropdownItems = ['All', ...allBranches.map((b) => b['id']?.toString() ?? '')];
                        if (!dropdownItems.contains('+ Add Custom Branch...')) {
                          dropdownItems.add('+ Add Custom Branch...');
                        }

                        if (!dropdownItems.contains(_branchFilter)) {
                          _branchFilter = 'All';
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: t.bgCardAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: t.bgRule),
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _branchFilter,
                            dropdownColor: t.bgCard,
                            decoration: InputDecoration(
                              labelText: 'Branch',
                              labelStyle: TextStyle(color: t.textSecondary, fontSize: 11),
                              border: InputBorder.none,
                              filled: false,
                            ),
                            style: TextStyle(color: t.textPrimary, fontSize: 13),
                            items: dropdownItems.map((id) {
                              if (id == 'All') {
                                return const DropdownMenuItem(value: 'All', child: Text('All Branches'));
                              }
                              if (id == '+ Add Custom Branch...') {
                                return const DropdownMenuItem(
                                  value: '+ Add Custom Branch...',
                                  child: Text('+ Add Custom Branch...', style: TextStyle(fontWeight: FontWeight.bold)),
                                );
                              }
                              final b = allBranches.firstWhereOrNull((x) => x['id'] == id);
                              String name = b?['name']?.toString() ?? id;
                              if (id == 'karachi-1' || id == 'karachi1') {
                                name = 'Karachi';
                              }
                              return DropdownMenuItem(value: id, child: Text('$name ($id)'));
                            }).toList(),
                            onChanged: (val) {
                              if (val == '+ Add Custom Branch...') {
                                showCustomBranchDialog(
                                  context: sheetCtx,
                                  theme: t,
                                  onAdded: (newId, newName) {
                                    setSheetState(() {
                                      _branchFilter = newId;
                                    });
                                    setState(() {});
                                  },
                                );
                              } else {
                                setSheetState(() => _branchFilter = val!);
                                setState(() {});
                              }
                            },
                          ),
                        );
                      },
                    ),
                  buildDropdownField(
                    label: 'Status',
                    value: _statusFilter,
                    items: const ['Active', 'Inactive', 'Archived', 'Temporary Leave', 'Left', 'All'],
                    onChanged: (val) {
                      setSheetState(() => _statusFilter = val!);
                      setState(() {});
                    },
                    theme: t,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('Show Results', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGroupedEmployeeList(RoleThemeData t, List<Map<String, dynamic>> list) {
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final emp in list) {
      final branchKey = _normalizeBranchKey(emp);
      final deptKey = _normalizeDepartmentKey(emp);
      grouped.putIfAbsent(branchKey, () => {});
      grouped[branchKey]!.putIfAbsent(deptKey, () => []);
      grouped[branchKey]![deptKey]!.add(emp);
    }

    final sortedBranches = grouped.keys.toList()..sort((a, b) {
      if (a == 'Unassigned') return 1;
      if (b == 'Unassigned') return -1;
      return a.compareTo(b);
    });

    final displayItems = <Map<String, dynamic>>[];
    for (final branchKey in sortedBranches) {
      final branchDepts = grouped[branchKey]!;
      final sortedDepartments = branchDepts.keys.toList()..sort((a, b) {
        if (a == 'Unassigned') return 1;
        if (b == 'Unassigned') return -1;
        return a.compareTo(b);
      });

      final branchCount = sortedDepartments.fold<int>(0, (count, deptKey) => count + branchDepts[deptKey]!.length);
      displayItems.add({'type': 'branchHeader', 'branchName': _displayBranchName(branchKey), 'count': branchCount});

      for (final deptKey in sortedDepartments) {
        final deptItems = List<Map<String, dynamic>>.from(branchDepts[deptKey]!..sort((a, b) {
          final aName = (a['name'] ?? '').toString().toLowerCase();
          final bName = (b['name'] ?? '').toString().toLowerCase();
          return aName.compareTo(bName);
        }));
        displayItems.add({'type': 'departmentHeader', 'departmentName': deptKey, 'count': deptItems.length});
        for (final emp in deptItems) {
          displayItems.add({'type': 'employee', 'employee': emp});
        }
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      itemCount: displayItems.length,
      itemBuilder: (ctx, i) {
        final item = displayItems[i];
        switch (item['type']) {
          case 'branchHeader':
            return _buildBranchHeader(item['branchName'] as String, item['count'] as int, t);
          case 'departmentHeader':
            return _buildDepartmentHeader(item['departmentName'] as String, item['count'] as int, t);
          default:
            return _buildEmployeeRow(t, item['employee'] as Map<String, dynamic>);
        }
      },
    );
  }

  Widget _buildBranchHeader(String branchName, int count, RoleThemeData t) {
    final col = _mutedColorForKey(branchName);
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(width: 6, height: 24, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(
            branchName.toUpperCase(),
            style: TextStyle(
              color: col.withOpacity(0.95),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: col.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count EMPLOYEES',
              style: TextStyle(
                color: col.withOpacity(0.95),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentHeader(String departmentName, int count, RoleThemeData t) {
    final col = _mutedColorForKey(departmentName);
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.bgCardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.bgRule),
      ),
      child: Row(
        children: [
          Icon(Icons.label_outline_rounded, color: col.withOpacity(0.95), size: 16),
          const SizedBox(width: 8),
          Text(
            departmentName.toUpperCase(),
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: col.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count EMPLOYEES',
              style: TextStyle(
                color: col.withOpacity(0.95),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Employee row ───────────────────────────────────────────────────────────
  // Redesign plan §3.C + §4: dense list row, not a boxed/shadowed card.
  // Salary rate stays as muted secondary text; "Advance" only renders as a
  // pill when non-zero — a zero balance is a null result and shouldn't
  // compete for attention with real ones.
  Widget _buildEmployeeRow(RoleThemeData t, Map<String, dynamic> emp) {
    final name = emp['name']?.toString() ?? '';
    final role = emp['role']?.toString() ?? '';
    final dept = emp['department']?.toString() ?? '';
    final empId = emp['localId']?.toString() ?? '';
    final isActive = emp['isActive'] as bool? ?? true;
    final status = emp['status'] as String? ?? (isActive ? 'Active' : 'Left');
    final branchName = _getBranchName(emp['branchId']?.toString() ?? '');

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.bgRule, width: 0.75),
      ),
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _showEmployeeDetailDrawer(context, empId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: Column(
                  children: [
                    Container(width: 4, height: 36, decoration: BoxDecoration(color: _mutedColorForKey(branchName), borderRadius: BorderRadius.circular(2))),
                  ],
                ),
              ),
              buildInitialsAvatar(
                name: name,
                theme: t,
                radius: 16,
                imageUrl: emp['profilePictureUrl']?.toString(),
                imagePath: emp['profilePicturePath']?.toString(),
              ),
                  const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.textPrimary), overflow: TextOverflow.ellipsis),
                        ),
                        if (!isActive) ...[
                          const SizedBox(width: 6),
                          buildStatusPill(theme: t, label: status.toUpperCase(), variant: StatusPillVariant.danger),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$role • $dept',
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                    if (branchName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 11, color: t.textTertiary),
                          const SizedBox(width: 4),
                          Text(branchName, style: TextStyle(fontSize: 11, color: t.textTertiary)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(RoleThemeData t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined, size: 54, color: t.textTertiary),
          const SizedBox(height: 14),
          Text('No employees found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textSecondary)),
          const SizedBox(height: 6),
          Text('Register a new employee to get started.', style: TextStyle(fontSize: 12, color: t.textTertiary)),
        ],
      ),
    );
  }

  void _showEmployeeDetailDrawer(BuildContext context, String employeeId) {
    final tOriginal = RoleThemeScope.dataOf(context);
    final t = RoleThemeData(
      roleLabel: tOriginal.roleLabel,
      isDarkCanvas: false,
      bg: const Color(0xFFF8FAFC),
      bgCard: Colors.white,
      bgCardAlt: const Color(0xFFF1F5F9),
      bgRule: const Color(0xFFE2E8F0),
      accent: const Color(0xFF10B981),
      accentLight: const Color(0xFF34D399),
      accentMuted: const Color(0xFFD1FAE5),
      accentGradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
      glassTint: const Color(0x1A10B981),
      textPrimary: const Color(0xFF111827),
      textSecondary: const Color(0xFF6B7280),
      textTertiary: const Color(0xFF9CA3AF),
      danger: const Color(0xFFEF4444),
      zakat: tOriginal.zakat,
      nonZakat: tOriginal.nonZakat,
      gmwf: tOriginal.gmwf,
      cardFillTokens: tOriginal.cardFillTokens,
      cardFillPrescriptions: tOriginal.cardFillPrescriptions,
      cardFillDispensary: tOriginal.cardFillDispensary,
      chartBar1: tOriginal.chartBar1,
      chartBar2: tOriginal.chartBar2,
      chartBar3: tOriginal.chartBar3,
      chartGrid: tOriginal.chartGrid,
    );
    final ps = PermissionService();
    DateTime calendarMonth = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return RoleThemeScope(
          role: RoleTheme.admin,
          child: StatefulBuilder(
            builder: (drawerCtx, setDrawerState) {
            final emp = FinanceLocalStorage.getEmployee(employeeId);
            if (emp == null) return const Center(child: Text('Employee profile deleted.'));

            final name = emp['name']?.toString() ?? '';
            final role = emp['role']?.toString() ?? '';
            final dept = emp['department']?.toString() ?? '';
            final cnic = emp['cnic']?.toString() ?? '';
            final phone = emp['phone']?.toString() ?? '';
            final salary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
            final advance = (emp['currentAdvanceBalance'] as num?)?.toDouble() ?? 0.0;
            final isActive = emp['isActive'] as bool? ?? true;

            final history = FinanceLocalStorage.getSalaryHistory(employeeId);
            final transfers = FinanceLocalStorage.getTransfersForEmployee(employeeId);
            final auditLogs = FinanceLocalStorage.getAuditLogsForEmployee(employeeId);

            final curRole = widget.userRole.toLowerCase().trim();
            final empRole = (emp['role']?.toString() ?? emp['designation']?.toString() ?? '').toLowerCase().trim();
            final empDept = (emp['department']?.toString() ?? '').toLowerCase().trim();
            final isExecOrAdmin = empRole == 'ceo' ||
                empRole == 'hq manager' ||
                empRole == 'hq_manager' ||
                empRole == 'admin' ||
                empRole == 'chairman' ||
                empDept == 'administration';
            final canEditEmp = curRole == 'chairman' || (!isExecOrAdmin);

            return DefaultTabController(
              length: 4,
              child: Container(
                height: MediaQuery.of(drawerCtx).size.height * 0.85,
                padding: const EdgeInsets.all(16),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Employee Detail Card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
                      Row(
                        children: [
                          if (isActive && canEditEmp) ...[
                            Tooltip(
                              message: 'Edit Profile',
                              child: IconButton(
                                icon: Icon(Icons.edit_outlined, color: t.accent),
                                onPressed: () {
                                  Navigator.pop(drawerCtx);
                                  widget.openEmployeeForm(context, employeeId);
                                },
                              ),
                            ),
                            if (ps.hasPermission(widget.userRole, AppPermission.transferEmployeeBranch))
                              Tooltip(
                                message: 'Transfer Branch',
                                child: IconButton(
                                  icon: Icon(Icons.compare_arrows_rounded, color: t.accent),
                                  onPressed: () => _openTransferDialog(context, employeeId, emp['branchId']),
                                ),
                              ),
                          ],
                          Tooltip(
                            message: 'Full Employee Report',
                            child: IconButton(
                              icon: Icon(Icons.insert_chart_outlined_rounded, color: t.accent),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => EmployeeReportPage(employeeId: employeeId)),
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Download Profile PDF',
                            child: IconButton(
                              icon: Icon(Icons.download_outlined, color: t.accent),
                              onPressed: () => FinanceReportHelper.exportIndividualPdf(employeeId),
                            ),
                          ),
                          Tooltip(
                            message: 'Download Payment History PDF',
                            child: IconButton(
                              icon: Icon(Icons.receipt_long_outlined, color: t.accent),
                              onPressed: () => FinanceReportHelper.exportPaymentReportPdf(employeeId),
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(drawerCtx)),
                        ],
                      ),
                    ],
                  ),
                    const SizedBox(height: 8),
                    TabBar(
                      labelColor: t.accent,
                      unselectedLabelColor: t.textTertiary,
                      indicatorColor: t.accent,
                      tabs: const [
                        Tab(text: 'Profile', icon: Icon(Icons.person_outline, size: 18)),
                        Tab(text: 'Attendance', icon: Icon(Icons.calendar_today_outlined, size: 18)),
                        Tab(text: 'Leaves', icon: Icon(Icons.offline_pin_outlined, size: 18)),
                        Tab(text: 'History', icon: Icon(Icons.history_outlined, size: 18)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Tab 1: Profile Details & Actions
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Column(
                                    children: [
                                      buildInitialsAvatar(
                                        name: name,
                                        theme: t,
                                        radius: 36,
                                        imageUrl: emp['profilePictureUrl']?.toString(),
                                        imagePath: emp['profilePicturePath']?.toString(),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: t.textPrimary)),
                                      const SizedBox(height: 2),
                                      Text('$role • $dept', style: TextStyle(fontSize: 13, color: t.textSecondary)),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          _buildInfoChip(Icons.badge, cnic, t),
                                          _buildInfoChip(Icons.phone, phone, t),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildDetailSectionHeader('Job & Financial Details', t),
                                _buildDetailRow('Joining Date', emp['joiningDate'] ?? 'N/A', t),
                                _buildDetailRow('Current Branch', '${_getBranchName(emp['branchId']?.toString() ?? '')} (${emp['branchId']?.toString().toUpperCase() ?? 'N/A'})', t),
                                _buildDetailRow('Compensation', _sentenceCase(emp['compensationType']?.toString()), t),
                                _buildDetailRow('Base Salary', 'PKR ${NumberFormat('#,###').format(salary)}', t),
                                _buildDetailRow('Bank Name', emp['bankName']?.toString().isNotEmpty == true ? emp['bankName'] : 'N/A', t),
                                _buildDetailRow('Account / IBAN', emp['bankAccount']?.toString().isNotEmpty == true ? emp['bankAccount'] : 'N/A', t),
                                _buildDetailRow('Education', emp['education'] ?? 'N/A', t),

                                const SizedBox(height: 20),
                                _buildDetailSectionHeader('Personal Details', t),
                                _buildDetailRow('Gender', emp['gender'] ?? 'N/A', t),
                                _buildDetailRow('DOB (Date of Birth)', emp['dob'] ?? 'N/A', t),
                                _buildDetailRow('Marital Status', emp['maritalStatus'] ?? 'N/A', t),
                                _buildDetailRow(emp['relationshipType'] ?? 'Father/Spouse', emp['relationshipName'] ?? 'N/A', t),
                                _buildDetailRow('CNIC Expiry', emp['cnicExpiry'] ?? 'N/A', t),
                                _buildDetailRow('Address', emp['currentAddress'] ?? 'N/A', t),

                                if (emp['workScheduleOverride'] != null) ...[
                                  const SizedBox(height: 20),
                                  _buildDetailSectionHeader('Work Schedule (Override)', t),
                                  _buildDetailRow('Winter shift', emp['workScheduleOverride']['winter'] ?? 'N/A', t),
                                  _buildDetailRow('Summer shift', emp['workScheduleOverride']['summer'] ?? 'N/A', t),
                                ],

                                const SizedBox(height: 20),
                                _buildDetailSectionHeader('Emergency Contacts', t),
                                if (emp['emergencyContacts'] == null || (emp['emergencyContacts'] as List).isEmpty)
                                  Text('No emergency contacts recorded.', style: TextStyle(color: t.textTertiary, fontSize: 12))
                                else
                                  ...(emp['emergencyContacts'] as List).map((ec) {
                                    final c = Map<String, dynamic>.from(ec as Map);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(8)),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(c['name'] ?? '', style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                                              Text(c['relation'] ?? '', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                            ],
                                          ),
                                          Text(c['phone'] ?? '', style: TextStyle(color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    );
                                  }),

                                const SizedBox(height: 30),
                                if (isActive)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.withOpacity(0.12),
                                      foregroundColor: Colors.red,
                                      elevation: 0,
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.red, width: 0.5)),
                                    ),
                                    icon: const Icon(Icons.person_off_outlined),
                                    label: const Text('Offboard Employee (Deactivate)', style: TextStyle(fontWeight: FontWeight.bold)),
                                    onPressed: () => _showDeactivateDialog(drawerCtx, employeeId, setDrawerState),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: t.accent.withOpacity(0.12),
                                          foregroundColor: t.accent,
                                          elevation: 0,
                                          minimumSize: const Size.fromHeight(48),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t.accent, width: 0.5)),
                                        ),
                                        icon: const Icon(Icons.person_add_alt_1_outlined),
                                        label: const Text('Reactivate Employee', style: TextStyle(fontWeight: FontWeight.bold)),
                                        onPressed: () async {
                                          try {
                                            final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
                                            final employeeRecord = FinanceLocalStorage.getEmployee(employeeId)!;
                                            employeeRecord['isActive'] = true;
                                            employeeRecord['status'] = 'Active';
                                            employeeRecord['exitDate'] = null;

                                            await FinanceLocalStorage.saveEmployee(
                                              branchId: widget.branchId,
                                              data: employeeRecord,
                                              performedBy: curUser,
                                            );

                                            await FinanceLocalStorage.logAction(
                                              branchId: widget.branchId,
                                              entityType: 'employee',
                                              entityId: employeeId,
                                              action: 'update',
                                              performedBy: curUser,
                                              reason: 'Reactivated employee profile.',
                                            );

                                            Navigator.pop(drawerCtx);
                                            showCustomSnackBar(context, 'Employee reactivated successfully!');
                                          } catch (e) {
                                            showCustomSnackBar(drawerCtx, 'Failed to reactivate: $e', error: true);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.withOpacity(0.12),
                                          foregroundColor: Colors.red,
                                          elevation: 0,
                                          minimumSize: const Size.fromHeight(48),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.red, width: 0.5)),
                                        ),
                                        icon: const Icon(Icons.delete_forever_outlined),
                                        label: const Text('Delete Employee Profile (Permanent)', style: TextStyle(fontWeight: FontWeight.bold)),
                                        onPressed: () => _confirmDeleteEmployee(drawerCtx, employeeId),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),

                          // Tab 2: Attendance Calendar
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailSectionHeader('Attendance Record (Calendar)', t),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.chevron_left, color: t.textPrimary),
                                      onPressed: () {
                                        setDrawerState(() {
                                          calendarMonth = DateTime(calendarMonth.year, calendarMonth.month - 1, 1);
                                        });
                                      },
                                    ),
                                    Text(
                                      DateFormat('MMMM yyyy').format(calendarMonth),
                                      style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.chevron_right, color: t.textPrimary),
                                      onPressed: calendarMonth.year >= DateTime.now().year && calendarMonth.month >= DateTime.now().month
                                          ? null
                                          : () {
                                              setDrawerState(() {
                                                calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + 1, 1);
                                              });
                                            },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                GridView.count(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisCount: 7,
                                  childAspectRatio: 1.5,
                                  children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) => Center(
                                    child: Text(day, style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
                                  )).toList(),
                                ),
                                const SizedBox(height: 4),
                                _buildCalendarDaysGrid(employeeId, emp, calendarMonth, t),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),

                          // Tab 3: Leave Quotas with Progress Bars
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailSectionHeader('Annual Leave Balances (${DateTime.now().year})', t),
                                const SizedBox(height: 14),
                                Builder(
                                  builder: (context) {
                                    final usage = FinanceLocalStorage.getLeaveUsage(employeeId, DateTime.now().year);
                                    final quotas = FinanceLocalStorage.getLeaveQuotas();

                                    Widget _buildQuotaProgressRow(String type, double used, int quota, Color color) {
                                      final remaining = (quota - used).clamp(0.0, quota.toDouble());
                                      final progress = (used / quota).clamp(0.0, 1.0);
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: t.bgCardAlt,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: t.bgRule),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  '${type.toUpperCase()} LEAVES',
                                                  style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                                Text(
                                                  'Used: ${used.toStringAsFixed(used % 1 == 0 ? 0 : 1)} / $quota  |  Remaining: ${remaining.toStringAsFixed(remaining % 1 == 0 ? 0 : 1)}',
                                                  style: TextStyle(color: remaining > 0 ? t.accent : t.danger, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: progress,
                                                minHeight: 8,
                                                backgroundColor: t.bgCard,
                                                valueColor: AlwaysStoppedAnimation<Color>(color),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return Column(
                                      children: [
                                        _buildQuotaProgressRow('Sick', usage['sick'] ?? 0.0, quotas['sick'] ?? 10, Colors.orange),
                                        _buildQuotaProgressRow('Casual', usage['casual'] ?? 0.0, quotas['casual'] ?? 12, Colors.blue),
                                        _buildQuotaProgressRow('Annual', usage['annual'] ?? 0.0, quotas['annual'] ?? 15, Colors.green),
                                        if ((usage['unpaid'] ?? 0.0) > 0.0)
                                          Container(
                                            margin: const EdgeInsets.only(bottom: 6),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.05),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.red.withOpacity(0.1)),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'UNPAID LEAVE',
                                                    style: TextStyle(color: Colors.red[800], fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                Text(
                                                  'Used: ${(usage['unpaid'] ?? 0.0).toStringAsFixed((usage['unpaid'] ?? 0.0) % 1 == 0 ? 0 : 1)} days',
                                                  style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),

                          // Tab 4: Ledger & History Logs
                          SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('SALARY ADJUSTMENTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t.accent, letterSpacing: 1.2)),
                                    if (isActive)
                                      TextButton.icon(
                                        onPressed: () => _openSalaryAdjustmentDialog(context, employeeId, salary, () {
                                          setDrawerState(() {});
                                        }),
                                        icon: const Icon(Icons.trending_up, size: 14),
                                        label: const Text('Adjust / Increment', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (history.isEmpty)
                                  Text('No salary adjustments recorded.', style: TextStyle(color: t.textTertiary, fontSize: 12))
                                else
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: history.length,
                                    itemBuilder: (ctx, idx) {
                                      final h = history[idx];
                                      final isRetro = h['isRetroactive'] == true;
                                      return Card(
                                        color: t.bgCardAlt,
                                        elevation: 0,
                                        margin: const EdgeInsets.only(bottom: 6),
                                        child: ListTile(
                                          dense: true,
                                          title: Row(
                                            children: [
                                              Text('PKR ${NumberFormat('#,###').format(h['amount'])}', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 6),
                                              if (isRetro)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                                                  child: const Text('RETROACTIVE', style: TextStyle(color: Colors.purple, fontSize: 8, fontWeight: FontWeight.bold)),
                                                )
                                            ],
                                          ),
                                          subtitle: Text('${h['reason']}\nApproved by: ${h['approvedBy']}', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                          trailing: Text(DateFormat('yyyy-MM-dd').format(DateTime.parse(h['effectiveDate'])), style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ),
                                      );
                                    },
                                  ),

                                const SizedBox(height: 20),
                                _buildDetailSectionHeader('Branch Transfer History', t),
                                if (transfers.isEmpty)
                                  Text('No transfer logs found.', style: TextStyle(color: t.textTertiary, fontSize: 12))
                                else
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: transfers.length,
                                    itemBuilder: (ctx, idx) {
                                      final tr = transfers[idx];
                                      return Card(
                                        color: t.bgCardAlt,
                                        elevation: 0,
                                        margin: const EdgeInsets.only(bottom: 6),
                                        child: ListTile(
                                          dense: true,
                                          leading: const Icon(Icons.compare_arrows_rounded, color: Colors.blue),
                                          title: Text('${tr['fromBranchId'].toString().toUpperCase()} ➔ ${tr['toBranchId'].toString().toUpperCase()}', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
                                          subtitle: Text('${tr['reason']}\nRequested by: ${tr['requestedBy']}\nApproved by: ${tr['approvedBy']}', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                          trailing: Text(DateFormat('yyyy-MM-dd').format(DateTime.parse(tr['effectiveDate'])), style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ),
                                      );
                                    },
                                  ),

                                const SizedBox(height: 20),
                                _buildDetailSectionHeader('Profile Change History', t),
                                if (auditLogs.isEmpty)
                                  Text('No profile changes recorded.', style: TextStyle(color: t.textTertiary, fontSize: 12))
                                else
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: auditLogs.length,
                                    itemBuilder: (ctx, idx) {
                                      final log = auditLogs[idx];
                                      final action = log['action']?.toString().toUpperCase() ?? '';
                                      final performedBy = log['performedBy'] ?? 'System';
                                      final timestamp = log['timestamp'] != null 
                                          ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(log['timestamp']).toLocal()) 
                                          : 'N/A';
                                      final List changes = log['fieldChanges'] ?? [];

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: t.bgCardAlt,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: t.bgRule),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  action == 'CREATE' ? '🎉 Profile Created' : '📝 Profile Updated',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: action == 'CREATE' ? Colors.green : t.accent,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(timestamp, style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text('By: $performedBy', style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                                            if (changes.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Divider(color: t.bgRule, height: 1),
                                              const SizedBox(height: 6),
                                              ...changes.map((c) {
                                                final field = c['field']?.toString() ?? '';
                                                final oldVal = c['oldValue'] ?? 'None';
                                                final newVal = c['newValue'] ?? 'None';

                                                String fieldName = field;
                                                if (field == 'relationshipName') fieldName = 'Father/Spouse Name';
                                                if (field == 'relationshipType') fieldName = 'Relation';
                                                if (field == 'dob') fieldName = 'Date of Birth';
                                                if (field == 'cnicExpiry') fieldName = 'CNIC Expiry';
                                                if (field == 'alternatePhone') fieldName = 'Alternate Phone';
                                                if (field == 'maritalStatus') fieldName = 'Marital Status';
                                                if (field == 'joiningDate') fieldName = 'Joining Date';
                                                if (field == 'compensationType') fieldName = 'Pay Type';
                                                if (field == 'currentSalary') fieldName = 'Base Salary';
                                                if (field == 'bankName') fieldName = 'Bank Name';
                                                if (field == 'bankAccount') fieldName = 'Account Number';
                                                if (field == 'currentAddress') fieldName = 'Address';
                                                if (field == 'winterShift') fieldName = 'Winter Shift';
                                                if (field == 'summerShift') fieldName = 'Summer Shift';
                                                if (field == 'gender') fieldName = 'Gender';

                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                                  child: Text(
                                                    '• $fieldName: "$oldVal" ➔ "$newVal"',
                                                    style: TextStyle(fontSize: 11, color: t.textPrimary),
                                                  ),
                                                );
                                              }),
                                            ]
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

  Map<String, dynamic> _previewProjectedArrears({
    required String employeeId,
    required double newSalary,
    required double oldSalary,
    required DateTime effectiveDate,
  }) {
    final today = DateTime.now();
    DateTime checkDate = DateTime(effectiveDate.year, effectiveDate.month, 15);
    final limitDate = DateTime(today.year, today.month, 1);
    
    double totalArrears = 0.0;
    int affectedMonthsCount = 0;
    final List<String> affectedMonths = [];

    final delta = newSalary - oldSalary;
    if (delta <= 0) {
      return {'count': 0, 'amount': 0.0, 'months': []};
    }

    while (checkDate.isBefore(limitDate)) {
      final mKey = DateFormat('yyyy-MM').format(checkDate);
      
      final payouts = FinanceLocalStorage.salaryLedgerBox.values.where((val) {
        if (val is! Map) return false;
        final entry = Map<String, dynamic>.from(val);
        return entry['employeeId'] == employeeId &&
               entry['monthKey'] == mKey &&
               entry['type'] == 'payout' &&
               entry['isVoided'] != true;
      }).toList();

      if (payouts.isNotEmpty) {
        totalArrears += delta;
        affectedMonthsCount++;
        affectedMonths.add(mKey);
      }

      checkDate = DateTime(checkDate.year, checkDate.month + 1, 15);
    }

    return {
      'count': affectedMonthsCount,
      'amount': totalArrears,
      'months': affectedMonths,
    };
  }

  void _openSalaryAdjustmentDialog(
    BuildContext context,
    String employeeId,
    double currentSalary,
    VoidCallback onUpdated,
  ) {
    final t = RoleThemeScope.dataOf(context);
    final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

    String adjustmentType = 'Percentage Raise (%)';
    final valueController = TextEditingController();
    final approvedByController = TextEditingController(text: curUser);
    final reasonController = TextEditingController();
    final effectiveDateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Adjust Salary / Increment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Current Base Salary: PKR ${NumberFormat('#,###').format(currentSalary)}', style: TextStyle(color: t.textSecondary, fontSize: 13)),
                    const SizedBox(height: 14),

                    buildDropdownField(
                      label: 'Adjustment Type *',
                      value: adjustmentType,
                      items: const ['Percentage Raise (%)', 'Fixed Raise (PKR)', 'Set New Salary (PKR)'],
                      onChanged: (val) {
                        setSheetState(() {
                          adjustmentType = val!;
                        });
                      },
                      theme: t,
                    ),
                    const SizedBox(height: 10),

                    buildFormField(
                      controller: valueController,
                      label: adjustmentType == 'Percentage Raise (%)' ? 'Percentage Value (e.g. 10) *' : 'Amount (PKR) *',
                      icon: Icons.payments,
                      theme: t,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 10),

                    buildDatePickerField(
                      context: sheetCtx,
                      controller: effectiveDateController,
                      label: 'Effective Date *',
                      icon: Icons.calendar_today,
                      theme: t,
                      onChanged: () => setSheetState(() {}),
                    ),
                    const SizedBox(height: 10),

                    buildFormField(
                      controller: approvedByController,
                      label: 'Approved By *',
                      icon: Icons.verified_user,
                      theme: t,
                    ),
                    const SizedBox(height: 10),

                    buildFormField(
                      controller: reasonController,
                      label: 'Reason / Remarks *',
                      icon: Icons.note_alt_outlined,
                      theme: t,
                    ),
                    const SizedBox(height: 15),

                    // Projected Arrears Preview
                    Builder(
                      builder: (context) {
                        final valStr = valueController.text.trim();
                        final val = double.tryParse(valStr) ?? 0.0;
                        double targetSalary = currentSalary;
                        if (adjustmentType == 'Percentage Raise (%)') {
                          targetSalary = currentSalary * (1 + val / 100);
                        } else if (adjustmentType == 'Fixed Raise (PKR)') {
                          targetSalary = currentSalary + val;
                        } else if (adjustmentType == 'Set New Salary (PKR)') {
                          targetSalary = val;
                        }

                        targetSalary = targetSalary.roundToDouble();

                        DateTime? effDate;
                        try {
                          effDate = DateTime.parse(effectiveDateController.text);
                        } catch (_) {}

                        if (effDate != null && effDate.isBefore(DateTime.now()) && targetSalary > currentSalary) {
                          final preview = _previewProjectedArrears(
                            employeeId: employeeId,
                            newSalary: targetSalary,
                            oldSalary: currentSalary,
                            effectiveDate: effDate,
                          );

                          final count = preview['count'] as int;
                          final amount = preview['amount'] as double;
                          final months = preview['months'] as List<String>;

                          if (count > 0) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.purple.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.info_outline, color: Colors.purple, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Retroactive Arrears Preview',
                                        style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'This change is retroactive and will generate arrears for $count paid month(s): ${months.join(", ")}.',
                                    style: TextStyle(color: t.textSecondary, fontSize: 11),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Total Projected Arrears: PKR ${NumberFormat('#,###').format(amount)}',
                                    style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                        return const SizedBox.shrink();
                      }
                    ),
                    const SizedBox(height: 10),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final valStr = valueController.text.trim();
                        final val = double.tryParse(valStr) ?? 0.0;
                        if (valStr.isEmpty || val <= 0) {
                          showCustomSnackBar(sheetCtx, 'Please enter a valid positive value.', error: true);
                          return;
                        }

                        final approver = approvedByController.text.trim();
                        if (approver.isEmpty) {
                          showCustomSnackBar(sheetCtx, 'Please specify who approved this adjustment.', error: true);
                          return;
                        }

                        final reason = reasonController.text.trim();
                        if (reason.isEmpty) {
                          showCustomSnackBar(sheetCtx, 'Please specify the reason.', error: true);
                          return;
                        }

                        final effDateStr = effectiveDateController.text.trim();
                        if (effDateStr.isEmpty) {
                          showCustomSnackBar(sheetCtx, 'Please select an effective date.', error: true);
                          return;
                        }

                        double newSalary = currentSalary;
                        if (adjustmentType == 'Percentage Raise (%)') {
                          newSalary = currentSalary * (1 + val / 100);
                        } else if (adjustmentType == 'Fixed Raise (PKR)') {
                          newSalary = currentSalary + val;
                        } else if (adjustmentType == 'Set New Salary (PKR)') {
                          newSalary = val;
                        }

                        newSalary = newSalary.roundToDouble();

                        try {
                          final emp = FinanceLocalStorage.getEmployee(employeeId);
                          if (emp == null) throw Exception('Employee not found.');

                          final effectiveDateTime = DateTime.parse(effDateStr);

                          await FinanceLocalStorage.saveSalaryHistory(
                            branchId: emp['branchId'] ?? widget.branchId,
                            employeeId: employeeId,
                            amount: newSalary,
                            effectiveDate: effectiveDateTime,
                            reason: reason,
                            approvedBy: approver,
                            performedBy: curUser,
                          );

                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx);
                            showCustomSnackBar(context, 'Salary updated successfully. New Salary: PKR ${NumberFormat('#,###').format(newSalary)}');
                          }
                          onUpdated();
                        } catch (e) {
                          showCustomSnackBar(sheetCtx, 'Failed: $e', error: true);
                        }
                      },
                      child: const Text('Apply Salary Adjustment', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openAnnualIncrementsDialog(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

    int targetYear = DateTime.now().year;
    final percentCtrl = TextEditingController(text: '10');
    final approvedByCtrl = TextEditingController(text: curUser);
    final reasonCtrl = TextEditingController(text: 'Annual 10% Increment');

    final Map<String, bool> selectedEmployees = {};
    final List<String> eligibleIds = [];
    bool showEligibleOnly = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final percent = double.tryParse(percentCtrl.text) ?? 10.0;
            final cutoffDate = DateTime(targetYear - 1, 5, 1);
            final activeEmployees = FinanceLocalStorage.getEmployees(widget.branchId)
                .where((e) => e['isActive'] == true)
                .toList();

            if (selectedEmployees.isEmpty) {
              for (final emp in activeEmployees) {
                final empId = emp['localId']?.toString() ?? '';
                final joinStr = emp['joiningDate']?.toString();
                bool isEligible = false;
                if (joinStr != null && joinStr.isNotEmpty) {
                  try {
                    final joinDate = DateTime.parse(joinStr);
                    if (joinDate.isBefore(cutoffDate) || joinDate.isAtSameMomentAs(cutoffDate)) {
                      isEligible = true;
                    }
                  } catch (_) {}
                }
                if (isEligible) {
                  eligibleIds.add(empId);
                  selectedEmployees[empId] = true;
                } else {
                  selectedEmployees[empId] = false;
                }
              }
            }

            final filteredEmployees = activeEmployees.where((emp) {
              if (showEligibleOnly) {
                final empId = emp['localId']?.toString() ?? '';
                return eligibleIds.contains(empId);
              }
              return true;
            }).toList();

            double currentTotalSalary = 0.0;
            double proposedTotalSalary = 0.0;
            int selectedCount = 0;
            for (final emp in activeEmployees) {
              final empId = emp['localId']?.toString() ?? '';
              final isSelected = selectedEmployees[empId] ?? false;
              if (isSelected) {
                final currentSalary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
                currentTotalSalary += currentSalary;
                proposedTotalSalary += (currentSalary * (1 + percent / 100)).roundToDouble();
                selectedCount++;
              }
            }
            final netPayrollIncrease = proposedTotalSalary - currentTotalSalary;

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.85,
              padding: EdgeInsets.only(
                top: 20,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Bulk Annual Increments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Rule: Applied on Jan 1st. Requires >= 8 months of work (joined on or before ${DateFormat('yyyy-MM-dd').format(cutoffDate)}).',
                    style: TextStyle(color: t.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 10),

                  // Projected Impact Summary Box
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: t.bgCardAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.bgRule),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PROJECTED PAYROLL IMPACT',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: t.accent, letterSpacing: 1.1),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Selected Employees', style: TextStyle(color: t.textSecondary, fontSize: 11)),
                            Text('$selectedCount', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Current Total Monthly Payroll', style: TextStyle(color: t.textSecondary, fontSize: 11)),
                            Text('PKR ${NumberFormat('#,###').format(currentTotalSalary)}', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Projected Total Monthly Payroll', style: TextStyle(color: t.textSecondary, fontSize: 11)),
                            Text('PKR ${NumberFormat('#,###').format(proposedTotalSalary)}', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Divider(color: t.bgRule, height: 1),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Projected Monthly Increase', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                            Text('+PKR ${NumberFormat('#,###').format(netPayrollIncrease)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: buildDropdownField(
                          label: 'Target Year',
                          value: targetYear.toString(),
                          items: [targetYear.toString(), (targetYear + 1).toString(), (targetYear - 1).toString()],
                          onChanged: (val) {
                            setSheetState(() {
                              targetYear = int.parse(val!);
                              selectedEmployees.clear();
                              eligibleIds.clear();
                              reasonCtrl.text = 'Annual ${percentCtrl.text}% Increment';
                            });
                          },
                          theme: t,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: buildFormField(
                          controller: percentCtrl,
                          label: 'Increment (%)',
                          icon: Icons.percent,
                          theme: t,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                          ],
                          onChanged: (_) {
                            setSheetState(() {
                              reasonCtrl.text = 'Annual ${percentCtrl.text}% Increment';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: buildFormField(
                          controller: approvedByCtrl,
                          label: 'Approved By *',
                          icon: Icons.verified_user,
                          theme: t,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: buildFormField(
                          controller: reasonCtrl,
                          label: 'Reason / Remarks *',
                          icon: Icons.note_alt_outlined,
                          theme: t,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Batch Controls & Filtering Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () {
                          setSheetState(() {
                            showEligibleOnly = !showEligibleOnly;
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: showEligibleOnly,
                                activeColor: t.accent,
                                onChanged: (val) {
                                  setSheetState(() {
                                    showEligibleOnly = val ?? false;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('Show Eligible Only', style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              setSheetState(() {
                                for (final empId in eligibleIds) {
                                  selectedEmployees[empId] = true;
                                }
                              });
                            },
                            child: const Text('Select Eligible', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              setSheetState(() {
                                for (final key in selectedEmployees.keys) {
                                  selectedEmployees[key] = false;
                                }
                              });
                            },
                            child: const Text('Clear All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'EMPLOYEE ELIGIBILITY LIST (${filteredEmployees.length} Shown)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: filteredEmployees.isEmpty
                        ? Center(child: Text('No employees found matching filters.', style: TextStyle(color: t.textTertiary)))
                        : ListView.builder(
                            itemCount: filteredEmployees.length,
                            itemBuilder: (ctx, idx) {
                              final emp = filteredEmployees[idx];
                              final empId = emp['localId']?.toString() ?? '';
                              final name = emp['name']?.toString() ?? '';
                              final role = emp['role']?.toString() ?? '';
                              final joinStr = emp['joiningDate']?.toString() ?? '';
                              final currentSalary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
                              final isEligible = eligibleIds.contains(empId);
                              
                              final proposedSalary = (currentSalary * (1 + percent / 100)).roundToDouble();

                              return Card(
                                color: t.bgCardAlt,
                                margin: const EdgeInsets.only(bottom: 6),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isEligible ? t.bgRule : Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  activeColor: t.accent,
                                  dense: true,
                                  title: Text(name, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('$role • Joined: ${joinStr.isNotEmpty ? joinStr : "N/A"}', style: TextStyle(color: t.textSecondary, fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text('PKR ${NumberFormat('#,###').format(currentSalary)} ➔ ', style: TextStyle(color: t.textTertiary, fontSize: 11)),
                                          Text('PKR ${NumberFormat('#,###').format(proposedSalary)}', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                                          const SizedBox(width: 8),
                                          if (!isEligible)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                                              child: const Text(
                                                '< 8 Months',
                                                style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  value: selectedEmployees[empId] ?? false,
                                  onChanged: (val) {
                                    setSheetState(() {
                                      selectedEmployees[empId] = val ?? false;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final approver = approvedByCtrl.text.trim();
                      if (approver.isEmpty) {
                        showCustomSnackBar(sheetCtx, 'Please specify who approved this adjustment.', error: true);
                        return;
                      }

                      final reason = reasonCtrl.text.trim();
                      if (reason.isEmpty) {
                        showCustomSnackBar(sheetCtx, 'Please specify the reason.', error: true);
                        return;
                      }

                      final selectedIds = selectedEmployees.entries
                          .where((entry) => entry.value == true)
                          .map((entry) => entry.key)
                          .toList();

                      if (selectedIds.isEmpty) {
                        showCustomSnackBar(sheetCtx, 'No employees selected for increment.', error: true);
                        return;
                      }

                      try {
                        final effectiveDateTime = DateTime(targetYear, 1, 1);

                        int count = 0;
                        for (final empId in selectedIds) {
                          final emp = activeEmployees.firstWhere((e) => e['localId'] == empId);
                          final currentSalary = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
                          final proposedSalary = (currentSalary * (1 + percent / 100)).roundToDouble();

                          await FinanceLocalStorage.saveSalaryHistory(
                            branchId: emp['branchId'] ?? widget.branchId,
                            employeeId: empId,
                            amount: proposedSalary,
                            effectiveDate: effectiveDateTime,
                            reason: reason,
                            approvedBy: approver,
                            performedBy: curUser,
                          );
                          count++;
                        }

                        if (sheetCtx.mounted) {
                          Navigator.pop(sheetCtx);
                          showCustomSnackBar(
                            context,
                            'Successfully applied annual increment to $count employees.',
                          );
                        }
                      } catch (e) {
                        showCustomSnackBar(sheetCtx, 'Failed: $e', error: true);
                      }
                    },
                    child: Text(
                      'Apply Increments to ${selectedEmployees.values.where((v) => v).length} Employees',
                      style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildInfoChip(IconData icon, String label, RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.bgRule)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: t.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildDetailSectionHeader(String label, RoleThemeData t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: t.accent, letterSpacing: 1.2)),
          const SizedBox(height: 2),
          Divider(color: t.bgRule, height: 1),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, RoleThemeData t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: t.textSecondary)),
          Text(value, style: TextStyle(fontSize: 13, color: t.textPrimary, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Sentence case instead of ALL CAPS — reads calmer, consistent with the
  // rest of the app (redesign plan §3.E).
  String _sentenceCase(String? s) {
    if (s == null || s.trim().isEmpty) return 'N/A';
    final lower = s.trim().toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  void _showDeactivateDialog(BuildContext sheetCtx, String employeeId, StateSetter setDrawerState) {
    final t = RoleThemeScope.dataOf(sheetCtx);
    final reasonController = TextEditingController();
    String selectedStatus = 'Left';

    showDialog(
      context: sheetCtx,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (diagCtx, setDiagState) {
            return AlertDialog(
              backgroundColor: t.bgCard,
              title: Text('Offboard Employee', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Are you sure you want to offboard this employee? This will toggle their status to inactive to preserve payroll records.',
                    style: TextStyle(color: t.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  buildDropdownField(
                    label: 'Offboarding Status *',
                    value: selectedStatus,
                    items: const ['Archived', 'Temporary Leave', 'Left'],
                    onChanged: (val) => setDiagState(() => selectedStatus = val!),
                    theme: t,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonController,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Offboarding Reason *',
                      labelStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.bgRule)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () async {
                    if (reasonController.text.trim().isEmpty) {
                      return;
                    }
                    try {
                      final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
                      final emp = FinanceLocalStorage.getEmployee(employeeId)!;
                      emp['isActive'] = false;
                      emp['status'] = selectedStatus;
                      emp['exitDate'] = DateFormat('yyyy-MM-dd').format(DateTime.now());

                      await FinanceLocalStorage.saveEmployee(
                        branchId: widget.branchId,
                        data: emp,
                        performedBy: curUser,
                      );

                      // Log soft delete audit
                      await FinanceLocalStorage.logAction(
                        branchId: widget.branchId,
                        entityType: 'employee',
                        entityId: employeeId,
                        action: 'update',
                        performedBy: curUser,
                        reason: 'Employee Deactivated as $selectedStatus. Reason: ${reasonController.text.trim()}',
                      );

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        Navigator.pop(sheetCtx); // close drawer
                        showCustomSnackBar(context, 'Employee offboarded.');
                      }
                    } catch (e) {
                      showCustomSnackBar(diagCtx, 'Failed: $e', error: true);
                    }
                  },
                  child: const Text('Offboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Branch Transfer Dialog ────────────────────────────────────────────────
  void _openTransferDialog(BuildContext context, String employeeId, String currentBranchId) {
    final t = RoleThemeScope.dataOf(context);
    String selectedToBranch = '';
    final reasonController = TextEditingController();
    final effectiveController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    bool loading = false;

    // Load available branches excluding current directly from Firestore list
    final availableBranches = widget.branches
        .where((b) => b['id'] != currentBranchId)
        .toList();

    if (availableBranches.isEmpty) {
      showCustomSnackBar(context, 'No other branches available for transfer.', error: true);
      return;
    }
    final List<String> dropdownItems = availableBranches.map((b) => "${b['name']} (${b['id']})").toList();
    String selectedDropdownItem = dropdownItems.first;
    selectedToBranch = availableBranches.first['id']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (diagCtx, setDiagState) {
            return AlertDialog(
              backgroundColor: t.bgCard,
              title: Text('Transfer Employee Branch', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildDropdownField(
                    label: 'Destination Branch *',
                    value: selectedDropdownItem,
                    items: dropdownItems,
                    onChanged: (val) {
                      if (val != null) {
                        setDiagState(() {
                          selectedDropdownItem = val;
                          final idx = dropdownItems.indexOf(val);
                          selectedToBranch = availableBranches[idx]['id']?.toString() ?? '';
                        });
                      }
                    },
                    theme: t,
                  ),
                  const SizedBox(height: 10),
                  buildDatePickerField(
                    context: diagCtx,
                    controller: effectiveController,
                    label: 'Effective Date *',
                    icon: Icons.calendar_today,
                    theme: t,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Transfer Reason *',
                      labelStyle: TextStyle(color: t.textTertiary, fontSize: 12),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.bgRule)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: t.accent),
                  onPressed: loading
                      ? null
                      : () async {
                          if (reasonController.text.trim().isEmpty) {
                            showCustomSnackBar(diagCtx, 'Transfer reason is required.', error: true);
                            return;
                          }
                          setDiagState(() => loading = true);
                          try {
                            final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

                            await FinanceLocalStorage.transferEmployee(
                              employeeId: employeeId,
                              fromBranchId: currentBranchId,
                              toBranchId: selectedToBranch,
                              reason: reasonController.text.trim(),
                              approvedBy: curUser, // In this flow, the current executive is the approver
                              performedBy: curUser,
                              effectiveDate: DateTime.parse(effectiveController.text),
                            );

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              Navigator.pop(context); // close drawer to refresh
                              showCustomSnackBar(context, 'Employee transfer requested successfully!');
                            }
                          } catch (e) {
                            showCustomSnackBar(diagCtx, e.toString(), error: true);
                          } finally {
                            setDiagState(() => loading = false);
                          }
                        },
                  child: Text(loading ? 'Processing...' : 'Transfer', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCalendarDaysGrid(String employeeId, Map<String, dynamic> emp, DateTime month, RoleThemeData t) {
    final year = month.year;
    final monthNum = month.month;
    final branchId = emp['branchId']?.toString() ?? '';
    final dept = emp['department']?.toString() ?? '';

    final firstDay = DateTime(year, monthNum, 1);
    final lastDay = DateTime(year, monthNum + 1, 0);

    final int prefixDays = firstDay.weekday - 1;
    final totalCells = prefixDays + lastDay.day;

    int presentCount = 0;
    int absentCount = 0;
    int leaveCount = 0;
    int holidayCount = 0;

    final days = <Widget>[];

    for (int i = 0; i < totalCells; i++) {
      if (i < prefixDays) {
        days.add(const SizedBox.shrink());
      } else {
        final dayNum = i - prefixDays + 1;
        final date = DateTime(year, monthNum, dayNum);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final isSunday = date.weekday == DateTime.sunday;
        final isHolidayDay = FinanceLocalStorage.isHoliday(
          branchId: branchId,
          department: dept,
          dateStr: dateStr,
        );

        final key = '${employeeId}_$dateStr';
        final val = FinanceLocalStorage.attendanceBox.get(key);

        String status = 'unmarked';
        String? leaveType;
        if (val is Map) {
          status = val['status']?.toString() ?? 'absent';
          leaveType = val['leaveType']?.toString();
        } else {
          if (isSunday) {
            status = 'off';
          } else if (isHolidayDay) {
            status = 'holiday';
          }
        }

        Color cellBg = Colors.transparent;
        Color textCol = t.textPrimary;
        Border? cellBorder = Border.all(color: t.bgRule);

        if (status == 'present' || status == 'late') {
          cellBg = Colors.green.withValues(alpha: 0.15);
          textCol = t.isDarkCanvas ? Colors.green[300]! : Colors.green[700]!;
          cellBorder = Border.all(color: Colors.green.withValues(alpha: 0.3));
          presentCount++;
        } else if (status == 'absent') {
          cellBg = Colors.red.withValues(alpha: 0.15);
          textCol = t.isDarkCanvas ? Colors.red[300]! : Colors.red[700]!;
          cellBorder = Border.all(color: Colors.red.withValues(alpha: 0.3));
          absentCount++;
        } else if (status == 'leave') {
          cellBg = Colors.orange.withValues(alpha: 0.15);
          textCol = t.isDarkCanvas ? Colors.orange[300]! : Colors.orange[700]!;
          cellBorder = Border.all(color: Colors.orange.withValues(alpha: 0.3));
          leaveCount++;
        } else if (status == 'half_day') {
          cellBg = Colors.blue.withValues(alpha: 0.15);
          textCol = t.isDarkCanvas ? Colors.blue[300]! : Colors.blue[700]!;
          cellBorder = Border.all(color: Colors.blue.withValues(alpha: 0.3));
          presentCount++;
        } else if (status == 'off' || status == 'holiday' || isHolidayDay) {
          cellBg = t.accent.withValues(alpha: 0.08);
          textCol = t.accent;
          cellBorder = Border.all(color: t.accent.withValues(alpha: 0.2));
          holidayCount++;
        }

        days.add(
          Tooltip(
            message: 'Date: $dateStr\nStatus: ${status.toUpperCase()}${leaveType != null ? " ($leaveType)" : ""}',
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: cellBg,
                borderRadius: BorderRadius.circular(6),
                border: cellBorder,
              ),
              child: Center(
                child: Text(
                  dayNum.toString(),
                  style: TextStyle(color: textCol, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 7,
          childAspectRatio: 1.3,
          children: days,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatIndicator('P', '$presentCount', Colors.green, t),
            _buildStatIndicator('A', '$absentCount', Colors.red, t),
            _buildStatIndicator('L', '$leaveCount', Colors.orange, t),
            _buildStatIndicator('H/O', '$holidayCount', t.accent, t),
          ],
        ),
      ],
    );
  }

  void _confirmDeleteEmployee(BuildContext context, String employeeId) {
    final t = RoleThemeScope.dataOf(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: t.bgCard,
          title: Text('Delete Employee Profile', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to permanently delete this employee\'s profile? This action is irreversible and will delete all their details from both the local database and Firestore.', style: TextStyle(color: t.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);
                try {
                  final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';
                  await FinanceLocalStorage.deleteEmployeePermanently(
                    branchId: widget.branchId,
                    employeeId: employeeId,
                    performedBy: curUser,
                  );
                  showCustomSnackBar(context, 'Employee profile permanently deleted.');
                } catch (e) {
                  showCustomSnackBar(context, 'Failed to delete: $e', error: true);
                }
              },
              child: const Text('Delete Permanently', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatIndicator(String label, String val, Color color, RoleThemeData t) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 6),
        Text(val, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  void _openBulkBackfillDialog(BuildContext context, String employeeId, String employeeName) {
    final t = RoleThemeScope.dataOf(context);
    final curUser = Hive.box('local_users').values.firstOrNull?['username']?.toString() ?? 'Admin';

    int startMonthsAgo = 3;
    final salaryCtrl = TextEditingController();
    final approvedByCtrl = TextEditingController(text: curUser);
    String defaultStatus = 'present'; // present, absent, off

    final emp = FinanceLocalStorage.getEmployee(employeeId);
    if (emp != null) {
      final double s = (emp['currentSalary'] as num?)?.toDouble() ?? 0.0;
      salaryCtrl.text = s.toStringAsFixed(0);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final now = DateTime.now();
            final months = <Map<String, dynamic>>[];
            for (int i = startMonthsAgo; i >= 1; i--) {
              final d = DateTime(now.year, now.month - i, 15);
              final mKey = DateFormat('yyyy-MM').format(d);
              final isLocked = Hive.box(LocalStorageService.financeSettingsBox).get('month_lock_$mKey') == true;
              months.add({
                'key': mKey,
                'label': DateFormat('MMMM yyyy').format(d),
                'isLocked': isLocked,
              });
            }

            final hasLockedMonths = months.any((m) => m['isLocked'] == true);

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.75,
              padding: EdgeInsets.only(
                top: 20,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Bulk Historical Backfill', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bulk initialize attendance and salary rates for $employeeName. Active month locks are strictly enforced.',
                      style: TextStyle(color: t.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(height: 14),

                    if (hasLockedMonths)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                                SizedBox(width: 6),
                                Text('Locked Periods Detected', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Some months in the selected window are closed and locked. Backfill is blocked.',
                              style: TextStyle(color: Colors.red, fontSize: 11),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: months.map((m) {
                                final isL = m['isLocked'] == true;
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isL ? Colors.red.withOpacity(0.12) : Colors.green.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${m['key']} ${isL ? "🔒" : "🔓"}',
                                    style: TextStyle(
                                      color: isL ? Colors.red : Colors.green,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              }).toList(),
                            )
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, color: t.accent, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'All periods in this backfill window (${months.isEmpty ? "none" : months.last['key']} to ${months.isEmpty ? "none" : months.first['key']}) are unlocked and safe.',
                                style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    buildDropdownField(
                      label: 'Backfill Window Depth (Months)',
                      value: startMonthsAgo.toString(),
                      items: const ['1', '2', '3', '4', '5', '6'],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => startMonthsAgo = int.parse(val));
                        }
                      },
                      theme: t,
                    ),

                    buildFormField(
                      controller: salaryCtrl,
                      label: 'Base Salary (PKR / Month) *',
                      icon: Icons.payments_outlined,
                      theme: t,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),

                    buildDropdownField(
                      label: 'Default Daily Attendance Status',
                      value: defaultStatus,
                      items: const ['present', 'absent', 'off'],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => defaultStatus = val);
                        }
                      },
                      theme: t,
                    ),

                    buildFormField(
                      controller: approvedByCtrl,
                      label: 'Approved By (CEO / Admin) *',
                      icon: Icons.verified_user_outlined,
                      theme: t,
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasLockedMonths ? Colors.grey : t.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: hasLockedMonths
                          ? null
                          : () async {
                              final double sVal = double.tryParse(salaryCtrl.text) ?? 0.0;
                              if (sVal <= 0) {
                                showCustomSnackBar(sheetCtx, 'Please enter a valid salary amount.', error: true);
                                return;
                              }
                              final approver = approvedByCtrl.text.trim();
                              if (approver.isEmpty) {
                                showCustomSnackBar(sheetCtx, 'Please specify who approved this backfill.', error: true);
                                return;
                              }

                              try {
                                showCustomSnackBar(sheetCtx, 'Starting backfill process...');
                                
                                for (final monthInfo in months) {
                                  final mKey = monthInfo['key'] as String;
                                  final parts = mKey.split('-');
                                  final year = int.parse(parts[0]);
                                  final month = int.parse(parts[1]);

                                  final effective = DateTime(year, month, 1);
                                  await FinanceLocalStorage.saveSalaryHistory(
                                    branchId: widget.branchId,
                                    employeeId: employeeId,
                                    amount: sVal,
                                    effectiveDate: effective,
                                    reason: 'Bulk Historical Backfill Initialization',
                                    approvedBy: approver,
                                    performedBy: curUser,
                                  );

                                  final days = FinanceLocalStorage.getDaysInMonth(mKey);
                                  for (int d = 1; d <= days; d++) {
                                    final dateStr = '$mKey-${d.toString().padLeft(2, '0')}';
                                    final date = DateTime(year, month, d);
                                    final status = date.weekday == DateTime.sunday ? 'off' : defaultStatus;

                                    await FinanceLocalStorage.saveAttendanceRecord(
                                      branchId: widget.branchId,
                                      data: {
                                        'employeeId': employeeId,
                                        'date': dateStr,
                                        'status': status,
                                        'leaveType': null,
                                        'arrivalTime': null,
                                        'departureTime': null,
                                        'note': 'Backfill Default',
                                      },
                                      performedBy: curUser,
                                    );
                                  }
                                }

                                Navigator.pop(sheetCtx);
                                showCustomSnackBar(context, 'Historical backfill completed successfully!');
                              } catch (e) {
                                showCustomSnackBar(sheetCtx, 'Error during backfill: $e', error: true);
                              }
                            },
                      child: const Text('Execute Historical Backfill', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

void showCustomBranchDialog({
  required BuildContext context,
  required RoleThemeData theme,
  required void Function(String id, String name) onAdded,
}) {
  final idController = TextEditingController();
  final nameController = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: theme.bgCard,
        title: Text('Add Custom Branch', style: TextStyle(color: theme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              autofocus: true,
              style: TextStyle(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter Branch ID (e.g. lahore)',
                hintStyle: TextStyle(color: theme.textTertiary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.bgRule)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.accent)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              style: TextStyle(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter Branch Name (e.g. Lahore)',
                hintStyle: TextStyle(color: theme.textTertiary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.bgRule)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.accent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.accent),
            onPressed: () async {
              final id = idController.text.trim().toLowerCase();
              final name = nameController.text.trim();
              if (id.isNotEmpty && name.isNotEmpty) {
                await FinanceLocalStorage.addCustomBranch(id, name);
                Navigator.pop(ctx);
                onAdded(id, name);
              }
            },
            child: const Text('Add Branch', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}