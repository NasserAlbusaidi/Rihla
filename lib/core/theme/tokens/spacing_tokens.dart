import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Typed spacing token set — spacing scale, border radii, and button height.
///
/// Use [AppSpacingTokens.standard] for the default spacing instance.
final class AppSpacingTokens extends ThemeExtension<AppSpacingTokens> {
  const AppSpacingTokens({
    required this.space4,
    required this.space8,
    required this.space12,
    required this.space16,
    required this.space20,
    required this.space24,
    required this.space32,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.buttonHeight,
    this.radiusInput = 14,
    this.radiusCard = 20,
    this.radiusSheet = 28,
    this.radiusPill = 9999,
  });

  /// 4dp spacing unit
  final double space4;

  /// 8dp spacing unit
  final double space8;

  /// 12dp spacing unit
  final double space12;

  /// 16dp spacing unit — base grid unit
  final double space16;

  /// 20dp spacing unit
  final double space20;

  /// 24dp spacing unit
  final double space24;

  /// 32dp spacing unit
  final double space32;

  /// Small border radius — 8dp (chips, tags). Legacy scale; see [radiusInput]+
  /// for the canonical semantic radii (`docs/DESIGN.md` §4).
  final double radiusSmall;

  /// Medium border radius — 12dp. Legacy scale — prefer [radiusInput] (14dp).
  final double radiusMedium;

  /// Large border radius — 16dp. Legacy scale — prefer [radiusCard] (20dp).
  final double radiusLarge;

  /// Standard button height — 52dp
  final double buttonHeight;

  // ── Canonical semantic radii (wireframe scale, `docs/DESIGN.md` §4) ──
  // The single source these resolve from is `AppTheme`; per-screen call sites
  // migrate onto these in Phase 2. Defaults match the values `AppTheme`
  // previously hardcoded, so wiring the theme to them is visually a no-op.

  /// Input / small-card radius — 14dp.
  final double radiusInput;

  /// Card / dialog radius — 20dp.
  final double radiusCard;

  /// Bottom-sheet / hero radius — 28dp.
  final double radiusSheet;

  /// Pill radius — 9999 (buttons, chips, FAB).
  final double radiusPill;

  /// Default standard spacing instance.
  static const AppSpacingTokens standard = AppSpacingTokens(
    space4: 4,
    space8: 8,
    space12: 12,
    space16: 16,
    space20: 20,
    space24: 24,
    space32: 32,
    radiusSmall: 8,
    radiusMedium: 12,
    radiusLarge: 16,
    buttonHeight: 52,
    radiusInput: 14,
    radiusCard: 20,
    radiusSheet: 28,
    radiusPill: 9999,
  );

  @override
  AppSpacingTokens copyWith({
    double? space4,
    double? space8,
    double? space12,
    double? space16,
    double? space20,
    double? space24,
    double? space32,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? buttonHeight,
    double? radiusInput,
    double? radiusCard,
    double? radiusSheet,
    double? radiusPill,
  }) {
    return AppSpacingTokens(
      space4: space4 ?? this.space4,
      space8: space8 ?? this.space8,
      space12: space12 ?? this.space12,
      space16: space16 ?? this.space16,
      space20: space20 ?? this.space20,
      space24: space24 ?? this.space24,
      space32: space32 ?? this.space32,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      buttonHeight: buttonHeight ?? this.buttonHeight,
      radiusInput: radiusInput ?? this.radiusInput,
      radiusCard: radiusCard ?? this.radiusCard,
      radiusSheet: radiusSheet ?? this.radiusSheet,
      radiusPill: radiusPill ?? this.radiusPill,
    );
  }

  @override
  AppSpacingTokens lerp(ThemeExtension<AppSpacingTokens>? other, double t) {
    if (other is! AppSpacingTokens) return this;
    return AppSpacingTokens(
      space4: lerpDouble(space4, other.space4, t)!,
      space8: lerpDouble(space8, other.space8, t)!,
      space12: lerpDouble(space12, other.space12, t)!,
      space16: lerpDouble(space16, other.space16, t)!,
      space20: lerpDouble(space20, other.space20, t)!,
      space24: lerpDouble(space24, other.space24, t)!,
      space32: lerpDouble(space32, other.space32, t)!,
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t)!,
      radiusMedium: lerpDouble(radiusMedium, other.radiusMedium, t)!,
      radiusLarge: lerpDouble(radiusLarge, other.radiusLarge, t)!,
      buttonHeight: lerpDouble(buttonHeight, other.buttonHeight, t)!,
      radiusInput: lerpDouble(radiusInput, other.radiusInput, t)!,
      radiusCard: lerpDouble(radiusCard, other.radiusCard, t)!,
      radiusSheet: lerpDouble(radiusSheet, other.radiusSheet, t)!,
      radiusPill: lerpDouble(radiusPill, other.radiusPill, t)!,
    );
  }
}
