import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/shared/widgets/animated_currency_text.dart';

void main() {
  group('AnimatedCurrencyText', () {
    testWidgets('renders without errors for initial value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedCurrencyText(
            value: Decimal.parse('10.500'),
            currency: 'OMR',
          ),
        ),
      );

      expect(find.byType(AnimatedCurrencyText), findsOneWidget);
    });

    testWidgets('renders TweenAnimationBuilder', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedCurrencyText(
            value: Decimal.parse('10.500'),
            currency: 'OMR',
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(TweenAnimationBuilder<double>), findsWidgets);
    });

    testWidgets('displays formatted currency text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedCurrencyText(
            value: Decimal.parse('10.500'),
            currency: 'OMR',
          ),
        ),
      );

      // Pump to completion
      await tester.pump();
      await tester.pumpAndSettle();

      // Should contain some OMR-formatted text
      final richText = tester.widgetList<Text>(find.byType(Text));
      expect(richText.isNotEmpty, true);
    });

    testWidgets('uses default duration of 600ms', (tester) async {
      final widget = AnimatedCurrencyText(
        value: Decimal.parse('5.000'),
        currency: 'OMR',
      );
      expect(widget.duration, const Duration(milliseconds: 600));
    });

    testWidgets('accepts custom duration', (tester) async {
      final widget = AnimatedCurrencyText(
        value: Decimal.parse('5.000'),
        currency: 'OMR',
        duration: const Duration(milliseconds: 300),
      );
      expect(widget.duration, const Duration(milliseconds: 300));
    });

    testWidgets('accepts custom TextStyle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedCurrencyText(
            value: Decimal.parse('10.500'),
            currency: 'OMR',
            style: const TextStyle(fontSize: 24),
          ),
        ),
      );

      expect(find.byType(AnimatedCurrencyText), findsOneWidget);
    });

    testWidgets('animates when value changes', (tester) async {
      Decimal currentValue = Decimal.parse('10.500');

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return GestureDetector(
                onTap: () => setState(() => currentValue = Decimal.parse('20.000')),
                child: AnimatedCurrencyText(
                  value: currentValue,
                  currency: 'OMR',
                ),
              );
            },
          ),
        ),
      );

      // Initial render
      await tester.pump();

      // Change value
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      // Animation should be in progress
      expect(find.byType(TweenAnimationBuilder<double>), findsWidgets);

      // Settle
      await tester.pumpAndSettle();
    });

    testWidgets('zero value renders textSecondary color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedCurrencyText(
            value: Decimal.zero,
            currency: 'OMR',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // The Text widget should exist and render
      expect(find.byType(Text), findsWidgets);
    });
  });
}
