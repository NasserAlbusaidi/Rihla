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
      await repo.cacheGroup(
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

      final members = await repo.getCachedGroupMembers('group-1');

      expect(members, hasLength(1));
      expect(members.single.isTombstone, isTrue);
    });
  });
}
