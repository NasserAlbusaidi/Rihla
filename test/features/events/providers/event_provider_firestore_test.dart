import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/services/event_service.dart';

const _groupId = 'group-1';

DocumentReference<Map<String, dynamic>> _eventRef(
  FakeFirebaseFirestore db,
  String eventId,
) {
  return db
      .collection('groups')
      .doc(_groupId)
      .collection('events')
      .doc(eventId);
}

Future<void> _seedEvent(
  FakeFirebaseFirestore db, {
  required String id,
  required String name,
  required String createdAt,
  bool isDeleted = false,
  DateTime? startDate,
}) {
  return _eventRef(db, id).set({
    'groupId': _groupId,
    'name': name,
    'type': 'trip',
    'createdBy': 'uid-creator',
    'participantIds': ['uid-creator', 'uid-friend'],
    'participantNames': {'uid-creator': 'Aisha', 'uid-friend': 'Omar'},
    'modules': {'ledger': true},
    'isDeleted': isDeleted,
    'startDate': startDate == null ? null : Timestamp.fromDate(startDate),
    'createdAt': createdAt,
  });
}

ProviderContainer _container(FakeFirebaseFirestore db) {
  final container = ProviderContainer(
    overrides: [
      eventServiceProvider.overrideWithValue(EventService.withFirestore(db)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('groupEventsProvider', () {
    test(
      'reads non-deleted events through EventService and applies D-25 sort',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedEvent(
          db,
          id: 'dated-new',
          name: 'Dated new',
          createdAt: '2026-03-04T00:00:00Z',
          startDate: DateTime.utc(2026, 4, 1),
        );
        await _seedEvent(
          db,
          id: 'no-date-new',
          name: 'No date new',
          createdAt: '2026-03-03T00:00:00Z',
        );
        await _seedEvent(
          db,
          id: 'no-date-old',
          name: 'No date old',
          createdAt: '2026-03-02T00:00:00Z',
        );
        await _seedEvent(
          db,
          id: 'dated-old',
          name: 'Dated old',
          createdAt: '2026-03-01T00:00:00Z',
          startDate: DateTime.utc(2026, 3, 20),
        );
        await _seedEvent(
          db,
          id: 'deleted',
          name: 'Deleted',
          createdAt: '2026-03-05T00:00:00Z',
          isDeleted: true,
        );

        final container = _container(db);

        final events = await container.read(
          groupEventsProvider(_groupId).future,
        );

        expect(events.map((event) => event.id), [
          'no-date-new',
          'no-date-old',
          'dated-new',
          'dated-old',
        ]);
        expect(events.map((event) => event.name), isNot(contains('Deleted')));
      },
    );
  });

  group('eventDetailProvider', () {
    test('reads existing and missing events through EventService', () async {
      final db = FakeFirebaseFirestore();
      await _seedEvent(
        db,
        id: 'event-1',
        name: 'Beach Day',
        createdAt: '2026-03-01T00:00:00Z',
      );
      final container = _container(db);

      final existing = await container.read(
        eventDetailProvider((groupId: _groupId, eventId: 'event-1')).future,
      );
      final missing = await container.read(
        eventDetailProvider((groupId: _groupId, eventId: 'missing')).future,
      );

      expect(existing, isA<Event>());
      expect(existing?.id, 'event-1');
      expect(existing?.name, 'Beach Day');
      expect(missing, isNull);
    });

    test(
      'yields null for a soft-deleted event doc (#518: detail fence)',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedEvent(
          db,
          id: 'deleted-event',
          name: 'Deleted Event',
          createdAt: '2026-03-01T00:00:00Z',
          isDeleted: true,
        );
        final container = _container(db);

        final result = await container.read(
          eventDetailProvider(
            (groupId: _groupId, eventId: 'deleted-event'),
          ).future,
        );

        expect(result, isNull,
            reason: 'soft-deleted event must yield null from detail stream');
      },
    );
  });
}
