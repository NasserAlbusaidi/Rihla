import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/group_avatar_colors.dart';
import 'package:safar/core/theme/tokens/gradient_tokens.dart';

/// Phase 37 Plan 04 — Token Promotion shape assertions.
///
/// Asserts shape of the new token files landed in Wave 4:
///   * `AppGroupAvatarColors.lightSlots` / `.darkSlots` (5 each)
///   * `AppGradients.terracotta` / `.olive` / `.teal` / `.gray`
///     each with light + dark LinearGradient variants.
///
/// These tests intentionally fail on import until Tasks 37-04-02 and
/// 37-04-03 land the token files — that's the TDD RED signal.
void main() {
  group('AppGroupAvatarColors', () {
    test('lightSlots has 5 entries', () {
      expect(AppGroupAvatarColors.lightSlots.length, 5);
    });

    test('darkSlots has 5 entries', () {
      expect(AppGroupAvatarColors.darkSlots.length, 5);
    });

    test('lightSlots and darkSlots are distinct color lists', () {
      expect(
        AppGroupAvatarColors.lightSlots,
        isNot(equals(AppGroupAvatarColors.darkSlots)),
      );
    });
  });

  group('AppGradients', () {
    test('terracotta has light+dark LinearGradient pairs', () {
      expect(AppGradients.terracotta.light, isA<LinearGradient>());
      expect(AppGradients.terracotta.dark, isA<LinearGradient>());
      expect(AppGradients.terracotta.light.colors.length, 2);
      expect(AppGradients.terracotta.dark.colors.length, 2);
    });

    test('olive has light+dark', () {
      expect(AppGradients.olive.light, isA<LinearGradient>());
      expect(AppGradients.olive.dark, isA<LinearGradient>());
    });

    test('teal has light+dark', () {
      expect(AppGradients.teal.light, isA<LinearGradient>());
      expect(AppGradients.teal.dark, isA<LinearGradient>());
    });

    test('gray has light+dark (for activity hero)', () {
      expect(AppGradients.gray.light, isA<LinearGradient>());
      expect(AppGradients.gray.dark, isA<LinearGradient>());
    });

    test('each gradient preserves begin/end across light+dark', () {
      final pairs = <AppGradientPair>[
        AppGradients.terracotta,
        AppGradients.olive,
        AppGradients.teal,
        AppGradients.gray,
      ];
      for (final g in pairs) {
        expect(g.light.begin, g.dark.begin);
        expect(g.light.end, g.dark.end);
      }
    });
  });
}
