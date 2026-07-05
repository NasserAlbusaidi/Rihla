import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// #900 PR-3 comp 6 — hero-only polarity caret. HERO-scoped: opted in ONLY
/// at `balance_hero_card.dart`'s net `RAmount`; every other call site keeps
/// `polarityCaret: false` (the default) and is untouched by this feature.
Widget _wrap(Widget child, {TextDirection? textDirection}) {
  final app = MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: Center(child: child)),
  );
  if (textDirection == null) return app;
  return Directionality(textDirection: textDirection, child: app);
}

List<TextSpan> _leafSpans(WidgetTester tester) {
  final richText = tester.widget<RichText>(find.byType(RichText).first);
  final leaves = <TextSpan>[];
  richText.text.visitChildren((node) {
    if (node is TextSpan && node.text != null) leaves.add(node);
    return true;
  });
  return leaves;
}

String _renderedText(WidgetTester tester) {
  return _leafSpans(tester).map((s) => s.text).join();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('RAmount — polarityCaret', () {
    testWidgets('positive value shows ▲ and suppresses the + prefix', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.parse('44.500'),
            currency: 'OMR',
            showCurrency: false,
            sign: true,
            polarityCaret: true,
          ),
        ),
      );
      final rendered = _renderedText(tester);
      expect(rendered, '▲ 44.500');
      expect(rendered.contains('+'), isFalse);
      final leaves = _leafSpans(tester);
      expect(leaves.first.style!.color, const Color(0xFF1F7A5C)); // success
    });

    testWidgets('negative value shows ▼ and suppresses the − prefix', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.parse('-44.500'),
            currency: 'OMR',
            showCurrency: false,
            sign: true,
            polarityCaret: true,
          ),
        ),
      );
      final rendered = _renderedText(tester);
      expect(rendered, '▼ 44.500');
      expect(rendered.contains('−'), isFalse);
      final leaves = _leafSpans(tester);
      expect(leaves.first.style!.color, const Color(0xFFB03A48)); // error
    });

    testWidgets('zero value renders neither caret glyph', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.zero,
            currency: 'OMR',
            showCurrency: false,
            sign: true,
            polarityCaret: true,
          ),
        ),
      );
      final rendered = _renderedText(tester);
      expect(rendered.contains('▲'), isFalse);
      expect(rendered.contains('▼'), isFalse);
    });

    testWidgets('polarityCaret defaults to false — dense rows unaffected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.parse('44.500'),
            currency: 'OMR',
            showCurrency: false,
            sign: true,
          ),
        ),
      );
      final rendered = _renderedText(tester);
      expect(rendered.contains('▲'), isFalse);
      expect(rendered, '+ 44.500');
    });

    testWidgets('RTL: caret is directionally neutral, never flips', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.parse('44.500'),
            currency: 'OMR',
            showCurrency: false,
            sign: true,
            polarityCaret: true,
          ),
          textDirection: TextDirection.rtl,
        ),
      );
      final rendered = _renderedText(tester);
      expect(rendered, '▲ 44.500');
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      expect(richText.textDirection, TextDirection.ltr);
    });

    testWidgets('a11y: spoken label keeps the ASCII sign, caret absent', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          RAmount(
            value: Decimal.parse('44.500'),
            currency: 'OMR',
            sign: true,
            polarityCaret: true,
          ),
        ),
      );
      expect(find.bySemanticsLabel('+OMR 44.500'), findsOneWidget);
      handle.dispose();
    });
  });
}
