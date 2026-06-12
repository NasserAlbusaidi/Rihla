/// Canonical display order for the supported currencies (GCC-first).
///
/// Single source of truth for the create-group currency picker (#261 B1) and
/// the per-currency cross-group hero bucket sort (#261 B2). Must stay in sync
/// with [MoneySerializer.supportedCurrencies] and [AppFormatters.currencyConfig]
/// — `supported_currencies_test.dart` guards the three against drift.
///
/// Order is GCC-first (the de-facto order in `currencyDisplayName`'s switch and
/// the ARB key order); the scale maps in money_serializer/formatters are in
/// insertion order, NOT display order, so neither can drive a picker/bucket sort.
const List<String> kSupportedCurrencies = [
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
];

/// GCC-first display rank: the [kSupportedCurrencies] index, with unknown
/// codes after all known ones (#382 PR-1 bucket ordering).
int currencyGccRank(String code) {
  final i = kSupportedCurrencies.indexOf(code);
  return i < 0 ? kSupportedCurrencies.length : i;
}

/// Currency codes sorted GCC-first ([currencyGccRank]), ties alphabetical —
/// the canonical order for rendering per-currency buckets (#382 PR-1).
List<String> sortedGccFirst(Iterable<String> codes) {
  return codes.toList()
    ..sort((a, b) {
      final r = currencyGccRank(a).compareTo(currencyGccRank(b));
      return r != 0 ? r : a.compareTo(b);
    });
}
