import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../theme/role_theme_provider.dart';

class MadrassaConfigView extends StatefulWidget {
  final String branchId;
  const MadrassaConfigView({super.key, required this.branchId});

  @override
  State<MadrassaConfigView> createState() => _MadrassaConfigViewState();
}

class _MadrassaConfigViewState extends State<MadrassaConfigView> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  int _ptmDay = 0;
  
  final _baseFeeController = TextEditingController();
  final _ptmDeductionController = TextEditingController();
  final _msgDeductionController = TextEditingController();
  final _maxAttDeductionController = TextEditingController();
  final _maxUniDeductionController = TextEditingController();
  
  int _initialPtmDay = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _baseFeeController.dispose();
    _ptmDeductionController.dispose();
    _msgDeductionController.dispose();
    _maxAttDeductionController.dispose();
    _maxUniDeductionController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    final doc = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('madrassa_config')
        .doc('current')
        .get();
    if (doc.exists && mounted) {
      final data = doc.data()!;
      setState(() {
        _year = data['year'] ?? _year;
        _month = data['month'] ?? _month;
        _ptmDay = data['ptmDay'] ?? 0;
        _initialPtmDay = _ptmDay;
        _baseFeeController.text = (data['baseFee'] ?? 3000).toString();
        _ptmDeductionController.text = (data['ptmDeduction'] ?? 700).toString();
        _msgDeductionController.text = (data['messageTotalDeduction'] ?? 1300).toString();
        _maxAttDeductionController.text = (data['attendanceMaxDeduction'] ?? 500).toString();
        _maxUniDeductionController.text = (data['uniformMaxDeduction'] ?? 500).toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final base = double.tryParse(_baseFeeController.text) ?? 3000;
    final ptm = double.tryParse(_ptmDeductionController.text) ?? 700;
    final msg = double.tryParse(_msgDeductionController.text) ?? 1300;
    final att = double.tryParse(_maxAttDeductionController.text) ?? 500;
    final uni = double.tryParse(_maxUniDeductionController.text) ?? 500;

    if ((ptm + msg + att + uni) != base) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Sum of deductions ($ptm + $msg + $att + $uni = ${ptm + msg + att + uni}) must equal Base Points ($base)'),
          ),
        );
      }
      return;
    }

    try {
      final Map<String, dynamic> updateData = {
        'year': _year,
        'month': _month,
        'ptmDay': _ptmDay,
        'baseFee': base,
        'ptmDeduction': ptm,
        'messageTotalDeduction': msg,
        'attendanceMaxDeduction': att,
        'uniformMaxDeduction': uni,
      };

      if (_ptmDay != _initialPtmDay) {
        final oldDate = _initialPtmDay == 0 ? 'Auto (1st Fri)' : 'Day $_initialPtmDay';
        final newDate = _ptmDay == 0 ? 'Auto (1st Fri)' : 'Day $_ptmDay';
        
        updateData['auditLog'] = FieldValue.arrayUnion([
          {
            'type': 'ptm_reschedule',
            'oldValue': oldDate,
            'newValue': newDate,
            'timestamp': Timestamp.now(),
            'month': _month,
            'year': _year,
          }
        ]);
        _initialPtmDay = _ptmDay;
      }

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_config')
          .doc('current')
          .set(updateData, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Config saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuration',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Color(0xFF1A1C1E)),
            ),
            const Text(
              'Set the active month and deduction parameters',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _configCard(
                    title: 'Active Period',
                    subtitle: 'All reports and logs use this month',
                    child: Column(
                      children: [
                        _dropdownField('Year', _year, List.generate(5, (i) => 2024 + i), (v) => setState(() => _year = v!)),
                        const SizedBox(height: 16),
                        _dropdownField('Month', _month, List.generate(12, (i) => i + 1), (v) => setState(() => _month = v!), isMonth: true),
                        const SizedBox(height: 16),
                        _dropdownField('PTM Day (Specific Date)', _ptmDay, List.generate(32, (i) => i), (v) => setState(() => _ptmDay = v!), isPtmDay: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _configCard(
                    title: 'Deduction Parameters',
                    subtitle: 'All values are in points (deducted from base)',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _textField('Base Points', _baseFeeController)),
                            const SizedBox(width: 16),
                            Expanded(child: _textField('PTM Deduction', _ptmDeductionController)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _textField('Message Deduction (fixed total — if ANY message day)', _msgDeductionController),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _textField('Max Attendance Deduction', _maxAttDeductionController)),
                            const SizedBox(width: 16),
                            Expanded(child: _textField('Max Uniform Deduction', _maxUniDeductionController)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008080), // Teal
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _configCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E2E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A1C1E))),
          Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF44474E))),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD0D3D9))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD0D3D9))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4C4DDC), width: 2)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(String label, int value, List<int> items, ValueChanged<int?> onChanged, {bool isMonth = false, bool isPtmDay = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF44474E))),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: value,
          items: items.map((i) {
            String text = '$i';
            if (isMonth) text = DateFormat('MMMM').format(DateTime(2024, i));
            if (isPtmDay) text = i == 0 ? 'Auto (1st Friday)' : 'Day $i';
            return DropdownMenuItem(value: i, child: Text(text));
          }).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD0D3D9))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD0D3D9))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4C4DDC), width: 2)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
