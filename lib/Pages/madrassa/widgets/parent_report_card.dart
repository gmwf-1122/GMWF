// lib/pages/madrassa/widgets/parent_report_card.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/madrassa_config.dart';
import '../models/madrassa_fee_logic.dart';
import '../widgets/madrassa_common_widgets.dart';
import '../utils/madrassa_report_helper.dart';

class ParentReportCard extends StatelessWidget {
  final String branchId;
  final String studentId;
  final Map<String, dynamic> studentData;
  final int? year;
  final int? month;
  final VoidCallback? onLogout;

  const ParentReportCard({
    super.key,
    required this.branchId,
    required this.studentId,
    required this.studentData,
    this.year,
    this.month,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('madrassa_daily_logs')
          .snapshots(),
      builder: (context, logSnap) {
        if (logSnap.hasError) return _ErrorView('Logs Error: ${logSnap.error}');
        
        return StreamBuilder<MadrassaConfig>(
          stream: FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .collection('madrassa_config')
              .doc('current')
              .snapshots()
              .map((s) => MadrassaConfig.fromFirestore(s)),
          builder: (context, configSnap) {
            if (configSnap.hasError) return _ErrorView('Config Error: ${configSnap.error}');
            
            if (logSnap.connectionState == ConnectionState.waiting ||
                configSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFFF8F9FD),
                body: Center(child: CircularProgressIndicator(color: Color(0xFF4C4DDC))),
              );
            }

            if (!logSnap.hasData || !configSnap.hasData) {
              return const _ErrorView('Waiting for data...');
            }

            final now = DateTime.now();
            final allLogs = logSnap.data?.docs ?? [];
            final config = configSnap.data ?? MadrassaConfig(id: 'current', year: now.year, month: now.month);
            final workingDays = MadrassaFeeLogic.getWorkingDaysCount(config.year, config.month);
            final monthKey = DateFormat('yyyy-MM').format(DateTime(config.year, config.month));
            final monthLogs = allLogs.where((l) => l.id.startsWith(monthKey)).toList();

            final fee = MadrassaFeeLogic.calculateStudentFee(
              studentId: studentId,
              studentData: studentData,
              logs: monthLogs,
              config: config,
              totalWorkingDays: workingDays,
            );

            final sortedLogs = [...monthLogs]..sort((a, b) => b.id.compareTo(a.id));
            int currentTotalLines = int.tryParse(studentData['currentLines']?.toString() ?? '0') ?? 0;

            String todayGain = '0';
            int monthGain = 0;

            if (sortedLogs.isNotEmpty) {
              final latestMap = (sortedLogs.first.data() as Map<String, dynamic>)[studentId] as Map<String, dynamic>?;
              final firstMap = (sortedLogs.last.data() as Map<String, dynamic>)[studentId] as Map<String, dynamic>?;
              if (latestMap != null && firstMap != null) {
                monthGain = (latestMap['currentLines'] ?? currentTotalLines) - (firstMap['currentLines'] ?? 0);
              }
              final latestTotal = (latestMap?['currentLines'] as int?) ?? currentTotalLines;
              if (sortedLogs.length > 1) {
                final prevMap = (sortedLogs[1].data() as Map<String, dynamic>)[studentId] as Map<String, dynamic>?;
                todayGain = '${latestTotal - ((prevMap?['currentLines'] as int?) ?? latestTotal)}';
              }
            }

            final todayStr = DateFormat('yyyy-MM-dd').format(now);
            Map<String, dynamic> todaySLog = {};
            try {
              final todayDoc = allLogs.firstWhere((l) => l.id == todayStr);
              final tData = todayDoc.data() as Map<String, dynamic>?;
              todaySLog = (tData?[studentId] is Map ? tData![studentId] as Map<String, dynamic> : {});
            } catch (_) {}
            final currentStatus = todaySLog['attendance']?.toString() ?? 'unknown';

            final ptmDate = config.getPtmDate();
            final isPtmToday = now.year == ptmDate.year && now.month == ptmDate.month && now.day == ptmDate.day;
            final needsReply = todaySLog['parentReplied'] != true && currentStatus == 'present';
            final leaveStatus = todaySLog['leaveStatus'] ?? 'pending';

            return Scaffold(
              backgroundColor: const Color(0xFFF8F9FD),
              body: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 220,
                    pinned: true,
                    backgroundColor: const Color(0xFF008080), // Teal
                    elevation: 0,
                    iconTheme: const IconThemeData(color: Colors.white),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF008080), Color(0xFF00A86B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: -50,
                              right: -50,
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.15),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: -20,
                              left: 30,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.1),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 20,
                              left: -10,
                              child: Transform.rotate(
                                angle: 0.5,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Colors.white.withValues(alpha: 0.05),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 70,
                                        height: 70,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                                        ),
                                        child: Center(
                                          child: Text(
                                            studentData['name']?[0] ?? '?',
                                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF4C4DDC)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(studentData['name'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                                            Text('Roll: ${studentData['rollNumber'] ?? '?' } • Class: ${studentData['class'] ?? 'Hifz'}', 
                                                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.white), onPressed: onLogout),
                    ],
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isPtmToday || needsReply || (currentStatus == 'absent' && leaveStatus == 'denied'))
                            _buildReminders(isPtmToday, needsReply, leaveStatus),
                          
                          _MonthBanner(year: config.year, month: config.month),
                          
                          if (config.auditLog.any((l) => l['type'] == 'ptm_reschedule' && l['month'] == config.month && l['year'] == config.year)) ...[
                            const SizedBox(height: 32),
                            const _SectionTitle(label: 'Recent Notices', icon: Icons.campaign_rounded),
                            const SizedBox(height: 12),
                            ...config.auditLog.where((l) => l['type'] == 'ptm_reschedule' && l['month'] == config.month && l['year'] == config.year).map((log) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.amber.shade200),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.event_repeat_rounded, color: Colors.amber),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'PTM Rescheduled: ${log['oldValue']} → ${log['newValue']}',
                                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                          ),
                                          const Text(
                                            'Parent Teacher Meeting date has been updated.',
                                            style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],

                          const SizedBox(height: 32),
                          Row(
                            children: [
                              const _SectionTitle(label: 'Actions', icon: Icons.bolt_rounded),
                              const Spacer(),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ExportButton(
                                    onExcel: () {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing your Excel report...')));
                                      MadrassaReportHelper.exportIndividualExcel(
                                        config: config,
                                        studentId: studentId,
                                        studentData: studentData,
                                        logs: monthLogs,
                                      );
                                    }, 
                                    onPdf: () {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing your report...')));
                                      MadrassaReportHelper.exportIndividualPdf(
                                        config: config,
                                        studentId: studentId,
                                        studentData: studentData,
                                        logs: monthLogs,
                                      );
                                    },
                                    isSmall: true,
                                  ),
                                  const SizedBox(height: 2),
                                  const Text('Saved in Downloads folder', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _ActionButton(
                            label: currentStatus == 'leave_requested' ? 'Leave Requested' : (currentStatus == 'leave' ? 'On Leave' : 'Request Leave'),
                            icon: Icons.email_outlined,
                            color: const Color(0xFF4C4DDC),
                            isSelected: currentStatus == 'leave_requested' || currentStatus == 'leave',
                            isActive: currentStatus != 'leave_requested' && currentStatus != 'leave',
                            onTap: () => _showLeaveReasonDialog(context, branchId, todayStr, studentId),
                          ),



                          const SizedBox(height: 32),
                          const _SectionTitle(label: 'Attendance', icon: Icons.calendar_month),
                          const SizedBox(height: 12),
                          const _CalendarLegend(),
                          const SizedBox(height: 16),
                          _AttendanceCalendar(studentId: studentId, logs: allLogs, year: config.year, month: config.month, config: config),

                          const SizedBox(height: 32),
                          const _SectionTitle(label: 'Fees & Savings', icon: Icons.account_balance_wallet),
                          const SizedBox(height: 12),
                          _PenaltyCard(due: fee['amountDue'], att: fee['attSavings'], uni: fee['uniSavings'], msg: fee['msgSavings'], ptm: fee['ptmSavings']),
                          
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReminders(bool isPtm, bool needsReply, String leaveStatus) {
    return Column(
      children: [
        if (isPtm) _reminderItem('PTM Today', 'Today is the Parent Teacher Meeting. Please visit the Madrassa.', Icons.people, Colors.orange),
        if (needsReply) _reminderItem('Reply Needed', 'Please reply to the teacher\'s message regarding today\'s status.', Icons.message, Colors.purple),
        if (leaveStatus == 'denied') _reminderItem('Leave Denied', 'Your leave request for ${studentData['name'] ?? 'the student'} was denied. They are marked absent.', Icons.error_outline, Colors.red),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _reminderItem(String en, String body, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(en, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text(body, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLeaveReasonDialog(BuildContext context, String branchId, String todayStr, String studentId) async {
    final TextEditingController reasonController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Request Leave'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(hintText: 'Enter reason here...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('branches').doc(branchId).collection('madrassa_daily_logs').doc(todayStr).set({
                studentId: { 'attendance': 'leave_requested', 'isParentRequested': true, 'leaveReason': reasonController.text, 'leaveStatus': 'pending', 'timestamp': FieldValue.serverTimestamp() }
              }, SetOptions(merge: true));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C4DDC), foregroundColor: Colors.white),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView(this.message);
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(message, style: const TextStyle(color: Colors.red))));
}

class _MonthBanner extends StatelessWidget {
  final int year, month;
  const _MonthBanner({required this.year, required this.month});
  @override
  Widget build(BuildContext context) {
    final date = DateTime(year, month);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF4C4DDC).withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF4C4DDC).withValues(alpha: 0.1))),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: Color(0xFF4C4DDC)),
          const SizedBox(width: 12),
          Text(DateFormat('MMMM yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4C4DDC))),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionTitle({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF4C4DDC)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  const _StatTile({required this.label, required this.value, required this.sub, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(sub, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _OverallProgressCard extends StatelessWidget {
  final int currentLines;
  const _OverallProgressCard({required this.currentLines});
  @override
  Widget build(BuildContext context) {
    const total = 9072;
    final pct = (currentLines / total * 100).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Overall Progress', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('$pct%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4C4DDC))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: currentLines / total, minHeight: 8, backgroundColor: const Color(0xFFF1F4F9), color: const Color(0xFF4C4DDC)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Line $currentLines of $total', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isActive, isSelected;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.isActive, required this.isSelected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isActive ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color : (isActive ? color.withValues(alpha: 0.1) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : (isActive ? color.withValues(alpha: 0.2) : Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : (isActive ? color : Colors.grey)),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (isActive ? color : Colors.grey))),
          ],
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();
  @override
  Widget build(BuildContext context) {
    final items = [
      (const Color(0xFFE8F5E9), 'Present'),
      (const Color(0xFFFFEBEE), 'Absent'),
      (const Color(0xFF4C4DDC), 'PTM Joining'),
      (const Color(0xFFFF5252), 'PTM Missed'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: items.map((t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: t.$1, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(t.$2, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      )).toList(),
    );
  }
}

class _AttendanceCalendar extends StatelessWidget {
  final String studentId;
  final List<QueryDocumentSnapshot> logs;
  final int year, month;
  final MadrassaConfig config;
  const _AttendanceCalendar({required this.studentId, required this.logs, required this.year, required this.month, required this.config});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = firstDay.weekday; 
    const dayHeaders = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final ptmDate = config.getPtmDate();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: dayHeaders.map((d) => Text(d, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))).toList()),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: daysInMonth + (firstWeekday - 1),
            itemBuilder: (context, index) {
              if (index < firstWeekday - 1) return const SizedBox();
              final day = index - (firstWeekday - 2);
              final date = DateTime(year, month, day);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              final isPtm = date.year == ptmDate.year && date.month == ptmDate.month && date.day == ptmDate.day;
              final isPast = date.isBefore(DateTime(now.year, now.month, now.day));
              final isToday = day == now.day && month == now.month && year == now.year;

              Map<String, dynamic>? statusData;
              try {
                final doc = logs.firstWhere((l) => l.id == dateStr);
                statusData = (doc.data() as Map<String, dynamic>)[studentId] as Map<String, dynamic>?;
              } catch (_) {}

              Color bg = const Color(0xFFF1F4F9);
              Color textCol = Colors.grey.shade400;
              bool ptmAttended = statusData?['ptm'] == true;

              if (statusData != null) {
                final att = statusData['attendance']?.toString();
                if (att == 'present') { bg = const Color(0xFFE8F5E9); textCol = const Color(0xFF2E7D32); }
                else if (att == 'leave' || att == 'leave_requested') { bg = const Color(0xFFFFF3E0); textCol = const Color(0xFFEF6C00); }
                else if (att == 'absent') { bg = const Color(0xFFFFEBEE); textCol = const Color(0xFFC62828); }
              }

              BoxDecoration decoration = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: isToday ? Border.all(color: const Color(0xFF4C4DDC), width: 2) : null);
              
              if (isPtm && !isPast) {
                return _PulsingPtmCell(day: day, textCol: isToday ? const Color(0xFF4C4DDC) : Colors.grey.shade600);
              }

              return Container(
                decoration: decoration,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('$day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textCol)),
                    if (isPtm && isPast)
                      Positioned(
                        bottom: 4,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(ptmAttended ? 'JOINED' : 'MISSED', style: TextStyle(fontSize: 5, fontWeight: FontWeight.w900, color: ptmAttended ? Colors.green : Colors.red)),
                            Container(width: 4, height: 4, decoration: BoxDecoration(color: ptmAttended ? Colors.green : Colors.red, shape: BoxShape.circle)),
                          ],
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
  }
}

class _PulsingPtmCell extends StatefulWidget {
  final int day;
  final Color textCol;
  const _PulsingPtmCell({required this.day, required this.textCol});
  @override
  State<_PulsingPtmCell> createState() => _PulsingPtmCellState();
}

class _PulsingPtmCellState extends State<_PulsingPtmCell> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4C4DDC).withOpacity(0.05 + (0.1 * _controller.value)),
                const Color(0xFF6B6CEE).withOpacity(0.1 + (0.2 * _controller.value)),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFF4C4DDC).withOpacity(0.2 + (0.4 * _controller.value)), width: 1 + _controller.value),
            boxShadow: [BoxShadow(color: const Color(0xFF4C4DDC).withOpacity(0.1 * _controller.value), blurRadius: 8, spreadRadius: 2)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${widget.day}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: widget.textCol)),
              const SizedBox(height: 2),
              const Text('PTM', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Color(0xFF4C4DDC))),
            ],
          ),
        );
      },
    );
  }
}

class _PenaltyCard extends StatelessWidget {
  final double due, att, uni, msg, ptm;
  const _PenaltyCard({required this.due, required this.att, required this.uni, required this.msg, required this.ptm});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total Due', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                Text('Current Month', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              Text('Rs. ${due.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFF43F5E))),
            ],
          ),
          const Divider(height: 32),
          _SavingsRow('Attendance Savings', att, Colors.green),
          _SavingsRow('Uniform Savings', uni, Colors.blue),
          _SavingsRow('Response Savings', msg, Colors.purple),
          _SavingsRow('PTM Meeting Savings', ptm, Colors.orange),
        ],
      ),
    );
  }
}

class _SavingsRow extends StatelessWidget {
  final String label; final double val; final Color color;
  const _SavingsRow(this.label, this.val, this.color);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)), Text('-Rs. ${val.toStringAsFixed(0)}', style: TextStyle(color: color, fontWeight: FontWeight.bold))]));
}
