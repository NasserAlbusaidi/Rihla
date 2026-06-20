import 'package:flutter/services.dart';

/// Normalizes decimal input from localized keyboards into ASCII text that
/// `Decimal.parse` can consume.
///
/// Arabic keyboards commonly emit Arabic-Indic digits and the Arabic decimal
/// separator. We store and parse monetary amounts in ASCII form, so input is
/// normalized at the boundary instead of making every parse site locale-aware.
///
/// #530: an ambiguous European-format amount (dot grouping + comma decimal, e.g.
/// pasted `1.234,56`) must NOT be silently normalized \u2014 the dot would win as the
/// decimal and truncate `1234.56` to `1.23`, a ~1000\u00D7 money error with no error
/// shown. Owner decision (2026-06-19): reject, do not truncate. When both a
/// dot-family char (`.`/`\u066B`) and a comma are present AND the comma is the LAST
/// separator (European decimal), the raw `value` is returned UNCHANGED so it
/// fails `Decimal.parse`/`tryParse` and the caller surfaces a validation error.
/// US grouping (comma thousands, dot decimal last \u2014 e.g. `1,234.50`) is NOT
/// ambiguous and stays supported.
String normalizeLocalizedDecimalInput(String value, {int? decimalDigits}) {
  // Ambiguity guard (#530): comma is the last separator while a dot-family char
  // also appears \u2192 European decimal we refuse to guess. Returned raw to reject.
  final lastDot = value.lastIndexOf('.') > value.lastIndexOf('\u066B')
      ? value.lastIndexOf('.')
      : value.lastIndexOf('\u066B');
  final lastComma = value.lastIndexOf(',');
  if (lastComma >= 0 && lastDot >= 0 && lastComma > lastDot) {
    return value;
  }

  final hasDotDecimal = value.contains('.') || value.contains('\u066B');
  final buffer = StringBuffer();
  var hasDecimal = false;
  var fractionDigits = 0;

  for (final rune in value.runes) {
    final digit = _asciiDigitForRune(rune);
    if (digit != null) {
      if (hasDecimal && decimalDigits != null) {
        if (fractionDigits >= decimalDigits) continue;
        fractionDigits++;
      }
      buffer.write(digit);
      continue;
    }

    final char = String.fromCharCode(rune);
    final isDecimalSeparator =
        char == '.' || char == '\u066B' || (!hasDotDecimal && char == ',');
    if (!isDecimalSeparator || hasDecimal) continue;

    // A 0-decimal currency (e.g. JPY) has no fraction: mark the decimal seen so
    // any following digits are dropped by the fractionDigits guard above, but
    // never emit the '.' — otherwise the field sticks at "100." and swallows the
    // next keystroke. Truncating (not no-op'ing) the separator also prevents a
    // pasted "100.5" from concatenating into "1005", a 10x money error (#523).
    if (decimalDigits != null && decimalDigits <= 0) {
      hasDecimal = true;
      continue;
    }

    if (buffer.isEmpty) buffer.write('0');
    buffer.write('.');
    hasDecimal = true;
  }

  return buffer.toString();
}

class LocalizedDecimalTextInputFormatter extends TextInputFormatter {
  const LocalizedDecimalTextInputFormatter({this.decimalDigits});

  final int? decimalDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = normalizeLocalizedDecimalInput(
      newValue.text,
      decimalDigits: decimalDigits,
    );
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
      composing: TextRange.empty,
    );
  }
}

String? _asciiDigitForRune(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return String.fromCharCode(rune);
  if (rune >= 0x0660 && rune <= 0x0669) {
    return String.fromCharCode(0x30 + rune - 0x0660);
  }
  if (rune >= 0x06F0 && rune <= 0x06F9) {
    return String.fromCharCode(0x30 + rune - 0x06F0);
  }
  return null;
}
