import 'package:flutter/services.dart';

/// Normalizes decimal input from localized keyboards into ASCII text that
/// `Decimal.parse` can consume.
///
/// Arabic keyboards commonly emit Arabic-Indic digits and the Arabic decimal
/// separator. We store and parse monetary amounts in ASCII form, so input is
/// normalized at the boundary instead of making every parse site locale-aware.
String normalizeLocalizedDecimalInput(String value, {int? decimalDigits}) {
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
