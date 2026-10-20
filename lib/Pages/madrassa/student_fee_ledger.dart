import 'package:flutter/material.dart';
import 'package:gmwf/design/tokens/soft_palette.dart';
import 'package:gmwf/design/tokens/comfort_colors.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/local_storage_service.dart';
import '../../realtime/realtime_manager.dart';
import 'utils/madrassa_local_storage.dart';

class StudentFeeLedgerScreen extends StatefulWidget {
  final String branchId;
  final String studentId;
  final String? studentName;
  final String? fatherName;
  final String? rollNumber;
  final double? monthlyFee;

  const StudentFeeLedgerScreen({
    Key? key,
    required this.branchId,
    required this.studentId,
    this.studentName,
    this.fatherName,
    this.rollNumber,
    this.monthlyFee,
  }) : super(key: key);

  @override
  State<StudentFeeLedgerScreen> createState() => _StudentFeeLedgerScreenState();
}

class _StudentFeeLedgerScreenState extends State<StudentFeeLedgerScreen> {
  int _selectedYear = DateTime.now().year;
  bool _isLoading = true;
  List<Map<String, dynamic>> _feeRecords = [];
  Map<String, dynamic>? _studentData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await LocalStorageService.ensureBoxOpen(LocalStorageService.madrassaFeesBox);
    await LocalStorageService.ensureBoxOpen(LocalStorageService.madrassaStudentsBox);

    final studentsBox = Hive.box(LocalStorageService.madrassaStudentsBox);
    final sKey = '${widget.branchId.toLowerCase().trim()}__std__${widget.studentId}';
    final rawStudent = studentsBox.get(sKey);
    if (rawStudent is Map) {
      _studentData = Map<String, dynamic>.from(rawStudent);
    }

    final feesBox = Hive.box(LocalStorageService.madrassaFeesBox);
    final prefix = '${widget.branchId.toLowerCase().trim()}__fee__';
    final List<Map<String, dynamic>> records = [];

    for (final key in feesBox.keys) {
      final keyStr = key.toString();
      if (keyStr.startsWith(prefix) && keyStr.endsWith('__${widget.studentId}')) {
        final raw = feesBox.get(key);
        if (raw is Map) {
          records.add(Map<String, dynamic>.from(raw));
        }
      }
    }

    // Sort descending by year and month
    records.sort((a, b) {
      final yA = (a['year'] ?? 0) as int;
      final yB = (b['year'] ?? 0) as int;
      if (yA != yB) return yB.compareTo(yA);
      final mA = (a['month'] ?? 0) as int;
      final mB = (b['month'] ?? 0) as int;
      return mB.compareTo(mA);
    });

    if (mounted) {
      setState(() {
        _feeRecords = records;
        _isLoading = false;
      });
    }
  }

  double get _totalPaid => _feeRecords.fold(0.0, (sum, r) => sum + ((r['amountPaid'] ?? 0) as num).toDouble());
  double get _totalDiscount => _feeRecords.fold(0.0, (sum, r) => sum + ((r['discount'] ?? 0) as num).toDouble());
  double get _totalDue => _feeRecords.fold(0.0, (sum, r) => sum + ((r['balanceDue'] ?? 0) as num).toDouble());

  String _getMonthName(int month) {
    if (month < 1 || month > 12) return 'Month $month';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  Future<void> _recordPaymentDialog() async {
    final double initialFee = (widget.monthlyFee ?? _studentData?['monthlyFee'] ?? 0.0).toDouble();
    final totalFeeCtrl = TextEditingController(text: initialFee > 0 ? initialFee.toStringAsFixed(0) : '0');
    final amountCtrl = TextEditingController(text: initialFee > 0 ? initialFee.toStringAsFixed(0) : '0');
    final discountCtrl = TextEditingController(text: '0');
    final noteCtrl = TextEditingController();
    int selectedMonth = DateTime.now().month;
    int selectedYear = _selectedYear;
    String paymentMethod = 'Cash';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final total = double.tryParse(totalFeeCtrl.text.trim()) ?? 0.0;
          final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
          final discount = double.tryParse(discountCtrl.text.trim()) ?? 0.0;
          final remaining = (total - amount - discount).clamp(0.0, double.infinity);
          final isCleared = remaining <= 0.0;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.payment, color: ctx.adapt(SoftPalette.blue500)),
                const SizedBox(width: 8),
                const Text('Collect / Deduct Fee Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedMonth,
                          decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder()),
                          items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_getMonthName(i + 1)))),
                          onChanged: (v) {
                            if (v != null) setDlgState(() => selectedMonth = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: selectedYear,
                          decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                          items: [selectedYear - 1, selectedYear, selectedYear + 1]
                              .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDlgState(() => selectedYear = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: totalFeeCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDlgState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Total Monthly Fee (PKR)',
                      prefixText: 'Rs. ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDlgState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Amount Paid by Parent (Deducted) (PKR)',
                      prefixText: 'Rs. ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: discountCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDlgState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Discount / Concession (PKR)',
                      prefixText: 'Rs. ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Live deduction breakdown card showing what remains
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCleared
                          ? SoftPalette.green550.withValues(alpha: 0.1)
                          : SoftPalette.red500.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCleared ? SoftPalette.green550 : SoftPalette.red500,
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Monthly Fee:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            Text('Rs. ${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Amount Paid (Deducted):', style: TextStyle(fontSize: 12, color: SoftPalette.green550, fontWeight: FontWeight.w600)),
                            Text('- Rs. ${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: SoftPalette.green550)),
                          ],
                        ),
                        if (discount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Concession / Discount:', style: TextStyle(fontSize: 12, color: SoftPalette.orange400, fontWeight: FontWeight.w600)),
                              Text('- Rs. ${discount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: SoftPalette.orange400)),
                            ],
                          ),
                        ],
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isCleared ? 'Status: Fully Cleared 🎉' : 'Remaining Balance Due:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isCleared ? SoftPalette.green550 : SoftPalette.red500,
                              ),
                            ),
                            Text(
                              'Rs. ${remaining.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isCleared ? SoftPalette.green550 : SoftPalette.red500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                      DropdownMenuItem(value: 'JazzCash/EasyPaisa', child: Text('JazzCash / EasyPaisa')),
                      DropdownMenuItem(value: 'Online', child: Text('Online / Card')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlgState(() => paymentMethod = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Remarks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SoftPalette.blue500,
                  foregroundColor: SoftPalette.gray50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final feeKey = '${widget.branchId.toLowerCase().trim()}__fee__${selectedYear}_${selectedMonth}__${widget.studentId}';
                  final receiptId = 'REC-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';

                  final feeEntry = {
                    'key': feeKey,
                    'branchId': widget.branchId.toLowerCase().trim(),
                    'studentId': widget.studentId,
                    'studentName': widget.studentName ?? _studentData?['name'] ?? 'Student',
                    'fatherName': widget.fatherName ?? _studentData?['fatherName'] ?? '',
                    'year': selectedYear,
                    'month': selectedMonth,
                    'amountPaid': amount,
                    'discount': discount,
                    'totalFee': total,
                    'amountDue': total,
                    'balanceDue': remaining,
                    'paymentMethod': paymentMethod,
                    'receiptId': receiptId,
                    'notes': noteCtrl.text.trim(),
                    'paidAt': DateTime.now().toIso8601String(),
                    'status': isCleared ? 'Paid' : (amount > 0 || discount > 0 ? 'Partial' : 'Unpaid'),
                  };

                  final box = await LocalStorageService.ensureBoxOpen(LocalStorageService.madrassaFeesBox);
                  await box.put(feeKey, feeEntry);

                  // Unified sync and audit log recording
                  await MadrassaLocalStorage.saveFeePaymentLocalAndSync(
                    branchId: widget.branchId,
                    studentId: widget.studentId,
                    studentName: widget.studentName ?? _studentData?['name'] ?? 'Student',
                    rollNumber: widget.rollNumber ?? _studentData?['rollNumber'] ?? '',
                    year: selectedYear,
                    month: selectedMonth,
                    amountDue: total,
                    amountPaid: amount,
                    discount: discount,
                    balanceDue: remaining,
                    paymentMethod: paymentMethod,
                    receiptId: receiptId,
                    status: isCleared ? 'paid' : (amount > 0 || discount > 0 ? 'partial' : 'unpaid'),
                    markedBy: 'HQ Manager',
                    markedByRole: 'hq manager',
                    note: noteCtrl.text.trim(),
                  );

                  // Broadcast on LAN
                  RealtimeManager().sendMessage({
                    'event_type': 'madrassa_fee_paid',
                    'branchId': widget.branchId,
                    'data': feeEntry,
                  });

                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Save & Print Receipt'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      await _loadData();
      if (_feeRecords.isNotEmpty) {
        await _printReceipt(_feeRecords.first);
      }
    }
  }

  Future<void> _printReceipt(Map<String, dynamic> record) async {
    final doc = pw.Document();
    final stdName = widget.studentName ?? _studentData?['name'] ?? 'Student';
    final fName = widget.fatherName ?? _studentData?['fatherName'] ?? '';
    final rId = record['receiptId'] ?? 'N/A';
    final mName = _getMonthName(record['month'] ?? 1);
    final year = record['year'] ?? DateTime.now().year;
    final amt = record['amountPaid'] ?? 0;
    final disc = record['discount'] ?? 0;
    final due = record['balanceDue'] ?? 0;
    final totalFee = record['totalFee'] ?? record['amountDue'] ?? 0;
    final method = record['paymentMethod'] ?? 'Cash';
    final date = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.tryParse(record['paidAt'] ?? '') ?? DateTime.now());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('GHULAM MUHAMMAD WELFARE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text('MADRASSA & EDUCATION SYSTEM', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text('Fee Payment Receipt', style: const pw.TextStyle(fontSize: 10)),
              pw.Divider(thickness: 0.5),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Receipt #: $rId', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Date: $date', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Student: $stdName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    if (fName.isNotEmpty) pw.Text('Father: $fName', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Period: $mName $year', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Method: $method', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              pw.Divider(thickness: 0.5),
              if (totalFee > 0)
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Total Fee:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Rs. $totalFee', style: const pw.TextStyle(fontSize: 8)),
                ]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Amount Paid (Deducted):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('Rs. $amt', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ]),
              if (disc > 0)
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Discount / Concession:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Rs. $disc', style: const pw.TextStyle(fontSize: 8)),
                ]),
              if (due > 0)
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Remaining Balance Due:', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red)),
                  pw.Text('Rs. $due', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red)),
                ])
              else
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Status:', style: const pw.TextStyle(fontSize: 8, color: PdfColors.green)),
                  pw.Text('FULLY CLEARED', style: const pw.TextStyle(fontSize: 8, color: PdfColors.green)),
                ]),
              pw.Divider(thickness: 0.5),
              pw.Text('Thank you for your payment.', style: const pw.TextStyle(fontSize: 7)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Receipt_$rId.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stdName = widget.studentName ?? _studentData?['name'] ?? 'Student';
    final fName = widget.fatherName ?? _studentData?['fatherName'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$stdName - Fee Ledger', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (fName.isNotEmpty)
              Text('S/O $fName | ID: ${widget.studentId}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Ledger',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.add_card),
            tooltip: 'Collect Fee',
            onPressed: _recordPaymentDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary cards
                Container(
                  padding: const EdgeInsets.all(16),
                  color: isDark ? SoftPalette.slate900 : SoftPalette.slate100,
                  child: Row(
                    children: [
                      _buildSummaryCard('Total Paid', 'Rs. ${_totalPaid.toStringAsFixed(0)}', context.adapt(SoftPalette.green400), Icons.check_circle_outline),
                      const SizedBox(width: 8),
                      _buildSummaryCard('Total Concession', 'Rs. ${_totalDiscount.toStringAsFixed(0)}', context.adapt(SoftPalette.amber300), Icons.discount_outlined),
                      const SizedBox(width: 8),
                      _buildSummaryCard('Outstanding Due', 'Rs. ${_totalDue.toStringAsFixed(0)}', context.adapt(SoftPalette.red400), Icons.pending_actions),
                    ],
                  ),
                ),
                // Filter bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('Fee History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Record Payment'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SoftPalette.blue500,
                          foregroundColor: SoftPalette.gray50,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _recordPaymentDialog,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Ledger List
                Expanded(
                  child: _feeRecords.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 64, color: context.adapt(SoftPalette.gray300)),
                              const SizedBox(height: 12),
                              Text('No fee records found for this student', style: TextStyle(fontSize: 16, color: context.adapt(SoftPalette.gray500))),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _recordPaymentDialog,
                                child: const Text('Collect First Payment'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _feeRecords.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final r = _feeRecords[idx];
                            final monthName = _getMonthName(r['month'] ?? 1);
                            final year = r['year'] ?? DateTime.now().year;
                            final amount = r['amountPaid'] ?? 0;
                            final discount = r['discount'] ?? 0;
                            final due = r['balanceDue'] ?? 0;
                            final status = r['status'] ?? 'Paid';
                            final receiptId = r['receiptId'] ?? 'N/A';
                            final paidDate = r['paidAt'] != null
                                ? DateFormat('dd MMM yyyy').format(DateTime.tryParse(r['paidAt']) ?? DateTime.now())
                                : '';

                            final isPaid = status.toString().toLowerCase() == 'paid';
                            final isPartial = status.toString().toLowerCase() == 'partial';

                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isPaid
                                      ? SoftPalette.green200
                                      : (isPartial ? SoftPalette.yellow150 : SoftPalette.pink100m),
                                  child: Icon(
                                    isPaid
                                        ? Icons.check
                                        : (isPartial ? Icons.pie_chart_outline_rounded : Icons.pending_actions_rounded),
                                    color: isPaid
                                        ? SoftPalette.green550
                                        : (isPartial ? SoftPalette.orange350 : SoftPalette.red500),
                                  ),
                                ),
                                title: Text('$monthName $year', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Receipt: $receiptId • Date: $paidDate\nMethod: ${r['paymentMethod'] ?? 'Cash'} ${discount > 0 ? '• Concession: Rs. $discount' : ''}'),
                                isThreeLine: true,
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Paid: Rs. $amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: ctx.adapt(SoftPalette.green400))),
                                    if (due > 0)
                                      Text('Remains: Rs. $due', style: TextStyle(fontSize: 11, color: ctx.adapt(SoftPalette.red400), fontWeight: FontWeight.bold))
                                    else
                                      Text('Cleared', style: TextStyle(fontSize: 11, color: ctx.adapt(SoftPalette.green550), fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                onTap: () => _printReceipt(r),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
