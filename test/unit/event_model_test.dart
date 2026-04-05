import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_type_config.dart';

void main() {
  group('EventType', () {
    test('fromString trip returns EventType.trip', () {
      expect(EventType.fromString('trip'), equals(EventType.trip));
    });

    test('fromString night_day_out returns EventType.nightDayOut', () {
      expect(
        EventType.fromString('night_day_out'),
        equals(EventType.nightDayOut),
      );
    });

    test('fromString unknown value returns EventType.custom (fallback)', () {
      expect(EventType.fromString('unknown_type'), equals(EventType.custom));
      expect(EventType.fromString(''), equals(EventType.custom));
    });

    test('EventType.trip.value equals trip', () {
      expect(EventType.trip.value, equals('trip'));
    });

    test('EventType.nightDayOut.value equals night_day_out', () {
      expect(EventType.nightDayOut.value, equals('night_day_out'));
    });

    test('EventType has exactly 5 values', () {
      expect(EventType.values.length, equals(5));
    });

    test('fromString camping returns EventType.camping', () {
      expect(EventType.fromString('camping'), equals(EventType.camping));
    });

    test('fromString travel returns EventType.travel', () {
      expect(EventType.fromString('travel'), equals(EventType.travel));
    });

    test('fromString custom returns EventType.custom', () {
      expect(EventType.fromString('custom'), equals(EventType.custom));
    });
  });

  group('EventModules', () {
    test('forType trip has all modules true', () {
      final modules = EventModules.forType(EventType.trip);
      expect(modules.ledger, isTrue);
      expect(modules.gear, isTrue);
      expect(modules.logistics, isTrue);
      expect(modules.vault, isTrue);
      expect(modules.memories, isTrue);
    });

    test(
      'forType camping has ledger=true, gear=true, logistics=true, vault=false, memories=true',
      () {
        final modules = EventModules.forType(EventType.camping);
        expect(modules.ledger, isTrue);
        expect(modules.gear, isTrue);
        expect(modules.logistics, isTrue);
        expect(modules.vault, isFalse);
        expect(modules.memories, isTrue);
      },
    );

    test(
      'forType travel has ledger=true, gear=false, logistics=true, vault=true, memories=true',
      () {
        final modules = EventModules.forType(EventType.travel);
        expect(modules.ledger, isTrue);
        expect(modules.gear, isFalse);
        expect(modules.logistics, isTrue);
        expect(modules.vault, isTrue);
        expect(modules.memories, isTrue);
      },
    );

    test('forType nightDayOut has only ledger=true, rest false', () {
      final modules = EventModules.forType(EventType.nightDayOut);
      expect(modules.ledger, isTrue);
      expect(modules.gear, isFalse);
      expect(modules.logistics, isFalse);
      expect(modules.vault, isFalse);
      expect(modules.memories, isFalse);
    });

    test(
      'forType custom has only ledger=true, rest false (default starting state)',
      () {
        final modules = EventModules.forType(EventType.custom);
        expect(modules.ledger, isTrue);
        expect(modules.gear, isFalse);
        expect(modules.logistics, isFalse);
        expect(modules.vault, isFalse);
        expect(modules.memories, isFalse);
      },
    );

    test(
      'constructor accepts ledger=false for custom type flexibility (per D-14)',
      () {
        const modules = EventModules(ledger: false);
        expect(modules.ledger, isFalse);
        expect(modules.gear, isFalse);
      },
    );

    test(
      'fromMap preserves ledger=false (custom type scenario per D-14)',
      () {
        final modules = EventModules.fromMap({'ledger': false, 'gear': true});
        expect(modules.ledger, isFalse);
        expect(modules.gear, isTrue);
      },
    );

    test('toMap round-trips correctly', () {
      const modules = EventModules(
        ledger: true,
        gear: true,
        logistics: false,
        vault: true,
        memories: false,
      );
      final map = modules.toMap();
      expect(map['ledger'], isTrue);
      expect(map['gear'], isTrue);
      expect(map['logistics'], isFalse);
      expect(map['vault'], isTrue);
      expect(map['memories'], isFalse);

      final restored = EventModules.fromMap(map);
      expect(restored.ledger, equals(modules.ledger));
      expect(restored.gear, equals(modules.gear));
      expect(restored.logistics, equals(modules.logistics));
      expect(restored.vault, equals(modules.vault));
      expect(restored.memories, equals(modules.memories));
    });

    test('copyWith includes ledger parameter for Custom type toggling', () {
      const modules = EventModules(ledger: true, gear: false);
      final updated = modules.copyWith(ledger: false, gear: true);
      expect(updated.ledger, isFalse);
      expect(updated.gear, isTrue);
      expect(updated.logistics, isFalse);
    });
  });

  group('Event', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    Future<DocumentSnapshot> _makeDoc({
      String id = 'event-001',
      Map<String, dynamic>? overrides,
    }) async {
      final data = <String, dynamic>{
        'name': 'Test Event',
        'type': 'trip',
        'groupId': 'group-001',
        'createdBy': 'uid-001',
        'participantIds': ['uid-001', 'uid-002'],
        'participantNames': {'uid-001': 'Alice', 'uid-002': 'Bob'},
        'modules': {
          'ledger': true,
          'gear': true,
          'logistics': true,
          'vault': true,
          'memories': true,
        },
        'startDate': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'endDate': Timestamp.fromDate(DateTime(2026, 6, 10)),
        'currency': 'OMR',
        'isDeleted': false,
        'createdAt': '2026-01-01T00:00:00.000Z',
        ...?overrides,
      };
      await fakeFirestore
          .collection('groups')
          .doc('group-001')
          .collection('events')
          .doc(id)
          .set(data);
      return fakeFirestore
          .collection('groups')
          .doc('group-001')
          .collection('events')
          .doc(id)
          .get();
    }

    test('fromDoc with full data creates correct Event', () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);

      expect(event.id, equals('event-001'));
      expect(event.name, equals('Test Event'));
      expect(event.type, equals(EventType.trip));
      expect(event.groupId, equals('group-001'));
      expect(event.createdBy, equals('uid-001'));
      expect(event.participantIds, equals(['uid-001', 'uid-002']));
      expect(event.participantNames['uid-001'], equals('Alice'));
      expect(event.currency, equals('OMR'));
      expect(event.isDeleted, isFalse);
    });

    test('fromDoc with null createdAt falls back to DateTime.now()', () async {
      final doc = await _makeDoc(overrides: {'createdAt': null});
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final event = Event.fromDoc(doc);
      expect(event.createdAt.isAfter(before), isTrue);
    });

    test('toFirestoreMap produces correct map', () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);
      final map = event.toFirestoreMap();

      expect(map['name'], equals('Test Event'));
      expect(map['type'], equals('trip'));
      expect(map['groupId'], equals('group-001'));
      expect(map['modules'], isA<Map<String, dynamic>>());
      expect(map['serverCreatedAt'], isNotNull);
    });

    test('isPast returns true when endDate is in the past', () async {
      final pastEnd = DateTime.now().subtract(const Duration(days: 1));
      final doc = await _makeDoc(
        id: 'event-past',
        overrides: {
          'startDate': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 5)),
          ),
          'endDate': Timestamp.fromDate(pastEnd),
        },
      );
      final event = Event.fromDoc(doc);
      expect(event.isPast, isTrue);
    });

    test('isPast returns false when endDate is null', () async {
      final doc = await _makeDoc(
        id: 'event-no-end',
        overrides: {'startDate': null, 'endDate': null},
      );
      final event = Event.fromDoc(doc);
      expect(event.isPast, isFalse);
    });

    test('isOngoing returns true when now is between startDate and endDate',
        () async {
      final doc = await _makeDoc(
        id: 'event-ongoing',
        overrides: {
          'startDate': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 1)),
          ),
          'endDate': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 1)),
          ),
        },
      );
      final event = Event.fromDoc(doc);
      expect(event.isOngoing, isTrue);
    });

    test(
      'Event with no dates is not isPast and not isOngoing (treated as active per D-35)',
      () async {
        final doc = await _makeDoc(
          id: 'event-nodates',
          overrides: {'startDate': null, 'endDate': null},
        );
        final event = Event.fromDoc(doc);
        expect(event.isPast, isFalse);
        expect(event.isOngoing, isFalse);
      },
    );

    test('copyWith creates new instance with updated fields', () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);
      final updated = event.copyWith(name: 'Updated Name');

      expect(updated.name, equals('Updated Name'));
      expect(updated.id, equals(event.id));
      expect(updated.type, equals(event.type));
    });

    test('Event equality based on id', () async {
      final doc1 = await _makeDoc(id: 'event-eq-1');
      final doc2 = await _makeDoc(id: 'event-eq-1');
      final event1 = Event.fromDoc(doc1);
      final event2 = Event.fromDoc(doc2);
      expect(event1, equals(event2));
    });

    test('fromDoc reads participantIds as List<String>', () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);
      expect(event.participantIds, isA<List<String>>());
      expect(event.participantIds.length, equals(2));
    });

    test('fromDoc reads participantNames as Map<String, String>', () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);
      expect(event.participantNames, isA<Map<String, String>>());
      expect(event.participantNames.length, equals(2));
    });

    test('toFirestoreMap includes serverCreatedAt as FieldValue', () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);
      final map = event.toFirestoreMap();
      expect(map.containsKey('serverCreatedAt'), isTrue);
    });

    // -------------------------------------------------------------------------
    // Phase 31: description field (ECC-01)
    // -------------------------------------------------------------------------

    test('Event.description is null by default when not in Firestore doc',
        () async {
      final doc = await _makeDoc(); // no 'description' key in data
      final event = Event.fromDoc(doc);
      expect(event.description, isNull);
    });

    test('fromDoc reads description field when present in Firestore data',
        () async {
      final doc = await _makeDoc(overrides: {'description': 'A fun trip!'});
      final event = Event.fromDoc(doc);
      expect(event.description, equals('A fun trip!'));
    });

    test('toFirestoreMap includes description key (null when not set)',
        () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);
      final map = event.toFirestoreMap();
      expect(map.containsKey('description'), isTrue);
      expect(map['description'], isNull);
    });

    test('toFirestoreMap writes description value when set', () async {
      final doc = await _makeDoc(overrides: {'description': 'Beach trip!'});
      final event = Event.fromDoc(doc);
      final map = event.toFirestoreMap();
      expect(map['description'], equals('Beach trip!'));
    });

    test('copyWith propagates description field', () async {
      final doc = await _makeDoc();
      final event = Event.fromDoc(doc);
      final updated = event.copyWith(description: 'Updated description');
      expect(updated.description, equals('Updated description'));
      expect(updated.id, equals(event.id)); // other fields unchanged
    });

    test('copyWith preserves existing description when not provided', () async {
      final doc = await _makeDoc(overrides: {'description': 'Original'});
      final event = Event.fromDoc(doc);
      final updated = event.copyWith(name: 'New Name');
      expect(updated.description, equals('Original'));
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 32 Wave 0: EventTypeConfig color assertions
  // These tests define the target color values BEFORE Plan 01 implements them.
  // ---------------------------------------------------------------------------

  group('EventTypeConfig', () {
    test('camping color uses successText token hex (#047857) for WCAG compliance',
        () {
      final campingConfig = EventTypeConfig.forType(EventType.camping);
      // successText (#047857) not success (#10B981) — WCAG 4.56:1 on white
      // const map cannot reference ThemeExtension fields; hex inline
      expect(campingConfig.color, equals(const Color(0xFF047857)));
    });

    test('trip color uses primary token hex (#0D7B74)', () {
      final tripConfig = EventTypeConfig.forType(EventType.trip);
      expect(tripConfig.color, equals(const Color(0xFF0D7B74)));
    });

    test('custom color uses warning token hex (#F59E0B)', () {
      final customConfig = EventTypeConfig.forType(EventType.custom);
      expect(customConfig.color, equals(const Color(0xFFF59E0B)));
    });
  });
}
