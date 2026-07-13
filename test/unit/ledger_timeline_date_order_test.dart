import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/utils/ledger_timeline.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

final _utcAfterLocalMidnight = DateTime.utc(2026, 7, 7, 20, 30);
final _canExerciseUtcLocalRollover = !_sameCalendarDate(
  _utcAfterLocalMidnight,
  _utcAfterLocalMidnight.toLocal(),
);

bool _sameCalendarDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// #154 — Ledger day labels must match Activity (day-month order) under
/// Arabic, e.g. `19 مايو`, not the month-day `مايو 19` the manual concat
/// produced. Digits stay Western per #145.
void main() {
  setUpAll(() async {
    // Load date symbols via the REAL app localization path (#1215), not
    // intl's own `initializeDateFormatting`: flutter_localizations' generated
    // `ar` DateSymbols carry ZERODIGIT: '٠', which intl's own `ar.json` does
    // not — a pin test loading intl's bare data renders Western digits and
    // passes even when the app renders Arabic-Indic ones. Don't mix this with
    // `initializeDateFormatting` — the two loaders race for the same intl
    // global symbol map, making the winner order-dependent.
    await GlobalMaterialLocalizations.delegate.load(const Locale('ar'));
    await GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  });

  Expense expense(String id, DateTime createdAt) {
    return Expense(
      id: id,
      tripId: 'event-1',
      payerParticipantId: 'p1',
      amount: Decimal.parse('5.000'),
      scope: ExpenseScope.global,
      customSplitParticipants: const [],
      splitMode: SplitMode.equally,
      splitDistribution: const {},
      createdAt: createdAt,
    );
  }

  Settlement settlement(String id, DateTime settledAt) {
    return Settlement(
      id: id,
      tripId: 'event-1',
      payerParticipantId: 'p1',
      recipientParticipantId: 'p2',
      amount: Decimal.parse('2.000'),
      settledAt: settledAt,
    );
  }

  test('groupTimelineByDay renders day-month order with Western digits (ar)', () {
    final item = LedgerExpenseItem(expense('e1', DateTime(2026, 5, 19)));
    // `now` is several days later so the bare month-day branch is hit
    // (no "Today"/"Yesterday" prefix).
    final groups = groupTimelineByDay(
      [item],
      DateTime(2026, 5, 25),
      l10n: AppLocalizationsAr(),
    );

    expect(groups, hasLength(1));
    final label = groups.single.label;
    expect(label, contains('19 مايو')); // day-month
    expect(label, isNot(contains('مايو 19'))); // not month-day
    expect(label, contains('19')); // Western digit
    expect(label, isNot(contains('١٩'))); // never Arabic-Indic (#1215)
  });

  test('groupTimelineByDay labels today and yesterday and preserves order', () {
    final todayExpense = LedgerExpenseItem(
      expense('today', DateTime(2026, 5, 25, 18)),
    );
    final yesterdaySettlement = LedgerSettlementItem(
      settlement('yesterday', DateTime(2026, 5, 24, 9)),
    );
    final groups = groupTimelineByDay(
      [todayExpense, yesterdaySettlement],
      DateTime(2026, 5, 25, 20),
      l10n: AppLocalizationsEn(),
    );

    expect(groups, hasLength(2));
    expect(groups[0].label, startsWith('Today · '));
    expect(groups[0].dateOnly, DateTime(2026, 5, 25));
    expect(groups[0].items.single, same(todayExpense));
    expect(groups[1].label, startsWith('Yesterday · '));
    expect(groups[1].dateOnly, DateTime(2026, 5, 24));
    expect(groups[1].items.single, same(yesterdaySettlement));
    expect(yesterdaySettlement.date, DateTime(2026, 5, 24, 9));
  });

  test(
    'groupTimelineByDay buckets UTC activity timestamps by local calendar date after midnight',
    skip: !_canExerciseUtcLocalRollover,
    () {
      final localNow = _utcAfterLocalMidnight.toLocal();
      final utcExpense = LedgerExpenseItem(
        expense('after-midnight-expense', _utcAfterLocalMidnight),
      );
      final utcSettlement = LedgerSettlementItem(
        settlement('after-midnight-settlement', _utcAfterLocalMidnight),
      );

      final groups = groupTimelineByDay(
        [utcExpense, utcSettlement],
        localNow,
        l10n: AppLocalizationsEn(),
      );

      expect(groups, hasLength(1));
      expect(groups.single.label, startsWith('Today · '));
      expect(groups.single.items, containsAll([utcExpense, utcSettlement]));
    },
  );

  test('formatEventDateRange handles null, one-sided, and full ranges', () {
    final l10n = AppLocalizationsEn();

    expect(formatEventDateRange(null, null, l10n: l10n), isNull);
    expect(
      formatEventDateRange(DateTime(2026, 5, 5), null, l10n: l10n),
      'MAY 5',
    );
    expect(
      formatEventDateRange(null, DateTime(2026, 5, 8), l10n: l10n),
      'MAY 8',
    );
    expect(
      formatEventDateRange(
        DateTime(2026, 5, 5),
        DateTime(2026, 5, 8),
        l10n: l10n,
      ),
      'MAY 5 ${l10n.timelineRangeSeparator} MAY 8',
    );
  });
}
