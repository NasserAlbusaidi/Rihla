// Unit tests for profileStatsProvider aggregation.
//
// TDD: RED tests written first. Imports will fail until production code
// is created in Task 1.

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart';

void main() {
  group('profileStatsProvider', () {
    test('returns loading when userGroupsProvider is loading', () {
      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith(
            (ref) => const Stream<List<Group>>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final stats = container.read(profileStatsProvider);
      expect(stats.isLoading, isTrue);
    });

    test('returns zero stats when there are no groups', () async {
      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith((ref) => Stream.value(<Group>[])),
        ],
      );
      addTearDown(container.dispose);

      // Subscribe to profileStatsProvider to start computation, then wait
      // for the underlying StreamProvider to emit its first value.
      container.read(profileStatsProvider); // Start watching
      await container.read(userGroupsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final stats = container.read(profileStatsProvider);
      expect(stats.hasValue, isTrue);
      final value = stats.requireValue;
      expect(value.groupCount, equals(0));
      expect(value.eventCount, equals(0));
      expect(value.spentByCurrency, isEmpty);
    });

    test(
      'aggregates group count, event count, and total spending across groups',
      () async {
        final group1 = Group(
          id: 'g1',
          name: 'Group 1',
          inviteCode: 'ABC123',
          createdBy: 'uid0',
          memberIds: ['uid0'],
          currency: 'OMR',
          createdAt: DateTime(2026, 1, 1),
        );
        final group2 = Group(
          id: 'g2',
          name: 'Group 2',
          inviteCode: 'DEF456',
          createdBy: 'uid0',
          memberIds: ['uid0'],
          currency: 'OMR',
          createdAt: DateTime(2026, 1, 2),
        );

        Event makeEvent(String id, String gid) => Event(
          id: id,
          name: 'Event $id',
          type: EventType.custom,
          groupId: gid,
          createdBy: 'uid0',
          participantIds: ['uid0'],
          participantNames: {'uid0': 'Alice'},
          modules: EventModules.forType(EventType.custom),
          createdAt: DateTime(2026, 1, 1),
        );

        final g1Events = [
          makeEvent('e1', 'g1'),
          makeEvent('e2', 'g1'),
          makeEvent('e3', 'g1'),
        ];
        final g2Events = [
          makeEvent('e4', 'g2'),
          makeEvent('e5', 'g2'),
          makeEvent('e6', 'g2'),
        ];

        // #517: profileStatsProvider now reads the ONE-SHOT groupBalancesOnceProvider
        // (no per-event live listeners), which wraps the same GroupBalances in a
        // GroupBalancesOnce. The currency-bucket assertions are unchanged.
        final GroupBalances g1Balances = (
          balances: <String, List<UserBalance>>{},
          totalSpent: {'OMR': Decimal.parse('10.000')},
          eventCount: 3,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
          memberNames: {'uid0': 'Alice'},
          memberRawNames: <String, String>{},
        );

        final GroupBalances g2Balances = (
          balances: <String, List<UserBalance>>{},
          totalSpent: {'OMR': Decimal.parse('10.000')},
          eventCount: 3,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
          memberNames: {'uid0': 'Alice'},
          memberRawNames: <String, String>{},
        );

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value([group1, group2]),
            ),
            groupEventsProvider(
              'g1',
            ).overrideWith((ref) => Stream.value(g1Events)),
            groupEventsProvider(
              'g2',
            ).overrideWith((ref) => Stream.value(g2Events)),
            groupBalancesOnceProvider('g1').overrideWith(
              (ref) async => (balances: g1Balances, failedEventIds: <String>{}, groupSettlementsFailed: false),
            ),
            groupBalancesOnceProvider('g2').overrideWith(
              (ref) async => (balances: g2Balances, failedEventIds: <String>{}, groupSettlementsFailed: false),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Pin the chain (the autoDispose once-path disposes between microtasks
        // without a listener), then drain so the async overrides resolve.
        final sub = container.listen(profileStatsProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(userGroupsProvider.future);
        await container.read(groupEventsProvider('g1').future);
        await container.read(groupEventsProvider('g2').future);
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final stats = container.read(profileStatsProvider);
        expect(stats.hasValue, isTrue);
        final value = stats.requireValue;
        expect(value.groupCount, equals(2));
        expect(value.eventCount, equals(6));
        // Same currency DOES sum (this proves we bucket, not cross-sum):
        // two OMR groups (10 + 10) collapse into a single OMR bucket of 20.
        expect(
          value.spentByCurrency,
          equals([(currency: 'OMR', amount: Decimal.parse('20.000'))]),
        );
      },
    );

    test(
      'RED #378: does NOT sum spend across currencies (10 OMR + 10 USD != 20)',
      () async {
        final omrGroup = Group(
          id: 'g1',
          name: 'OMR Group',
          inviteCode: 'ABC123',
          createdBy: 'uid0',
          memberIds: ['uid0'],
          currency: 'OMR',
          createdAt: DateTime(2026, 1, 1),
        );
        final usdGroup = Group(
          id: 'g2',
          name: 'USD Group',
          inviteCode: 'DEF456',
          createdBy: 'uid0',
          memberIds: ['uid0'],
          currency: 'USD',
          createdAt: DateTime(2026, 1, 2),
        );

        // #382 PR-1: the spend currency now lives IN the record (the
        // totalSpent bucket key) — the provider merges by it, not group.currency.
        GroupBalances balances(Decimal spent, String currency) => (
              balances: <String, List<UserBalance>>{},
              totalSpent: {currency: spent},
              eventCount: 0,
              perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
              memberNames: {'uid0': 'Alice'},
              memberRawNames: <String, String>{},
            );

        final container = ProviderContainer(
          overrides: [
            userGroupsProvider.overrideWith(
              (ref) => Stream.value([omrGroup, usdGroup]),
            ),
            groupEventsProvider('g1').overrideWith((ref) => Stream.value([])),
            groupEventsProvider('g2').overrideWith((ref) => Stream.value([])),
            groupBalancesOnceProvider('g1').overrideWith(
              (ref) async => (
                balances: balances(Decimal.parse('10.000'), 'OMR'),
                failedEventIds: <String>{},
                groupSettlementsFailed: false,
              ),
            ),
            groupBalancesOnceProvider('g2').overrideWith(
              (ref) async => (
                balances: balances(Decimal.parse('10.00'), 'USD'),
                failedEventIds: <String>{},
                groupSettlementsFailed: false,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final sub = container.listen(profileStatsProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(userGroupsProvider.future);
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final value = container.read(profileStatsProvider).requireValue;

        // The currency-blind sum (the bug) would be Decimal '20'. The fix must
        // bucket per currency: OMR 10 and USD 10, never one combined 20.
        expect(
          value.spentByCurrency,
          equals([
            (currency: 'OMR', amount: Decimal.parse('10.000')),
            (currency: 'USD', amount: Decimal.parse('10.00')),
          ]),
        );
      },
    );
  });
}
