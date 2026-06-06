import 'package:flutter/material.dart';

/// Typed motion token set — canonical animation durations + curves.
///
/// Three speeds, matching `docs/DESIGN.md` §6:
/// - [quick] (120ms) — tap/press feedback (e.g. `TapBounce`). Pair [curveStandard].
/// - [standard] (200ms) — default state transitions, toggles. Pair [curveStandard].
/// - [emphasis] (300ms) — banners, sheets, entrances. Pair [curveEmphasis].
///
/// Read via `context.motion.*` (extension in `domain_aliases.dart`). Use
/// [AppMotionTokens.base] only at ThemeExtension registration sites.
///
/// Curves don't interpolate, and durations realistically never animate (this
/// only lerps on a theme swap), so [lerp] snaps every field at `t >= 0.5`.
final class AppMotionTokens extends ThemeExtension<AppMotionTokens> {
  const AppMotionTokens({
    required this.quick,
    required this.standard,
    required this.emphasis,
    required this.curveStandard,
    required this.curveEmphasis,
  });

  /// 120ms — tap/press feedback.
  final Duration quick;

  /// 200ms — default state transitions.
  final Duration standard;

  /// 300ms — banners, sheets, entrances.
  final Duration emphasis;

  /// Default easing for [quick] / [standard].
  final Curve curveStandard;

  /// Decelerating easing for [emphasis] entrances.
  final Curve curveEmphasis;

  /// Canonical motion instance — registered in both light and dark themes.
  static const AppMotionTokens base = AppMotionTokens(
    quick: Duration(milliseconds: 120),
    standard: Duration(milliseconds: 200),
    emphasis: Duration(milliseconds: 300),
    curveStandard: Curves.easeInOut,
    curveEmphasis: Curves.easeOutCubic,
  );

  @override
  AppMotionTokens copyWith({
    Duration? quick,
    Duration? standard,
    Duration? emphasis,
    Curve? curveStandard,
    Curve? curveEmphasis,
  }) {
    return AppMotionTokens(
      quick: quick ?? this.quick,
      standard: standard ?? this.standard,
      emphasis: emphasis ?? this.emphasis,
      curveStandard: curveStandard ?? this.curveStandard,
      curveEmphasis: curveEmphasis ?? this.curveEmphasis,
    );
  }

  @override
  AppMotionTokens lerp(ThemeExtension<AppMotionTokens>? other, double t) {
    if (other is! AppMotionTokens) return this;
    return t < 0.5 ? this : other;
  }
}
