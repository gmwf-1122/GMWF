// lib/theme/app_theme.dart
//
// ── THEME OVERVIEW ────────────────────────────────────────────────────────────
//  Rank 1  Chairman     → Gold + Dark Navy       — top institutional authority
//  Rank 2  CEO          → Electric Blue + Navy   — executive leadership
//  Rank 3  HQ Manager   → Royal Purple / Plum    — corporate strategic
//  Rank 4  Branch Mgr   → Deep Sapphire Indigo   — strong local leadership
//  Rank 5  Admin        → Cool Grey-Blue / Slate — system administration
//  Rank 6  Supervisor   → Operational Emerald    — floor / ops control
//  Rank 7  Doctor       → Teal/Cyan clinical
//  Rank 8  Dispenser    → Purple-violet pharmacy
//  Rank 9  Receptionist → Warm-rose reception
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

enum RoleTheme {
  chairman,
  ceo,
  globalUser,     // cross-branch viewer – dark canvas, emerald accent
  admin,
  manager,        // generic manager / light-surface indigo
  hqManager,      // HQ Manager – same palette as manager, distinct label
  branchManager,  // Branch Manager – warm amber-brown, field authority
  doctor,
  supervisor,
  dispenser,
  receptionist,
  madrassa,
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
  final Color textSecondary;
  final Color textTertiary;

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

  final LinearGradient accentGradient;
  final Color glassTint;
  final bool isDarkCanvas;

  const RoleThemeData({
    required this.roleLabel,
    required this.bg,
    required this.bgCard,
    required this.bgCardAlt,
    required this.bgRule,
    required this.accent,
    required this.accentLight,
    required this.accentMuted,
    required this.accentGradient,
    required this.glassTint,
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
    this.isDarkCanvas = false,
  });

  // ── Chairman – deep navy canvas, warm gold accent ─────────────────────────
  // Evokes authority and institutional heritage.
  static const RoleThemeData _chairman = RoleThemeData(
    roleLabel:             'CHAIRMAN',
    isDarkCanvas:          true,
    bg:                    Color(0xFF090C10),
    bgCard:                Color(0xFF0D1117),
    bgCardAlt:             Color(0xFF161B22),
    bgRule:                Color(0xFF21262D),
    accent:                Color(0xFFD4A017),
    accentLight:           Color(0xFFF0C040),
    accentMuted:           Color(0xFF2A2106),
    accentGradient:        LinearGradient(colors: [Color(0xFFD4A017), Color(0xFFB8860B)]),
    glassTint:             Color(0x1AD4A017),
    textPrimary:           Color(0xFFE6EDF3),
    textSecondary:         Color(0xFFB1BAC4),
    textTertiary:          Color(0xFF8B949E),
    danger:                Color(0xFFF85149),
    zakat:                 Color(0xFF3FB950),
    nonZakat:              Color(0xFF79C0FF),
    gmwf:                  Color(0xFFD4A017),
    cardFillTokens:        Color(0xFFD4A017),
    cardFillPrescriptions: Color(0xFFC78800),
    cardFillDispensary:    Color(0xFFAD6F00),
    chartBar1:             Color(0xFFD4A017),
    chartBar2:             Color(0xFF3FB950),
    chartBar3:             Color(0xFF79C0FF),
    chartGrid:             Color(0xFF21262D),
  );

  // ── CEO – dark navy canvas, electric-blue accent ──────────────────────────
  // Distinct from chairman (blue vs gold) – forward-looking, decisive.
  static const RoleThemeData _ceo = RoleThemeData(
    roleLabel:             'CEO',
    isDarkCanvas:          true,
    bg:                    Color(0xFF090C10),
    bgCard:                Color(0xFF0D1117),
    bgCardAlt:             Color(0xFF161B22),
    bgRule:                Color(0xFF21262D),
    accent:                Color(0xFF388BFF),
    accentLight:           Color(0xFF58A6FF),
    accentMuted:           Color(0xFF051D3A),
    accentGradient:        LinearGradient(colors: [Color(0xFF388BFF), Color(0xFF1F6FEB)]),
    glassTint:             Color(0x1A388BFF),
    textPrimary:           Color(0xFFE6EDF3),
    textSecondary:         Color(0xFFB1BAC4),
    textTertiary:          Color(0xFF8B949E),
    danger:                Color(0xFFF85149),
    zakat:                 Color(0xFF3FB950),
    nonZakat:              Color(0xFF79C0FF),
    gmwf:                  Color(0xFFD4A017),
    cardFillTokens:        Color(0xFF388BFF),
    cardFillPrescriptions: Color(0xFF1F6FEB),
    cardFillDispensary:    Color(0xFF0D4A9A),
    chartBar1:             Color(0xFF388BFF),
    chartBar2:             Color(0xFF3FB950),
    chartBar3:             Color(0xFFD4A017),
    chartGrid:             Color(0xFF21262D),
  );

  // ── Global User – dark canvas, emerald-green accent ───────────────────────
  // Cross-branch viewer: sees everything but holds no executive command.
  // Emerald sits clearly apart from CEO blue, chairman gold, and admin slate.
  static const RoleThemeData _globalUser = RoleThemeData(
    roleLabel:             'GLOBAL USER',
    isDarkCanvas:          true,
    bg:                    Color(0xFF080E0B),
    bgCard:                Color(0xFF0C1410),
    bgCardAlt:             Color(0xFF111D16),
    bgRule:                Color(0xFF1A2E22),
    accent:                Color(0xFF2EA878),
    accentLight:           Color(0xFF3EC68D),
    accentMuted:           Color(0xFF052514),
    accentGradient:        LinearGradient(colors: [Color(0xFF2EA878), Color(0xFF1A7A54)]),
    glassTint:             Color(0x1A2EA878),
    textPrimary:           Color(0xFFDCF0E8),
    textSecondary:         Color(0xFF9EC8B4),
    textTertiary:          Color(0xFF5A8A72),
    danger:                Color(0xFFF85149),
    zakat:                 Color(0xFF3FB950),
    nonZakat:              Color(0xFF79C0FF),
    gmwf:                  Color(0xFFD4A017),
    cardFillTokens:        Color(0xFF2EA878),
    cardFillPrescriptions: Color(0xFF1A7A54),
    cardFillDispensary:    Color(0xFF0E5038),
    chartBar1:             Color(0xFF2EA878),
    chartBar2:             Color(0xFF79C0FF),
    chartBar3:             Color(0xFFD4A017),
    chartGrid:             Color(0xFF1A2E22),
  );

  // ── Manager / HQ Manager – slate-indigo, light surface ───────────────────
  // Professional and clean — clearly different from the dark global-exec look.
  static const RoleThemeData _manager = RoleThemeData(
    roleLabel:             'MANAGER',
    isDarkCanvas:          false,
    bg:                    Color(0xFFF1F3F8),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFE8ECF5),
    bgRule:                Color(0xFFD0D7E8),
    accent:                Color(0xFF4455A4),
    accentLight:           Color(0xFF5B6FBF),
    accentMuted:           Color(0xFFDCE2F8),
    accentGradient:        LinearGradient(colors: [Color(0xFF4455A4), Color(0xFF5B6FBF)]),
    glassTint:             Color(0x1A4455A4),
    textPrimary:           Color(0xFF0E1526),
    textSecondary:         Color(0xFF2E3D6B),
    textTertiary:          Color(0xFF7080AC),
    danger:                Color(0xFFD32F2F),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFF4455A4),
    cardFillPrescriptions: Color(0xFF2E3D6B),
    cardFillDispensary:    Color(0xFF19254A),
    chartBar1:             Color(0xFF4455A4),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFD0D7E8),
  );

  // ── HQ Manager – deep teal / executive ───────────────────────────────────
  // Rank 3: corporate strategic authority — premium teal, calming confidence.
  static const RoleThemeData _hqManager = RoleThemeData(
    roleLabel:             'MANAGER',
    isDarkCanvas:          false,
    bg:                    Color(0xFFF0FAFA),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFE0F5F5),
    bgRule:                Color(0xFFB2E0E0),
    accent:                Color(0xFF00796B),
    accentLight:           Color(0xFF009688),
    accentMuted:           Color(0xFFCCEEEB),
    accentGradient:        LinearGradient(colors: [Color(0xFF00796B), Color(0xFF009688)]),
    glassTint:             Color(0x1A00796B),
    textPrimary:           Color(0xFF00251A),
    textSecondary:         Color(0xFF004D40),
    textTertiary:          Color(0xFF4DB6AC),
    danger:                Color(0xFFD32F2F),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFF00796B),
    cardFillPrescriptions: Color(0xFF004D40),
    cardFillDispensary:    Color(0xFF00332B),
    chartBar1:             Color(0xFF00796B),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFB2E0E0),
  );

  // ── Branch Manager – deep sapphire blue ──────────────────────────────────
  // Rank 4: strong local leadership — trustworthy, professional, below HQ purple.
  static const RoleThemeData _branchManager = RoleThemeData(
    roleLabel:             'BRANCH MANAGER',
    isDarkCanvas:          false,
    bg:                    Color(0xFFF2F5FC),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFE4EBFA),
    bgRule:                Color(0xFFC8D4EE),
    accent:                Color(0xFF2F4DA0),
    accentLight:           Color(0xFF4B6BD6),
    accentMuted:           Color(0xFFDCE5FF),
    accentGradient:        LinearGradient(colors: [Color(0xFF2F4DA0), Color(0xFF4B6BD6)]),
    glassTint:             Color(0x1A2F4DA0),
    textPrimary:           Color(0xFF0E1838),
    textSecondary:         Color(0xFF253570),
    textTertiary:          Color(0xFF6878B0),
    danger:                Color(0xFFD32F2F),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFF2F4DA0),
    cardFillPrescriptions: Color(0xFF1C3278),
    cardFillDispensary:    Color(0xFF4B6BD6),
    chartBar1:             Color(0xFF2F4DA0),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFC8D4EE),
  );

  // ── Admin / Global Admin – cool grey-blue ─────────────────────────────────
  static const RoleThemeData _admin = RoleThemeData(
    roleLabel:             'ADMIN',
    isDarkCanvas:          false,
    bg:                    Color(0xFFF4F5F8),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFEEF0F5),
    bgRule:                Color(0xFFDCE0EC),
    accent:                Color(0xFF3D5A9A),
    accentLight:           Color(0xFF5070B8),
    accentMuted:           Color(0xFFDCE5F8),
    accentGradient:        LinearGradient(colors: [Color(0xFF3D5A9A), Color(0xFF5070B8)]),
    glassTint:             Color(0x1A3D5A9A),
    textPrimary:           Color(0xFF131824),
    textSecondary:         Color(0xFF3A4A68),
    textTertiary:          Color(0xFF8090B8),
    danger:                Color(0xFFB91C1C),
    zakat:                 Color(0xFF2E7D32),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFFFA500),
    cardFillTokens:        Color(0xFF2C4280),
    cardFillPrescriptions: Color(0xFF3D5A9A),
    cardFillDispensary:    Color(0xFF1E2F60),
    chartBar1:             Color(0xFF3D5A9A),
    chartBar2:             Color(0xFF2E7D32),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFDCE0EC),
  );

  // ── Doctor – teal/cyan clinical ───────────────────────────────────────────
  static const RoleThemeData _doctor = RoleThemeData(
    roleLabel:             'DOCTOR',
    bg:                    Color(0xFFF0FDFD),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFE2F9F9),
    bgRule:                Color(0xFFB7E4E4),
    accent:                Color(0xFF0891B2),
    accentLight:           Color(0xFF06B6D4),
    accentMuted:           Color(0xFFD1F5F5),
    accentGradient:        LinearGradient(colors: [Color(0xFF0891B2), Color(0xFF06B6D4)]),
    glassTint:             Color(0x1A0891B2),
    textPrimary:           Color(0xFF083344),
    textSecondary:         Color(0xFF155E75),
    textTertiary:          Color(0xFF67A8B8),
    danger:                Color(0xFFE11D48),
    zakat:                 Color(0xFF166534),
    nonZakat:              Color(0xFF1D4ED8),
    gmwf:                  Color(0xFFEA580C),
    cardFillTokens:        Color(0xFF155E75),
    cardFillPrescriptions: Color(0xFF0891B2),
    cardFillDispensary:    Color(0xFF164E63),
    chartBar1:             Color(0xFF0891B2),
    chartBar2:             Color(0xFF166534),
    chartBar3:             Color(0xFF1D4ED8),
    chartGrid:             Color(0xFFB7E4E4),
  );

  // ── Supervisor – operational emerald green ───────────────────────────────
  // Rank 6: floor / ops control — fresh, active, productivity feel.
  static const RoleThemeData _supervisor = RoleThemeData(
    roleLabel:             'SUPERVISOR',
    bg:                    Color(0xFFF0FBF8),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFDEF5EE),
    bgRule:                Color(0xFFB2DDD4),
    accent:                Color(0xFF059669),
    accentLight:           Color(0xFF10B981),
    accentMuted:           Color(0xFFD1FAE5),
    accentGradient:        LinearGradient(colors: [Color(0xFF059669), Color(0xFF10B981)]),
    glassTint:             Color(0x1A059669),
    textPrimary:           Color(0xFF064E3B),
    textSecondary:         Color(0xFF065F46),
    textTertiary:          Color(0xFF34D399),
    danger:                Color(0xFFB91C1C),
    zakat:                 Color(0xFF388E3C),
    nonZakat:              Color(0xFF1565C0),
    gmwf:                  Color(0xFFE65100),
    cardFillTokens:        Color(0xFF0A7C66),
    cardFillPrescriptions: Color(0xFF065244),
    cardFillDispensary:    Color(0xFF13A989),
    chartBar1:             Color(0xFF0A7C66),
    chartBar2:             Color(0xFF388E3C),
    chartBar3:             Color(0xFF1565C0),
    chartGrid:             Color(0xFFB2DDD4),
  );

  // ── Dispenser – violet-purple pharmacy ───────────────────────────────────
  static const RoleThemeData _dispenser = RoleThemeData(
    roleLabel:             'DISPENSER',
    bg:                    Color(0xFFF8F4FF),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFF0E8FF),
    bgRule:                Color(0xFFDDD0F8),
    accent:                Color(0xFF7C3AED),
    accentLight:           Color(0xFF8B5CF6),
    accentMuted:           Color(0xFFEDE9FE),
    accentGradient:        LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)]),
    glassTint:             Color(0x1A7C3AED),
    textPrimary:           Color(0xFF2E1065),
    textSecondary:         Color(0xFF4C1D95),
    textTertiary:          Color(0xFF8B5CF6),
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

  // ── Receptionist – warm-rose ──────────────────────────────────────────────
  static const RoleThemeData _receptionist = RoleThemeData(
    roleLabel:             'RECEPTIONIST',
    bg:                    Color(0xFFFFF5F5),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFFFECEC),
    bgRule:                Color(0xFFF8D0D0),
    accent:                Color(0xFFE11D48),
    accentLight:           Color(0xFFF43F5E),
    accentMuted:           Color(0xFFFFF1F2),
    accentGradient:        LinearGradient(colors: [Color(0xFFE11D48), Color(0xFFF43F5E)]),
    glassTint:             Color(0x1AE11D48),
    textPrimary:           Color(0xFF4C0519),
    textSecondary:         Color(0xFF881337),
    textTertiary:          Color(0xFFE11D48),
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

  // ── Madrassa – royal indigo & soft gold ──────────────────────────────────
  // A scholarly, premium theme for the educational wing.
  static const RoleThemeData _madrassa = RoleThemeData(
    roleLabel:             'MADRASSA',
    isDarkCanvas:          false,
    bg:                    Color(0xFFFFFFFF),
    bgCard:                Color(0xFFFFFFFF),
    bgCardAlt:             Color(0xFFF8FAFF),
    bgRule:                Color(0xFFD8DEED),
    accent:                Color(0xFF4338CA), // Indigo
    accentLight:           Color(0xFF6366F1),
    accentMuted:           Color(0xFFE0E7FF),
    accentGradient:        LinearGradient(colors: [Color(0xFF4338CA), Color(0xFF6366F1)]),
    glassTint:             Color(0x1A4338CA),
    textPrimary:           Color(0xFF1E1B4B),
    textSecondary:         Color(0xFF3730A3),
    textTertiary:          Color(0xFF6366F1),
    danger:                Color(0xFFEF4444),
    zakat:                 Color(0xFF10B981),
    nonZakat:              Color(0xFF3B82F6),
    gmwf:                  Color(0xFFF59E0B), // Gold
    cardFillTokens:        Color(0xFF4338CA),
    cardFillPrescriptions: Color(0xFF3730A3),
    cardFillDispensary:    Color(0xFF312E81),
    chartBar1:             Color(0xFF4338CA),
    chartBar2:             Color(0xFF10B981),
    chartBar3:             Color(0xFFF59E0B),
    chartGrid:             Color(0xFFD8DEED),
  );

  // ── Factory ───────────────────────────────────────────────────────────────

  factory RoleThemeData.of(RoleTheme role, [Color? customAccent]) {
    RoleThemeData base;
    switch (role) {
      case RoleTheme.chairman:      base = _chairman; break;
      case RoleTheme.ceo:           base = _ceo; break;
      case RoleTheme.globalUser:    base = _globalUser; break;
      case RoleTheme.admin:         base = _admin; break;
      case RoleTheme.manager:       base = _manager; break;
      case RoleTheme.hqManager:     base = _hqManager; break;
      case RoleTheme.branchManager: base = _branchManager; break;
      case RoleTheme.doctor:        base = _doctor; break;
      case RoleTheme.supervisor:    base = _supervisor; break;
      case RoleTheme.dispenser:     base = _dispenser; break;
      case RoleTheme.receptionist:  base = _receptionist; break;
      case RoleTheme.madrassa:      base = _madrassa; break;
    }

    if (customAccent == null) return base;

    // Derived colors from custom accent
    final hsv = HSVColor.fromColor(customAccent);
    final light = hsv.withValue((hsv.value + 0.2).clamp(0.0, 1.0)).withSaturation((hsv.saturation - 0.1).clamp(0.0, 1.0)).toColor();
    final muted = hsv.withSaturation(0.1).withValue(0.95).toColor();
    final dark = hsv.withValue((hsv.value - 0.2).clamp(0.0, 1.0)).toColor();

    return RoleThemeData(
      roleLabel:             base.roleLabel,
      isDarkCanvas:          base.isDarkCanvas,
      bg:                    base.bg,
      bgCard:                base.bgCard,
      bgCardAlt:             base.bgCardAlt,
      bgRule:                base.bgRule,
      accent:                customAccent,
      accentLight:           light,
      accentMuted:           muted,
      accentGradient:        LinearGradient(colors: [customAccent, dark]),
      glassTint:             customAccent.withValues(alpha: 0.12),
      textPrimary:           base.textPrimary,
      textSecondary:         base.textSecondary,
      textTertiary:          base.textTertiary,
      danger:                base.danger,
      zakat:                 base.zakat,
      nonZakat:              base.nonZakat,
      gmwf:                  base.gmwf,
      cardFillTokens:        customAccent,
      cardFillPrescriptions: dark,
      cardFillDispensary:    base.cardFillDispensary,
      chartBar1:             customAccent,
      chartBar2:             base.chartBar2,
      chartBar3:             base.chartBar3,
      chartGrid:             base.chartGrid,
    );
  }

  static RoleTheme fromString(String role) {
    switch (role.toLowerCase().trim()) {
      case 'chairman':        return RoleTheme.chairman;
      case 'ceo':             return RoleTheme.ceo;
      case 'global user':     return RoleTheme.globalUser;
      case 'manager':
      case 'hq manager':      return RoleTheme.hqManager;
      case 'branch manager':  return RoleTheme.branchManager;
      case 'doctor':          return RoleTheme.doctor;
      case 'supervisor':      return RoleTheme.supervisor;
      case 'dispenser':       return RoleTheme.dispenser;
      case 'receptionist':    return RoleTheme.receptionist;
      case 'madrassa admin':
      case 'madrassa teacher':
      case 'madrassa guardian':
      case 'madrassa':        return RoleTheme.madrassa;
      case 'admin':
      case 'global admin':
      default:                return RoleTheme.admin;
    }
  }

  RoleThemeData _withLabel(String label) => RoleThemeData(
    roleLabel:             label,
    isDarkCanvas:          isDarkCanvas,
    bg:                    bg,
    bgCard:                bgCard,
    bgCardAlt:             bgCardAlt,
    bgRule:                bgRule,
    accent:                accent,
    accentLight:           accentLight,
    accentMuted:           accentMuted,
    accentGradient:        accentGradient,
    glassTint:             glassTint,
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

// ── Shared luxury decoration helpers ─────────────────────────────────────────

class LuxuryDeco {
  static BoxDecoration heroDecoration(Color from, Color to, Color accent) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [from, to],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: 0.20), width: 1),
      boxShadow: [
        BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 32,
            offset: const Offset(0, 8)),
      ],
    );
  }

  static BoxDecoration cardDecoration(Color bg, Color accent) {
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: 0.12), width: 1.2),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.04),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
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
                letterSpacing: 1.5)),
      ]),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

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
              child: CircularProgressIndicator(color: color, strokeWidth: 2.5),
            ),
            const SizedBox(height: 20),
            Text('Loading…',
                style: TextStyle(
                    color: color.withValues(alpha: 0.6),
                    fontSize: 14,
                    letterSpacing: 1)),
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
        child:
            Center(child: CircularProgressIndicator(color: color, strokeWidth: 2)),
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
            t.accent.withValues(alpha: 0.15),
            t.accent.withValues(alpha: 0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.accent.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Revenue',
                    style: TextStyle(
                        color: t.textTertiary,
                        fontSize: 13,
                        letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text('PKR ${_fmt(revenue)}',
                    style: TextStyle(
                        color: t.accent,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!,
                      style:
                          TextStyle(color: t.textTertiary, fontSize: 11)),
                ],
              ]),
        ),
        _statPill(t, Icons.confirmation_number_outlined, '$tokens', 'Tokens'),
        const SizedBox(width: 12),
        _statPill(
            t, Icons.local_pharmacy_outlined, '$dispensed', 'Dispensed'),
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
        border: Border.all(color: t.accentMuted.withValues(alpha: 0.4)),
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
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
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
          Text('PKR ${count * feePerPatient}',
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
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
        border: Border.all(color: t.accentMuted.withValues(alpha: 0.3)),
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