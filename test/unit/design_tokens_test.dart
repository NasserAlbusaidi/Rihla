import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/core/theme/tokens/domain_aliases.dart';
import 'package:safar/core/theme/tokens/gradient_tokens.dart';
import 'package:safar/core/theme/tokens/shadow_tokens.dart';
import 'package:safar/core/theme/tokens/spacing_tokens.dart';

import 'shared_test_contrast_helpers.dart';

/// Builds a test-friendly ThemeData that includes the design token extensions
/// but uses the default system font to avoid google_fonts HTTP requests in tests.
ThemeData _testTheme() {
  return ThemeData.light(useMaterial3: true).copyWith(
    extensions: <ThemeExtension>[
      AppColorTokens.light,
      AppSpacingTokens.standard,
      AppShadowTokens.light,
    ],
  );
}

/// Builds a fully-saturated [AppColorTokens] instance with every field set to
/// the given color. Used by lerp tests so we don't have to repeat ~50 fields
/// inline.
AppColorTokens _allBlack() {
  const c = Color(0xFF000000);
  return const AppColorTokens(
    brightness: Brightness.light,
    primary: c,
    scaffoldBackground: c,
    cardSurface: c,
    inputFill: c,
    border: c,
    textPrimary: c,
    textSecondary: c,
    textMuted: c,
    textOnPrimary: c,
    success: c,
    successText: c,
    error: c,
    errorText: c,
    disabled: c,
    disabledText: c,
    focusRing: c,
    selectionFill: c,
    moduleLedger: c,
    moduleLedgerLight: c,
    moduleGear: c,
    moduleGearLight: c,
    moduleLogistics: c,
    moduleLogisticsLight: c,
    moduleVault: c,
    moduleVaultLight: c,
    moduleActivity: c,
    moduleActivityLight: c,
    moduleMemories: c,
    moduleMemoriesLight: c,
    headerGradientStart: c,
    headerGradientEnd: c,
    offlineBannerBackground: c,
    bottomNavBackground: c,
    bottomNavActiveIcon: c,
    bottomNavInactiveIcon: c,
    inputFillWarm: c,
    focusBorderWarm: c,
    borderWarm: c,
    warning: c,
    primaryDark: c,
    paperDeep: c,
    cardSoft: c,
    ink2: c,
    saffronSoft: c,
    saffronTint: c,
    rule: c,
    rule2: c,
    cat1: c,
    cat2: c,
    cat3: c,
    cat4: c,
    cat5: c,
    cat6: c,
  );
}

class _OtherSpacingExtension extends ThemeExtension<AppSpacingTokens> {
  const _OtherSpacingExtension();

  @override
  _OtherSpacingExtension copyWith() => this;

  @override
  _OtherSpacingExtension lerp(
    ThemeExtension<AppSpacingTokens>? other,
    double t,
  ) => this;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AppColorTokens — saffron palette', () {
    test('light.primary equals saffron #D17B2C', () {
      expect(AppColorTokens.light.primary, equals(const Color(0xFFD17B2C)));
    });

    test('light.scaffoldBackground equals paper #F6F1E6', () {
      expect(
        AppColorTokens.light.scaffoldBackground,
        equals(const Color(0xFFF6F1E6)),
      );
    });

    test('light.cardSurface equals white #FFFFFF', () {
      expect(AppColorTokens.light.cardSurface, equals(const Color(0xFFFFFFFF)));
    });

    test('light.textPrimary equals ink #1B1A17', () {
      expect(AppColorTokens.light.textPrimary, equals(const Color(0xFF1B1A17)));
    });

    test('light.success equals sage #5C7A57', () {
      expect(AppColorTokens.light.success, equals(const Color(0xFF5C7A57)));
    });

    test('light.error equals rust #A84B33', () {
      expect(AppColorTokens.light.error, equals(const Color(0xFFA84B33)));
    });

    test('light.textOnPrimary equals white #FFFFFF', () {
      expect(
        AppColorTokens.light.textOnPrimary,
        equals(const Color(0xFFFFFFFF)),
      );
    });

    test('light appended saffron tokens are populated', () {
      final t = AppColorTokens.light;
      expect(t.paperDeep, equals(const Color(0xFFEFE8D7)));
      expect(t.cardSoft, equals(const Color(0xFFFBF7EE)));
      expect(t.ink2, equals(const Color(0xFF3D3A33)));
      expect(t.saffronSoft, equals(const Color(0xFFF4DDB8)));
      expect(t.saffronTint, equals(const Color(0xFFFBEED5)));
    });

    test('light category palette has six distinct colors', () {
      final cats = [
        AppColorTokens.light.cat1,
        AppColorTokens.light.cat2,
        AppColorTokens.light.cat3,
        AppColorTokens.light.cat4,
        AppColorTokens.light.cat5,
        AppColorTokens.light.cat6,
      ];
      expect(
        cats.toSet().length,
        equals(6),
        reason: 'Category palette must have 6 distinct colors',
      );
    });

    test('copyWith returns new instance with changed primary', () {
      const newPrimary = Color(0xFF000000);
      final modified = AppColorTokens.light.copyWith(primary: newPrimary);
      expect(modified.primary, equals(newPrimary));
      expect(
        modified.scaffoldBackground,
        equals(AppColorTokens.light.scaffoldBackground),
      );
    });

    test('copyWith propagates appended saffron fields', () {
      const newSaffron = Color(0xFFAA0000);
      final modified = AppColorTokens.light.copyWith(saffronSoft: newSaffron);
      expect(modified.saffronSoft, equals(newSaffron));
      expect(modified.saffronTint, equals(AppColorTokens.light.saffronTint));
    });

    test('copyWith does not mutate original instance', () {
      final original = AppColorTokens.light;
      original.copyWith(primary: const Color(0xFF000000));
      expect(original.primary, equals(const Color(0xFFD17B2C)));
    });

    test('lerp at t=0.0 returns this', () {
      final lerped = AppColorTokens.light.lerp(_allBlack(), 0.0);
      expect(lerped.primary, equals(AppColorTokens.light.primary));
      expect(lerped.saffronSoft, equals(AppColorTokens.light.saffronSoft));
    });

    test('lerp at t=1.0 returns other values', () {
      final lerped = AppColorTokens.light.lerp(_allBlack(), 1.0);
      expect(lerped.primary, equals(const Color(0xFF000000)));
      expect(lerped.saffronSoft, equals(const Color(0xFF000000)));
      expect(lerped.cat1, equals(const Color(0xFF000000)));
    });

    test('lerp at t=0.5 produces intermediate color', () {
      final white = AppColorTokens.light.copyWith(
        primary: const Color(0xFFFFFFFF),
      );
      final black = AppColorTokens.light.copyWith(
        primary: const Color(0xFF000000),
      );
      final lerped = white.lerp(black, 0.5);
      expect(lerped.primary, isNot(equals(const Color(0xFFFFFFFF))));
      expect(lerped.primary, isNot(equals(const Color(0xFF000000))));
    });
  });

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
      expect(s.radiusSmall, equals(8.0));
      expect(s.radiusMedium, equals(12.0));
      expect(s.radiusLarge, equals(16.0));
    });

    test('standard.buttonHeight equals 52.0', () {
      expect(AppSpacingTokens.standard.buttonHeight, equals(52.0));
    });

    test('copyWith can override every spacing token', () {
      final modified = AppSpacingTokens.standard.copyWith(
        space4: 5,
        space8: 9,
        space12: 13,
        space16: 17,
        space20: 21,
        space24: 25,
        space32: 33,
        radiusSmall: 10,
        radiusMedium: 14,
        radiusLarge: 18,
        buttonHeight: 56,
      );

      expect(modified.space4, equals(5));
      expect(modified.space8, equals(9));
      expect(modified.space12, equals(13));
      expect(modified.space16, equals(17));
      expect(modified.space20, equals(21));
      expect(modified.space24, equals(25));
      expect(modified.space32, equals(33));
      expect(modified.radiusSmall, equals(10));
      expect(modified.radiusMedium, equals(14));
      expect(modified.radiusLarge, equals(18));
      expect(modified.buttonHeight, equals(56));
    });

    test('copyWith preserves defaults when no overrides are provided', () {
      final modified = AppSpacingTokens.standard.copyWith();
      expect(modified.space4, equals(AppSpacingTokens.standard.space4));
      expect(
        modified.radiusLarge,
        equals(AppSpacingTokens.standard.radiusLarge),
      );
      expect(
        modified.buttonHeight,
        equals(AppSpacingTokens.standard.buttonHeight),
      );
    });

    test('lerp ignores unrelated ThemeExtension types', () {
      final result = AppSpacingTokens.standard.lerp(
        const _OtherSpacingExtension(),
        0.5,
      );
      expect(result, same(AppSpacingTokens.standard));
    });

    test('lerp interpolates the full spacing scale', () {
      const expanded = AppSpacingTokens(
        space4: 8,
        space8: 16,
        space12: 24,
        space16: 32,
        space20: 40,
        space24: 48,
        space32: 64,
        radiusSmall: 16,
        radiusMedium: 24,
        radiusLarge: 32,
        buttonHeight: 64,
      );

      final lerped = AppSpacingTokens.standard.lerp(expanded, 0.5);

      expect(lerped.space4, equals(6));
      expect(lerped.space8, equals(12));
      expect(lerped.space12, equals(18));
      expect(lerped.space16, equals(24));
      expect(lerped.space20, equals(30));
      expect(lerped.space24, equals(36));
      expect(lerped.space32, equals(48));
      expect(lerped.radiusSmall, equals(12));
      expect(lerped.radiusMedium, equals(18));
      expect(lerped.radiusLarge, equals(24));
      expect(lerped.buttonHeight, equals(58));
    });
  });

  group('AppShadowTokens', () {
    test('light.raised has exactly 2 BoxShadow entries', () {
      expect(AppShadowTokens.light.raised.length, equals(2));
    });

    test('light.floating has exactly 2 BoxShadow entries', () {
      expect(AppShadowTokens.light.floating.length, equals(2));
    });

    test('light.flat is empty', () {
      expect(AppShadowTokens.light.flat, isEmpty);
    });
  });

  group('ThemeExtension registration', () {
    test('AppColorTokens is registered in test theme', () {
      expect(_testTheme().extension<AppColorTokens>(), isNotNull);
    });

    test('AppSpacingTokens is registered in test theme', () {
      expect(_testTheme().extension<AppSpacingTokens>(), isNotNull);
    });

    test('AppShadowTokens is registered in test theme', () {
      expect(_testTheme().extension<AppShadowTokens>(), isNotNull);
    });

    test('AppColorTokens from test theme has correct primary color', () {
      final tokens = _testTheme().extension<AppColorTokens>()!;
      expect(tokens.primary, equals(const Color(0xFFD17B2C)));
    });

    testWidgets('AppTheme.lightTheme registers all three extensions', (
      tester,
    ) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exception.toString().contains('google_fonts')) return;
        originalOnError?.call(details);
      };

      final theme = AppTheme.lightTheme;

      FlutterError.onError = originalOnError;

      expect(theme.extension<AppColorTokens>(), isNotNull);
      expect(theme.extension<AppSpacingTokens>(), isNotNull);
      expect(theme.extension<AppShadowTokens>(), isNotNull);
    });
  });

  group('BuildContext extensions', () {
    testWidgets('context.colors returns AppColorTokens', (tester) async {
      late AppColorTokens colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Builder(
            builder: (context) {
              colors = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(colors.primary, equals(const Color(0xFFD17B2C)));
    });

    testWidgets('context.spacing returns AppSpacingTokens', (tester) async {
      late AppSpacingTokens spacing;
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Builder(
            builder: (context) {
              spacing = context.spacing;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(spacing.space16, equals(16.0));
    });

    testWidgets('context.shadows returns AppShadowTokens', (tester) async {
      late AppShadowTokens shadows;
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Builder(
            builder: (context) {
              shadows = context.shadows;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(shadows.raised.length, equals(2));
    });

    testWidgets('context.gradient resolves by active brightness', (
      tester,
    ) async {
      late LinearGradient lightGradient;
      late LinearGradient darkGradient;

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Builder(
            builder: (context) {
              lightGradient = context.gradient(AppGradients.terracotta);
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        Theme(
          data: ThemeData.dark(useMaterial3: true).copyWith(
            extensions: <ThemeExtension>[
              AppColorTokens.dark,
              AppSpacingTokens.standard,
              AppShadowTokens.dark,
            ],
          ),
          child: Builder(
            builder: (context) {
              darkGradient = context.gradient(AppGradients.terracotta);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(lightGradient, equals(AppGradients.terracotta.light));
      expect(darkGradient, equals(AppGradients.terracotta.dark));
    });
  });

  group('WCAG AA contrast — saffron palette', () {
    const paper = Color(0xFFF6F1E6);
    const white = Color(0xFFFFFFFF);

    test('textPrimary (ink) on paper >= 4.5:1', () {
      final ratio = contrastRatio(AppColorTokens.light.textPrimary, paper);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: 'Ink on paper: ${ratio.toStringAsFixed(2)}:1',
      );
    });

    test('textSecondary (ink-3) on paper >= 4.5:1', () {
      final ratio = contrastRatio(AppColorTokens.light.textSecondary, paper);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: 'Ink-3 on paper: ${ratio.toStringAsFixed(2)}:1',
      );
    });

    test('successText (sage-dark) on white >= 4.5:1', () {
      final ratio = contrastRatio(AppColorTokens.light.successText, white);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: 'Sage-dark on white: ${ratio.toStringAsFixed(2)}:1',
      );
    });

    test('errorText (rust-dark) on white >= 4.5:1', () {
      final ratio = contrastRatio(AppColorTokens.light.errorText, white);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: 'Rust-dark on white: ${ratio.toStringAsFixed(2)}:1',
      );
    });

    test('white on saffron >= 3.0:1 (AA large/UI threshold)', () {
      // Saffron on white is borderline (~3.4:1) — passes AA large but not AA
      // normal text. This is acceptable for buttons/FAB labels which are
      // typically larger. Functional text on saffron surfaces should use ink.
      final ratio = contrastRatio(white, AppColorTokens.light.primary);
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason: 'White on saffron: ${ratio.toStringAsFixed(2)}:1',
      );
    });
  });
}
