import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

/// #441 PR2 — the durable-credential gate inside GroupService.
///
/// createGroup/joinGroup must refuse to stage ANY write for an anonymous
/// user (an offline-queued batch replays on reconnect and bypasses UI
/// gates), and the seam must default to "durable" so every pre-existing
/// withFirestore test keeps its contract.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Nasser'});
    prefs = await SharedPreferences.getInstance();
  });

  GroupService buildService(
    FakeFirebaseFirestore db, {
    bool Function()? isAnonymous,
    Future<String> Function({
      required String inviteCode,
      required String displayName,
    })?
    joinGroupCallableOverride,
  }) {
    late GroupService service;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupServiceProvider.overrideWith((ref) {
          service = GroupService.withFirestore(
            ref,
            db,
            currentUserId: 'uid-under-test',
            isAnonymous: isAnonymous,
            joinGroupCallableOverride: joinGroupCallableOverride,
          );
          return service;
        }),
      ],
    );
    addTearDown(container.dispose);
    return container.read(groupServiceProvider);
  }

  test(
    'createGroup throws DurableCredentialRequiredException for an anonymous '
    'user and stages no writes',
    () async {
      final db = FakeFirebaseFirestore();
      final service = buildService(db, isAnonymous: () => true);

      await expectLater(
        service.createGroup(name: 'Trip', currency: 'OMR'),
        throwsA(isA<DurableCredentialRequiredException>()),
      );

      expect((await db.collection('groups').get()).docs, isEmpty);
      expect((await db.collection('inviteCodes').get()).docs, isEmpty);
    },
  );

  test(
    '#648: joinGroup invokes the callable for an anonymous user '
    '(gate creation, not participation)',
    () async {
      var callableInvoked = false;
      final db = FakeFirebaseFirestore();
      // The callable owns the membership write; mirror it so the post-join
      // group read (Group.fromDoc) finds a document.
      await db.collection('groups').doc('g1').set({
        'id': 'g1',
        'name': 'Trip',
        'inviteCode': 'ABC234',
        'createdBy': 'creator',
        'memberIds': ['creator', 'uid-under-test'],
        'currency': 'OMR',
        'createdAt': DateTime(2026).toIso8601String(),
        'updatedAt': DateTime(2026).toIso8601String(),
      });
      final service = buildService(
        db,
        isAnonymous: () => true,
        joinGroupCallableOverride:
            ({required inviteCode, required displayName}) async {
              callableInvoked = true;
              return 'g1';
            },
      );

      final group = await service.joinGroup(inviteCode: 'ABC234');

      expect(callableInvoked, isTrue);
      expect(group.id, 'g1');
    },
  );

  test('createGroup proceeds when isAnonymous override reports false', () async {
    final db = FakeFirebaseFirestore();
    final service = buildService(db, isAnonymous: () => false);

    final group = await service.createGroup(name: 'Trip', currency: 'OMR');

    expect((await db.collection('groups').doc(group.id).get()).exists, isTrue);
  });

  test(
    'withFirestore without isAnonymous override defaults to durable '
    '(pre-existing tests contract)',
    () async {
      final db = FakeFirebaseFirestore();
      final service = buildService(db);

      final group = await service.createGroup(name: 'Trip', currency: 'OMR');

      expect(group.createdBy, 'uid-under-test');
    },
  );
}
