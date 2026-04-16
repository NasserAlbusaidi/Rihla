import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a minimal [Group] for testing.
Group _makeGroup({required String id, required String name}) {
  return Group(
    id: id,
    name: name,
    inviteCode: 'AAAAAA',
    createdBy: 'uid-user',
    memberIds: const ['uid-user'],
    createdAt: DateTime(2025, 1, 1),
  );
}

/// Build a [GroupActivityLog] with a given timestamp.
GroupActivityLog _makeLog({
  required String id,
  required DateTime timestamp,
}) {
  return GroupActivityLog(
    id: id,
    type: 'expense_added',
    actorId: 'uid-user',
    actorName: 'User',
    description: 'Added expense',
    timestamp: timestamp,
  );
}

/// Pump the provider container until the synchronous Provider body re-evaluates.
Future<void> _pump(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // crossGroupActivityProvider
  // ---------------------------------------------------------------------------
  group('crossGroupActivityProvider', () {
    test(
      'returns empty list when no groups exist',
      () async {
        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith((_) => Stream.value([])),
          ],
        );
        addTearDown(container.dispose);

        container.listen(crossGroupActivityProvider, (_, __) {}, fireImmediately: true);
        await _pump(container);

        final result = container.read(crossGroupActivityProvider);
        expect(result, isA<AsyncData<List<CrossGroupActivityEntry>>>());
        expect(result.valueOrNull, isEmpty);
      },
    );

    test(
      'merges 2 groups activity into chronological order (newest first)',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');
        final group2 = _makeGroup(id: 'g2', name: 'Group 2');

        // g1 has an older entry, g2 has a newer entry
        final log1 = _makeLog(id: 'log-g1', timestamp: DateTime(2025, 1, 1));
        final log2 = _makeLog(id: 'log-g2', timestamp: DateTime(2025, 1, 2));

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith((_) => Stream.value([group1, group2])),
            groupActivityProvider('g1').overrideWith((_) => Stream.value([log1])),
            groupActivityProvider('g2').overrideWith((_) => Stream.value([log2])),
          ],
        );
        addTearDown(container.dispose);

        container.listen(crossGroupActivityProvider, (_, __) {}, fireImmediately: true);
        await _pump(container);

        final result = container.read(crossGroupActivityProvider);
        expect(result, isA<AsyncData<List<CrossGroupActivityEntry>>>());
        final entries = result.valueOrNull!;

        expect(entries.length, equals(2));
        // newest first: log2 (Jan 2) before log1 (Jan 1)
        expect(entries[0].log.id, equals('log-g2'));
        expect(entries[1].log.id, equals('log-g1'));
      },
    );

    test(
      'limits to 5 entries total',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');

        // 7 log entries for a single group — result must be capped at 5
        final logs = List.generate(
          7,
          (i) => _makeLog(
            id: 'log-$i',
            timestamp: DateTime(2025, 1, i + 1),
          ),
        );

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith((_) => Stream.value([group1])),
            groupActivityProvider('g1').overrideWith((_) => Stream.value(logs)),
          ],
        );
        addTearDown(container.dispose);

        container.listen(crossGroupActivityProvider, (_, __) {}, fireImmediately: true);
        await _pump(container);

        final result = container.read(crossGroupActivityProvider);
        expect(result, isA<AsyncData<List<CrossGroupActivityEntry>>>());
        expect(result.valueOrNull!.length, equals(5));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // weeklyGroupSpendingProvider
  // ---------------------------------------------------------------------------
  group('weeklyGroupSpendingProvider', () {
    test(
      'returns 7 day entries (Mon-Sun) for current week',
      () async {
        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith((_) => Stream.value([])),
          ],
        );
        addTearDown(container.dispose);

        container.listen(weeklyGroupSpendingProvider, (_, __) {}, fireImmediately: true);
        await _pump(container);

        final result = container.read(weeklyGroupSpendingProvider);
        expect(result, isA<AsyncData<List<DailySpending>>>());
        final week = result.valueOrNull!;

        // Always returns exactly 7 entries
        expect(week.length, equals(7));

        // First entry is Monday (weekday == 1)
        expect(week.first.date.weekday, equals(DateTime.monday));
        // Last entry is Sunday (weekday == 7)
        expect(week.last.date.weekday, equals(DateTime.sunday));
      },
    );

    test(
      'returns Decimal.zero for days with no expenses',
      () async {
        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith((_) => Stream.value([])),
          ],
        );
        addTearDown(container.dispose);

        container.listen(weeklyGroupSpendingProvider, (_, __) {}, fireImmediately: true);
        await _pump(container);

        final result = container.read(weeklyGroupSpendingProvider);
        expect(result, isA<AsyncData<List<DailySpending>>>());
        final week = result.valueOrNull!;

        // All amounts should be zero when no groups (hence no expenses)
        for (final day in week) {
          expect(day.amount, equals(Decimal.zero));
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // ARCH-02: weeklyGroupSpendingProvider fan-out bounded to O(G)
  // ---------------------------------------------------------------------------
  group('ARCH-02: weeklyGroupSpendingProvider does not watch eventExpensesProvider', () {
    test(
      'weeklyGroupSpendingProvider resolves via weeklyGroupExpensesProvider, not eventExpensesProvider',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');

        // Inject a known in-range expense via weeklyGroupExpensesProvider override.
        // If the provider resolves through weeklyGroupExpensesProvider (O(G)),
        // this expense will appear in the weekly total.
        // If it still fans out through eventExpensesProvider (O(G×E)),
        // the weeklyGroupExpensesProvider override would be bypassed and the
        // expense would NOT appear — the test would fail.
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final weekday = today.weekday;
        final monday = today.subtract(Duration(days: weekday - 1));
        // Use Wednesday of the current week so the date is within Mon-Sun
        final wednesday = monday.add(const Duration(days: 2));

        final testExpense = Expense(
          id: 'exp-arch02',
          tripId: 'e1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('25.000'),
          scope: ExpenseScope.global,
          createdAt: wednesday,
        );

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith((_) => Stream.value([group1])),
            // Override the per-group aggregate provider — O(G) boundary.
            weeklyGroupExpensesProvider('g1').overrideWith(
              (_) => Stream.value([testExpense]),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(weeklyGroupSpendingProvider, (_, __) {}, fireImmediately: true);
        await _pump(container);

        final result = container.read(weeklyGroupSpendingProvider);
        expect(result, isA<AsyncData<List<DailySpending>>>());
        final week = result.valueOrNull!;

        // The expense on Wednesday should appear in the weekly totals.
        final wednesdayEntry = week.firstWhere(
          (d) => d.date.weekday == DateTime.wednesday,
        );
        expect(
          wednesdayEntry.amount,
          equals(Decimal.parse('25.000')),
          reason: 'weeklyGroupSpendingProvider must source from '
              'weeklyGroupExpensesProvider, not eventExpensesProvider',
        );

        // Total across the week equals the single expense amount.
        final total = week.fold(
          Decimal.zero,
          (sum, d) => sum + d.amount,
        );
        expect(total, equals(Decimal.parse('25.000')));
      },
    );

    test(
      'weeklyGroupExpensesProvider is a StreamProvider.family keyed by groupId',
      () {
        // Structural assertion: weeklyGroupExpensesProvider must be a
        // StreamProvider.family<List<Expense>, String> — not a flat provider.
        // We verify this by checking that calling it with a groupId compiles
        // and returns a ProviderListenable.
        final provider = weeklyGroupExpensesProvider('some-group-id');
        expect(provider, isNotNull);
      },
    );
  });
}
