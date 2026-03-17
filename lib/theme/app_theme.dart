// lib/theme/app_theme.dart

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

  final Color bg;
  final Color bgCard;
  final Color bgCardAlt;
  final Color bgRule;

  final Color accent;
  final Color accentLight;
  final Color accentMuted;

  final Color textPrimary;
  final Color textSecondary;  final Color textTertiary;

  final Color danger;
  final Color zakat;
  final Color nonZakat;
  final Color gmwf;

  final Color cardFillTokens;
  final Color cardFillPrescriptions;
  final Color cardFillDispensary;

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
  static const RoleThemeData _chairman = RoleThemeData(
    roleLabel:             'CHAIRMAN',
    bg:                    Color(0xFFFAF7F0),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFF5EFE0),
    bgRule:                Color(0xFFEAE0C8),
    accent:                Color(0xFFC8880E), 
    accentLight:           Color(0xFFE8A020),
    accentMuted:           Color(0xFFFEF3DC),
    textPrimary:           Color(0xFF1A1508),
    textSecondary:         Color(0xFF4A3C20),
    textTertiary:          Color(0xFF9A8860),
    danger:                Color(0xFFDC2626),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFC8880E),
    cardFillTokens:        Color(0xFFC8880E),   
    cardFillPrescriptions: Color(0xFFB06010),   
    cardFillDispensary:    Color(0xFF8B4513), 
    chartBar1:             Color(0xFFC8880E),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFEAE0C8),
  );

  static const RoleThemeData _ceo = RoleThemeData(
    roleLabel:             'CEO',
    bg:                    Color(0xFFF0F4FF),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFE8EFFE),
    bgRule:                Color(0xFFCDD8F8),
    accent:                Color(0xFF1A3DAF),   
    accentLight:           Color(0xFF2952CC),
    accentMuted:           Color(0xFFDEE7FD),
    textPrimary:           Color(0xFF060D28),
    textSecondary:         Color(0xFF2A3A68),
    textTertiary:          Color(0xFF7080B8),
    danger:                Color(0xFFDC2626),
    zakat:                 Color(0xFF00897B),
    nonZakat:              Color(0xFF2952CC),
    gmwf:                  Color(0xFFE67C00),
    cardFillTokens:        Color(0xFF1A3DAF),  
    cardFillPrescriptions: Color(0xFF2D1FA3), 
    cardFillDispensary:    Color(0xFF0D2880),  
    chartBar1:             Color(0xFF1A3DAF),
    chartBar2:             Color(0xFF00897B),
    chartBar3:             Color(0xFF7C3AED),
    chartGrid:             Color(0xFFCDD8F8),
  );

  static const RoleThemeData _doctor = RoleThemeData(
    roleLabel:             'DOCTOR',
    bg:                    Color(0xFFF0FAFA),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFE4F5F5),
    bgRule:                Color(0xFFB8E0E0),
    accent:                Color(0xFF00838F),  
    accentLight:           Color(0xFF0097A7),
    accentMuted:           Color(0xFFD8F4F6),
    textPrimary:           Color(0xFF002830),
    textSecondary:         Color(0xFF2A6068),
    textTertiary:          Color(0xFF6AA8B0),
    danger:                Color(0xFFB91C1C),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFF006064),   
    cardFillPrescriptions: Color(0xFF00838F),   
    cardFillDispensary:    Color(0xFF004D55),   
    chartBar1:             Color(0xFF00838F),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFB8E0E0),
  );

  static const RoleThemeData _staff = RoleThemeData(
    roleLabel:             'STAFF',
    bg:                    Color(0xFFF4F5F8),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFEEF0F5),
    bgRule:                Color(0xFFDCE0EC),
    accent:                Color(0xFF3D5A9A), 
    accentLight:           Color(0xFF5070B8),
    accentMuted:           Color(0xFFDCE5F8),
    textPrimary:           Color(0xFF131824),
    textSecondary:         Color(0xFF3A4A68),
    textTertiary:          Color(0xFF8090B8),
    danger:                Color(0xFFB91C1C),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFF8B4513),
    cardFillTokens:        Color(0xFF2C4280),  
    cardFillPrescriptions: Color(0xFF3D5A9A), 
    cardFillDispensary:    Color(0xFF1E2F60),
    chartBar1:             Color(0xFF3D5A9A),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFDCE0EC),
  );

  static const RoleThemeData _supervisor = RoleThemeData(
    roleLabel:             'SUPERVISOR',
    bg:                    Color(0xFFF0F8F5),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFE2F3EC),
    bgRule:                Color(0xFFB8DDD0),
    accent:                Color(0xFF00695C),
    accentLight:           Color(0xFF00897B),
    accentMuted:           Color(0xFFD8F2EC),
    textPrimary:           Color(0xFF002820),
    textSecondary:         Color(0xFF285850),
    textTertiary:          Color(0xFF60988C),
    danger:                Color(0xFFB91C1C),
    zakat:                 Color(0xFF388E3C),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFF00695C),  
    cardFillPrescriptions: Color(0xFF004D44),  
    cardFillDispensary:    Color(0xFF00796B),
    chartBar1:             Color(0xFF00695C),
    chartBar2:             Color(0xFF388E3C),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFB8DDD0),
  );

  static const RoleThemeData _dispenser = RoleThemeData(
    roleLabel:             'DISPENSER',
    bg:                    Color(0xFFF8F4FF),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFF0E8FF),
    bgRule:                Color(0xFFDDD0F8),
    accent:                Color(0xFF6B35C8),   
    accentLight:           Color(0xFF8050E0),
    accentMuted:           Color(0xFFECE4FE),
    textPrimary:           Color(0xFF180830),
    textSecondary:         Color(0xFF3C2468),
    textTertiary:          Color(0xFF8868B8),
    danger:                Color(0xFFB91C1C),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFF6B35C8),  
    cardFillPrescriptions: Color(0xFF4A20A0),  
    cardFillDispensary:    Color(0xFF7B2FA8),   
    chartBar1:             Color(0xFF6B35C8),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFDDD0F8),
  );

  static const RoleThemeData _receptionist = RoleThemeData(
    roleLabel:             'RECEPTIONIST',
    bg:                    Color(0xFFFFF5F5),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFFFECEC),
    bgRule:                Color(0xFFF8D0D0),
    accent:                Color(0xFFC0392B),  
    accentLight:           Color(0xFFE04040),
    accentMuted:           Color(0xFFFFE5E5),
    textPrimary:           Color(0xFF280808),
    textSecondary:         Color(0xFF602020),
    textTertiary:          Color(0xFFB07070),
    danger:                Color(0xFFB91C1C),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFFC0392B), 
    cardFillPrescriptions: Color(0xFF962020),  
    cardFillDispensary:    Color(0xFFAD1457), 
    chartBar1:             Color(0xFFC0392B),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFF8D0D0),
  );

  factory RoleThemeData.of(RoleTheme role) {
    switch (role) {
      case RoleTheme.chairman:     return _chairman;
      case RoleTheme.ceo:          return _ceo;
      case RoleTheme.admin:        return _staff._withLabel('ADMIN');
      case RoleTheme.manager:      return _staff._withLabel('MANAGER');
      case RoleTheme.doctor:       return _doctor;
      case RoleTheme.supervisor:   return _supervisor;
      case RoleTheme.dispenser:    return _dispenser;
      case RoleTheme.receptionist: return _receptionist;
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
    roleLabel:             label,
    bg:                    bg,
    bgCard:                bgCard,
    bgCardAlt:             bgCardAlt,
    bgRule:                bgRule,
    accent:                accent,
    accentLight:           accentLight,
    accentMuted:           accentMuted,
    textPrimary:           textPrimary,
    textSecondary:         textSecondary,
    textTertiary:          textTertiary,
    danger:                danger,
    zakat:                 zakat,
    nonZakat:              nonZakat,
    gmwf:                  gmwf,
    cardFillTokens:        cardFillTokens,
    cardFillPrescriptions: cardFillPrescriptions,
    cardFillDispensary:    cardFillDispensary,
    chartBar1:             chartBar1,
    chartBar2:             chartBar2,
    chartBar3:             chartBar3,
    chartGrid:             chartGrid,
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
        BoxShadow(color: accent.withOpacity(0.06), blurRadius: 32, offset: const Offset(0, 8)),
      ],
    );
  }

  static BoxDecoration cardDecoration(Color bg, Color accent) {
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent.withOpacity(0.15), width: 0.8),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
      ],
    );
  }

  static Widget label(String text, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
            width: 3, height: 18,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(text,
            style: TextStyle(
                color: accent, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
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
              width: 40, height: 40,
              child: CircularProgressIndicator(color: color, strokeWidth: 2.5),
            ),
            const SizedBox(height: 20),
            Text('Loading…',
                style: TextStyle(color: color.withOpacity(0.6), fontSize: 14, letterSpacing: 1)),
          ]),
        ),
      );
}

class LuxuryLoadCard extends StatelessWidget {
  final Color color;
  final double height;
  const LuxuryLoadCard({super.key, required this.color, required this.height});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(child: CircularProgressIndicator(color: color, strokeWidth: 2)),
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
          colors: [t.accent.withOpacity(0.15), t.accent.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.accent.withOpacity(0.25), width: 1),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total Revenue',
                style: TextStyle(color: t.textTertiary, fontSize: 13, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text('PKR ${_fmt(revenue)}',
                style: TextStyle(
                    color: t.accent, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: TextStyle(color: t.textTertiary, fontSize: 11)),
            ],
          ]),
        ),
        _statPill(t, Icons.confirmation_number_outlined, '$tokens', 'Tokens'),
        const SizedBox(width: 12),
        _statPill(t, Icons.local_pharmacy_outlined, '$dispensed', 'Dispensed'),
      ]),
    );
  }

  Widget _statPill(RoleThemeData t, IconData icon, String val, String lbl) {
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
            style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(lbl, style: TextStyle(color: t.textTertiary, fontSize: 11)),
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
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon ?? Icons.local_hospital_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 3),
            Text('$count',
                style: TextStyle(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ),
        if (feePerPatient > 0)
          Text('PKR ${count * feePerPatient}',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
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
            if (zakat > 0) Expanded(flex: zakat, child: Container(height: 10, color: t.zakat)),
            if (nonZakat > 0) Expanded(flex: nonZakat, child: Container(height: 10, color: t.nonZakat)),
            if (gmwf > 0) Expanded(flex: gmwf, child: Container(height: 10, color: t.gmwf)),
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
            width: 10, height: 10,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text('$label ', style: TextStyle(color: t.textTertiary, fontSize: 12)),
        Text(pct,
            style: TextStyle(
                color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}