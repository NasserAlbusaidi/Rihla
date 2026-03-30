import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AppColorTokens new fields (Phase 18 D-24 / D-25)
  // ---------------------------------------------------------------------------
  group('AppColorTokens — new Phase 18 tokens', () {
    test('light.offlineBannerBackground equals amber #F59E0B', () {
      expect(
        AppColorTokens.light.offlineBannerBackground,
        equals(const Color(0xFFF59E0B)),
      );
    });

    test('light.bottomNavBackground equals white #FFFFFF', () {
      expect(
        AppColorTokens.light.bottomNavBackground,
        equals(const Color(0xFFFFFFFF)),
      );
    });

    test('light.bottomNavActiveIcon equals teal #0D7B74', () {
      expect(
        AppColorTokens.light.bottomNavActiveIcon,
        equals(const Color(0xFF0D7B74)),
      );
    });

    test('light.bottomNavInactiveIcon equals gray-400 #9CA3AF', () {
      expect(
        AppColorTokens.light.bottomNavInactiveIcon,
        equals(const Color(0xFF9CA3AF)),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AppColors facade — new Phase 18 static consts
  // ---------------------------------------------------------------------------
  group('AppColors facade — new Phase 18 constants', () {
    test('AppColors.errorText equals dark red #B91C1C', () {
      expect(
        AppColors.errorText,
        equals(const Color(0xFFB91C1C)),
      );
    });

    test('AppColors.successText equals dark emerald #047857', () {
      expect(
        AppColors.successText,
        equals(const Color(0xFF047857)),
      );
    });

    test('AppColors.offlineBannerBackground equals amber #F59E0B', () {
      expect(
        AppColors.offlineBannerBackground,
        equals(const Color(0xFFF59E0B)),
      );
    });

    test('AppColors.bottomNavBackground equals white #FFFFFF', () {
      expect(
        AppColors.bottomNavBackground,
        equals(const Color(0xFFFFFFFF)),
      );
    });

    test('AppColors.bottomNavActiveIcon equals teal #0D7B74', () {
      expect(
        AppColors.bottomNavActiveIcon,
        equals(const Color(0xFF0D7B74)),
      );
    });

    test('AppColors.bottomNavInactiveIcon equals gray-400 #9CA3AF', () {
      expect(
        AppColors.bottomNavInactiveIcon,
        equals(const Color(0xFF9CA3AF)),
      );
    });
  });
}
