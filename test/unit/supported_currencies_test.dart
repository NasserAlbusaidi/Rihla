import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/constants/supported_currencies.dart';
import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/core/utils/formatters.dart';

void main() {
  group('kSupportedCurrencies (#261 PR-B canonical order + drift guard)', () {
    test('has no duplicates', () {
      expect(kSupportedCurrencies.toSet().length, kSupportedCurrencies.length);
    });

    test('defaults OMR first (the create-group default)', () {
      expect(kSupportedCurrencies.first, 'OMR');
    });

    test('GCC-first canonical order is exactly the 10 codes', () {
      expect(kSupportedCurrencies, const [
        'OMR',
        'AED',
        'SAR',
        'USD',
        'EUR',
        'GBP',
        'QAR',
        'KWD',
        'BHD',
        'JPY',
      ]);
    });

    test('set equals MoneySerializer.supportedCurrencies (no scale drift)', () {
      expect(kSupportedCurrencies.toSet(), MoneySerializer.supportedCurrencies);
    });

    test('set equals AppFormatters.currencyConfig keys (no decimals drift)', () {
      expect(kSupportedCurrencies.toSet(), AppFormatters.currencyConfig.keys.toSet());
    });

    test('every code is MoneySerializer-supported; junk is not', () {
      for (final code in kSupportedCurrencies) {
        expect(MoneySerializer.isSupported(code), isTrue, reason: code);
      }
      expect(MoneySerializer.isSupported('ZZZ'), isFalse);
    });
  });
}
