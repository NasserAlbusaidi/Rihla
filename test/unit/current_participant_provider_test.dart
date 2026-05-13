import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';

Event _event({
  List<String> participantIds = const ['uid-payer', 'uid-debtor'],
  Map<String, String> participantNames = const {
    'uid-payer': 'Mona',
    'uid-debtor': 'Nasser',
  },
}) {
  return Event(
    id: 'event-1',
    name: 'Dinner',
    type: EventType.nightDayOut,
    groupId: 'group-1',
    createdBy: 'uid-payer',
    participantIds: participantIds,
    participantNames: participantNames,
    modules: const EventModules(),
    createdAt: DateTime(2026, 5, 12),
  );
}

Future<void> _pumpAsync() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const eventRef = (groupId: 'group-1', eventId: 'event-1');

  test(
    'currentEventParticipantProvider resolves identity from the current event',
    () async {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-payer'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((_) => Stream<Event?>.value(_event())),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        currentEventParticipantProvider(eventRef),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final participant = container.read(
        currentEventParticipantProvider(eventRef),
      );

      expect(participant, isNotNull);
      expect(participant!.id, 'uid-payer');
      expect(participant.userId, 'uid-payer');
      expect(participant.displayName, 'Mona');
      expect(participant.role, ParticipantRole.leader);
    },
  );

  test(
    'currentEventParticipantProvider returns null when uid is not in event',
    () async {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-stranger'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((_) => Stream<Event?>.value(_event())),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        currentEventParticipantProvider(eventRef),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      expect(container.read(currentEventParticipantProvider(eventRef)), isNull);
    },
  );
}
