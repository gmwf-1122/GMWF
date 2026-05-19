import 'package:flutter/material.dart';
import 'views/daily_log_view.dart';
import 'views/student_management_view.dart';
import 'views/monthly_report_view.dart';
import 'views/madrassa_config_view.dart';
import 'views/madrassa_overview_view.dart';

class MadrassaDashboard extends StatefulWidget {
  final String branchId;
  final String username;
  final String role;
  final bool isAdmin;

  const MadrassaDashboard({
    super.key,
    required this.branchId,
    required this.username,
    required this.role,
    this.isAdmin = true,
  });

  @override
  State<MadrassaDashboard> createState() => _MadrassaDashboardState();
}

class _MadrassaDashboardState extends State<MadrassaDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final branchId = widget.branchId;

    if (branchId == 'unknown') {
      return const Center(child: Text('Please select a branch first'));
    }

    final views = [
      MadrassaOverviewView(
        branchId: branchId,
        onAction: (index) => setState(() => _selectedIndex = index),
      ),
      DailyLogView(branchId: branchId, editorName: widget.username),
      StudentManagementView(branchId: branchId, isAdmin: widget.isAdmin),
      if (widget.isAdmin) ...[
        MonthlyReportView(branchId: branchId),
        MadrassaConfigView(branchId: branchId),
      ],
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/logo/gmwf-1.png', height: 32),
            const SizedBox(width: 12),
            const Text(
              'Gulzar Madina',
              style: TextStyle(color: Color(0xFF1A1C1E), fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: views[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF4C4DDC),
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Overview'),
            const BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), activeIcon: Icon(Icons.calendar_today), label: 'Daily Log'),
            const BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Students'),
            if (widget.isAdmin) ...[
              const BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Reports'),
              const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: 'Config'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _navAction(String label, IconData icon, int index) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TextButton.icon(
        onPressed: index == -1 ? null : () => setState(() => _selectedIndex = index),
        icon: Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.grey[700]),
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey[700], fontSize: 13)),
        style: TextButton.styleFrom(
          backgroundColor: isSelected ? const Color(0xFF4C4DDC) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
