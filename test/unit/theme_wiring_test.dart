import 'package:flutter/foundation.dart';
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
  });
}
