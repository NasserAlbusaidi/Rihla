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
          userGroupsProvider.overrideWith(
            (ref) => Stream.value(<Group>[]),
          ),
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
      expect(value.totalSpent, equals(Decimal.zero));
    });

    test('aggregates group count, event count, and total spending across groups',
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

      final g1Balances = AsyncValue<GroupBalances>.data((
        balances: [],
        totalSpent: Decimal.parse('10.000'),
        eventCount: 3,
        perEventBreakdown: {},
        memberNames: {'uid0': 'Alice'},
      ));

      final g2Balances = AsyncValue<GroupBalances>.data((
        balances: [],
        totalSpent: Decimal.parse('10.000'),
        eventCount: 3,
        perEventBreakdown: {},
        memberNames: {'uid0': 'Alice'},
      ));

      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith(
            (ref) => Stream.value([group1, group2]),
          ),
          groupEventsProvider('g1').overrideWith(
            (ref) => Stream.value(g1Events),
          ),
          groupEventsProvider('g2').overrideWith(
            (ref) => Stream.value(g2Events),
          ),
          groupBalancesProvider('g1').overrideWith(
            (ref) => g1Balances,
          ),
          groupBalancesProvider('g2').overrideWith(
            (ref) => g2Balances,
          ),
        ],
      );
      addTearDown(container.dispose);

      // Subscribe to start computation, then await the upstream StreamProviders
      container.read(profileStatsProvider);
      await container.read(userGroupsProvider.future);
      await container.read(groupEventsProvider('g1').future);
      await container.read(groupEventsProvider('g2').future);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final stats = container.read(profileStatsProvider);
      expect(stats.hasValue, isTrue);
      final value = stats.requireValue;
      expect(value.groupCount, equals(2));
      expect(value.eventCount, equals(6));
      expect(value.totalSpent, equals(Decimal.parse('20.000')));
    });
  });
}
