// lib/design/gallery/design_gallery.dart
//
// ── Design System Gallery ────────────────────────────────────────────────────
// A living reference of every token and shared component, rendered with the
// real theme. Runs on its own, without Firebase or a login:
//
//   flutter run -t lib/design/gallery/design_gallery.dart -d chrome
//
// Use the app bar to switch role palette and light/dark mode.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../services/user_theme_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/role_theme_provider.dart';
import '../design_system.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter('gmwf_design_gallery');
  await Hive.openBox('app_settings');
  runApp(const DesignGalleryApp());
}

class DesignGalleryApp extends StatefulWidget {
  const DesignGalleryApp({super.key});

  @override
  State<DesignGalleryApp> createState() => _DesignGalleryAppState();
}

class _DesignGalleryAppState extends State<DesignGalleryApp> {
  RoleTheme _role = RoleTheme.hqManager;
  bool _dark = Hive.box('app_settings').get('is_dark_mode', defaultValue: false) as bool;

  void _setDark(bool v) {
    Hive.box('app_settings').put('is_dark_mode', v);
    UserThemeService.notifyThemeChanged();
    setState(() => _dark = v);
  }

  @override
  Widget build(BuildContext context) {
    final seed = RoleThemeData.of(_role).accent;
    return MaterialApp(
      title: 'GMWF Design System',
      debugShowCheckedModeBanner: false,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: GTheme.build(seedColor: seed, brightness: Brightness.light),
      darkTheme: GTheme.build(seedColor: seed, brightness: Brightness.dark),
      home: RoleThemeScope(
        role: _role,
        child: _GalleryPage(
          role: _role,
          dark: _dark,
          onRole: (r) => setState(() => _role = r),
          onDark: _setDark,
        ),
      ),
    );
  }
}

class _GalleryPage extends StatefulWidget {
  const _GalleryPage({required this.role, required this.dark, required this.onRole, required this.onDark});

  final RoleTheme role;
  final bool dark;
  final ValueChanged<RoleTheme> onRole;
  final ValueChanged<bool> onDark;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  String _segment = 'Today';
  bool _filter = true;

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          title: const Text('GMWF Design System'),
          actions: [
            DropdownButton<RoleTheme>(
              value: widget.role,
              underline: const SizedBox.shrink(),
              items: [
                for (final r in RoleTheme.values) DropdownMenuItem(value: r, child: Text(r.name)),
              ],
              onChanged: (r) => r == null ? null : widget.onRole(r),
            ),
            const SizedBox(width: Gsp.sp2),
            Icon(widget.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 20),
            Switch(value: widget.dark, onChanged: widget.onDark),
            const SizedBox(width: Gsp.sp3),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Overview'), Tab(text: 'Patients'), Tab(text: 'Reports')],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gsp.screenHD, Gsp.sp6, Gsp.screenHD, Gsp.pageBottom),
          children: [
            _section(context, 'Colour', _colours(context, t)),
            _section(context, 'Typography', _type(t)),
            _section(context, 'KPI cards', _kpis(t)),
            _section(context, 'Buttons', _buttons(context)),
            _section(context, 'Inputs', _inputs(context)),
            _section(context, 'Chips & status', _chips(t)),
            _section(context, 'Cards & lists', _cards(context, t)),
            _section(context, 'Table', _table(t)),
            _section(context, 'Empty state', const AppCard(child: AppEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No tokens yet today',
              subtitle: 'New tokens appear here as reception issues them.',
              compact: true,
            ))),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: Gsp.sp8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [AppSectionHeader(label: label), child],
        ),
      );

  // ── Colour ────────────────────────────────────────────────────────────────

  Widget _colours(BuildContext context, RoleThemeData t) {
    final c = context.comfort;
    Widget swatch(String name, Color color) => SizedBox(
          width: 128,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: Gr.input,
                  border: Border.all(color: t.bgRule),
                ),
              ),
              const SizedBox(height: Gsp.sp1),
              Text(name, style: GText.caption(t.textSecondary)),
            ],
          ),
        );
    return Wrap(spacing: Gsp.sp3, runSpacing: Gsp.sp3, children: [
      swatch('canvas · bg', t.bg),
      swatch('surface · bgCard', t.bgCard),
      swatch('well · bgCardAlt', t.bgCardAlt),
      swatch('hairline · bgRule', t.bgRule),
      swatch('accent', t.accent),
      swatch('accentLight', t.accentLight),
      swatch('accentMuted', t.accentMuted),
      swatch('textPrimary', t.textPrimary),
      swatch('textSecondary', t.textSecondary),
      swatch('textTertiary', t.textTertiary),
      swatch('success', c.success),
      swatch('warning', c.warning),
      swatch('danger', c.danger),
      swatch('info', c.info),
    ]);
  }

  // ── Typography ────────────────────────────────────────────────────────────

  Widget _type(RoleThemeData t) {
    Widget row(String name, TextStyle style, String sample) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Gsp.sp1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            SizedBox(width: 96, child: Text(name, style: GText.caption(t.textTertiary))),
            Expanded(child: Text(sample, style: style)),
          ]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row('display', GText.display(t.textPrimary), 'PKR 1,284,500'),
        row('h1', GText.h1(t.textPrimary), 'Branch overview'),
        row('h2', GText.h2(t.textPrimary), 'Dispensary summary'),
        row('h3', GText.h3(t.textPrimary), 'Recent prescriptions'),
        row('body1', GText.body1(t.textPrimary), 'Token 42 was dispensed by Ahmed at 10:24.'),
        row('body2', GText.body2(t.textSecondary), 'Zakat-eligible patients are billed at zero cost.'),
        row('label', GText.label(t.textSecondary), 'PATIENT TYPE'),
        row('caption', GText.caption(t.textTertiary), 'Synced 2 minutes ago'),
        row('statLg', GText.statLg(t.textPrimary), '1,111 · 9,999 · 4,040'),
      ]),
    );
  }

  // ── KPI cards ─────────────────────────────────────────────────────────────

  Widget _kpis(RoleThemeData t) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 900 ? 4 : 2;
        final w = (box.maxWidth - Gsp.sp3 * (cols - 1)) / cols;
        return Wrap(spacing: Gsp.sp3, runSpacing: Gsp.sp3, children: [
          SizedBox(width: w, child: const StatCard(label: 'Tokens today', value: '1,284', icon: Icons.confirmation_number_outlined, subtitle: '+12% vs yesterday')),
          SizedBox(width: w, child: const StatCard(label: 'Prescriptions', value: '968', icon: Icons.medication_outlined, subtitle: '75% of tokens')),
          SizedBox(width: w, child: const StatCard(label: 'Dispensed', value: '931', icon: Icons.local_pharmacy_outlined)),
          SizedBox(width: w, child: const StatCard(label: 'Donations', value: 'PKR 245K', icon: Icons.volunteer_activism_outlined)),
          SizedBox(
            width: box.maxWidth,
            child: const HeroStatCard(label: 'Monthly revenue', value: 'PKR 2,450,000', trend: '+8.4%', icon: Icons.trending_up_rounded),
          ),
          SizedBox(
            width: box.maxWidth,
            child: RatioBar(zakat: 540, nonZakat: 610, gmwf: 134, total: 1284, t: t),
          ),
        ]);
      });

  // ── Buttons ───────────────────────────────────────────────────────────────

  Widget _buttons(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: Gsp.sp3, runSpacing: Gsp.sp3, crossAxisAlignment: WrapCrossAlignment.center, children: [
            IntrinsicWidth(child: AppButton(label: 'Save patient', icon: Icons.check_rounded, onTap: () {})),
            IntrinsicWidth(child: AppButton(label: 'Export', variant: AppButtonVariant.secondary, icon: Icons.download_rounded, onTap: () {})),
            IntrinsicWidth(child: AppButton(label: 'Cancel', variant: AppButtonVariant.ghost, onTap: () {})),
            IntrinsicWidth(child: AppButton(label: 'Delete', variant: AppButtonVariant.danger, icon: Icons.delete_outline_rounded, onTap: () {})),
            IntrinsicWidth(child: AppButton(label: 'Syncing', loading: true, onTap: () {})),
            IntrinsicWidth(child: AppButton(label: 'Small', size: AppButtonSize.sm, onTap: () {})),
          ]),
          const SizedBox(height: Gsp.sp4),
          Text('Stock Material buttons (themed)', style: GText.caption(context.comfort.textMuted)),
          const SizedBox(height: Gsp.sp2),
          Wrap(spacing: Gsp.sp3, runSpacing: Gsp.sp3, children: [
            ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
            FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Filled')),
            OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
            TextButton(onPressed: () {}, child: const Text('Text')),
            const ElevatedButton(onPressed: null, child: Text('Disabled')),
            TextButton(
              onPressed: () => showAppConfirmDialog(
                context: context,
                title: 'Delete token?',
                message: 'Token 42 and its prescription will be removed from today\'s queue.',
                confirmLabel: 'Delete',
                icon: Icons.delete_outline_rounded,
                isDanger: true,
              ),
              child: const Text('Open dialog'),
            ),
          ]),
        ]),
      );

  // ── Inputs ────────────────────────────────────────────────────────────────

  Widget _inputs(BuildContext context) => AppCard(
        child: Column(children: [
          Row(children: [
            const Expanded(child: TextField(decoration: InputDecoration(labelText: 'Patient name', hintText: 'e.g. Ahmed Raza'))),
            const SizedBox(width: Gsp.sp3),
            Expanded(child: TextField(decoration: roleInputDecoration(context, label: 'CNIC', icon: Icons.badge_outlined, required: true))),
          ]),
          const SizedBox(height: Gsp.sp3),
          Row(children: [
            const Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                  errorText: 'Enter an 11-digit number',
                ),
              ),
            ),
            const SizedBox(width: Gsp.sp3),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: 'Zakat',
                decoration: const InputDecoration(labelText: 'Patient type'),
                items: const [
                  DropdownMenuItem(value: 'Zakat', child: Text('Zakat')),
                  DropdownMenuItem(value: 'Non-Zakat', child: Text('Non-Zakat')),
                  DropdownMenuItem(value: 'GMWF', child: Text('GMWF')),
                ],
                onChanged: (_) {},
              ),
            ),
          ]),
          const SizedBox(height: Gsp.sp4),
          Row(children: [
            AppSegmentedControl(
              options: const ['Today', 'Week', 'Month'],
              selected: _segment,
              onChanged: (v) => setState(() => _segment = v),
            ),
            const Spacer(),
            Checkbox(value: _filter, onChanged: (v) => setState(() => _filter = v ?? false)),
            const Text('Only unsynced'),
          ]),
        ]),
      );

  // ── Chips ─────────────────────────────────────────────────────────────────

  Widget _chips(RoleThemeData t) => Wrap(spacing: Gsp.sp2, runSpacing: Gsp.sp2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const AppChip(label: 'ACTIVE', state: AppChipState.active),
        const AppChip(label: 'PENDING', state: AppChipState.warning, icon: Icons.schedule_rounded),
        const AppChip(label: 'FAILED', state: AppChipState.danger),
        const AppChip(label: 'SYNCED', state: AppChipState.info),
        const AppChip(label: 'ARCHIVED', state: AppChipState.inactive),
        const AppChip(label: 'ROLE', state: AppChipState.custom),
        const SizedBox(width: Gsp.sp3),
        StatusBadge(label: 'Online', color: context.comfort.success),
        const SizedBox(width: Gsp.sp3),
        FilterChip(label: const Text('Zakat'), selected: _filter, onSelected: (v) => setState(() => _filter = v)),
        const Chip(label: Text('Karachi'), avatar: Icon(Icons.place_outlined, size: 16)),
      ]);

  // ── Cards & lists ─────────────────────────────────────────────────────────

  Widget _cards(BuildContext context, RoleThemeData t) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: RoleCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (name, detail, chip) in [
                ('Ahmed Raza', 'Token 42 · Dr. Saima', AppChipState.active),
                ('Fatima Bibi', 'Token 43 · Waiting', AppChipState.warning),
                ('Muhammad Ali', 'Token 44 · Dispensed', AppChipState.info),
              ]) ...[
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: t.accentMuted,
                    child: Text(name[0], style: GText.body1Bold(t.accent)),
                  ),
                  title: Text(name),
                  subtitle: Text(detail),
                  trailing: AppChip(label: chip.name.toUpperCase(), state: chip),
                ),
                if (name != 'Muhammad Ali') const Divider(indent: 16, endIndent: 16),
              ],
            ]),
          ),
        ),
        const SizedBox(width: Gsp.sp4),
        Expanded(
          child: Column(children: [
            AppCard(
              variant: AppCardVariant.accent,
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: t.accent),
                const SizedBox(width: Gsp.sp3),
                Expanded(child: Text('Accent card — highlights one important message.', style: GText.body2(t.textPrimary))),
              ]),
            ),
            const SizedBox(height: Gsp.sp3),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Gsp.cardPad),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Stock Material Card', style: GText.h3(t.textPrimary)),
                  const SizedBox(height: Gsp.sp1),
                  Text('Uses the themed CardTheme: surface, hairline border, no tint.', style: GText.body2(t.textSecondary)),
                  const SizedBox(height: Gsp.sp3),
                  const LinearProgressIndicator(value: 0.64),
                ]),
              ),
            ),
          ]),
        ),
      ]);

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _table(RoleThemeData t) => RoleCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: Gr.card,
          child: SizedBox(
            width: double.infinity,
            child: DataTable(columns: const [
              DataColumn(label: Text('MEDICINE')),
              DataColumn(label: Text('BATCH')),
              DataColumn(label: Text('STOCK'), numeric: true),
              DataColumn(label: Text('STATUS')),
            ], rows: [
              for (final (m, b, s, st) in [
                ('Paracetamol 500mg', 'PX-2207', 1240, AppChipState.active),
                ('Amoxicillin 250mg', 'AM-1180', 86, AppChipState.warning),
                ('Metformin 500mg', 'MF-0912', 0, AppChipState.danger),
              ])
                DataRow(cells: [
                  DataCell(Text(m)),
                  DataCell(Text(b, style: GText.body2(t.textSecondary))),
                  DataCell(Text('$s', style: GText.numeric(t.textPrimary))),
                  DataCell(AppChip(label: s == 0 ? 'OUT' : (s < 100 ? 'LOW' : 'OK'), state: st)),
                ]),
            ]),
          ),
        ),
      );
}
