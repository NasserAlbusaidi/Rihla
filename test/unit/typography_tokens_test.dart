import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/tokens/typography_tokens.dart';

/// The four brand faces are bundled as app assets and resolved natively by the
/// Flutter font engine — no `google_fonts` runtime fetch (#103). Each helper is
/// therefore a pure, synchronous `TextStyle` builder whose `fontFamily` is the
/// exact bundled family name (no synthetic `Family_variant` suffix), so these
/// are plain `test()`s with no async font-load machinery.
void main() {
  group('AppTypography.sans (Geist)', () {
    test('uses the bundled Geist family, defaults to w400, no tabular by default', () {
      final style = AppTypography.sans(fontSize: 16);
      expect(style.fontFamily, AppTypography.sansFamily);
      expect(style.fontFamily, 'Geist');
      expect(style.fontWeight, FontWeight.w400);
      expect(style.fontStyle, isNot(FontStyle.italic));
      expect(style.fontFeatures, isNull);
    });

    test('opts into tabular figures when asked', () {
      final style = AppTypography.sans(fontSize: 16, tabularNums: true);
      expect(style.fontFeatures, AppTypography.tabularNumberFeatures);
    });
  });

  group('AppTypography.mono (Geist Mono)', () {
    test('uses the bundled Geist Mono family, defaults to w500, always tabular', () {
      final style = AppTypography.mono(fontSize: 14);
      expect(style.fontFamily, AppTypography.monoFamily);
      expect(style.fontFamily, 'Geist Mono');
      expect(style.fontWeight, FontWeight.w500);
      expect(style.fontFeatures, AppTypography.tabularNumberFeatures);
    });
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
      expect(
        style.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  group('AppTypography.display (Instrument Serif)', () {
    test('uses the bundled Instrument Serif family, italic by default, w400', () {
      final style = AppTypography.display(fontSize: 28);
      expect(style.fontFamily, AppTypography.displayFamily);
      expect(style.fontFamily, 'Instrument Serif');
      expect(style.fontStyle, FontStyle.italic);
      expect(style.fontWeight, FontWeight.w400);
    });

    test('honors italic: false', () {
      final style = AppTypography.display(fontSize: 28, italic: false);
      expect(style.fontStyle, FontStyle.normal);
    });
  });

  group('AppTypography.arabicDisplay (Reem Kufi)', () {
    test('uses the bundled Reem Kufi family and never defaults italic on', () {
      final style = AppTypography.arabicDisplay(fontSize: 22);
      expect(style.fontFamily, AppTypography.reemKufiFamily);
      expect(style.fontFamily, 'Reem Kufi');
      expect(style.fontStyle, isNot(FontStyle.italic));
      expect(style.fontWeight, FontWeight.w400);
    });

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
}
