import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/madrassa_config.dart';

class MadrassaOverviewView extends StatelessWidget {
  final String branchId;
  final Function(int)? onAction;
  const MadrassaOverviewView({super.key, required this.branchId, this.onAction});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('branches').doc(branchId).collection('madrassa_config').doc('current').snapshots(),
      builder: (context, configSnap) {
        final config = configSnap.hasData ? MadrassaConfig.fromFirestore(configSnap.data!) : MadrassaConfig(id: 'current', year: DateTime.now().year, month: DateTime.now().month);
        
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('branches').doc(branchId).collection('madrassa_students').where('status', isEqualTo: 'active').snapshots(),
          builder: (context, studentSnap) {
            final activeStudents = studentSnap.data?.docs.length ?? 0;
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeHeader(context),
                  const SizedBox(height: 32),
                  _buildStatGrid(context, activeStudents, config),
                  const SizedBox(height: 32),
                  _buildQuickActions(context),
                  const SizedBox(height: 32),
                  _buildRecentActivity(context),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWelcomeHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Madrassa Dashboard',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
        ),
        const SizedBox(height: 4),
        Text(
          'Overview of academic and behavioral operations',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildStatGrid(BuildContext context, int students, MadrassaConfig config) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.5,
          children: [
            _statCard('Total Students', '$students', Icons.people_alt_rounded, Colors.blue),
            _statCard('Today\'s Log', 'Pending', Icons.edit_calendar_rounded, Colors.orange),
            _statCard('Next PTM', DateFormat('MMM d').format(config.getPtmDate()), Icons.event_available_rounded, Colors.red),
            _statCard('Base Fee', 'Rs. ${config.baseFee.toInt()}', Icons.account_balance_wallet_rounded, Colors.green),
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const Icon(Icons.trending_up, color: Colors.green, size: 16),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E))),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Operations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _quickActionBtn(context, 'Take Attendance', Icons.checklist_rounded, Colors.indigo, () => onAction?.call(1)),
            _quickActionBtn(context, 'Monthly Report', Icons.analytics_rounded, Colors.teal, () => onAction?.call(3)),
            _quickActionBtn(context, 'Configure Fees', Icons.settings_suggest_rounded, Colors.blueGrey, () => onAction?.call(4)),
          ],
        ),
      ],
    );
  }

  Widget _quickActionBtn(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Academic Notices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Icon(Icons.more_horiz, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 16),
          _activityItem('System', 'Monthly report for April is now ready for review.', '2 hours ago', Icons.info_outline, Colors.blue),
          _activityItem('Principal', 'PTM date has been rescheduled to Friday, May 15.', 'Yesterday', Icons.notification_important_rounded, Colors.red),
          _activityItem('Finance', 'Base fee updated to Rs. 1000 from current month.', '2 days ago', Icons.payments_rounded, Colors.green),
        ],
      ),
    );
  }

  Widget _activityItem(String user, String text, String time, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(user, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(time, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
