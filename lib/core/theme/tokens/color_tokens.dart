import 'package:flutter/material.dart';

/// Typed color token set for the warm earthy palette.
///
/// All fields are final Color values. Gradient tokens are computed getters
/// (LinearGradient is not const-constructable, so they cannot be fields).
///
/// Use [AppColorTokens.earthyLight] for the default light palette instance.
final class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
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
  });

  /// Terracotta — primary action color (buttons, FABs, focused inputs, links)
  final Color primary;

  /// Sand — scaffold/page background (#F2E8D6)
  final Color scaffoldBackground;

  /// Warm white — card surface (#FFF9F2)
  final Color cardSurface;

  /// Sand light — input fill (#F5EDE1)
  final Color inputFill;

  /// Warm gray — dividers and borders (#E5D5C0)
  final Color border;

  /// Dark brown — primary body text, 13.71:1 on sand (#2C1A0E)
  final Color textPrimary;

  /// Warm gray — secondary text, 5.35:1 on sand (#6B5B4E)
  final Color textSecondary;

  /// Decorative use only — 2.30:1 contrast, below AA. Use textSecondary for functional labels.
  final Color textMuted;

  /// White on terracotta — 3.64:1 AA large (#FFFFFF)
  final Color textOnPrimary;

  /// Display only (badges, icons). For text use [successText].
  final Color success;

  /// Dark emerald — WCAG-safe success text, 4.51:1 on sand (#047857)
  final Color successText;

  /// Display only (badges, icons). For text use [errorText].
  final Color error;

  /// Dark red — WCAG-safe error text, 5.33:1 on sand (#B91C1C)
  final Color errorText;

  /// Warm beige — disabled control background (#E5D5C0)
  final Color disabled;

  /// Sand gray — disabled text (#A89888)
  final Color disabledText;

  /// Terracotta focus ring — matches primary (#CC6B49)
  final Color focusRing;

  /// Terracotta 15% tint — selected chip/item background (#F5DDD3)
  final Color selectionFill;

  /// Ledger module accent — terracotta (#CC6B49)
  final Color moduleLedger;

  /// Ledger module light tint (#ECD5C0)
  final Color moduleLedgerLight;

  /// Gear module accent — olive (#7A8C5E)
  final Color moduleGear;

  /// Gear module light tint (#E0DAC4)
  final Color moduleGearLight;

  /// Logistics module accent — dusty teal (#5B7B8C)
  final Color moduleLogistics;

  /// Logistics module light tint (#DBD7CA)
  final Color moduleLogisticsLight;

  /// Vault module accent — warm bronze (#8B7355)
  final Color moduleVault;

  /// Vault module light tint (#E2D6C2)
  final Color moduleVaultLight;

  /// Activity module accent — caramel (#A67C5B)
  final Color moduleActivity;

  /// Activity module light tint (#E6D7C3)
  final Color moduleActivityLight;

  /// Memories module accent — desert sand (#9B7A5C)
  final Color moduleMemories;

  /// Memories module light tint (#E4D7C3)
  final Color moduleMemoriesLight;

  /// Header gradient start — dark brown (#2C1A0E)
  final Color headerGradientStart;

  /// Header gradient end — slightly lighter dark brown (#3D2B1E)
  final Color headerGradientEnd;

  /// Computed dark header gradient (not const — LinearGradient is not const-constructable).
  LinearGradient get headerGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [headerGradientStart, headerGradientEnd],
      );

  /// Default earthy light palette instance.
  static const AppColorTokens earthyLight = AppColorTokens(
    primary: Color(0xFFCC6B49),
    scaffoldBackground: Color(0xFFF2E8D6),
    cardSurface: Color(0xFFFFF9F2),
    inputFill: Color(0xFFF5EDE1),
    border: Color(0xFFE5D5C0),
    textPrimary: Color(0xFF2C1A0E),
    textSecondary: Color(0xFF6B5B4E),
    textMuted: Color(0xFFA89888),
    textOnPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF10B981),
    successText: Color(0xFF047857),
    error: Color(0xFFEF4444),
    errorText: Color(0xFFB91C1C),
    disabled: Color(0xFFE5D5C0),
    disabledText: Color(0xFFA89888),
    focusRing: Color(0xFFCC6B49),
    selectionFill: Color(0xFFF5DDD3),
    moduleLedger: Color(0xFFCC6B49),
    moduleLedgerLight: Color(0xFFECD5C0),
    moduleGear: Color(0xFF7A8C5E),
    moduleGearLight: Color(0xFFE0DAC4),
    moduleLogistics: Color(0xFF5B7B8C),
    moduleLogisticsLight: Color(0xFFDBD7CA),
    moduleVault: Color(0xFF8B7355),
    moduleVaultLight: Color(0xFFE2D6C2),
    moduleActivity: Color(0xFFA67C5B),
    moduleActivityLight: Color(0xFFE6D7C3),
    moduleMemories: Color(0xFF9B7A5C),
    moduleMemoriesLight: Color(0xFFE4D7C3),
    headerGradientStart: Color(0xFF2C1A0E),
    headerGradientEnd: Color(0xFF3D2B1E),
  );

  @override
  AppColorTokens copyWith({
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
  }) {
    return AppColorTokens(
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
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
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
    );
  }
}
