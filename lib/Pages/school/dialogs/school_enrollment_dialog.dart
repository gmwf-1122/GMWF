// lib/pages/school/dialogs/school_enrollment_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../widgets/media_upload_tile.dart';
import '../models/school_student.dart';
import '../utils/school_local_storage.dart';
import '../constants/school_constants.dart';

class SchoolEnrollmentDialog extends StatefulWidget {
  final String branchId;
  final SchoolStudent? studentToEdit;

  const SchoolEnrollmentDialog({
    super.key,
    required this.branchId,
    this.studentToEdit,
  });

  @override
  State<SchoolEnrollmentDialog> createState() => _SchoolEnrollmentDialogState();
}

class _SchoolEnrollmentDialogState extends State<SchoolEnrollmentDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _rollNoCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _guardianNameCtrl;
  late TextEditingController _guardianPhoneCtrl;
  late TextEditingController _addressCtrl;

  String _selectedGrade = 'Pre-9th';
  String _selectedSection = 'A';
  String _selectedAcademicGroup = 'General';
  String _selectedGender = 'Male';
  String _status = 'active';
  String? _photoUrl;
  String? _guardianCnicUrl;
  String? _bformUrl;
  List<Map<String, String>> _additionalDocuments = [];
  DateTime _admissionDate = DateTime.now();
  bool _isSaving = false;

  final List<String> _grades = SchoolConstants.grades;
  final List<String> _sections = SchoolConstants.sections;

  @override
  void initState() {
    super.initState();
    final st = widget.studentToEdit;
    _rollNoCtrl = TextEditingController(text: st?.rollNo ?? '');
    _nameCtrl = TextEditingController(text: st?.name ?? '');
    _guardianNameCtrl = TextEditingController(text: st?.guardianName ?? '');
    _guardianPhoneCtrl = TextEditingController(text: st?.guardianPhone ?? '');
    _addressCtrl = TextEditingController(text: st?.address ?? '');

    if (st != null) {
      _selectedGrade = _grades.contains(st.grade) ? st.grade : _grades.first;
      _selectedSection = _sections.contains(st.section) ? st.section : _sections.first;
      final availGroups = SchoolConstants.getAcademicGroupsForGrade(_selectedGrade);
      _selectedAcademicGroup = availGroups.contains(st.academicGroup) ? st.academicGroup : availGroups.first;
      _selectedGender = st.gender;
      _status = st.status;
      _photoUrl = st.photoUrl;
      _guardianCnicUrl = st.guardianCnicUrl;
      _bformUrl = st.bformUrl;
      _additionalDocuments = st.additionalDocuments.map((d) => Map<String, String>.from(d)).toList();
      if (st.admissionDate.isNotEmpty) {
        _admissionDate = DateTime.tryParse(st.admissionDate) ?? DateTime.now();
      }
    } else {
      _selectedGrade = '1';
      _selectedAcademicGroup = 'General';
    }
  }

  @override
  void dispose() {
    _rollNoCtrl.dispose();
    _nameCtrl.dispose();
    _guardianNameCtrl.dispose();
    _guardianPhoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final studentId = widget.studentToEdit?.id ?? 'SCH-${DateTime.now().millisecondsSinceEpoch}';
    final studentData = {
      'rollNo': _rollNoCtrl.text.trim(),
      'name': _nameCtrl.text.trim(),
      'guardianName': _guardianNameCtrl.text.trim(),
      'guardianPhone': _guardianPhoneCtrl.text.trim(),
      'grade': _selectedGrade,
      'section': _selectedSection,
      'academicGroup': _selectedAcademicGroup,
      'gender': _selectedGender,
      'status': _status,
      'photoUrl': _photoUrl ?? '',
      'guardianCnicUrl': _guardianCnicUrl ?? '',
      'bformUrl': _bformUrl ?? '',
      'additionalDocuments': _additionalDocuments,
      'branchId': widget.branchId,
      'admissionDate': DateFormat('yyyy-MM-dd').format(_admissionDate),
      'address': _addressCtrl.text.trim(),
    };

    await SchoolLocalStorage.saveStudent(
      branchId: widget.branchId,
      studentId: studentId,
      studentData: studentData,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _addCustomDocumentDialog() async {
    final titleCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.note_add_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 10),
            Text('Add Custom Document', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the document name (e.g., Previous School Certificate, Medical Certificate, Character Letter):',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: 'Document Name *',
                hintText: 'e.g. Previous School Certificate',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
            onPressed: () {
              final text = titleCtrl.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Add & Attach File'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _additionalDocuments.add({'name': result, 'url': ''});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.studentToEdit != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 680,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.school_rounded, color: Color(0xFF6366F1)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isEditing ? 'Edit Student Profile & Admission' : 'New Student Admission & Profile',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),

                // SECTION 1: Student & Guardian Upload Documents
                const Text(
                  'Student Profile & Official Documents',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 10),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Student Photo
                    Expanded(
                      child: MediaUploadTile(
                        label: 'Student Photo',
                        icon: Icons.add_a_photo_outlined,
                        initialValue: _photoUrl,
                        onChanged: (val) => setState(() => _photoUrl = val),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Guardian CNIC Document
                    Expanded(
                      child: MediaUploadTile(
                        label: 'Guardian CNIC',
                        icon: Icons.badge_outlined,
                        isDocument: true,
                        initialValue: _guardianCnicUrl,
                        onChanged: (val) => setState(() => _guardianCnicUrl = val),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // B-Form / Birth Certificate Document
                    Expanded(
                      child: MediaUploadTile(
                        label: 'B-Form / Birth Cert',
                        icon: Icons.description_outlined,
                        isDocument: true,
                        initialValue: _bformUrl,
                        onChanged: (val) => setState(() => _bformUrl = val),
                      ),
                    ),
                  ],
                ),

                // Additional Custom Documents List
                if (_additionalDocuments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Custom Documents:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  ..._additionalDocuments.asMap().entries.map((entry) {
                    final index = entry.key;
                    final doc = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: MediaUploadTile(
                              label: doc['name'] ?? 'Custom Document',
                              icon: Icons.file_present_rounded,
                              isDocument: true,
                              initialValue: doc['url'],
                              onChanged: (val) {
                                setState(() {
                                  _additionalDocuments[index]['url'] = val ?? '';
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            onPressed: () {
                              setState(() {
                                _additionalDocuments.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                    label: const Text('+ Add Custom Document (e.g. SLC, Medical, Degree)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _addCustomDocumentDialog,
                  ),
                ),

                const Divider(height: 32),

                  // Roll No & Name
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _rollNoCtrl,
                          decoration: InputDecoration(
                            labelText: 'Roll No',
                            hintText: 'e.g. 101',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Student Full Name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Enter student name' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Grade, Section & Academic Group
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _selectedGrade,
                          decoration: InputDecoration(
                            labelText: 'Class',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: _grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _selectedGrade = v;
                                final avail = SchoolConstants.getAcademicGroupsForGrade(v);
                                if (!avail.contains(_selectedAcademicGroup)) {
                                  _selectedAcademicGroup = avail.first;
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          value: _selectedSection,
                          decoration: InputDecoration(
                            labelText: 'Section',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: _sections.map((s) => DropdownMenuItem(value: s, child: Text('Sec $s'))).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedSection = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Academic Group / Subject Stream
                  Builder(
                    builder: (context) {
                      final groupOptions = SchoolConstants.getAcademicGroupsForGrade(_selectedGrade);
                      final isHigh = SchoolConstants.isHighSchool(_selectedGrade);

                      return DropdownButtonFormField<String>(
                        value: groupOptions.contains(_selectedAcademicGroup) ? _selectedAcademicGroup : groupOptions.first,
                        decoration: InputDecoration(
                          labelText: isHigh ? 'Academic Group / Stream (High School)' : 'Academic Group (General Stream)',
                          helperText: isHigh ? 'Select subject stream (Computer, Biology, Arts, General)' : 'Automatic General stream for Primary & Middle classes',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: groupOptions.map((group) {
                          return DropdownMenuItem(value: group, child: Text(group));
                        }).toList(),
                        onChanged: isHigh ? (v) {
                          if (v != null) setState(() => _selectedAcademicGroup = v);
                        } : null, // Disabled / fixed for general grades
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Guardian Name & Phone
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _guardianNameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Guardian Name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Enter guardian' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _guardianPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Guardian Phone',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Enter phone' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Gender & Status
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedGender,
                          decoration: InputDecoration(
                            labelText: 'Gender',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Male', child: Text('Male')),
                            DropdownMenuItem(value: 'Female', child: Text('Female')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedGender = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _status,
                          decoration: InputDecoration(
                            labelText: 'Enrollment Status',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                            DropdownMenuItem(value: 'graduated', child: Text('Graduated')),
                            DropdownMenuItem(value: 'dropped', child: Text('Dropped')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _status = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Address
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: InputDecoration(
                      labelText: 'Residential Address',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveStudent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(isEditing ? 'Save Changes' : 'Enroll Student'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
