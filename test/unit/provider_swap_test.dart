import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';

void main() {
  group('eventLogisticsParticipantsProvider (EVT-08 Fix #1)', () {
    final testEvent = Event(
      id: 'evt-1',
      name: 'Test Trip',
      type: EventType.trip,
      groupId: 'grp-1',
      createdBy: 'uid-alice',
      participantIds: const ['uid-alice', 'uid-bob', 'uid-charlie'],
      participantNames: const {
        'uid-alice': 'Alice',
        'uid-bob': 'Bob',
        'uid-charlie': 'Charlie',
      },
      modules: const EventModules(),
      createdAt: DateTime(2026, 3, 15),
    );

    test('returns non-empty participant list for Firestore-only event', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final participants = container.read(
        eventLogisticsParticipantsProvider(testEvent),
      );

      expect(participants, isNotEmpty);
      expect(participants.length, 3);
    });

    test('participant displayNames match event.participantNames', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final participants = container.read(
        eventLogisticsParticipantsProvider(testEvent),
      );

      final alice = participants.firstWhere((p) => p.id == 'uid-alice');
      expect(alice.displayName, 'Alice');

      final bob = participants.firstWhere((p) => p.id == 'uid-bob');
      expect(bob.displayName, 'Bob');

      final charlie = participants.firstWhere((p) => p.id == 'uid-charlie');
      expect(charlie.displayName, 'Charlie');
    });

    test('participant count matches participantIds length', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final participants = container.read(
        eventLogisticsParticipantsProvider(testEvent),
      );

      expect(participants.length, testEvent.participantIds.length);
    });
  });
}
