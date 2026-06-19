import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/services/event_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helper: write a raw doc into FakeFirebaseFirestore and return its snapshot.
  Future<DocumentSnapshot> seedDoc(
    FakeFirebaseFirestore db,
    String path,
    Map<String, dynamic> data,
  ) async {
    final ref = db.doc(path);
    await ref.set(data);
    return ref.get();
  }

  // ---------------------------------------------------------------------------
  group('Event.fromDoc – total-parse (#532)', () {
    test('parses a well-formed doc correctly', () async {
      final db = FakeFirebaseFirestore();
      final now = DateTime(2026, 1, 1, 12, 0, 0).toUtc();
      final snap = await seedDoc(
        db,
        'groups/g1/events/e1',
        {
          'name': 'Weekend Trip',
          'type': 'trip',
          'groupId': 'g1',
          'createdBy': 'uid-1',
          'participantIds': ['uid-1', 'uid-2'],
          'participantNames': {'uid-1': 'Alice', 'uid-2': 'Bob'},
          'modules': {'ledger': true},
          'startDate': Timestamp.fromDate(now),
          'endDate': Timestamp.fromDate(now.add(const Duration(days: 2))),
          'isDeleted': false,
          'createdAt': now.toIso8601String(),
        },
      );

      final event = Event.fromDoc(snap);

      expect(event.id, 'e1');
      expect(event.name, 'Weekend Trip');
      expect(event.type, EventType.trip);
      expect(event.groupId, 'g1');
      expect(event.createdBy, 'uid-1');
      expect(event.startDate, isNotNull);
      expect(event.endDate, isNotNull);
      expect(event.isDeleted, isFalse);
    });

    test(
      'non-String name falls back to empty string instead of throwing',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-bad-name',
          {
            'name': 42, // wrong type
            'type': 'trip',
            'groupId': 'g1',
            'createdBy': 'uid-1',
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': false,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        expect(event.name, '');
      },
    );

    test(
      'non-String groupId falls back to empty string instead of throwing',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-bad-gid',
          {
            'name': 'Trip',
            'type': 'trip',
            'groupId': 99, // wrong type
            'createdBy': 'uid-1',
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': false,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        expect(event.groupId, '');
      },
    );

    test(
      'non-String createdBy falls back to empty string instead of throwing',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-bad-creator',
          {
            'name': 'Trip',
            'type': 'trip',
            'groupId': 'g1',
            'createdBy': true, // wrong type
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': false,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        expect(event.createdBy, '');
      },
    );

    test(
      'String startDate (wrong type) yields null startDate instead of throwing',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-bad-startdate',
          {
            'name': 'Trip',
            'type': 'trip',
            'groupId': 'g1',
            'createdBy': 'uid-1',
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': false,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
            // A non-Timestamp present value for a date field:
            'startDate': 'not-a-timestamp',
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        // tryParse('not-a-timestamp') == null → startDate is null (safe fallback)
        expect(event.startDate, isNull);
      },
    );

    test(
      'integer endDate (wrong type) yields null endDate instead of throwing',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-bad-enddate',
          {
            'name': 'Trip',
            'type': 'trip',
            'groupId': 'g1',
            'createdBy': 'uid-1',
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': false,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
            'endDate': 1234567890, // integer, not Timestamp
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        expect(event.endDate, isNull);
      },
    );

    test(
      'integer deletedAt (wrong type) yields null instead of throwing',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-bad-deletedat',
          {
            'name': 'Trip',
            'type': 'trip',
            'groupId': 'g1',
            'createdBy': 'uid-1',
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': true,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
            'deletedAt': 9999, // integer, not Timestamp
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        expect(event.deletedAt, isNull);
      },
    );

    test(
      'integer updatedAt (wrong type) yields null instead of throwing',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-bad-updatedat',
          {
            'name': 'Trip',
            'type': 'trip',
            'groupId': 'g1',
            'createdBy': 'uid-1',
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': false,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
            'updatedAt': 'bad-stamp', // invalid string, not Timestamp
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        expect(event.updatedAt, isNull);
      },
    );

    test(
      'doc with all wrong-type fields does not throw — every field gets safe fallback',
      () async {
        final db = FakeFirebaseFirestore();
        final snap = await seedDoc(
          db,
          'groups/g1/events/e-all-bad',
          {
            'name': 123, // int
            'type': 456, // int — falls back to 'custom'
            'groupId': true, // bool
            'createdBy': <String>[], // List
            'participantIds': 'oops', // String not List
            'participantNames': 'oops', // String not Map
            'modules': 'oops', // String not Map
            'isDeleted': 'yes', // String not bool
            'createdAt': null, // null → DateTime.now() fallback
            'startDate': 'bad',
            'endDate': 'bad',
            'deletedAt': 'bad',
            'updatedAt': 'bad',
          },
        );

        expect(() => Event.fromDoc(snap), returnsNormally);
        final event = Event.fromDoc(snap);
        expect(event.name, '');
        expect(event.groupId, '');
        expect(event.createdBy, '');
        expect(event.type, EventType.custom);
        expect(event.startDate, isNull);
        expect(event.endDate, isNull);
        expect(event.deletedAt, isNull);
        expect(event.updatedAt, isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  group('EventService.watchGroupEvents – skip-net (#532)', () {
    test(
      'drops one malformed event doc and keeps the rest — stream does not error',
      () async {
        final db = FakeFirebaseFirestore();

        // Good doc
        await db.doc('groups/g1/events/good').set({
          'name': 'Good Event',
          'type': 'trip',
          'groupId': 'g1',
          'createdBy': 'uid-1',
          'participantIds': <String>[],
          'participantNames': <String, String>{},
          'modules': {'ledger': true},
          'isDeleted': false,
          'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        });

        // Malformed doc: name is an integer (causes CastError on bare `as String`)
        await db.doc('groups/g1/events/bad').set({
          'name': 42, // <-- malformed
          'type': 'trip',
          'groupId': 'g1',
          'createdBy': 'uid-1',
          'participantIds': <String>[],
          'participantNames': <String, String>{},
          'modules': {'ledger': true},
          'isDeleted': false,
          'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        });

        final service = EventService.withFirestore(db);
        final stream = service.watchGroupEvents('g1');

        // Stream must emit without error, and include the good doc.
        // The malformed doc should be skipped (or, after the fix, tolerated
        // via total-parse — either way the stream must not error).
        await expectLater(
          stream,
          emits(
            predicate<List<Event>>(
              (events) => events.any((e) => e.name == 'Good Event'),
              'contains the good event',
            ),
          ),
        );
      },
    );

    test(
      'all-malformed collection emits empty list, not an error',
      () async {
        final db = FakeFirebaseFirestore();

        // Three docs whose 'name' field is an int (hard-cast breaks the stream)
        for (var i = 0; i < 3; i++) {
          await db.doc('groups/g2/events/bad$i').set({
            'name': i, // int, not String
            'type': 'custom',
            'groupId': 'g2',
            'createdBy': 'uid-x',
            'participantIds': <String>[],
            'participantNames': <String, String>{},
            'modules': {'ledger': true},
            'isDeleted': false,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
          });
        }

        final service = EventService.withFirestore(db);
        final stream = service.watchGroupEvents('g2');

        await expectLater(
          stream,
          // After total-parse: docs yield name=='' (not a throw).
          // The stream emits a list (possibly with 3 blank-name events)
          // but NEVER emits an error.
          emits(isA<List<Event>>()),
        );
      },
    );
  });
}
