import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/active_journeys_provider.dart';

const _uid = 'uid-user';

Group _makeGroup({required String id, String? name}) {
  return Group(
    id: id,
    name: name ?? 'Group $id',
    inviteCode: 'ABC123',
    createdBy: _uid,
    memberIds: const [_uid],
    createdAt: DateTime(2026),
  );
}

Event _makeEvent({
  required String id,
  required String groupId,
  DateTime? startDate,
  DateTime? endDate,
  bool isClosed = false,
  bool isDeleted = false,
  List<String> participantIds = const [_uid],
  DateTime? createdAt,
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: _uid,
    participantIds: participantIds,
    participantNames: {for (final p in participantIds) p: 'Name $p'},
    modules: const EventModules(),
    startDate: startDate,
    endDate: endDate,
    isClosed: isClosed,
    isDeleted: isDeleted,
    createdAt: createdAt ?? startDate ?? DateTime(2026),
  );
}

Future<void> _pump() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _container(List<Override> overrides) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  container.listen(addExpenseTargetsProvider, (_, _) {}, fireImmediately: true);
  return container;
}

void main() {
  group('addExpenseTargetsProvider', () {
    test('filters closed and deleted events out of active AND totalOpen',
        () async {
      final group = _makeGroup(id: 'g1');
      final open = _makeEvent(id: 'open', groupId: 'g1');
      final closed = _makeEvent(id: 'closed', groupId: 'g1', isClosed: true);
      final deleted = _makeEvent(id: 'deleted', groupId: 'g1', isDeleted: true);

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider('g1')
            .overrideWith((_) => Stream.value([open, closed, deleted])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active.map((t) => t.eventId), ['open']);
      expect(targets.totalOpen, 1);
      expect(targets.sole?.eventId, 'open');
    });

    test(
        'filters events the uid is not a participant of out of '
        'active, totalOpen and sole (Gate rd-1 P2)', () async {
      final group = _makeGroup(id: 'g1');
      final mine = _makeEvent(id: 'mine', groupId: 'g1');
      final notMine = _makeEvent(
        id: 'not-mine',
        groupId: 'g1',
        participantIds: const ['uid-other'],
      );

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider('g1')
            .overrideWith((_) => Stream.value([mine, notMine])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active.map((t) => t.eventId), ['mine']);
      expect(targets.totalOpen, 1);
      expect(targets.sole?.eventId, 'mine');
    });

    test('sorts active targets ongoing → upcoming → undated', () async {
      final now = DateTime.now();
      final group = _makeGroup(id: 'g1');
      final undated = _makeEvent(
        id: 'undated',
        groupId: 'g1',
        createdAt: now.subtract(const Duration(days: 2)),
      );
      final upcoming = _makeEvent(
        id: 'upcoming',
        groupId: 'g1',
        startDate: now.add(const Duration(days: 3)),
        endDate: now.add(const Duration(days: 5)),
      );
      final ongoing = _makeEvent(
        id: 'ongoing',
        groupId: 'g1',
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider('g1')
            .overrideWith((_) => Stream.value([undated, upcoming, ongoing])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(
        targets.active.map((t) => t.eventId),
        ['ongoing', 'upcoming', 'undated'],
      );
    });

    test(
        'an open dated event outside the active window counts toward '
        'totalOpen but not active — and can be the sole fast-path target',
        () async {
      final now = DateTime.now();
      final group = _makeGroup(id: 'g1');
      final longEnded = _makeEvent(
        id: 'long-ended',
        groupId: 'g1',
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.subtract(const Duration(days: 20)),
      );

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider('g1')
            .overrideWith((_) => Stream.value([longEnded])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active, isEmpty);
      expect(targets.totalOpen, 1);
      expect(targets.sole?.eventId, 'long-ended');
      expect(targets.sole?.groupId, 'g1');
    });

    test('sole is null when more than one open event exists', () async {
      final group = _makeGroup(id: 'g1');
      final a = _makeEvent(id: 'a', groupId: 'g1');
      final b = _makeEvent(id: 'b', groupId: 'g1');

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider('g1').overrideWith((_) => Stream.value([a, b])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.totalOpen, 2);
      expect(targets.sole, isNull);
    });

    test(
        'a still-loading group stream ⇒ allResolved false, sole null, '
        'resolved groups still listed', () async {
      final g1 = _makeGroup(id: 'g1');
      final g2 = _makeGroup(id: 'g2');
      final open = _makeEvent(id: 'open', groupId: 'g1');
      final never = StreamController<List<Event>>();
      addTearDown(never.close);

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([g1, g2])),
        groupEventsProvider('g1').overrideWith((_) => Stream.value([open])),
        groupEventsProvider('g2').overrideWith((_) => never.stream),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.allResolved, isFalse);
      expect(targets.sole, isNull);
      expect(targets.active.map((t) => t.eventId), ['open']);
      expect(targets.totalOpen, 1);
    });

    test('zero groups ⇒ empty, totalOpen 0, allResolved true', () async {
      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value(const [])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active, isEmpty);
      expect(targets.totalOpen, 0);
      expect(targets.sole, isNull);
      expect(targets.allResolved, isTrue);
    });

    test(
        'openByGroup carries ALL open targets per group — including '
        'outside-window ones — priority-sorted, omitting empty groups',
        () async {
      final now = DateTime.now();
      final g1 = _makeGroup(id: 'g1');
      final g2 = _makeGroup(id: 'g2');
      final ongoing = _makeEvent(
        id: 'ongoing',
        groupId: 'g1',
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );
      final longEnded = _makeEvent(
        id: 'long-ended',
        groupId: 'g1',
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.subtract(const Duration(days: 20)),
      );
      final closedOnly = _makeEvent(
        id: 'closed-only',
        groupId: 'g2',
        isClosed: true,
      );

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([g1, g2])),
        groupEventsProvider('g1')
            .overrideWith((_) => Stream.value([longEnded, ongoing])),
        groupEventsProvider('g2')
            .overrideWith((_) => Stream.value([closedOnly])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(
        targets.openByGroup['g1']!.map((t) => t.eventId),
        ['ongoing', 'long-ended'],
      );
      expect(targets.openByGroup.containsKey('g2'), isFalse);
      expect(targets.active.map((t) => t.eventId), ['ongoing']);
      expect(targets.totalOpen, 2);
    });

    test('carries event and group names for the sheet rows', () async {
      final group = _makeGroup(id: 'g1', name: 'Salalah Khareef');
      final open = _makeEvent(id: 'open', groupId: 'g1');

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider('g1').overrideWith((_) => Stream.value([open])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active.single.eventName, 'Event open');
      expect(targets.active.single.groupName, 'Salalah Khareef');
    });
  });

  group('AddExpenseTargets.preferred (#900)', () {
    test('null when any group stream has not resolved', () async {
      final g1 = _makeGroup(id: 'g1');
      final g2 = _makeGroup(id: 'g2');
      final open = _makeEvent(id: 'open', groupId: 'g1');
      final never = StreamController<List<Event>>();
      addTearDown(never.close);

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([g1, g2])),
        groupEventsProvider('g1').overrideWith((_) => Stream.value([open])),
        groupEventsProvider('g2').overrideWith((_) => never.stream),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.allResolved, isFalse);
      // Without the guard, `active.first` (non-empty from g1) would fire.
      expect(targets.preferred, isNull);
    });

    test('null when there are zero open targets anywhere', () async {
      final group = _makeGroup(id: 'g1');
      final closed = _makeEvent(id: 'closed', groupId: 'g1', isClosed: true);

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider('g1').overrideWith((_) => Stream.value([closed])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.preferred, isNull);
    });

    test(
        'returns the _priority-first active target when active is non-empty '
        '(fires even with 2+ open events in one group)', () async {
      final now = DateTime.now();
      final group = _makeGroup(id: 'g1');
      final undated = _makeEvent(
        id: 'undated',
        groupId: 'g1',
        createdAt: now.subtract(const Duration(days: 2)),
      );
      final ongoing = _makeEvent(
        id: 'ongoing',
        groupId: 'g1',
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider(
          'g1',
        ).overrideWith((_) => Stream.value([undated, ongoing])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active, hasLength(2));
      expect(targets.preferred?.eventId, 'ongoing');
    });

    test(
        'falls back to sole when nothing is in the active window and only '
        'one open target exists', () async {
      final now = DateTime.now();
      final group = _makeGroup(id: 'g1');
      final longEnded = _makeEvent(
        id: 'long-ended',
        groupId: 'g1',
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.subtract(const Duration(days: 20)),
      );

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([group])),
        groupEventsProvider(
          'g1',
        ).overrideWith((_) => Stream.value([longEnded])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active, isEmpty);
      expect(targets.sole?.eventId, 'long-ended');
      expect(targets.preferred?.eventId, 'long-ended');
    });

    test(
        'falls back across groups (best of each group'
        "'s own best) when nothing is in the active window and more than "
        'one open target exists', () async {
      final now = DateTime.now();
      final g1 = _makeGroup(id: 'g1');
      final g2 = _makeGroup(id: 'g2');
      // g1's own best is further from now than g2's own best.
      final farEnded = _makeEvent(
        id: 'far-ended',
        groupId: 'g1',
        startDate: now.subtract(const Duration(days: 60)),
        endDate: now.subtract(const Duration(days: 50)),
      );
      final closerEnded = _makeEvent(
        id: 'closer-ended',
        groupId: 'g2',
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.subtract(const Duration(days: 20)),
      );

      final container = _container([
        currentUserIdProvider.overrideWith((_) => _uid),
        userGroupsProvider.overrideWith((_) => Stream.value([g1, g2])),
        groupEventsProvider(
          'g1',
        ).overrideWith((_) => Stream.value([farEnded])),
        groupEventsProvider(
          'g2',
        ).overrideWith((_) => Stream.value([closerEnded])),
      ]);
      await _pump();

      final targets = container.read(addExpenseTargetsProvider).valueOrNull!;
      expect(targets.active, isEmpty);
      // Two open targets total ⇒ sole is null ⇒ falls through to the
      // cross-group best.
      expect(targets.sole, isNull);
      expect(targets.preferred?.eventId, 'closer-ended');
    });
  });
}
