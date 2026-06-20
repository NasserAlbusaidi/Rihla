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

    group('fractionDigits', () {
      test('OMR returns 3', () {
        expect(MoneySerializer.fractionDigits('OMR'), equals(3));
      });

      test('USD returns 2', () {
        expect(MoneySerializer.fractionDigits('USD'), equals(2));
      });

      test('JPY returns 0', () {
        expect(MoneySerializer.fractionDigits('JPY'), equals(0));
      });

      test('lowercase omr returns 3 (case-insensitive)', () {
        expect(MoneySerializer.fractionDigits('omr'), equals(3));
      });

      test('unsupported XYZ throws ArgumentError', () {
        expect(
          () => MoneySerializer.fractionDigits('XYZ'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('isSupported', () {
      test('true for OMR/USD/JPY', () {
        expect(MoneySerializer.isSupported('OMR'), isTrue);
        expect(MoneySerializer.isSupported('USD'), isTrue);
        expect(MoneySerializer.isSupported('JPY'), isTrue);
      });

      test('case-insensitive (lowercase usd)', () {
        expect(MoneySerializer.isSupported('usd'), isTrue);
      });

      test('false for unsupported XYZ', () {
        expect(MoneySerializer.isSupported('XYZ'), isFalse);
      });
    });

    // #528: amountFils must stay <= Number.MAX_SAFE_INTEGER (2^53-1). Above it, a
    // Dart int64 read back as a JS number server-side diverges, breaking the
    // oracle's byte-for-byte parity. fitsSafeSubunits is the client-side guard;
    // computed on BigInt so an over-cap amount can't wrap during the check.
    group('fitsSafeSubunits (#528 upper bound)', () {
      const cap = 9007199254740991; // 2^53 - 1

      test('maxSafeSubunits is Number.MAX_SAFE_INTEGER', () {
        expect(MoneySerializer.maxSafeSubunits, equals(cap));
      });

      // (label, amount, currency, fits) — clean / at-cap / one-over, per scale,
      // plus the currency-scale axis: the SAME major amount over-caps in a
      // high-scale currency (OMR ×1000) but fits in a low-scale one (JPY ×1).
      final cases = <List<dynamic>>[
        // clean, normal amounts
        ['OMR 10.500 clean', '10.500', 'OMR', true],
        ['USD 9.99 clean', '9.99', 'USD', true],
        ['JPY 1000 clean', '1000', 'JPY', true],
        // at the cap exactly (amount * scale == 2^53-1)
        ['OMR at cap', '9007199254740.991', 'OMR', true],
        ['USD at cap', '90071992547409.91', 'USD', true],
        ['JPY at cap', '9007199254740991', 'JPY', true],
        // one subunit over the cap (== 2^53)
        ['OMR one over', '9007199254740.992', 'OMR', false],
        ['USD one over', '90071992547409.92', 'USD', false],
        ['JPY one over', '9007199254740992', 'JPY', false],
        // currency-scale axis: 1e13 major units
        ['OMR 1e13 over (×1000=1e16)', '10000000000000', 'OMR', false],
        ['JPY 1e13 fits (×1=1e13)', '10000000000000', 'JPY', true],
      ];

      for (final c in cases) {
        final label = c[0] as String;
        final amount = Decimal.parse(c[1] as String);
        final currency = c[2] as String;
        final fits = c[3] as bool;
        test(label, () {
          expect(MoneySerializer.fitsSafeSubunits(amount, currency), fits);
        });
      }

      test('case-insensitive currency', () {
        final overOmr = Decimal.parse('9007199254740.992');
        expect(MoneySerializer.fitsSafeSubunits(overOmr, 'omr'), isFalse);
      });
    });
  });
}
