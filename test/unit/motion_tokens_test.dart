import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/domain_aliases.dart';
import 'package:safar/core/theme/tokens/motion_tokens.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AppMotionTokens', () {
    test('base has the canonical three durations (DESIGN.md §6)', () {
      const m = AppMotionTokens.base;
      expect(m.quick, const Duration(milliseconds: 120));
      expect(m.standard, const Duration(milliseconds: 200));
      expect(m.emphasis, const Duration(milliseconds: 300));
    });

    test('base curves are easeInOut / easeOutCubic', () {
      const m = AppMotionTokens.base;
      expect(m.curveStandard, Curves.easeInOut);
      expect(m.curveEmphasis, Curves.easeOutCubic);
    });

    test('copyWith overrides one field and preserves the rest', () {
      final m = AppMotionTokens.base.copyWith(
        standard: const Duration(milliseconds: 250),
      );
      expect(m.standard, const Duration(milliseconds: 250));
      expect(m.quick, AppMotionTokens.base.quick);
      expect(m.emphasis, AppMotionTokens.base.emphasis);
    });

    test('lerp snaps at the t=0.5 threshold', () {
      final other = AppMotionTokens.base.copyWith(
        quick: const Duration(milliseconds: 999),
      );
      expect(AppMotionTokens.base.lerp(other, 0.4).quick,
          AppMotionTokens.base.quick);
      expect(AppMotionTokens.base.lerp(other, 0.6).quick, other.quick);
    });

    test('lerp ignores unrelated extension types', () {
      final result = AppMotionTokens.base.lerp(null, 0.5);
      expect(result, same(AppMotionTokens.base));
    });
  });

  group('AppMotionTokens — theme registration', () {
    testWidgets('both themes register AppMotionTokens', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exception.toString().contains('google_fonts')) return;
        originalOnError?.call(details);
      };
      expect(AppTheme.lightTheme.extension<AppMotionTokens>(), isNotNull);
      expect(AppTheme.darkTheme.extension<AppMotionTokens>(), isNotNull);
      FlutterError.onError = originalOnError;
    });

    testWidgets('context.motion resolves to base', (tester) async {
      late AppMotionTokens motion;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true).copyWith(
            extensions: const <ThemeExtension>[AppMotionTokens.base],
          ),
          home: Builder(
            builder: (context) {
              motion = context.motion;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(motion.standard, const Duration(milliseconds: 200));
    });
  });
}
