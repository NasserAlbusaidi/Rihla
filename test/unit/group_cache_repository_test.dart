import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/cache/group_cache_repository.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('rihla-group-cache-');
    await LocalDatabase.setDatabasePathForTesting(
      '${tempDir.path}/safar_cache.db',
    );
  });

  setUp(() async {
    await LocalDatabase.clearAll();
  });

  tearDownAll(() async {
    await LocalDatabase.close();
    await LocalDatabase.setDatabasePathForTesting(null);
    await tempDir.delete(recursive: true);
  });

  group('GroupCacheRepository', () {
    late GroupCacheRepository repo;

    setUp(() {
      repo = GroupCacheRepository();
    });

    test('preserves tombstone members through SQLite round-trip', () async {
      const ownerUid = 'owner-1';
      await repo.cacheGroup(
        ownerUid,
        Group(
          id: 'group-1',
          name: 'Adventure Crew',
          inviteCode: 'ABC123',
          createdBy: 'uid-owner',
          memberIds: const ['deleted-a1b2c3d4'],
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      await repo.cacheGroupMember(
        ownerUid,
        GroupMember(
          id: 'deleted-a1b2c3d4',
          groupId: 'group-1',
          userId: 'deleted-a1b2c3d4',
          displayName: 'Deleted member',
          role: 'MEMBER',
          isTombstone: true,
          joinedAt: DateTime(2026, 1, 2),
        ),
      );

      final members = await repo.getCachedGroupMembers(ownerUid, 'group-1');

      expect(members, hasLength(1));
      expect(members.single.isTombstone, isTrue);
    });

    test('reads only groups and members for the requested owner UID', () async {
      await repo.cacheGroup(
        'owner-a',
        Group(
          id: 'group-shared',
          name: 'Owner A Group',
          inviteCode: 'AAAAAA',
          createdBy: 'owner-a',
          memberIds: const ['owner-a'],
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await repo.cacheGroupMember(
        'owner-a',
        GroupMember(
          id: 'owner-a',
          groupId: 'group-shared',
          userId: 'owner-a',
          displayName: 'Owner A',
          role: 'CREATOR',
          joinedAt: DateTime(2026, 1, 1),
        ),
      );
      await repo.cacheGroup(
        'owner-b',
        Group(
          id: 'group-shared-b',
          name: 'Owner B Group',
          inviteCode: 'BBBBBB',
          createdBy: 'owner-b',
          memberIds: const ['owner-b'],
          createdAt: DateTime(2026, 1, 2),
        ),
      );

      final ownerAGroups = await repo.getCachedGroups('owner-a');
      final ownerBGroups = await repo.getCachedGroups('owner-b');
      final ownerAMembers = await repo.getCachedGroupMembers(
        'owner-a',
        'group-shared',
      );
      final ownerBMembers = await repo.getCachedGroupMembers(
        'owner-b',
        'group-shared',
      );

      expect(ownerAGroups.map((group) => group.name), ['Owner A Group']);
      expect(ownerBGroups.map((group) => group.name), ['Owner B Group']);
      expect(ownerAMembers.map((member) => member.displayName), ['Owner A']);
      expect(ownerBMembers, isEmpty);
    });
  });
}
