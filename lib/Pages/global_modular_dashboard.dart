// lib/pages/global_modular_dashboard.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import '../models/module_registry.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import 'settings_page.dart';
import 'support_page.dart';
import '../widgets/global_module_wrapper.dart';
import '../services/sync_service.dart';
import 'admin/data_cleanup_screen.dart';

const String _kGlobalBranchId = 'all';

// ── Category filter enum ──────────────────────────────────────────────────────

enum DashboardCategoryFilter {
  overall,
  office,
  dispensary,
  dasterkhwaan,
  madrassa,
}

// ── Page ──────────────────────────────────────────────────────────────────────

class GlobalModularDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const GlobalModularDashboard({super.key, required this.userData});

  @override
  State<GlobalModularDashboard> createState() => _GlobalModularDashboardState();
}

class _GlobalModularDashboardState extends State<GlobalModularDashboard>
    with TickerProviderStateMixin {
  late List<AppModule> _availableModules;
  late String _userName;
  late String _role;

  DashboardCategoryFilter _selectedCategory = DashboardCategoryFilter.overall;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _searchOpen = false;

  List<AppModule> _cachedFilteredModules = [];
  Timer? _searchDebounce;

  // ── Animation controllers ─────────────────────────────────────────────────
  late AnimationController _pageEntryCtrl;
  late AnimationController _heroCtrl;
  late AnimationController _sidebarCtrl;
  late AnimationController _searchAnimCtrl;
  late AnimationController _logoPulseCtrl;

  late Animation<double> _pageOpacity;
  late Animation<Offset> _heroSlide;
  late Animation<double> _heroFade;
  late Animation<double> _searchExpand;
  late Animation<double> _logoPulseAnim;

  @override
  void initState() {
    super.initState();
    _role = (widget.userData['role'] as String? ?? 'unknown').toLowerCase();
    _userName = widget.userData['name'] ?? widget.userData['username'] ?? 'User';

    final allModules = ModuleRegistry.getAvailableModules(_role);
    if (_role == 'ceo') {
      _availableModules = allModules
          .where((m) =>
              m.id == 'executive_dashboard' ||
              m.id == 'kitchen' ||
              m.id == 'madrassa_admin')
          .toList();
    } else {
      _availableModules = _isFullExecutive
          ? allModules.where((m) => !m.hideFromExecutives).toList()
          : allModules;
    }

    // ── START SYNC SERVICE ────────────────────────────────────────────────────
    final branchId = (widget.userData['branchId'] as String? ?? '').trim();
    if (branchId.isNotEmpty && branchId != _kGlobalBranchId) {
      SyncService().start(branchId);
    }
    // ─────────────────────────────────────────────────────────────────────────

    _pageEntryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _pageOpacity =
        CurvedAnimation(parent: _pageEntryCtrl, curve: Curves.easeOut);

    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 680));
    _heroSlide =
        Tween<Offset>(begin: const Offset(0, 0.07), end: Offset.zero).animate(
            CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));
    _heroFade =
        CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);

    _sidebarCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));

    _searchAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _searchExpand =
        CurvedAnimation(parent: _searchAnimCtrl, curve: Curves.easeOutCubic);

    _logoPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3));
    _logoPulseAnim = Tween<double>(begin: 1.0, end: 1.07)
        .animate(CurvedAnimation(parent: _logoPulseCtrl, curve: Curves.easeInOut));
    _logoPulseCtrl.repeat(reverse: true);

    // Staggered entrance
    _pageEntryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 80),
        () { if (mounted) _heroCtrl.forward(); });
    Future.delayed(const Duration(milliseconds: 160),
        () { if (mounted) _sidebarCtrl.forward(); });

    _recomputeFilteredModules();
  }

  // ── Role helpers ──────────────────────────────────────────────────────────

  bool get _isGlobalExecutive =>
      ['ceo', 'chairman', 'global user'].contains(_role);

  bool get _isFullExecutive {
    const execRoles = [
      'admin', 'global admin', 'ceo', 'chairman',
      'global user', 'manager', 'hq manager',
    ];
    return execRoles.contains(_role);
  }

  bool get _isSupervisor => _role == 'supervisor';
  bool get _isBranchManager => _role == 'branch manager';

  /// Categories visible to this role (branch manager hides madrassa).
  List<DashboardCategoryFilter> get _visibleCategories =>
      _isBranchManager
          ? DashboardCategoryFilter.values
              .where((c) => c != DashboardCategoryFilter.madrassa)
              .toList()
          : DashboardCategoryFilter.values;

  /// Desktop sidebar shows category nav for full-exec/branch-manager,
  /// module tiles for supervisor.
  bool get _sidebarShowsCategories =>
      (_isFullExecutive && _role != 'ceo') || _isBranchManager;

  bool get _mobileShowsCategoryChips =>
      (_isFullExecutive && _role != 'ceo') || _isBranchManager;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _pageEntryCtrl.dispose();
    _heroCtrl.dispose();
    _sidebarCtrl.dispose();
    _searchAnimCtrl.dispose();
    _logoPulseCtrl.dispose();
    super.dispose();
  }

  void _recomputeFilteredModules() {
    Iterable<AppModule> filtered = _availableModules;
    if (_selectedCategory != DashboardCategoryFilter.overall) {
      final targetCat = ModuleCategory.values
          .firstWhere((c) => c.name == _selectedCategory.name);
      filtered = filtered.where((m) => m.category == targetCat);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((m) =>
          m.title.toLowerCase().contains(q) ||
          m.description.toLowerCase().contains(q));
    }
    _cachedFilteredModules = filtered.toList();
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    _searchOpen
        ? _searchAnimCtrl.forward()
        : _searchAnimCtrl.reverse();
    if (!_searchOpen) {
      _searchCtrl.clear();
      setState(() {
        _searchQuery = '';
        _recomputeFilteredModules();
      });
    }
  }

  void _changeCategory(DashboardCategoryFilter cat) {
    setState(() {
      _selectedCategory = cat;
      _searchCtrl.clear();
      _searchQuery = '';
      _searchDebounce?.cancel();
      _recomputeFilteredModules();
    });
  }

  void _openModule(AppModule module) {
    const wrappedRoles = [
      'admin', 'global admin', 'ceo', 'chairman',
      'global user', 'manager', 'hq manager',
      'supervisor', 'branch manager',
    ];
    final isWrapped = wrappedRoles.contains(_role);
    final dest = (isWrapped && module.supportsGlobalWrapper)
        ? GlobalModuleWrapper(module: module, userData: widget.userData)
        : module.builder(context, widget.userData);

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => dest,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0.025, 0), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final roleTheme = RoleThemeData.fromString(_role);
    Color? customColor;
    final prefColorStr = widget.userData['preferredColor'] as String?;
    if (prefColorStr != null && prefColorStr.isNotEmpty) {
      try {
        final hex = prefColorStr.replaceAll('#', '');
        customColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }

    return RoleThemeScope(
      role: roleTheme,
      child: Builder(builder: (ctx) {
        final t = RoleThemeData.of(roleTheme, customColor);
        final isDesktop = MediaQuery.of(ctx).size.width >= 900;

        return FadeTransition(
          opacity: _pageOpacity,
          child: Scaffold(
            backgroundColor: t.bg,
            body: isDesktop
                ? Row(children: [
                    _Sidebar(state: this, t: t),
                    Expanded(
                        child:
                            _MainContent(state: this, t: t, isDesktop: true)),
                  ])
                : _MobileLayout(state: this, t: t),
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sidebar  (desktop)
// ═══════════════════════════════════════════════════════════════════════════════

class _Sidebar extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  const _Sidebar({required this.state, required this.t});

  bool get _dark => state._isGlobalExecutive;
  Color get _bg => _dark ? const Color(0xFF0D1117) : t.bgCard;
  Color get _divider => _dark ? const Color(0xFF30363D) : t.bgRule;
  Color get _muted => _dark ? const Color(0xFF8B949E) : t.textTertiary;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state._sidebarCtrl,
      builder: (ctx, _) => FadeTransition(
        opacity: state._sidebarCtrl,
        child: SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(-0.05, 0), end: Offset.zero)
              .animate(CurvedAnimation(
                  parent: state._sidebarCtrl,
                  curve: Curves.easeOutCubic)),
          child: Container(
            width: 240,
            decoration: BoxDecoration(
              color: _bg,
              border: Border(right: BorderSide(color: _divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SidebarBrand(state: state, t: t, dark: _dark),
                Divider(color: _divider, height: 1),
                const SizedBox(height: 14),
                _buildNav(context),
                const Spacer(),
                Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
                _SidebarActions(state: state, t: t, dark: _dark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNav(BuildContext context) {
    // ── Supervisor: module tiles ─────────────────────────────────────────────
    if (state._isSupervisor) {
      return Expanded(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _NavLabel(label: 'MY MODULES', muted: _muted),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: state._availableModules.length,
              itemBuilder: (ctx, i) => _AnimatedEntry(
                index: i,
                ctrl: state._sidebarCtrl,
                child: _SidebarModuleTile(
                  module: state._availableModules[i],
                  t: t,
                  dark: _dark,
                  onTap: () => state._openModule(state._availableModules[i]),
                ),
              ),
            ),
          ),
        ]),
      );
    }

    // ── Full exec / branch manager: category nav ─────────────────────────────
    if (state._sidebarShowsCategories) {
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: _NavLabel(label: 'NAVIGATE', muted: _muted),
        ),
        ...state._visibleCategories.asMap().entries.map((e) =>
            _AnimatedEntry(
              index: e.key,
              ctrl: state._sidebarCtrl,
              child: _SidebarCatItem(
                cat: e.value,
                selected: state._selectedCategory == e.value,
                t: t,
                dark: _dark,
                onTap: () => state._changeCategory(e.value),
              ),
            )),
        const SizedBox(height: 8),
      ]);
    }

    return const SizedBox.shrink();
  }
}

// ── Sidebar brand section ─────────────────────────────────────────────────────

class _SidebarBrand extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool dark;
  const _SidebarBrand(
      {required this.state, required this.t, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _LogoPulse(accent: t.accent, pulseAnim: state._logoPulseAnim, size: 50),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GMWF',
                style: TextStyle(
                    color: dark ? Colors.white : t.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1)),
            Text('System',
                style: TextStyle(
                    color: dark
                        ? const Color(0xFF8B949E)
                        : t.textTertiary,
                    fontSize: 10)),
          ]),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: t.accent.withOpacity(dark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.accent.withValues(alpha: 0.3)),
          ),
          child: Text(
            state._role.toUpperCase(),
            style: TextStyle(
                color: t.accent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          state._userName,
          style: TextStyle(
              color: dark ? Colors.white : t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ]),
    );
  }
}

// ── Sidebar bottom actions ────────────────────────────────────────────────────

class _SidebarActions extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool dark;
  const _SidebarActions(
      {required this.state, required this.t, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      child: Column(children: [
        _ActionTile(
          icon: Icons.settings_outlined,
          label: 'Settings',
          t: t,
          dark: dark,
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      SettingsPage(userData: state.widget.userData))),
        ),
        if (state._isFullExecutive)
          _ActionTile(
            icon: Icons.cleaning_services_outlined,
            label: 'Data Integrity',
            t: t,
            dark: dark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataCleanupScreen()),
            ),
          ),
        _ActionTile(
          icon: Icons.help_outline_rounded,
          label: 'Support',
          t: t,
          dark: dark,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SupportPage())),
        ),
        _ActionTile(
          icon: Icons.logout_rounded,
          label: 'Sign Out',
          t: t,
          dark: dark,
          danger: true,
          onTap: state._logout,
        ),
      ]),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _NavLabel extends StatelessWidget {
  final String label;
  final Color muted;
  const _NavLabel({required this.label, required this.muted});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(label,
            style: TextStyle(
                color: muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
      );
}

// ── Staggered entry wrapper ───────────────────────────────────────────────────

class _AnimatedEntry extends StatelessWidget {
  final int index;
  final AnimationController ctrl;
  final Widget child;
  const _AnimatedEntry(
      {required this.index, required this.ctrl, required this.child});

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.07).clamp(0.0, 0.65);
    final end = (start + 0.35).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
        parent: ctrl,
        curve: Interval(start, end, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: anim,
      builder: (ctx, ch) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(-0.08, 0), end: Offset.zero)
              .animate(anim),
          child: ch,
        ),
      ),
      child: child,
    );
  }
}

// ── Logo pulse ────────────────────────────────────────────────────────────────

class _LogoPulse extends StatelessWidget {
  final Color accent;
  final Animation<double> pulseAnim;
  final double size;
  const _LogoPulse({required this.accent, required this.pulseAnim, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: pulseAnim,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.2),
          boxShadow: [
            BoxShadow(
                color: accent.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          'assets/logo/gmwf-1.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

// ── Sidebar category item ─────────────────────────────────────────────────────

class _SidebarCatItem extends StatefulWidget {
  final DashboardCategoryFilter cat;
  final bool selected;
  final RoleThemeData t;
  final bool dark;
  final VoidCallback onTap;
  const _SidebarCatItem({
    required this.cat,
    required this.selected,
    required this.t,
    required this.dark,
    required this.onTap,
  });

  @override
  State<_SidebarCatItem> createState() => _SidebarCatItemState();
}

class _SidebarCatItemState extends State<_SidebarCatItem> {
  bool _hov = false;

  static const _icons = {
    DashboardCategoryFilter.overall: Icons.grid_view_rounded,
    DashboardCategoryFilter.office: Icons.business_center_outlined,
    DashboardCategoryFilter.dispensary: Icons.local_pharmacy_outlined,
    DashboardCategoryFilter.dasterkhwaan: Icons.restaurant_outlined,
    DashboardCategoryFilter.madrassa: Icons.menu_book_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final sel = widget.selected;
    final dark = widget.dark;
    final label = widget.cat == DashboardCategoryFilter.overall
        ? 'All Modules'
        : widget.cat.name[0].toUpperCase() + widget.cat.name.substring(1);

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? (dark ? t.accent.withValues(alpha: 0.18) : t.glassTint)
                : (_hov ? (dark ? Colors.white.withValues(alpha: 0.04) : t.accent.withValues(alpha: 0.05)) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? t.accent.withValues(alpha: 0.4) : Colors.transparent,
            ),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: sel ? t.accentGradient : null,
                color: !sel
                    ? (dark
                        ? const Color(0xFF21262D)
                        : t.accent.withValues(alpha: 0.08))
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _icons[widget.cat] ?? Icons.circle_outlined,
                color: sel
                    ? Colors.white
                    : (dark ? const Color(0xFF8B949E) : t.textTertiary),
                size: 15,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: sel
                          ? (dark ? Colors.white : t.textPrimary)
                          : (dark ? const Color(0xFF8B949E) : t.textSecondary),
                      fontWeight:
                          sel ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13.5)),
            ),
            if (sel)
              AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                    color: t.accent, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.5), blurRadius: 4)]),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── Sidebar module tile (supervisor) ─────────────────────────────────────────

class _SidebarModuleTile extends StatefulWidget {
  final AppModule module;
  final RoleThemeData t;
  final bool dark;
  final VoidCallback onTap;
  const _SidebarModuleTile({
    required this.module,
    required this.t,
    required this.dark,
    required this.onTap,
  });

  @override
  State<_SidebarModuleTile> createState() => _SidebarModuleTileState();
}

class _SidebarModuleTileState extends State<_SidebarModuleTile> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final dark = widget.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hov
                ? (dark ? t.accent.withValues(alpha: 0.12) : t.accent.withValues(alpha: 0.06))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _hov ? t.accent.withValues(alpha: 0.3) : Colors.transparent),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: _hov ? t.accentGradient : null,
                color: !_hov
                    ? (dark ? const Color(0xFF21262D) : t.accent.withValues(alpha: 0.08))
                    : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.module.icon,
                color: _hov
                    ? Colors.white
                    : (dark ? const Color(0xFF8B949E) : t.textTertiary),
                size: 15,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.module.title,
                style: TextStyle(
                  color: _hov
                      ? (dark ? Colors.white : t.textPrimary)
                      : (dark ? const Color(0xFFB1BAC4) : t.textSecondary),
                  fontWeight: _hov ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AnimatedOpacity(
              opacity: _hov ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.arrow_forward_ios_rounded,
                  color: t.accent, size: 12),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Sidebar action tile ───────────────────────────────────────────────────────

class _ActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final RoleThemeData t;
  final bool dark;
  final bool danger;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.t,
    required this.dark,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final col = widget.danger
        ? Colors.redAccent
        : (widget.dark ? const Color(0xFF8B949E) : widget.t.textSecondary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _hov
                ? (widget.danger
                    ? Colors.redAccent.withValues(alpha: 0.08)
                    : widget.t.accent.withValues(alpha: 0.07))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(widget.icon, color: col, size: 16),
            const SizedBox(width: 10),
            Text(widget.label,
                style: TextStyle(
                    color: col,
                    fontSize: 13,
                    fontWeight:
                        widget.danger ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mobile layout
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileLayout extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  const _MobileLayout({required this.state, required this.t});

  bool get _dark => state._isGlobalExecutive;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.bg,
      appBar: _buildAppBar(context),
      drawer: _buildDrawer(context),
      body: _MainContent(state: state, t: t, isDesktop: false),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _dark ? const Color(0xFF0D1117) : t.bgCard,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: Icon(Icons.menu_rounded,
              color: _dark ? Colors.white : t.textPrimary),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Row(children: [
        _LogoPulse(accent: t.accent, pulseAnim: state._logoPulseAnim),
        const SizedBox(width: 8),
        Text('GMWF',
            style: TextStyle(
                color: _dark ? Colors.white : t.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 1)),
      ]),
      actions: [
        IconButton(
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => RotationTransition(
              turns:
                  Tween(begin: 0.85, end: 1.0).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              state._searchOpen
                  ? Icons.close_rounded
                  : Icons.search_rounded,
              key: ValueKey(state._searchOpen),
              color: _dark ? Colors.white70 : t.textSecondary,
            ),
          ),
          onPressed: state._toggleSearch,
        ),
        IconButton(
          icon: Icon(Icons.notifications_none_rounded,
              color: _dark ? Colors.white70 : t.textSecondary),
          onPressed: () {},
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
            height: 1,
            color: _dark ? const Color(0xFF30363D) : t.bgRule),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: _dark ? const Color(0xFF0D1117) : t.bgCard,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: t.accent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        state._role.toUpperCase(),
                        style: TextStyle(
                            color: t.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state._userName,
                      style: TextStyle(
                          color: _dark ? Colors.white : t.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800),
                    ),
                  ]),
            ),
            Divider(
                color: _dark ? const Color(0xFF30363D) : t.bgRule,
                height: 1),
            const SizedBox(height: 8),

            // Supervisor: module list in drawer
            if (state._isSupervisor) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: _NavLabel(
                    label: 'MY MODULES',
                    muted: _dark
                        ? const Color(0xFF8B949E)
                        : t.textTertiary),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: state._availableModules.length,
                  itemBuilder: (ctx, i) {
                    final m = state._availableModules[i];
                    return ListTile(
                      dense: true,
                      leading:
                          Icon(m.icon, color: t.accent, size: 18),
                      title: Text(m.title,
                          style: TextStyle(
                              color: _dark
                                  ? const Color(0xFFE6EDF3)
                                  : t.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      trailing: Icon(Icons.arrow_forward_ios_rounded,
                          color: t.textTertiary, size: 12),
                      onTap: () {
                        Navigator.pop(context);
                        state._openModule(m);
                      },
                    );
                  },
                ),
              ),
            ]
            // Category nav for others
            else if (state._mobileShowsCategoryChips) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: _NavLabel(
                    label: 'NAVIGATE',
                    muted: _dark
                        ? const Color(0xFF8B949E)
                        : t.textTertiary),
              ),
              ...state._visibleCategories.map((cat) => _SidebarCatItem(
                    cat: cat,
                    selected: state._selectedCategory == cat,
                    t: t,
                    dark: _dark,
                    onTap: () {
                      state._changeCategory(cat);
                      Navigator.pop(context);
                    },
                  )),
              const Expanded(child: SizedBox.shrink()),
            ] else
              const Expanded(child: SizedBox.shrink()),

            Divider(
                color: _dark ? const Color(0xFF30363D) : t.bgRule,
                height: 1),
            _ActionTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              t: t,
              dark: _dark,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SettingsPage(
                            userData: state.widget.userData)));
              },
            ),
            _ActionTile(
              icon: Icons.help_outline_rounded,
              label: 'Support',
              t: t,
              dark: _dark,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SupportPage()));
              },
            ),
            _ActionTile(
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              t: t,
              dark: _dark,
              danger: true,
              onTap: state._logout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Main content  (shared desktop / mobile)
// ═══════════════════════════════════════════════════════════════════════════════

class _MainContent extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool isDesktop;
  const _MainContent(
      {required this.state, required this.t, required this.isDesktop});

  bool get _dark => state._isGlobalExecutive;
  bool get _showMobileChips =>
      !isDesktop && state._mobileShowsCategoryChips && !state._isSupervisor;

  @override
  Widget build(BuildContext context) {
    final filtered = state._cachedFilteredModules;
    final double hPad = isDesktop ? 36 : 20;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _HeroHeader(state: state, t: t, isDesktop: isDesktop),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
            child: _SearchBar(state: state, t: t),
          ),
        ),
        if (_showMobileChips)
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
              child: _CategoryChips(state: state, t: t),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 14),
            child: _SectionLabel(
                state: state, t: t, count: filtered.length, isDesktop: isDesktop),
          ),
        ),
        filtered.isEmpty
            ? SliverToBoxAdapter(
                child: _EmptySearch(state: state, t: t, hPad: hPad))
            : SliverPadding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 56),
                sliver: _ModuleGrid(
                    state: state,
                    t: t,
                    modules: filtered,
                    isDesktop: isDesktop),
              ),
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final int count;
  final bool isDesktop;
  const _SectionLabel({
    required this.state,
    required this.t,
    required this.count,
    required this.isDesktop,
  });

  bool get _dark => state._isGlobalExecutive;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your Modules',
              style: TextStyle(
                  color: _dark ? const Color(0xFFE6EDF3) : t.textPrimary,
                  fontSize: isDesktop ? 20 : 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text('$count available',
                key: ValueKey(count),
                style: TextStyle(
                    color: _dark ? const Color(0xFF8B949E) : t.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
        Container(
          height: 3,
          width: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [t.accent, t.accent.withValues(alpha: 0.0)]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Hero header
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroHeader extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool isDesktop;
  const _HeroHeader({required this.state, required this.t, required this.isDesktop});

  bool get _dark => state._isGlobalExecutive;

  @override
  Widget build(BuildContext context) {
    final hPad = isDesktop ? 36.0 : 20.0;
    return FadeTransition(
      opacity: state._heroFade,
      child: SlideTransition(
        position: state._heroSlide,
        child: _dark
            ? _DarkHero(state: state, t: t, isDesktop: isDesktop, hPad: hPad)
            : _LightHero(state: state, t: t, isDesktop: isDesktop, hPad: hPad),
      ),
    );
  }
}

// ── Dark hero (Chairman / CEO / Global User) ──────────────────────────────────
class _DarkHero extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool isDesktop;
  final double hPad;
  const _DarkHero({required this.state, required this.t, required this.isDesktop, required this.hPad});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${_weekday(now.weekday)}, ${now.day} ${_month(now.month)} ${now.year}';

    return Container(
      margin: EdgeInsets.fromLTRB(hPad, isDesktop ? 36 : 24, hPad, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF30363D)),
        boxShadow: [
          BoxShadow(color: t.accent.withValues(alpha: 0.12), blurRadius: 40, offset: const Offset(0, 12)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Subtle accent glow top-right
          Positioned(
            top: -60, right: -60,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  t.accent.withValues(alpha: 0.12),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isDesktop ? 28 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: role badge + time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: t.accent.withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(color: t.accent.withValues(alpha: 0.05), blurRadius: 8)
                        ],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8,
                          decoration: BoxDecoration(
                            gradient: t.accentGradient,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.4), blurRadius: 4)],
                          )),
                        const SizedBox(width: 8),
                        Text(state._role.toUpperCase(),
                          style: TextStyle(color: t.accent, fontSize: 10.5,
                            fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Name
                Text(state._userName,
                  style: TextStyle(
                    color: const Color(0xFFE6EDF3),
                    fontSize: isDesktop ? 32 : 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(dateStr,
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
                const SizedBox(height: 20),
                // Live stat pills
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: [
                    _StatPill(label: '${state._availableModules.length} Modules',
                      icon: Icons.grid_view_rounded, t: t),
                    _StatPill(label: 'Global Access',
                      icon: Icons.public_rounded, t: t),
                    _StatPill(label: 'Live',
                      icon: Icons.circle, t: t, pulse: true),
                  ],
                ),
              ],
            ),
          ),
          // Avatar top-right on desktop
          if (isDesktop)
            Positioned(
              top: 28, right: 28,
              child: _AvatarMenu(state: state, t: t, dark: true),
            ),
        ],
      ),
    );
  }

  String _weekday(int d) => ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d-1];
  String _month(int m) => ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'][m-1];
}

// ── Light hero (Manager / HQ / Branch / Admin / Supervisor) ──────────────────
class _LightHero extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool isDesktop;
  final double hPad;
  const _LightHero({required this.state, required this.t, required this.isDesktop, required this.hPad});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${_weekday(now.weekday)}, ${now.day} ${_month(now.month)} ${now.year}';
    final greeting = _greeting(now.hour);

    return Container(
      margin: EdgeInsets.fromLTRB(hPad, isDesktop ? 36 : 24, hPad, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.accent, t.accentLight.withBlue(t.accentLight.blue + 10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 14)),
          BoxShadow(color: Colors.white.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative circles
          Positioned(right: -40, top: -40,
            child: Container(width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07)))),
          Positioned(right: 60, bottom: -20,
            child: Container(width: 100, height: 100,
              decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05)))),
          Padding(
            padding: EdgeInsets.all(isDesktop ? 28 : 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Greeting
                      Text(greeting,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75),
                          fontSize: isDesktop ? 14 : 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(state._userName,
                        style: TextStyle(color: Colors.white,
                          fontSize: isDesktop ? 30 : 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1, height: 1.1),
                      ),
                      const SizedBox(height: 6),
                      Text(dateStr,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                      const SizedBox(height: 18),
                      // Role + module count pills
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        _WhitePill(label: state._role.toUpperCase(),
                          icon: Icons.verified_user_rounded, t: t),
                        _WhitePill(
                          label: '${state._availableModules.length} Modules',
                          icon: Icons.grid_view_rounded, t: t),
                      ]),
                    ],
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 20),
                  _AvatarMenu(state: state, t: t, dark: false),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _greeting(int hour) {
    if (hour < 12) return '☀️  Good morning';
    if (hour < 17) return '🌤  Good afternoon';
    return '🌙  Good evening';
  }
  String _weekday(int d) => ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d-1];
  String _month(int m) => ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'][m-1];
}

// ── Shared pill widgets ───────────────────────────────────────────────────────

class _StatPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final RoleThemeData t;
  final bool pulse;
  const _StatPill({required this.label, required this.icon,
    required this.t, this.pulse = false});
  @override State<_StatPill> createState() => _StatPillState();
}

class _StatPillState extends State<_StatPill> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _a = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
    if (widget.pulse) _c.repeat(reverse: true);
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        widget.pulse
            ? AnimatedBuilder(
                animation: _a,
                builder: (_, __) => Opacity(
                  opacity: _a.value,
                  child: Icon(widget.icon, size: 8, color: widget.t.accent),
                ))
            : Icon(widget.icon, size: 12, color: widget.t.accent),
        const SizedBox(width: 6),
        Text(widget.label,
          style: const TextStyle(color: Color(0xFFE6EDF3),
            fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _WhitePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final RoleThemeData t;
  const _WhitePill({required this.label, required this.icon, required this.t});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(color: Colors.white,
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ]),
    );
  }
}



// ── Avatar popup ──────────────────────────────────────────────────────────────

class _AvatarMenu extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool dark;
  const _AvatarMenu(
      {required this.state, required this.t, required this.dark});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 54),
      color: dark ? const Color(0xFF161B22) : t.bgCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: dark ? const Color(0xFF30363D) : t.bgRule)),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.accent.withValues(alpha: 0.4), width: 2),
          gradient: dark
              ? LinearGradient(colors: [
                  t.accent.withValues(alpha: 0.3),
                  t.accent.withValues(alpha: 0.1),
                ])
              : null,
        ),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: t.accentMuted,
          child: Text(
            state._userName.isNotEmpty
                ? state._userName[0].toUpperCase()
                : 'U',
            style: TextStyle(
                color: t.accent,
                fontWeight: FontWeight.w900,
                fontSize: 16),
          ),
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(state._userName,
                style: TextStyle(
                    color: dark ? const Color(0xFFE6EDF3) : t.textPrimary,
                    fontWeight: FontWeight.bold)),
            Text(state._role.toUpperCase(),
                style: TextStyle(
                    color: t.accent, fontSize: 10, fontWeight: FontWeight.w700)),
            const Divider(),
          ]),
        ),
        _pmi(Icons.settings_outlined, 'settings', dark, t),
        _pmi(Icons.help_outline_rounded, 'support', dark, t),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 17),
            SizedBox(width: 12),
            Text('Sign Out',
                style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ]),
        ),
      ],
      onSelected: (v) {
        if (v == 'settings') {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      SettingsPage(userData: state.widget.userData)));
        } else if (v == 'support') {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SupportPage()));
        } else if (v == 'logout') {
          state._logout();
        }
      },
    );
  }

  PopupMenuItem<String> _pmi(
      IconData icon, String value, bool dark, RoleThemeData t) {
    final label = value[0].toUpperCase() + value.substring(1);
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon,
            color: dark ? const Color(0xFF8B949E) : t.textSecondary,
            size: 17),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                color: dark ? const Color(0xFFE6EDF3) : t.textPrimary,
                fontSize: 13)),
      ]),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  const _SearchBar({required this.state, required this.t});

  bool get _dark => state._isGlobalExecutive;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile && !state._searchOpen) return const SizedBox.shrink();

    return SizeTransition(
      sizeFactor: isMobile
          ? state._searchExpand
          : const AlwaysStoppedAnimation(1.0),
      axisAlignment: -1,
      child: FadeTransition(
        opacity: isMobile
            ? state._searchExpand
            : const AlwaysStoppedAnimation(1.0),
        child: Container(
          decoration: BoxDecoration(
            color: _dark ? const Color(0xFF161B22) : t.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: _dark ? const Color(0xFF30363D) : t.bgRule,
                width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: TextField(
            controller: state._searchCtrl,
            autofocus: isMobile && state._searchOpen,
            onChanged: (v) {
              state._searchDebounce?.cancel();
              state._searchDebounce = Timer(const Duration(milliseconds: 220), () {
                state.setState(() => state._searchQuery = v.trim());
                state._recomputeFilteredModules();
              });
            },
            style: TextStyle(
                color: _dark ? const Color(0xFFE6EDF3) : t.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Search modules…',
              hintStyle: TextStyle(
                  color: _dark ? const Color(0xFF8B949E) : t.textTertiary,
                  fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded,
                  color: _dark ? const Color(0xFF8B949E) : t.textTertiary,
                  size: 20),
              suffixIcon: state._searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: _dark
                              ? const Color(0xFF8B949E)
                              : t.textTertiary,
                          size: 18),
                      onPressed: () => state.setState(() {
                            state._searchCtrl.clear();
                            state._searchQuery = '';
                            state._recomputeFilteredModules();
                          }),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 16, horizontal: 8),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Category chips (mobile) ───────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  const _CategoryChips({required this.state, required this.t});

  bool get _dark => state._isGlobalExecutive;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: state._visibleCategories.map((cat) {
          final sel = state._selectedCategory == cat;
          final label = cat == DashboardCategoryFilter.overall
              ? 'All'
              : cat.name[0].toUpperCase() + cat.name.substring(1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: ChoiceChip(
                label: Text(label),
                selected: sel,
                onSelected: (v) { if (v) state._changeCategory(cat); },
                selectedColor:
                    _dark ? t.accent.withValues(alpha: 0.2) : t.accent,
                labelStyle: TextStyle(
                    color: sel
                        ? (_dark ? t.accent : Colors.white)
                        : (_dark
                            ? const Color(0xFF8B949E)
                            : t.textSecondary),
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12),
                backgroundColor:
                    _dark ? const Color(0xFF161B22) : t.bgCard,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                        color: sel
                            ? t.accent
                            : (_dark
                                ? const Color(0xFF30363D)
                                : t.bgRule))),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Empty search ──────────────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final double hPad;
  const _EmptySearch(
      {required this.state, required this.t, required this.hPad});

  bool get _dark => state._isGlobalExecutive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 60),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (ctx, v, ch) => Opacity(
            opacity: v,
            child: Transform.translate(
                offset: Offset(0, 14 * (1 - v)), child: ch),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _dark ? const Color(0xFF161B22) : t.accentMuted.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                border: Border.all(
                    color: _dark ? const Color(0xFF30363D) : t.bgRule),
              ),
              child: Icon(Icons.search_off_rounded,
                  size: 32,
                  color: _dark ? const Color(0xFF8B949E) : t.textTertiary),
            ),
            const SizedBox(height: 16),
            Text('No modules found',
                style: TextStyle(
                    color: _dark ? const Color(0xFFE6EDF3) : t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('"${state._searchQuery}" didn\'t match anything',
                style: TextStyle(
                    color: _dark ? const Color(0xFF8B949E) : t.textTertiary,
                    fontSize: 13)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => state.setState(() {
                state._searchCtrl.clear();
                state._searchQuery = '';
                state._recomputeFilteredModules();
              }),
              style: TextButton.styleFrom(
                foregroundColor: t.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: t.accent.withValues(alpha: 0.4))),
              ),
              child: const Text('Clear search',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Module grid
// ═══════════════════════════════════════════════════════════════════════════════

class _ModuleGrid extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final List<AppModule> modules;
  final bool isDesktop;
  const _ModuleGrid({
    required this.state,
    required this.t,
    required this.modules,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cols = w < 480 ? 2 : w < 700 ? 2 : w < 1100 ? 3 : 4;

    // AnimatedSwitcher cross-fades the entire grid when the category changes.
    return SliverToBoxAdapter(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: _buildGrid(context, cols, w),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, int cols, double w) {
  final heroModules = modules.where((m) => m.isFeatured).toList();
  final restModules = heroModules.isEmpty ? modules : modules.where((m) => !m.isFeatured).toList();

  return Column(
    key: ValueKey(state._selectedCategory),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Hero row — 2 cols always, taller aspect ratio
      if (heroModules.isNotEmpty)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: w < 480 ? 1 : 2,
            crossAxisSpacing: isDesktop ? 18 : 12,
            mainAxisSpacing: isDesktop ? 18 : 12,
            childAspectRatio: w < 480 ? 2.2 : 1.8,
          ),
          itemCount: heroModules.length,
          itemBuilder: (ctx, i) {
            final delayMs = (i * 45).clamp(0, 200);
            return TweenAnimationBuilder<double>(
              key: ValueKey('hero_${state._selectedCategory}_$i'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 320 + delayMs),
              curve: Curves.easeOutCubic,
              builder: (ctx, v, ch) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: ch),
              ),
              child: _ModuleCard(
                module: heroModules[i],
                t: t,
                dark: state._isGlobalExecutive,
                isDesktop: isDesktop,
                isHero: true,
                onTap: () => state._openModule(heroModules[i]),
              ),
            );
          },
        ),

      // Secondary modules — normal compact grid
      if (restModules.isNotEmpty) ...[
        if (heroModules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: Row(children: [
              Container(width: 3, height: 14,
                decoration: BoxDecoration(
                  color: t.accent, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('MORE MODULES',
                style: TextStyle(color: state._isGlobalExecutive
                    ? const Color(0xFF8B949E) : t.textTertiary,
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ]),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: isDesktop ? 18 : 12,
            mainAxisSpacing: isDesktop ? 18 : 12,
            childAspectRatio: w < 480 ? 0.9 : 1.35,
          ),
          itemCount: restModules.length,
          itemBuilder: (ctx, i) {
            final delayMs = (i * 40).clamp(0, 400);
            return TweenAnimationBuilder<double>(
              key: ValueKey('rest_${state._selectedCategory}_$i'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 360 + delayMs),
              curve: Curves.easeOutCubic,
              builder: (ctx, v, ch) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: ch),
              ),
              child: _ModuleCard(
                module: restModules[i],
                t: t,
                dark: state._isGlobalExecutive,
                isDesktop: isDesktop,
                isHero: false,
                onTap: () => state._openModule(restModules[i]),
              ),
            );
          },
        ),
      ],
    ],
  );
}
}

// ── Module card ───────────────────────────────────────────────────────────────

class _ModuleCard extends StatefulWidget {
  final AppModule module;
  final RoleThemeData t;
  final bool dark;
  final bool isDesktop;
  final bool isHero;
  final VoidCallback onTap;
  const _ModuleCard({
    required this.module,
    required this.t,
    required this.dark,
    required this.isDesktop,
    required this.onTap,
    this.isHero = false,
  });

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard>
    with SingleTickerProviderStateMixin {
  bool _hov = false;
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 140));
    _pressScale = Tween<double>(begin: 1.0, end: 0.96).animate(
        CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final dark = widget.dark;
    final tiny = MediaQuery.of(context).size.width < 480;

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() {
        _hov = false;
        _pressCtrl.reverse();
      }),
      child: GestureDetector(
        onTapDown: (_) => _pressCtrl.forward(),
        onTapUp: (_) => _pressCtrl.reverse(),
        onTapCancel: () => _pressCtrl.reverse(),
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _pressScale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translate(0.0, _hov ? -5.0 : 0.0),
            padding: EdgeInsets.all(widget.isHero ? (widget.isDesktop ? 24 : 18) : (tiny ? 14 : 20)),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF161B22) : t.bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _hov
                    ? t.accent.withValues(alpha: 0.5)
                    : (dark ? const Color(0xFF30363D) : t.bgRule),
                width: _hov ? 1.5 : 1,
              ),
              boxShadow: _hov
                  ? [
                      BoxShadow(
                          color: t.accent.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 10)),
                      BoxShadow(
                          color: t.accent.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2)),
                    ]
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4)),
                    ],
            ),
            child: Stack(
              children: [
                // Subtle corner accent on hover
                if (_hov)
                  Positioned(
                    top: -20, right: -20,
                    child: Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.accent.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon box with gradient
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: EdgeInsets.all(tiny ? 10 : 12),
                      decoration: BoxDecoration(
                        gradient: _hov ? t.accentGradient : null,
                        color: !_hov ? (dark ? const Color(0xFF21262D) : t.accent.withValues(alpha: 0.08)) : null,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _hov ? [
                          BoxShadow(color: t.accent.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
                        ] : [],
                      ),
                      child: Icon(
                        widget.module.icon,
                        color: _hov ? Colors.white : t.accent,
                        size: widget.isHero ? 28 : (tiny ? 20 : 24),
                      ),
                    ),

                    const Spacer(),

                    // Title
                    Text(
                      widget.module.title,
                      style: TextStyle(
                        color: dark ? const Color(0xFFE6EDF3) : t.textPrimary,
                        fontSize: widget.isHero ? (widget.isDesktop ? 18 : 16) : (tiny ? 13 : (widget.isDesktop ? 15 : 14)),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (!tiny) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.module.description,
                        style: TextStyle(
                          color: dark ? const Color(0xFF8B949E) : t.textTertiary,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Arrow indicator
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _hov ? t.accent : (dark ? const Color(0xFF21262D) : t.accentMuted),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: _hov ? Colors.white : t.accent,
                          size: 13,
                        ),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}