import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'views/daily_log_view.dart' show DailyLogView;
import 'views/student_management_view.dart';
import 'views/monthly_report_view.dart';
import 'views/madrassa_config_view.dart';
import 'views/madrassa_overview_view.dart';
import 'views/madrassa_progress_view.dart';
import 'dialogs/enrollment_dialog.dart';
import 'madrassa_strings.dart';
import '../../services/sync_service.dart';

class MadrassaDashboard extends StatefulWidget {
  final String branchId;
  final String username;
  final String role;
  final bool isAdmin;
  final int? initialIndex;
  final bool autoOpenAddStudent;

  const MadrassaDashboard({
    super.key,
    required this.branchId,
    required this.username,
    required this.role,
    this.isAdmin = true,
    this.initialIndex,
    this.autoOpenAddStudent = false,
  });

  @override
  State<MadrassaDashboard> createState() => _MadrassaDashboardState();
}

class _MadrassaDashboardState extends State<MadrassaDashboard> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex ?? 0;
    if (widget.branchId.isNotEmpty && widget.branchId != 'unknown') {
      SyncService().start(widget.branchId);
    }
    if (widget.autoOpenAddStudent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAddStudentDialog(
          context,
          widget.branchId,
          username: widget.username,
          role: widget.role,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MadrassaLanguageProvider(),
      child: Builder(
        builder: (context) {
          final branchId = widget.branchId;

          if (branchId == 'unknown') {
            return const Center(child: Text('Please select a branch first'));
          }

          final isTeacherOrAdmin = widget.isAdmin || widget.role.toLowerCase() == 'madrassa teacher';

          final views = [
            if (widget.isAdmin)
              MadrassaOverviewView(
                branchId: branchId,
                isAdmin: widget.isAdmin,
                onAction: (index) => setState(() => _selectedIndex = index),
              ),
            DailyLogView(
              branchId: branchId,
              editorName: widget.username,
              editorRole: widget.role,
            ),
            StudentManagementView(
              branchId: branchId,
              isAdmin: widget.isAdmin,
              username: widget.username,
              role: widget.role,
            ),
            if (isTeacherOrAdmin) ...[
              MadrassaProgressView(
                branchId: branchId,
                isAdmin: widget.isAdmin,
              ),
              MonthlyReportView(branchId: branchId),
              MadrassaConfigView(
                branchId: branchId,
                username: widget.username,
                role: widget.role,
              ),
            ],
          ];

          final isMobileLayout = MediaQuery.of(context).size.width < 600;

          // Navigation items definitions
          final navTitles = [
            if (widget.isAdmin)
              isMobileLayout
                  ? (context.isUrdu ? 'اوور ویو' : 'Home')
                  : context.l.overviewTitle,
            isMobileLayout
                ? (context.isUrdu ? 'روزانہ' : 'Daily')
                : context.l.dailyLog,
            isMobileLayout
                ? (context.isUrdu ? 'طلبہ' : 'Students')
                : context.l.students,
            if (isTeacherOrAdmin) ...[
              context.isUrdu ? 'پیشرفت' : 'Progress',
              isMobileLayout
                  ? (context.isUrdu ? 'ماہانہ' : 'Monthly')
                  : context.l.monthlyReport,
              isMobileLayout
                  ? (context.isUrdu ? 'سیٹنگ' : 'Setup')
                  : context.l.navConfig,
            ],
          ];

          final navIcons = [
            if (widget.isAdmin) const Icon(Icons.dashboard_outlined),
            const Icon(Icons.calendar_today_outlined),
            const Icon(Icons.people_outline),
            if (isTeacherOrAdmin) ...[
              const Icon(Icons.trending_up_outlined),
              const Icon(Icons.bar_chart_outlined),
              const Icon(Icons.settings_outlined),
            ],
          ];

          final navActiveIcons = [
            if (widget.isAdmin) const Icon(Icons.dashboard),
            const Icon(Icons.calendar_today),
            const Icon(Icons.people),
            if (isTeacherOrAdmin) ...[
              const Icon(Icons.trending_up),
              const Icon(Icons.bar_chart),
              const Icon(Icons.settings),
            ],
          ];

          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth <= 900;

              if (isMobile) {
                return Scaffold(
                  backgroundColor: const Color(0xFFF8F9FD),
                  appBar: AppBar(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    titleSpacing: 16,
                    automaticallyImplyLeading: false,
                    title: Row(
                      children: [
                        Image.asset('assets/logo/gmwf-1.webp', height: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l.appName,
                            overflow: TextOverflow.ellipsis,
                            style: context.urduStyle(
                              style: const TextStyle(
                                color: Color(0xFF1A1C1E),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      // Language Toggle
                      IconButton(
                        icon: Text(
                          context.isUrdu ? 'EN' : 'اردو',
                          style: context.urduStyle(
                            style: TextStyle(
                              color: const Color(0xFF4C4DDC),
                              fontWeight: FontWeight.bold,
                              fontSize: context.isUrdu ? 12 : 14,
                            ),
                          ),
                        ),
                        onPressed: () {
                          Provider.of<MadrassaLanguageProvider>(context, listen: false).toggleLanguage();
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4C4DDC).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF4C4DDC).withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              widget.role,
                              style: const TextStyle(
                                color: Color(0xFF4C4DDC),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  body: views[_selectedIndex],
                  bottomNavigationBar: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        )
                      ],
                    ),
                    child: BottomNavigationBar(
                      currentIndex: _selectedIndex,
                      onTap: (i) => setState(() => _selectedIndex = i),
                      type: BottomNavigationBarType.fixed,
                      backgroundColor: Colors.white,
                      selectedItemColor: const Color(0xFF4C4DDC),
                      unselectedItemColor: Colors.grey,
                      selectedLabelStyle: context.urduStyle(style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      unselectedLabelStyle: context.urduStyle(style: const TextStyle(fontSize: 12)),
                      items: List.generate(navTitles.length, (idx) {
                        return BottomNavigationBarItem(
                          icon: navIcons[idx],
                          activeIcon: navActiveIcons[idx],
                          label: navTitles[idx],
                        );
                      }),
                    ),
                  ),
                );
              } else if (isTablet) {
                return Scaffold(
                  backgroundColor: const Color(0xFFF8F9FD),
                  appBar: AppBar(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    titleSpacing: 16,
                    automaticallyImplyLeading: false,
                    title: Row(
                      children: [
                        Image.asset('assets/logo/gmwf-1.webp', height: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l.appName,
                            overflow: TextOverflow.ellipsis,
                            style: context.urduStyle(
                              style: const TextStyle(
                                color: Color(0xFF1A1C1E),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      // Language Toggle
                      IconButton(
                        icon: Text(
                          context.isUrdu ? 'EN' : 'اردو',
                          style: context.urduStyle(
                            style: TextStyle(
                              color: const Color(0xFF4C4DDC),
                              fontWeight: FontWeight.bold,
                              fontSize: context.isUrdu ? 12 : 14,
                            ),
                          ),
                        ),
                        onPressed: () {
                          Provider.of<MadrassaLanguageProvider>(context, listen: false).toggleLanguage();
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4C4DDC).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF4C4DDC).withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              widget.role,
                              style: const TextStyle(
                                color: Color(0xFF4C4DDC),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  body: Row(
                    children: [
                      NavigationRail(
                        backgroundColor: Colors.white,
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
                        labelType: NavigationRailLabelType.none,
                        selectedIconTheme: const IconThemeData(color: Color(0xFF4C4DDC)),
                        unselectedIconTheme: const IconThemeData(color: Colors.grey),
                        destinations: List.generate(navTitles.length, (idx) {
                          return NavigationRailDestination(
                            icon: navIcons[idx],
                            selectedIcon: navActiveIcons[idx],
                            label: Text(navTitles[idx]),
                          );
                        }),
                      ),
                      const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE0E2E7)),
                      Expanded(child: views[_selectedIndex]),
                    ],
                  ),
                );
              } else {
                // Desktop (> 900px)
                return Scaffold(
                  backgroundColor: const Color(0xFFF8F9FD),
                  appBar: AppBar(
                    backgroundColor: Colors.white,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    title: Row(
                      children: [
                        Image.asset('assets/logo/gmwf-1.webp', height: 32),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            context.l.appName,
                            overflow: TextOverflow.ellipsis,
                            style: context.urduStyle(
                              style: const TextStyle(
                                color: Color(0xFF008080),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(width: 1, height: 20, color: const Color(0xFFE0E2E7)),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            navTitles[_selectedIndex],
                            overflow: TextOverflow.ellipsis,
                            style: context.urduStyle(
                              style: const TextStyle(
                                color: Color(0xFF1A1C1E),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      // Language Toggle
                      IconButton(
                        icon: Text(
                          context.isUrdu ? 'EN' : 'اردو',
                          style: context.urduStyle(
                            style: TextStyle(
                              color: const Color(0xFF4C4DDC),
                              fontWeight: FontWeight.bold,
                              fontSize: context.isUrdu ? 12 : 14,
                            ),
                          ),
                        ),
                        onPressed: () {
                          Provider.of<MadrassaLanguageProvider>(context, listen: false).toggleLanguage();
                        },
                      ),
                      const SizedBox(width: 16),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(1),
                      child: Container(
                        color: const Color(0xFFE0E2E7),
                        height: 1,
                      ),
                    ),
                  ),
                  body: Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: Column(
                          children: [
                            Expanded(
                              child: NavigationRail(
                                extended: true,
                                backgroundColor: Colors.white,
                                selectedIndex: _selectedIndex,
                                onDestinationSelected: (i) => setState(() => _selectedIndex = i),
                                selectedIconTheme: const IconThemeData(color: Color(0xFF4C4DDC)),
                                unselectedIconTheme: const IconThemeData(color: Colors.grey),
                                selectedLabelTextStyle: context.urduStyle(
                                  style: const TextStyle(
                                    color: Color(0xFF4C4DDC),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                unselectedLabelTextStyle: context.urduStyle(
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                                leading: Column(
                                  children: [
                                    const SizedBox(height: 24),
                                    Image.asset('assets/logo/gmwf-1.webp', height: 36),
                                    const SizedBox(height: 8),
                                    Text(
                                      context.l.appName,
                                      style: context.urduStyle(
                                        style: const TextStyle(
                                          color: Color(0xFF008080),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                                destinations: List.generate(navTitles.length, (idx) {
                                  return NavigationRailDestination(
                                    icon: navIcons[idx],
                                    selectedIcon: navActiveIcons[idx],
                                    label: Text(navTitles[idx]),
                                  );
                                }),
                              ),
                            ),
                            const Divider(height: 1, thickness: 1, color: Color(0xFFE0E2E7)),
                            Container(
                              color: Colors.white,
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.username,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF1A1C1E),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.role,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                                    tooltip: 'Sign Out',
                                    onPressed: () async {
                                      final navigator = Navigator.of(context);
                                      await FirebaseAuth.instance.signOut();
                                      navigator.pushNamedAndRemoveUntil('/login', (_) => false);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE0E2E7)),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: views[_selectedIndex],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}
