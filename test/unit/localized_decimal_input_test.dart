import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/localized_decimal_input.dart';

void main() {
  group('normalizeLocalizedDecimalInput', () {
    test('normalizes Arabic-Indic digits and decimal separator', () {
      expect(normalizeLocalizedDecimalInput('١٢٣٫٤٥٦'), '123.456');
    });

    test('normalizes Eastern Arabic digits', () {
      expect(normalizeLocalizedDecimalInput('۱۲۳.۴۵'), '123.45');
    });

    test('clamps decimal places and drops non-numeric text', () {
      expect(
        normalizeLocalizedDecimalInput('OMR ١٢٫٣٤٥٦', decimalDigits: 3),
        '12.345',
      );
    });

    test('treats comma as decimal separator when no dot is present', () {
      expect(normalizeLocalizedDecimalInput('١٢,٥٠'), '12.50');
    });

    test('drops grouping separators when a dot decimal is present', () {
      expect(normalizeLocalizedDecimalInput('1,234.50'), '1234.50');
    });
  });

  group('LocalizedDecimalTextInputFormatter', () {
    test('normalizes localized input before it reaches the controller', () {
      const formatter = LocalizedDecimalTextInputFormatter(decimalDigits: 3);

      final value = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '١٢٫٣٤٥٦',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );

      expect(value.text, '12.345');
      expect(value.selection, const TextSelection.collapsed(offset: 6));
      expect(value.composing, TextRange.empty);
    });
  });
}
