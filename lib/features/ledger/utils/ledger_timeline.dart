import '../models/expense_model.dart';
import '../models/settlement_model.dart';

/// Sealed union of timeline items — expense or settlement — for the
/// chronological day-grouped feed.
sealed class LedgerTimelineItem {
  DateTime get date;
}

final class LedgerExpenseItem extends LedgerTimelineItem {
  LedgerExpenseItem(this.expense);
  final Expense expense;
  @override
  DateTime get date => expense.createdAt;
}

final class LedgerSettlementItem extends LedgerTimelineItem {
  LedgerSettlementItem(this.settlement);
  final Settlement settlement;
  @override
  DateTime get date => settlement.settledAt;
}

class LedgerDayGroup {
  const LedgerDayGroup({
    required this.label,
    required this.dateOnly,
    required this.items,
  });
  final String label;
  final DateTime dateOnly;
  final List<LedgerTimelineItem> items;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Groups timeline items by calendar day (newest first within each day).
///
/// Labels: "Today · May 14", "Yesterday · May 13", "May 12".
List<LedgerDayGroup> groupTimelineByDay(
  List<LedgerTimelineItem> items,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<LedgerTimelineItem>>{};
  final dateByLabel = <String, DateTime>{};
  final order = <String>[];
  for (final item in items) {
    final ts = item.date;
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? 'Today · ${_months[ts.month - 1]} ${ts.day}'
        : diff == 1
            ? 'Yesterday · ${_months[ts.month - 1]} ${ts.day}'
            : '${_months[ts.month - 1]} ${ts.day}';
    if (!groups.containsKey(label)) {
      groups[label] = [];
      dateByLabel[label] = day;
      order.add(label);
    }
    groups[label]!.add(item);
  }
  return [
    for (final label in order)
      LedgerDayGroup(
        label: label,
        dateOnly: dateByLabel[label]!,
        items: groups[label]!,
      ),
  ];
}

/// Formats an event's optional date range as "MAY 5 — MAY 8" / "MAY 5".
String? formatEventDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return null;
  String fmt(DateTime d) => '${_months[d.month - 1].toUpperCase()} ${d.day}';
  if (start == null) return fmt(end!);
  if (end == null) return fmt(start);
  return '${fmt(start)} — ${fmt(end)}';
}
