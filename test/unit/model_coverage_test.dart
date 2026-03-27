// Coverage-gap closing tests for model classes.
//
// Targets:
//   - GroupMember.fromDoc, hashCode, toString (13 lines)
//   - GroupActivityLog.fromFirestore (string/null ts), ==, hashCode, toString (9 lines)
//   - EventModules.copyWith (2 lines)
//   - Event.copyWith, hashCode, toString (6 lines)
//   - Group.fromDoc (tested via FakeFirebaseFirestore)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';

void main() {
  // ---------------------------------------------------------------------------
  // GroupMember
  // ---------------------------------------------------------------------------

  group('GroupMember', () {
    test('fromDoc deserializes correctly from FakeFirebaseFirestore', () async {
      final fakeDb = FakeFirebaseFirestore();
      final now = Timestamp.fromDate(DateTime(2026, 1, 1));

      await fakeDb
          .collection('groups')
          .doc('grp-1')
          .collection('members')
          .doc('mem-1')
          .set({
        'userId': 'uid-alice',
        'displayName': 'Alice',
        'role': 'CREATOR',
        'isShadow': false,
        'joinedAt': now,
      });

      final doc = await fakeDb
          .collection('groups')
          .doc('grp-1')
          .collection('members')
          .doc('mem-1')
          .get();

      final member = GroupMember.fromDoc(doc, 'grp-1');

      expect(member.id, equals('mem-1'));
      expect(member.groupId, equals('grp-1'));
      expect(member.userId, equals('uid-alice'));
      expect(member.displayName, equals('Alice'));
      expect(member.role, equals('CREATOR'));
      expect(member.isShadow, isFalse);
      expect(member.joinedAt, equals(DateTime(2026, 1, 1)));
    });

    test('fromDoc with isShadow=true', () async {
      final fakeDb = FakeFirebaseFirestore();
      final now = Timestamp.fromDate(DateTime(2026, 2, 1));

      await fakeDb
          .collection('groups')
          .doc('grp-1')
          .collection('members')
          .doc('mem-shadow')
          .set({
        'userId': 'uid-bob',
        'displayName': 'Bob',
        'role': 'MEMBER',
        'isShadow': true,
        'joinedAt': now,
      });

      final doc = await fakeDb
          .collection('groups')
          .doc('grp-1')
          .collection('members')
          .doc('mem-shadow')
          .get();

      final member = GroupMember.fromDoc(doc, 'grp-1');
      expect(member.isShadow, isTrue);
      expect(member.role, equals('MEMBER'));
    });

    test('hashCode equals id.hashCode', () {
      final member = GroupMember(
        id: 'mem-1',
        groupId: 'grp-1',
        userId: 'uid-1',
        displayName: 'Alice',
        role: 'CREATOR',
        joinedAt: DateTime(2026, 1, 1),
      );
      expect(member.hashCode, equals('mem-1'.hashCode));
    });

    test('toString contains id, displayName, role', () {
      final member = GroupMember(
        id: 'mem-1',
        groupId: 'grp-1',
        userId: 'uid-1',
        displayName: 'Alice',
        role: 'CREATOR',
        joinedAt: DateTime(2026, 1, 1),
      );
      final str = member.toString();
      expect(str, contains('mem-1'));
      expect(str, contains('Alice'));
      expect(str, contains('CREATOR'));
    });

    test('== returns true for same id', () {
      final m1 = GroupMember(
        id: 'mem-x',
        groupId: 'grp-1',
        userId: 'uid-1',
        displayName: 'Alice',
        role: 'MEMBER',
        joinedAt: DateTime(2026, 1, 1),
      );
      final m2 = GroupMember(
        id: 'mem-x',
        groupId: 'grp-2',
        userId: 'uid-2',
        displayName: 'Bob',
        role: 'CREATOR',
        joinedAt: DateTime(2026, 2, 1),
      );
      expect(m1, equals(m2));
    });

    test('fromMap deserializes from SQLite row', () {
      final map = {
        'id': 'mem-2',
        'group_id': 'grp-2',
        'user_id': 'uid-charlie',
        'display_name': 'Charlie',
        'role': 'MEMBER',
        'is_shadow': 0,
        'joined_at': '2026-01-15T10:00:00.000',
      };
      final member = GroupMember.fromMap(map);
      expect(member.id, equals('mem-2'));
      expect(member.displayName, equals('Charlie'));
      expect(member.isShadow, isFalse);
    });

    test('toMap serializes to SQLite row', () {
      final member = GroupMember(
        id: 'mem-3',
        groupId: 'grp-3',
        userId: 'uid-dave',
        displayName: 'Dave',
        role: 'MEMBER',
        joinedAt: DateTime(2026, 3, 1),
      );
      final map = member.toMap();
      expect(map['id'], equals('mem-3'));
      expect(map['group_id'], equals('grp-3'));
      expect(map['display_name'], equals('Dave'));
      expect(map['role'], equals('MEMBER'));
      expect(map['is_shadow'], equals(0));
    });

    test('copyWith creates new instance with updated fields', () {
      final original = GroupMember(
        id: 'mem-4',
        groupId: 'grp-4',
        userId: 'uid-eve',
        displayName: 'Eve',
        role: 'MEMBER',
        joinedAt: DateTime(2026, 1, 1),
      );
      final updated = original.copyWith(displayName: 'Eve Updated', role: 'CREATOR');
      expect(updated.displayName, equals('Eve Updated'));
      expect(updated.role, equals('CREATOR'));
      expect(updated.id, equals('mem-4')); // unchanged
    });

    test('isCreator returns true only for CREATOR role', () {
      final creator = GroupMember(
        id: 'm1',
        groupId: 'g1',
        userId: 'u1',
        displayName: 'Alice',
        role: 'CREATOR',
        joinedAt: DateTime(2026, 1, 1),
      );
      final member = GroupMember(
        id: 'm2',
        groupId: 'g1',
        userId: 'u2',
        displayName: 'Bob',
        role: 'MEMBER',
        joinedAt: DateTime(2026, 1, 1),
      );
      expect(creator.isCreator, isTrue);
      expect(member.isCreator, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // GroupActivityLog
  // ---------------------------------------------------------------------------

  group('GroupActivityLog', () {
    test('fromFirestore with String timestamp', () {
      final data = {
        'id': 'log-1',
        'type': 'event_created',
        'actorId': 'uid-1',
        'actorName': 'Alice',
        'description': 'Created event Trip to Mountains',
        'metadata': {'eventId': 'evt-1'},
        'timestamp': '2026-01-15T10:30:00.000Z',
      };
      final log = GroupActivityLog.fromFirestore(data);
      expect(log.id, equals('log-1'));
      expect(log.type, equals('event_created'));
      expect(log.actorName, equals('Alice'));
      expect(log.description, contains('Trip'));
    });

    test('fromFirestore with null timestamp falls back to DateTime.now', () {
      final data = {
        'id': 'log-2',
        'type': 'member_joined',
        'actorId': 'uid-2',
        'actorName': null, // actorName is null — should use 'Unknown'
        'description': 'Bob joined the group',
        'timestamp': null,
      };
      final log = GroupActivityLog.fromFirestore(data);
      expect(log.actorName, equals('Unknown'));
      // timestamp falls back to DateTime.now() — just verify it's recent
      expect(
        log.timestamp.isAfter(DateTime(2020, 1, 1)),
        isTrue,
      );
    });

    test('fromFirestore with Timestamp object', () {
      final ts = Timestamp.fromDate(DateTime(2026, 3, 15));
      final data = {
        'id': 'log-3',
        'type': 'group_settlement',
        'actorId': 'uid-3',
        'actorName': 'Charlie',
        'description': 'Settlement recorded',
        'timestamp': ts,
      };
      final log = GroupActivityLog.fromFirestore(data);
      expect(log.timestamp, equals(DateTime(2026, 3, 15)));
    });

    test('hashCode equals id.hashCode', () {
      final log = GroupActivityLog(
        id: 'log-4',
        type: 'member_left',
        actorId: 'uid-4',
        actorName: 'Dave',
        description: 'Dave left',
        timestamp: DateTime(2026, 1, 1),
      );
      expect(log.hashCode, equals('log-4'.hashCode));
    });

    test('toString contains id, type, description', () {
      final log = GroupActivityLog(
        id: 'log-5',
        type: 'event_deleted',
        actorId: 'uid-5',
        actorName: 'Eve',
        description: 'Deleted camping event',
        timestamp: DateTime(2026, 1, 1),
      );
      final str = log.toString();
      expect(str, contains('log-5'));
      expect(str, contains('event_deleted'));
      expect(str, contains('Deleted camping event'));
    });

    test('== returns true for same id, false for different', () {
      final log1 = GroupActivityLog(
        id: 'log-x',
        type: 'event_created',
        actorId: 'uid-1',
        actorName: 'Alice',
        description: 'Created event',
        timestamp: DateTime(2026, 1, 1),
      );
      final log2 = GroupActivityLog(
        id: 'log-x',
        type: 'member_joined',
        actorId: 'uid-2',
        actorName: 'Bob',
        description: 'Other event',
        timestamp: DateTime(2026, 2, 1),
      );
      final log3 = GroupActivityLog(
        id: 'log-y',
        type: 'event_created',
        actorId: 'uid-1',
        actorName: 'Alice',
        description: 'Created event',
        timestamp: DateTime(2026, 1, 1),
      );
      expect(log1, equals(log2)); // same id
      expect(log1, isNot(equals(log3))); // different id
    });
  });

  // ---------------------------------------------------------------------------
  // EventModules
  // ---------------------------------------------------------------------------

  group('EventModules', () {
    test('copyWith updates only specified fields', () {
      const original = EventModules(
        ledger: true,
        gear: false,
        logistics: false,
        vault: false,
        memories: false,
      );
      final updated = original.copyWith(gear: true, memories: true);
      expect(updated.ledger, isTrue);
      expect(updated.gear, isTrue);
      expect(updated.logistics, isFalse);
      expect(updated.vault, isFalse);
      expect(updated.memories, isTrue);
    });

    test('copyWith with no args returns equivalent instance', () {
      const original = EventModules(ledger: true, gear: true);
      final copy = original.copyWith();
      expect(copy.ledger, equals(original.ledger));
      expect(copy.gear, equals(original.gear));
    });
  });

  // ---------------------------------------------------------------------------
  // Event model
  // ---------------------------------------------------------------------------

  group('Event model', () {
    Event _makeEvent() => Event(
          id: 'evt-1',
          name: 'Summer Trip',
          type: EventType.trip,
          groupId: 'grp-1',
          createdBy: 'uid-1',
          participantIds: const ['uid-1', 'uid-2'],
          participantNames: const {'uid-1': 'Alice', 'uid-2': 'Bob'},
          modules: const EventModules(ledger: true, gear: true),
          createdAt: DateTime(2026, 1, 1),
        );

    test('copyWith updates name', () {
      final original = _makeEvent();
      final updated = original.copyWith(name: 'Winter Trip');
      expect(updated.name, equals('Winter Trip'));
      expect(updated.id, equals('evt-1')); // unchanged
    });

    test('copyWith updates modules', () {
      final original = _makeEvent();
      final updated = original.copyWith(
        modules: const EventModules(ledger: false, vault: true),
      );
      expect(updated.modules.vault, isTrue);
      expect(updated.modules.ledger, isFalse); // explicitly set to false
    });

    test('hashCode equals id.hashCode', () {
      final event = _makeEvent();
      expect(event.hashCode, equals('evt-1'.hashCode));
    });

    test('toString contains id, name, type, groupId', () {
      final event = _makeEvent();
      final str = event.toString();
      expect(str, contains('evt-1'));
      expect(str, contains('Summer Trip'));
      expect(str, contains('trip'));
      expect(str, contains('grp-1'));
    });

    test('== returns true for same id', () {
      final e1 = _makeEvent();
      final e2 = Event(
        id: 'evt-1',
        name: 'Different Name',
        type: EventType.camping,
        groupId: 'grp-2',
        createdBy: 'uid-2',
        participantIds: const [],
        participantNames: const {},
        modules: const EventModules(),
        createdAt: DateTime(2026, 2, 1),
      );
      expect(e1, equals(e2));
    });
  });

  // ---------------------------------------------------------------------------
  // Group model
  // ---------------------------------------------------------------------------

  group('Group model', () {
    test('fromDoc deserializes from FakeFirebaseFirestore', () async {
      final fakeDb = FakeFirebaseFirestore();
      final now = Timestamp.fromDate(DateTime(2026, 1, 1));

      await fakeDb.collection('groups').doc('grp-x').set({
        'name': 'Adventure Crew',
        'inviteCode': 'ABX123',
        'createdBy': 'uid-creator',
        'memberIds': ['uid-creator', 'uid-member'],
        'currency': 'USD',
        'createdAt': now,
        'updatedAt': null,
      });

      final doc = await fakeDb.collection('groups').doc('grp-x').get();
      final group = Group.fromDoc(doc);

      expect(group.id, equals('grp-x'));
      expect(group.name, equals('Adventure Crew'));
      expect(group.inviteCode, equals('ABX123'));
      expect(group.currency, equals('USD'));
      expect(group.memberIds, hasLength(2));
      expect(group.updatedAt, isNull);
    });
  });
}
