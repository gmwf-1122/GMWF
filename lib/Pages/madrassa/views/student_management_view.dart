import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/madrassa_status_menu.dart';
import '../../../theme/role_theme_provider.dart';
import '../dialogs/enrollment_dialog.dart';

class StudentManagementView extends StatefulWidget {
  final String branchId;
  final bool isAdmin;
  const StudentManagementView({super.key, required this.branchId, required this.isAdmin});

  @override
  State<StudentManagementView> createState() => _StudentManagementViewState();
}

class _StudentManagementViewState extends State<StudentManagementView> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .collection('madrassa_students')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                
                final filteredStudents = snap.data!.docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final name = (d['name'] ?? '').toString().toLowerCase();
                  final roll = (d['rollNumber'] ?? '').toString().toLowerCase();
                  final query = _searchQuery.toLowerCase();
                  return name.contains(query) || roll.contains(query);
                }).toList()..sort((a, b) => (a['rollNumber'] ?? '').compareTo(b['rollNumber'] ?? ''));

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        width: MediaQuery.of(context).size.width - 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE0E2E7)),
                        ),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F4F9)),
                          dataRowHeight: 60,
                          columns: const [
                            DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Roll No.', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Class', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Guardian', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: List.generate(filteredStudents.length, (i) {
                            final s = filteredStudents[i];
                            final d = s.data() as Map<String, dynamic>;
                            return DataRow(cells: [
                              DataCell(Text('${i + 1}')),
                              DataCell(Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: const BoxDecoration(color: Color(0xFFF0F2F5), shape: BoxShape.circle),
                                    alignment: Alignment.center,
                                    child: Text(d['name']?[0] ?? '?', style: const TextStyle(color: Color(0xFF008080), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              )),
                              DataCell(Text(d['rollNumber'] ?? '?')),
                              DataCell(Text(d['class'] ?? 'Hifz')),
                              DataCell(Text(d['guardianName'] ?? '—')),
                              DataCell(Text(d['phone'] ?? '—')),
                              DataCell(StatusActionMenu(student: s, branchId: widget.branchId, isAdmin: widget.isAdmin, t: RoleThemeScope.dataOf(context))),
                            ]);
                          }),
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
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Students', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Color(0xFF1A1C1E))),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('branches').doc(widget.branchId).collection('madrassa_students').snapshots(),
                      builder: (context, snap) {
                        final count = snap.data?.docs.length ?? 0;
                        return Text('$count students enrolled', style: const TextStyle(fontSize: 14, color: Colors.grey));
                      }
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => showAddStudentDialog(context, widget.branchId),
                icon: const Icon(Icons.add),
                label: const Text('Add Student'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008080), // Teal
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E2E7)),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(
                hintText: 'Search by name or roll number...',
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
