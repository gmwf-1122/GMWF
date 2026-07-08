import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

import 'package:intl/intl.dart';
import '../widgets/student_progress_dialog.dart';
import '../utils/photo_upload_helper.dart';

import '../widgets/madrassa_status_menu.dart';
import '../../../theme/role_theme_provider.dart';
import '../dialogs/enrollment_dialog.dart';
import '../madrassa_strings.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/madrassa_providers.dart';

class StudentManagementView extends ConsumerStatefulWidget {
  final String branchId;
  final bool isAdmin;
  final String username;
  final String role;
  const StudentManagementView({
    super.key,
    required this.branchId,
    required this.isAdmin,
    required this.username,
    this.role = 'Madrassa Teacher',
  });

  @override
  ConsumerState<StudentManagementView> createState() => _StudentManagementViewState();
}

class _StudentManagementViewState extends ConsumerState<StudentManagementView> {
  String _searchQuery = '';
  String _statusFilter = 'all';
  String _sortBy = 'rollNumber';
  final Map<String, PhotoUploadStatus> _uploadStates = {};

  Future<void> _importStudentsFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      final fileContent = utf8.decode(bytes);
      final extension = file.extension?.toLowerCase();

      List<Map<String, dynamic>> studentsToImport = [];

      if (extension == 'json') {
        final decoded = jsonDecode(fileContent);
        if (decoded is List) {
          for (var item in decoded) {
            if (item is Map<String, dynamic>) {
              studentsToImport.add(item);
            }
          }
        } else if (decoded is Map<String, dynamic>) {
          studentsToImport.add(decoded);
        }
      } else if (extension == 'csv') {
        studentsToImport = _parseCsvToMap(fileContent);
      }

      if (studentsToImport.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No valid student records found in file. Format should be JSON list or CSV.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            context.isUrdu ? 'طلباء درآمد کریں' : 'Import Students',
            style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          content: Text(
            'Found ${studentsToImport.length} student records in the file. Would you like to import them to local cache and sync with Firestore?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l.cancel, style: context.urduStyle()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF008080)),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.isUrdu ? 'درآمد کریں' : 'Import', style: context.urduStyle(style: const TextStyle(color: Colors.white))),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      int successCount = 0;
      int skippedCount = 0;
      final now = DateTime.now();

      final existingStudents = await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_students')
          .get();
      final existingRollNumbers = existingStudents.docs
          .map((d) => d.data()['rollNumber']?.toString().trim())
          .whereType<String>()
          .toSet();
      final existingIds = existingStudents.docs.map((d) => d.id).toSet();

      for (var s in studentsToImport) {
        final name = s['name']?.toString().trim() ?? '';
        final rollNumber = s['rollNumber']?.toString().trim() ?? '';
        if (name.isEmpty || rollNumber.isEmpty) {
          skippedCount++;
          continue;
        }

        final docId = s['id']?.toString().trim();
        if (docId != null && docId.isNotEmpty && existingIds.contains(docId)) {
          skippedCount++;
          continue;
        }
        if (existingRollNumbers.contains(rollNumber)) {
          skippedCount++;
          continue;
        }

        final guardianName = s['guardianName']?.toString().trim() ?? '';
        final guardianCnic = s['guardianCnic']?.toString().trim() ?? '';
        final contactPhone = s['contactPhone']?.toString().trim() ?? s['phone']?.toString().trim() ?? '';
        final studentCnic = s['studentCnic']?.toString().trim() ?? '';
        final className = s['class']?.toString().trim() ?? 'Hifz';
        final lines = int.tryParse(s['currentLines']?.toString() ?? '') ?? 0;
        final rawHasPrev = s['hasPrevMadrassa'] ?? s['has_prev_madrassa'];
        final hasPrevMadrassa = rawHasPrev != null ? (rawHasPrev.toString().toLowerCase() == 'true' || rawHasPrev.toString() == '1') : false;
        final prevMadrassaName = s['prevMadrassaName']?.toString().trim() ?? s['prev_madrassa_name']?.toString().trim() ?? s['previousMadrassa']?.toString().trim() ?? '';
        final prevHifzLines = int.tryParse(s['prevHifzLines']?.toString() ?? s['prev_hifz_lines']?.toString() ?? s['priorHifzLines']?.toString() ?? '') ?? 0;

        final rawJoinDate = s['joindate'] ?? s['join_date'] ?? s['created_date'] ?? s['createddate'] ?? s['joinDate'] ?? s['createdDate'];
        DateTime parsedJoinDate = now;
        if (rawJoinDate != null) {
          try {
            parsedJoinDate = DateTime.parse(rawJoinDate.toString());
          } catch (_) {
            try {
              parsedJoinDate = DateFormat('yyyy-MM-dd').parse(rawJoinDate.toString());
            } catch (_) {}
          }
        }

        final finalData = {
          'name': name,
          'rollNumber': rollNumber,
          'studentCnic': studentCnic,
          'class': className,
          'guardianName': guardianName,
          'guardianCnic': guardianCnic,
          'contactPhone': contactPhone,
          'joinDate': Timestamp.fromDate(parsedJoinDate),
          'hasPrevMadrassa': hasPrevMadrassa || prevMadrassaName.isNotEmpty,
          'prevMadrassaName': prevMadrassaName,
          'prevHifzLines': prevHifzLines,
          'branchId': widget.branchId,
          'status': 'active',
          'auditLog': [
            {
              'status': 'active',
              'type': 'enrollment',
              'date': Timestamp.fromDate(parsedJoinDate),
              'reason': 'Bulk Import'
            }
          ],
          'currentLines': lines,
          'enrolledMonth': DateFormat('yyyy-MM').format(parsedJoinDate),
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'photoUrl': '',
        };

        if (docId != null && docId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('madrassa_students')
              .doc(docId)
              .set(finalData);
          existingIds.add(docId);
        } else {
          final newDoc = await FirebaseFirestore.instance
              .collection('branches')
              .doc(widget.branchId)
              .collection('madrassa_students')
              .add(finalData);
          existingIds.add(newDoc.id);
        }
        existingRollNumbers.add(rollNumber);
        successCount++;
      }

      if (mounted) {
        String msg = 'Successfully imported $successCount students.';
        if (skippedCount > 0) {
          msg += ' Skipped $skippedCount existing students.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: successCount > 0 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _parseCsvToMap(String csvText) {
    final List<Map<String, dynamic>> result = [];
    final lines = csvText.split('\n');
    if (lines.isEmpty) return result;

    final headerLine = lines.first.trim();
    final headers = headerLine.split(',').map((h) => h.replaceAll('"', '').trim().toLowerCase()).toList();

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final values = _splitCsvLine(line);
      final Map<String, dynamic> row = {};

      for (int j = 0; j < headers.length; j++) {
        if (j < values.length) {
          final header = headers[j];
          final val = values[j];
          if (header == 'rollnumber' || header == 'roll' || header == 'roll_number') {
            row['rollNumber'] = val;
          } else if (header == 'name' || header == 'fullname' || header == 'student_name') {
            row['name'] = val;
          } else if (header == 'guardianname' || header == 'guardian_name') {
            row['guardianName'] = val;
          } else if (header == 'guardiancnic' || header == 'guardian_cnic') {
            row['guardianCnic'] = val;
          } else if (header == 'contactphone' || header == 'phone' || header == 'contact_phone') {
            row['contactPhone'] = val;
          } else if (header == 'studentcnic' || header == 'student_cnic') {
            row['studentCnic'] = val;
          } else if (header == 'class' || header == 'classname') {
            row['class'] = val;
          } else if (header == 'currentlines' || header == 'lines' || header == 'progress') {
            row['currentLines'] = val;
          } else {
            row[header] = val;
          }
        }
      }
      result.add(row);
    }
    return result;
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    StringBuffer sb = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(char);
      }
    }
    result.add(sb.toString().trim());
    return result;
  }

  void _showStudentProgressDialog(BuildContext context, Map<String, dynamic> studentData) {
    final totalLines = 8640;
    final currentLines = (studentData['currentLines'] as num?)?.toInt() ?? 0;
    final prevLines = int.tryParse(studentData['prevHifzLines']?.toString() ?? '0') ?? 0;
    // joinDate may be stored as Timestamp or ISO string
    final dynamic joinField = studentData['joinDate'];
    Timestamp? joinTimestamp;
    if (joinField is Timestamp) {
      joinTimestamp = joinField;
    } else if (joinField is String) {
      try {
        final parsed = DateTime.parse(joinField);
        joinTimestamp = Timestamp.fromDate(parsed);
      } catch (_) {}
    }
    final joinDate = joinTimestamp?.toDate();
    final daysSinceJoin = (joinDate != null) ? DateTime.now().difference(joinDate).inDays : 0;
    // totalMemorized = lines at this madrassa + prior hifz
    final totalMemorized = currentLines + prevLines;
    // Use totalMemorized for rate so prior hifz is reflected in the student's real pace
    final avgPerDay = daysSinceJoin > 0 ? totalMemorized / daysSinceJoin : 0.0;
    final remainingLines = (totalLines - totalMemorized).clamp(0, totalLines);
    final estimatedDays = avgPerDay > 0 ? (remainingLines / avgPerDay).ceil() : null;
    final pct = ((totalMemorized / totalLines) * 100).clamp(0.0, 100.0).toStringAsFixed(1);

    showDialog(
      context: context,
      builder: (_) => StudentProgressDialog(
        studentName: studentData['name'] ?? 'Student',
        photoUrl: studentData['photoUrl'],
        className: studentData['class']?.toString() ?? 'Hifz',
        rollNumber: studentData['rollNumber']?.toString() ?? '?',
        joinDate: joinDate,
        totalLines: totalLines,
        currentLines: currentLines,
        prevHifzLines: prevLines,
        percentage: pct,
        estimatedDays: estimatedDays,
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, Map<String, dynamic> d) {
    final status = d['status'] ?? 'active';
    String statusLabel;
    Color color;

    switch (status) {
      case 'active':
        statusLabel = context.l.statusActive;
        color = const Color(0xFF008080); // Teal
        break;
      case 'archived':
        statusLabel = context.l.statusArchived;
        color = const Color(0xFFF59E0B); // Amber
        break;
      case 'hifz_completed':
        statusLabel = context.l.statusHifzCompleted;
        color = const Color(0xFF4C4DDC); // Purple
        break;
      case 'left':
        statusLabel = context.l.statusLeft;
        color = const Color(0xFFEF4444); // Red/Rose
        break;
      case 'inactive':
        statusLabel = context.isUrdu ? 'غیر فعال' : 'Inactive';
        color = const Color(0xFF6B7280); // Slate Gray
        break;
      default:
        statusLabel = status.toString().toUpperCase();
        color = const Color(0xFF6B7280);
    }

    // Extract the latest reason for this status from auditLog
    String reason = '';
    final rawAuditLog = d['auditLog'];
    final auditListRaw = rawAuditLog is List ? rawAuditLog : [];
    if (auditListRaw.isNotEmpty) {
      final auditList = List<Map<String, dynamic>>.from(
        auditListRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      // Sort in descending order to get the latest first
      auditList.sort((a, b) {
        final dynamic aRaw = a['date'];
        final dynamic bRaw = b['date'];
        
        DateTime aDate;
        if (aRaw is Timestamp) {
          aDate = aRaw.toDate();
        } else if (aRaw is String) {
          aDate = DateTime.tryParse(aRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
        } else {
          aDate = DateTime.fromMillisecondsSinceEpoch(0);
        }

        DateTime bDate;
        if (bRaw is Timestamp) {
          bDate = bRaw.toDate();
        } else if (bRaw is String) {
          bDate = DateTime.tryParse(bRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
        } else {
          bDate = DateTime.fromMillisecondsSinceEpoch(0);
        }

        return bDate.compareTo(aDate);
      });
      final matchingEntry = auditList.firstWhere(
        (entry) => entry['status'] == status,
        orElse: () => <String, dynamic>{},
      );
      if (matchingEntry.isNotEmpty) {
        reason = matchingEntry['reason'] ?? '';
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25), width: 1),
          ),
          child: Text(
            statusLabel,
            style: context.urduStyle(
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        if (reason.isNotEmpty && reason != statusLabel && reason != '$statusLabel:') ...[
          const SizedBox(height: 4),
          Tooltip(
            message: reason,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.urduStyle(
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileStudentCard(dynamic s, Map<String, dynamic> d) {
    final studentId = s is DocumentSnapshot ? s.id : s['id'].toString();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E2E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _pickAndUploadPhoto(studentId),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFF0F2F5), shape: BoxShape.circle),
                  child: _uploadStates[studentId] == PhotoUploadStatus.uploading
                      ? const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF008080)),
                        )
                      : (d['photoUrl'] != null && d['photoUrl'].toString().isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                d['photoUrl'],
                                fit: BoxFit.cover,
                                width: 36,
                                height: 36,
                                errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(d['name'], fontSize: 14),
                              ),
                            )
                          : _buildAvatarFallback(d['name'], fontSize: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      '${context.l.rollNumber}: ${d['rollNumber'] ?? '?'} • Class: ${d['class'] ?? 'Hifz'}',
                      style: context.urduStyle(style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ),
                    const SizedBox(height: 6),
                    _buildStatusChip(context, d),
                  ],
                ),
              ),
              StatusActionMenu(
                student: s,
                branchId: widget.branchId,
                isAdmin: widget.isAdmin,
                t: RoleThemeScope.dataOf(context),
                username: widget.username,
                role: widget.role,
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, color: Color(0xFF008080)),
                tooltip: context.l.moreInfo,
                onPressed: () => _showStudentProgressDialog(context, d),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE0E2E7)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l.guardianFullName, style: context.urduStyle(style: TextStyle(fontSize: 10, color: Colors.grey[500]))),
                  const SizedBox(height: 2),
                  Text(d['guardianName'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(context.l.contactPhone, style: context.urduStyle(style: TextStyle(fontSize: 10, color: Colors.grey[500]))),
                  const SizedBox(height: 2),
                  Text(d['contactPhone'] ?? d['phone'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildProgressBar(context, d['currentLines'] ?? 0),
        ],
      ),
    );
  }


  

  Widget _buildProgressBar(BuildContext context, int currentLines) {
    const int totalLines = 8640;
    final double pct = (currentLines / totalLines).clamp(0.0, 1.0);
    final pctText = (pct * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${context.l.memorizationProgress} ($currentLines ${context.l.lines})',
              style: context.urduStyle(style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600])),
            ),
            Text('$pctText%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF008080))),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: const Color(0xFFF0F2F5),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF008080)),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          _buildPendingRejoinRequests(),
          Expanded(
            child: ref.watch(madrassaStudentsProvider(widget.branchId)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error loading students: $e')),
              data: (studentsList) {
                final filteredStudents = studentsList.where((d) {
                  final name = (d['name'] ?? '').toString().toLowerCase();
                  final roll = (d['rollNumber'] ?? '').toString().toLowerCase();
                  final query = _searchQuery.toLowerCase();
                  
                  final matchesSearch = name.contains(query) || roll.contains(query);
                  if (!matchesSearch) return false;

                  if (_statusFilter != 'all') {
                    final status = d['status'] ?? 'active';
                    return status == _statusFilter;
                  }
                  return true;
                }).toList()..sort((a, b) {
                  if (_sortBy == 'rollNumber') {
                    final aVal = int.tryParse(a['rollNumber']?.toString() ?? '') ?? 999999;
                    final bVal = int.tryParse(b['rollNumber']?.toString() ?? '') ?? 999999;
                    return aVal.compareTo(bVal);
                  } else if (_sortBy == 'progress') {
                    final aLines = (a['currentLines'] as num?)?.toInt() ?? 0;
                    final aPrev = int.tryParse(a['prevHifzLines']?.toString() ?? '0') ?? 0;
                    final aTotal = aLines + aPrev;

                    final bLines = (b['currentLines'] as num?)?.toInt() ?? 0;
                    final bPrev = int.tryParse(b['prevHifzLines']?.toString() ?? '0') ?? 0;
                    final bTotal = bLines + bPrev;

                    return bTotal.compareTo(aTotal);
                  } else if (_sortBy == 'joinDate') {
                    final dynamic aJoinRaw = a['joinDate'];
                    final dynamic bJoinRaw = b['joinDate'];
                    
                    DateTime aJoin;
                    if (aJoinRaw is Timestamp) {
                      aJoin = aJoinRaw.toDate();
                    } else if (aJoinRaw is String) {
                      aJoin = DateTime.tryParse(aJoinRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
                    } else {
                      aJoin = DateTime.fromMillisecondsSinceEpoch(0);
                    }

                    DateTime bJoin;
                    if (bJoinRaw is Timestamp) {
                      bJoin = bJoinRaw.toDate();
                    } else if (bJoinRaw is String) {
                      bJoin = DateTime.tryParse(bJoinRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
                    } else {
                      bJoin = DateTime.fromMillisecondsSinceEpoch(0);
                    }

                    return bJoin.compareTo(aJoin);
                  }
                  return 0;
                });

                if (filteredStudents.isEmpty) {
                  return Center(
                    child: Text(
                      context.l.noData,
                      style: context.urduStyle(style: const TextStyle(color: Colors.grey)),
                    ),
                  );
                }

                // Group students by batch
                final Map<String, List<Map<String, dynamic>>> studentsByBatch = {};
                for (final student in filteredStudents) {
                  final batch = student['batch'] ?? 'active';
                  studentsByBatch.putIfAbsent(batch, () => []).add(student);
                }

                // Define batch order
                const batchOrder = ['active', 'left', 'dropped', 'hifz_complete'];

                if (isMobile) {
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final batch in batchOrder)
                        if (studentsByBatch.containsKey(batch))
                          ...[
                            _buildBatchHeader(context, batch),
                            ...studentsByBatch[batch]!.map((s) => _buildMobileStudentCard(s, s)),
                          ]
                    ],
                  );
                }

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final batch in batchOrder)
                          if (studentsByBatch.containsKey(batch))
                            ...[
                              _buildBatchHeader(context, batch),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE0E2E7)),
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                  columnSpacing: 12,
                                  horizontalMargin: 12,
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F4F9)),
                                  dataRowMinHeight: 60,
                                  dataRowMaxHeight: 60,
                                  columns: [
                                    const DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(context.l.students, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)))),
                                    DataColumn(label: Text(context.l.rollNumber, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)))),
                                    const DataColumn(label: Text('Class', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(context.l.guardianFullName, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)))),
                                    DataColumn(label: Text(context.l.contactPhone, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)))),
                                    DataColumn(label: Text(context.l.overallProgress, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)))),
                                    const DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text(context.l.todayActions, style: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold)))),
                                  ],
                                  rows: List.generate(studentsByBatch[batch]!.length, (i) {
                                    final s = studentsByBatch[batch]![i];
                                    final d = s;
                                    final studentId = s['id'].toString();
                                    final lines = d['currentLines'] ?? 0;
                                    final prevL = int.tryParse(d['prevHifzLines']?.toString() ?? '0') ?? 0;
                                    final totalL = lines + prevL;
                                    final pct = (totalL / 8640 * 100).clamp(0.0, 100.0).toStringAsFixed(1);

                                    return DataRow(cells: [
                                      DataCell(Text('${i + 1}')),
                                      DataCell(Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _pickAndUploadPhoto(studentId),
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: const BoxDecoration(color: Color(0xFFF0F2F5), shape: BoxShape.circle),
                                              child: _uploadStates[studentId] == PhotoUploadStatus.uploading
                                                  ? const Padding(
                                                      padding: EdgeInsets.all(4.0),
                                                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF008080)),
                                                    )
                                                  : (d['photoUrl'] != null && d['photoUrl'].toString().isNotEmpty
                                                      ? ClipOval(
                                                          child: Image.network(
                                                            d['photoUrl'],
                                                            fit: BoxFit.cover,
                                                            width: 24,
                                                            height: 24,
                                                            errorBuilder: (context, error, stackTrace) => _buildAvatarFallback(d['name'], fontSize: 10),
                                                          ),
                                                        )
                                                      : _buildAvatarFallback(d['name'], fontSize: 10)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(d['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ],
                                      )),
                                      DataCell(Text(d['rollNumber']?.toString() ?? '?')),
                                      DataCell(Text(d['class']?.toString() ?? 'Hifz')),
                                      DataCell(Text(d['guardianName']?.toString() ?? '—')),
                                      DataCell(Text(d['contactPhone']?.toString() ?? d['phone']?.toString() ?? '—')),
                                      DataCell(Row(
                                        children: [
                                          Text('$totalL lines ($pct%)', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF008080))),
                                          IconButton(
                                            icon: const Icon(Icons.info_outline, size: 14, color: Color(0xFF008080)),
                                            tooltip: context.l.moreInfo,
                                            onPressed: () => _showStudentProgressDialog(context, d),
                                          ),
                                        ],
                                      )),
                                      DataCell(_buildStatusChip(context, d)),
                                      DataCell(StatusActionMenu(
                                        student: s,
                                        branchId: widget.branchId,
                                        isAdmin: widget.isAdmin,
                                        t: RoleThemeScope.dataOf(context),
                                        username: widget.username,
                                        role: widget.role,
                                      )),
                                    ]);
                                  }),
                                ),
                              ),
                              ),
                              const SizedBox(height: 24),
                            ]
                      ],
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

  Widget _buildBatchHeader(BuildContext context, String batch) {
    String displayName;
    Color batchColor;
    IconData batchIcon;
    
    switch (batch) {
      case 'active':
        displayName = 'Active Students';
        batchColor = Colors.green;
        batchIcon = Icons.check_circle;
        break;
      case 'left':
        displayName = 'Students Left';
        batchColor = Colors.orange;
        batchIcon = Icons.exit_to_app;
        break;
      case 'dropped':
        displayName = 'Dropped Students';
        batchColor = Colors.red;
        batchIcon = Icons.cancel;
        break;
      case 'hifz_complete':
        displayName = 'Hifz Complete';
        batchColor = Colors.blue;
        batchIcon = Icons.auto_stories;
        break;
      default:
        displayName = batch;
        batchColor = Colors.grey;
        batchIcon = Icons.people;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        children: [
          Icon(batchIcon, color: batchColor, size: 24),
          const SizedBox(width: 12),
          Text(
            displayName,
            style: context.urduStyle(
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: batchColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.l.studentRoster,
                style: context.urduStyle(
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.isAdmin)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF008080),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _importStudentsFile,
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        context.isUrdu ? 'درآمد کریں' : 'Import File',
                        style: context.urduStyle(style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => showAddStudentDialog(
                        context,
                        widget.branchId,
                        username: widget.username,
                        role: widget.role,
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(
                        context.l.enrollNew,
                        style: context.urduStyle(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: '${context.l.search}...',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final isSmallScreen = MediaQuery.of(context).size.width < 600;

              final statusFilterDropdown = DropdownButtonFormField<String>(
                value: _statusFilter,
                decoration: InputDecoration(
                  labelText: context.isUrdu ? 'حیثیت کے لحاظ سے فلٹر کریں' : 'Filter by Status',
                  labelStyle: context.urduStyle(style: const TextStyle(fontSize: 12, color: Color(0xFF008080))),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
                  ),
                ),
                dropdownColor: Colors.white,
                style: context.urduStyle(style: const TextStyle(color: Colors.black, fontSize: 13)),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(context.isUrdu ? 'تمام' : 'All Statuses')),
                  DropdownMenuItem(value: 'active', child: Text(context.l.statusActive)),
                  DropdownMenuItem(value: 'inactive', child: Text(context.isUrdu ? 'غیر فعال' : 'Inactive')),
                  DropdownMenuItem(value: 'archived', child: Text(context.l.statusArchived)),
                  DropdownMenuItem(value: 'hifz_completed', child: Text(context.l.statusHifzCompleted)),
                  DropdownMenuItem(value: 'left', child: Text(context.l.statusLeft)),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _statusFilter = val;
                    });
                  }
                },
              );

              final sortByDropdown = DropdownButtonFormField<String>(
                value: _sortBy,
                decoration: InputDecoration(
                  labelText: context.isUrdu ? 'ترتیب دیں' : 'Sort By',
                  labelStyle: context.urduStyle(style: const TextStyle(fontSize: 12, color: Color(0xFF008080))),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
                  ),
                ),
                dropdownColor: Colors.white,
                style: context.urduStyle(style: const TextStyle(color: Colors.black, fontSize: 13)),
                items: [
                  DropdownMenuItem(value: 'rollNumber', child: Text(context.isUrdu ? 'رول نمبر' : 'Roll Number')),
                  DropdownMenuItem(value: 'progress', child: Text(context.isUrdu ? 'حفظ کی ترقی' : 'Progress')),
                  DropdownMenuItem(value: 'joinDate', child: Text(context.isUrdu ? 'شمولیت کی تاریخ' : 'Joining Date')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _sortBy = val;
                    });
                  }
                },
              );

              return isSmallScreen
                  ? Column(
                      children: [
                        statusFilterDropdown,
                        const SizedBox(height: 12),
                        sortByDropdown,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: statusFilterDropdown),
                        const SizedBox(width: 12),
                        Expanded(child: sortByDropdown),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(String studentId) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (!mounted) return;
      setState(() => _uploadStates[studentId] = PhotoUploadStatus.uploading);

      final bytes = await picked.readAsBytes();
      
      final uploadStream = PhotoUploadHelper.upload(
        bytes: bytes,
        branchId: widget.branchId,
        studentId: studentId,
      );

      await for (final state in uploadStream) {
        if (!mounted) return;
        setState(() {
          _uploadStates[studentId] = state.status;
        });

        if (state.status == PhotoUploadStatus.success) {
          final downloadUrl = state.downloadUrl;
          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('branches')
                .doc(widget.branchId)
                .collection('madrassa_students')
                .doc(studentId)
                .update({'photoUrl': downloadUrl});

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Photo updated')),
              );
            }
          }
        } else if (state.status == PhotoUploadStatus.error) {
          throw Exception(state.error ?? 'Upload error');
        }
      }
    } catch (e) {
      
      if (!mounted) return;
      setState(() => _uploadStates[studentId] = PhotoUploadStatus.error);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo upload failed, try again.')),
      );
    }
  }

  Widget _buildAvatarFallback(String? name, {double? fontSize}) {
    final firstLetter = name != null && name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE0F2F1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        firstLetter,
        style: TextStyle(
          color: const Color(0xFF008080),
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }

  Widget _buildPendingRejoinRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_students')
          .where('rejoinRequestStatus', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final docs = snap.data!.docs;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7), // Light amber
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hail_rounded, color: Color(0xFFD97706), size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Pending Rejoining Requests (${docs.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF92400E)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const Divider(color: Color(0xFFFDE68A)),
                itemBuilder: (context, i) {
                  final s = docs[i];
                  final d = s.data() as Map<String, dynamic>;
                  final date = d['rejoinRequestDate'] as Timestamp?;
                  final dateStr = date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date.toDate()) : '';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${d['name'] ?? ''} (Roll: ${d['rollNumber'] ?? '?'})',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF78350F)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Reason: "${d['rejoinRequestReason'] ?? 'No reason specified'}"',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                              ),
                              if (dateStr.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Requested on: $dateStr',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFFB45309)),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _approveRejoin(s),
                          icon: const Icon(Icons.check, size: 14),
                          label: const Text('Approve', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _rejectRejoin(s),
                          icon: const Icon(Icons.close, size: 14, color: Colors.red),
                          label: const Text('Reject', style: TextStyle(fontSize: 11, color: Colors.red)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _approveRejoin(DocumentSnapshot studentDoc) async {
    final now = Timestamp.now();
    final sData = studentDoc.data() as Map<String, dynamic>;
    final auditReason = 'Rejoin request approved. Notes: ${sData['rejoinRequestReason'] ?? ''}';

    await studentDoc.reference.update({
      'status': 'active',
      'rejoinRequestStatus': null,
      'rejoinRequestReason': null,
      'rejoinRequestDate': null,
      'auditLog': FieldValue.arrayUnion([
        {
          'status': 'active',
          'type': 'rejoin_approval',
          'date': now,
          'reason': auditReason,
        }
      ]),
    });

    // Central Audit Log
    await MadrassaAuditService.logAction(
      branchId: widget.branchId,
      editor: widget.username,
      role: widget.role,
      type: 'status_change',
      message: 'Approved rejoining request for student ${sData['name'] ?? ''} (Roll: ${sData['rollNumber'] ?? ''})',
      studentId: studentDoc.id,
      studentName: sData['name'],
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rejoin approved for ${sData['name'] ?? ''}')),
      );
    }
  }

  Future<void> _rejectRejoin(DocumentSnapshot studentDoc) async {
    final sData = studentDoc.data() as Map<String, dynamic>;
    final reasonCtrl = TextEditingController();
    String? reasonError;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDs) {
          return AlertDialog(
            title: const Text('Reject Rejoin Request', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Are you sure you want to reject the rejoin request for ${sData['name'] ?? ''}?'),
                const SizedBox(height: 16),
                RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'Rejection Reason',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      TextSpan(
                        text: ' *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Class capacity reached.',
                    errorText: reasonError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: reasonError != null ? const Color(0xFFD32F2F) : const Color(0xFFD0D3D9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    if (reasonError != null) setDs(() => reasonError = null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (reasonCtrl.text.trim().isEmpty) {
                    setDs(() {
                      reasonError = 'Rejection reason is required';
                    });
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text('Reject'),
              ),
            ],
          );
        },
      ),
    );

    if (confirm == true) {
      final now = Timestamp.now();
      final customReason = reasonCtrl.text.trim();
      final finalReason = customReason.isEmpty ? 'Rejoin request rejected by teacher.' : 'Rejoin request rejected by teacher. Reason: $customReason';

      await studentDoc.reference.update({
        'rejoinRequestStatus': 'rejected',
        'auditLog': FieldValue.arrayUnion([
          {
            'status': sData['status'] ?? 'left',
            'type': 'rejoin_rejection',
            'date': now,
            'reason': finalReason,
          }
        ]),
      });

      // Central Audit Log
      await MadrassaAuditService.logAction(
        branchId: widget.branchId,
        editor: widget.username,
        role: widget.role,
        type: 'status_change',
        message: 'Rejected rejoining request for student ${sData['name'] ?? ''} (Roll: ${sData['rollNumber'] ?? ''}). Reason: $customReason',
        studentId: studentDoc.id,
        studentName: sData['name'],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rejoin rejected for ${sData['name'] ?? ''}')),
        );
      }
    }
  }
}
