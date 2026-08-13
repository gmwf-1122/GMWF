// lib/pages/global_modular_dashboard.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../models/module_registry.dart';
import '../theme/app_theme.dart';
import '../theme/role_theme_provider.dart';
import 'settings_page.dart';
import 'support_page.dart';
import '../widgets/global_module_wrapper.dart';
import '../widgets/home_snapshot_widgets.dart';
import '../services/sync_service.dart';
import 'admin/data_cleanup_screen.dart';
import '../services/role_simulator_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/local_storage_service.dart';
import '../services/auth_service.dart';
import '../constants/navigator_key.dart';
import 'login_page.dart';
import '../services/offline_auth_service.dart' as offline_auth;
import '../services/image_upload_service.dart';
import '../services/auto_update_service.dart';
import '../utils/formatters.dart';

const String _kGlobalBranchId = 'all';

// ── Category filter enum ──────────────────────────────────────────────────────

enum DashboardCategoryFilter {
  overall,
  office,
  dispensary,
  dasterkhwaan,
  madrassa,
  school,
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
  void refresh() { if (mounted) setState(() {}); }
  
  String get _userName {
    final email = widget.userData['email']?.toString();
    Map<String, dynamic> data = Map<String, dynamic>.from(widget.userData);
    if (email != null && email.isNotEmpty) {
      try {
        if (Hive.isBoxOpen('local_users')) {
          final user = Hive.box('local_users').get('user:${email.toLowerCase()}');
          if (user != null && user is Map) {
            data.addAll(Map<String, dynamic>.from(user));
          }
        }
      } catch (_) {}
    }
    return resolveUserDisplayName(data);
  }

  String get _userPhotoUrl {
    final email = widget.userData['email']?.toString();
    Map<String, dynamic> data = Map<String, dynamic>.from(widget.userData);
    if (email != null && email.isNotEmpty) {
      try {
        if (Hive.isBoxOpen('local_users')) {
          final user = Hive.box('local_users').get('user:${email.toLowerCase()}');
          if (user != null && user is Map) {
            data.addAll(Map<String, dynamic>.from(user));
          }
        }
      } catch (_) {}
    }
    return (data['profileImage'] ?? data['profilePictureUrl'] ?? data['photoUrl'] ?? data['avatarUrl'])?.toString() ?? '';
  }

  String get _role {
    String r = (widget.userData['role']?.toString() ?? '').toLowerCase().trim();
    if (r.isNotEmpty && r != 'unknown') return r;

    final email = widget.userData['email']?.toString();
    if (email != null && email.isNotEmpty) {
      try {
        if (Hive.isBoxOpen('local_users')) {
          final user = Hive.box('local_users').get('user:${email.toLowerCase()}');
          if (user != null && user is Map) {
            r = (user['role']?.toString() ?? '').toLowerCase().trim();
            if (r.isNotEmpty && r != 'unknown') return r;
          }
        }
      } catch (_) {}
    }

    try {
      if (Hive.isBoxOpen('app_settings')) {
        final currentUserData = Hive.box('app_settings').get('user_data');
        if (currentUserData != null && currentUserData is Map) {
          r = (currentUserData['role']?.toString() ?? '').toLowerCase().trim();
          if (r.isNotEmpty && r != 'unknown') return r;
        }
      }
    } catch (_) {}

    return r.isNotEmpty && r != 'unknown' ? r : 'admin';
  }

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

    final allModules = ModuleRegistry.getAvailableModules(_role);
    if (_role == 'ceo') {
      _availableModules = allModules
          .where((m) =>
              m.id == 'executive_dashboard' ||
              m.id == 'kitchen' ||
              m.id == 'dasterkhwaan_inventory' ||
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
    if (!kIsWeb && (_isGlobalExecutive || _isFullExecutive)) {
      _startBackgroundFullSync();
    }
  }

  // ── Role helpers ──────────────────────────────────────────────────────────

  bool get _isGlobalExecutive =>
      ['ceo', 'chairman', 'global user'].contains(_role);

  /// Whether the user has toggled dark mode in Settings.
  bool get _userDarkMode {
    try {
      if (Hive.isBoxOpen('app_settings')) {
        return Hive.box('app_settings').get('is_dark_mode', defaultValue: false) as bool;
      }
    } catch (_) {}
    return false;
  }

  /// True when the dashboard should render in dark canvas mode.
  bool get _isDark => _isGlobalExecutive || _userDarkMode;

  bool get _isFullExecutive {
    const execRoles = [
      'admin', 'global admin', 'ceo', 'chairman',
      'global user', 'manager', 'hq manager',
    ];
    return execRoles.contains(_role);
  }

  bool get _isSupervisor => _role == 'supervisor';
  bool get _isBranchManager => _role == 'branch manager';

  /// Categories visible to this role.
  List<DashboardCategoryFilter> get _visibleCategories => DashboardCategoryFilter.values;

  /// Desktop sidebar shows category nav for full-exec/branch-manager,
  /// module tiles for supervisor.
  bool get _sidebarShowsCategories =>
      _isFullExecutive || _isBranchManager;

  bool get _mobileShowsCategoryChips =>
      _isFullExecutive || _isBranchManager;

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

  void updateSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
    });
    _recomputeFilteredModules();
  }

  void clearSearch() {
    setState(() {
      _searchCtrl.clear();
      _searchQuery = '';
    });
    _recomputeFilteredModules();
  }

  static bool _hasRunFullBackgroundSync = false;

  Future<void> _startBackgroundFullSync() async {
    if (_hasRunFullBackgroundSync || RoleSimulatorService.isSimulating) return;
    _hasRunFullBackgroundSync = true;
    try {

      final snap = await FirebaseFirestore.instance.collection('branches').get();
      final branches = snap.docs.map((d) => d.id).toList();

      for (final originalBId in branches) {
        final bId = originalBId.toLowerCase().trim();
        // 1. Initial full download if not already complete (patients, inventory, tokens, donations, donors)
        await SyncService().initialFullDownload(bId);

        // 2. Pre-cache dispensary records for the last 30 days
        final now = DateTime.now();
        final start = now.subtract(const Duration(days: 30));
        final end = now.add(const Duration(days: 1));

        final df = DateFormat('ddMMyy');
        final days = <String>[];
        for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
          days.add(df.format(d));
        }

        final missingDays = <String>[];
        for (final day in days) {
          final cached = LocalStorageService.getBranchDayCache(bId, day, 'dispensary');
          if (cached == null) {
            missingDays.add(day);
          }
        }

        if (missingDays.isNotEmpty) {
          // Fetch raw docs in parallel
          final Map<String, List<Map<String, dynamic>>> rawDocsMap = {};
          final fetchRawFutures = missingDays.map((day) async {
            try {
              final snapDocs = await FirebaseFirestore.instance
                  .collection('branches/$bId/dispensary/$day/$day')
                  .get();
              final docs = snapDocs.docs.map((doc) {
                final data = Map<String, dynamic>.from(doc.data());
                data['id'] = doc.id;
                data['_syncDayKey'] = day;
                return data;
              }).toList();
              rawDocsMap[day] = docs;
            } catch (_) {}
          });
          await Future.wait(fetchRawFutures);

          // Combine raw docs
          final List<Map<String, dynamic>> allRawDocs = [];
          for (final dayDocs in rawDocsMap.values) {
            allRawDocs.addAll(dayDocs);
          }

          if (allRawDocs.isNotEmpty) {
            List<Map<String, dynamic>> enrichedAll;
            try {
              enrichedAll = await LocalStorageService.enrichRawDocs(bId, allRawDocs);
            } catch (e) {
              debugPrint('[GlobalModularDashboard] enrichRawDocs failed, using raw docs: $e');
              enrichedAll = allRawDocs.map((d) {
                String firstNonEmpty(List<dynamic> candidates) {
                  for (final c in candidates) {
                    final s = c?.toString().trim() ?? '';
                    if (s.isNotEmpty && s != 'null' && s != 'N/A') return s;
                  }
                  return '';
                }
                return {
                  ...d,
                  'name': firstNonEmpty([d['patientName'], d['name'], 'Unknown']),
                  'phone': d['phone']?.toString() ?? 'N/A',
                  'age': d['age']?.toString() ?? d['patientAge']?.toString() ?? 'N/A',
                  'gender': d['gender']?.toString() ?? d['patientGender']?.toString() ?? 'N/A',
                  'displayCnic': firstNonEmpty([d['patientCnic'], d['cnic'], d['guardianCnic'], 'N/A']),
                  'isChild': (d['guardianCnic'] ?? '').toString().isNotEmpty && (d['patientCnic'] ?? d['cnic'] ?? '').toString().isEmpty,
                  'doctorName': firstNonEmpty([d['doctorName'], d['prescribedBy'], 'Unknown']),
                  'dispenserName': firstNonEmpty([d['dispenserName'], d['dispensedBy'], 'Unknown']),
                  'tokenBy': firstNonEmpty([d['createdByName'], d['tokenBy'], d['createdBy'], 'Unknown']),
                  'daysOfMedicine': (d['daysOfMedicine'] as num?)?.toInt() ?? 1,
                  'frequentFlag': d['frequentFlag'] ?? false,
                };
              }).toList();
            }

            // Group by day and cache
            final Map<String, List<Map<String, dynamic>>> enrichedByDay = {};
            final displayFormat = DateFormat('dd MMM yyyy');

            for (final d in enrichedAll) {
              final day = d['_syncDayKey'] as String? ?? df.format(now);
              d.remove('_syncDayKey');
              d['dispenseDate'] = displayFormat.format(LocalStorageService.parseDdMMyy(day));
              d['type'] = _resolveType(d);
              enrichedByDay.putIfAbsent(day, () => []).add(d);
            }

            for (final day in missingDays) {
              final dayEnriched = enrichedByDay[day] ?? [];
              await LocalStorageService.putBranchDayCache(bId, day, 'dispensary', dayEnriched);
            }
          } else {
            // Write empty cache for days with no records so we don't query Firestore again
            for (final day in missingDays) {
              await LocalStorageService.putBranchDayCache(bId, day, 'dispensary', []);
            }
          }
        }
      }
      debugPrint('[GlobalModularDashboard] Background full branch sync completed successfully.');
    } catch (e) {
      debugPrint('[GlobalModularDashboard] Background full branch sync error: $e');
    }
  }

  String _resolveType(Map<String, dynamic> data) {
    final raw = (data['queueType'] ?? data['type'] ?? '').toString().toLowerCase().trim();
    switch (raw) {
      case 'zakat':     return 'zakat';
      case 'non-zakat': return 'non-zakat';
      case 'gmwf':      return 'gmwf';
      default:          return 'Unknown';
    }
  }

  void _logout() async {
    try {
      await AuthService().signOut();
    } catch (e) {
      debugPrint('[GlobalModularDashboard] Logout error: $e');
    }
    try {
      final navCtx = navigatorKey.currentContext;
      if (navCtx != null) {
        Navigator.of(navCtx, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      } else if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('[GlobalModularDashboard] Logout navigation error: $e');
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
        pageBuilder: (_, anim, _) => dest,
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
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

    return ValueListenableBuilder(
      valueListenable: Hive.box('app_settings').listenable(keys: ['custom_accent_color', 'is_dark_mode']),
      builder: (context, Box box, child) {
        Color? customColor;
        
        // 1. Try local settings override first
        final localHex = box.get('custom_accent_color') as String?;
        if (localHex != null && localHex.isNotEmpty) {
          try {
            final hex = localHex.replaceAll('#', '');
            customColor = Color(int.parse('FF$hex', radix: 16));
          } catch (_) {}
        }
        
        // 2. Fallback to user metadata preference
        if (customColor == null) {
          final prefColorStr = widget.userData['preferredColor'] as String?;
          if (prefColorStr != null && prefColorStr.isNotEmpty) {
            try {
              final hex = prefColorStr.replaceAll('#', '');
              customColor = Color(int.parse('FF$hex', radix: 16));
            } catch (_) {}
          }
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
      },
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

  bool get _dark => state._isDark;
  Color get _bg => _dark ? const Color(0xFF0D1117) : t.bgCard;
  Color get _divider => _dark ? const Color(0xFF30363D) : t.bgRule;
  Color get _muted => _dark ? const Color(0xFFC9D1D9) : t.textTertiary;

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildNav(context),
                    ],
                  ),
                ),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _NavLabel(label: 'MY MODULES', muted: _muted),
          ),
          ...state._availableModules.asMap().entries.map((e) => _AnimatedEntry(
                index: e.key,
                ctrl: state._sidebarCtrl,
                child: _SidebarModuleTile(
                  module: e.value,
                  t: t,
                  dark: _dark,
                  onTap: () => state._openModule(e.value),
                ),
              )),
        ],
      );
    }

    // ── Full exec / branch manager: category nav ─────────────────────────────
    if (state._sidebarShowsCategories) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
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
        ],
      );
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
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
            Row(
              children: [
                Text('System',
                    style: TextStyle(
                        color: dark
                            ? const Color(0xFF8B949E)
                            : t.textTertiary,
                        fontSize: 10)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('v${AutoUpdateService.currentVersion}',
                      style: TextStyle(
                          color: t.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: dark ? 0.15 : 0.08),
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
        const SizedBox(height: 4),
        Text(
          state._userName,
          style: TextStyle(
              color: dark ? Colors.white : t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.25),
          softWrap: true,
          maxLines: 3,
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      child: Column(children: [
        if (RoleSimulatorService.canAccessSimulator(state.widget.userData['role']?.toString()))
          _ActionTile(
            icon: Icons.preview_rounded,
            label: 'Role Simulator',
            t: t,
            dark: dark,
            onTap: () => RoleSimulatorService.showRoleSelectorModal(context),
          ),
        _ActionTile(

          icon: Icons.settings_outlined,
          label: 'Settings',
          t: t,
          dark: dark,

          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      SettingsPage(userData: state.widget.userData))).then((_) {
            state.refresh();
          }),
        ),
        if ((state.widget.userData['role']?.toString().toLowerCase().contains('chairman') ?? false))
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
          'assets/logo/gmwf-1.webp',
          cacheWidth: 200,
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
    DashboardCategoryFilter.overall: Icons.home_outlined,
    DashboardCategoryFilter.office: Icons.business_center_outlined,
    DashboardCategoryFilter.dispensary: Icons.local_pharmacy_outlined,
    DashboardCategoryFilter.dasterkhwaan: Icons.restaurant_outlined,
    DashboardCategoryFilter.madrassa: Icons.menu_book_outlined,
    DashboardCategoryFilter.school: Icons.school_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final sel = widget.selected;
    final dark = widget.dark;
    final label = widget.cat == DashboardCategoryFilter.overall
        ? 'Dashboard'
        : widget.cat.name[0].toUpperCase() + widget.cat.name.substring(1);

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
              padding: const EdgeInsets.all(5),
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
                    : (dark ? const Color(0xFFC9D1D9) : t.textTertiary),
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: sel
                          ? (dark ? Colors.white : t.textPrimary)
                          : (dark ? const Color(0xFFC9D1D9) : t.textSecondary),
                      fontWeight:
                          sel ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12.5)),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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

  bool get _dark => state._isDark;

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
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('v${AutoUpdateService.currentVersion}',
              style: TextStyle(
                  color: t.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ),
      ]),
      actions: [
        if (RoleSimulatorService.canAccessSimulator(state._role))
          IconButton(
            tooltip: 'Live Role Simulator',
            icon: const Icon(Icons.preview_rounded, color: Colors.amberAccent, size: 22),
            onPressed: () => RoleSimulatorService.showRoleSelectorModal(context),
          ),
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

            // Scrollable navigation links
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state._isSupervisor) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: _NavLabel(
                            label: 'MY MODULES',
                            muted: _dark
                                ? const Color(0xFF8B949E)
                                : t.textTertiary),
                      ),
                      ...state._availableModules.map((m) => ListTile(
                            dense: true,
                            leading: Icon(m.icon, color: t.accent, size: 18),
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
                          )),
                    ] else if (state._mobileShowsCategoryChips) ...[
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
                    ],
                  ],
                ),
              ),
            ),

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
                            userData: state.widget.userData))).then((_) {
                  state.refresh();
                });
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

  bool get _showMobileChips =>
      !isDesktop && state._mobileShowsCategoryChips && !state._isSupervisor;

  @override
  Widget build(BuildContext context) {
    final filtered = state._cachedFilteredModules;
    final double hPad = isDesktop ? 36 : 20;

    final showSnapshot = state._selectedCategory == DashboardCategoryFilter.overall && state._searchQuery.isEmpty;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _HeroHeader(state: state, t: t, isDesktop: isDesktop),
        ),
        if (!showSnapshot)
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
        if (showSnapshot)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 56),
            sliver: SliverToBoxAdapter(
              child: HomeSnapshotDashboard(
                userData: state.widget.userData,
                t: t,
                availableModules: state._availableModules,
                onOpenModule: state._openModule,
                isDesktop: isDesktop,
                onViewReports: () {
                  final reportsModule = state._availableModules.firstWhere(
                    (m) => m.id == 'executive_dashboard',
                    orElse: () => ModuleRegistry.allModules.firstWhere((m) => m.id == 'executive_dashboard'),
                  );
                  state._openModule(reportsModule);
                },
              ),
            ),
          )
        else ...[
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

  bool get _dark => state._isDark;

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

  bool get _dark => state._isDark;

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

// ── Dark & Light Profile-Oriented Hero Header (Lag-free Executive Profile Layout) ─────────
class _DarkHero extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool isDesktop;
  final double hPad;
  const _DarkHero({required this.state, required this.t, required this.isDesktop, required this.hPad});

  @override
  Widget build(BuildContext context) {
    return _buildProfileHeroCard(
      state: state,
      t: t,
      isDesktop: isDesktop,
      hPad: hPad,
      isDark: true,
    );
  }
}

class _LightHero extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  final bool isDesktop;
  final double hPad;
  const _LightHero({required this.state, required this.t, required this.isDesktop, required this.hPad});

  @override
  Widget build(BuildContext context) {
    return _buildProfileHeroCard(
      state: state,
      t: t,
      isDesktop: isDesktop,
      hPad: hPad,
      isDark: false,
    );
  }
}

class _TypewriterUserNameText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _TypewriterUserNameText({
    required this.text,
    required this.style,
  });

  @override
  State<_TypewriterUserNameText> createState() => _TypewriterUserNameTextState();
}

class _TypewriterUserNameTextState extends State<_TypewriterUserNameText> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<int> _charCount;
  bool _showCursor = true;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();
    final textLen = widget.text.length.clamp(1, 100);
    // Slower pacing (min 1.2s to 3.0s) so short 3-letter names like "Ans" type out distinctly
    final animMs = (textLen * 350).clamp(1200, 3000);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: animMs),
    );
    _charCount = StepTween(begin: 0, end: textLen).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _cursorTimer?.cancel();
        if (mounted) setState(() => _showCursor = false);
      }
    });

    _ctrl.forward();

    _cursorTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted && _ctrl.isAnimating) {
        setState(() => _showCursor = !_showCursor);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _TypewriterUserNameText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _ctrl.stop();
      final textLen = widget.text.length.clamp(1, 100);
      final animMs = (textLen * 350).clamp(1200, 3000);
      _ctrl.duration = Duration(milliseconds: animMs);
      _charCount = StepTween(begin: 0, end: textLen).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      );
      setState(() => _showCursor = true);
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _charCount,
      builder: (context, _) {
        final currentLen = _charCount.value.clamp(0, widget.text.length);
        final displayedText = widget.text.substring(0, currentLen);
        final isFinished = currentLen >= widget.text.length;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                displayedText,
                style: widget.style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isFinished)
              Opacity(
                opacity: _showCursor ? 1.0 : 0.0,
                child: Container(
                  margin: const EdgeInsets.only(left: 3),
                  width: 3.5,
                  height: (widget.style.fontSize ?? 20) * 0.85,
                  decoration: BoxDecoration(
                    color: widget.style.color ?? Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RotatingGlowBorderContainer extends StatefulWidget {
  final Widget child;
  final Color accentColor;
  final double borderRadius;
  final EdgeInsets margin;

  const _RotatingGlowBorderContainer({
    required this.child,
    required this.accentColor,
    this.borderRadius = 22.0,
    required this.margin,
  });

  @override
  State<_RotatingGlowBorderContainer> createState() => _RotatingGlowBorderContainerState();
}

class _RotatingGlowBorderContainerState extends State<_RotatingGlowBorderContainer> with SingleTickerProviderStateMixin {
  late AnimationController _rotationCtrl;

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    return Container(
      margin: widget.margin,
      child: AnimatedBuilder(
        animation: _rotationCtrl,
        builder: (context, child) {
          return CustomPaint(
            foregroundPainter: _HeroBorderFlarePainter(
              progress: _rotationCtrl.value,
              accentColor: accent,
              borderRadius: widget.borderRadius,
            ),
            child: Container(
              padding: const EdgeInsets.all(2.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE8B84A).withValues(alpha: 0.20),
                    blurRadius: 40,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 80,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 120,
                    offset: const Offset(0, 24),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius - 2.0),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroBorderFlarePainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final double borderRadius;

  _HeroBorderFlarePainter({
    required this.progress,
    required this.accentColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 1. Base 2px Border (Gold #E8B84A -> Warm Amber #FFCC66 -> Gold)
    final baseBorderPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFE8B84A),
          Color(0xFFFFCC66),
          Color(0xFFE8B84A),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRRect(rrect, baseBorderPaint);

    // 2. Compute Reflection Position Along Perimeter (top -> right -> bottom -> left)
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final pathMetric = metrics.first;
    final totalLength = pathMetric.length;
    final distance = (progress * totalLength) % totalLength;

    // Moving reflection highlight: ~60px width
    const highlightLength = 60.0;
    final startDist = distance - (highlightLength / 2);
    final endDist = distance + (highlightLength / 2);

    Path highlightPath;
    if (startDist >= 0 && endDist <= totalLength) {
      highlightPath = pathMetric.extractPath(startDist, endDist);
    } else if (startDist < 0) {
      highlightPath = pathMetric.extractPath(startDist + totalLength, totalLength);
      highlightPath.addPath(pathMetric.extractPath(0, endDist), Offset.zero);
    } else {
      highlightPath = pathMetric.extractPath(startDist, totalLength);
      highlightPath.addPath(pathMetric.extractPath(0, endDist - totalLength), Offset.zero);
    }

    final tangent = pathMetric.getTangentForOffset(distance);
    if (tangent == null) return;
    final reflPos = tangent.position;

    // 3. Single Metallic Moving Light Reflection (Soft Bloom, Feathered Edges)
    final reflPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (reflPos.dx / (size.width == 0 ? 1 : size.width)) * 2 - 1,
          (reflPos.dy / (size.height == 0 ? 1 : size.height)) * 2 - 1,
        ),
        radius: 0.15,
        colors: [
          Colors.white,
          const Color(0xFFFFF3D1).withValues(alpha: 0.85),
          const Color(0xFFFFCC66).withValues(alpha: 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;

    canvas.drawPath(highlightPath, reflPaint);

    // Soft bloom glow over reflection (barely extends outside card)
    final softBloomPaint = Paint()
      ..color = const Color(0xFFFFF3D1).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(reflPos, 14, softBloomPaint);
  }

  @override
  bool shouldRepaint(covariant _HeroBorderFlarePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accentColor != accentColor;
}

class _HeroBackgroundPainter extends CustomPainter {
  final Color accentColor;

  _HeroBackgroundPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bgPaint = Paint()..color = Color.lerp(accentColor, const Color(0xFF0F172A), 0.70)!;
    canvas.drawRect(rect, bgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _buildProfileHeroCard({
  required _GlobalModularDashboardState state,
  required RoleThemeData t,
  required bool isDesktop,
  required double hPad,
  required bool isDark,
}) {
  final now = DateTime.now();
  final dateStr = '${_weekdayFull(now.weekday)}, ${now.day} ${_monthFull(now.month)} ${now.year}';
  final hour = now.hour;

  final isCeo = state._role == 'ceo';
  final isChairman = state._role == 'chairman';

  final timeOfDayUpper = _timeOfDayString(hour).toUpperCase();
  final timeEmoji = (hour >= 18 || hour < 5) ? '🌙' : '☀️';

  final greetingBadgeText = isChairman
      ? '$timeEmoji GOOD $timeOfDayUpper, CHAIRMAN'
      : (isCeo
          ? '$timeEmoji GOOD $timeOfDayUpper, CEO'
          : '$timeEmoji GOOD $timeOfDayUpper');

  final String userPhotoUrl = state._userPhotoUrl;
  final String userName = state._userName;
  final String userRole = state._role.toUpperCase();

  final avatarSize = isDesktop ? 76.0 : 64.0;

  final primaryThemeColor = t.accent;

  return _RotatingGlowBorderContainer(
    accentColor: primaryThemeColor,
    margin: EdgeInsets.fromLTRB(hPad, isDesktop ? 24 : 16, hPad, 0),
    child: Stack(
      children: [
        // Layered Surface Background with Ambient Lighting & Abstract Mesh
        Positioned.fill(
          child: CustomPaint(
            painter: _HeroBackgroundPainter(accentColor: primaryThemeColor),
          ),
        ),

        Padding(
          padding: EdgeInsets.all(isDesktop ? 24 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Greeting Badge Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: Color.lerp(primaryThemeColor, Colors.black, 0.6)!.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  greetingBadgeText,
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Profile Avatar, User Name & Date Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Interactive Avatar with Brighter Gold Solid Ring & 1px White Online Indicator
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _showEnlargedAvatarDialog(state.context, state, t),
                      child: Tooltip(
                        message: 'Tap to view, change or remove profile picture',
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFE8B84A),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE8B84A).withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(2.5),
                              child: ClipOval(
                                child: _buildUserHeroAvatar(userPhotoUrl, userName, t, size: avatarSize),
                              ),
                            ),
                            Positioned(
                              right: 1,
                              bottom: 1,
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.6),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  // User Display Name (Weight 700) & Date Subtitle (Opacity 0.65)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TypewriterUserNameText(
                          text: userName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isDesktop ? 25 : 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dateStr,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Bottom Metadata Badges Row
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ExecutiveGlassPill(
                    label: userRole,
                    icon: (isChairman || isCeo)
                        ? Icons.workspace_premium_rounded
                        : Icons.shield_outlined,
                    accentColor: const Color(0xFFF59E0B),
                    isGreenTheme: true,
                  ),
                  _ExecutiveGlassPill(
                    label: '${state._availableModules.length} Modules',
                    icon: Icons.grid_view_rounded,
                    accentColor: primaryThemeColor,
                    isGreenTheme: true,
                  ),
                  _ExecutiveGlassPill(
                    label: 'Global Access',
                    icon: Icons.public_rounded,
                    accentColor: const Color(0xFF38BDF8),
                    isGreenTheme: true,
                  ),
                  _ExecutiveGlassPill(
                    label: 'Live System',
                    icon: Icons.bolt_rounded,
                    accentColor: const Color(0xFFF59E0B),
                    isGreenTheme: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ExecutiveGlassPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isGreenTheme;

  const _ExecutiveGlassPill({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isGreenTheme,
  });

  @override
  State<_ExecutiveGlassPill> createState() => _ExecutiveGlassPillState();
}

class _ExecutiveGlassPillState extends State<_ExecutiveGlassPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0.0, _isHovered ? -2.0 : 0.0, 0.0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(30, 35, 45, 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered
                ? widget.accentColor.withValues(alpha: 0.3)
                : const Color.fromRGBO(255, 255, 255, 0.08),
            width: 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.2),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [
                Color.fromRGBO(255, 255, 255, 0.04),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: widget.accentColor),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showEnlargedAvatarDialog(
  BuildContext context,
  _GlobalModularDashboardState state,
  RoleThemeData t,
) async {
  final userName = state._userName;
  final userRole = state._role.toUpperCase();

  final userData = state.widget.userData;
  final lastUpdatedByName = (userData['photoUpdatedByName'] as String?) ?? '';
  final rawTime = userData['photoUpdatedAt'];
  final lastUpdatedTime = (rawTime != null)
      ? (rawTime is Timestamp
          ? rawTime.toDate().toLocal().toString().split('.')[0]
          : rawTime.toString())
      : '';

  showDialog(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final currentPhoto = state._userPhotoUrl;
        final hasPhoto = currentPhoto.trim().isNotEmpty;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: t.accent.withValues(alpha: 0.4), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header bar with Title & Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_circle_rounded, color: t.accent, size: 22),
                        const SizedBox(width: 8),
                        const Text(
                          'Profile Photo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(dialogCtx),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Enlarged Avatar Preview Container (Crystal Clear 320px display)
                Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF59E0B), width: 4.0),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                        blurRadius: 24,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _buildUserHeroAvatar(currentPhoto, userName, t, size: 320),
                  ),
                ),
                const SizedBox(height: 20),

                // User Name & Role Pill
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    userRole,
                    style: TextStyle(
                      color: t.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // Audit Trail info badge (Who updated this info last)
                if (lastUpdatedByName.isNotEmpty || lastUpdatedTime.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.history_rounded, size: 13, color: Colors.white60),
                            const SizedBox(width: 4),
                            Text(
                              'Last Photo Audit',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Updated by: ${lastUpdatedByName.isNotEmpty ? lastUpdatedByName : "System"}${lastUpdatedTime.isNotEmpty ? ' ($lastUpdatedTime)' : ''}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action Buttons Row: Change Photo & Remove Photo
                Row(
                  children: [
                    // Change Photo Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final source = await ImageUploadService.showSourceDialog(context, title: 'Choose Profile Photo Source');
                          if (source == null) return;

                          final newBase64 = await ImageUploadService.pickAndProcessImage(source: source, maxWidth: 512, maxHeight: 512);
                          if (newBase64 == null || newBase64.isEmpty) return;

                          await _updateUserProfilePhoto(
                            state: state,
                            newBase64: newBase64,
                            action: 'PHOTO_CHANGED',
                          );

                          setDialogState(() {});
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Profile photo updated successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.photo_camera_rounded, size: 18),
                        label: const Text('Change Photo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: t.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    if (hasPhoto) ...[
                      const SizedBox(width: 12),
                      // Remove Photo Button
                      OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (confirmCtx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E293B),
                              title: const Text('Remove Profile Photo?', style: TextStyle(color: Colors.white)),
                              content: const Text('Are you sure you want to remove your profile photo?', style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(confirmCtx, false),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(confirmCtx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                  child: const Text('Remove', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );

                          if (confirm != true) return;

                          await _updateUserProfilePhoto(
                            state: state,
                            newBase64: '',
                            action: 'PHOTO_REMOVED',
                          );

                          setDialogState(() {});
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🗑️ Profile photo removed.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                        label: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent, width: 1.2),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _updateUserProfilePhoto({
  required _GlobalModularDashboardState state,
  required String newBase64,
  required String action,
}) async {
  // 1. Update State User Data
  state.widget.userData['profileImage'] = newBase64;
  state.widget.userData['photoUrl'] = newBase64;
  state.widget.userData['profilePictureUrl'] = newBase64;

  // 2. Audit Trail Tracking (who performed the update)
  final currentUser = FirebaseAuth.instance.currentUser;
  final updaterUid = (currentUser?.uid ?? state.widget.userData['uid'] ?? state.widget.userData['id'] ?? 'unknown').toString();
  final updaterName = state._userName;
  final updaterEmail = (state.widget.userData['email'] ?? currentUser?.email ?? 'unknown').toString();
  final timestampStr = DateTime.now().toIso8601String();

  final auditRecord = {
    'action': action,
    'timestamp': timestampStr,
    'updatedByUid': updaterUid,
    'updatedByName': updaterName,
    'updatedByEmail': updaterEmail,
  };

  state.widget.userData['photoUpdatedAt'] = timestampStr;
  state.widget.userData['photoUpdatedByUid'] = updaterUid;
  state.widget.userData['photoUpdatedByName'] = updaterName;
  state.widget.userData['photoUpdatedByEmail'] = updaterEmail;

  state.refresh();

  // 3. Save locally in Hive & Offline Secure Credentials Cache
  await LocalStorageService.saveLocalUser(state.widget.userData);
  await offline_auth.OfflineAuthService.updateCachedUserData(state.widget.userData);

  // 4. Sync online with Cloud Firestore
  try {
    if (updaterUid.isNotEmpty && updaterUid != 'unknown') {
      final updateData = {
        'profileImage': newBase64,
        'photoUrl': newBase64,
        'profilePictureUrl': newBase64,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
        'photoUpdatedByUid': updaterUid,
        'photoUpdatedByName': updaterName,
        'photoUpdatedByEmail': updaterEmail,
        'photoHistory': FieldValue.arrayUnion([auditRecord]),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(updaterUid).set(updateData, SetOptions(merge: true));

      final branchId = state.widget.userData['branchId']?.toString();
      if (branchId != null && branchId.isNotEmpty && branchId != 'all' && branchId != 'unknown') {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .collection('users')
            .doc(updaterUid)
            .set(updateData, SetOptions(merge: true));
      }

      try {
        final cgSnap = await FirebaseFirestore.instance
            .collectionGroup('users')
            .where('uid', isEqualTo: updaterUid)
            .get()
            .timeout(const Duration(seconds: 4));
        for (final doc in cgSnap.docs) {
          await doc.reference.set(updateData, SetOptions(merge: true));
        }
      } catch (_) {}
    }
  } catch (e) {
    debugPrint('[GlobalDashboard] Error syncing updated profile photo to cloud: $e');
  }
}

String _timeOfDayString(int hour) {
  if (hour < 12) return 'morning';
  if (hour < 17) return 'afternoon';
  return 'evening';
}

String _weekdayFull(int d) => ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d - 1];
String _monthFull(int m) => ['January','February','March','April','May','June','July','August','September','October','November','December'][m-1];

Widget _buildUserHeroAvatar(String photoUrl, String userName, RoleThemeData t, {double size = 64}) {
  final str = photoUrl.trim();
  Widget child;
  if (str.isNotEmpty) {
    final bytes = ImageUploadService.decodeBase64ToBytes(str);
    if (bytes != null) {
      child = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, errorBuilder: (c, e, s) => _buildUserAvatarFallback(userName, t, size));
    } else if (str.startsWith('http://') || str.startsWith('https://')) {
      child = Image.network(str, width: size, height: size, fit: BoxFit.cover, errorBuilder: (c, e, s) => _buildUserAvatarFallback(userName, t, size));
    } else if (File(str).existsSync()) {
      child = Image.file(File(str), width: size, height: size, fit: BoxFit.cover, errorBuilder: (c, e, s) => _buildUserAvatarFallback(userName, t, size));
    } else {
      child = _buildUserAvatarFallback(userName, t, size);
    }
  } else {
    child = _buildUserAvatarFallback(userName, t, size);
  }

  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 3.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: ClipOval(child: child),
  );
}

Widget _buildUserAvatarFallback(String userName, RoleThemeData t, double size) {
  final initial = userName.trim().isNotEmpty ? userName.trim()[0].toUpperCase() : 'U';
  return Container(
    color: t.accent.withValues(alpha: 0.8),
    alignment: Alignment.center,
    child: Text(
      initial,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: size * 0.42,
      ),
    ),
  );
}






// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final _GlobalModularDashboardState state;
  final RoleThemeData t;
  const _SearchBar({required this.state, required this.t});

  bool get _dark => state._isDark;

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
                state.updateSearchQuery(v.trim());
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
                      onPressed: () => state.clearSearch(),
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

  bool get _dark => state._isDark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: state._visibleCategories.map((cat) {
          final sel = state._selectedCategory == cat;
          final label = cat == DashboardCategoryFilter.overall
              ? 'Dashboard'
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

  bool get _dark => state._isDark;

  @override
  Widget build(BuildContext context) {
    final isSchoolCat = state._selectedCategory == DashboardCategoryFilter.school;
    final branchId = (state.widget.userData['branchId'] as String? ?? '').trim();
    final branchName = LocalStorageService.getBranchName(branchId);
    final isSchoolUnavailable = isSchoolCat && !LocalStorageService.hasSchoolFacility(branchId);

    if (isSchoolUnavailable) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 40),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _dark ? const Color(0xFF161B22) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _dark ? const Color(0xFF30363D) : t.bgRule),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.school_outlined, size: 36, color: Color(0xFF2563EB)),
                ),
                const SizedBox(height: 18),
                Text(
                  'School is not available in $branchName yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _dark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The school facility is not enabled or registered for the $branchName branch.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: _dark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
            Text(state._searchQuery.isNotEmpty ? '"${state._searchQuery}" didn\'t match anything' : 'No modules available for this category',
                style: TextStyle(
                    color: _dark ? const Color(0xFF8B949E) : t.textTertiary,
                    fontSize: 13)),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => state.clearSearch(),
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
    final dark = state._isDark;
    final isSearchActive = state._searchQuery.isNotEmpty;

    // Responsive Grid Delegate: 1 col on mobile, 2 on tablet, 3-4 on desktop
    final gridCols = w < 600 ? 1 : (w < 950 ? 2 : (w < 1350 ? 3 : 4));
    final gridAspect = w < 600 ? 2.6 : (w < 950 ? 2.3 : (w < 1350 ? 2.2 : 2.1));

    // If searching or category filter chip is selected (not 'overall'), show flat grid
    if (isSearchActive || state._selectedCategory != DashboardCategoryFilter.overall) {
      return GridView.builder(
        key: ValueKey('flat_${state._selectedCategory}_${state._searchQuery}'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridCols,
          crossAxisSpacing: isDesktop ? 14 : 10,
          mainAxisSpacing: isDesktop ? 14 : 10,
          childAspectRatio: gridAspect,
        ),
        itemCount: modules.length,
        itemBuilder: (ctx, i) {
          return _ModuleCard(
            module: modules[i],
            t: t,
            dark: dark,
            isDesktop: isDesktop,
            isHero: modules[i].isFeatured,
            onTap: () => state._openModule(modules[i]),
          );
        },
      );
    }

    // Hierarchical Department Grouping for Main Dashboard View
    final featured = modules.where((m) => m.isFeatured).toList();
    final officeMods = modules.where((m) => !m.isFeatured && m.category == ModuleCategory.office).toList();
    final medicalMods = modules.where((m) => !m.isFeatured && m.category == ModuleCategory.dispensary).toList();
    final welfareMods = modules.where((m) => !m.isFeatured && m.category == ModuleCategory.dasterkhwaan).toList();
    final eduMods = modules.where((m) => !m.isFeatured && (m.category == ModuleCategory.madrassa || m.category == ModuleCategory.school)).toList();
    final restMods = modules.where((m) => !m.isFeatured &&
        m.category != ModuleCategory.office &&
        m.category != ModuleCategory.dispensary &&
        m.category != ModuleCategory.dasterkhwaan &&
        m.category != ModuleCategory.madrassa &&
        m.category != ModuleCategory.school).toList();

    Widget buildCategorySection(String title, IconData icon, Color color, List<AppModule> secModules) {
      if (secModules.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: dark ? const Color(0xFFE6EDF3) : t.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${secModules.length}',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridCols,
              crossAxisSpacing: isDesktop ? 14 : 10,
              mainAxisSpacing: isDesktop ? 14 : 10,
              childAspectRatio: gridAspect,
            ),
            itemCount: secModules.length,
            itemBuilder: (ctx, i) {
              return _ModuleCard(
                module: secModules[i],
                t: t,
                dark: dark,
                isDesktop: isDesktop,
                isHero: secModules[i].isFeatured,
                onTap: () => state._openModule(secModules[i]),
              );
            },
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('hierarchical_grid'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (featured.isNotEmpty)
          buildCategorySection('Core & Executive Operations', Icons.star_rounded, const Color(0xFFF59E0B), featured),
        if (officeMods.isNotEmpty)
          buildCategorySection('Office & Financial ERP', Icons.business_center_rounded, const Color(0xFF6366F1), officeMods),
        if (medicalMods.isNotEmpty)
          buildCategorySection('Medical & Dispensary Services', Icons.local_hospital_rounded, const Color(0xFF0D9488), medicalMods),
        if (welfareMods.isNotEmpty)
          buildCategorySection('Welfare & Relief Services', Icons.volunteer_activism_rounded, const Color(0xFFF97316), welfareMods),
        if (eduMods.isNotEmpty)
          buildCategorySection('Madrassa & School Education', Icons.school_rounded, const Color(0xFF8B5CF6), eduMods),
        if (restMods.isNotEmpty)
          buildCategorySection('System & Maintenance', Icons.settings_rounded, const Color(0xFF64748B), restMods),
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
        vsync: this, duration: const Duration(milliseconds: 100));
    _pressScale = Tween<double>(begin: 1.0, end: 0.97).animate(
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
    final w = MediaQuery.of(context).size.width;
    final tiny = w < 480;

    // Get color & label for category
    final Color categoryColor;
    final String categoryLabel;
    switch (widget.module.category) {
      case ModuleCategory.office:
        categoryColor = const Color(0xFF6366F1); // Indigo
        categoryLabel = widget.module.id == 'finance' ? 'HR' : 'OFFICE';
        break;
      case ModuleCategory.dispensary:
        categoryColor = const Color(0xFF0D9488); // Teal
        categoryLabel = 'MEDICAL';
        break;
      case ModuleCategory.dasterkhwaan:
        categoryColor = const Color(0xFFF97316); // Orange
        categoryLabel = 'WELFARE';
        break;
      case ModuleCategory.madrassa:
        categoryColor = const Color(0xFF8B5CF6); // Purple
        categoryLabel = 'MADRASSA';
        break;
      case ModuleCategory.school:
        categoryColor = const Color(0xFF2563EB); // Blue
        categoryLabel = 'SCHOOL';
        break;
    }

    final categoryGradient = LinearGradient(
      colors: [categoryColor.withValues(alpha: 0.85), categoryColor],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

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
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutQuart,
            transform: Matrix4.translationValues(0.0, _hov ? -4.0 : 0.0, 0.0),
            decoration: BoxDecoration(
              color: dark 
                  ? (_hov ? const Color(0xFF1E293B) : const Color(0xFF0F172A))
                  : (_hov ? Colors.white : t.bgCard),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hov
                    ? categoryColor.withValues(alpha: 0.7)
                    : (dark ? const Color(0xFF1E293B) : t.bgRule),
                width: _hov ? 1.8 : 1.0,
              ),
              boxShadow: _hov
                  ? [
                      BoxShadow(
                          color: categoryColor.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8)),
                      BoxShadow(
                          color: categoryColor.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2)),
                    ]
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: Stack(
                children: [
                  // Left colored accent border line
                  Positioned(
                    left: 0, top: 0, bottom: 0,
                    width: 4,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: _hov
                              ? [categoryColor, categoryColor.withValues(alpha: 0.5)]
                              : [categoryColor.withValues(alpha: 0.7), categoryColor.withValues(alpha: 0.2)],
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      tiny ? 14 : 18,
                      tiny ? 12 : 14,
                      tiny ? 14 : 16,
                      tiny ? 12 : 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top row: Icon + Category Badge + Arrow
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Icon container
                            AnimatedRotation(
                              turns: _hov ? 0.02 : 0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutBack,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: EdgeInsets.all(tiny ? 8 : 10),
                                decoration: BoxDecoration(
                                  gradient: _hov ? categoryGradient : null,
                                  color: !_hov 
                                      ? (dark ? const Color(0xFF1E293B) : categoryColor.withValues(alpha: 0.1)) 
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: _hov ? [
                                    BoxShadow(
                                      color: categoryColor.withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ] : [],
                                ),
                                child: Icon(
                                  widget.module.icon,
                                  color: _hov ? Colors.white : categoryColor,
                                  size: tiny ? 18 : 22,
                                ),
                              ),
                            ),
                            
                            const SizedBox(width: 12),

                            // Category badge pill & Title block
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: categoryColor.withValues(alpha: _hov ? 0.25 : 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      categoryLabel,
                                      style: TextStyle(
                                        color: categoryColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.module.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: dark ? const Color(0xFFF3F4F6) : t.textPrimary,
                                      fontSize: tiny ? 13.5 : 15.0,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Arrow Indicator
                            AnimatedOpacity(
                              opacity: _hov ? 1.0 : 0.4,
                              duration: const Duration(milliseconds: 200),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: _hov 
                                      ? categoryColor 
                                      : (dark ? const Color(0xFF1E293B) : categoryColor.withValues(alpha: 0.08)),
                                  shape: BoxShape.circle,
                                ),
                                child: Transform.translate(
                                  offset: Offset(_hov ? 2.0 : 0.0, 0.0),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: _hov ? Colors.white : categoryColor,
                                    size: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Description
                        Text(
                          widget.module.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: dark 
                                ? (_hov ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280))
                                : (_hov ? t.textSecondary : t.textTertiary),
                            fontSize: tiny ? 10.5 : 11.5,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}