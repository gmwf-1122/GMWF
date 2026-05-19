import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/madrassa_config.dart';
import '../models/madrassa_fee_logic.dart';
import '../widgets/madrassa_common_widgets.dart';
import '../utils/madrassa_report_helper.dart';

class MonthlyReportView extends StatelessWidget {
  final String branchId;
  const MonthlyReportView({super.key, required this.branchId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_config')
          .doc('current')
          .snapshots(),
      builder: (context, configSnap) {
        if (!configSnap.hasData) return const Center(child: CircularProgressIndicator());
        final config = MadrassaConfig.fromFirestore(configSnap.data!);
        final monthKey = DateFormat('yyyy-MM').format(DateTime(config.year, config.month));

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .collection('madrassa_students')
              .snapshots(),
          builder: (context, studentSnap) {
            if (!studentSnap.hasData) return const Center(child: CircularProgressIndicator());
            final students = studentSnap.data!.docs;

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(branchId)
                  .collection('madrassa_daily_logs')
                  .where(FieldPath.documentId, isGreaterThanOrEqualTo: '$monthKey-01')
                  .where(FieldPath.documentId, isLessThanOrEqualTo: '$monthKey-31')
                  .snapshots(),
              builder: (context, logSnap) {
                if (!logSnap.hasData) return const Center(child: CircularProgressIndicator());
                final monthLogs = logSnap.data!.docs;
                final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);

                return Scaffold(
                  backgroundColor: const Color(0xFFF8F9FD),
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, config, students, monthLogs),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                                        border: Border.all(color: const Color(0xFFE0E2E7)),
                                      ),
                                      child: DataTable(
                                        horizontalMargin: 12,
                                        columnSpacing: 12,
                                        headingRowColor: WidgetStateProperty.all(const Color(0xFFE0F2F1)), // Light Teal
                                        dataRowHeight: 48,
                                        headingRowHeight: 44,
                                        columns: [
                                          const DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                          const DataColumn(label: Text('Student', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                          const DataColumn(label: Text('Roll', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                          const DataColumn(label: Text('Days', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                          const DataColumn(label: Text('P', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13))),
                                          const DataColumn(label: Text('L', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFED6C02), fontSize: 13))),
                                          const DataColumn(label: Text('A', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), fontSize: 13))),
                                          const DataColumn(label: Text('Att.', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13))),
                                          const DataColumn(label: Text('U.', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF008080), fontSize: 13))),
                                          const DataColumn(label: Text('U.Rs', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13))),
                                          const DataColumn(label: Text('Msg', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFED6C02), fontSize: 13))),
                                          const DataColumn(label: Text('PTM', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), fontSize: 13))),
                                          const DataColumn(label: Text('Tot.', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32), fontSize: 13))),
                                          const DataColumn(label: Text('Due', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFD32F2F), fontSize: 13))),
                                          const DataColumn(label: Text('Card', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF008080), fontSize: 13))),
                                        ],
                                        rows: List.generate(students.length, (i) {
                                          final s = students[i];
                                          final fee = MadrassaFeeLogic.calculateStudentFee(
                                            studentId: s.id,
                                            studentData: s.data() as Map<String, dynamic>,
                                            logs: monthLogs,
                                            config: config,
                                            totalWorkingDays: workingDays,
                                          );
                                          return _buildDataRow(context, i + 1, s, fee, config, monthLogs);
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, MadrassaConfig config, List<QueryDocumentSnapshot> students, List<QueryDocumentSnapshot> logs) {
    final monthName = DateFormat('MMMM yyyy').format(DateTime(config.year, config.month));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.description_outlined, color: Color(0xFF008080)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gulzar Madina Madrassa', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Color(0xFF008080), letterSpacing: -0.5)),
                  Text('$monthName • ${MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month)} working days • ${students.length} students',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF454749), fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ExportButton(
                  onExcel: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing Excel report...')));
                    MadrassaReportHelper.exportMonthlyExcel(config: config, students: students, logs: logs);
                  },
                  onPdf: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing PDF report...')));
                    MadrassaReportHelper.exportMonthlyPdf(config: config, students: students, logs: logs);
                  },
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.folder_open, size: 12, color: Colors.teal),
                    SizedBox(width: 4),
                    Text('Saved in Downloads folder', style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildDataRow(BuildContext context, int index, QueryDocumentSnapshot s, Map<String, dynamic> fee, MadrassaConfig config, List<QueryDocumentSnapshot> logs) {
    final data = s.data() as Map<String, dynamic>;
    return DataRow(cells: [
      DataCell(Text('$index', style: const TextStyle(fontSize: 12))),
      DataCell(Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text(data['rollNumber'] ?? '?', style: const TextStyle(fontSize: 12))),
      DataCell(Text('${fee['activeWorkingDays']}', style: const TextStyle(fontSize: 12))),
      DataCell(Text('${fee['present']}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text('${fee['leave']}', style: const TextStyle(color: Color(0xFFED6C02), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text('${fee['absent']}', style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text('${(fee['attSavings'] as num).toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text('${fee['uniform']}', style: const TextStyle(color: Color(0xFF008080), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text('${(fee['uniSavings'] as num).toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text('${fee['message']}/${fee['activeWorkingDays']}', style: const TextStyle(color: Color(0xFFED6C02), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(_tag(fee['ptm'] ? 'J' : 'M', fee['ptm'] ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE), fee['ptm'] ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F))),
      DataCell(Text('${(fee['totalSavings'] as num).toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(Text((fee['amountDue'] as num).toStringAsFixed(0), style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold, fontSize: 12))),
      DataCell(StudentExportMenu(
        onPdf: () {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preparing report for ${data['name'] ?? 'student'}...')));
          MadrassaReportHelper.exportIndividualPdf(config: config, studentId: s.id, studentData: data, logs: logs);
        },
        onExcel: () {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preparing Excel report for ${data['name'] ?? 'student'}...')));
          MadrassaReportHelper.exportIndividualExcel(config: config, studentId: s.id, studentData: data, logs: logs);
        }, 
      )),
    ]);
  }

  Widget _tag(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
