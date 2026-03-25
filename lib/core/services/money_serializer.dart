import 'package:decimal/decimal.dart';

/// Converts Decimal amounts to/from integer subunits for Firestore storage.
/// OMR uses 1000 subunits (fils). USD/EUR use 100 (cents). JPY uses 1 (units).
///
/// ONLY call at the Firestore read/write boundary. All internal math uses Decimal.
class MoneySerializer {
  static const Map<String, int> _currencyScale = {
    'OMR': 1000,
    'USD': 100,
    'EUR': 100,
    'GBP': 100,
    'SAR': 100,
    'AED': 100,
    'JPY': 1,
    'KWD': 1000,
    'BHD': 1000,
    'QAR': 100,
  };

  /// Convert a Decimal amount to integer subunits for Firestore storage.
  /// e.g. OMR 10.500 -> 10500, USD 9.99 -> 999
  static int toSubunits(Decimal amount, String currency) {
    final scale = _scale(currency);
    return (amount * Decimal.fromInt(scale)).toBigInt().toInt();
  }

  /// Convert integer subunits from Firestore to a Decimal amount.
  /// e.g. OMR: 10500 -> Decimal('10.500'), USD: 999 -> Decimal('9.99')
  static Decimal fromSubunits(int subunits, String currency) {
    final scale = _scale(currency);
    return (Decimal.fromInt(subunits) / Decimal.fromInt(scale))
        .toDecimal(scaleOnInfinitePrecision: 10);
  }

  static int _scale(String currency) {
    final scale = _currencyScale[currency.toUpperCase()];
    if (scale == null) {
      throw ArgumentError('Unsupported currency: $currency');
    }
    return scale;
  }
}
