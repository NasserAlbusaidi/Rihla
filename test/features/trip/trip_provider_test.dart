import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';

Event _event({
  required String id,
  required String createdBy,
  required List<String> participantIds,
  Map<String, String>? participantNames,
}) =>
    Event(
      id: id,
      name: 'N',
      type: EventType.trip,
      groupId: 'g1',
      createdBy: createdBy,
      participantIds: participantIds,
      participantNames: participantNames ??
          {for (final id in participantIds) id: 'User $id'},
      modules: const EventModules(),
      createdAt: DateTime(2026, 3, 1),
    );

void main() {
  const ref = (groupId: 'g1', eventId: 'e1');

  group('currentEventParticipantProvider', () {
    test('returns null when uid is null', () {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          eventDetailProvider(ref).overrideWith(
            (_) => Stream.value(_event(
              id: 'e1',
              createdBy: 'someone',
              participantIds: const ['someone'],
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentEventParticipantProvider(ref)), isNull);
    });

    test('returns null when event is null', () {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-1'),
          eventDetailProvider(ref).overrideWith(
            (_) => Stream<Event?>.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentEventParticipantProvider(ref)), isNull);
    });

    test('returns null when user is not in participantIds', () {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-1'),
          eventDetailProvider(ref).overrideWith(
            (_) => Stream.value(_event(
              id: 'e1',
              createdBy: 'someone-else',
              participantIds: const ['someone-else'],
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentEventParticipantProvider(ref)), isNull);
    });

    test('returns leader Participant when uid is the creator', () async {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-1'),
          eventDetailProvider(ref).overrideWith(
            (_) => Stream.value(_event(
              id: 'e1',
              createdBy: 'uid-1',
              participantIds: const ['uid-1', 'uid-2'],
              participantNames: const {'uid-1': 'Alice', 'uid-2': 'Bob'},
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Pump the stream by awaiting the eventDetailProvider future first
      await container.read(eventDetailProvider(ref).future);

      final participant =
          container.read(currentEventParticipantProvider(ref));
      expect(participant, isNotNull);
      expect(participant!.id, 'uid-1');
      expect(participant.userId, 'uid-1');
      expect(participant.tripId, 'e1');
      expect(participant.role, ParticipantRole.leader);
      expect(participant.displayName, 'Alice');
    });

    test('returns member Participant when uid is not the creator', () async {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-2'),
          eventDetailProvider(ref).overrideWith(
            (_) => Stream.value(_event(
              id: 'e1',
              createdBy: 'uid-1',
              participantIds: const ['uid-1', 'uid-2'],
              participantNames: const {'uid-1': 'Alice', 'uid-2': 'Bob'},
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(eventDetailProvider(ref).future);

      final participant =
          container.read(currentEventParticipantProvider(ref));
      expect(participant, isNotNull);
      expect(participant!.role, ParticipantRole.member);
      expect(participant.displayName, 'Bob');
    });

    test('displayName falls back to empty string when missing in map',
        () async {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-2'),
          eventDetailProvider(ref).overrideWith(
            (_) => Stream.value(_event(
              id: 'e1',
              createdBy: 'uid-1',
              participantIds: const ['uid-1', 'uid-2'],
              participantNames: const {'uid-1': 'Alice'},
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(eventDetailProvider(ref).future);

      final participant =
          container.read(currentEventParticipantProvider(ref));
      expect(participant?.displayName, '');
    });
  });
}
