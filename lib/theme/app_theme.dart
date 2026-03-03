// lib/theme/app_theme.dart
// Role-Based Theming System — 60/30/10 Color Rule
// 60% = dominant background/surface (neutral, spacious)
// 30% = secondary/supporting UI elements (cards, panels, accents)
// 10% = accent/highlight (calls to action, key metrics, brand)
import 'package:flutter/material.dart';

enum RoleTheme {
  chairman,
  ceo,
  admin,
  manager,
  doctor,
  supervisor,
  dispenser,
  receptionist,
}

class RoleThemeData {
  final String roleLabel;

  // ── 60% — Dominant backgrounds ───────────────────────────────────────────
  final Color bg;          // Main app background (60%)
  final Color bgCard;      // Card surfaces (part of 60%)
  final Color bgCardAlt;   // Alternate card / input fill
  final Color bgRule;      // Dividers, borders

  // ── 30% — Supporting UI ──────────────────────────────────────────────────
  final Color accent;        // Primary accent (30% role)
  final Color accentLight;   // Lighter tint of accent
  final Color accentMuted;   // Very light tint for badge backgrounds

  // ── Text hierarchy ───────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // ── 10% — Semantic pops ──────────────────────────────────────────────────
  final Color danger;
  final Color zakat;
  final Color nonZakat;
  final Color gmwf;

  // ── Summary card fills (deep, rich, white-text-safe) ─────────────────────
  final Color cardFillTokens;
  final Color cardFillPrescriptions;
  final Color cardFillDispensary;

  // ── New: Distribution / chart colors ─────────────────────────────────────
  final Color chartBar1;
  final Color chartBar2;
  final Color chartBar3;
  final Color chartGrid;

  const RoleThemeData({
    required this.roleLabel,
    required this.bg,
    required this.bgCard,
    required this.bgCardAlt,
    required this.bgRule,
    required this.accent,
    required this.accentLight,
    required this.accentMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.danger,
    required this.zakat,
    required this.nonZakat,
    required this.gmwf,
    required this.cardFillTokens,
    required this.cardFillPrescriptions,
    required this.cardFillDispensary,
    required this.chartBar1,
    required this.chartBar2,
    required this.chartBar3,
    required this.chartGrid,
  });

  // ── Tier 1 — Chairman: Champagne Gold on Warm Ivory ──────────────────────
  static const RoleThemeData _chairman = RoleThemeData(
    roleLabel:            'CHAIRMAN',
    bg:                   Color(0xFFF7F5F0),
    bgCard:               Color(0xFFFFFFFF),
    bgCardAlt:            Color(0xFFF2EFE8),
    bgRule:               Color(0xFFE8E3D8),
    accent:               Color(0xFFB8860B),
    accentLight:          Color(0xFFD4A843),
    accentMuted:          Color(0xFFFDF4DC),
    textPrimary:          Color(0xFF1C1812),
    textSecondary:        Color(0xFF5C5242),
    textTertiary:         Color(0xFFA09078),
    danger:               Color(0xFFDC2626),
    zakat:                Color(0xFF15803D),
    nonZakat:             Color(0xFF1D4ED8),
    gmwf:                 Color(0xFFB8860B),
    cardFillTokens:       Color(0xFF14532D),
    cardFillPrescriptions:Color(0xFF1E3A5F),
    cardFillDispensary:   Color(0xFF78350F),
    chartBar1:            Color(0xFFB8860B),
    chartBar2:            Color(0xFF15803D),
    chartBar3:            Color(0xFF1D4ED8),
    chartGrid:            Color(0xFFE8E3D8),
  );

  // ── Tier 2 — CEO: Midnight Navy on Crisp White ───────────────────────────
  static const RoleThemeData _ceo = RoleThemeData(
    roleLabel:            'CEO',
    bg:                   Color(0xFFF4F6FB),
    bgCard:               Color(0xFFFFFFFF),
    bgCardAlt:            Color(0xFFEFF2F9),
    bgRule:               Color(0xFFDDE3EE),
    accent:               Color(0xFF0F2356),
    accentLight:          Color(0xFF1D3A80),
    accentMuted:          Color(0xFFE8EDF8),
    textPrimary:          Color(0xFF080F24),
    textSecondary:        Color(0xFF3D4F72),
    textTertiary:         Color(0xFF8A96B5),
    danger:               Color(0xFFDC2626),
    zakat:                Color(0xFF059669),
    nonZakat:             Color(0xFF2563EB),
    gmwf:                 Color(0xFFD97706),
    cardFillTokens:       Color(0xFF064E3B),
    cardFillPrescriptions:Color(0xFF0F2356),
    cardFillDispensary:   Color(0xFF78350F),
    chartBar1:            Color(0xFF0F2356),
    chartBar2:            Color(0xFF059669),
    chartBar3:            Color(0xFF2563EB),
    chartGrid:            Color(0xFFDDE3EE),
  );

  // ── Tier 3 — Staff: Slate Blue on Soft Warm White ────────────────────────
  static const RoleThemeData _staff = RoleThemeData(
    roleLabel:            'STAFF',
    bg:                   Color(0xFFF3F1EE),
    bgCard:               Color(0xFFFFFFFF),
    bgCardAlt:            Color(0xFFF7F6F3),
    bgRule:               Color(0xFFE2DED8),
    accent:               Color(0xFF334E7B),
    accentLight:          Color(0xFF4A6FA5),
    accentMuted:          Color(0xFFDCE8F5),
    textPrimary:          Color(0xFF1A1E2A),
    textSecondary:        Color(0xFF4A5568),
    textTertiary:         Color(0xFF8A99B0),
    danger:               Color(0xFFB91C1C),
    zakat:                Color(0xFF166534),
    nonZakat:             Color(0xFF1E40AF),
    gmwf:                 Color(0xFF92400E),
    cardFillTokens:       Color(0xFF14532D),
    cardFillPrescriptions:Color(0xFF1E3A5F),
    cardFillDispensary:   Color(0xFF713F12),
    chartBar1:            Color(0xFF334E7B),
    chartBar2:            Color(0xFF166534),
    chartBar3:            Color(0xFF1E40AF),
    chartGrid:            Color(0xFFE2DED8),
  );

  factory RoleThemeData.of(RoleTheme role) {
    switch (role) {
      case RoleTheme.chairman:     return _chairman;
      case RoleTheme.ceo:          return _ceo;
      case RoleTheme.admin:        return _staff._withLabel('ADMIN');
      case RoleTheme.manager:      return _staff._withLabel('MANAGER');
      case RoleTheme.doctor:       return _staff._withLabel('DOCTOR');
      case RoleTheme.supervisor:   return _staff._withLabel('SUPERVISOR');
      case RoleTheme.dispenser:    return _staff._withLabel('DISPENSER');
      case RoleTheme.receptionist: return _staff._withLabel('RECEPTIONIST');
    }
  }

  static RoleTheme fromString(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':     return RoleTheme.chairman;
      case 'ceo':          return RoleTheme.ceo;
      case 'manager':      return RoleTheme.manager;
      case 'doctor':       return RoleTheme.doctor;
      case 'supervisor':   return RoleTheme.supervisor;
      case 'dispenser':    return RoleTheme.dispenser;
      case 'receptionist': return RoleTheme.receptionist;
      default:             return RoleTheme.admin;
    }
  }

  RoleThemeData _withLabel(String label) => RoleThemeData(
    roleLabel:            label,
    bg:                   bg,
    bgCard:               bgCard,
    bgCardAlt:            bgCardAlt,
    bgRule:               bgRule,
    accent:               accent,
    accentLight:          accentLight,
    accentMuted:          accentMuted,
    textPrimary:          textPrimary,
    textSecondary:        textSecondary,
    textTertiary:         textTertiary,
    danger:               danger,
    zakat:                zakat,
    nonZakat:             nonZakat,
    gmwf:                 gmwf,
    cardFillTokens:       cardFillTokens,
    cardFillPrescriptions:cardFillPrescriptions,
    cardFillDispensary:   cardFillDispensary,
    chartBar1:            chartBar1,
    chartBar2:            chartBar2,
    chartBar3:            chartBar3,
    chartGrid:            chartGrid,
  );
}

// ── Shared luxury decoration helpers ────────────────────────────────────────

class LuxuryDeco {
  static BoxDecoration heroDecoration(Color from, Color to, Color accent) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [from, to],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withOpacity(0.20), width: 1),
      boxShadow: [
        BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 32,
            offset: const Offset(0, 8)),
      ],
    );
  }

  static BoxDecoration cardDecoration(Color bg, Color accent) {
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent.withOpacity(0.15), width: 0.8),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4)),
      ],
    );
  }

  static Widget label(String text, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
                color: accent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(text,
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            )),
      ]),
    );
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class LuxuryLoader extends StatelessWidget {
  final Color color;
  final Color bg;
  const LuxuryLoader({super.key, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                  color: color, strokeWidth: 2.5),
            ),
            const SizedBox(height: 20),
            Text('Loading…',
                style: TextStyle(
                    color: color.withOpacity(0.6),
                    fontSize: 14,
                    letterSpacing: 1)),
          ]),
        ),
      );
}

class LuxuryLoadCard extends StatelessWidget {
  final Color color;
  final double height;
  const LuxuryLoadCard(
      {super.key, required this.color, required this.height});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
            child:
                CircularProgressIndicator(color: color, strokeWidth: 2)),
      );
}

class RevenueBanner extends StatelessWidget {
  final RoleThemeData t;
  final int revenue;
  final int tokens;
  final int dispensed;
  final String? subtitle;

  const RevenueBanner({
    super.key,
    required this.t,
    required this.revenue,
    required this.tokens,
    required this.dispensed,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            t.accent.withOpacity(0.15),
            t.accent.withOpacity(0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.accent.withOpacity(0.25), width: 1),
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total Revenue',
                style: TextStyle(
                    color: t.textTertiary,
                    fontSize: 13,
                    letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text(
              'PKR ${_fmt(revenue)}',
              style: TextStyle(
                  color: t.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style:
                      TextStyle(color: t.textTertiary, fontSize: 11)),
            ],
          ]),
        ),
        _statPill(
            t, Icons.confirmation_number_outlined, '$tokens', 'Tokens'),
        const SizedBox(width: 12),
        _statPill(t, Icons.local_pharmacy_outlined, '$dispensed',
            'Dispensed'),
      ]),
    );
  }

  Widget _statPill(
      RoleThemeData t, IconData icon, String val, String lbl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.accentMuted.withOpacity(0.4)),
      ),
      child: Column(children: [
        Icon(icon, color: t.accentLight, size: 18),
        const SizedBox(height: 6),
        Text(val,
            style: TextStyle(
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(lbl,
            style: TextStyle(color: t.textTertiary, fontSize: 11)),
      ]),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class PatientTypeCard extends StatelessWidget {
  final RoleThemeData t;
  final String label;
  final int count;
  final int feePerPatient;
  final Color color;
  final IconData? icon;

  const PatientTypeCard({
    super.key,
    required this.t,
    required this.label,
    required this.count,
    required this.feePerPatient,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon ?? Icons.local_hospital_rounded,
              color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text('$count',
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
        if (feePerPatient > 0)
          Text(
            'PKR ${count * feePerPatient}',
            style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
      ]),
    );
  }
}

class RatioBar extends StatelessWidget {
  final int zakat;
  final int nonZakat;
  final int gmwf;
  final int total;
  final RoleThemeData t;

  const RatioBar({
    super.key,
    required this.zakat,
    required this.nonZakat,
    required this.gmwf,
    required this.total,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final zp = total > 0 ? (zakat / total * 100).round() : 0;
    final np = total > 0 ? (nonZakat / total * 100).round() : 0;
    final gp = total > 0 ? (gmwf / total * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accentMuted.withOpacity(0.3)),
      ),
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            if (zakat > 0)
              Expanded(
                  flex: zakat,
                  child: Container(height: 10, color: t.zakat)),
            if (nonZakat > 0)
              Expanded(
                  flex: nonZakat,
                  child: Container(height: 10, color: t.nonZakat)),
            if (gmwf > 0)
              Expanded(
                  flex: gmwf,
                  child: Container(height: 10, color: t.gmwf)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _leg(t.zakat, 'Zakat', '$zp%'),
          _leg(t.nonZakat, 'Non-Zakat', '$np%'),
          _leg(t.gmwf, 'GMWF', '$gp%'),
        ]),
      ]),
    );
  }

  Widget _leg(Color c, String label, String pct) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text('$label ',
            style: TextStyle(color: t.textTertiary, fontSize: 12)),
        Text(pct,
            style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ]);
}