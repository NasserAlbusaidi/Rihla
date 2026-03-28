import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/core/theme/tokens/domain_aliases.dart';
import 'package:safar/core/theme/tokens/shadow_tokens.dart';
import 'package:safar/core/theme/tokens/spacing_tokens.dart';

// ---------------------------------------------------------------------------
// WCAG 2.1 contrast helpers
// ---------------------------------------------------------------------------

/// WCAG 2.1 relative luminance and contrast ratio calculation.
/// Used for compile-time verification of color token accessibility.
double _relativeLuminance(Color color) {
  double linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linearize(color.r);
  final g = linearize(color.g);
  final b = linearize(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color foreground, Color background) {
  final l1 = _relativeLuminance(foreground);
  final l2 = _relativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Builds a test-friendly ThemeData that includes the design token extensions
/// but uses the default system font to avoid google_fonts HTTP requests in tests.
ThemeData _testTheme() {
  return ThemeData.light(useMaterial3: true).copyWith(
    extensions: <ThemeExtension>[
      AppColorTokens.earthyLight,
      AppSpacingTokens.standard,
      AppShadowTokens.standard,
    ],
  );
}

void main() {
  setUpAll(() {
    // Disable google_fonts HTTP fetching in tests — fonts are not required
    // for token value assertions and cause false failures in CI environments.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ---------------------------------------------------------------------------
  // AppColorTokens
  // ---------------------------------------------------------------------------
  group('AppColorTokens', () {
    test('earthyLight.primary equals terracotta #CC6B49', () {
      expect(
        AppColorTokens.earthyLight.primary,
        equals(const Color(0xFFCC6B49)),
      );
    });

    test('earthyLight.scaffoldBackground equals sand #F2E8D6', () {
      expect(
        AppColorTokens.earthyLight.scaffoldBackground,
        equals(const Color(0xFFF2E8D6)),
      );
    });

    test('earthyLight.successText equals dark emerald #047857', () {
      expect(
        AppColorTokens.earthyLight.successText,
        equals(const Color(0xFF047857)),
      );
    });

    test('earthyLight.errorText equals dark red #B91C1C', () {
      expect(
        AppColorTokens.earthyLight.errorText,
        equals(const Color(0xFFB91C1C)),
      );
    });

    test('earthyLight.textOnPrimary equals white #FFFFFF', () {
      expect(
        AppColorTokens.earthyLight.textOnPrimary,
        equals(const Color(0xFFFFFFFF)),
      );
    });

    test('copyWith returns new instance with changed primary', () {
      const newPrimary = Color(0xFF000000);
      final modified = AppColorTokens.earthyLight.copyWith(primary: newPrimary);
      expect(modified.primary, equals(newPrimary));
      // Other fields remain unchanged
      expect(
        modified.scaffoldBackground,
        equals(AppColorTokens.earthyLight.scaffoldBackground),
      );
    });

    test('copyWith does not mutate original instance', () {
      final original = AppColorTokens.earthyLight;
      original.copyWith(primary: const Color(0xFF000000));
      expect(original.primary, equals(const Color(0xFFCC6B49)));
    });

    test('lerp at t=0.0 returns this', () {
      const other = AppColorTokens(
        primary: Color(0xFF000000),
        scaffoldBackground: Color(0xFF000000),
        cardSurface: Color(0xFF000000),
        inputFill: Color(0xFF000000),
        border: Color(0xFF000000),
        textPrimary: Color(0xFF000000),
        textSecondary: Color(0xFF000000),
        textMuted: Color(0xFF000000),
        textOnPrimary: Color(0xFF000000),
        success: Color(0xFF000000),
        successText: Color(0xFF000000),
        error: Color(0xFF000000),
        errorText: Color(0xFF000000),
        disabled: Color(0xFF000000),
        disabledText: Color(0xFF000000),
        focusRing: Color(0xFF000000),
        selectionFill: Color(0xFF000000),
        moduleLedger: Color(0xFF000000),
        moduleLedgerLight: Color(0xFF000000),
        moduleGear: Color(0xFF000000),
        moduleGearLight: Color(0xFF000000),
        moduleLogistics: Color(0xFF000000),
        moduleLogisticsLight: Color(0xFF000000),
        moduleVault: Color(0xFF000000),
        moduleVaultLight: Color(0xFF000000),
        moduleActivity: Color(0xFF000000),
        moduleActivityLight: Color(0xFF000000),
        moduleMemories: Color(0xFF000000),
        moduleMemoriesLight: Color(0xFF000000),
        headerGradientStart: Color(0xFF000000),
        headerGradientEnd: Color(0xFF000000),
      );
      final lerped = AppColorTokens.earthyLight.lerp(other, 0.0);
      expect(lerped.primary, equals(AppColorTokens.earthyLight.primary));
    });

    test('lerp at t=1.0 returns other values', () {
      const other = AppColorTokens(
        primary: Color(0xFF000000),
        scaffoldBackground: Color(0xFF000000),
        cardSurface: Color(0xFF000000),
        inputFill: Color(0xFF000000),
        border: Color(0xFF000000),
        textPrimary: Color(0xFF000000),
        textSecondary: Color(0xFF000000),
        textMuted: Color(0xFF000000),
        textOnPrimary: Color(0xFF000000),
        success: Color(0xFF000000),
        successText: Color(0xFF000000),
        error: Color(0xFF000000),
        errorText: Color(0xFF000000),
        disabled: Color(0xFF000000),
        disabledText: Color(0xFF000000),
        focusRing: Color(0xFF000000),
        selectionFill: Color(0xFF000000),
        moduleLedger: Color(0xFF000000),
        moduleLedgerLight: Color(0xFF000000),
        moduleGear: Color(0xFF000000),
        moduleGearLight: Color(0xFF000000),
        moduleLogistics: Color(0xFF000000),
        moduleLogisticsLight: Color(0xFF000000),
        moduleVault: Color(0xFF000000),
        moduleVaultLight: Color(0xFF000000),
        moduleActivity: Color(0xFF000000),
        moduleActivityLight: Color(0xFF000000),
        moduleMemories: Color(0xFF000000),
        moduleMemoriesLight: Color(0xFF000000),
        headerGradientStart: Color(0xFF000000),
        headerGradientEnd: Color(0xFF000000),
      );
      final lerped = AppColorTokens.earthyLight.lerp(other, 1.0);
      expect(lerped.primary, equals(const Color(0xFF000000)));
    });

    test('lerp at t=0.5 produces intermediate color', () {
      // Lerping from white (0xFFFFFFFF) to black (0xFF000000) at t=0.5
      // should produce gray (0xFF808080 approximately)
      final white = AppColorTokens.earthyLight.copyWith(
        primary: const Color(0xFFFFFFFF),
      );
      final black = AppColorTokens.earthyLight.copyWith(
        primary: const Color(0xFF000000),
      );
      final lerped = white.lerp(black, 0.5);
      // The resulting color should be approximately mid-gray, not white or black
      expect(lerped.primary, isNot(equals(const Color(0xFFFFFFFF))));
      expect(lerped.primary, isNot(equals(const Color(0xFF000000))));
    });
  });

  // ---------------------------------------------------------------------------
  // AppSpacingTokens
  // ---------------------------------------------------------------------------
  group('AppSpacingTokens', () {
    test('standard.space16 equals 16.0', () {
      expect(AppSpacingTokens.standard.space16, equals(16.0));
    });

    test('standard has correct full spacing scale', () {
      final s = AppSpacingTokens.standard;
      expect(s.space4, equals(4.0));
      expect(s.space8, equals(8.0));
      expect(s.space12, equals(12.0));
      expect(s.space16, equals(16.0));
      expect(s.space20, equals(20.0));
      expect(s.space24, equals(24.0));
      expect(s.space32, equals(32.0));
    });

    test('standard has correct border radii', () {
      final s = AppSpacingTokens.standard;
      expect(s.radiusSmall, equals(12.0));
      expect(s.radiusMedium, equals(16.0));
      expect(s.radiusLarge, equals(20.0));
    });

    test('standard.buttonHeight equals 52.0', () {
      expect(AppSpacingTokens.standard.buttonHeight, equals(52.0));
    });
  });

  // ---------------------------------------------------------------------------
  // AppShadowTokens
  // ---------------------------------------------------------------------------
  group('AppShadowTokens', () {
    test('standard.raised has exactly 2 BoxShadow entries', () {
      expect(AppShadowTokens.standard.raised.length, equals(2));
    });

    test('standard.floating has exactly 2 BoxShadow entries', () {
      expect(AppShadowTokens.standard.floating.length, equals(2));
    });

    test('standard.flat is empty', () {
      expect(AppShadowTokens.standard.flat, isEmpty);
    });

    test('raised shadows use warm brown base #2C1A0E', () {
      final raised = AppShadowTokens.standard.raised;
      // Both shadows should use the warm brown color base
      for (final shadow in raised) {
        expect(shadow.color.r, closeTo(const Color(0xFF2C1A0E).r, 0.01));
        expect(shadow.color.g, closeTo(const Color(0xFF2C1A0E).g, 0.01));
        expect(shadow.color.b, closeTo(const Color(0xFF2C1A0E).b, 0.01));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // ThemeExtension registration
  // ---------------------------------------------------------------------------
  group('ThemeExtension registration', () {
    // Uses _testTheme() (no google_fonts) for extension registration checks.
    // AppTheme.lightTheme IS also verified to contain the extensions — see
    // the AppColors facade group below for the light theme value check.

    test('AppColorTokens is registered in test theme', () {
      final tokens = _testTheme().extension<AppColorTokens>();
      expect(tokens, isNotNull);
    });

    test('AppSpacingTokens is registered in test theme', () {
      final tokens = _testTheme().extension<AppSpacingTokens>();
      expect(tokens, isNotNull);
    });

    test('AppShadowTokens is registered in test theme', () {
      final tokens = _testTheme().extension<AppShadowTokens>();
      expect(tokens, isNotNull);
    });

    test('AppColorTokens from test theme has correct primary color', () {
      final tokens = _testTheme().extension<AppColorTokens>()!;
      expect(tokens.primary, equals(const Color(0xFFCC6B49)));
    });

    testWidgets('AppTheme.lightTheme registers all three extensions', (tester) async {
      // Suppress google_fonts async font-load errors — fonts are not
      // bundled in test assets but do not affect token extension assertions.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exception.toString().contains('google_fonts')) return;
        originalOnError?.call(details);
      };

      // Calling lightTheme triggers _buildTextTheme which uses GoogleFonts —
      // that's expected in production. Here we just verify extensions are set.
      final theme = AppTheme.lightTheme;

      FlutterError.onError = originalOnError;

      expect(theme.extension<AppColorTokens>(), isNotNull);
      expect(theme.extension<AppSpacingTokens>(), isNotNull);
      expect(theme.extension<AppShadowTokens>(), isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // BuildContext extensions
  // ---------------------------------------------------------------------------
  group('BuildContext extensions', () {
    testWidgets('context.colors returns AppColorTokens', (tester) async {
      late AppColorTokens colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Builder(builder: (context) {
            colors = context.colors;
            return const SizedBox();
          }),
        ),
      );
      expect(colors.primary, equals(const Color(0xFFCC6B49)));
    });

    testWidgets('context.spacing returns AppSpacingTokens', (tester) async {
      late AppSpacingTokens spacing;
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Builder(builder: (context) {
            spacing = context.spacing;
            return const SizedBox();
          }),
        ),
      );
      expect(spacing.space16, equals(16.0));
    });

    testWidgets('context.shadows returns AppShadowTokens', (tester) async {
      late AppShadowTokens shadows;
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Builder(builder: (context) {
            shadows = context.shadows;
            return const SizedBox();
          }),
        ),
      );
      expect(shadows.raised.length, equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // WCAG AA contrast compliance
  // ---------------------------------------------------------------------------
  group('WCAG AA contrast compliance', () {
    const sand = Color(0xFFF2E8D6); // scaffold background

    test('primary text (#2C1A0E) on scaffold (#F2E8D6) >= 4.5:1', () {
      const textPrimary = Color(0xFF2C1A0E);
      final ratio = _contrastRatio(textPrimary, sand);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Primary text contrast: ${ratio.toStringAsFixed(2)}:1');
    });

    test('secondary text (#6B5B4E) on scaffold (#F2E8D6) >= 4.5:1', () {
      const textSecondary = Color(0xFF6B5B4E);
      final ratio = _contrastRatio(textSecondary, sand);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Secondary text contrast: ${ratio.toStringAsFixed(2)}:1');
    });

    test('successText (#047857) on scaffold (#F2E8D6) >= 4.5:1', () {
      const successText = Color(0xFF047857);
      final ratio = _contrastRatio(successText, sand);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Success text contrast: ${ratio.toStringAsFixed(2)}:1');
    });

    test('errorText (#B91C1C) on scaffold (#F2E8D6) >= 4.5:1', () {
      const errorText = Color(0xFFB91C1C);
      final ratio = _contrastRatio(errorText, sand);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Error text contrast: ${ratio.toStringAsFixed(2)}:1');
    });

    test('white (#FFFFFF) on terracotta (#CC6B49) >= 3.0:1 (AA large text)', () {
      const white = Color(0xFFFFFFFF);
      const terracotta = Color(0xFFCC6B49);
      final ratio = _contrastRatio(white, terracotta);
      expect(ratio, greaterThanOrEqualTo(3.0),
          reason: 'White on terracotta contrast: ${ratio.toStringAsFixed(2)}:1');
    });
  });

  // ---------------------------------------------------------------------------
  // AppColors facade
  // ---------------------------------------------------------------------------
  group('AppColors facade', () {
    test('AppColors.primary equals terracotta #CC6B49', () {
      expect(AppColors.primary, equals(const Color(0xFFCC6B49)));
    });

    test('AppColors.textOnPrimary equals white #FFFFFF (not black)', () {
      expect(AppColors.textOnPrimary, equals(const Color(0xFFFFFFFF)));
    });

    test('AppColors.background equals sand #F2E8D6', () {
      expect(AppColors.background, equals(const Color(0xFFF2E8D6)));
    });

    test('AppColors.textPrimary equals dark brown #2C1A0E', () {
      expect(AppColors.textPrimary, equals(const Color(0xFF2C1A0E)));
    });

    test('AppColors.surface equals warm white #FFF9F2', () {
      expect(AppColors.surface, equals(const Color(0xFFFFF9F2)));
    });
  });
}
