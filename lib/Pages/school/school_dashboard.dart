// lib/pages/school/school_dashboard.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'views/school_overview_view.dart';
import 'views/school_daily_attendance_view.dart';
import 'views/school_teacher_attendance_view.dart';
import 'views/school_student_management_view.dart';
import 'views/school_teacher_management_view.dart';
import 'views/school_library_view.dart';
import 'views/school_audit_log_view.dart';
import 'views/school_grading_view.dart';
import 'views/school_fee_management_view.dart';
import 'views/school_principal_dashboard_view.dart';
import 'theme/school_theme.dart';
import 'utils/school_local_storage.dart';
import 'utils/school_sync_service.dart';
import '../../widgets/global_module_wrapper.dart';
import '../../widgets/app_back_button.dart';

class _NavItem {
  final String label;
  final IconData icon;

  const _NavItem({
    required this.label,
    required this.icon,
  });
}

class SchoolDashboard extends StatefulWidget {
  final String branchId;
  final String username;
  final String role;
  final int initialTabIndex;

  const SchoolDashboard({
    super.key,
    this.branchId = 'all',
    this.username = 'User',
    this.role = 'School Admin',
    this.initialTabIndex = 0,
  });

  @override
  State<SchoolDashboard> createState() => _SchoolDashboardState();
}

class _SchoolDashboardState extends State<SchoolDashboard> {
  int _selectedIndex = 0;
  List<_NavItem> _navItems = [];
  List<Widget> _views = [];
  bool _isCollapsed = false;

  bool get _isTeacher {
    final r = widget.role.toLowerCase().trim();
    return r.contains('teacher') && !r.contains('admin') && !r.contains('principal');
  }

  bool get _isPrincipal {
    final r = widget.role.toLowerCase().trim();
    return r.contains('principal');
  }

  @override
  void initState() {
    super.initState();
    SchoolLocalStorage.ensureBoxesOpen();
    SchoolSyncService().init();
    _initNavItemsAndViews();
    _selectedIndex = widget.initialTabIndex.clamp(0, _navItems.isNotEmpty ? _navItems.length - 1 : 0);
  }

  @override
  void didUpdateWidget(covariant SchoolDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role || oldWidget.branchId != widget.branchId || oldWidget.username != widget.username) {
      _initNavItemsAndViews();
    }
  }

  void _initNavItemsAndViews() {
    if (_isPrincipal) {
      // Principal sees Principal Dashboard (Top Students + School Details), Directory, Fee, Library, Reports
      _navItems = const [
        _NavItem(label: 'Principal Dashboard', icon: Icons.dashboard_rounded),
        _NavItem(label: 'Student Directory', icon: Icons.groups_rounded),
        _NavItem(label: 'Daily Attendance', icon: Icons.how_to_reg_rounded),
        _NavItem(label: 'Faculty Attendance', icon: Icons.co_present_rounded),
        _NavItem(label: 'Faculty Registry', icon: Icons.record_voice_over_rounded),
        _NavItem(label: 'Fee Management', icon: Icons.payments_rounded),
        _NavItem(label: 'School Library', icon: Icons.local_library_rounded),
        _NavItem(label: 'Grading & Reports', icon: Icons.grade_rounded),
        _NavItem(label: 'Audit Trail', icon: Icons.security_rounded),
      ];
      _views = [
        SchoolPrincipalDashboardView(
          branchId: widget.branchId,
          userName: widget.username,
        ),
        SchoolStudentManagementView(branchId: widget.branchId),
        SchoolDailyAttendanceView(
          branchId: widget.branchId,
          editorName: widget.username,
          userRole: widget.role,
        ),
        SchoolTeacherAttendanceView(
          branchId: widget.branchId,
          editorName: widget.username,
        ),
        SchoolTeacherManagementView(branchId: widget.branchId),
        SchoolFeeManagementView(
          branchId: widget.branchId,
          userName: widget.username,
          userRole: widget.role,
        ),
        SchoolLibraryView(
          branchId: widget.branchId,
          userName: widget.username,
        ),
        SchoolGradingView(
          branchId: widget.branchId,
          userRole: widget.role,
          userName: widget.username,
        ),
        SchoolAuditLogView(branchId: widget.branchId),
      ];
    } else if (_isTeacher) {
      // Teachers see Overview, Student Attendance (Homeroom restricted), Student Directory, and Grading & Reports
      _navItems = const [
        _NavItem(label: 'Overview', icon: Icons.analytics_rounded),
        _NavItem(label: 'Student Attendance', icon: Icons.how_to_reg_rounded),
        _NavItem(label: 'Students Directory', icon: Icons.groups_rounded),
        _NavItem(label: 'Grading & Reports', icon: Icons.grade_rounded),
      ];
      _views = [
        SchoolOverviewView(branchId: widget.branchId),
        SchoolDailyAttendanceView(
          branchId: widget.branchId,
          editorName: widget.username,
          userRole: widget.role,
        ),
        SchoolStudentManagementView(branchId: widget.branchId),
        SchoolGradingView(
          branchId: widget.branchId,
          userRole: widget.role,
          userName: widget.username,
        ),
      ];
    } else {
      // Admin sees complete school control: Fee Management, Library, Faculty Attendance, Student Visibility, Homeroom Assignment, Reports
      _navItems = const [
        _NavItem(label: 'Overview', icon: Icons.analytics_rounded),
        _NavItem(label: 'Student Admissions', icon: Icons.groups_rounded),
        _NavItem(label: 'Student Attendance', icon: Icons.how_to_reg_rounded),
        _NavItem(label: 'Faculty Attendance', icon: Icons.co_present_rounded),
        _NavItem(label: 'Faculty Registry', icon: Icons.record_voice_over_rounded),
        _NavItem(label: 'Fee Management', icon: Icons.payments_rounded),
        _NavItem(label: 'School Library', icon: Icons.local_library_rounded),
        _NavItem(label: 'Grading & Reports', icon: Icons.grade_rounded),
        _NavItem(label: 'Audit Trail', icon: Icons.security_rounded),
      ];
      _views = [
        SchoolOverviewView(branchId: widget.branchId),
        SchoolStudentManagementView(branchId: widget.branchId),
        SchoolDailyAttendanceView(
          branchId: widget.branchId,
          editorName: widget.username,
          userRole: widget.role,
        ),
        SchoolTeacherAttendanceView(
          branchId: widget.branchId,
          editorName: widget.username,
        ),
        SchoolTeacherManagementView(branchId: widget.branchId),
        SchoolFeeManagementView(
          branchId: widget.branchId,
          userName: widget.username,
          userRole: widget.role,
        ),
        SchoolLibraryView(
          branchId: widget.branchId,
          userName: widget.username,
        ),
        SchoolGradingView(
          branchId: widget.branchId,
          userRole: widget.role,
          userName: widget.username,
        ),
        SchoolAuditLogView(branchId: widget.branchId),
      ];
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 10),
            Text('Sign Out'),
          ],
        ),
        content: const Text('Are you sure you want to sign out from the School System?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_navItems.isEmpty) {
      _initNavItemsAndViews();
    }
    final mediaWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = mediaWidth < 850;
    final effectiveCollapsed = _isCollapsed || isSmallScreen;
    final isWrapped = GlobalModuleWrapper.isWrapped(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: isWrapped ? null : _buildTopAppBar(context),
      body: Row(
        children: [
          // Sidebar Navigation
          _buildSidebar(effectiveCollapsed),

          // Main View Content Area
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _views,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildTopAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: SchoolTheme.sidebarBg,
      elevation: 0,
      leading: const AppBackButton(color: Colors.white),
      title: Row(
        children: [
          // Dual Logo Header: GMWF Logo + TWT Logo
          ClipRRect(
            borderRadius: SchoolTheme.radius8,
            child: Image.asset(
              'assets/logo/gmwf-1.png',
              height: 32,
              width: 32,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: SchoolTheme.primaryDark,
                  borderRadius: SchoolTheme.radius8,
                ),
                child: const Text('GMWF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('•', style: TextStyle(color: SchoolTheme.sidebarMuted, fontSize: 16)),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: SchoolTheme.radius8,
            child: Image.asset(
              'assets/logo/twt_logo.png',
              height: 32,
              width: 32,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SchoolTheme.accent.withValues(alpha: 0.2),
                  border: Border.all(color: SchoolTheme.accent),
                  borderRadius: SchoolTheme.radius8,
                ),
                child: Row(
                  children: const [
                    Icon(Icons.school_rounded, color: SchoolTheme.accent, size: 16),
                    SizedBox(width: 4),
                    Text('TWT', style: TextStyle(color: SchoolTheme.accent, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Taleem-o-Tarbiyat School System',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'A Project of GMWF • Branch: ${widget.branchId} • Role: ${widget.role}',
                  style: const TextStyle(color: SchoolTheme.sidebarMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        _SchoolSyncBadge(branchId: widget.branchId),
        IconButton(
          tooltip: _isCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
          icon: Icon(
            _isCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() => _isCollapsed = !_isCollapsed);
          },
        ),
        IconButton(
          tooltip: 'Logout',
          icon: const Icon(Icons.logout_rounded, color: SchoolTheme.statusAbsent),
          onPressed: _logout,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSidebar(bool isCollapsed) {
    final width = isCollapsed ? 72.0 : 250.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: width,
      decoration: const BoxDecoration(
        color: SchoolTheme.sidebarBg,
        border: Border(
          right: BorderSide(color: SchoolTheme.sidebarBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Sidebar Section Header
          if (!isCollapsed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'NAVIGATION',
                  style: TextStyle(
                    color: SchoolTheme.sidebarMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 4),

          // Navigation items list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = index == _selectedIndex;

                final tileWidget = Material(
                    color: Colors.transparent,
                    borderRadius: SchoolTheme.radius12,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedIndex = index);
                      },
                      splashColor: SchoolTheme.accent.withValues(alpha: 0.15),
                      hoverColor: SchoolTheme.sidebarBorder,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCollapsed ? 0 : 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? SchoolTheme.accent
                              : Colors.transparent,
                          borderRadius: SchoolTheme.radius12,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: SchoolTheme.accent.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: isCollapsed
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            Icon(
                              item.icon,
                              color: isSelected
                                  ? Colors.white
                                  : SchoolTheme.sidebarMuted,
                              size: 20,
                            ),
                            if (!isCollapsed) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : SchoolTheme.sidebarText,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 13.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: isCollapsed
                      ? Tooltip(message: item.label, child: tileWidget)
                      : tileWidget,
                );
              },
            ),
          ),

          // Logout tile in Sidebar
          const Divider(color: Color(0xFF1E293B), height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _logout,
                splashColor: const Color(0xFFEF4444).withValues(alpha: 0.2),
                hoverColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCollapsed ? 0 : 14,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: isCollapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFF87171),
                        size: 20,
                      ),
                      if (!isCollapsed) ...[
                        const SizedBox(width: 12),
                        const Text(
                          'Sign Out',
                          style: TextStyle(
                            color: Color(0xFFF87171),
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Sidebar Footer / Toggle button
          const Divider(color: Color(0xFF1E293B), height: 1),
          InkWell(
            onTap: () => setState(() => _isCollapsed = !_isCollapsed),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: isCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  if (!isCollapsed)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.branchId.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  Icon(
                    isCollapsed
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.arrow_back_ios_rounded,
                    color: const Color(0xFF64748B),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchoolSyncBadge extends StatelessWidget {
  final String branchId;

  const _SchoolSyncBadge({required this.branchId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SchoolSyncStatus>(
      stream: SchoolSyncService().statusStream,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null) return const SizedBox.shrink();

        Color color;
        String text;
        IconData? icon;

        switch (status.state) {
          case SchoolSyncState.synced:
            color = const Color(0xFF10B981);
            text = 'Synced';
            icon = Icons.cloud_done_rounded;
            break;
          case SchoolSyncState.syncing:
            color = const Color(0xFFF59E0B);
            text = 'Syncing…';
            icon = Icons.sync_rounded;
            break;
          case SchoolSyncState.failed:
            color = const Color(0xFFEF4444);
            text = 'Sync Failed (${status.failedCount})';
            icon = Icons.error_outline_rounded;
            break;
          case SchoolSyncState.offlinePending:
            color = status.isOnline ? const Color(0xFFF59E0B) : const Color(0xFF64748B);
            text = status.pendingCount > 0 ? 'Offline (${status.pendingCount} pending)' : 'Offline Mode';
            icon = Icons.cloud_off_rounded;
            break;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Triggering manual School data sync…'),
                    duration: Duration(seconds: 1),
                  ),
                );
                await SchoolSyncService().syncNow(branchId: branchId);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status.state == SchoolSyncState.syncing)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    else
                      Icon(icon, color: color, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      text,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.refresh_rounded, color: color.withValues(alpha: 0.8), size: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
