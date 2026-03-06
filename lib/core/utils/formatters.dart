import 'package:decimal/decimal.dart';

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
  };

  /// Format amount for display (OMR uses 3 decimal places)
  static String formatOMR(Decimal amount) {
    return '${amount.toStringAsFixed(3)} OMR';
  }

  /// Format amount with the given currency code.
  static String formatCurrency(Decimal amount, String currencyCode) {
    final config = currencyConfig[currencyCode];
    final decimals = config?.decimals ?? 3;
    final symbol = config?.symbol ?? currencyCode;
    return '$symbol ${amount.toStringAsFixed(decimals)}';
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
