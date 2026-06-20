import 'package:decimal/decimal.dart';
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

    // #523: a 0-decimal currency (JPY) has no fraction. The decimal separator
    // must never leave a stuck trailing '.' (that swallows the next digit), and
    // any fraction digits are truncated — NOT concatenated into the integer
    // part (a bare no-op separator would turn a pasted '100.5' into '1005', a
    // 10x money error).
    group('0-decimal currency (JPY, decimalDigits: 0)', () {
      test('a trailing separator is dropped, not left as "100."', () {
        expect(normalizeLocalizedDecimalInput('100.', decimalDigits: 0), '100');
      });

      test('a fraction is truncated to the integer part (not concatenated)', () {
        expect(normalizeLocalizedDecimalInput('100.5', decimalDigits: 0), '100');
        expect(
          normalizeLocalizedDecimalInput('100.567', decimalDigits: 0),
          '100',
        );
      });

      test('integer-only input is unchanged', () {
        expect(normalizeLocalizedDecimalInput('100', decimalDigits: 0), '100');
      });

      test('Arabic and comma separators are also no-fraction', () {
        expect(normalizeLocalizedDecimalInput('١٢٣٫٤', decimalDigits: 0), '123');
        expect(normalizeLocalizedDecimalInput('100,5', decimalDigits: 0), '100');
      });
    });

    test('non-zero decimalDigits and null are unaffected (no regression)', () {
      expect(normalizeLocalizedDecimalInput('100.5', decimalDigits: 2), '100.5');
      expect(normalizeLocalizedDecimalInput('100.5'), '100.5');
      expect(normalizeLocalizedDecimalInput('100.'), '100.');
    });

    // #530: an ambiguous European-format amount (dot grouping + comma decimal,
    // e.g. pasted `1.234,56`) was silently truncated to `1.23` because the dot
    // won as the decimal. Owner decision (2026-06-19): REJECT, do not truncate —
    // when both a dot-family char (`.`/`٫`) and a comma are present AND the comma
    // is the LAST separator, return the raw value unchanged so it fails parse and
    // the caller surfaces a validation error. US grouping (comma thousands, dot
    // decimal last) stays supported and is NOT rejected.
    group('#530 ambiguous mixed-separator input (reject, do not truncate)', () {
      test('European 1.234,56 is returned raw (not truncated to 1.23)', () {
        final out = normalizeLocalizedDecimalInput('1.234,56', decimalDigits: 2);
        expect(out, '1.234,56');
        expect(
          Decimal.tryParse(out),
          isNull,
          reason: 'a rejected amount must fail parse so the caller can error',
        );
      });

      test('European with no decimalDigits is also returned raw', () {
        expect(normalizeLocalizedDecimalInput('1.234,56'), '1.234,56');
      });

      test('European multi-group 1.234.567,89 is returned raw', () {
        final out = normalizeLocalizedDecimalInput('1.234.567,89');
        expect(out, '1.234.567,89');
        expect(Decimal.tryParse(out), isNull);
      });

      test('Arabic decimal ٫ followed by a comma is rejected (raw)', () {
        expect(normalizeLocalizedDecimalInput('1٫234,56'), '1٫234,56');
      });

      test('US grouping (comma thousands, dot decimal) still normalizes', () {
        // Regression guard: the comma is NOT the last separator → not ambiguous.
        expect(normalizeLocalizedDecimalInput('1,234.50'), '1234.50');
        expect(normalizeLocalizedDecimalInput('1,234,567.89'), '1234567.89');
      });

      test('single-separator input is never treated as ambiguous', () {
        expect(normalizeLocalizedDecimalInput('12,50'), '12.50');
        expect(normalizeLocalizedDecimalInput('1.5'), '1.5');
        expect(normalizeLocalizedDecimalInput('1,234'), '1.234');
      });
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
