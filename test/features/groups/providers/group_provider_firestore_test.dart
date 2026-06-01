import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

Future<void> _seedGroup(
  FakeFirebaseFirestore db, {
  required String id,
  required DateTime createdAt,
  List<String> memberIds = const ['owner'],
  bool? isDeleted,
}) {
  final data = <String, Object?>{
    'id': id,
    'name': 'Group $id',
    'inviteCode': 'ABC123',
    'createdBy': 'owner',
    'memberIds': memberIds,
    'currency': 'OMR',
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(createdAt),
    'deletedAt': null,
  };
  if (isDeleted != null) {
    data['isDeleted'] = isDeleted;
  }
  return db.collection('groups').doc(id).set(data);
}

Future<void> _seedMember(
  FakeFirebaseFirestore db, {
  required String groupId,
  required String id,
  required String userId,
  required String displayName,
  required DateTime joinedAt,
}) {
  return db
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc(id)
      .set({
        'id': id,
        'userId': userId,
        'displayName': displayName,
        'role': id == 'member-1' ? 'CREATOR' : 'MEMBER',
        'joinedAt': Timestamp.fromDate(joinedAt),
        'isShadow': false,
      });
}

ProviderContainer _container(FakeFirebaseFirestore db) {
  final container = ProviderContainer(
    overrides: [
      firebaseUserProvider.overrideWith(
        (ref) => Stream.value(MockUser(uid: 'owner', isAnonymous: true)),
      ),
      groupServiceProvider.overrideWith(
        (ref) => GroupService.withFirestore(ref, db, currentUserId: 'owner'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'userGroupsProvider reads current-user groups through GroupService',
    () async {
      final db = FakeFirebaseFirestore();
      await _seedGroup(db, id: 'legacy', createdAt: DateTime.utc(2026, 1, 3));
      await _seedGroup(
        db,
        id: 'active',
        createdAt: DateTime.utc(2026, 1, 2),
        isDeleted: false,
      );
      await _seedGroup(
        db,
        id: 'deleted',
        createdAt: DateTime.utc(2026, 1, 1),
        isDeleted: true,
      );
      await _seedGroup(
        db,
        id: 'other-user',
        createdAt: DateTime.utc(2026, 1, 4),
        memberIds: const ['someone-else'],
      );

      final container = _container(db);
      await container.read(firebaseUserProvider.future);

      final groups = await container.read(userGroupsProvider.future);

      expect(groups.map((group) => group.id), ['legacy', 'active']);
    },
  );

  test(
    'groupMembersProvider reads ordered members through GroupService',
    () async {
      final db = FakeFirebaseFirestore();
      await _seedGroup(db, id: 'group-1', createdAt: DateTime.utc(2026, 1, 1));
      await _seedMember(
        db,
        groupId: 'group-1',
        id: 'member-2',
        userId: 'bob',
        displayName: 'Bob',
        joinedAt: DateTime.utc(2026, 1, 2),
      );
      await _seedMember(
        db,
        groupId: 'group-1',
        id: 'member-1',
        userId: 'alice',
        displayName: 'Alice',
        joinedAt: DateTime.utc(2026, 1, 1),
      );

      final container = _container(db);

      final members = await container.read(
        groupMembersProvider('group-1').future,
      );

      expect(members.map((member) => member.displayName), ['Alice', 'Bob']);
    },
  );

  test(
    'groupDetailProvider reads existing and missing groups through GroupService',
    () async {
      final db = FakeFirebaseFirestore();
      await _seedGroup(db, id: 'group-1', createdAt: DateTime.utc(2026, 1, 1));
      final container = _container(db);

      final existing = await container.read(
        groupDetailProvider('group-1').future,
      );
      final missing = await container.read(
        groupDetailProvider('missing').future,
      );

      expect(existing, isA<Group>());
      expect(existing?.id, 'group-1');
      expect(missing, isNull);
    },
  );
}
