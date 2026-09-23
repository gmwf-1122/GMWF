import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'views/daily_log_view.dart' show DailyLogView;
import 'views/student_management_view.dart';
import 'views/monthly_report_view.dart';
import 'views/madrassa_config_view.dart';
import 'views/madrassa_overview_view.dart';
import 'views/madrassa_progress_view.dart';
import 'views/madrassa_teachers_view.dart';
import 'dialogs/enrollment_dialog.dart';
import 'dialogs/madrassa_profile_dialog.dart';
import 'dialogs/register_teacher_dialog.dart';
import 'madrassa_strings.dart';
import 'utils/madrassa_local_storage.dart';
import '../../services/local_storage_service.dart';
import '../../services/sync_service.dart';
import '../../services/auth_service.dart';
import '../../services/user_theme_service.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../design/design_system.dart';

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
  late Future<void> _bootstrapFuture;
  late String _displayUsername;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex ?? 0;
    _displayUsername = widget.username;
    _bootstrapFuture = _bootstrapMadrassa();
    if (widget.autoOpenAddStudent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAddStudentDialog(
          context,
          widget.branchId,
          username: _displayUsername,
          role: widget.role,
        );
      });
    }
  }

  Future<void> _openProfileDialog() async {
    final updated = await MadrassaProfileDialog.show(
      context,
      branchId: widget.branchId,
      currentUsername: _displayUsername,
      userRole: widget.role,
    );
    if (updated != null && updated.isNotEmpty && mounted) {
      setState(() {
        _displayUsername = updated;
      });
    }
  }

  Future<void> _openRegisterTeacherDialog() async {
    // Derive branch display name (fallback to branchId if not stored)
    String branchDisplayName = widget.branchId.toUpperCase();
    try {
      if (Hive.isBoxOpen('app_settings')) {
        final box = Hive.box('app_settings');
        final bn = box.get('branch_name_${widget.branchId.toLowerCase()}');
        if (bn is String && bn.isNotEmpty) branchDisplayName = bn;
      }
    } catch (_) {}

    final registered = await showRegisterTeacherDialog(
      context,
      branchId: widget.branchId,
      branchName: branchDisplayName,
      principalUsername: _displayUsername,
    );
    if (registered == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.white, size: 17),
          SizedBox(width: 8),
          Text('Teacher registered successfully!'),
        ]),
        backgroundColor: Color(0xFF0F766E),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        duration: Duration(seconds: 3),
      ));
    }
  }

  Future<void> _bootstrapMadrassa() async {
    await LocalStorageService.initForRoles([
      widget.role,
      'madrassa',
      'madrassa admin',
      'madrassa teacher',
      'qari',
      'nazim',
      'chairman',
      'hq manager',
      'hq_manager',
      'ceo',
      'admin',
    ]);
    await MadrassaLocalStorage.ensureBoxesOpen();
    if (widget.branchId.isNotEmpty && widget.branchId != 'unknown') {
      SyncService().start(widget.branchId);
    }
  }

  bool get _effectiveIsAdmin {
    final r = widget.role.toLowerCase().trim();
    return widget.isAdmin ||
        r.contains('admin') ||
        r.contains('chairman') ||
        r.contains('hq') ||
        r.contains('hq manager') ||
        r.contains('hqmanager') ||
        r.contains('hq_manager') ||
        r.contains('ceo') ||
        r.contains('principal') ||
        r.contains('manager') ||
        r.contains('director') ||
        r.contains('supervisor') ||
        r.contains('global');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00796B),
              ),
            ),
          );
        }
        return ChangeNotifierProvider(
          create: (_) => MadrassaLanguageProvider(),
          child: Builder(
        builder: (context) {
          final branchId = widget.branchId;

          if (branchId == 'unknown') {
            return const Scaffold(
              body: Center(
                child: Text('Please select a branch first'),
              ),
            );
          }

          final isTeacherOrAdmin = _effectiveIsAdmin || widget.role.toLowerCase() == 'madrassa teacher';

          final views = [
            if (_effectiveIsAdmin)
              MadrassaOverviewView(
                branchId: branchId,
                isAdmin: _effectiveIsAdmin,
                onAction: (index) => setState(() => _selectedIndex = index),
              ),
            DailyLogView(
              branchId: branchId,
              editorName: _displayUsername,
              editorRole: widget.role,
            ),
            StudentManagementView(
              branchId: branchId,
              isAdmin: _effectiveIsAdmin,
              username: _displayUsername,
              role: widget.role,
            ),
            if (_effectiveIsAdmin)
              MadrassaTeachersView(
                branchId: branchId,
                principalUsername: _displayUsername,
                role: widget.role,
              ),
            if (isTeacherOrAdmin) ...[
              MadrassaProgressView(
                branchId: branchId,
                isAdmin: _effectiveIsAdmin,
                username: _displayUsername,
              ),
              MonthlyReportView(
                branchId: branchId,
                username: _displayUsername,
                role: widget.role,
              ),
              MadrassaConfigView(
                branchId: branchId,
                username: _displayUsername,
                role: widget.role,
              ),
            ],
          ];

          final isMobileLayout = GBreakpoint.isMobile(context);

          // Navigation items definitions
          final navTitles = [
            if (_effectiveIsAdmin)
              isMobileLayout
                  ? (context.isUrdu ? 'اوور ویو' : 'Home')
                  : context.l.overviewTitle,
            isMobileLayout
                ? (context.isUrdu ? 'روزانہ' : 'Daily')
                : context.l.dailyLog,
            isMobileLayout
                ? (context.isUrdu ? 'طلبہ' : 'Students')
                : context.l.students,
            if (_effectiveIsAdmin)
              isMobileLayout
                  ? (context.isUrdu ? 'اساتذہ' : 'Teachers')
                  : context.l.teachers,
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
            if (_effectiveIsAdmin) Icons.dashboard_outlined,
            Icons.calendar_today_outlined,
            Icons.people_outline,
            if (_effectiveIsAdmin) Icons.school_outlined,
            if (isTeacherOrAdmin) ...[
              Icons.trending_up_outlined,
              Icons.bar_chart_outlined,
              Icons.settings_outlined,
            ],
          ];

          final navActiveIcons = [
            if (_effectiveIsAdmin) Icons.dashboard_rounded,
            Icons.calendar_today_rounded,
            Icons.people_alt_rounded,
            if (_effectiveIsAdmin) Icons.school_rounded,
            if (isTeacherOrAdmin) ...[
              Icons.trending_up_rounded,
              Icons.bar_chart_rounded,
              Icons.settings_rounded,
            ],
          ];

          return RoleThemeScope(
            role: RoleTheme.madrassa,
            child: ValueListenableBuilder(
              valueListenable: UserThemeService.listenable(widget.username),
              builder: (context, Box box, _) {
                final isDark = UserThemeService.isDarkMode(widget.username);
                final scaffoldBg = isDark ? const Color(0xFF090D16) : const Color(0xFFF6F8FB);
                final cardBg = isDark ? const Color(0xFF131B2E) : Colors.white;
                final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
                final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
                final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
                const emeraldPrimary = Color(0xFF0F766E);
                const emeraldLight = Color(0xFF14B8A6);

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = GBreakpoint.isMobileC(constraints);
                    final isTablet = GBreakpoint.isTabletC(constraints);

                    if (isMobile) {
                      return Scaffold(
                        backgroundColor: scaffoldBg,
                        appBar: _buildMobileAppBar(
                          context,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                        ),
                        body: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildIslamicWatermark(isDark),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                                  child: child,
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey(_selectedIndex),
                                child: views[_selectedIndex],
                              ),
                            ),
                          ],
                        ),
                        bottomNavigationBar: MadrassaMotionBottomBar(
                          selectedIndex: _selectedIndex,
                          onTabSelected: (i) => setState(() => _selectedIndex = i),
                          titles: navTitles,
                          icons: navIcons,
                          activeIcons: navActiveIcons,
                          isDark: isDark,
                        ),
                      );
                    } else if (isTablet) {
                      return Scaffold(
                        backgroundColor: scaffoldBg,
                        appBar: _buildTabletAppBar(
                          context,
                          isDark: isDark,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                          currentTitle: navTitles[_selectedIndex],
                        ),
                        body: Row(
                          children: [
                            _buildTabletSidebar(
                              context,
                              isDark: isDark,
                              cardBg: cardBg,
                              borderColor: borderColor,
                              textMuted: textMuted,
                              navIcons: navIcons,
                              navActiveIcons: navActiveIcons,
                              navTitles: navTitles,
                            ),
                            VerticalDivider(width: 1, thickness: 1, color: borderColor),
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildIslamicWatermark(isDark),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    child: KeyedSubtree(
                                      key: ValueKey(_selectedIndex),
                                      child: views[_selectedIndex],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // Desktop (> 960px)
                      return Scaffold(
                        backgroundColor: scaffoldBg,
                        body: Row(
                          children: [
                            // Executive Desktop Sidebar
                            _buildDesktopSidebar(
                              context,
                              isDark: isDark,
                              cardBg: cardBg,
                              borderColor: borderColor,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              emeraldPrimary: emeraldPrimary,
                              emeraldLight: emeraldLight,
                              navIcons: navIcons,
                              navActiveIcons: navActiveIcons,
                              navTitles: navTitles,
                            ),
                            VerticalDivider(width: 1, thickness: 1, color: borderColor),
                            // Main View Area with Desktop Top Bar
                            Expanded(
                              child: Column(
                                children: [
                                  _buildDesktopTopBar(
                                    context,
                                    isDark: isDark,
                                    cardBg: cardBg,
                                    borderColor: borderColor,
                                    textPrimary: textPrimary,
                                    textMuted: textMuted,
                                    currentTitle: navTitles[_selectedIndex],
                                  ),
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _buildIslamicWatermark(isDark),
                                        Align(
                                          alignment: Alignment.topCenter,
                                          child: Container(
                                            constraints: const BoxConstraints(maxWidth: 1280),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 250),
                                              child: KeyedSubtree(
                                                key: ValueKey(_selectedIndex),
                                                child: views[_selectedIndex],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
          },
        ),
      );
    },
  );
}

  // --- Islamic Watermark Background ---
  Widget _buildIslamicWatermark(bool isDark) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: isDark ? 0.055 : 0.075,
          child: Image.asset(
            'assets/images/islamic_pattern.webp',
            fit: BoxFit.cover,
            repeat: ImageRepeat.repeat,
            color: const Color(0xFFD4AF37),
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
      ),
    );
  }

  // --- Mobile App Bar ---
  PreferredSizeWidget _buildMobileAppBar(
    BuildContext context, {
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg.withValues(alpha: 0.95),
          border: Border(bottom: BorderSide(color: borderColor, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                // Logo squircle with glow
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Image.asset('assets/logo/gmwf-1.webp', fit: BoxFit.contain),
                ),
                const SizedBox(width: 10),
                // Title and role
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gulzar Madina Madrassa',
                        overflow: TextOverflow.ellipsis,
                        style: context.urduStyle(
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              widget.branchId.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF0F766E),
                                fontWeight: FontWeight.bold,
                                fontSize: 9.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _displayUsername.isNotEmpty && _displayUsername.toLowerCase() != 'unknown'
                                  ? _displayUsername
                                  : widget.role,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textMuted,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Profile & Security Button
                IconButton(
                  icon: const Icon(Icons.manage_accounts_rounded, size: 20, color: Color(0xFF0F766E)),
                  tooltip: 'Profile & Password',
                  onPressed: _openProfileDialog,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 6),
                // Register Teacher (principal / chairman / hq / admin)
                if (_effectiveIsAdmin) ...[
                  _buildRegisterTeacherBtn(compact: true),
                  const SizedBox(width: 4),
                ],
                // Modern Action Buttons
                _buildSyncBtn(context, isDark),
                const SizedBox(width: 4),
                _buildThemeToggleBtn(isDark),
                const SizedBox(width: 4),
                _buildLanguageToggleBtn(context, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Tablet App Bar ---
  PreferredSizeWidget _buildTabletAppBar(
    BuildContext context, {
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textMuted,
    required String currentTitle,
  }) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          border: Border(bottom: BorderSide(color: borderColor, width: 1)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Image.asset('assets/logo/gmwf-1.webp', height: 34),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gulzar Madina Madrassa',
                      style: context.urduStyle(
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.branchId.toUpperCase()} • $_displayUsername (${widget.role})',
                      style: TextStyle(color: textMuted, fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    currentTitle,
                    style: context.urduStyle(
                      style: const TextStyle(
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.manage_accounts_rounded, size: 22, color: Color(0xFF0F766E)),
                  tooltip: 'Profile & Password',
                  onPressed: _openProfileDialog,
                ),
                const SizedBox(width: 6),
                if (_effectiveIsAdmin) ...[
                  _buildRegisterTeacherBtn(compact: true),
                  const SizedBox(width: 6),
                ],
                _buildSyncBtn(context, isDark),
                const SizedBox(width: 6),
                _buildThemeToggleBtn(isDark),
                const SizedBox(width: 6),
                _buildLanguageToggleBtn(context, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Tablet Sidebar Navigation Rail ---
  Widget _buildTabletSidebar(
    BuildContext context, {
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textMuted,
    required List<IconData> navIcons,
    required List<IconData> navActiveIcons,
    required List<String> navTitles,
  }) {
    return Container(
      width: 72,
      color: cardBg,
      child: NavigationRail(
        backgroundColor: cardBg,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        labelType: NavigationRailLabelType.none,
        selectedIconTheme: const IconThemeData(color: Color(0xFF0F766E), size: 24),
        unselectedIconTheme: IconThemeData(color: textMuted, size: 22),
        indicatorColor: const Color(0xFF0F766E).withValues(alpha: 0.14),
        destinations: List.generate(navTitles.length, (idx) {
          return NavigationRailDestination(
            icon: Icon(navIcons[idx]),
            selectedIcon: Icon(navActiveIcons[idx]),
            label: Text(navTitles[idx]),
          );
        }),
      ),
    );
  }

  // --- Desktop Top Bar ---
  Widget _buildDesktopTopBar(
    BuildContext context, {
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textMuted,
    required String currentTitle,
  }) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          // Section Title pill badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF0F766E).withValues(alpha: 0.25), const Color(0xFF14B8A6).withValues(alpha: 0.1)]
                    : [const Color(0xFF0F766E).withValues(alpha: 0.12), const Color(0xFF14B8A6).withValues(alpha: 0.05)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                  currentTitle,
                  style: context.urduStyle(
                    style: TextStyle(
                      color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Branch info pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF0F766E)),
                const SizedBox(width: 4),
                Text(
                  widget.branchId.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Profile & Password Button
          IconButton(
            icon: const Icon(Icons.manage_accounts_rounded, size: 22, color: Color(0xFF0F766E)),
            tooltip: 'Profile & Password',
            onPressed: _openProfileDialog,
          ),
          const SizedBox(width: 8),
          // Sync button
          _buildSyncBtn(context, isDark),
          const SizedBox(width: 8),
          // Theme Toggle
          _buildThemeToggleBtn(isDark),
          const SizedBox(width: 8),
          // Language Toggle
          _buildLanguageToggleBtn(context, isDark),
        ],
      ),
    );
  }

  // --- Executive Desktop Sidebar ---
  Widget _buildDesktopSidebar(
    BuildContext context, {
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textMuted,
    required Color emeraldPrimary,
    required Color emeraldLight,
    required List<IconData> navIcons,
    required List<IconData> navActiveIcons,
    required List<String> navTitles,
  }) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Sidebar Brand Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Image.asset('assets/logo/gmwf-1.webp', fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Madrassa',
                        style: context.urduStyle(
                          style: TextStyle(
                            color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Text(
                        'Management Hub',
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sidebar Navigation Items
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: navTitles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, idx) {
                final isSelected = _selectedIndex == idx;
                return _SidebarNavItem(
                  title: navTitles[idx],
                  icon: navIcons[idx],
                  activeIcon: navActiveIcons[idx],
                  isSelected: isSelected,
                  isDark: isDark,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedIndex = idx);
                  },
                );
              },
            ),
          ),

          // Register Teacher button (principal / chairman / hq / admin)
          if (_effectiveIsAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _buildRegisterTeacherBtn(compact: false),
            ),
          // User Profile Card at Bottom
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0E1626) : const Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                // Avatar Circle & User Details (Tappable)
                Expanded(
                  child: InkWell(
                    onTap: _openProfileDialog,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                _displayUsername.isNotEmpty ? _displayUsername[0].toUpperCase() : 'M',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _displayUsername,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 13,
                                      color: const Color(0xFF0F766E).withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  widget.isAdmin
                                      ? 'Principal / Admin'
                                      : widget.role,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Sign Out Button
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                  tooltip: 'Sign Out',
                  splashRadius: 18,
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    try {
                      await AuthService().signOut();
                    } catch (e) {
                      debugPrint('[MadrassaDashboard] Sign out error: $e');
                    }
                    navigator.pushNamedAndRemoveUntil('/login', (_) => false);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Register Teacher Button ---
  Widget _buildRegisterTeacherBtn({required bool compact}) {
    if (compact) {
      // Icon-only for app bars
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF0F766E).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF0F766E).withValues(alpha: 0.3), width: 1),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.person_add_rounded, size: 18, color: Color(0xFF0F766E)),
          tooltip: 'Register New Teacher',
          onPressed: _openRegisterTeacherDialog,
        ),
      );
    }
    // Full-width button for desktop sidebar
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0xFF0F766E).withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: const Icon(Icons.person_add_rounded, size: 17),
        label: const Text(
          'Register Teacher',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
        onPressed: _openRegisterTeacherDialog,
      ),
    );
  }

  // --- Theme Toggle Button ---
  Widget _buildThemeToggleBtn(bool isDark) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            key: ValueKey(isDark),
            color: isDark ? const Color(0xFFFDE047) : const Color(0xFF0F766E),
            size: 18,
          ),
        ),
        tooltip: isDark ? 'Light Mode' : 'Dark Mode',
        onPressed: () async {
          await UserThemeService.toggleDarkMode(explicitUserKey: widget.username);
        },
      ),
    );
  }

  // --- Language Toggle Button ---
  Widget _buildLanguageToggleBtn(BuildContext context, bool isDark) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Provider.of<MadrassaLanguageProvider>(context, listen: false).toggleLanguage();
        },
        child: Center(
          child: Text(
            context.isUrdu ? 'EN' : 'اردو',
            style: context.urduStyle(
              style: TextStyle(
                color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E),
                fontWeight: FontWeight.bold,
                fontSize: context.isUrdu ? 12 : 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Sync Cloud Data Button ---
  Widget _buildSyncBtn(BuildContext context, bool isDark) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(
          Icons.sync_rounded,
          color: Color(0xFF0F766E),
          size: 18,
        ),
        tooltip: context.isUrdu ? 'کلاؤڈ سے معلومات اپ ڈیٹ کریں' : 'Sync / Download Cloud Data',
        onPressed: () async {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.isUrdu ? 'ڈیٹا حاصل کیا جا رہا ہے...' : 'Syncing data from cloud...'),
              duration: const Duration(seconds: 1),
            ),
          );
          final now = DateTime.now();
          await MadrassaLocalStorage.downloadStudents(widget.branchId, force: true);
          await MadrassaLocalStorage.downloadLogsForMonth(widget.branchId, now.year, now.month);
          await MadrassaLocalStorage.downloadHolidays(widget.branchId);
          if (mounted) setState(() {});
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.isUrdu ? 'ڈیٹا کامیابی سے اپ ڈیٹ ہو گیا' : 'Sync completed successfully!'),
                backgroundColor: const Color(0xFF0F766E),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }
}

// ==========================================
// DESKTOP SIDEBAR NAV ITEM (With Hover Effects)
// ==========================================
class _SidebarNavItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final activeBg = widget.isDark
        ? const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF115E59)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          );

    final hoverBg = widget.isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.6)
        : const Color(0xFFF1F5F9);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: widget.isSelected ? activeBg : null,
            color: widget.isSelected ? null : (_isHovered ? hoverBg : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.isSelected ? widget.activeIcon : widget.icon,
                size: 20,
                color: widget.isSelected
                    ? Colors.white
                    : (_isHovered
                        ? (widget.isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E))
                        : (widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: context.urduStyle(
                    style: TextStyle(
                      color: widget.isSelected
                          ? Colors.white
                          : (_isHovered
                              ? (widget.isDark ? Colors.white : const Color(0xFF0F172A))
                              : (widget.isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155))),
                      fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isSelected)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34D399),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MOBILE MOTION BOTTOM BAR (Glass / Floating Style)
// ==========================================
class MadrassaMotionBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final List<String> titles;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final bool isDark;

  const MadrassaMotionBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.titles,
    required this.icons,
    required this.activeIcons,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF101726) : Colors.white;
    final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final activeGradient = isDark
        ? const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF14B8A6)])
        : const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0D9488)]);
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final isScrollable = titles.length > 5;

    Widget buildItem(int i) {
      final isSelected = selectedIndex == i;
      final item = GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTabSelected(i);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            gradient: isSelected ? activeGradient : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? activeIcons[i] : icons[i],
                  size: 19,
                  color: isSelected ? Colors.white : inactiveColor,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 5),
                Text(
                  titles[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.urduStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

      if (isScrollable) {
        return item;
      }
      return Expanded(
        flex: isSelected ? 2 : 1,
        child: item,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: borderColor, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: isScrollable
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: List.generate(titles.length, buildItem),
                  ),
                )
              : Row(
                  children: List.generate(titles.length, buildItem),
                ),
        ),
      ),
    );
  }
}
