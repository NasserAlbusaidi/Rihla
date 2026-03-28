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

  /// Small border radius — 12dp (chips, tags)
  final double radiusSmall;

  /// Medium border radius — 16dp (buttons, inputs)
  final double radiusMedium;

  /// Large border radius — 20dp (cards, sheets)
  final double radiusLarge;

  /// Standard button height — 52dp
  final double buttonHeight;

  /// Default standard spacing instance.
  static const AppSpacingTokens standard = AppSpacingTokens(
    space4: 4,
    space8: 8,
    space12: 12,
    space16: 16,
    space20: 20,
    space24: 24,
    space32: 32,
    radiusSmall: 12,
    radiusMedium: 16,
    radiusLarge: 20,
    buttonHeight: 52,
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
    );
  }
}
