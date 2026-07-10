import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/providers/shell_emptiness_gate.dart';
import 'package:safar/features/groups/models/group_model.dart';

class _MockUser extends Mock implements User {}

Group _group(String id) => Group(
  id: id,
  name: 'Trip',
  inviteCode: 'ABC234',
  createdBy: 'uid-1',
  memberIds: const ['uid-1'],
  createdAt: DateTime(2026),
);

void main() {
  late _MockUser user;

  setUp(() {
    user = _MockUser();
    when(() => user.uid).thenReturn('uid-1');
  });

  group('outgoingShellProvablyEmpty — gate logic', () {
    Future<bool> run({
      required Future<User?> Function() readUser,
      required Future<List<Group>> Function() readGroups,
      required Future<bool?> Function(String uid) probe,
      Duration timeout = const Duration(seconds: 2),
    }) {
      return outgoingShellProvablyEmpty(
        readUser: readUser,
        readGroups: readGroups,
        probeHasLiveData: probe,
        timeout: timeout,
      );
    }

    test(
      'cache-empty stream + server has live data → BLOCK (#1091 regression)',
      () async {
        final result = await run(
          readUser: () async => user,
          readGroups: () async => const <Group>[],
          probe: (_) async => true,
        );
        expect(result, isFalse);
      },
    );

    test('cache-empty stream + server-confirmed empty → PROCEED', () async {
      String? seenUid;
      final result = await run(
        readUser: () async => user,
        readGroups: () async => const <Group>[],
        probe: (uid) async {
          seenUid = uid;
          return false;
        },
      );
      expect(result, isTrue);
      expect(seenUid, 'uid-1');
    });

    test('cache-empty stream + inconclusive probe (null) → BLOCK', () async {
      final result = await run(
        readUser: () async => user,
        readGroups: () async => const <Group>[],
        probe: (_) async => null,
      );
      expect(result, isFalse);
    });

    test('probe throws → BLOCK (fail-safe)', () async {
      final result = await run(
        readUser: () async => user,
        readGroups: () async => const <Group>[],
        probe: (_) async {
          throw StateError('boom');
        },
      );
      expect(result, isFalse);
    });

    test('probe hangs past the gate timeout → BLOCK', () async {
      final result = await run(
        readUser: () async => user,
        readGroups: () async => const <Group>[],
        probe: (_) => Completer<bool?>().future,
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, isFalse);
    });

    test('non-empty stream → BLOCK without invoking the probe', () async {
      var probed = false;
      final result = await run(
        readUser: () async => user,
        readGroups: () async => [_group('g1')],
        probe: (_) async {
          probed = true;
          return false;
        },
      );
      expect(result, isFalse);
      expect(probed, isFalse);
    });

    test('null user → PROCEED without invoking the probe', () async {
      var probed = false;
      final result = await run(
        readUser: () async => null,
        readGroups: () async => const <Group>[],
        probe: (_) async {
          probed = true;
          return false;
        },
      );
      expect(result, isTrue);
      expect(probed, isFalse);
    });
  });

  group('hasAnyLiveGroupMembership — probe semantics', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('one live membership → true', () async {
      await db.collection('groups').add({
        'memberIds': ['uid-1'],
        'isDeleted': false,
      });
      expect(await hasAnyLiveGroupMembership(db, 'uid-1'), isTrue);
    });

    test(
      'tombstone-only membership → false (round-1 P1: tombstones must not block)',
      () async {
        await db.collection('groups').add({
          'memberIds': ['uid-1'],
          'isDeleted': true,
        });
        expect(await hasAnyLiveGroupMembership(db, 'uid-1'), isFalse);
      },
    );

    test('legacy doc without isDeleted → true (missing = live)', () async {
      await db.collection('groups').add({
        'memberIds': ['uid-1'],
      });
      expect(await hasAnyLiveGroupMembership(db, 'uid-1'), isTrue);
    });

    test('zero matching memberships → false', () async {
      await db.collection('groups').add({
        'memberIds': ['someone-else'],
        'isDeleted': false,
      });
      expect(await hasAnyLiveGroupMembership(db, 'uid-1'), isFalse);
    });

    test('mixed tombstone + live → true', () async {
      await db.collection('groups').add({
        'memberIds': ['uid-1'],
        'isDeleted': true,
      });
      await db.collection('groups').add({
        'memberIds': ['uid-1'],
        'isDeleted': false,
      });
      expect(await hasAnyLiveGroupMembership(db, 'uid-1'), isTrue);
    });
  });
}
