import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/active_journeys_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

Group _makeGroup({required String id}) {
  return Group(
    id: id,
    name: 'Group $id',
    inviteCode: 'ABC123',
    createdBy: 'uid-user',
    memberIds: const ['uid-user'],
    createdAt: DateTime(2026),
  );
}

Event _makeEvent({
  required String id,
  required String groupId,
  required DateTime startDate,
  required DateTime endDate,
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'uid-user',
    participantIds: const ['uid-user'],
    participantNames: const {'uid-user': 'Nasser'},
    modules: const EventModules(),
    startDate: startDate,
    endDate: endDate,
    createdAt: startDate,
  );
}

GroupBalances _makeGroupBalances(String eventId, Map<String, Decimal> nets) {
  return (
    balances: {
      for (final entry in nets.entries)
        entry.key: [
          UserBalance(
            participantId: 'uid-user',
            displayName: 'Nasser',
            totalPaid: Decimal.zero,
            totalOwed: Decimal.zero,
            netBalance: entry.value,
          ),
        ],
    },
    totalSpent: {for (final ccy in nets.keys) ccy: Decimal.zero},
    eventCount: 1,
    perEventBreakdown: {
      'uid-user': {eventId: nets},
    },
    memberNames: const {'uid-user': 'Nasser'},
    memberRawNames: const {'uid-user': 'Nasser'},
  );
}

Future<void> _pump(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('activeJourneysProvider', () {
    test(
      'does not aggregate balances for groups with no active events',
      () async {
        const groupId = 'old-group';
        final group = _makeGroup(id: groupId);
        final oldEvent = _makeEvent(
          id: 'old-event',
          groupId: groupId,
          startDate: DateTime(2020),
          endDate: DateTime(2020, 1, 2),
        );

        final container = ProviderContainer(
          overrides: [
            currentUserIdProvider.overrideWith((_) => 'uid-user'),
            userGroupsProvider.overrideWith((_) => Stream.value([group])),
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([oldEvent])),
            groupBalancesOnceProvider(groupId).overrideWith((_) {
              fail('inactive groups should not aggregate balances');
            }),
          ],
        );
        addTearDown(container.dispose);

        container.listen(activeJourneysProvider, (_, _) {}, fireImmediately: true);
        await _pump(container);

        expect(container.read(activeJourneysProvider).valueOrNull, isEmpty);
      },
    );

    test('uses group balances for active event user totals', () async {
      const groupId = 'active-group';
      const eventId = 'active-event';
      final group = _makeGroup(id: groupId);
      final activeEvent = _makeEvent(
        id: eventId,
        groupId: groupId,
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
      );
      final balances =
          _makeGroupBalances(eventId, {'OMR': Decimal.parse('4.250')});

      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((_) => 'uid-user'),
          userGroupsProvider.overrideWith((_) => Stream.value([group])),
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([activeEvent])),
          groupBalancesOnceProvider(
            groupId,
          ).overrideWith(
            (_) => (balances: balances, failedEventIds: const <String>{}),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(activeJourneysProvider, (_, _) {}, fireImmediately: true);
      await _pump(container);

      final entries = container.read(activeJourneysProvider).valueOrNull!;
      expect(entries, hasLength(1));
      expect(entries.single.eventId, eventId);
      expect(entries.single.nets, [
        (currency: 'OMR', net: Decimal.parse('4.250')),
      ]);
    });

    test(
      'labels an AED-only event under an OMR group AED — honest, '
      'not group.currency (#382 PR-3)',
      () async {
        const groupId = 'aed-group';
        const eventId = 'aed-event';
        final group = _makeGroup(id: groupId); // currency defaults to 'OMR'
        final activeEvent = _makeEvent(
          id: eventId,
          groupId: groupId,
          startDate: DateTime.now().subtract(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 1)),
        );
        final balances =
            _makeGroupBalances(eventId, {'AED': Decimal.parse('10.50')});

        final container = ProviderContainer(
          overrides: [
            currentUserIdProvider.overrideWith((_) => 'uid-user'),
            userGroupsProvider.overrideWith((_) => Stream.value([group])),
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([activeEvent])),
            groupBalancesOnceProvider(
              groupId,
            ).overrideWith(
              (_) => (balances: balances, failedEventIds: const <String>{}),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(
          activeJourneysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final entries = container.read(activeJourneysProvider).valueOrNull!;
        expect(entries, hasLength(1));
        expect(entries.single.nets, [
          (currency: 'AED', net: Decimal.parse('10.50')),
        ]);
      },
    );

    test(
      'renders every non-zero bucket GCC-first — '
      'OMR line before USD line (#382 PR-5)',
      () async {
        const groupId = 'multi-group';
        const eventId = 'multi-event';
        final group = _makeGroup(id: groupId);
        final activeEvent = _makeEvent(
          id: eventId,
          groupId: groupId,
          startDate: DateTime.now().subtract(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 1)),
        );
        final balances = _makeGroupBalances(eventId, {
          'USD': Decimal.parse('7.25'),
          'OMR': Decimal.parse('1.500'),
        });

        final container = ProviderContainer(
          overrides: [
            currentUserIdProvider.overrideWith((_) => 'uid-user'),
            userGroupsProvider.overrideWith((_) => Stream.value([group])),
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([activeEvent])),
            groupBalancesOnceProvider(
              groupId,
            ).overrideWith(
              (_) => (balances: balances, failedEventIds: const <String>{}),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(
          activeJourneysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final entries = container.read(activeJourneysProvider).valueOrNull!;
        expect(entries, hasLength(1));
        expect(entries.single.isSettled, isFalse);
        expect(entries.single.nets, [
          (currency: 'OMR', net: Decimal.parse('1.500')),
          (currency: 'USD', net: Decimal.parse('7.25')),
        ]);
      },
    );

    test(
      'two-currency event nets — both buckets become lines (#382 PR-5)',
      () async {
        const groupId = 'two-ccy-group';
        const eventId = 'two-ccy-event';
        final group = _makeGroup(id: groupId);
        final activeEvent = _makeEvent(
          id: eventId,
          groupId: groupId,
          startDate: DateTime.now().subtract(const Duration(days: 1)),
          endDate: DateTime.now().add(const Duration(days: 1)),
        );
        final balances = _makeGroupBalances(eventId, {
          'AED': Decimal.parse('41'),
          'OMR': Decimal.parse('1.4'),
        });

        final container = ProviderContainer(
          overrides: [
            currentUserIdProvider.overrideWith((_) => 'uid-user'),
            userGroupsProvider.overrideWith((_) => Stream.value([group])),
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([activeEvent])),
            groupBalancesOnceProvider(
              groupId,
            ).overrideWith(
              (_) => (balances: balances, failedEventIds: const <String>{}),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.listen(
          activeJourneysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final entries = container.read(activeJourneysProvider).valueOrNull!;
        expect(entries, hasLength(1));
        expect(entries.single.nets, [
          (currency: 'OMR', net: Decimal.parse('1.4')),
          (currency: 'AED', net: Decimal.parse('41')),
        ]);
      },
    );
  });
}
