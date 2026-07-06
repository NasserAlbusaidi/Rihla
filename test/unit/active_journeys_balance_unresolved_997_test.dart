import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/active_journeys_provider.dart';

// ---------------------------------------------------------------------------
// #997 — `activeJourneysProvider` used to default a loading/errored group's
// per-event nets to `{}`, so every one of that group's tickets rendered a
// false "settled" (0.000) net. This pins the fix: an unresolved balance
// facade drops the group's tickets from the strip rather than guessing zero
// — they reappear once the facade resolves.
// ---------------------------------------------------------------------------

Group _makeGroup({required String id}) => Group(
  id: id,
  name: 'Group $id',
  inviteCode: 'ABC123',
  createdBy: 'uid-user',
  memberIds: const ['uid-user'],
  createdAt: DateTime(2026),
);

Event _makeActiveEvent({required String id, required String groupId}) =>
    Event(
      id: id,
      name: 'Event $id',
      type: EventType.trip,
      groupId: groupId,
      createdBy: 'uid-user',
      participantIds: const ['uid-user'],
      participantNames: const {'uid-user': 'Nasser'},
      modules: const EventModules(),
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 1)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );

Future<void> _pump(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _make({
  required Group group,
  required Event event,
  required AsyncValue<HomeGroupBalance> balance,
}) {
  return ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWith((_) => 'uid-user'),
      userGroupsProvider.overrideWith((_) => Stream.value([group])),
      groupEventsProvider(
        group.id,
      ).overrideWith((_) => Stream.value([event])),
      homeGroupBalanceProvider(group.id).overrideWith((_) => balance),
    ],
  );
}

void main() {
  group('activeJourneysProvider balance-facade states (#997)', () {
    test(
      'a loading facade drops the group\'s tickets instead of a false-zero net',
      () async {
        final group = _makeGroup(id: 'g1');
        final event = _makeActiveEvent(id: 'e1', groupId: 'g1');

        final container = _make(
          group: group,
          event: event,
          balance: const AsyncValue.loading(),
        );
        addTearDown(container.dispose);

        container.listen(
          activeJourneysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final entries = container.read(activeJourneysProvider).valueOrNull!;
        expect(
          entries,
          isEmpty,
          reason:
              'a still-loading balance must not fabricate a settled ticket',
        );
      },
    );

    test(
      'an errored facade drops the group\'s tickets instead of a false-zero net',
      () async {
        final group = _makeGroup(id: 'g1');
        final event = _makeActiveEvent(id: 'e1', groupId: 'g1');

        final container = _make(
          group: group,
          event: event,
          balance: AsyncValue.error(Exception('denied'), StackTrace.empty),
        );
        addTearDown(container.dispose);

        container.listen(
          activeJourneysProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await _pump(container);

        final entries = container.read(activeJourneysProvider).valueOrNull!;
        expect(
          entries,
          isEmpty,
          reason: 'an unreadable balance must not fabricate a settled ticket',
        );
      },
    );

    test('a resolved facade still surfaces the ticket with its real net', () async {
      final group = _makeGroup(id: 'g1');
      final event = _makeActiveEvent(id: 'e1', groupId: 'g1');

      final container = _make(
        group: group,
        event: event,
        balance: AsyncValue.data((
          userNet: {'OMR': Decimal.parse('4.250')},
          userPerEventNet: {
            'e1': {'OMR': Decimal.parse('4.250')},
          },
          eventCount: 1,
          partial: false,
          fromAggregate: true,
        )),
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
        (currency: 'OMR', net: Decimal.parse('4.250')),
      ]);
    });
  });
}
