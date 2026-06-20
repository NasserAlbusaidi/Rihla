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

  /// Largest `amountFils` that survives the Dart-int64 → JS-number round trip
  /// (`Number.MAX_SAFE_INTEGER`, 2^53 - 1). Above this, a value stored as a Dart
  /// int64 reads back as a different JS `number` on the server, breaking the
  /// balance oracle's byte-for-byte parity. Mirrored by the `positiveInt` cap in
  /// `security/firestore.rules` (#528).
  static const int maxSafeSubunits = 9007199254740991;

  /// Convert a Decimal amount to integer subunits for Firestore storage.
  /// e.g. OMR 10.500 -> 10500, USD 9.99 -> 999
  static int toSubunits(Decimal amount, String currency) {
    final scale = _scale(currency);
    return (amount * Decimal.fromInt(scale)).toBigInt().toInt();
  }

  /// True if [amount] in [currency] serializes to an `amountFils` within the
  /// safe-integer range (`|subunits| <= maxSafeSubunits`). The write boundary
  /// guard for #528 — callers reject before persisting so an over-cap amount
  /// never reaches Firestore.
  ///
  /// Computed on the `BigInt` BEFORE any `.toInt()` so an over-cap amount cannot
  /// wrap to a small int mid-check (which is exactly the corruption being
  /// guarded against). Throws [ArgumentError] on an unsupported currency,
  /// consistent with [toSubunits].
  static bool fitsSafeSubunits(Decimal amount, String currency) {
    final raw = (amount * Decimal.fromInt(_scale(currency))).toBigInt();
    return raw.abs() <= BigInt.from(maxSafeSubunits);
  }

  /// Convert integer subunits from Firestore to a Decimal amount.
  /// e.g. OMR: 10500 -> Decimal('10.500'), USD: 999 -> Decimal('9.99')
  static Decimal fromSubunits(int subunits, String currency) {
    final scale = _scale(currency);
    return (Decimal.fromInt(subunits) / Decimal.fromInt(scale))
        .toDecimal(scaleOnInfinitePrecision: 10);
  }

  /// True if [currency] (case-insensitive) has a known subunit scale.
  static bool isSupported(String currency) =>
      _currencyScale.containsKey(currency.toUpperCase());

  /// The set of supported currency codes. Exposed so the canonical display
  /// order ([kSupportedCurrencies]) can be drift-guarded against this scale map.
  static Set<String> get supportedCurrencies => _currencyScale.keys.toSet();

  /// Fractional digits for [currency] (OMR→3, USD→2, JPY→0).
  ///
  /// Throws [ArgumentError] on an unsupported currency, consistent with
  /// [toSubunits]/[fromSubunits]. Callers that must not throw (e.g. balance
  /// math over untrusted Firestore data) should guard with [isSupported].
  static int fractionDigits(String currency) {
    var scale = _scale(currency); // scale is a power of ten (1, 100, 1000)
    var digits = 0;
    while (scale > 1) {
      scale ~/= 10;
      digits++;
    }
    return digits;
  }

  static int _scale(String currency) {
    final scale = _currencyScale[currency.toUpperCase()];
    if (scale == null) {
      throw ArgumentError('Unsupported currency: $currency');
    }
    return scale;
  }
}
