import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/core/utils/day_grouping.dart';
import 'package:safar/core/utils/localized_dates.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _Entry {
  const _Entry(this.label, this.timestamp);
  final String label;
  final DateTime timestamp;
}

/// Captures a [BuildContext] with localization delegates wired, so
/// `groupByDay` (which reads `context.l10n` + the month/day formatter) has
/// what it needs — no theme extensions required since it never touches
/// `context.colors`/`context.spacing`.
Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('groupByDay', () {
    testWidgets('buckets today/yesterday/older and preserves first-seen order', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final now = DateTime(2026, 3, 15, 12);

      final entries = [
        _Entry('today-morning', DateTime(2026, 3, 15, 9)),
        _Entry('five-days-ago', DateTime(2026, 3, 10, 8)),
        _Entry('yesterday-late', DateTime(2026, 3, 14, 22)),
        _Entry('today-evening', DateTime(2026, 3, 15, 18)),
      ];

      final groups = groupByDay<_Entry>(
        context,
        entries,
        now,
        (e) => e.timestamp,
      );

      final todayText = formatShortMonthDay(context, DateTime(2026, 3, 15));
      final olderText = formatShortMonthDay(context, DateTime(2026, 3, 10));
      final yesterdayText = formatShortMonthDay(context, DateTime(2026, 3, 14));

      expect(groups, hasLength(3));

      // Bucket order follows first-seen order across the input list, not
      // chronological order: today (item 0), older (item 1), yesterday
      // (item 2) — even though yesterday is chronologically more recent
      // than the five-days-ago bucket.
      expect(groups[0].label, context.l10n.timelineToday);
      expect(groups[0].dateSuffix, todayText);
      expect(
        groups[0].entries.map((e) => e.label),
        ['today-morning', 'today-evening'],
      );

      expect(groups[1].label, olderText);
      expect(groups[1].dateSuffix, isNull);
      expect(groups[1].entries.map((e) => e.label), ['five-days-ago']);

      expect(groups[2].label, context.l10n.timelineYesterday);
      expect(groups[2].dateSuffix, yesterdayText);
      expect(groups[2].entries.map((e) => e.label), ['yesterday-late']);
    });

    testWidgets('returns an empty list for an empty input', (tester) async {
      final context = await _pumpContext(tester);
      final groups = groupByDay<_Entry>(
        context,
        const <_Entry>[],
        DateTime(2026, 3, 15),
        (e) => e.timestamp,
      );
      expect(groups, isEmpty);
    });
  });
}
