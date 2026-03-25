import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/money_serializer.dart';

void main() {
  group('MoneySerializer', () {
    group('OMR (3 decimal places, scale 1000)', () {
      test('toSubunits: OMR 10.500 returns 10500', () {
        final amount = Decimal.parse('10.500');
        expect(MoneySerializer.toSubunits(amount, 'OMR'), equals(10500));
      });

      test('fromSubunits: 10500 OMR returns Decimal 10.500', () {
        final result = MoneySerializer.fromSubunits(10500, 'OMR');
        expect(result, equals(Decimal.parse('10.500')));
      });

      test('round-trip OMR: toSubunits then fromSubunits returns original', () {
        final amount = Decimal.parse('10.500');
        final subunits = MoneySerializer.toSubunits(amount, 'OMR');
        final restored = MoneySerializer.fromSubunits(subunits, 'OMR');
        expect(restored, equals(amount));
      });

      test('round-trip OMR small amount: 0.001 -> 1 -> 0.001', () {
        final amount = Decimal.parse('0.001');
        final subunits = MoneySerializer.toSubunits(amount, 'OMR');
        expect(subunits, equals(1));
        final restored = MoneySerializer.fromSubunits(subunits, 'OMR');
        expect(restored, equals(amount));
      });

      test('toSubunits zero amount: 0.000 OMR returns 0', () {
        final amount = Decimal.parse('0.000');
        expect(MoneySerializer.toSubunits(amount, 'OMR'), equals(0));
      });

      test('fromSubunits zero: 0 OMR returns Decimal.zero', () {
        final result = MoneySerializer.fromSubunits(0, 'OMR');
        expect(result, equals(Decimal.zero));
      });
    });

    group('USD (2 decimal places, scale 100)', () {
      test('toSubunits: USD 9.99 returns 999', () {
        final amount = Decimal.parse('9.99');
        expect(MoneySerializer.toSubunits(amount, 'USD'), equals(999));
      });

      test('fromSubunits: 999 USD returns Decimal 9.99', () {
        final result = MoneySerializer.fromSubunits(999, 'USD');
        expect(result, equals(Decimal.parse('9.99')));
      });

      test('round-trip USD: toSubunits then fromSubunits returns original', () {
        final amount = Decimal.parse('9.99');
        final subunits = MoneySerializer.toSubunits(amount, 'USD');
        final restored = MoneySerializer.fromSubunits(subunits, 'USD');
        expect(restored, equals(amount));
      });
    });

    group('JPY (0 decimal places, scale 1)', () {
      test('toSubunits: JPY 1000 returns 1000', () {
        final amount = Decimal.parse('1000');
        expect(MoneySerializer.toSubunits(amount, 'JPY'), equals(1000));
      });

      test('fromSubunits: 1000 JPY returns Decimal 1000', () {
        final result = MoneySerializer.fromSubunits(1000, 'JPY');
        expect(result, equals(Decimal.parse('1000')));
      });
    });

    group('Case insensitivity', () {
      test('lowercase omr works same as OMR', () {
        final amount = Decimal.parse('10.500');
        expect(
          MoneySerializer.toSubunits(amount, 'omr'),
          equals(MoneySerializer.toSubunits(amount, 'OMR')),
        );
      });

      test('mixed case Usd works same as USD', () {
        final amount = Decimal.parse('9.99');
        expect(
          MoneySerializer.toSubunits(amount, 'Usd'),
          equals(MoneySerializer.toSubunits(amount, 'USD')),
        );
      });
    });

    group('Unsupported currency', () {
      test('toSubunits with XYZ throws ArgumentError', () {
        expect(
          () => MoneySerializer.toSubunits(Decimal.parse('10.00'), 'XYZ'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('fromSubunits with XYZ throws ArgumentError', () {
        expect(
          () => MoneySerializer.fromSubunits(1000, 'XYZ'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
