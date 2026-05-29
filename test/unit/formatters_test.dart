import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/core/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  group('AppFormatters Tests', () {
    test('formatOMR: Should format with 3 decimal places', () {
      expect(AppFormatters.formatOMR(Decimal.parse('10')), '10.000 OMR');
      expect(AppFormatters.formatOMR(Decimal.parse('10.5')), '10.500 OMR');
      expect(AppFormatters.formatOMR(Decimal.parse('10.525')), '10.525 OMR');
      expect(AppFormatters.formatOMR(Decimal.parse('10.5256')), '10.526 OMR');
    });

    test('formatOMR: zero amount formats as 0.000 OMR', () {
      expect(AppFormatters.formatOMR(Decimal.parse('0')), '0.000 OMR');
      expect(AppFormatters.formatOMR(Decimal.zero), '0.000 OMR');
    });

    test('formatOMR: 10.5 formats as 10.500 (3 decimal places for OMR)', () {
      expect(AppFormatters.formatOMR(Decimal.parse('10.5')), '10.500 OMR');
    });

    test('formatOMR: large amounts format correctly', () {
      expect(
        AppFormatters.formatOMR(Decimal.parse('1000000.001')),
        '1000000.001 OMR',
      );
      expect(
        AppFormatters.formatOMR(Decimal.parse('999999.999')),
        '999999.999 OMR',
      );
    });

    test('formatOMR: negative amounts format with minus sign', () {
      expect(AppFormatters.formatOMR(Decimal.parse('-5.500')), '-5.500 OMR');
      expect(AppFormatters.formatOMR(Decimal.parse('-0.001')), '-0.001 OMR');
    });

    test('formatCurrency: Should format with correct symbol and decimals', () {
      expect(
        AppFormatters.formatCurrency(Decimal.parse('10'), 'OMR'),
        'ر.ع. 10.000',
      );
      expect(
        AppFormatters.formatCurrency(Decimal.parse('25.5'), 'USD'),
        '\$ 25.50',
      );
      expect(
        AppFormatters.formatCurrency(Decimal.parse('99.99'), 'EUR'),
        '€ 99.99',
      );
      expect(
        AppFormatters.formatCurrency(Decimal.parse('100'), 'AED'),
        'د.إ 100.00',
      );
    });

    test('formatCurrency: Should fallback for unknown currency', () {
      expect(
        AppFormatters.formatCurrency(Decimal.parse('50'), 'XYZ'),
        'XYZ 50.000',
      );
    });

    test('formatRelativeDate: Should return Today for same day', () {
      final now = DateTime(2023, 10, 10, 12, 0);
      final date = DateTime(2023, 10, 10, 8, 0);
      expect(AppFormatters.formatRelativeDate(date, now: now), 'Today');
    });

    test('formatRelativeDate: Should return Yesterday for previous day', () {
      final now = DateTime(2023, 10, 10, 12, 0);
      final date = DateTime(2023, 10, 9, 8, 0);
      expect(AppFormatters.formatRelativeDate(date, now: now), 'Yesterday');
    });

    test('formatRelativeDate: Should return days ago for recent dates', () {
      final now = DateTime(2023, 10, 10, 12, 0);
      final date = DateTime(2023, 10, 7, 8, 0);
      expect(AppFormatters.formatRelativeDate(date, now: now), '3 days ago');
    });

    test('formatRelativeDate: Should return dd/mm for older dates', () {
      final now = DateTime(2023, 10, 10, 12, 0);
      final date = DateTime(2023, 9, 10, 8, 0);
      expect(AppFormatters.formatRelativeDate(date, now: now), '10/9');
    });
  });

  group('formatCurrency multi-currency precision (#63)', () {
    test('JPY: 0 decimal places, yen symbol', () {
      expect(AppFormatters.formatCurrency(Decimal.parse('1234'), 'JPY'), '¥ 1234');
      // 0dp rounds the fraction away.
      expect(AppFormatters.formatCurrency(Decimal.parse('1234.4'), 'JPY'), '¥ 1234');
    });

    test('QAR: 2 decimal places, riyal symbol', () {
      expect(AppFormatters.formatCurrency(Decimal.parse('50'), 'QAR'), 'ر.ق 50.00');
    });

    test('KWD: 3 decimal places, dinar symbol', () {
      expect(AppFormatters.formatCurrency(Decimal.parse('50'), 'KWD'), 'د.ك 50.000');
    });

    test('BHD: 3 decimal places, dinar symbol', () {
      expect(AppFormatters.formatCurrency(Decimal.parse('50'), 'BHD'), 'د.ب 50.000');
    });

    test('OMR/USD unchanged (regression guard)', () {
      expect(AppFormatters.formatCurrency(Decimal.parse('10'), 'OMR'), 'ر.ع. 10.000');
      expect(AppFormatters.formatCurrency(Decimal.parse('25.5'), 'USD'), '\$ 25.50');
    });

    test('currencyConfig.decimals matches MoneySerializer.fractionDigits '
        'for every supported currency (drift guard)', () {
      const supported = [
        'OMR', 'USD', 'EUR', 'GBP', 'SAR', 'AED', 'JPY', 'KWD', 'BHD', 'QAR',
      ];
      for (final code in supported) {
        final config = AppFormatters.currencyConfig[code];
        expect(config, isNotNull, reason: '$code missing from currencyConfig');
        expect(
          config!.decimals,
          MoneySerializer.fractionDigits(code),
          reason: '$code: currencyConfig decimals (${config.decimals}) != '
              'fractionDigits (${MoneySerializer.fractionDigits(code)})',
        );
      }
    });
  });

  group('formatShortMonthDay', () {
    test('formats March 15 as "Mar 15"', () {
      expect(
        AppFormatters.formatShortMonthDay(DateTime(2026, 3, 15), 'en'),
        'Mar 15',
      );
    });

    test('formats January 1 without leading zero', () {
      expect(
        AppFormatters.formatShortMonthDay(DateTime(2026, 1, 1), 'en'),
        'Jan 1',
      );
    });

    test('formats December 31', () {
      expect(
        AppFormatters.formatShortMonthDay(DateTime(2026, 12, 31), 'en'),
        'Dec 31',
      );
    });

    test('formats single-digit day without padding', () {
      expect(
        AppFormatters.formatShortMonthDay(DateTime(2026, 6, 3), 'en'),
        'Jun 3',
      );
    });

    test('uses locale-specific month names', () {
      final english = AppFormatters.formatShortMonthDay(
        DateTime(2026, 3, 15),
        'en',
      );
      final arabic = AppFormatters.formatShortMonthDay(
        DateTime(2026, 3, 15),
        'ar',
      );

      expect(arabic, isNotEmpty);
      expect(arabic, isNot(english));
    });
  });
}
