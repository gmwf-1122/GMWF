// lib/pages/office/holiday_manager_dialog.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/finance_local_storage.dart';
import '../../services/local_storage_service.dart';
import 'shared_widgets.dart';

class HolidayManagerDialog extends StatefulWidget {
  final String branchId;
  final List<Map<String, dynamic>> branches;
  final String userRole;

  const HolidayManagerDialog({
    super.key,
    required this.branchId,
    required this.branches,
    required this.userRole,
  });

  @override
  State<HolidayManagerDialog> createState() => _HolidayManagerDialogState();
}

class _HolidayManagerDialogState extends State<HolidayManagerDialog> {
  bool _showAddForm = false;

  // Form controllers & states
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController(
    text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
  );
  final TextEditingController _endDateCtrl = TextEditingController();

  bool _allBranchesScope = true;
  final Map<String, bool> _selectedBranches = {};

  bool _allDeptsScope = true;
  final List<String> _departmentsList = ['Dispensary', 'Kitchen', 'Office', 'Madrassa', 'General'];
  final Map<String, bool> _selectedDepts = {};

  final List<Map<String, String>> _exceptions = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Default select active branch in case of specific branch scope
    for (final b in widget.branches) {
      final bId = b['id']?.toString() ?? '';
      if (bId.isNotEmpty) {
        _selectedBranches[bId] = (bId == widget.branchId);
      }
    }
    // Default select all departments
    for (final d in _departmentsList) {
      _selectedDepts[d] = true;
    }
    // Add custom departments if any
    final customDepts = FinanceLocalStorage.getCustomDepartments();
    for (final d in customDepts) {
      if (!_departmentsList.contains(d)) {
        _departmentsList.add(d);
        _selectedDepts[d] = true;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  bool get _isExecutive {
    final role = widget.userRole.toLowerCase();
    return ['admin', 'ceo', 'chairman', 'hq manager', 'global admin'].contains(role);
  }

  String _getBranchName(String id) {
    if (id == 'all') return 'All Branches';
    for (final b in widget.branches) {
      if (b['id'] == id) {
        return b['name']?.toString() ?? id;
      }
    }
    return id;
  }

  void _resetForm() {
    _nameCtrl.clear();
    _dateCtrl.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _endDateCtrl.clear();
    _allBranchesScope = true;
    for (final key in _selectedBranches.keys) {
      _selectedBranches[key] = (key == widget.branchId);
    }
    _allDeptsScope = true;
    for (final key in _selectedDepts.keys) {
      _selectedDepts[key] = true;
    }
    _exceptions.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 600;

    return Container(
      constraints: BoxConstraints(
        maxHeight: size.height * 0.9,
        maxWidth: isNarrow ? double.infinity : 650,
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(t),
          const SizedBox(height: 10),
          Expanded(
            child: _showAddForm ? _buildAddHolidayForm(t, isNarrow) : _buildHolidaysList(t),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(RoleThemeData t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.festival_outlined, color: t.accent, size: 22),
            const SizedBox(width: 8),
            Text(
              _showAddForm ? 'Add Holiday' : 'Holiday Calendar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary),
            ),
          ],
        ),
        Row(
          children: [
            if (!_showAddForm)
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: t.accent,
                onPressed: () {
                  setState(() {
                    _resetForm();
                    _showAddForm = true;
                  });
                },
              ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildHolidaysList(RoleThemeData t) {
    return ValueListenableBuilder(
      valueListenable: Hive.box(LocalStorageService.financeHolidaysBox).listenable(),
      builder: (ctx, Box box, _) {
        final list = FinanceLocalStorage.getHolidays(widget.branchId);

        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy_outlined, size: 54, color: t.textTertiary),
                const SizedBox(height: 14),
                Text('No holidays scheduled', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('All departments are operating normally.', style: TextStyle(color: t.textTertiary, fontSize: 11)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (c, i) {
            final hol = list[i];
            final id = hol['id']?.toString() ?? '';
            final name = hol['name']?.toString() ?? 'Holiday';
            final dateRaw = hol['date'];
            DateTime? parsedDate;
            if (dateRaw is String) parsedDate = DateTime.tryParse(dateRaw);
            final dateStr = parsedDate != null ? DateFormat('EEEE, dd MMMM yyyy').format(parsedDate) : (dateRaw?.toString() ?? '');

            final branches = hol['branches'] is List ? List<String>.from(hol['branches'] as List) : <String>[];
            final departments = hol['departments'] is List ? List<String>.from(hol['departments'] as List) : <String>[];
            final exceptions = hol['exceptions'] is List ? List<dynamic>.from(hol['exceptions'] as List) : [];

            final isGlobal = branches.contains('all');
            final appliesToAllDepts = departments.contains('all') || departments.isEmpty;

            return Card(
              color: t.bgCard,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: t.bgRule),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(dateStr, style: TextStyle(color: t.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            if (hol['syncStatus'] == 'pending')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: const Text('Syncing...', style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () => _confirmDelete(id, branches),
                            ),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 6),
                    Divider(color: t.bgRule, height: 1),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildBadge(isGlobal ? 'All Branches' : 'Selected Branches', Colors.blue, t),
                        _buildBadge(appliesToAllDepts ? 'All Departments' : 'Dept: ${departments.join(", ")}', Colors.teal, t),
                      ],
                    ),
                    if (exceptions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('EXCEPTIONS (OPEN/WORKING):', style: TextStyle(color: t.accent, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Column(
                        children: exceptions.map((ex) {
                          if (ex is! Map) return const SizedBox();
                          final exBranch = ex['branchId']?.toString() ?? 'all';
                          final exDept = ex['department']?.toString() ?? 'all';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2.0),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Colors.orange, size: 10),
                                const SizedBox(width: 6),
                                Text(
                                  '${exDept.toUpperCase()} department on ${_getBranchName(exBranch)}',
                                  style: TextStyle(color: t.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      )
                    ]
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBadge(String text, Color color, RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildAddHolidayForm(RoleThemeData t, bool isNarrow) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildDatePickerField(
            context: context,
            controller: _dateCtrl,
            label: 'Holiday Start Date *',
            icon: Icons.calendar_today,
            theme: t,
          ),
          const SizedBox(height: 10),
          buildDatePickerField(
            context: context,
            controller: _endDateCtrl,
            label: 'Holiday End Date (Optional)',
            icon: Icons.calendar_today,
            theme: t,
          ),
          const SizedBox(height: 10),
          buildFormField(
            controller: _nameCtrl,
            label: 'Holiday Name / Occasion *',
            icon: Icons.edit_note,
            theme: t,
          ),
          const SizedBox(height: 10),
          
          // ── Branch Selection Scope ──
          if (_isExecutive) ...[
            Text('BRANCH APPLICABILITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: t.accent)),
            Row(
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: _allBranchesScope,
                  activeColor: t.accent,
                  onChanged: (val) => setState(() => _allBranchesScope = true),
                ),
                Text('All Branches', style: TextStyle(color: t.textPrimary, fontSize: 12)),
                const SizedBox(width: 20),
                Radio<bool>(
                  value: false,
                  groupValue: _allBranchesScope,
                  activeColor: t.accent,
                  onChanged: (val) => setState(() => _allBranchesScope = false),
                ),
                Text('Specific Branches', style: TextStyle(color: t.textPrimary, fontSize: 12)),
              ],
            ),
            if (!_allBranchesScope)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
                child: Wrap(
                  spacing: 12,
                  children: widget.branches.map((b) {
                    final bId = b['id']?.toString() ?? '';
                    final bName = b['name']?.toString() ?? bId;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _selectedBranches[bId] ?? false,
                          activeColor: t.accent,
                          onChanged: (val) => setState(() => _selectedBranches[bId] = val ?? false),
                        ),
                        Text('$bName ($bId)', style: TextStyle(color: t.textPrimary, fontSize: 11)),
                      ],
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 14),
          ],

          // ── Department Selection Scope ──
          Text('DEPARTMENT APPLICABILITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: t.accent)),
          Row(
            children: [
              Radio<bool>(
                value: true,
                groupValue: _allDeptsScope,
                activeColor: t.accent,
                onChanged: (val) => setState(() => _allDeptsScope = true),
              ),
              Text('All Departments', style: TextStyle(color: t.textPrimary, fontSize: 12)),
              const SizedBox(width: 20),
              Radio<bool>(
                value: false,
                groupValue: _allDeptsScope,
                activeColor: t.accent,
                onChanged: (val) => setState(() => _allDeptsScope = false),
              ),
              Text('Specific Departments', style: TextStyle(color: t.textPrimary, fontSize: 12)),
            ],
          ),
          if (!_allDeptsScope)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: t.bgCardAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: t.bgRule)),
              child: Wrap(
                spacing: 12,
                children: _departmentsList.map((dept) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _selectedDepts[dept] ?? false,
                        activeColor: t.accent,
                        onChanged: (val) => setState(() => _selectedDepts[dept] = val ?? false),
                      ),
                      Text(dept, style: TextStyle(color: t.textPrimary, fontSize: 11)),
                    ],
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 14),

          // ── Exceptions Builder ──
          _buildExceptionsBuilder(t),
          const SizedBox(height: 20),

          // Save / Cancel Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: t.bgRule),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() => _showAddForm = false),
                  child: Text('Cancel', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSaving ? null : () => _saveHoliday(t),
                  child: Text(_isSaving ? 'Saving...' : 'Add Holiday', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExceptionsBuilder(RoleThemeData t) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.bgCardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.bgRule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('EXCEPTIONS (DEPARTMENTS REMAINING OPEN)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: t.accent)),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 12),
                label: const Text('Add Exclusion', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                onPressed: () {
                  setState(() {
                    _exceptions.add({'branchId': 'all', 'department': 'Office'});
                  });
                },
              ),
            ],
          ),
          if (_exceptions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Text(
                'No exceptions defined. All targeted employees get this holiday off.',
                style: TextStyle(color: t.textTertiary, fontSize: 11, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          ..._exceptions.asMap().entries.map((entry) {
            final idx = entry.key;
            final ex = entry.value;

            final currentBranch = ex['branchId'] ?? 'all';
            final currentDept = ex['department'] ?? 'Office';

            // Branch selector options: All Branches + individual branches
            final branchOptions = <String>['all'];
            for (final b in widget.branches) {
              final bId = b['id']?.toString() ?? '';
              if (bId.isNotEmpty) branchOptions.add(bId);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: t.bgCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentBranch,
                          dropdownColor: t.bgCard,
                          style: TextStyle(color: t.textPrimary, fontSize: 11),
                          isExpanded: true,
                          items: branchOptions.map((opt) {
                            return DropdownMenuItem<String>(
                              value: opt,
                              child: Text(opt == 'all' ? 'All Branches' : _getBranchName(opt)),
                            );
                          }).toList(),
                          onChanged: !_isExecutive
                              ? null // locked to current branch exceptions
                              : (val) {
                                  if (val != null) {
                                    setState(() {
                                      _exceptions[idx]['branchId'] = val;
                                    });
                                  }
                                },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: t.bgCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.bgRule),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _departmentsList.contains(currentDept) ? currentDept : _departmentsList.first,
                          dropdownColor: t.bgCard,
                          style: TextStyle(color: t.textPrimary, fontSize: 11),
                          isExpanded: true,
                          items: _departmentsList.map((opt) {
                            return DropdownMenuItem<String>(
                              value: opt,
                              child: Text(opt),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _exceptions[idx]['department'] = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 18),
                    onPressed: () {
                      setState(() {
                        _exceptions.removeAt(idx);
                      });
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _saveHoliday(RoleThemeData t) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showCustomSnackBar(context, 'Please specify the holiday name.', error: true);
      return;
    }

    final dateStr = _dateCtrl.text.trim();
    final date = DateTime.tryParse(dateStr);
    if (date == null) {
      showCustomSnackBar(context, 'Please select a valid start date.', error: true);
      return;
    }

    DateTime? endDate;
    final endDateStr = _endDateCtrl.text.trim();
    if (endDateStr.isNotEmpty) {
      endDate = DateTime.tryParse(endDateStr);
    }

    final List<DateTime> targetDates = [];
    if (endDate != null && endDate.isAfter(date)) {
      var curr = DateTime(date.year, date.month, date.day);
      final limit = DateTime(endDate.year, endDate.month, endDate.day);
      while (curr.isBefore(limit) || curr.isAtSameMomentAs(limit)) {
        targetDates.add(curr);
        curr = curr.add(const Duration(days: 1));
      }
    } else {
      targetDates.add(date);
    }

    // Resolve branch selection
    final List<String> branches = [];
    if (!_isExecutive) {
      branches.add(widget.branchId);
    } else {
      if (_allBranchesScope) {
        branches.add('all');
      } else {
        final selected = _selectedBranches.entries
            .where((entry) => entry.value == true)
            .map((entry) => entry.key)
            .toList();
        if (selected.isEmpty) {
          showCustomSnackBar(context, 'Please select at least one branch.', error: true);
          return;
        }
        branches.addAll(selected);
      }
    }

    // Resolve department selection
    final List<String> departments = [];
    if (_allDeptsScope) {
      departments.add('all');
    } else {
      final selected = _selectedDepts.entries
          .where((entry) => entry.value == true)
          .map((entry) => entry.key)
          .toList();
      if (selected.isEmpty) {
        showCustomSnackBar(context, 'Please select at least one department.', error: true);
        return;
      }
      departments.addAll(selected);
    }

    setState(() => _isSaving = true);
    try {
      final curUser = LocalStorageService.getActiveUsername();

      for (final targetDate in targetDates) {
        await FinanceLocalStorage.saveHoliday(
          name: name,
          date: targetDate,
          branches: branches,
          departments: departments,
          exceptions: _exceptions,
          performedBy: curUser,
        );
      }

      if (mounted) {
        showCustomSnackBar(context, 'Holiday scheduled successfully!');
        setState(() {
          _showAddForm = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(context, 'Failed: $e', error: true);
        setState(() => _isSaving = false);
      }
    }
  }

  void _confirmDelete(String holidayId, List<String> branches) {
    final t = RoleThemeScope.dataOf(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: t.bgCard,
          title: Text('Delete Holiday', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold)),
          content: Text('Are you sure you want to cancel and delete this holiday schedule? This will restore regular work hour calculations for all employees on this date.', style: TextStyle(color: t.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final curUser = LocalStorageService.getActiveUsername();
                  await FinanceLocalStorage.deleteHoliday(
                    holidayId: holidayId,
                    branches: branches,
                    performedBy: curUser,
                  );
                  showCustomSnackBar(context, 'Holiday deleted.');
                } catch (e) {
                  showCustomSnackBar(context, 'Failed: $e', error: true);
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}
