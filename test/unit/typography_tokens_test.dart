import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/tokens/typography_tokens.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Obtains a [BuildContext] under [locale] for the context-aware helpers
/// (`caption`, `displayOf`) — they branch on
/// `Localizations.localeOf(context).languageCode`.
Future<BuildContext> _localizedContext(
  WidgetTester tester,
  Locale locale,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return captured;
}

/// Brand faces are bundled as app assets and resolved natively by the Flutter
/// font engine — no `google_fonts` runtime fetch (#103). The Arabic wordmark
/// face is a small Reem Kufi subset (#636). Each helper is therefore a pure,
/// synchronous `TextStyle` builder whose `fontFamily` is the exact bundled
/// family name (no synthetic `Family_variant` suffix), so these are plain
/// `test()`s with no async font-load machinery.
void main() {
  group('AppTypography.sans (Geist)', () {
    test(
      'uses the bundled Geist family, defaults to w400, no tabular by default',
      () {
        final style = AppTypography.sans(fontSize: 16);
        expect(style.fontFamily, AppTypography.sansFamily);
        expect(style.fontFamily, 'Geist');
        expect(style.fontWeight, FontWeight.w400);
        expect(style.fontStyle, isNot(FontStyle.italic));
        expect(style.fontFeatures, isNull);
      },
    );

    test('opts into tabular figures when asked', () {
      final style = AppTypography.sans(fontSize: 16, tabularNums: true);
      expect(style.fontFeatures, AppTypography.tabularNumberFeatures);
    });
  });

  group('AppTypography.mono (Geist Mono)', () {
    test(
      'uses the bundled Geist Mono family, defaults to w500, always tabular',
      () {
        final style = AppTypography.mono(fontSize: 14);
        expect(style.fontFamily, AppTypography.monoFamily);
        expect(style.fontFamily, 'Geist Mono');
        expect(style.fontWeight, FontWeight.w500);
        expect(style.fontFeatures, AppTypography.tabularNumberFeatures);
      },
    );
  });

  group('tabular number features (#148: no slashed zero in money)', () {
    test('feature set keeps tabular figures but drops the slashed zero', () {
      expect(
        AppTypography.tabularNumberFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(
        AppTypography.tabularNumberFeatures,
        isNot(contains(const FontFeature.slashedZero())),
        reason: 'a slashed 0 reads as Ø/null on money figures (#148)',
      );
    });

    test('mono() money style renders a plain (un-slashed) zero', () {
      final style = AppTypography.mono(fontSize: 14);
      expect(
        style.fontFeatures,
        isNot(contains(const FontFeature.slashedZero())),
      );
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('AppTypography.display (Instrument Serif)', () {
    test(
      'uses the bundled Instrument Serif family, italic by default, w400',
      () {
        final style = AppTypography.display(fontSize: 28);
        expect(style.fontFamily, AppTypography.displayFamily);
        expect(style.fontFamily, 'Instrument Serif');
        expect(style.fontStyle, FontStyle.italic);
        expect(style.fontWeight, FontWeight.w400);
      },
    );

    test('honors italic: false', () {
      final style = AppTypography.display(fontSize: 28, italic: false);
      expect(style.fontStyle, FontStyle.normal);
    });
  });

  group('AppTypography.arabicDisplay (Rihla Arabic Display)', () {
    test(
      'uses the bundled Arabic wordmark subset and never defaults italic on',
      () {
        final style = AppTypography.arabicDisplay(fontSize: 22);
        expect(style.fontFamily, AppTypography.arabicDisplayFamily);
        expect(style.fontFamily, 'Rihla Arabic Display');
        expect(style.fontStyle, isNot(FontStyle.italic));
        expect(style.fontWeight, FontWeight.w400);
      },
    );

    test('honors color, weight, letterSpacing overrides', () {
      final style = AppTypography.arabicDisplay(
        fontSize: 60,
        color: const Color(0xFF112233),
        fontWeight: FontWeight.w600,
        letterSpacing: -2,
      );
      expect(style.color, const Color(0xFF112233));
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, -2);
    });
  });

  group('AppTypography.caption (per-script caption, #841)', () {
    testWidgets(
      'EN: byte-identical to mono() — family, w500 default, spacing preserved',
      (tester) async {
        final context = await _localizedContext(tester, const Locale('en'));
        final style = AppTypography.caption(
          context,
          fontSize: 11,
          letterSpacing: 1.2,
        );
        final monoStyle = AppTypography.mono(fontSize: 11, letterSpacing: 1.2);
        expect(style.fontFamily, AppTypography.monoFamily);
        expect(style.fontFamily, 'Geist Mono');
        expect(
          style.fontWeight,
          FontWeight.w500,
          reason:
              'caption() EN default weight must equal mono()\'s default so a '
              'no-weight migrated caller renders byte-identically',
        );
        expect(style.fontWeight, monoStyle.fontWeight);
        expect(style.letterSpacing, 1.2);
        expect(style, monoStyle);
      },
    );

    testWidgets('AR: sans w700, letterSpacing 0, fontSize floored to 11', (
      tester,
    ) async {
      final context = await _localizedContext(tester, const Locale('ar'));
      final style = AppTypography.caption(
        context,
        fontSize: 10.5,
        letterSpacing: 1.2,
      );
      expect(style.fontFamily, AppTypography.sansFamily);
      expect(style.fontFamily, 'Geist');
      expect(style.fontWeight, FontWeight.w700);
      expect(style.letterSpacing, 0);
      expect(style.fontSize, 11);
    });

    testWidgets('AR: fontSize at or above the floor passes through', (
      tester,
    ) async {
      final context = await _localizedContext(tester, const Locale('ar'));
      final style = AppTypography.caption(context, fontSize: 13);
      expect(style.fontSize, 13);
    });
  });

  group('AppTypography.displayOf (locale-aware display, #841)', () {
    testWidgets('EN: italic Instrument Serif, w400 default — display() as-is', (
      tester,
    ) async {
      final context = await _localizedContext(tester, const Locale('en'));
      final style = AppTypography.displayOf(context, fontSize: 28);
      expect(style.fontFamily, AppTypography.displayFamily);
      expect(style.fontStyle, FontStyle.italic);
      expect(style.fontWeight, FontWeight.w400);
      expect(style, AppTypography.display(fontSize: 28));
    });

    testWidgets('AR: upright w500 default — no synthetic italic', (
      tester,
    ) async {
      final context = await _localizedContext(tester, const Locale('ar'));
      final style = AppTypography.displayOf(context, fontSize: 28);
      expect(style.fontStyle, FontStyle.normal);
      expect(style.fontWeight, FontWeight.w500);
    });

    testWidgets('AR: explicit fontWeight is honored', (tester) async {
      final context = await _localizedContext(tester, const Locale('ar'));
      final style = AppTypography.displayOf(
        context,
        fontSize: 28,
        fontWeight: FontWeight.w400,
      );
      expect(style.fontWeight, FontWeight.w400);
    });

    testWidgets('AR: the italic argument is ignored — always upright', (
      tester,
    ) async {
      final context = await _localizedContext(tester, const Locale('ar'));
      final style = AppTypography.displayOf(
        context,
        fontSize: 28,
        italic: true,
      );
      expect(style.fontStyle, FontStyle.normal);
    });
  });
}
