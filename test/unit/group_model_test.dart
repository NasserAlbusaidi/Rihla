import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';

void main() {
  group('Group model', () {
    final baseGroup = Group(
      id: 'g1',
      name: 'Road Crew',
      inviteCode: 'ABC123',
      createdBy: 'uid-001',
      memberIds: ['uid-001', 'uid-002'],
      currency: 'OMR',
      createdAt: DateTime(2026, 3, 1, 12, 0, 0),
      updatedAt: DateTime(2026, 3, 2, 8, 0, 0),
    );

    group('fromDoc / toMap serialization', () {
      test('toMap produces SQLite-compatible map with snake_case keys', () {
        final map = baseGroup.toMap();

        expect(map['id'], equals('g1'));
        expect(map['name'], equals('Road Crew'));
        expect(map['invite_code'], equals('ABC123'));
        expect(map['created_by'], equals('uid-001'));
        expect(map['currency'], equals('OMR'));
        // memberIds is JSON-encoded list per SQLite column definition
        final decoded = jsonDecode(map['member_ids'] as String) as List;
        expect(decoded, equals(['uid-001', 'uid-002']));
      });

      test('fromMap creates Group from SQLite row with snake_case keys', () {
        final map = {
          'id': 'g1',
          'name': 'Road Crew',
          'invite_code': 'ABC123',
          'created_by': 'uid-001',
          'member_ids': '["uid-001","uid-002"]',
          'currency': 'OMR',
          'created_at': '2026-03-01T12:00:00.000',
          'updated_at': null,
          'synced_at': null,
        };
        final group = Group.fromMap(map);

        expect(group.id, equals('g1'));
        expect(group.name, equals('Road Crew'));
        expect(group.inviteCode, equals('ABC123'));
        expect(group.memberIds, equals(['uid-001', 'uid-002']));
        expect(group.updatedAt, isNull);
      });

      test(
        'round-trip: Group -> toMap -> fromMap returns equivalent Group',
        () {
          final map = baseGroup.toMap();
          final restored = Group.fromMap(map);

          expect(restored.id, equals(baseGroup.id));
          expect(restored.name, equals(baseGroup.name));
          expect(restored.inviteCode, equals(baseGroup.inviteCode));
          expect(restored.createdBy, equals(baseGroup.createdBy));
          expect(restored.memberIds, equals(baseGroup.memberIds));
          expect(restored.currency, equals(baseGroup.currency));
          expect(
            restored.createdAt.toIso8601String(),
            equals(baseGroup.createdAt.toIso8601String()),
          );
        },
      );

      test('memberIds is List<String> not Map (per D-14)', () {
        expect(baseGroup.memberIds, isA<List<String>>());
        expect(baseGroup.memberIds, containsAll(['uid-001', 'uid-002']));
      });

      test('fromMap with null updated_at produces null updatedAt', () {
        final map = Map<String, dynamic>.from(baseGroup.toMap());
        map['updated_at'] = null;
        final restored = Group.fromMap(map);
        expect(restored.updatedAt, isNull);
      });

      test('default currency is OMR when not specified in fromMap', () {
        final map = Map<String, dynamic>.from(baseGroup.toMap());
        map['currency'] = null;
        final restored = Group.fromMap(map);
        expect(restored.currency, equals('OMR'));
      });
    });

    group('copyWith', () {
      test('copyWith creates new instance with updated name', () {
        final updated = baseGroup.copyWith(name: 'Desert Crew');

        expect(updated.name, equals('Desert Crew'));
        expect(updated, isNot(same(baseGroup)));
      });

      test('copyWith preserves unchanged fields', () {
        final updated = baseGroup.copyWith(name: 'Desert Crew');

        expect(updated.id, equals(baseGroup.id));
        expect(updated.inviteCode, equals(baseGroup.inviteCode));
        expect(updated.createdBy, equals(baseGroup.createdBy));
        expect(updated.memberIds, equals(baseGroup.memberIds));
        expect(updated.currency, equals(baseGroup.currency));
      });

      test('copyWith with new memberIds does not mutate original', () {
        final updated = baseGroup.copyWith(
          memberIds: ['uid-001', 'uid-002', 'uid-003'],
        );

        expect(updated.memberIds.length, equals(3));
        expect(baseGroup.memberIds.length, equals(2));
      });
    });

    test('equality is id-based', () {
      final copy = baseGroup.copyWith(name: 'Different Name');
      expect(copy, equals(baseGroup));
      expect(copy.hashCode, equals(baseGroup.hashCode));
    });

    test('different ids are not equal', () {
      final other = baseGroup.copyWith(id: 'g2');
      expect(other, isNot(equals(baseGroup)));
    });
  });

  group('GroupMember model', () {
    final baseMember = GroupMember(
      id: 'm1',
      groupId: 'g1',
      userId: 'uid-001',
      displayName: 'Nasser',
      role: 'CREATOR',
      isShadow: false,
      joinedAt: DateTime(2026, 3, 1, 12, 0, 0),
    );

    group('fromDoc / toMap serialization', () {
      test('toMap produces SQLite-compatible map', () {
        final map = baseMember.toMap();

        expect(map['id'], equals('m1'));
        expect(map['group_id'], equals('g1'));
        expect(map['user_id'], equals('uid-001'));
        expect(map['display_name'], equals('Nasser'));
        expect(map['role'], equals('CREATOR'));
        expect(map['is_shadow'], equals(0));
        expect(map['joined_at'], isA<String>());
      });

      test('fromMap creates GroupMember from SQLite row', () {
        final map = {
          'id': 'm1',
          'group_id': 'g1',
          'user_id': 'uid-001',
          'display_name': 'Nasser',
          'role': 'CREATOR',
          'is_shadow': 0,
          'joined_at': '2026-03-01T12:00:00.000',
          'synced_at': null,
        };
        final member = GroupMember.fromMap(map);

        expect(member.id, equals('m1'));
        expect(member.groupId, equals('g1'));
        expect(member.userId, equals('uid-001'));
        expect(member.displayName, equals('Nasser'));
        expect(member.role, equals('CREATOR'));
        expect(member.isShadow, isFalse);
      });

      test('fromDoc reads tombstone flag from Firestore', () async {
        final firestore = FakeFirebaseFirestore();
        final ref = firestore.doc('groups/g1/members/deleted-a1b2c3d4');
        await ref.set({
          'userId': 'deleted-a1b2c3d4',
          'displayName': 'Deleted member',
          'role': 'MEMBER',
          'isShadow': false,
          'isTombstone': true,
          'joinedAt': Timestamp.fromDate(DateTime(2026, 3, 2, 12, 0, 0)),
        });

        final member = GroupMember.fromDoc(await ref.get(), 'g1');

        expect(member.isTombstone, isTrue);
      });

      test(
        'isShadow stored as int (0/1) in toMap and restored from fromMap',
        () {
          final shadow = baseMember.copyWith(isShadow: true);
          final map = shadow.toMap();
          expect(map['is_shadow'], equals(1));

          final restored = GroupMember.fromMap(map);
          expect(restored.isShadow, isTrue);
        },
      );

      test('role is String not enum — accepts CREATOR and MEMBER', () {
        final creator = baseMember.copyWith(role: 'CREATOR');
        final member = baseMember.copyWith(role: 'MEMBER');

        expect(creator.role, equals('CREATOR'));
        expect(member.role, equals('MEMBER'));
        expect(creator.role, isA<String>());
      });

      test(
        'round-trip: GroupMember -> toMap -> fromMap returns equivalent',
        () {
          final map = baseMember.toMap();
          final restored = GroupMember.fromMap(map);

          expect(restored.id, equals(baseMember.id));
          expect(restored.groupId, equals(baseMember.groupId));
          expect(restored.userId, equals(baseMember.userId));
          expect(restored.displayName, equals(baseMember.displayName));
          expect(restored.role, equals(baseMember.role));
          expect(restored.isShadow, equals(baseMember.isShadow));
        },
      );
    });

    test('isCreator returns true for CREATOR role', () {
      expect(baseMember.isCreator, isTrue);
    });

    test('isCreator returns false for MEMBER role', () {
      final member = baseMember.copyWith(role: 'MEMBER');
      expect(member.isCreator, isFalse);
    });

    test('copyWith changes only specified fields', () {
      final updated = baseMember.copyWith(displayName: 'Ali');

      expect(updated.displayName, equals('Ali'));
      expect(updated.id, equals(baseMember.id));
      expect(updated.role, equals(baseMember.role));
    });

    test('equality is id-based', () {
      final copy = baseMember.copyWith(displayName: 'Different');
      expect(copy, equals(baseMember));
    });

    test('default isShadow is false', () {
      final member = GroupMember(
        id: 'm2',
        groupId: 'g1',
        userId: 'uid-002',
        displayName: 'Sara',
        role: 'MEMBER',
        joinedAt: DateTime.now(),
      );
      expect(member.isShadow, isFalse);
    });
  });
}
