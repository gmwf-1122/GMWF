import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/finance_local_storage.dart';

class OffboardDialog extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  final String performedBy;
  final VoidCallback? onOffboarded;

  const OffboardDialog({
    super.key,
    required this.employeeData,
    required this.performedBy,
    this.onOffboarded,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> employeeData,
    required String performedBy,
    VoidCallback? onOffboarded,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OffboardDialog(
        employeeData: employeeData,
        performedBy: performedBy,
        onOffboarded: onOffboarded,
      ),
    );
  }

  @override
  State<OffboardDialog> createState() => _OffboardDialogState();
}

class _OffboardDialogState extends State<OffboardDialog> {
  late String _selectedReason;
  late TextEditingController _detailedReasonCtrl;
  late DateTime _effectiveDate;
  late TimeOfDay _effectiveTime;
  String _shiftMilestone = 'Immediate';
  bool _isClearanceConfirmed = true;
  bool _isProcessing = false;
  late Map<String, dynamic> _lastRecordedData;

  final List<String> _reasonOptions = [
    'Resigned',
    'Terminated',
    'Contract Ended',
    'Retired',
    'Suspended',
    'Disciplinary Action',
    'Relocated',
    'Medical Reasons',
    'Other',
  ];

  final List<String> _milestoneOptions = [
    'Immediate',
    'End of Morning Shift',
    'End of Evening Shift',
    'End of Day / Month-End',
  ];

  @override
  void initState() {
    super.initState();
    _selectedReason = 'Resigned';
    _detailedReasonCtrl = TextEditingController();
    _effectiveDate = DateTime.now();
    _effectiveTime = TimeOfDay.now();

    final empId = widget.employeeData['localId']?.toString() ??
        widget.employeeData['employeeId']?.toString() ??
        widget.employeeData['id']?.toString() ??
        '';
    final cnic = widget.employeeData['cnic']?.toString();
    final userId = widget.employeeData['linkedUserId']?.toString() ??
        widget.employeeData['uid']?.toString();

    _lastRecordedData = FinanceLocalStorage.getLastRecordedDataForEmployee(
      employeeId: empId,
      cnic: cnic,
      userId: userId,
    );
  }

  @override
  void dispose() {
    _detailedReasonCtrl.dispose();
    super.dispose();
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _effectiveDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _effectiveTime,
    );
    if (picked != null) {
      setState(() => _effectiveTime = picked);
    }
  }

  Future<void> _handleConfirm() async {
    final detailed = _detailedReasonCtrl.text.trim();
    if (detailed.isEmpty && _selectedReason == 'Other') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide specific remarks for the offboarding reason.')),
      );
      return;
    }

    if (!_isClearanceConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please check the confirmation box to complete offboarding.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final empId = widget.employeeData['localId']?.toString() ??
          widget.employeeData['employeeId']?.toString() ??
          widget.employeeData['id']?.toString() ??
          '';
      final cnic = widget.employeeData['cnic']?.toString();
      final userId = widget.employeeData['linkedUserId']?.toString() ??
          widget.employeeData['uid']?.toString();

      await FinanceLocalStorage.syncBiDirectionalOffboarding(
        employeeId: empId,
        userId: userId,
        cnic: cnic,
        performedBy: widget.performedBy,
        reason: _selectedReason,
        detailedReason: detailed,
        effectiveDate: _effectiveDate,
        effectiveTime: _formatTimeOfDay(_effectiveTime),
        shiftMilestone: _shiftMilestone,
        lastRecordedData: _lastRecordedData,
      ).timeout(const Duration(seconds: 4));

      widget.onOffboarded?.call();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete offboarding: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgDialog = isDark ? const Color(0xFF1E293B) : Colors.white;
    final bgCard = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final empName = widget.employeeData['name']?.toString() ??
        widget.employeeData['fullName']?.toString() ??
        widget.employeeData['username']?.toString() ??
        'Employee';
    final empRole = widget.employeeData['role']?.toString() ??
        widget.employeeData['designation']?.toString() ??
        'Staff';
    final empId = widget.employeeData['localId']?.toString() ??
        widget.employeeData['employeeId']?.toString() ??
        widget.employeeData['id']?.toString() ??
        '';
    final empBranch = widget.employeeData['branchId']?.toString() ??
        widget.employeeData['branchName']?.toString() ??
        'Main Branch';

    final lastAtt = _lastRecordedData['lastAttendance']?.toString() ?? 'No punches recorded';
    final lastAct = _lastRecordedData['lastActivity']?.toString() ?? 'No app logins recorded';
    final salaryNum = (_lastRecordedData['currentSalary'] as num?)?.toDouble() ?? 0.0;
    final loanNum = (_lastRecordedData['loanBalance'] as num?)?.toDouble() ?? 0.0;
    final joinDateStr = _lastRecordedData['joiningDate']?.toString() ?? '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: bgDialog,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_off_rounded, color: Colors.redAccent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Employee Offboarding & Access Revocation',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Terminate active status, freeze salary & record detailed audit handover for $empName',
                          style: TextStyle(fontSize: 12, color: subtextColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: subtextColor),
                  ),
                ],
              ),
            ),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Target Employee Summary Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                            child: Text(
                              empName.isNotEmpty ? empName[0].toUpperCase() : 'E',
                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      empName,
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        empRole.toUpperCase(),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: subtextColor),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: $empId • Branch: $empBranch',
                                  style: TextStyle(fontSize: 11, color: subtextColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Section 1: Details about Last Recorded Data ──
                    Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 6),
                        Text(
                          'Last Recorded System Data & Status Audit',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          _buildAuditRow(
                            icon: Icons.fingerprint_rounded,
                            iconColor: Colors.teal,
                            label: 'Last Attendance / Punch:',
                            value: lastAtt,
                            textColor: textColor,
                            subtextColor: subtextColor,
                          ),
                          const Divider(height: 16, thickness: 0.6),
                          _buildAuditRow(
                            icon: Icons.devices_rounded,
                            iconColor: Colors.indigo,
                            label: 'Last App / System Activity:',
                            value: lastAct,
                            textColor: textColor,
                            subtextColor: subtextColor,
                          ),
                          const Divider(height: 16, thickness: 0.6),
                          Row(
                            children: [
                              Expanded(
                                child: _buildAuditRow(
                                  icon: Icons.payments_rounded,
                                  iconColor: Colors.amber,
                                  label: 'Active Base Salary:',
                                  value: 'PKR ${NumberFormat('#,##0').format(salaryNum)}',
                                  textColor: textColor,
                                  subtextColor: subtextColor,
                                ),
                              ),
                              Expanded(
                                child: _buildAuditRow(
                                  icon: Icons.account_balance_wallet_rounded,
                                  iconColor: loanNum > 0 ? Colors.redAccent : Colors.green,
                                  label: 'Advance / Loan Balance:',
                                  value: 'PKR ${NumberFormat('#,##0').format(loanNum)} ${loanNum > 0 ? '(Outstanding)' : '(Cleared)'}',
                                  textColor: textColor,
                                  subtextColor: subtextColor,
                                ),
                              ),
                            ],
                          ),
                          if (joinDateStr.isNotEmpty) ...[
                            const Divider(height: 16, thickness: 0.6),
                            _buildAuditRow(
                              icon: Icons.event_available_rounded,
                              iconColor: Colors.purple,
                              label: 'Joining / Service Record:',
                              value: 'Joined: $joinDateStr',
                              textColor: textColor,
                              subtextColor: subtextColor,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Section 2: Offboarding Reasons ──
                    Row(
                      children: [
                        const Icon(Icons.assignment_late_rounded, size: 16, color: Colors.orangeAccent),
                        const SizedBox(width: 6),
                        Text(
                          'Offboarding Reasons & Justification',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Reason Category Dropdown
                    Text('Primary Reason Category *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subtextColor)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: _selectedReason,
                      dropdownColor: bgDialog,
                      style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: bgCard,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      ),
                      items: _reasonOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedReason = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Detailed Notes / Remarks
                    Text('Detailed Circumstances / Exit Remarks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subtextColor)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _detailedReasonCtrl,
                      style: TextStyle(color: textColor, fontSize: 13),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter reason, resignation letter details, disciplinary grounds or handover notes...',
                        hintStyle: TextStyle(color: subtextColor, fontSize: 12),
                        filled: true,
                        fillColor: bgCard,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Section 3: Exact Timing From When It Will Be Offboarded ──
                    Row(
                      children: [
                        const Icon(Icons.access_time_filled_rounded, size: 16, color: Colors.teal),
                        const SizedBox(width: 6),
                        Text(
                          'Exact Effective Timing & Shift Cutoff',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        // Date Picker
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Effective Date *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subtextColor)),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: _pickDate,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: bgCard,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        DateFormat('dd MMM yyyy').format(_effectiveDate),
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                      ),
                                      const Icon(Icons.calendar_today_rounded, size: 16, color: Colors.teal),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Time Picker
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Exact Cutoff Time *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subtextColor)),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: _pickTime,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: bgCard,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatTimeOfDay(_effectiveTime),
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                      ),
                                      const Icon(Icons.schedule_rounded, size: 16, color: Colors.teal),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Shift Milestone Chips
                    Text('Timing Milestone / Shift Window', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subtextColor)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _milestoneOptions.map((m) {
                        final isSel = _shiftMilestone == m;
                        return ChoiceChip(
                          label: Text(m),
                          selected: isSel,
                          selectedColor: Colors.teal.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            color: isSel ? (isDark ? Colors.white : Colors.teal) : subtextColor,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: isSel ? Colors.teal : borderColor),
                          backgroundColor: bgCard,
                          onSelected: (_) => setState(() => _shiftMilestone = m),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // Clearance Confirmation Checkbox
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _isClearanceConfirmed,
                            activeColor: Colors.redAccent,
                            onChanged: (val) => setState(() => _isClearanceConfirmed = val ?? false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'I verify that the last recorded data has been audited, departmental assets/credentials are handed over, and active salary calculations should be stopped effective immediately.',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : const Color(0xFF1E293B)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isProcessing ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _handleConfirm,
                    icon: _isProcessing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.person_off_rounded, size: 18),
                    label: Text(_isProcessing ? 'Processing Offboarding...' : 'Confirm Offboarding & Terminate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color textColor,
    required Color subtextColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subtextColor),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
          ),
        ),
      ],
    );
  }
}
