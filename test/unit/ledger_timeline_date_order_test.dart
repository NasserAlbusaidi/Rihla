import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/utils/ledger_timeline.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';

/// #154 — Ledger day labels must match Activity (day-month order) under
/// Arabic, e.g. `19 مايو`, not the month-day `مايو 19` the manual concat
/// produced. Digits stay Western per #145.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
  });

  test('groupTimelineByDay renders day-month order with Western digits (ar)', () {
    final item = LedgerExpenseItem(
      Expense(
        id: 'e1',
        tripId: 'event-1',
        payerParticipantId: 'p1',
        amount: Decimal.parse('5.000'),
        scope: ExpenseScope.global,
        customSplitParticipants: const [],
        splitMode: SplitMode.equally,
        splitDistribution: const {},
        createdAt: DateTime(2026, 5, 19),
      ),
    );
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
    expect(label, contains('19')); // Western digit, not ١٩
  });
}
