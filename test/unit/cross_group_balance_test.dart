import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
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

/// Build a minimal [GroupBalances] record for testing.
GroupBalances _makeGroupBalances({required List<UserBalance> balances}) {
  return (
    balances: balances,
    totalSpent: Decimal.zero,
    eventCount: 0,
    perEventBreakdown: const {},
    memberNames: const {},
    memberRawNames: <String, String>{},
  );
}

/// Build a [UserBalance] for testing.
UserBalance _makeUserBalance({
  required String participantId,
  required Decimal netBalance,
}) {
  return UserBalance(
    participantId: participantId,
    displayName: 'User $participantId',
    totalPaid: Decimal.zero,
    totalOwed: Decimal.zero,
    netBalance: netBalance,
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
  // crossGroupBalanceProvider
  // ---------------------------------------------------------------------------
  group('crossGroupBalanceProvider', () {
    const uid = 'uid-user';

    test('returns AsyncValue.loading when userGroupsProvider is loading', () {
      // A stream that never emits — provider must return loading.
      final controller = StreamController<List<Group>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith((_) => controller.stream),
          currentUserIdProvider.overrideWith((_) => uid),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(crossGroupBalanceProvider);
      // Before stream emits, userGroupsProvider is loading
      expect(result, isA<AsyncLoading<CrossGroupBalance>>());
    });

    test('returns net=0 and groupCount=0 for empty groups list', () async {
      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith((_) => Stream.value([])),
          currentUserIdProvider.overrideWith((_) => uid),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        crossGroupBalanceProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _pump(container);

      final result = container.read(crossGroupBalanceProvider);
      expect(result, isA<AsyncData<CrossGroupBalance>>());
      final data = result.valueOrNull!;
      expect(data.net, equals(Decimal.zero));
      expect(data.groupCount, equals(0));
    });

    test(
      'sums positive net balance across 2 groups into a single positive Decimal',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');
        final group2 = _makeGroup(id: 'g2', name: 'Group 2');

        // uid-user has net +10 in g1 and +20 in g2 => total +30
        final balances1 = _makeGroupBalances(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('10.000'),
            ),
          ],
        );
        final balances2 = _makeGroupBalances(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('20.000'),
            ),
          ],
        );

        // Override groupBalancesProvider with actual balance data
        final container2 = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith(
              (_) => Stream.value([group1, group2]),
            ),
            currentUserIdProvider.overrideWith((_) => uid),
            groupBalancesProvider(
              'g1',
            ).overrideWith((_) => AsyncValue.data(balances1)),
            groupBalancesProvider(
              'g2',
            ).overrideWith((_) => AsyncValue.data(balances2)),
          ],
        );
        addTearDown(container2.dispose);

        container2.listen(
          crossGroupBalanceProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container2);

        final result = container2.read(crossGroupBalanceProvider);
        expect(result, isA<AsyncData<CrossGroupBalance>>());
        final data = result.valueOrNull!;
        // uid-user net: +10 + +20 = +30
        expect(data.net, equals(Decimal.parse('30.000')));
        expect(data.groupCount, equals(2));
      },
    );

    test(
      'sums mixed balances (positive + negative) into correct net',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');
        final group2 = _makeGroup(id: 'g2', name: 'Group 2');

        // uid-user has +15 in g1 and -5 in g2 => total +10
        final balances1 = _makeGroupBalances(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('15.000'),
            ),
          ],
        );
        final balances2 = _makeGroupBalances(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('-5.000'),
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith(
              (_) => Stream.value([group1, group2]),
            ),
            currentUserIdProvider.overrideWith((_) => uid),
            groupBalancesProvider(
              'g1',
            ).overrideWith((_) => AsyncValue.data(balances1)),
            groupBalancesProvider(
              'g2',
            ).overrideWith((_) => AsyncValue.data(balances2)),
          ],
        );
        addTearDown(container.dispose);

        container.listen(
          crossGroupBalanceProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final result = container.read(crossGroupBalanceProvider);
        expect(result, isA<AsyncData<CrossGroupBalance>>());
        final data = result.valueOrNull!;
        // +15 + (-5) = +10
        expect(data.net, equals(Decimal.parse('10.000')));
      },
    );

    test(
      'returns net=0 when user has no balance entries in any group',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');

        // groupBalancesProvider returns balances for OTHER users, not uid-user
        final balancesNoUser = _makeGroupBalances(
          balances: [
            _makeUserBalance(
              participantId: 'other-uid',
              netBalance: Decimal.parse('10.000'),
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith((_) => Stream.value([group1])),
            currentUserIdProvider.overrideWith((_) => uid),
            groupBalancesProvider(
              'g1',
            ).overrideWith((_) => AsyncValue.data(balancesNoUser)),
          ],
        );
        addTearDown(container.dispose);

        container.listen(
          crossGroupBalanceProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final result = container.read(crossGroupBalanceProvider);
        expect(result, isA<AsyncData<CrossGroupBalance>>());
        final data = result.valueOrNull!;
        // No entry for uid-user => net = 0
        expect(data.net, equals(Decimal.zero));
      },
    );
  });
}
