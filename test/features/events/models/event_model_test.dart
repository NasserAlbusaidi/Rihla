import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';

Future<DocumentSnapshot> _writeAndRead(
  FakeFirebaseFirestore db,
  Map<String, dynamic> data, {
  String id = 'evt-1',
}) async {
  await db.collection('events').doc(id).set(data);
  return db.collection('events').doc(id).get();
}

void main() {
  group('EventType', () {
    test('fromString maps known values', () {
      expect(EventType.fromString('trip'), EventType.trip);
      expect(EventType.fromString('camping'), EventType.camping);
      expect(EventType.fromString('travel'), EventType.travel);
      expect(EventType.fromString('night_day_out'), EventType.nightDayOut);
      expect(EventType.fromString('custom'), EventType.custom);
    });

    test('fromString falls back to custom for unknown values', () {
      expect(EventType.fromString('bogus'), EventType.custom);
      expect(EventType.fromString(''), EventType.custom);
    });

    test('nightDayOut serializes as snake_case', () {
      expect(EventType.nightDayOut.value, 'night_day_out');
    });
  });

  group('EventModules', () {
    test('default ledger is true', () {
      const modules = EventModules();
      expect(modules.ledger, isTrue);
    });

    test('forType always returns ledger: true', () {
      for (final type in EventType.values) {
        expect(EventModules.forType(type).ledger, isTrue);
      }
    });

    test('fromMap reads explicit ledger flag', () {
      expect(EventModules.fromMap({'ledger': false}).ledger, isFalse);
      expect(EventModules.fromMap({'ledger': true}).ledger, isTrue);
    });

    test('fromMap defaults to true when ledger key missing', () {
      expect(EventModules.fromMap(const {}).ledger, isTrue);
    });

    test('fromMap silently ignores legacy keys', () {
      final modules = EventModules.fromMap({
        'ledger': true,
        'gear': true,
        'logistics': true,
        'memories': true,
        'vault': true,
      });
      expect(modules.ledger, isTrue);
    });

    test('toMap round-trips with fromMap', () {
      const original = EventModules(ledger: false);
      expect(EventModules.fromMap(original.toMap()).ledger, isFalse);
    });

    test('copyWith overrides ledger', () {
      const original = EventModules(ledger: true);
      expect(original.copyWith(ledger: false).ledger, isFalse);
      expect(original.copyWith().ledger, isTrue);
    });
  });

  group('Event.fromDoc', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    test('parses required fields and timestamp createdAt', () async {
      final snap = await _writeAndRead(db, {
        'name': 'Beach Day',
        'type': 'trip',
        'groupId': 'g1',
        'createdBy': 'uid-1',
        'participantIds': ['uid-1', 'uid-2'],
        'participantNames': {'uid-1': 'Alice', 'uid-2': 'Bob'},
        'modules': {'ledger': true},
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
        'startDate': Timestamp.fromDate(DateTime(2026, 4, 1)),
        'endDate': Timestamp.fromDate(DateTime(2026, 4, 5)),
        'isDeleted': false,
      });

      final event = Event.fromDoc(snap);

      expect(event.id, 'evt-1');
      expect(event.name, 'Beach Day');
      expect(event.type, EventType.trip);
      expect(event.groupId, 'g1');
      expect(event.createdBy, 'uid-1');
      expect(event.participantIds, ['uid-1', 'uid-2']);
      expect(event.participantNames, {'uid-1': 'Alice', 'uid-2': 'Bob'});
      expect(event.modules.ledger, isTrue);
      expect(event.createdAt, DateTime(2026, 3, 1));
      expect(event.startDate, DateTime(2026, 4, 1));
      expect(event.endDate, DateTime(2026, 4, 5));
      expect(event.isDeleted, isFalse);
      expect(event.deletedAt, isNull);
      expect(event.updatedAt, isNull);
      expect(event.description, isNull);
    });

    test('parses ISO 8601 string createdAt', () async {
      final snap = await _writeAndRead(db, {
        'name': 'X',
        'type': 'custom',
        'groupId': 'g1',
        'createdBy': 'uid-1',
        'participantIds': const <String>[],
        'participantNames': const <String, String>{},
        'modules': const {'ledger': true},
        'createdAt': '2026-03-01T12:34:56Z',
      });

      final event = Event.fromDoc(snap);
      expect(event.createdAt.toUtc(), DateTime.utc(2026, 3, 1, 12, 34, 56));
    });

    test('falls back to now() when createdAt is null', () async {
      final before = DateTime.now();
      final snap = await _writeAndRead(db, {
        'name': 'X',
        'type': 'custom',
        'groupId': 'g1',
        'createdBy': 'uid-1',
        'participantIds': const <String>[],
        'participantNames': const <String, String>{},
        'modules': const {'ledger': true},
        // createdAt intentionally omitted
      });

      final event = Event.fromDoc(snap);
      final after = DateTime.now();
      expect(
        event.createdAt.isAtSameMomentAs(before) ||
            (event.createdAt.isAfter(before) &&
                event.createdAt.isBefore(after.add(const Duration(seconds: 1)))),
        isTrue,
      );
    });

    test('parses optional deletedAt, updatedAt, description', () async {
      final snap = await _writeAndRead(db, {
        'name': 'Beach',
        'type': 'camping',
        'groupId': 'g1',
        'createdBy': 'uid-1',
        'participantIds': const <String>[],
        'participantNames': const <String, String>{},
        'modules': const {'ledger': true},
        'createdAt': '2026-03-01T00:00:00Z',
        'deletedAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 4, 15)),
        'description': 'A weekend trip',
        'isDeleted': true,
      });

      final event = Event.fromDoc(snap);
      expect(event.deletedAt, DateTime(2026, 5, 1));
      expect(event.updatedAt, DateTime(2026, 4, 15));
      expect(event.description, 'A weekend trip');
      expect(event.isDeleted, isTrue);
    });

    test('defaults type to custom when missing', () async {
      final snap = await _writeAndRead(db, {
        'name': 'X',
        'groupId': 'g1',
        'createdBy': 'uid-1',
        'participantIds': const <String>[],
        'participantNames': const <String, String>{},
        'modules': const {'ledger': true},
        'createdAt': '2026-03-01T00:00:00Z',
      });

      expect(Event.fromDoc(snap).type, EventType.custom);
    });
  });

  group('Event.toFirestoreMap', () {
    Event sample({
      DateTime? startDate,
      DateTime? endDate,
      DateTime? deletedAt,
      DateTime? updatedAt,
      String? description,
    }) =>
        Event(
          id: 'e1',
          name: 'N',
          type: EventType.trip,
          groupId: 'g1',
          createdBy: 'u1',
          participantIds: const ['u1'],
          participantNames: const {'u1': 'A'},
          modules: const EventModules(),
          startDate: startDate,
          endDate: endDate,
          deletedAt: deletedAt,
          updatedAt: updatedAt,
          description: description,
          createdAt: DateTime(2026, 3, 1),
        );

    test('serializes non-null date fields as Timestamps', () {
      final map = sample(
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 5),
        deletedAt: DateTime(2026, 4, 6),
        updatedAt: DateTime(2026, 4, 7),
      ).toFirestoreMap();

      expect(map['startDate'], isA<Timestamp>());
      expect(map['endDate'], isA<Timestamp>());
      expect(map['deletedAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());
    });

    test('serializes null date fields as null', () {
      final map = sample().toFirestoreMap();
      expect(map['startDate'], isNull);
      expect(map['endDate'], isNull);
      expect(map['deletedAt'], isNull);
      expect(map['updatedAt'], isNull);
    });

    test('createdAt is ISO 8601 string, includes server timestamp sentinel', () {
      final map = sample().toFirestoreMap();
      expect(map['createdAt'], '2026-03-01T00:00:00.000');
      expect(map['serverCreatedAt'], isA<FieldValue>());
    });

    test('serializes modules + type value + description', () {
      final map = sample(description: 'hello').toFirestoreMap();
      expect(map['type'], 'trip');
      expect(map['modules'], {'ledger': true});
      expect(map['description'], 'hello');
    });
  });

  group('Event.copyWith', () {
    Event base() => Event(
          id: 'e1',
          name: 'Old',
          type: EventType.trip,
          groupId: 'g1',
          createdBy: 'u1',
          participantIds: const ['u1'],
          participantNames: const {'u1': 'A'},
          modules: const EventModules(),
          createdAt: DateTime(2026, 3, 1),
        );

    test('overrides each field independently', () {
      final updated = base().copyWith(
        name: 'New',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 5),
        participantIds: const ['u1', 'u2'],
        participantNames: const {'u1': 'A', 'u2': 'B'},
        modules: const EventModules(ledger: false),
        isDeleted: true,
        deletedAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 4, 30),
        description: 'desc',
      );

      expect(updated.name, 'New');
      expect(updated.startDate, DateTime(2026, 4, 1));
      expect(updated.endDate, DateTime(2026, 4, 5));
      expect(updated.participantIds, ['u1', 'u2']);
      expect(updated.participantNames, {'u1': 'A', 'u2': 'B'});
      expect(updated.modules.ledger, isFalse);
      expect(updated.isDeleted, isTrue);
      expect(updated.deletedAt, DateTime(2026, 5, 1));
      expect(updated.updatedAt, DateTime(2026, 4, 30));
      expect(updated.description, 'desc');
    });

    test('preserves immutable id, type, groupId, createdBy, createdAt', () {
      final original = base();
      final updated = original.copyWith(name: 'changed');
      expect(updated.id, original.id);
      expect(updated.type, original.type);
      expect(updated.groupId, original.groupId);
      expect(updated.createdBy, original.createdBy);
      expect(updated.createdAt, original.createdAt);
    });
  });

  group('Event computed flags', () {
    Event withDates({DateTime? start, DateTime? end}) => Event(
          id: 'e1',
          name: 'N',
          type: EventType.trip,
          groupId: 'g1',
          createdBy: 'u1',
          participantIds: const ['u1'],
          participantNames: const {'u1': 'A'},
          modules: const EventModules(),
          startDate: start,
          endDate: end,
          createdAt: DateTime(2026, 3, 1),
        );

    test('isPast returns false when endDate is null', () {
      expect(withDates().isPast, isFalse);
    });

    test('isPast returns true when endDate is before now', () {
      expect(
        withDates(end: DateTime.now().subtract(const Duration(days: 1))).isPast,
        isTrue,
      );
    });

    test('isPast returns false when endDate is in the future', () {
      expect(
        withDates(end: DateTime.now().add(const Duration(days: 1))).isPast,
        isFalse,
      );
    });

    test('isOngoing requires both startDate and endDate', () {
      expect(withDates().isOngoing, isFalse);
      expect(withDates(start: DateTime(2020)).isOngoing, isFalse);
      expect(withDates(end: DateTime(2030)).isOngoing, isFalse);
    });

    test('isOngoing returns true when now is between start and end', () {
      final ongoing = withDates(
        start: DateTime.now().subtract(const Duration(days: 1)),
        end: DateTime.now().add(const Duration(days: 1)),
      );
      expect(ongoing.isOngoing, isTrue);
    });

    test('isOngoing returns false outside the window', () {
      final past = withDates(
        start: DateTime(2020, 1, 1),
        end: DateTime(2020, 1, 2),
      );
      final future = withDates(
        start: DateTime.now().add(const Duration(days: 10)),
        end: DateTime.now().add(const Duration(days: 20)),
      );
      expect(past.isOngoing, isFalse);
      expect(future.isOngoing, isFalse);
    });
  });

  group('Event equality + toString', () {
    Event with_(String id) => Event(
          id: id,
          name: 'N',
          type: EventType.trip,
          groupId: 'g1',
          createdBy: 'u1',
          participantIds: const [],
          participantNames: const {},
          modules: const EventModules(),
          createdAt: DateTime(2026, 3, 1),
        );

    test('equality is id-based', () {
      expect(with_('a') == with_('a'), isTrue);
      expect(with_('a') == with_('b'), isFalse);
      expect(with_('a').hashCode, with_('a').hashCode);
    });

    test('identical instances are equal', () {
      final e = with_('a');
      expect(e == e, isTrue);
    });

    test('toString includes id, name, type, groupId', () {
      final s = with_('abc').toString();
      expect(s, contains('abc'));
      expect(s, contains('trip'));
      expect(s, contains('g1'));
    });
  });
}
