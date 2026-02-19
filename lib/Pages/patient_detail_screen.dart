// lib/pages/patient_detail_screen.dart — COMPLETE REDESIGN

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'patient_history.dart';
import 'dart:async';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final bool isOnline;
  final Box localBox;
  final String branchId;
  final String doctorId;
  final bool isAdmin;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.isOnline,
    required this.localBox,
    required this.branchId,
    required this.doctorId,
    this.isAdmin = false,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _noteController     = TextEditingController();
  final TextEditingController _medicineController = TextEditingController();
  final TextEditingController _nameController     = TextEditingController();
  final TextEditingController _cnicController     = TextEditingController();
  final TextEditingController _guardianCnicController = TextEditingController();
  final TextEditingController _phoneController    = TextEditingController();
  final TextEditingController _dobController      = TextEditingController();
  final TextEditingController _ageController      = TextEditingController();

  String? _selectedGender;
  String? _selectedBloodGroup;
  String? _selectedStatus;
  String? branchName;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // ── Palette ─────────────────────────────────────────────────
  static const Color _primary   = Color(0xFF00796B);
  static const Color _dark      = Color(0xFF004D40);
  static const Color _accent    = Color(0xFF26A69A);
  static const Color _bg        = Color(0xFFF5F6FA);
  static const Color _surface   = Color(0xFFFFFFFF);
  static const Color _ink       = Color(0xFF1C1F26);
  static const Color _inkMid    = Color(0xFF5A6072);
  static const Color _inkLight  = Color(0xFFADB5BD);
  static const Color _divider   = Color(0xFFE9ECEF);
  static const Color _light     = Color(0xFFE0F2F1);

  // Status colours
  static const Map<String, Color> _statusColors = {
    'Zakat':     Color(0xFF1565C0),
    'Non-Zakat': Color(0xFF6A1B9A),
    'GMWF':      Color(0xFF2E7D32),
  };

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    _fetchBranchName();
  }

  @override
  void dispose() {
    _animController.dispose();
    _noteController.dispose(); _medicineController.dispose();
    _nameController.dispose(); _cnicController.dispose();
    _guardianCnicController.dispose(); _phoneController.dispose();
    _dobController.dispose(); _ageController.dispose();
    super.dispose();
  }

  Future<void> _fetchBranchName() async {
    try {
      final doc = await _firestore.collection('branches').doc(widget.branchId.toLowerCase()).get();
      if (doc.exists) setState(() => branchName = doc.data()!['name'] as String? ?? widget.branchId);
    } catch (_) {}
  }

  Stream<DocumentSnapshot> _patientStream() => _firestore
      .collection('branches').doc(widget.branchId.toLowerCase())
      .collection('patients').doc(widget.patientId).snapshots();

  Stream<QuerySnapshot> _childrenStream(String? cnic) => _firestore
      .collection('branches').doc(widget.branchId.toLowerCase())
      .collection('patients')
      .where('guardianCnic', isEqualTo: cnic)
      .where('isAdult', isEqualTo: false).snapshots();

  Future<DocumentSnapshot?> _getGuardian(String? guardianCnic) async {
    if (guardianCnic == null || guardianCnic.trim().isEmpty || guardianCnic == 'Unknown') return null;
    final qs = await _firestore
        .collection('branches').doc(widget.branchId.toLowerCase())
        .collection('patients').where('cnic', isEqualTo: guardianCnic.trim()).limit(1).get();
    return qs.docs.isNotEmpty ? qs.docs[0] : null;
  }

  Future<bool> _checkPassword() async {
    final completer = Completer<bool>();
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _light, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.lock_outline_rounded, color: _primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Text('Admin Verification',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(fontSize: 14, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Enter admin password',
                  hintStyle: const TextStyle(color: _inkLight),
                  prefixIcon: const Icon(Icons.password_rounded, color: _inkLight, size: 20),
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () { Navigator.pop(ctx); completer.complete(false); },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _divider)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: _inkMid, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (ctrl.text == 'admin1122') { Navigator.pop(ctx); completer.complete(true); }
                      else _snack('Wrong password', error: true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    return completer.future;
  }

  void _showEditDialog(Map<String, dynamic> data) async {
    if (!await _checkPassword()) return;

    final editKey = GlobalKey<FormState>();
    final isAdult = data['isAdult'] == true;

    _nameController.text = data['name'] ?? '';
    _cnicController.text = data['cnic'] ?? '';
    _guardianCnicController.text = data['guardianCnic'] ?? '';
    _phoneController.text = data['phone'] ?? '';
    _ageController.text = data['age']?.toString() ?? '';
    _selectedGender = data['gender'];
    _selectedBloodGroup = data['bloodGroup'] ?? 'N/A';
    _selectedStatus = data['status'] ?? 'Zakat';

    final dobTs = data['dob'] as Timestamp?;
    _dobController.text = dobTs != null ? DateFormat('dd-MM-yyyy').format(dobTs.toDate()) : '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: _bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                decoration: const BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(children: [
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Edit Patient',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                    padding: EdgeInsets.zero,
                  ),
                ]),
              ),
              // Form
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: editKey,
                    child: Column(children: [
                      _editField(_nameController, 'Full Name', Icons.person_outline_rounded,
                          validator: (v) => v?.isEmpty ?? true ? 'Required' : null),
                      _editField(_cnicController, 'CNIC (XXXXX-XXXXXXX-X)', Icons.credit_card_outlined,
                          maxLen: 15, formatters: [CNICInputFormatter()],
                          validator: (v) {
                            final r = RegExp(r'^\d{5}-\d{7}-\d{1}$');
                            if (!isAdult && (v?.isEmpty ?? true)) return null;
                            if (v?.isEmpty ?? true) return 'Required';
                            if (!r.hasMatch(v!)) return 'Format: 12345-1234567-1';
                            return null;
                          }),
                      if (!isAdult)
                        _editField(_guardianCnicController, 'Guardian CNIC', Icons.credit_card_outlined,
                            maxLen: 15, formatters: [CNICInputFormatter()],
                            validator: (v) {
                              final r = RegExp(r'^\d{5}-\d{7}-\d{1}$');
                              if (v?.isEmpty ?? true) return 'Required';
                              if (!r.hasMatch(v!)) return 'Format: 12345-1234567-1';
                              return null;
                            }),
                      _editField(_phoneController, 'Phone Number', Icons.phone_outlined,
                          type: TextInputType.phone, maxLen: 11,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) { if (v != null && v.isNotEmpty && v.length != 11) return '11 digits required'; return null; }),
                      _editField(_dobController, 'Date of Birth (dd-MM-yyyy)', Icons.cake_outlined,
                          type: TextInputType.datetime,
                          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(10), _DobFormatter()],
                          onChanged: (v) {
                            if (RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(v)) {
                              final p = v.split('-');
                              final birth = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                              final today = DateTime.now();
                              int age = today.year - birth.year;
                              if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) age--;
                              _ageController.text = age.toString();
                            }
                          },
                          validator: (v) {
                            if (v!.isEmpty) return 'Required';
                            if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(v)) return 'Use dd-MM-yyyy';
                            return null;
                          }),
                      _editField(_ageController, 'Age', Icons.calendar_today_outlined,
                          type: TextInputType.number,
                          validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid age' : null),
                      const SizedBox(height: 4),
                      _editDropdown(value: _selectedGender, label: 'Gender', icon: Icons.wc_rounded,
                          items: const ['Male', 'Female', 'Other'],
                          onChanged: (v) => setS(() => _selectedGender = v)),
                      _editDropdown(value: _selectedBloodGroup, label: 'Blood Group', icon: Icons.bloodtype_outlined,
                          items: const ['N/A', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
                          onChanged: (v) => setS(() => _selectedBloodGroup = v)),
                      _editDropdown(value: _selectedStatus, label: 'Status', icon: Icons.mosque_rounded,
                          items: const ['Zakat', 'Non-Zakat', 'GMWF'],
                          onChanged: (v) => setS(() => _selectedStatus = v)),
                    ]),
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: const BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                  border: Border(top: BorderSide(color: _divider)),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _divider)),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: _inkMid, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () async => _savePatient(ctx, editKey, isAdult),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _savePatient(BuildContext ctx, GlobalKey<FormState> key, bool isAdult) async {
    if (!key.currentState!.validate()) return;
    final updates = <String, dynamic>{
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'gender': _selectedGender,
      'bloodGroup': _selectedBloodGroup ?? 'N/A',
      'status': _selectedStatus ?? 'Zakat',
      'age': int.tryParse(_ageController.text) ?? 0,
      'isAdult': (int.tryParse(_ageController.text) ?? 0) >= 18,
    };
    if (updates['isAdult'] == true) {
      updates['cnic'] = _cnicController.text.trim();
      updates['guardianCnic'] = null;
    } else {
      updates['guardianCnic'] = _guardianCnicController.text.trim();
      updates['cnic'] = null;
    }
    if (_dobController.text.isNotEmpty) {
      final p = _dobController.text.split('-');
      updates['dob'] = Timestamp.fromDate(DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])));
    }
    try {
      await _firestore.collection('branches').doc(widget.branchId.toLowerCase())
          .collection('patients').doc(widget.patientId).update(updates);
      _snack('Patient updated successfully!', success: true);
      if (mounted) Navigator.pop(ctx);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _addPrescription() async {
    final note = _noteController.text.trim();
    final medicine = _medicineController.text.trim();
    if (note.isEmpty && medicine.isEmpty) { _snack('Enter note or medicine', error: true); return; }

    final data = {
      'timestamp': FieldValue.serverTimestamp(),
      'doctorId': widget.doctorId,
      'note': note,
      'medicines': medicine.isNotEmpty ? [{'name': medicine, 'quantity': 1}] : [],
    };

    try {
      if (widget.isOnline) {
        await _firestore.collection('branches').doc(widget.branchId.toLowerCase())
            .collection('prescriptions').doc(widget.patientId).collection('prescriptions').add(data);
        _snack('Prescription added', success: true);
      } else {
        final pending = widget.localBox.get('pendingPrescriptions', defaultValue: []) as List;
        pending.add({'branchId': widget.branchId.toLowerCase(), 'patientId': widget.patientId, 'data': data});
        await widget.localBox.put('pendingPrescriptions', pending);
        _snack('Saved offline');
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    } finally {
      _noteController.clear();
      _medicineController.clear();
    }
  }

  void _deletePatient() async {
    if (!await _checkPassword()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.delete_forever_rounded, color: Colors.red.shade600, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('Delete Patient?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 8),
              const Text('This action cannot be undone.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: _inkMid)),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _divider)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: _inkMid, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _firestore.collection('branches').doc(widget.branchId.toLowerCase())
          .collection('patients').doc(widget.patientId).delete();
      _snack('Patient deleted', success: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false, bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : success ? Icons.check_circle_outline : Icons.info_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: error ? const Color(0xFFB00020) : success ? const Color(0xFF2E7D32) : const Color(0xFF37474F),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _patientStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              const Text('Error loading patient', style: TextStyle(fontWeight: FontWeight.w600, color: _inkMid)),
            ]));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _primary));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.person_off_outlined, size: 48, color: _inkLight),
              const SizedBox(height: 12),
              const Text('Patient not found', style: TextStyle(fontWeight: FontWeight.w600, color: _inkMid)),
            ]));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          return FadeTransition(
            opacity: _fadeAnim,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                return isWide ? _wideLayout(data) : _narrowLayout(data);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _wideLayout(Map<String, dynamic> data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: info
        SizedBox(
          width: 340,
          child: CustomScrollView(
            slivers: [
              _buildSliverAppBar(data),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(delegate: SliverChildListDelegate(_buildInfoWidgets(data))),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: _divider),
        // Right: history
        Expanded(child: _buildHistoryPanel(data)),
      ],
    );
  }

  Widget _narrowLayout(Map<String, dynamic> data) {
    return CustomScrollView(
      slivers: [
        _buildSliverAppBar(data),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              ..._buildInfoWidgets(data),
              const SizedBox(height: 16),
              _buildHistoryPanel(data),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryPanel(Map<String, dynamic> data) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _divider))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _light, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.history_rounded, color: _primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Visit History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            ]),
          ),
          if (!widget.isAdmin)
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildPrescriptionForm(),
            ),
          Expanded(
            child: PatientHistory(
              patientCnic: widget.patientId,
              branchId: widget.branchId,
              onRepeatLast: (visit) {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _light.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.note_add_rounded, color: _primary, size: 18),
            const SizedBox(width: 8),
            const Text('Add Prescription', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
          ]),
          const SizedBox(height: 12),
          _prescField(_noteController, 'Note / Diagnosis', Icons.description_outlined, maxLines: 2),
          const SizedBox(height: 10),
          _prescField(_medicineController, 'Medicine', Icons.medication_outlined),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save Prescription', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _addPrescription,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _prescField(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _inkLight, fontSize: 13),
        prefixIcon: Icon(icon, color: _inkLight, size: 20),
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 2)),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(Map<String, dynamic> data) {
    final name = data['name'] ?? 'Patient';
    final age = data['age']?.toString() ?? '?';
    final gender = data['gender'] ?? 'N/A';
    final status = data['status'] as String? ?? '';
    final statusColor = _statusColors[status] ?? _primary;

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: widget.isAdmin ? [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
          ),
          onPressed: () => _patientStream().first.then((s) {
            if (s.exists) _showEditDialog(s.data() as Map<String, dynamic>);
          }),
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white),
          ),
          onPressed: _deletePatient,
        ),
        const SizedBox(width: 8),
      ] : null,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF004D40), Color(0xFF00796B), Color(0xFF26A69A)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 2.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.trim().isEmpty ? '?' : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$gender · $age yrs',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          if (status.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(status,
                                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                        ]),
                        const SizedBox(height: 6),
                        Text(branchName ?? widget.branchId,
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInfoWidgets(Map<String, dynamic> data) {
    final isAdult = data['isAdult'] == true;
    final dobString = data['dob'] is Timestamp
        ? DateFormat('dd MMM yyyy').format((data['dob'] as Timestamp).toDate())
        : 'N/A';
    final joined = data['createdAt'] is Timestamp
        ? DateFormat('dd MMM yyyy').format((data['createdAt'] as Timestamp).toDate())
        : 'N/A';

    return [
      const SizedBox(height: 4),
      _card('Patient Info', Icons.person_outline_rounded, const Color(0xFF00796B), [
        _infoRow('Patient ID', widget.patientId, Icons.fingerprint_rounded),
        _infoRow('Date of Birth', dobString, Icons.cake_outlined),
        _infoRow('Blood Group', data['bloodGroup'] ?? 'N/A', Icons.bloodtype_outlined),
        _infoRow('Status', data['status'] ?? 'N/A', Icons.mosque_rounded),
        _infoRow('Phone', data['phone'] ?? 'N/A', Icons.phone_outlined),
        if (isAdult) _infoRow('CNIC', data['cnic'] ?? 'N/A', Icons.credit_card_outlined)
        else _infoRow('Guardian CNIC', data['guardianCnic'] ?? 'N/A', Icons.credit_card_outlined),
        _infoRow('Branch', branchName ?? widget.branchId, Icons.location_on_outlined),
        _infoRow('Joined', joined, Icons.calendar_today_outlined),
      ]),
      const SizedBox(height: 14),
      _buildFamilySection(data),
    ];
  }

  Widget _buildFamilySection(Map<String, dynamic> data) {
    final isAdult = data['isAdult'] == true;
    if (isAdult) {
      return StreamBuilder<QuerySnapshot>(
        stream: _childrenStream(data['cnic']),
        builder: (ctx, snap) {
          if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
          return _card('Family Members', Icons.family_restroom_rounded, const Color(0xFF1565C0),
            snap.data!.docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return _infoRow('${d['name'] ?? 'N/A'} (${d['age'] ?? '?'} yrs)',
                  '${d['gender'] ?? 'N/A'}', Icons.person_outline_rounded);
            }).toList());
        },
      );
    } else {
      return FutureBuilder<DocumentSnapshot?>(
        future: _getGuardian(data['guardianCnic']),
        builder: (ctx, snap) {
          if (!snap.hasData || snap.data == null) {
            return _card('Guardian', Icons.person_outlined, const Color(0xFF6A1B9A), [
              _infoRow('Status', 'Ungrouped Child', Icons.info_outline_rounded),
            ]);
          }
          final gd = snap.data!.data() as Map<String, dynamic>;
          return _card('Guardian', Icons.person_outlined, const Color(0xFF6A1B9A), [
            _infoRow('Name', gd['name'] ?? 'N/A', Icons.person_outline_rounded),
            _infoRow('Age', '${gd['age'] ?? '?'} yrs', Icons.calendar_today_outlined),
            _infoRow('Gender', gd['gender'] ?? 'N/A', Icons.wc_rounded),
          ]);
        },
      );
    }
  }

  Widget _card(String title, IconData icon, Color accent, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accent.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            ]),
          ),
          const Divider(height: 1, color: _divider),
          Padding(padding: const EdgeInsets.all(16), child: Column(children: children)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _inkLight),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13, color: _inkMid, fontWeight: FontWeight.w500))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: _ink, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ── Edit form helpers ─────────────────────────────────────────

  Widget _editField(TextEditingController ctrl, String label, IconData icon, {
    TextInputType? type, List<TextInputFormatter>? formatters, int? maxLen, int maxLines = 1,
    String? Function(String?)? validator, ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        inputFormatters: formatters,
        maxLength: maxLen,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: _ink),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: _inkLight),
          floatingLabelStyle: const TextStyle(fontSize: 12, color: _primary, fontWeight: FontWeight.w600),
          prefixIcon: Icon(icon, color: _inkLight, size: 20),
          filled: true,
          fillColor: _surface,
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 2)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400)),
          errorStyle: const TextStyle(fontSize: 11),
        ),
        validator: validator,
      ),
    );
  }

  Widget _editDropdown({required String? value, required String label, required IconData icon,
      required List<String> items, required Function(String?) onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        hint: Text(label, style: const TextStyle(color: _inkLight, fontSize: 13)),
        isExpanded: true,
        dropdownColor: _surface,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _inkLight),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _inkLight, size: 20),
          filled: true,
          fillColor: _surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 2)),
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, color: _ink)))).toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'Select $label' : null,
      ),
    );
  }
}

// ─── Formatters ───────────────────────────────────────────────────────────────
class CNICInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if ((i == 4 || i == 11) && i != digits.length - 1) buffer.write('-');
    }
    return TextEditingValue(text: buffer.toString(), selection: TextSelection.collapsed(offset: buffer.length));
  }
}

class _DobFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue newVal) {
    var t = newVal.text.replaceAll(RegExp(r'\D'), '');
    if (t.length > 8) t = t.substring(0, 8);
    final b = StringBuffer();
    for (int i = 0; i < t.length; i++) {
      if (i == 2 || i == 4) b.write('-');
      b.write(t[i]);
    }
    return TextEditingValue(text: b.toString(), selection: TextSelection.collapsed(offset: b.length));
  }
}