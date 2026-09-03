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
import 'dialogs/enrollment_dialog.dart';
import 'madrassa_strings.dart';
import '../../services/sync_service.dart';
import '../../services/auth_service.dart';
import '../../services/user_theme_service.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';

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
                username: widget.username,
              ),
              MonthlyReportView(
                branchId: branchId,
                username: widget.username,
              ),
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

          return RoleThemeScope(
            role: RoleTheme.madrassa,
            child: ValueListenableBuilder(
              valueListenable: UserThemeService.listenable(widget.username),
              builder: (context, Box box, _) {
                final isDark = UserThemeService.isDarkMode(widget.username);
                final scaffoldBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F9FD);
                final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
                final textPrimary = isDark ? Colors.white : const Color(0xFF1A1C1E);
                final textMuted = isDark ? const Color(0xFF94A3B8) : Colors.grey;
                final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE0E2E7);
                const accentColor = Color(0xFF0F6C5A);

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth <= 900;

                    if (isMobile) {
                      return Scaffold(
                        backgroundColor: scaffoldBg,
                        appBar: AppBar(
                          backgroundColor: cardBg,
                          elevation: 0,
                          titleSpacing: 12,
                          automaticallyImplyLeading: false,
                          title: Row(
                            children: [
                              Image.asset('assets/logo/gmwf-1.webp', height: 32),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Gulzar Madina Madrassa',
                                      overflow: TextOverflow.ellipsis,
                                      style: context.urduStyle(
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      '${widget.username.isNotEmpty && widget.username.toLowerCase() != 'unknown' ? "${widget.username} • " : ""}${widget.role}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            // Dark Mode Toggle
                            IconButton(
                              icon: Icon(
                                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                color: isDark ? const Color(0xFFFDE047) : accentColor,
                                size: 20,
                              ),
                              tooltip: isDark ? (context.isUrdu ? 'لائٹ موڈ' : 'Light Mode') : (context.isUrdu ? 'ڈارک موڈ' : 'Dark Mode'),
                              onPressed: () async {
                                await UserThemeService.toggleDarkMode(explicitUserKey: widget.username);
                              },
                            ),
                            // Language Toggle
                            IconButton(
                              icon: Text(
                                context.isUrdu ? 'EN' : 'اردو',
                                style: context.urduStyle(
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC),
                                    fontWeight: FontWeight.bold,
                                    fontSize: context.isUrdu ? 12 : 14,
                                  ),
                                ),
                              ),
                              onPressed: () {
                                Provider.of<MadrassaLanguageProvider>(context, listen: false).toggleLanguage();
                              },
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                        body: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: isDark ? 0.085 : 0.11,
                                  child: Image.asset(
                                    'assets/images/islamic_pattern.webp',
                                    fit: BoxFit.cover,
                                    repeat: ImageRepeat.repeat,
                                    color: const Color(0xFFD4AF37),
                                    colorBlendMode: BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
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
                        appBar: AppBar(
                          backgroundColor: cardBg,
                          elevation: 0,
                          titleSpacing: 12,
                          automaticallyImplyLeading: false,
                          title: Row(
                            children: [
                              Image.asset('assets/logo/gmwf-1.webp', height: 32),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Gulzar Madina Madrassa',
                                      overflow: TextOverflow.ellipsis,
                                      style: context.urduStyle(
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      '${widget.username.isNotEmpty && widget.username.toLowerCase() != 'unknown' ? "${widget.username} • " : ""}${widget.role}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            // Dark Mode Toggle
                            IconButton(
                              icon: Icon(
                                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                color: isDark ? const Color(0xFFFDE047) : accentColor,
                                size: 20,
                              ),
                              tooltip: isDark ? (context.isUrdu ? 'لائٹ موڈ' : 'Light Mode') : (context.isUrdu ? 'ڈارک موڈ' : 'Dark Mode'),
                              onPressed: () async {
                                await UserThemeService.toggleDarkMode(explicitUserKey: widget.username);
                              },
                            ),
                            // Language Toggle
                            IconButton(
                              icon: Text(
                                context.isUrdu ? 'EN' : 'اردو',
                                style: context.urduStyle(
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC),
                                    fontWeight: FontWeight.bold,
                                    fontSize: context.isUrdu ? 12 : 14,
                                  ),
                                ),
                              ),
                              onPressed: () {
                                Provider.of<MadrassaLanguageProvider>(context, listen: false).toggleLanguage();
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                        body: Row(
                          children: [
                            NavigationRail(
                              backgroundColor: cardBg,
                              selectedIndex: _selectedIndex,
                              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
                              labelType: NavigationRailLabelType.none,
                              selectedIconTheme: IconThemeData(color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC)),
                              unselectedIconTheme: IconThemeData(color: textMuted),
                              destinations: List.generate(navTitles.length, (idx) {
                                return NavigationRailDestination(
                                  icon: navIcons[idx],
                                  selectedIcon: navActiveIcons[idx],
                                  label: Text(navTitles[idx]),
                                );
                              }),
                            ),
                            VerticalDivider(width: 1, thickness: 1, color: borderColor),
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity: isDark ? 0.085 : 0.11,
                                        child: Image.asset(
                                          'assets/images/islamic_pattern.webp',
                                          fit: BoxFit.cover,
                                          repeat: ImageRepeat.repeat,
                                          color: const Color(0xFFD4AF37),
                                          colorBlendMode: BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                  ),
                                  views[_selectedIndex],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // Desktop (> 900px)
                      return Scaffold(
                        backgroundColor: scaffoldBg,
                        appBar: AppBar(
                          backgroundColor: cardBg,
                          elevation: 0,
                          automaticallyImplyLeading: false,
                          title: Row(
                            children: [
                              Image.asset('assets/logo/gmwf-1.webp', height: 32),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gulzar Madina Madrassa',
                                    overflow: TextOverflow.ellipsis,
                                    style: context.urduStyle(
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF008080),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    '${widget.username.isNotEmpty && widget.username.toLowerCase() != 'unknown' ? "${widget.username} • " : ""}${widget.role}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Container(width: 1, height: 24, color: borderColor),
                              const SizedBox(width: 14),
                              Flexible(
                                child: Text(
                                  navTitles[_selectedIndex],
                                  overflow: TextOverflow.ellipsis,
                                  style: context.urduStyle(
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            // Dark Mode Toggle
                            IconButton(
                              icon: Icon(
                                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                color: isDark ? const Color(0xFFFDE047) : accentColor,
                                size: 20,
                              ),
                              tooltip: isDark ? (context.isUrdu ? 'لائٹ موڈ' : 'Light Mode') : (context.isUrdu ? 'ڈارک موڈ' : 'Dark Mode'),
                              onPressed: () async {
                                await UserThemeService.toggleDarkMode(explicitUserKey: widget.username);
                              },
                            ),
                            // Language Toggle
                            IconButton(
                              icon: Text(
                                context.isUrdu ? 'EN' : 'اردو',
                                style: context.urduStyle(
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC),
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
                              color: borderColor,
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
                                      backgroundColor: cardBg,
                                      selectedIndex: _selectedIndex,
                                      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
                                      selectedIconTheme: IconThemeData(color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC)),
                                      unselectedIconTheme: IconThemeData(color: textMuted),
                                      selectedLabelTextStyle: context.urduStyle(
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4C4DDC),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      unselectedLabelTextStyle: context.urduStyle(
                                        style: TextStyle(
                                          color: textMuted,
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
                                              style: TextStyle(
                                                color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF008080),
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
                                  Divider(height: 1, thickness: 1, color: borderColor),
                                  Container(
                                    color: cardBg,
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
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: textPrimary,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                widget.role,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: textMuted,
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
                            ),
                            VerticalDivider(width: 1, thickness: 1, color: borderColor),
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity: isDark ? 0.085 : 0.11,
                                        child: Image.asset(
                                          'assets/images/islamic_pattern.webp',
                                          fit: BoxFit.cover,
                                          repeat: ImageRepeat.repeat,
                                          color: const Color(0xFFD4AF37),
                                          colorBlendMode: BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 1200),
                                      child: views[_selectedIndex],
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
  }
}

class MadrassaMotionBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final List<String> titles;
  final List<Widget> icons;
  final List<Widget> activeIcons;
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
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final activeGradient = isDark
        ? const LinearGradient(colors: [Color(0xFF0D9488), Color(0xFF14B8A6)])
        : const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0D9488)]);
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: borderColor, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: List.generate(titles.length, (i) {
              final isSelected = selectedIndex == i;
              return Expanded(
                flex: isSelected ? 2 : 1,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTabSelected(i);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      gradient: isSelected ? activeGradient : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.35),
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
                          scale: isSelected ? 1.1 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: IconTheme(
                            data: IconThemeData(
                              size: 20,
                              color: isSelected ? Colors.white : inactiveColor,
                            ),
                            child: isSelected ? activeIcons[i] : icons[i],
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
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
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
