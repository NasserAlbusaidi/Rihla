import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/formatters.dart';

void main() {
  group('AppFormatters Tests', () {
    test('formatOMR: Should format with 3 decimal places', () {
      expect(AppFormatters.formatOMR(Decimal.parse('10')), '10.000 OMR');
      expect(AppFormatters.formatOMR(Decimal.parse('10.5')), '10.500 OMR');
      expect(AppFormatters.formatOMR(Decimal.parse('10.525')), '10.525 OMR');
      expect(AppFormatters.formatOMR(Decimal.parse('10.5256')), '10.526 OMR');
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
}
