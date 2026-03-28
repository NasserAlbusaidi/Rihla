import 'package:flutter/material.dart';

/// Typed shadow token set — elevation shadow levels using warm brown base.
///
/// Note: [List<BoxShadow>] is not const-constructable, so this class does NOT
/// use a const constructor. Use [AppShadowTokens.standard] for the default instance.
final class AppShadowTokens extends ThemeExtension<AppShadowTokens> {
  AppShadowTokens({
    required this.flat,
    required this.raised,
    required this.floating,
  });

  /// No elevation — empty shadow list.
  final List<BoxShadow> flat;

  /// Subtle raised elevation — two warm-brown shadows at low opacity.
  final List<BoxShadow> raised;

  /// Floating/modal elevation — two warm-brown shadows at higher opacity.
  final List<BoxShadow> floating;

  /// Default standard shadow instance using warm brown base (#2C1A0E).
  static AppShadowTokens get standard => AppShadowTokens(
        flat: const [],
        raised: [
          BoxShadow(
            color: const Color(0xFF2C1A0E).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF2C1A0E).withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        floating: [
          BoxShadow(
            color: const Color(0xFF2C1A0E).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF2C1A0E).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      );

  @override
  AppShadowTokens copyWith({
    List<BoxShadow>? flat,
    List<BoxShadow>? raised,
    List<BoxShadow>? floating,
  }) {
    return AppShadowTokens(
      flat: flat ?? this.flat,
      raised: raised ?? this.raised,
      floating: floating ?? this.floating,
    );
  }

  @override
  AppShadowTokens lerp(ThemeExtension<AppShadowTokens>? other, double t) {
    if (other is! AppShadowTokens) return this;
    // List<BoxShadow> lerp: use t >= 0.5 threshold (shadow lists may differ in length)
    return AppShadowTokens(
      flat: t < 0.5 ? flat : other.flat,
      raised: t < 0.5 ? raised : other.raised,
      floating: t < 0.5 ? floating : other.floating,
    );
  }
}
