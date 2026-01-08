import 'package:decimal/decimal.dart';

class AppFormatters {
  /// Format amount for display (OMR uses 3 decimal places)
  static String formatOMR(Decimal amount) {
    return '${amount.toStringAsFixed(3)} OMR';
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
