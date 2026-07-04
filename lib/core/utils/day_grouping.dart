import 'package:flutter/widgets.dart';

import '../extensions/build_context_l10n.dart';
import 'localized_dates.dart';

/// One day bucket produced by [groupByDay].
class DayGroup<T> {
  const DayGroup({required this.label, this.dateSuffix, required this.entries});

  final String label;
  final String? dateSuffix;
  final List<T> entries;
}

/// Buckets [items] into calendar-day groups relative to [now], in
/// first-seen order.
///
/// Today → label "Today" + a `Mar 15`-style date suffix. Yesterday → label
/// "Yesterday" + suffix. Any other day → the date itself as the label, no
/// suffix. Semantics mirror the richest of the three per-screen
/// `_groupByDay` variants (`group_activity_screen.dart`).
List<DayGroup<T>> groupByDay<T>(
  BuildContext context,
  List<T> items,
  DateTime now,
  DateTime Function(T) timestampOf,
) {
  final today = DateTime(now.year, now.month, now.day);
  // #634: hoist the constant l10n strings and the DateFormat out of the
  // per-item loop — constructing a DateFormat parses the ICU skeleton each
  // call, which over an unbounded list is re-paid per item on every build.
  final todayLabel = context.l10n.timelineToday;
  final yesterdayLabel = context.l10n.timelineYesterday;
  final monthDayFmt = shortMonthDayFormatter(context);
  final buckets = <String, _DayBucket<T>>{};
  final order = <String>[];
  for (final item in items) {
    final ts = timestampOf(item);
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final dateText = monthDayFmt.format(ts);
    final (label, suffix) = switch (diff) {
      0 => (todayLabel, dateText),
      1 => (yesterdayLabel, dateText),
      _ => (dateText, null),
    };
    final bucket = buckets.putIfAbsent(label, () {
      order.add(label);
      return _DayBucket<T>(suffix: suffix, entries: []);
    });
    bucket.entries.add(item);
  }
  return [
    for (final label in order)
      DayGroup<T>(
        label: label,
        dateSuffix: buckets[label]!.suffix,
        entries: buckets[label]!.entries,
      ),
  ];
}

class _DayBucket<T> {
  _DayBucket({required this.suffix, required this.entries});
  final String? suffix;
  final List<T> entries;
}
