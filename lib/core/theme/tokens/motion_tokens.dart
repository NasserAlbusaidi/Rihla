import 'package:flutter/material.dart';

/// Seal-settle motion — a stamp pressing down: scales in from 1.08→1.0,
/// unrotates −3°→0°, over [duration], with a one-frame ink-bloom on the
/// FIRST frame (the bloom is a CONSUMER effect — a brief opacity/ink pop —
/// not a field here). Grafted from Jawaz. Reduced-motion → opacity-only
/// (handled by the consumer via MediaQuery.disableAnimations).
@immutable
class StampMotion {
  const StampMotion({
    required this.duration,
    required this.curve,
    required this.beginScale,
    required this.beginTurns,
  });
  final Duration duration;
  final Curve curve;
  final double beginScale; // 1.08
  final double beginTurns; // -3/360 (turns; use with RotationTransition/AnimatedRotation)
  static const StampMotion base = StampMotion(
    duration: Duration(milliseconds: 300),
    curve: Curves.easeOutBack, // slight overshoot reads as a press-and-settle
    beginScale: 1.08,
    beginTurns: -3 / 360,
  );
}

/// Continuous channel-fill motion. **Means "SYNCING" and nothing else,
/// app-wide** (spec, grafted from Kamal). Linear by contract — do NOT use
/// [flow] for loading/entrance/decorative motion (those use quick/standard/
/// emphasis). Reserved: this token exists; the live sync indicator is a
/// later wire-up.
@immutable
class FlowMotion {
  const FlowMotion({required this.period, required this.curve});
  final Duration period; // one fill cycle
  final Curve curve; // ALWAYS Curves.linear (channel water = constant rate)
  static const FlowMotion base = FlowMotion(
    period: Duration(milliseconds: 1100),
    curve: Curves.linear,
  );
}

/// Typed motion token set — canonical animation durations + curves.
///
/// Three speeds, matching `docs/DESIGN.md` §6:
/// - [quick] (120ms) — tap/press feedback (e.g. `TapBounce`). Pair [curveStandard].
/// - [standard] (200ms) — default state transitions, toggles. Pair [curveStandard].
/// - [emphasis] (300ms) — banners, sheets, entrances. Pair [curveEmphasis].
///
/// Plus two named devices: [stamp] (seal-settle) and [flow] (syncing only —
/// see [FlowMotion]).
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
    required this.stamp,
    required this.flow,
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

  /// Seal-settle device (see [StampMotion]).
  final StampMotion stamp;

  /// Syncing-only channel-fill device (see [FlowMotion]).
  final FlowMotion flow;

  /// Canonical motion instance — registered in both light and dark themes.
  static const AppMotionTokens base = AppMotionTokens(
    quick: Duration(milliseconds: 120),
    standard: Duration(milliseconds: 200),
    emphasis: Duration(milliseconds: 300),
    curveStandard: Curves.easeInOut,
    curveEmphasis: Curves.easeOutCubic,
    stamp: StampMotion.base,
    flow: FlowMotion.base,
  );

  @override
  AppMotionTokens copyWith({
    Duration? quick,
    Duration? standard,
    Duration? emphasis,
    Curve? curveStandard,
    Curve? curveEmphasis,
    StampMotion? stamp,
    FlowMotion? flow,
  }) {
    return AppMotionTokens(
      quick: quick ?? this.quick,
      standard: standard ?? this.standard,
      emphasis: emphasis ?? this.emphasis,
      curveStandard: curveStandard ?? this.curveStandard,
      curveEmphasis: curveEmphasis ?? this.curveEmphasis,
      stamp: stamp ?? this.stamp,
      flow: flow ?? this.flow,
    );
  }

  @override
  AppMotionTokens lerp(ThemeExtension<AppMotionTokens>? other, double t) {
    if (other is! AppMotionTokens) return this;
    return t < 0.5 ? this : other;
  }
}
