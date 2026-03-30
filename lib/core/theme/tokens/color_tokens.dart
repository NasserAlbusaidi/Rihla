import 'package:flutter/material.dart';

/// Typed color token set for the neutral + teal palette.
///
/// All fields are final Color values. Gradient tokens are computed getters
/// (LinearGradient is not const-constructable, so they cannot be fields).
///
/// Use [AppColorTokens.light] for the default light palette instance.
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
    required this.offlineBannerBackground,
    required this.bottomNavBackground,
    required this.bottomNavActiveIcon,
    required this.bottomNavInactiveIcon,
  });

  /// Teal — primary action color (buttons, FABs, focused inputs, links)
  final Color primary;

  /// White — scaffold/page background (#FFFFFF)
  final Color scaffoldBackground;

  /// Gray-50 — card surface (#F8F9FA)
  final Color cardSurface;

  /// Gray-100 — input fill (#F3F4F6)
  final Color inputFill;

  /// Gray-200 — dividers and borders (#E5E7EB)
  final Color border;

  /// Gray-900 — primary body text, 17.15:1 on white (#111827)
  final Color textPrimary;

  /// Gray-500 — secondary text, 5.74:1 on white (#6B7280)
  final Color textSecondary;

  /// Gray-400 — decorative use only, below AA. Use textSecondary for functional labels.
  final Color textMuted;

  /// White on teal — AA large (#FFFFFF)
  final Color textOnPrimary;

  /// Display only (badges, icons). For text use [successText].
  final Color success;

  /// Dark emerald — WCAG-safe success text, 4.56:1 on white (#047857)
  final Color successText;

  /// Display only (badges, icons). For text use [errorText].
  final Color error;

  /// Dark red — WCAG-safe error text, 5.92:1 on white (#B91C1C)
  final Color errorText;

  /// Gray-200 — disabled control background (#E5E7EB)
  final Color disabled;

  /// Gray-400 — disabled text (#9CA3AF)
  final Color disabledText;

  /// Teal focus ring — matches primary (#0D7B74)
  final Color focusRing;

  /// Teal 10% tint — selected chip/item background (#E6F5F3)
  final Color selectionFill;

  /// Ledger module accent — teal (#0D7B74)
  final Color moduleLedger;

  /// Ledger module light tint (#E6F5F3)
  final Color moduleLedgerLight;

  /// Gear module accent — gray-500 (#6B7280)
  final Color moduleGear;

  /// Gear module light tint (#F3F4F6)
  final Color moduleGearLight;

  /// Logistics module accent — gray-500 (#6B7280)
  final Color moduleLogistics;

  /// Logistics module light tint (#F3F4F6)
  final Color moduleLogisticsLight;

  /// Vault module accent — gray-500 (#6B7280)
  final Color moduleVault;

  /// Vault module light tint (#F3F4F6)
  final Color moduleVaultLight;

  /// Activity module accent — gray-500 (#6B7280)
  final Color moduleActivity;

  /// Activity module light tint (#F3F4F6)
  final Color moduleActivityLight;

  /// Memories module accent — gray-500 (#6B7280)
  final Color moduleMemories;

  /// Memories module light tint (#F3F4F6)
  final Color moduleMemoriesLight;

  /// Header gradient start — gray-900 (#111827)
  final Color headerGradientStart;

  /// Header gradient end — gray-800 (#1F2937)
  final Color headerGradientEnd;

  /// Amber offline indicator (#F59E0B)
  final Color offlineBannerBackground;

  /// Bottom nav bar surface (#FFFFFF)
  final Color bottomNavBackground;

  /// Active tab icon — matches primary (#0D7B74)
  final Color bottomNavActiveIcon;

  /// Inactive tab icon — decorative only (#9CA3AF)
  final Color bottomNavInactiveIcon;

  /// Computed dark header gradient (not const — LinearGradient is not const-constructable).
  LinearGradient get headerGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [headerGradientStart, headerGradientEnd],
      );

  /// Default neutral + teal light palette instance.
  static const AppColorTokens light = AppColorTokens(
    primary: Color(0xFF0D7B74),
    scaffoldBackground: Color(0xFFFFFFFF),
    cardSurface: Color(0xFFF8F9FA),
    inputFill: Color(0xFFF3F4F6),
    border: Color(0xFFE5E7EB),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textMuted: Color(0xFF9CA3AF),
    textOnPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF10B981),
    successText: Color(0xFF047857),
    error: Color(0xFFEF4444),
    errorText: Color(0xFFB91C1C),
    disabled: Color(0xFFE5E7EB),
    disabledText: Color(0xFF9CA3AF),
    focusRing: Color(0xFF0D7B74),
    selectionFill: Color(0xFFE6F5F3),
    moduleLedger: Color(0xFF0D7B74),
    moduleLedgerLight: Color(0xFFE6F5F3),
    moduleGear: Color(0xFF6B7280),
    moduleGearLight: Color(0xFFF3F4F6),
    moduleLogistics: Color(0xFF6B7280),
    moduleLogisticsLight: Color(0xFFF3F4F6),
    moduleVault: Color(0xFF6B7280),
    moduleVaultLight: Color(0xFFF3F4F6),
    moduleActivity: Color(0xFF6B7280),
    moduleActivityLight: Color(0xFFF3F4F6),
    moduleMemories: Color(0xFF6B7280),
    moduleMemoriesLight: Color(0xFFF3F4F6),
    headerGradientStart: Color(0xFF111827),
    headerGradientEnd: Color(0xFF1F2937),
    offlineBannerBackground: Color(0xFFF59E0B),
    bottomNavBackground: Color(0xFFFFFFFF),
    bottomNavActiveIcon: Color(0xFF0D7B74),
    bottomNavInactiveIcon: Color(0xFF9CA3AF),
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
    Color? offlineBannerBackground,
    Color? bottomNavBackground,
    Color? bottomNavActiveIcon,
    Color? bottomNavInactiveIcon,
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
      offlineBannerBackground: offlineBannerBackground ?? this.offlineBannerBackground,
      bottomNavBackground: bottomNavBackground ?? this.bottomNavBackground,
      bottomNavActiveIcon: bottomNavActiveIcon ?? this.bottomNavActiveIcon,
      bottomNavInactiveIcon: bottomNavInactiveIcon ?? this.bottomNavInactiveIcon,
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
      offlineBannerBackground: Color.lerp(offlineBannerBackground, other.offlineBannerBackground, t)!,
      bottomNavBackground: Color.lerp(bottomNavBackground, other.bottomNavBackground, t)!,
      bottomNavActiveIcon: Color.lerp(bottomNavActiveIcon, other.bottomNavActiveIcon, t)!,
      bottomNavInactiveIcon: Color.lerp(bottomNavInactiveIcon, other.bottomNavInactiveIcon, t)!,
    );
  }
}
