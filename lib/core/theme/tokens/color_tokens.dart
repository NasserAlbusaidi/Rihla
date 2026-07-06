import 'package:flutter/material.dart';

/// Typed color token set for the Falaj (Gulf Modern travel ledger) direction.
///
/// All fields are final Color values. Gradient tokens are computed getters
/// (LinearGradient is not const-constructable, so they cannot be fields).
///
/// Use [AppColorTokens.light] for the default light palette instance.
///
/// **Migration note:** field names — and many per-field descriptors below —
/// are historical (inherited from earthy/teal/saffron iterations) and remain
/// stable to protect existing call sites, so some still read in the older
/// tonal vocabulary (saffron / sage / rust / paper). The *values* are the
/// Falaj palette (Muscat plaster / night navigation). Trust the role and
/// `docs/DESIGN.md` §2 (the SSOT), not the field name. Per-field hex citations
/// were intentionally dropped — the value one line away is the truth.
final class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.brightness,
    required this.primary,
    required this.scaffoldBackground,
    required this.cardSurface,
    required this.inputFill,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnPrimary,
    required this.success,
    required this.successText,
    required this.error,
    required this.errorText,
    required this.disabled,
    required this.disabledText,
    required this.focusRing,
    required this.selectionFill,
    required this.moduleLedger,
    required this.moduleLedgerLight,
    required this.moduleGear,
    required this.moduleGearLight,
    required this.moduleLogistics,
    required this.moduleLogisticsLight,
    required this.moduleVault,
    required this.moduleVaultLight,
    required this.moduleActivity,
    required this.moduleActivityLight,
    required this.moduleMemories,
    required this.moduleMemoriesLight,
    required this.headerGradientStart,
    required this.headerGradientEnd,
    required this.offlineBannerBackground,
    required this.bottomNavBackground,
    required this.bottomNavActiveIcon,
    required this.bottomNavInactiveIcon,
    required this.inputFillWarm,
    required this.focusBorderWarm,
    required this.borderWarm,
    required this.warning,
    required this.primaryDark,
    // Saffron-direction additions:
    required this.paperDeep,
    required this.cardSoft,
    required this.ink2,
    required this.saffronSoft,
    required this.saffronTint,
    required this.rule,
    required this.rule2,
    required this.cat1,
    required this.cat2,
    required this.cat3,
    required this.cat4,
    required this.cat5,
    required this.cat6,
  });

  /// Which brightness variant this instance represents.
  final Brightness brightness;

  /// Saffron — primary action color (buttons, FABs, focused inputs, links).
  final Color primary;

  /// Paper — scaffold/page background.
  final Color scaffoldBackground;

  /// White — card surface.
  final Color cardSurface;

  /// Card-soft — input fill.
  final Color inputFill;

  /// 8% ink hairline border (solid approximation).
  final Color border;

  /// Ink — primary body text.
  final Color textPrimary;

  /// Ink-3 — secondary text.
  final Color textSecondary;

  /// Ink-4 — decorative-only tertiary text. Below AA contrast — never use for functional labels.
  final Color textMuted;

  /// White on saffron — primary button label.
  final Color textOnPrimary;

  /// Sage — semantic positive surface (badge fill, "owed to you" tone).
  final Color success;

  /// Sage-dark — WCAG-safe positive text.
  final Color successText;

  /// Rust — semantic negative surface ("you owe" tone).
  final Color error;

  /// Rust-dark — WCAG-safe negative text.
  final Color errorText;

  /// Card-soft — disabled control background.
  final Color disabled;

  /// Ink-4 — disabled text.
  final Color disabledText;

  /// Saffron focus ring — matches primary.
  final Color focusRing;

  /// Saffron-tint — selected chip/item background.
  final Color selectionFill;

  /// Ledger module accent — saffron (the only colored module per locked direction).
  final Color moduleLedger;

  /// Ledger module light tint.
  final Color moduleLedgerLight;

  /// Gear module accent — ink-3 (modules differentiate by icon, not color).
  final Color moduleGear;

  /// Gear module light tint — card-soft.
  final Color moduleGearLight;

  /// Logistics module accent — ink-3.
  final Color moduleLogistics;

  /// Logistics module light tint — card-soft.
  final Color moduleLogisticsLight;

  /// Vault module accent — ink-3.
  final Color moduleVault;

  /// Vault module light tint — card-soft.
  final Color moduleVaultLight;

  /// Activity module accent — ink-3.
  final Color moduleActivity;

  /// Activity module light tint — card-soft.
  final Color moduleActivityLight;

  /// Memories module accent — ink-3.
  final Color moduleMemories;

  /// Memories module light tint — card-soft.
  final Color moduleMemoriesLight;

  /// Ink — header gradient start.
  final Color headerGradientStart;

  /// Ink-2 — header gradient end.
  final Color headerGradientEnd;

  /// Offline indicator — warning hue, re-hued off the old amber to clear brass.
  final Color offlineBannerBackground;

  /// Paper — bottom nav surface.
  final Color bottomNavBackground;

  /// Saffron — active tab icon.
  final Color bottomNavActiveIcon;

  /// Ink-4 — inactive tab icon.
  final Color bottomNavInactiveIcon;

  /// Card-soft — warm form field fill alias of [inputFill].
  final Color inputFillWarm;

  /// Saffron — warm form focus indicator.
  final Color focusBorderWarm;

  /// Border — warm enabled border alias.
  final Color borderWarm;

  /// Warning — used for warning badges and alerts (re-hued off the old amber to clear brass).
  final Color warning;

  /// Saffron-dark — paired with [primary] for CTA gradient.
  final Color primaryDark;

  // ────────── saffron-direction additions ──────────

  /// Paper-deep — secondary paper tone for layered surfaces.
  final Color paperDeep;

  /// Card-soft — between [cardSurface] and [scaffoldBackground].
  final Color cardSoft;

  /// Ink-2 — between [textPrimary] (ink) and [textSecondary] (ink-3).
  final Color ink2;

  /// Saffron-soft. Used for saffron chip backgrounds and journey-glyph fills.
  final Color saffronSoft;

  /// Saffron-tint. Lightest saffron, used for selected chip backgrounds.
  final Color saffronTint;

  /// Rule — 8% ink hairline divider. Distinct from [border] which is more solid.
  final Color rule;

  /// Rule-2 — 14% ink hairline, slightly stronger.
  final Color rule2;

  /// Category palette — food.
  final Color cat1;

  /// Category palette — lodging.
  final Color cat2;

  /// Category palette — transit.
  final Color cat3;

  /// Category palette — groceries.
  final Color cat4;

  /// Category palette — activities.
  final Color cat5;

  /// Category palette — other.
  final Color cat6;

  /// Computed dark header gradient (not const — LinearGradient is not const-constructable).
  LinearGradient get headerGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [headerGradientStart, headerGradientEnd],
      );

  /// Saffron-to-saffron-dark gradient for CTA buttons and accents.
  LinearGradient get primaryGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, primaryDark],
      );

  /// Default Falaj light palette instance.
  static const AppColorTokens light = AppColorTokens(
    brightness: Brightness.light,
    primary: Color(0xFF8A5D0D), // Saffron
    scaffoldBackground: Color(0xFFF6F7F5), // Paper
    cardSurface: Color(0xFFFFFFFF), // White
    inputFill: Color(0xFFF1F2ED), // Card-soft
    border: Color(0xFFE3E6E0), // 8% ink approximation
    textPrimary: Color(0xFF1B1F1E), // Ink
    textSecondary: Color(0xFF5C6462), // Ink-3
    textMuted: Color(0xFF8B918D), // Ink-4 (decorative only)
    textOnPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF1F7A5C), // Sage
    successText: Color(0xFF175A44), // Sage-dark
    error: Color(0xFFB03A48), // Rust
    errorText: Color(0xFF8A2430), // Rust-dark
    disabled: Color(0xFFF1F2ED), // Card-soft
    disabledText: Color(0xFF8B918D), // Ink-4
    focusRing: Color(0xFF8A5D0D), // Saffron
    selectionFill: Color(0xFFF1F2DF), // Saffron-tint
    moduleLedger: Color(0xFF8A5D0D), // Saffron — sole colored module
    moduleLedgerLight: Color(0xFFF1F2DF),
    moduleGear: Color(0xFF5C6462), // Ink-3 — neutral
    moduleGearLight: Color(0xFFF1F2ED),
    moduleLogistics: Color(0xFF5C6462),
    moduleLogisticsLight: Color(0xFFF1F2ED),
    moduleVault: Color(0xFF5C6462),
    moduleVaultLight: Color(0xFFF1F2ED),
    moduleActivity: Color(0xFF5C6462),
    moduleActivityLight: Color(0xFFF1F2ED),
    moduleMemories: Color(0xFF5C6462),
    moduleMemoriesLight: Color(0xFFF1F2ED),
    headerGradientStart: Color(0xFF1B1F1E), // Ink
    headerGradientEnd: Color(0xFF333A38), // Ink-2
    offlineBannerBackground: Color(0xFFC2410C), // Warning (re-hued off amber)
    bottomNavBackground: Color(0xFFF6F7F5), // Paper
    bottomNavActiveIcon: Color(0xFF8A5D0D), // Saffron
    bottomNavInactiveIcon: Color(0xFF8B918D), // Ink-4
    inputFillWarm: Color(0xFFF1F2ED), // Card-soft alias
    focusBorderWarm: Color(0xFF8A5D0D), // Saffron
    borderWarm: Color(0xFFE3E6E0), // 8% ink alias
    warning: Color(0xFFC2410C), // Warning (re-hued off amber)
    primaryDark: Color(0xFF6F4A08), // Saffron-dark
    // Appended saffron tokens:
    paperDeep: Color(0xFFECEEE8),
    cardSoft: Color(0xFFF1F2ED),
    ink2: Color(0xFF333A38),
    saffronSoft: Color(0xFFE3E4C9),
    saffronTint: Color(0xFFF1F2DF),
    rule: Color(0xFFE3E6E0), // 8% ink solid approximation
    rule2: Color(0xFFCDD2CA), // 14% ink solid approximation
    cat1: Color(0xFF9C4F2E), // food
    cat2: Color(0xFF41708F), // lodging
    cat3: Color(0xFF575E93), // transit
    cat4: Color(0xFF6C7A33), // groceries
    cat5: Color(0xFF984B7C), // activities
    cat6: Color(0xFF4D5A6A), // other
  );

  /// Dark palette instance — Falaj, dark variant.
  ///
  /// Tuned for production (#900 PR-4 — DESIGN.md §13 D5 resolved): card
  /// surface tint, the five previously-missing component themes, and input
  /// hint contrast were all brought up to the night-navigation spec.
  static const AppColorTokens dark = AppColorTokens(
    brightness: Brightness.dark,
    primary: Color(0xFFD9A845), // Saffron-light for dark mode
    scaffoldBackground: Color(0xFF111514), // Paper-dark
    cardSurface: Color(0xFF1E2422), // Card-dark — lifted from #1A201E (#900): elevation reads by tint, not shadow
    inputFill: Color(0xFF242B28), // Card-soft-dark
    border: Color(0xFF2A322F), // Rule on dark
    textPrimary: Color(0xFFECEFEA), // Ink-light
    textSecondary: Color(0xFF9AA39E), // Ink-3-light
    textMuted: Color(0xFF6E7773), // Ink-4-light
    textOnPrimary: Color(0xFF1B1F1E),
    success: Color(0xFF4FBE8F), // Sage-light
    successText: Color(0xFF7FD6AE),
    error: Color(0xFFE0707B), // Rust-light
    errorText: Color(0xFFF0A3AB),
    disabled: Color(0xFF242B28),
    disabledText: Color(0xFF6E7773),
    focusRing: Color(0xFFD9A845),
    selectionFill: Color(0xFF2C2A20),
    moduleLedger: Color(0xFFD9A845),
    moduleLedgerLight: Color(0xFF2C2A20),
    moduleGear: Color(0xFF9AA39E),
    moduleGearLight: Color(0xFF242B28),
    moduleLogistics: Color(0xFF9AA39E),
    moduleLogisticsLight: Color(0xFF242B28),
    moduleVault: Color(0xFF9AA39E),
    moduleVaultLight: Color(0xFF242B28),
    moduleActivity: Color(0xFF9AA39E),
    moduleActivityLight: Color(0xFF242B28),
    moduleMemories: Color(0xFF9AA39E),
    moduleMemoriesLight: Color(0xFF242B28),
    headerGradientStart: Color(0xFF0C0F0E),
    headerGradientEnd: Color(0xFF1A201E),
    offlineBannerBackground: Color(0xFFE8703A),
    bottomNavBackground: Color(0xFF111514),
    bottomNavActiveIcon: Color(0xFFD9A845),
    bottomNavInactiveIcon: Color(0xFF6E7773),
    inputFillWarm: Color(0xFF242B28),
    focusBorderWarm: Color(0xFFD9A845),
    borderWarm: Color(0xFF2A322F),
    warning: Color(0xFFE8703A),
    primaryDark: Color(0xFFB8862B),
    paperDeep: Color(0xFF0C0F0E),
    cardSoft: Color(0xFF242B28),
    ink2: Color(0xFFC9CFC9),
    saffronSoft: Color(0xFF3A3626),
    saffronTint: Color(0xFF2C2A20),
    rule: Color(0xFF2A322F),
    rule2: Color(0xFF3A433F),
    cat1: Color(0xFFD08A63),
    cat2: Color(0xFF7FA9C4),
    cat3: Color(0xFF8E96C9),
    cat4: Color(0xFFA6B56A),
    cat5: Color(0xFFC98BB0),
    cat6: Color(0xFF98A2A8),
  );

  @override
  AppColorTokens copyWith({
    Brightness? brightness,
    Color? primary,
    Color? scaffoldBackground,
    Color? cardSurface,
    Color? inputFill,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textOnPrimary,
    Color? success,
    Color? successText,
    Color? error,
    Color? errorText,
    Color? disabled,
    Color? disabledText,
    Color? focusRing,
    Color? selectionFill,
    Color? moduleLedger,
    Color? moduleLedgerLight,
    Color? moduleGear,
    Color? moduleGearLight,
    Color? moduleLogistics,
    Color? moduleLogisticsLight,
    Color? moduleVault,
    Color? moduleVaultLight,
    Color? moduleActivity,
    Color? moduleActivityLight,
    Color? moduleMemories,
    Color? moduleMemoriesLight,
    Color? headerGradientStart,
    Color? headerGradientEnd,
    Color? offlineBannerBackground,
    Color? bottomNavBackground,
    Color? bottomNavActiveIcon,
    Color? bottomNavInactiveIcon,
    Color? inputFillWarm,
    Color? focusBorderWarm,
    Color? borderWarm,
    Color? warning,
    Color? primaryDark,
    Color? paperDeep,
    Color? cardSoft,
    Color? ink2,
    Color? saffronSoft,
    Color? saffronTint,
    Color? rule,
    Color? rule2,
    Color? cat1,
    Color? cat2,
    Color? cat3,
    Color? cat4,
    Color? cat5,
    Color? cat6,
  }) {
    return AppColorTokens(
      brightness: brightness ?? this.brightness,
      primary: primary ?? this.primary,
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      cardSurface: cardSurface ?? this.cardSurface,
      inputFill: inputFill ?? this.inputFill,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      success: success ?? this.success,
      successText: successText ?? this.successText,
      error: error ?? this.error,
      errorText: errorText ?? this.errorText,
      disabled: disabled ?? this.disabled,
      disabledText: disabledText ?? this.disabledText,
      focusRing: focusRing ?? this.focusRing,
      selectionFill: selectionFill ?? this.selectionFill,
      moduleLedger: moduleLedger ?? this.moduleLedger,
      moduleLedgerLight: moduleLedgerLight ?? this.moduleLedgerLight,
      moduleGear: moduleGear ?? this.moduleGear,
      moduleGearLight: moduleGearLight ?? this.moduleGearLight,
      moduleLogistics: moduleLogistics ?? this.moduleLogistics,
      moduleLogisticsLight: moduleLogisticsLight ?? this.moduleLogisticsLight,
      moduleVault: moduleVault ?? this.moduleVault,
      moduleVaultLight: moduleVaultLight ?? this.moduleVaultLight,
      moduleActivity: moduleActivity ?? this.moduleActivity,
      moduleActivityLight: moduleActivityLight ?? this.moduleActivityLight,
      moduleMemories: moduleMemories ?? this.moduleMemories,
      moduleMemoriesLight: moduleMemoriesLight ?? this.moduleMemoriesLight,
      headerGradientStart: headerGradientStart ?? this.headerGradientStart,
      headerGradientEnd: headerGradientEnd ?? this.headerGradientEnd,
      offlineBannerBackground: offlineBannerBackground ?? this.offlineBannerBackground,
      bottomNavBackground: bottomNavBackground ?? this.bottomNavBackground,
      bottomNavActiveIcon: bottomNavActiveIcon ?? this.bottomNavActiveIcon,
      bottomNavInactiveIcon: bottomNavInactiveIcon ?? this.bottomNavInactiveIcon,
      inputFillWarm: inputFillWarm ?? this.inputFillWarm,
      focusBorderWarm: focusBorderWarm ?? this.focusBorderWarm,
      borderWarm: borderWarm ?? this.borderWarm,
      warning: warning ?? this.warning,
      primaryDark: primaryDark ?? this.primaryDark,
      paperDeep: paperDeep ?? this.paperDeep,
      cardSoft: cardSoft ?? this.cardSoft,
      ink2: ink2 ?? this.ink2,
      saffronSoft: saffronSoft ?? this.saffronSoft,
      saffronTint: saffronTint ?? this.saffronTint,
      rule: rule ?? this.rule,
      rule2: rule2 ?? this.rule2,
      cat1: cat1 ?? this.cat1,
      cat2: cat2 ?? this.cat2,
      cat3: cat3 ?? this.cat3,
      cat4: cat4 ?? this.cat4,
      cat5: cat5 ?? this.cat5,
      cat6: cat6 ?? this.cat6,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
      // Brightness is discrete — snap to `other` once t >= 0.5.
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: Color.lerp(primary, other.primary, t)!,
      scaffoldBackground: Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      disabledText: Color.lerp(disabledText, other.disabledText, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      selectionFill: Color.lerp(selectionFill, other.selectionFill, t)!,
      moduleLedger: Color.lerp(moduleLedger, other.moduleLedger, t)!,
      moduleLedgerLight: Color.lerp(moduleLedgerLight, other.moduleLedgerLight, t)!,
      moduleGear: Color.lerp(moduleGear, other.moduleGear, t)!,
      moduleGearLight: Color.lerp(moduleGearLight, other.moduleGearLight, t)!,
      moduleLogistics: Color.lerp(moduleLogistics, other.moduleLogistics, t)!,
      moduleLogisticsLight: Color.lerp(moduleLogisticsLight, other.moduleLogisticsLight, t)!,
      moduleVault: Color.lerp(moduleVault, other.moduleVault, t)!,
      moduleVaultLight: Color.lerp(moduleVaultLight, other.moduleVaultLight, t)!,
      moduleActivity: Color.lerp(moduleActivity, other.moduleActivity, t)!,
      moduleActivityLight: Color.lerp(moduleActivityLight, other.moduleActivityLight, t)!,
      moduleMemories: Color.lerp(moduleMemories, other.moduleMemories, t)!,
      moduleMemoriesLight: Color.lerp(moduleMemoriesLight, other.moduleMemoriesLight, t)!,
      headerGradientStart: Color.lerp(headerGradientStart, other.headerGradientStart, t)!,
      headerGradientEnd: Color.lerp(headerGradientEnd, other.headerGradientEnd, t)!,
      offlineBannerBackground: Color.lerp(offlineBannerBackground, other.offlineBannerBackground, t)!,
      bottomNavBackground: Color.lerp(bottomNavBackground, other.bottomNavBackground, t)!,
      bottomNavActiveIcon: Color.lerp(bottomNavActiveIcon, other.bottomNavActiveIcon, t)!,
      bottomNavInactiveIcon: Color.lerp(bottomNavInactiveIcon, other.bottomNavInactiveIcon, t)!,
      inputFillWarm: Color.lerp(inputFillWarm, other.inputFillWarm, t)!,
      focusBorderWarm: Color.lerp(focusBorderWarm, other.focusBorderWarm, t)!,
      borderWarm: Color.lerp(borderWarm, other.borderWarm, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      paperDeep: Color.lerp(paperDeep, other.paperDeep, t)!,
      cardSoft: Color.lerp(cardSoft, other.cardSoft, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      saffronSoft: Color.lerp(saffronSoft, other.saffronSoft, t)!,
      saffronTint: Color.lerp(saffronTint, other.saffronTint, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      rule2: Color.lerp(rule2, other.rule2, t)!,
      cat1: Color.lerp(cat1, other.cat1, t)!,
      cat2: Color.lerp(cat2, other.cat2, t)!,
      cat3: Color.lerp(cat3, other.cat3, t)!,
      cat4: Color.lerp(cat4, other.cat4, t)!,
      cat5: Color.lerp(cat5, other.cat5, t)!,
      cat6: Color.lerp(cat6, other.cat6, t)!,
    );
  }
}
