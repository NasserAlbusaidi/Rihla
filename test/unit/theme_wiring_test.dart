import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/core/theme/tokens/shadow_tokens.dart';
import 'package:safar/core/theme/tokens/spacing_tokens.dart';

/// Suppresses google_fonts' async "asset not bundled" error while [body] runs.
///
/// Mirrors the pattern used in [design_tokens_test.dart] around
/// `AppTheme.lightTheme registers all three extensions`:
/// fonts are not bundled in test assets but do not affect token/extension
/// assertions, so the async loader complaint is silently dropped.
T _suppressFontErrors<T>(T Function() body) {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('google_fonts')) return;
    originalOnError?.call(details);
  };
  try {
    return body();
  } finally {
    FlutterError.onError = originalOnError;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AppTheme wiring', () {
    testWidgets(
        'lightTheme has Brightness.light and registers light tokens',
        (tester) async {
      _suppressFontErrors(() {
        final t = AppTheme.lightTheme;
        expect(t.brightness, Brightness.light);
        expect(t.extension<AppColorTokens>(), AppColorTokens.light);
        expect(t.extension<AppSpacingTokens>(), AppSpacingTokens.standard);
        expect(t.extension<AppShadowTokens>(), isNotNull);
      });
    });

    testWidgets(
        'darkTheme has Brightness.dark and registers dark tokens',
        (tester) async {
      _suppressFontErrors(() {
        final t = AppTheme.darkTheme;
        expect(t.brightness, Brightness.dark);
        expect(t.extension<AppColorTokens>(), AppColorTokens.dark);
        expect(t.extension<AppSpacingTokens>(), AppSpacingTokens.standard);
        expect(t.extension<AppShadowTokens>(), isNotNull);
      });
    });

    testWidgets('light and dark shadow extensions are distinct instances',
        (tester) async {
      _suppressFontErrors(() {
        expect(
          identical(
            AppTheme.lightTheme.extension<AppShadowTokens>(),
            AppTheme.darkTheme.extension<AppShadowTokens>(),
          ),
          isFalse,
        );
      });
    });

    testWidgets(
        'AppTheme.darkTheme is a valid ThemeData with extensions populated',
        (tester) async {
      _suppressFontErrors(() {
        // Reference AppTheme.darkTheme directly so grep can find the string.
        expect(AppTheme.darkTheme.brightness, Brightness.dark);
        expect(AppTheme.darkTheme.extension<AppColorTokens>(),
            AppColorTokens.dark);
      });
    });

    // #622: themes derive only from compile-time tokens (no runtime/context
    // inputs), so each access must return the SAME cached ThemeData rather than
    // rebuilding the full tree on every root rebuild. Pins the static-final
    // memoization — a regression to a `get` accessor makes these identical
    // checks fail.
    testWidgets('lightTheme returns the same cached instance across accesses',
        (tester) async {
      _suppressFontErrors(() {
        expect(identical(AppTheme.lightTheme, AppTheme.lightTheme), isTrue);
      });
    });

    testWidgets('darkTheme returns the same cached instance across accesses',
        (tester) async {
      _suppressFontErrors(() {
        expect(identical(AppTheme.darkTheme, AppTheme.darkTheme), isTrue);
      });
    });

    // #900 PR-4: dark previously fell back to M3 defaults for these five
    // component themes (light already defined them). Pins each against the
    // dark token instance so the fallback can't silently regress.
    testWidgets('darkTheme defines the previously-missing component themes',
        (tester) async {
      _suppressFontErrors(() {
        final t = AppTheme.darkTheme;
        const dark = AppColorTokens.dark;

        expect(t.floatingActionButtonTheme.backgroundColor, dark.primary);
        expect(t.floatingActionButtonTheme.foregroundColor,
            dark.textOnPrimary);

        expect(t.chipTheme.selectedColor, dark.textPrimary);
        expect(t.chipTheme.labelStyle?.color, dark.textSecondary);
        expect(t.chipTheme.secondaryLabelStyle?.color, dark.textOnPrimary);
        expect(
          (t.chipTheme.shape as RoundedRectangleBorder?)?.side.color,
          dark.rule2,
        );

        expect(t.dividerTheme.color, dark.rule);

        expect(t.bottomSheetTheme.backgroundColor, dark.cardSurface);
        expect(t.dialogTheme.backgroundColor, dark.cardSurface);
      });
    });

    // #900 PR-4: dark hintStyle read textMuted (~3.1:1 on inputFill, below
    // AA) — swapped to textSecondary (~5.6:1).
    testWidgets('darkTheme input hint uses textSecondary, not textMuted',
        (tester) async {
      _suppressFontErrors(() {
        final hintColor =
            AppTheme.darkTheme.inputDecorationTheme.hintStyle?.color;
        expect(hintColor, AppColorTokens.dark.textSecondary);
        expect(hintColor, isNot(AppColorTokens.dark.textMuted));
      });
    });
  });
}
