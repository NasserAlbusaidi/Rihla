import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/r_amount.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );
}

/// Walk a [TextSpan] tree and return every leaf span (one with non-null text).
///
/// `Text.rich` wraps the caller's span in a default-style parent, so the
/// caller's children show up nested rather than as direct `.children!` of
/// the root. Visiting recursively gives us a flat list in render order.
List<TextSpan> _leafSpans(WidgetTester tester) {
  final richText = tester.widget<RichText>(find.byType(RichText).first);
  final leaves = <TextSpan>[];
  richText.text.visitChildren((node) {
    if (node is TextSpan && node.text != null) leaves.add(node);
    return true;
  });
  return leaves;
}

/// Concatenate the text of every leaf span — what the user actually sees.
String _renderedText(WidgetTester tester) {
  return _leafSpans(tester).map((s) => s.text).join();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('RAmount — formatting', () {
    testWidgets('OMR renders 3 decimal places', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('184.2'), currency: 'OMR')),
      );
      expect(_renderedText(tester), 'OMR 184.200');
    });

    testWidgets('USD renders 2 decimal places', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('100'), currency: 'USD')),
      );
      expect(_renderedText(tester), 'USD 100.00');
    });

    testWidgets('integer value still gets decimals', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.fromInt(50), currency: 'OMR')),
      );
      expect(_renderedText(tester), 'OMR 50.000');
    });

    testWidgets('absolute value used regardless of sign mode', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(
          value: Decimal.parse('-42.500'),
          currency: 'OMR',
          sign: false,
        )),
      );
      // No prefix in non-sign mode; abs value rendered.
      expect(_renderedText(tester), 'OMR 42.500');
    });
  });

  group('RAmount — multi-currency precision (#63)', () {
    testWidgets('JPY renders 0 decimal places', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('1234'), currency: 'JPY')),
      );
      expect(_renderedText(tester), 'JPY 1234');
    });

    testWidgets('KWD renders 3 decimal places', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('50'), currency: 'KWD')),
      );
      expect(_renderedText(tester), 'KWD 50.000');
    });

    testWidgets('BHD renders 3 decimal places', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('50'), currency: 'BHD')),
      );
      expect(_renderedText(tester), 'BHD 50.000');
    });

    testWidgets('QAR renders 2 decimal places', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('50'), currency: 'QAR')),
      );
      expect(_renderedText(tester), 'QAR 50.00');
    });

    testWidgets('unknown currency falls back to 2 decimal places',
        (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('50'), currency: 'XYZ')),
      );
      expect(_renderedText(tester), 'XYZ 50.00');
    });
  });

  group('RAmount — sign mode', () {
    testWidgets('positive shows + prefix', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(
          value: Decimal.parse('184.200'),
          currency: 'OMR',
          sign: true,
        )),
      );
      expect(_renderedText(tester), '+OMR 184.200');
    });

    testWidgets('negative shows typographic minus (U+2212), not hyphen',
        (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(
          value: Decimal.parse('-42.500'),
          currency: 'OMR',
          sign: true,
        )),
      );
      final rendered = _renderedText(tester);
      expect(rendered, '−OMR 42.500');
      expect(rendered.contains('-'), isFalse,
          reason: 'must use U+2212 minus, not hyphen-minus');
    });

    testWidgets('zero with sign mode shows no prefix', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(
          value: Decimal.zero,
          currency: 'OMR',
          sign: true,
        )),
      );
      expect(_renderedText(tester), 'OMR 0.000');
    });
  });

  group('RAmount — color tones', () {
    Color wholeColor(WidgetTester tester) {
      // Leaves are: [currency code, whole, decimal?]. Whole is index 1.
      return _leafSpans(tester)[1].style!.color!;
    }

    testWidgets('positive sign mode → success/sage tone', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('10'), sign: true)),
      );
      // Sage/emerald = #1F7A5C
      expect(wholeColor(tester), const Color(0xFF1F7A5C));
    });

    testWidgets('negative sign mode → error/rust tone', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('-10'), sign: true)),
      );
      // Rust/pomegranate = #B03A48
      expect(wholeColor(tester), const Color(0xFFB03A48));
    });

    testWidgets('explicit tone:rust overrides positive value', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(
          value: Decimal.parse('10'),
          sign: true,
          tone: AmountTone.rust,
        )),
      );
      expect(wholeColor(tester), const Color(0xFFB03A48));
    });

    testWidgets('zero in sign mode → ink/textPrimary tone', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.zero, sign: true)),
      );
      expect(wholeColor(tester), const Color(0xFF1B1F1E));
    });
  });

  group('RAmount — size scaling', () {
    testWidgets('decimal portion uses 0.55× whole size', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('184.2'), size: 100)),
      );
      final leaves = _leafSpans(tester);
      expect(leaves[1].style!.fontSize, 100.0);
      expect(leaves[2].style!.fontSize, closeTo(55.0, 0.01));
    });

    testWidgets('currency code uses 0.42× whole size', (tester) async {
      await tester.pumpWidget(
        _wrap(RAmount(value: Decimal.parse('184.2'), size: 100)),
      );
      expect(_leafSpans(tester)[0].style!.fontSize, closeTo(42.0, 0.01));
    });
  });

  group('RAmount — semantics (a11y)', () {
    testWidgets('negative signed amount announces an ASCII minus, '
        'not the fragmented spans with U+2212', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          RAmount(value: Decimal.parse('-12.5'), currency: 'OMR', sign: true),
        ),
      );
      expect(find.bySemanticsLabel('-OMR 12.500'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('positive signed amount announces the plus', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          RAmount(value: Decimal.parse('12.5'), currency: 'OMR', sign: true),
        ),
      );
      expect(find.bySemanticsLabel('+OMR 12.500'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('showCurrency:false announces the bare value', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.parse('184.2'),
            currency: 'USD',
            showCurrency: false,
          ),
        ),
      );
      expect(find.bySemanticsLabel('184.20'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('caller-provided semanticsLabel wins', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.parse('184.2'),
            currency: 'OMR',
            semanticsLabel: 'You are owed OMR 184.200',
          ),
        ),
      );
      expect(find.bySemanticsLabel('You are owed OMR 184.200'), findsOneWidget);
      handle.dispose();
    });
  });
}
