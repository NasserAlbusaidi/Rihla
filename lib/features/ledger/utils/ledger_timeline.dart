import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
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

/// #628: `DateFormat.MMMd` parses ICU patterns on construction, so allocating
/// one per [groupTimelineByDay] call (every ledger build / chip-tap regroup)
/// is wasted work. `DateFormat` carries no per-format mutable state, so a
/// process-lifetime cache keyed by `localeName` (its only constructor input) is
/// safe to share.
final Map<String, DateFormat> _monthDayFormatByLocale = {};

/// Groups timeline items by calendar day (newest first within each day).
///
/// Labels: "Today · May 14", "Yesterday · May 13", "May 12".
List<LedgerDayGroup> groupTimelineByDay(
  List<LedgerTimelineItem> items,
  DateTime now, {
  required AppLocalizations l10n,
}) {
  final localNow = now.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final groups = <String, List<LedgerTimelineItem>>{};
  final dateByLabel = <String, DateTime>{};
  final order = <String>[];
  // MMMd yields the locale's natural day/month order (e.g. en "May 19",
  // ar "19 مايو") — matching Activity (#154). The old MMM + manual
  // " ${ts.day}" concat forced month-day everywhere. `useNativeDigits =
  // false` enforces Western digits (DEC-5/#145): flutter_localizations'
  // generated `ar` DateSymbols carry ZERODIGIT: '٠', which intl adopts by
  // default per-locale, so without this every ar digit renders Arabic-Indic
  // (#1215).
  final monthDayFormat = _monthDayFormatByLocale.putIfAbsent(
    l10n.localeName,
    () => DateFormat.MMMd(l10n.localeName)..useNativeDigits = false,
  );
  for (final item in items) {
    final ts = item.date.toLocal();
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final monthDay = monthDayFormat.format(ts);
    final label = diff == 0
        ? '${l10n.timelineToday} · $monthDay'
        : diff == 1
        ? '${l10n.timelineYesterday} · $monthDay'
        : monthDay;
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
String? formatEventDateRange(
  DateTime? start,
  DateTime? end, {
  required AppLocalizations l10n,
}) {
  if (start == null && end == null) return null;
  final monthFormat = DateFormat.MMM(l10n.localeName);
  String fmt(DateTime d) => '${monthFormat.format(d).toUpperCase()} ${d.day}';
  if (start == null) return fmt(end!);
  if (end == null) return fmt(start);
  return '${fmt(start)} ${l10n.timelineRangeSeparator} ${fmt(end)}';
}
