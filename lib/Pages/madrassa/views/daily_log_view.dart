import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/madrassa_config.dart';
import '../models/madrassa_fee_logic.dart';

class DailyLogView extends StatefulWidget {
  final String branchId;
  final String editorName;
  const DailyLogView({super.key, required this.branchId, this.editorName = 'Unknown'});

  @override
  State<DailyLogView> createState() => _DailyLogViewState();
}

class _DailyLogViewState extends State<DailyLogView> {
  DateTime _selectedDate = DateTime.now();
  Map<String, Map<String, dynamic>> _localChanges = {};
  bool _isSaving = false;
  final Map<String, TextEditingController> _lineControllers = {};

  @override
  void dispose() {
    for (var c in _lineControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_localChanges.isEmpty) return;
    setState(() => _isSaving = true);
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final auditMetadata = {
        'lastEditedBy': widget.editorName,
        'lastEditedAt': FieldValue.serverTimestamp(),
      };
      
      final Map<String, dynamic> finalUpdate = {};
      _localChanges.forEach((sId, data) {
        finalUpdate[sId] = {...data, ...auditMetadata};
      });

      final docRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_daily_logs')
          .doc(dateKey);

      await docRef.set(finalUpdate, SetOptions(merge: true));
      setState(() {
        _localChanges = {};
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved successfully')),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  TextEditingController _getController(String sId, String initial) {
    if (!_lineControllers.containsKey(sId)) {
      _lineControllers[sId] = TextEditingController(text: initial);
    }
    return _lineControllers[sId]!;
  }

  void _updateLocal(String sId, String key, dynamic value) {
    setState(() {
      _localChanges.putIfAbsent(sId, () => {})[key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return StreamBuilder<MadrassaConfig>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('madrassa_config')
          .doc('current')
          .snapshots()
          .map((s) => MadrassaConfig.fromFirestore(s)),
      builder: (context, configSnap) {
        final config = configSnap.data ?? MadrassaConfig(id: 'current', year: _selectedDate.year, month: _selectedDate.month);
        final ptmDate = config.getPtmDate();
        final isPtmDay = _selectedDate.year == ptmDate.year && _selectedDate.month == ptmDate.month && _selectedDate.day == ptmDate.day;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FD),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(config),
              _buildHorizontalCalendar(config),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('branches')
                      .doc(widget.branchId)
                      .collection('madrassa_students')
                      .where('status', isEqualTo: 'active')
                      .snapshots(),
                  builder: (context, studentSnap) {
                    if (!studentSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final students = studentSnap.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final joinDate = (data['joinDate'] as Timestamp?)?.toDate();
                      if (joinDate == null) return true;
                      final joinDay = DateTime(joinDate.year, joinDate.month, joinDate.day);
                      final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
                      return !selectedDay.isBefore(joinDay);
                    }).toList()
                      ..sort((a, b) => (a['rollNumber'] ?? '').compareTo(b['rollNumber'] ?? ''));

                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('branches')
                          .doc(widget.branchId)
                          .collection('madrassa_daily_logs')
                          .doc(dateKey)
                          .snapshots(),
                      builder: (context, logSnap) {
                        final logData = logSnap.data?.data() as Map<String, dynamic>? ?? {};

                        return Column(
                          children: [
                            _buildStatusLegend(students, logData),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                itemCount: students.length,
                                itemBuilder: (context, i) {
                                  final s = students[i];
                                  final sLog = _localChanges[s.id] ?? logData[s.id] as Map<String, dynamic>? ?? {};
                                  return _buildStudentItem(s, sLog, isPtmDay);
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              if (_localChanges.isNotEmpty) _buildSaveFab(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(MadrassaConfig config) {
    final ptmDate = config.getPtmDate();
    final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('MMMM yyyy').format(_selectedDate)} — Daily Log',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Color(0xFF1A1C1E)),
          ),
          const SizedBox(height: 4),
          Text(
            '$workingDays working days • Sundays excluded • PTM: ${DateFormat('EEE, MMM d').format(ptmDate)}',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCalendar(MadrassaConfig config) {
    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final ptmDate = config.getPtmDate();
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: daysInMonth,
        itemBuilder: (context, i) {
          final date = DateTime(_selectedDate.year, _selectedDate.month, i + 1);
          final isSelected = date.day == _selectedDate.day;
          final isSunday = date.weekday == DateTime.sunday;
          final isPtm = date.year == ptmDate.year && date.month == ptmDate.month && date.day == ptmDate.day;

          return GestureDetector(
            onTap: isSunday ? null : () => setState(() => _selectedDate = date),
            child: Opacity(
              opacity: isSunday ? 0.3 : 1.0,
              child: Container(
                width: 60,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF4C4DDC) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? const Color(0xFF4C4DDC) : const Color(0xFFE0E2E7)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('E').format(date).toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white70 : Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${date.day}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF1A1C1E)),
                    ),
                    if (isPtm)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'PTM',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : const Color(0xFFD32F2F)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusLegend(List<QueryDocumentSnapshot> students, Map<String, dynamic> logData) {
    int present = 0, leave = 0, absent = 0, replied = 0;
    for (var s in students) {
      final log = logData[s.id] as Map<String, dynamic>? ?? {};
      final att = log['attendance'] ?? 'absent';
      if (att == 'present') {
        present++;
      } else if (att == 'leave') leave++;
      else absent++;
      if (log['parentReplied'] == true) replied++;
    }

    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              _statText('P: $present', const Color(0xFF2E7D32)),
              const SizedBox(width: 12),
              _statText('L: $leave', const Color(0xFFED6C02)),
              const SizedBox(width: 12),
              _statText('A: $absent', const Color(0xFFD32F2F)),
              const SizedBox(width: 12),
              _statText('Replied: $replied', const Color(0xFFED6C02)),
            ],
          ),
          if (isToday) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _efficiencyButton('All Present', Icons.done_all, const Color(0xFF2E7D32), () {
                  for (var s in students) {
                    final log = logData[s.id] as Map<String, dynamic>? ?? {};
                    if (log['attendance'] != 'leave') {
                      _updateLocal(s.id, 'attendance', 'present');
                    }
                  }
                }),
                const SizedBox(width: 8),
                _efficiencyButton('All Replied', Icons.message_outlined, const Color(0xFFED6C02), () {
                  for (var s in students) {
                    _updateLocal(s.id, 'parentReplied', true);
                  }
                }),
                const SizedBox(width: 8),
                _efficiencyButton('All Uniform', Icons.check_circle_outline, const Color(0xFF4C4DDC), () {
                  for (var s in students) {
                    _updateLocal(s.id, 'uniform', true);
                  }
                }),
                const Spacer(),
                _legendItem('P = Present', const Color(0xFF2E7D32)),
                _legendItem('L = Leave', const Color(0xFFED6C02)),
                _legendItem('A = Absent', const Color(0xFFD32F2F)),
              ],
            ),
          ] else ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                _legendItem('P = Present', const Color(0xFF2E7D32)),
                _legendItem('L = Leave', const Color(0xFFED6C02)),
                _legendItem('A = Absent', const Color(0xFFD32F2F)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _efficiencyButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _statText(String label, Color color) {
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14));
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStudentItem(QueryDocumentSnapshot s, Map<String, dynamic> log, bool isPtmDay) {
    final data = s.data() as Map<String, dynamic>;
    final sId = s.id;
    final att = log['attendance'] ?? 'absent';
    final uni = log['uniform'] ?? false;
    final msg = log['parentReplied'] ?? false;
    final isParentRequested = log['isParentRequested'] == true;
    final leaveStatus = log['leaveStatus'] ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E2E7)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text('${data['rollNumber'] ?? '?'}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: Color(0xFFF0F2F5), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(data['name']?[0] ?? '?', style: const TextStyle(color: Color(0xFF008080), fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (isParentRequested && leaveStatus == 'pending')
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                        child: Text('Parent requested a leave: ${log['leaveReason'] ?? "No reason"}', style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              
              if (isParentRequested && leaveStatus == 'pending')
                Row(
                  children: [
                    _actionButton('Approve', Colors.green, () {
                      _updateLocal(sId, 'attendance', 'leave');
                      _updateLocal(sId, 'leaveStatus', 'approved');
                    }),
                    const SizedBox(width: 8),
                    _actionButton('Deny', Colors.red, () {
                      _updateLocal(sId, 'attendance', 'absent');
                      _updateLocal(sId, 'leaveStatus', 'denied');
                    }),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Attendance', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _attButton('P', att == 'present', const Color(0xFF2E7D32), () => _updateLocal(sId, 'attendance', 'present')),
                        const SizedBox(width: 4),
                        _attButton('L', att == 'leave', const Color(0xFFED6C02), () => _updateLocal(sId, 'attendance', 'leave')),
                        const SizedBox(width: 4),
                        _attButton('A', att == 'absent', const Color(0xFFD32F2F), () => _updateLocal(sId, 'attendance', 'absent')),
                      ],
                    ),
                  ],
                ),
              const SizedBox(width: 24),
              _switchCol('Uniform', uni, (v) => _updateLocal(sId, 'uniform', v)),
              const SizedBox(width: 24),
              _switchCol('Replied', msg, (v) => _updateLocal(sId, 'parentReplied', v)),

              if (isPtmDay) ...[
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('PTM', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _attButton('J', log['ptm'] == true, const Color(0xFF2E7D32), () => _updateLocal(sId, 'ptm', true)),
                        const SizedBox(width: 4),
                        _attButton('M', log['ptm'] == false, const Color(0xFFD32F2F), () => _updateLocal(sId, 'ptm', false)),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _attButton(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? color : const Color(0xFFF0F2F5),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _switchCol(String label, bool val, ValueChanged<bool> onChanged) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Switch(
          value: val,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF008080), // Teal
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildSaveFab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveChanges,
          icon: const Icon(Icons.check),
          label: const Text('Saved'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF008080), // Teal
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}
