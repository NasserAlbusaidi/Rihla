import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// #261: these tests assert the SINGLE-currency cross-group math (all groups
/// here are default-OMR). The contract is now per-currency [CrossGroupBalance.
/// byCurrency]; this adapter reads "the sole currency bucket" so the existing
/// assertions keep proving the single-currency aggregation. `.single` THROWS if
/// a test ever holds >1 currency — so it can never silently re-sum across
/// currencies (the bug #261 fixes). Multi-currency bucketing is proven in
/// cross_group_currency_buckets_test.dart.
extension _SingleCurrencyAccess on CrossGroupBalance {
  CurrencyBalance? get _only => byCurrency.isEmpty ? null : byCurrency.single;
  Decimal get net => _only?.net ?? Decimal.zero;
  Decimal get owedToUser => _only?.owedToUser ?? Decimal.zero;
  Decimal get userOwes => _only?.userOwes ?? Decimal.zero;
}

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

/// Build a minimal [GroupBalancesOnce] record for testing.
GroupBalancesOnce _makeGroupBalancesOnce({required List<UserBalance> balances}) {
  return (
    balances: (
      balances: {'OMR': balances},
      totalSpent: {'OMR': Decimal.zero},
      eventCount: 0,
      perEventBreakdown: const {},
      memberNames: const {},
      memberRawNames: <String, String>{},
    ),
    failedEventIds: const <String>{},
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

/// Pump the provider container until the async once-providers settle.
Future<void> _pump(ProviderContainer container) async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Read [crossGroupHomeBalanceProvider] after settling. Returns the
/// [CrossGroupBalance] nested inside the once-wrapper.
Future<CrossGroupBalance> _readBalance(ProviderContainer container) async {
  // Pin the provider so autoDispose sources don't evict between microtasks.
  final sub = container.listen(crossGroupHomeBalanceProvider, (_, _) {},
      fireImmediately: true);
  await _pump(container);
  final once = container.read(crossGroupHomeBalanceProvider).valueOrNull;
  sub.close();
  return once?.balance ??
      const (
        byCurrency: <CurrencyBalance>[],
        groupCount: 0,
        isLoading: false,
      );
}

void main() {
  // ---------------------------------------------------------------------------
  // crossGroupHomeBalanceProvider (migrated from crossGroupBalanceProvider #466)
  // ---------------------------------------------------------------------------
  group('crossGroupHomeBalanceProvider', () {
    const uid = 'uid-user';

    // Override helpers: offline so the aggregate path is bypassed, driving the
    // one-shot path through groupBalancesOnceProvider (injectable per group).
    List<Override> baseOverrides(
      List<Group> groups,
      Map<String, GroupBalancesOnce> onceSeed,
    ) => [
      currentUserIdProvider.overrideWith((_) => uid),
      connectivityProvider.overrideWith(
        (_) => ConnectivityNotifier(
          connectivityProbe: () async => false,
          startPeriodicChecks: false,
        )..setOffline(),
      ),
      userGroupsProvider.overrideWith((_) => Stream.value(groups)),
      for (final entry in onceSeed.entries)
        groupBalancesOnceProvider(entry.key)
            .overrideWith((_) => Future.value(entry.value)),
    ];

    test('returns AsyncValue.loading when userGroupsProvider is loading', () {
      // A stream that never emits — provider must return loading.
      final controller = StreamController<List<Group>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((_) => uid),
          connectivityProvider.overrideWith(
            (_) => ConnectivityNotifier(
              connectivityProbe: () async => false,
              startPeriodicChecks: false,
            )..setOffline(),
          ),
          userGroupsProvider.overrideWith((_) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(crossGroupHomeBalanceProvider);
      // Before stream emits, userGroupsProvider is loading
      expect(result, isA<AsyncLoading<CrossGroupBalanceOnce>>());
    });

    test('returns net=0 and groupCount=0 for empty groups list', () async {
      final container = ProviderContainer(
        overrides: baseOverrides([], {}),
      );
      addTearDown(container.dispose);

      final balance = await _readBalance(container);
      expect(balance.net, equals(Decimal.zero));
      expect(balance.groupCount, equals(0));
    });

    test(
      'sums positive net balance across 2 groups into a single positive Decimal',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');
        final group2 = _makeGroup(id: 'g2', name: 'Group 2');

        // uid-user has net +10 in g1 and +20 in g2 => total +30
        final once1 = _makeGroupBalancesOnce(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('10.000'),
            ),
          ],
        );
        final once2 = _makeGroupBalancesOnce(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('20.000'),
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: baseOverrides([group1, group2], {'g1': once1, 'g2': once2}),
        );
        addTearDown(container.dispose);

        final balance = await _readBalance(container);
        // uid-user net: +10 + +20 = +30
        expect(balance.net, equals(Decimal.parse('30.000')));
        expect(balance.groupCount, equals(2));
      },
    );

    test(
      'sums mixed balances (positive + negative) into correct net',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');
        final group2 = _makeGroup(id: 'g2', name: 'Group 2');

        // uid-user has +15 in g1 and -5 in g2 => total +10
        final once1 = _makeGroupBalancesOnce(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('15.000'),
            ),
          ],
        );
        final once2 = _makeGroupBalancesOnce(
          balances: [
            _makeUserBalance(
              participantId: uid,
              netBalance: Decimal.parse('-5.000'),
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: baseOverrides([group1, group2], {'g1': once1, 'g2': once2}),
        );
        addTearDown(container.dispose);

        final balance = await _readBalance(container);
        // +15 + (-5) = +10
        expect(balance.net, equals(Decimal.parse('10.000')));
      },
    );

    test(
      'returns net=0 when user has no balance entries in any group',
      () async {
        final group1 = _makeGroup(id: 'g1', name: 'Group 1');

        // groupBalancesOnceProvider returns balances for OTHER users, not uid-user
        final onceNoUser = _makeGroupBalancesOnce(
          balances: [
            _makeUserBalance(
              participantId: 'other-uid',
              netBalance: Decimal.parse('10.000'),
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: baseOverrides([group1], {'g1': onceNoUser}),
        );
        addTearDown(container.dispose);

        final balance = await _readBalance(container);
        // No entry for uid-user => net = 0
        expect(balance.net, equals(Decimal.zero));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // crossGroupHomeBalanceProvider — owed/owes split (#110)
  //
  // The split is folded into the same fan-out that sums `net`. Invariant:
  // net == owedToUser - userOwes (exact partition of each group's netBalance).
  // ---------------------------------------------------------------------------
  group('crossGroupHomeBalanceProvider owed/owes split (#110)', () {
    const uid = 'uid-user';

    ProviderContainer containerFor(Map<String, Decimal> groupNets) {
      final groups = groupNets.keys
          .map((id) => _makeGroup(id: id, name: 'Group $id'))
          .toList();
      return ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((_) => uid),
          connectivityProvider.overrideWith(
            (_) => ConnectivityNotifier(
              connectivityProbe: () async => false,
              startPeriodicChecks: false,
            )..setOffline(),
          ),
          userGroupsProvider.overrideWith((_) => Stream.value(groups)),
          for (final entry in groupNets.entries)
            groupBalancesOnceProvider(entry.key).overrideWith(
              (_) => Future.value(
                _makeGroupBalancesOnce(
                  balances: [
                    _makeUserBalance(participantId: uid, netBalance: entry.value),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    test('all-positive groups => owedToUser sums, userOwes zero', () async {
      final container = containerFor({
        'g1': Decimal.parse('10.000'),
        'g2': Decimal.parse('20.000'),
      });
      addTearDown(container.dispose);

      final balance = await _readBalance(container);
      expect(balance.owedToUser, equals(Decimal.parse('30.000')));
      expect(balance.userOwes, equals(Decimal.zero));
      expect(balance.net, equals(balance.owedToUser - balance.userOwes));
    });

    test(
      'all-negative groups => userOwes sums |net|, owedToUser zero',
      () async {
        final container = containerFor({
          'g1': Decimal.parse('-10.000'),
          'g2': Decimal.parse('-5.000'),
        });
        addTearDown(container.dispose);

        final balance = await _readBalance(container);
        expect(balance.owedToUser, equals(Decimal.zero));
        expect(balance.userOwes, equals(Decimal.parse('15.000')));
        expect(balance.net, equals(balance.owedToUser - balance.userOwes));
      },
    );

    test('mixed groups => split partitions net (invariant holds)', () async {
      final container = containerFor({
        'g1': Decimal.parse('15.000'),
        'g2': Decimal.parse('-5.000'),
      });
      addTearDown(container.dispose);

      final balance = await _readBalance(container);
      expect(balance.owedToUser, equals(Decimal.parse('15.000')));
      expect(balance.userOwes, equals(Decimal.parse('5.000')));
      expect(balance.net, equals(Decimal.parse('10.000')));
      expect(balance.net, equals(balance.owedToUser - balance.userOwes));
    });

    test(
      'partial-loading: two resolved groups produce correct split while a '
      'third group is still loading',
      () async {
        // g1 +5, g2 -5 (net cancels to 0), g3 still loading (never-completing
        // future). The provider must stay LOADING when any group is unresolved.
        final groups = [
          _makeGroup(id: 'g1', name: 'Group 1'),
          _makeGroup(id: 'g2', name: 'Group 2'),
          _makeGroup(id: 'g3', name: 'Group 3'),
        ];
        final container = ProviderContainer(
          overrides: [
            currentUserIdProvider.overrideWith((_) => uid),
            connectivityProvider.overrideWith(
              (_) => ConnectivityNotifier(
                connectivityProbe: () async => false,
                startPeriodicChecks: false,
              )..setOffline(),
            ),
            userGroupsProvider.overrideWith((_) => Stream.value(groups)),
            groupBalancesOnceProvider('g1').overrideWith(
              (_) => Future.value(
                _makeGroupBalancesOnce(
                  balances: [
                    _makeUserBalance(
                      participantId: uid,
                      netBalance: Decimal.parse('5.000'),
                    ),
                  ],
                ),
              ),
            ),
            groupBalancesOnceProvider('g2').overrideWith(
              (_) => Future.value(
                _makeGroupBalancesOnce(
                  balances: [
                    _makeUserBalance(
                      participantId: uid,
                      netBalance: Decimal.parse('-5.000'),
                    ),
                  ],
                ),
              ),
            ),
            // g3: a never-completing future — homeGroupBalanceProvider stays loading.
            groupBalancesOnceProvider('g3').overrideWith(
              (_) => Completer<GroupBalancesOnce>().future,
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(crossGroupHomeBalanceProvider, (_, _) {},
            fireImmediately: true);
        await _pump(container);

        // crossGroupHomeBalanceProvider must stay loading while g3 is unresolved.
        final result = container.read(crossGroupHomeBalanceProvider);
        expect(result, isA<AsyncLoading<CrossGroupBalanceOnce>>());
      },
    );
  });
}
