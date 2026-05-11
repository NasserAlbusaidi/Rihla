import 'package:flutter/material.dart';

import 'group_avatar_colors.dart';

/// Typed color token set for the saffron travel-journal direction (v2.0).
///
/// All fields are final Color values. Gradient tokens are computed getters
/// (LinearGradient is not const-constructable, so they cannot be fields).
///
/// Use [AppColorTokens.light] for the default light palette instance.
///
/// **Migration note:** field names are inherited from the prior earthy/teal
/// iterations and remain stable to protect existing call sites. Values are
/// remapped to the saffron palette; semantic groupings (success → sage,
/// error → rust, primary → saffron, scaffoldBackground → paper, etc.) are
/// documented per-field below.
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

  /// Saffron — primary action color (buttons, FABs, focused inputs, links). `#D17B2C`
  final Color primary;

  /// Paper — scaffold/page background. `#F6F1E6`
  final Color scaffoldBackground;

  /// White — card surface. `#FFFFFF`
  final Color cardSurface;

  /// Card-soft warm white — input fill. `#FBF7EE`
  final Color inputFill;

  /// 8% ink hairline border. `rgba(27,26,23,0.08)` solid approximation.
  final Color border;

  /// Ink — primary body text. `#1B1A17`
  final Color textPrimary;

  /// Ink-3 — secondary text. `#6B675D`
  final Color textSecondary;

  /// Ink-4 — decorative-only tertiary text. `#948F82`. Below AA contrast — never use for functional labels.
  final Color textMuted;

  /// White on saffron — primary button label. `#FFFFFF`
  final Color textOnPrimary;

  /// Sage — semantic positive surface (badge fill, "owed to you" tone). `#5C7A57`
  final Color success;

  /// Sage-dark — WCAG-safe positive text. `#3F5A3B`
  final Color successText;

  /// Rust — semantic negative surface ("you owe" tone). `#A84B33`
  final Color error;

  /// Rust-dark — WCAG-safe negative text. `#7A2F1F`
  final Color errorText;

  /// Card-soft — disabled control background. `#FBF7EE`
  final Color disabled;

  /// Ink-4 — disabled text. `#948F82`
  final Color disabledText;

  /// Saffron focus ring — matches primary. `#D17B2C`
  final Color focusRing;

  /// Saffron-tint — selected chip/item background. `#FBEED5`
  final Color selectionFill;

  /// Ledger module accent — saffron (the only colored module per locked direction). `#D17B2C`
  final Color moduleLedger;

  /// Ledger module light tint. `#FBEED5`
  final Color moduleLedgerLight;

  /// Gear module accent — ink-3 (modules differentiate by icon, not color). `#6B675D`
  final Color moduleGear;

  /// Gear module light tint — card-soft. `#FBF7EE`
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

  /// Ink — header gradient start. `#1B1A17`
  final Color headerGradientStart;

  /// Ink-2 — header gradient end. `#3D3A33`
  final Color headerGradientEnd;

  /// Amber offline indicator (semantic, palette-independent). `#F59E0B`
  final Color offlineBannerBackground;

  /// Paper — bottom nav surface. `#F6F1E6`
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

  /// Amber warning — used for warning badges and alerts. `#F59E0B`
  final Color warning;

  /// Saffron-dark — paired with [primary] for CTA gradient. `#B5641A`
  final Color primaryDark;

  // ────────── saffron-direction additions ──────────

  /// Paper-deep — secondary paper tone for layered surfaces. `#EFE8D7`
  final Color paperDeep;

  /// Card-soft — warm white between [cardSurface] and [scaffoldBackground]. `#FBF7EE`
  final Color cardSoft;

  /// Ink-2 — between [textPrimary] (ink) and [textSecondary] (ink-3). `#3D3A33`
  final Color ink2;

  /// Saffron-soft — `#F4DDB8`. Used for saffron chip backgrounds and journey-glyph fills.
  final Color saffronSoft;

  /// Saffron-tint — `#FBEED5`. Lightest saffron, used for selected chip backgrounds.
  final Color saffronTint;

  /// Rule — 8% ink hairline divider. Distinct from [border] which is more solid.
  final Color rule;

  /// Rule-2 — 14% ink hairline, slightly stronger.
  final Color rule2;

  /// Category palette — food. `#C2693B`
  final Color cat1;

  /// Category palette — lodging. `#4F7B96`
  final Color cat2;

  /// Category palette — transit. `#8C6A2F`
  final Color cat3;

  /// Category palette — groceries. `#6F7A3A`
  final Color cat4;

  /// Category palette — activities. `#94517A`
  final Color cat5;

  /// Category palette — other. `#4D5A6A`
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

  /// Deterministic avatar color for [groupId], theme-aware.
  ///
  /// Uses a stable FNV-like hash over `codeUnits` — not `String.hashCode`,
  /// which is not guaranteed stable across Dart versions. The return value
  /// comes from [AppGroupAvatarColors.lightSlots] or `.darkSlots` based on
  /// the active [brightness] on this token instance.
  Color groupAvatarSlot(String groupId) {
    final slots = brightness == Brightness.dark
        ? AppGroupAvatarColors.darkSlots
        : AppGroupAvatarColors.lightSlots;
    return slots[_stableGroupHash(groupId) % slots.length];
  }

  /// Default saffron light palette instance.
  static const AppColorTokens light = AppColorTokens(
    brightness: Brightness.light,
    primary: Color(0xFFD17B2C), // Saffron
    scaffoldBackground: Color(0xFFF6F1E6), // Paper
    cardSurface: Color(0xFFFFFFFF), // White
    inputFill: Color(0xFFFBF7EE), // Card-soft
    border: Color(0xFFEAE5D9), // 8% ink approximation
    textPrimary: Color(0xFF1B1A17), // Ink
    textSecondary: Color(0xFF6B675D), // Ink-3
    textMuted: Color(0xFF948F82), // Ink-4 (decorative only)
    textOnPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF5C7A57), // Sage
    successText: Color(0xFF3F5A3B), // Sage-dark
    error: Color(0xFFA84B33), // Rust
    errorText: Color(0xFF7A2F1F), // Rust-dark
    disabled: Color(0xFFFBF7EE), // Card-soft
    disabledText: Color(0xFF948F82), // Ink-4
    focusRing: Color(0xFFD17B2C), // Saffron
    selectionFill: Color(0xFFFBEED5), // Saffron-tint
    moduleLedger: Color(0xFFD17B2C), // Saffron — sole colored module
    moduleLedgerLight: Color(0xFFFBEED5),
    moduleGear: Color(0xFF6B675D), // Ink-3 — neutral
    moduleGearLight: Color(0xFFFBF7EE),
    moduleLogistics: Color(0xFF6B675D),
    moduleLogisticsLight: Color(0xFFFBF7EE),
    moduleVault: Color(0xFF6B675D),
    moduleVaultLight: Color(0xFFFBF7EE),
    moduleActivity: Color(0xFF6B675D),
    moduleActivityLight: Color(0xFFFBF7EE),
    moduleMemories: Color(0xFF6B675D),
    moduleMemoriesLight: Color(0xFFFBF7EE),
    headerGradientStart: Color(0xFF1B1A17), // Ink
    headerGradientEnd: Color(0xFF3D3A33), // Ink-2
    offlineBannerBackground: Color(0xFFF59E0B), // Amber (semantic, kept)
    bottomNavBackground: Color(0xFFF6F1E6), // Paper
    bottomNavActiveIcon: Color(0xFFD17B2C), // Saffron
    bottomNavInactiveIcon: Color(0xFF948F82), // Ink-4
    inputFillWarm: Color(0xFFFBF7EE), // Card-soft alias
    focusBorderWarm: Color(0xFFD17B2C), // Saffron
    borderWarm: Color(0xFFEAE5D9), // 8% ink alias
    warning: Color(0xFFF59E0B), // Amber
    primaryDark: Color(0xFFB5641A), // Saffron-dark
    // Appended saffron tokens:
    paperDeep: Color(0xFFEFE8D7),
    cardSoft: Color(0xFFFBF7EE),
    ink2: Color(0xFF3D3A33),
    saffronSoft: Color(0xFFF4DDB8),
    saffronTint: Color(0xFFFBEED5),
    rule: Color(0xFFEAE5D9), // 8% ink solid approximation
    rule2: Color(0xFFD9D3C5), // 14% ink solid approximation
    cat1: Color(0xFFC2693B), // food
    cat2: Color(0xFF4F7B96), // lodging
    cat3: Color(0xFF8C6A2F), // transit
    cat4: Color(0xFF6F7A3A), // groceries
    cat5: Color(0xFF94517A), // activities
    cat6: Color(0xFF4D5A6A), // other
  );

  /// Dark palette instance — saffron direction, dark variant.
  ///
  /// Visual quality target for dark mode is deferred to a later phase; values
  /// here are plausible and prevent crashes/illegible text but have not been
  /// tuned for production. Per locked plan: light first.
  static const AppColorTokens dark = AppColorTokens(
    brightness: Brightness.dark,
    primary: Color(0xFFE89A4F), // Saffron-light for dark mode
    scaffoldBackground: Color(0xFF1A1714), // Paper-dark
    cardSurface: Color(0xFF25211C), // Card-dark
    inputFill: Color(0xFF1F1B17), // Card-soft-dark
    border: Color(0xFF3D3A33), // Rule on dark
    textPrimary: Color(0xFFF4EEE0), // Ink-light
    textSecondary: Color(0xFF9C9486), // Ink-3-light
    textMuted: Color(0xFF6E6759), // Ink-4-light
    textOnPrimary: Color(0xFF1A1714),
    success: Color(0xFF8AA982), // Sage-light
    successText: Color(0xFFB7CFB0),
    error: Color(0xFFD77962), // Rust-light
    errorText: Color(0xFFEEB7A8),
    disabled: Color(0xFF1F1B17),
    disabledText: Color(0xFF6E6759),
    focusRing: Color(0xFFE89A4F),
    selectionFill: Color(0xFF2E2113),
    moduleLedger: Color(0xFFE89A4F),
    moduleLedgerLight: Color(0xFF2E2113),
    moduleGear: Color(0xFF9C9486),
    moduleGearLight: Color(0xFF1F1B17),
    moduleLogistics: Color(0xFF9C9486),
    moduleLogisticsLight: Color(0xFF1F1B17),
    moduleVault: Color(0xFF9C9486),
    moduleVaultLight: Color(0xFF1F1B17),
    moduleActivity: Color(0xFF9C9486),
    moduleActivityLight: Color(0xFF1F1B17),
    moduleMemories: Color(0xFF9C9486),
    moduleMemoriesLight: Color(0xFF1F1B17),
    headerGradientStart: Color(0xFF1A1714),
    headerGradientEnd: Color(0xFF25211C),
    offlineBannerBackground: Color(0xFFF59E0B),
    bottomNavBackground: Color(0xFF1A1714),
    bottomNavActiveIcon: Color(0xFFE89A4F),
    bottomNavInactiveIcon: Color(0xFF6E6759),
    inputFillWarm: Color(0xFF1F1B17),
    focusBorderWarm: Color(0xFFE89A4F),
    borderWarm: Color(0xFF3D3A33),
    warning: Color(0xFFF59E0B),
    primaryDark: Color(0xFFF5B069),
    paperDeep: Color(0xFF221E1A),
    cardSoft: Color(0xFF1F1B17),
    ink2: Color(0xFFD8D1C0),
    saffronSoft: Color(0xFF4A3618),
    saffronTint: Color(0xFF2E2113),
    rule: Color(0xFF3D3A33),
    rule2: Color(0xFF4A4640),
    cat1: Color(0xFFD4845B),
    cat2: Color(0xFF7AA0B6),
    cat3: Color(0xFFB69254),
    cat4: Color(0xFF9AA660),
    cat5: Color(0xFFB57A98),
    cat6: Color(0xFF7B8898),
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

/// Deterministic string hash — folds `codeUnits` with a 31-constant FNV-like
/// loop. Stable across Dart versions (unlike `String.hashCode`).
int _stableGroupHash(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0xffffffff;
  }
  return h;
}
