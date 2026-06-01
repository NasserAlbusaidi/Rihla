import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

// RED regression for cluster `server-deletegroup-callable` (#190), spec §8.4-A.
//
// The soft-delete model (option (b): keep `memberIds`, filter on `isDeleted`)
// requires a create-path producer fix + a visibility filter (HARD REQ #6):
//   1. `createGroup` must persist `isDeleted:false` + `deletedAt:null` so a new
//      group carries explicit soft-delete state and passes `validGroupCreate`.
//   2. `Group.fromDoc` must read `isDeleted`/`deletedAt`, and the visibility
//      query must drop `isDeleted:true` groups while keeping `isDeleted:false`.
//
// Original RED reasons before #190 was implemented:
//   - case 1: `createGroup` (group_provider.dart:120-129) omits both keys, so
//     the persisted group doc has no `isDeleted`/`deletedAt` → ASSERTION fail.
//   - case 2: `Group.fromDoc` (group_model.dart:33-47) defines no `isDeleted`
//     getter → COMPILE fail (the soft-delete model surface the visibility
//     filter depends on is absent). After GREEN it asserts the filter behavior.
//
// NOTE: `userGroupsProvider` reads `FirebaseConfig.firestore` statically
// (group_provider.dart:397) and is not DI-injectable, so case 2 drives the
// EXACT post-fix read shape (`memberIds arrayContains` + `orderBy createdAt
// desc`, then an IN-MEMORY `!isDeleted` filter) against a FakeFirebaseFirestore
// and maps through `Group.fromDoc`, pinning the same invariant at the
// query+model level. The filter is client-side (not a `where('isDeleted','==',
// false)` query) so a legacy group whose doc predates the field — `isDeleted`
// absent — stays VISIBLE instead of being silently hidden until a backfill ran.

void main() {
  Map<String, dynamic> groupData({
    required String id,
    required String uid,
    bool? isDeleted,
    DateTime? deletedAt,
    DateTime? createdAt,
  }) {
    final data = <String, dynamic>{
      'id': id,
      'name': 'Group $id',
      'inviteCode': '${id.toUpperCase()}12',
      'createdBy': uid,
      'memberIds': [uid],
      'currency': 'OMR',
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026)),
      'updatedAt': null,
    };
    if (isDeleted != null) {
      data['isDeleted'] = isDeleted;
      data['deletedAt'] =
          deletedAt != null ? Timestamp.fromDate(deletedAt) : null;
    }
    return data;
  }

  // The EXACT post-fix userGroupsProvider read shape: the existing
  // memberIds+createdAt query, then an in-memory `!isDeleted` filter.
  Future<List<Group>> visibleGroupsFor(
    FakeFirebaseFirestore db,
    String uid,
  ) async {
    final snap = await db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map(Group.fromDoc)
        .where((group) => !group.isDeleted)
        .toList();
  }

  test(
    'createGroup persists isDeleted:false + deletedAt:null (producer fix, '
    'HARD REQ #6) — FAILS today: createGroup omits them',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Owner',
      });
      final prefs = await SharedPreferences.getInstance();
      final fakeDb = FakeFirebaseFirestore();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupServiceProvider.overrideWith(
            (ref) =>
                GroupService.withFirestore(ref, fakeDb, currentUserId: 'owner'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final group = await container
          .read(groupServiceProvider)
          .createGroup(name: 'Desert Crew', currency: 'OMR');

      final doc = await fakeDb.doc('groups/${group.id}').get();
      final data = doc.data()!;

      expect(
        data.containsKey('isDeleted'),
        isTrue,
        reason:
            'createGroup must write isDeleted so the new userGroupsProvider '
            'model surface has explicit soft-delete state (#190 HARD REQ #6).',
      );
      expect(data['isDeleted'], isFalse);
      expect(
        data.containsKey('deletedAt'),
        isTrue,
        reason: 'createGroup must write deletedAt:null alongside isDeleted.',
      );
      expect(data['deletedAt'], isNull);
    },
  );

  test(
    'visibility filter excludes isDeleted:true, keeps isDeleted:false AND '
    'legacy docs with no isDeleted field (Group.fromDoc defaults false) — '
    'FAILS today: no isDeleted getter',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('groups/gLegacy').set(
        // Pre-#190 doc: NO isDeleted field. Must stay visible (no backfill).
        groupData(id: 'gLegacy', uid: 'owner', createdAt: DateTime(2026, 1, 3)),
      );
      await db.doc('groups/gActive').set(
        groupData(
          id: 'gActive',
          uid: 'owner',
          isDeleted: false,
          createdAt: DateTime(2026, 1, 2),
        ),
      );
      await db.doc('groups/gDeleted').set(
        groupData(
          id: 'gDeleted',
          uid: 'owner',
          isDeleted: true,
          deletedAt: DateTime(2026, 5, 31),
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final visible = await visibleGroupsFor(db, 'owner');

      expect(
        visible.map((g) => g.id),
        equals(['gLegacy', 'gActive']),
        reason:
            'The in-memory !isDeleted filter must drop only the soft-deleted '
            'group, keeping the active one AND the legacy field-absent one — '
            'no server equality query that would hide legacy groups (#190, '
            'codex [P1]: backfill-or-vanish avoided).',
      );
      // Pin the model surface the filter depends on.
      expect(visible.every((g) => !g.isDeleted), isTrue);
    },
  );
}
