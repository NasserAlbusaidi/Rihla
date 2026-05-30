import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// Configuration for a currency (symbol and decimal places).
class CurrencyConfig {
  final String symbol;
  final int decimals;

  const CurrencyConfig({required this.symbol, required this.decimals});
}

class AppFormatters {
  /// Known currency configurations.
  static const Map<String, CurrencyConfig> currencyConfig = {
    'OMR': CurrencyConfig(symbol: 'ر.ع.', decimals: 3),
    'USD': CurrencyConfig(symbol: '\$', decimals: 2),
    'EUR': CurrencyConfig(symbol: '€', decimals: 2),
    'GBP': CurrencyConfig(symbol: '£', decimals: 2),
    'AED': CurrencyConfig(symbol: 'د.إ', decimals: 2),
    'SAR': CurrencyConfig(symbol: 'ر.س', decimals: 2),
    'QAR': CurrencyConfig(symbol: 'ر.ق', decimals: 2),
    'JPY': CurrencyConfig(symbol: '¥', decimals: 0),
    'KWD': CurrencyConfig(symbol: 'د.ك', decimals: 3),
    'BHD': CurrencyConfig(symbol: 'د.ب', decimals: 3),
  };

  /// Format amount for display (OMR uses 3 decimal places)
  static String formatOMR(Decimal amount) {
    return '${amount.toStringAsFixed(3)} OMR';
  }

  /// Format amount with the given currency, code-first (#144).
  ///
  /// One app-wide rule: `<ISO_CODE> <amount>` (e.g. `OMR 12.450`), Western
  /// digits, LTR — in every locale. The `symbol` field is intentionally NOT
  /// used for amount display: money renders in Geist Mono, which has no Arabic
  /// glyphs, so an Arabic symbol would break alignment and bidi. Precision
  /// still comes from the currency config.
  static String formatCurrency(Decimal amount, String currencyCode) {
    final config = currencyConfig[currencyCode];
    final decimals = config?.decimals ?? 3;
    return '$currencyCode ${amount.toStringAsFixed(decimals)}';
  }

  /// Format a date as "Mar 15" (short month abbreviation + day, no year).
  ///
  /// Used in GroupSettleUpScreen per-event breakdown labels (D-04).
  /// Day is not zero-padded: June 3 renders as "Jun 3", not "Jun 03".
  static String formatShortMonthDay(DateTime date, String localeTag) {
    return DateFormat.MMMd(localeTag).format(date);
  }

  /// Format date for display (Relative formatting)
  static String formatRelativeDate(DateTime date, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7 && diff.inDays > 0) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}';
    }
  }
}
