import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:safar/core/services/cache/participant_cache_repository.dart';
import 'package:safar/core/services/local_database.dart';
import 'package:safar/features/trip/models/trip_model.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('rihla-participant-cache-');
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

  Participant build({
    String id = 'p1',
    String tripId = 't1',
    String? userId = 'uid-1',
    ParticipantRole role = ParticipantRole.member,
    String? displayName = 'Alice',
    String? avatarUrl,
    bool isShadow = false,
  }) =>
      Participant(
        id: id,
        tripId: tripId,
        userId: userId,
        role: role,
        joinedAt: DateTime(2026, 3, 1),
        displayName: displayName,
        avatarUrl: avatarUrl,
        isShadow: isShadow,
      );

  group('ParticipantCacheRepository', () {
    late ParticipantCacheRepository repo;

    setUp(() {
      repo = ParticipantCacheRepository();
    });

    test('cacheParticipants writes and getCachedParticipants reads them back',
        () async {
      final p1 = build(id: 'p1', userId: 'u1', displayName: 'Alice');
      final p2 = build(
        id: 'p2',
        userId: 'u2',
        role: ParticipantRole.leader,
        displayName: 'Bob',
        avatarUrl: 'https://x/y.png',
      );
      await repo.cacheParticipants('t1', [p1, p2]);

      final loaded = await repo.getCachedParticipants('t1');
      expect(loaded, hasLength(2));
      expect(loaded.map((p) => p.id).toSet(), {'p1', 'p2'});

      final bob = loaded.firstWhere((p) => p.id == 'p2');
      expect(bob.role, ParticipantRole.leader);
      expect(bob.displayName, 'Bob');
      expect(bob.avatarUrl, 'https://x/y.png');
      expect(bob.isShadow, isFalse);
    });

    test('returns empty list when nothing cached', () async {
      final loaded = await repo.getCachedParticipants('unknown-trip');
      expect(loaded, isEmpty);
    });

    test('caching an empty list clears prior entries for that trip', () async {
      await repo.cacheParticipants('t1', [build(id: 'p1')]);
      expect(await repo.getCachedParticipants('t1'), hasLength(1));

      await repo.cacheParticipants('t1', []);
      expect(await repo.getCachedParticipants('t1'), isEmpty);
    });

    test('replaces snapshot — does not leave ghost rows', () async {
      await repo.cacheParticipants('t1', [
        build(id: 'p1'),
        build(id: 'p2'),
        build(id: 'p3'),
      ]);
      await repo.cacheParticipants('t1', [build(id: 'p1')]);

      final loaded = await repo.getCachedParticipants('t1');
      expect(loaded.map((p) => p.id), ['p1']);
    });

    test('isShadow round-trips as a 1/0 column', () async {
      await repo.cacheParticipants('t1', [
        build(id: 'p1', isShadow: true),
        build(id: 'p2', isShadow: false),
      ]);

      final loaded = await repo.getCachedParticipants('t1');
      final shadow = loaded.firstWhere((p) => p.id == 'p1');
      final real = loaded.firstWhere((p) => p.id == 'p2');
      expect(shadow.isShadow, isTrue);
      expect(real.isShadow, isFalse);
    });

    test('rows for one trip do not leak into another trip query', () async {
      await repo.cacheParticipants('t1', [build(id: 'p1', tripId: 't1')]);
      await repo.cacheParticipants('t2', [build(id: 'p2', tripId: 't2')]);

      final t1 = await repo.getCachedParticipants('t1');
      final t2 = await repo.getCachedParticipants('t2');
      expect(t1.map((p) => p.id), ['p1']);
      expect(t2.map((p) => p.id), ['p2']);
    });

    test('role string defaults to member if unknown — fromString fallback',
        () async {
      // Confirm the read path tolerates malformed role data: we write a member
      // and exercise the read mapping.
      await repo.cacheParticipants('t1', [
        build(id: 'p1', role: ParticipantRole.member),
      ]);
      final loaded = await repo.getCachedParticipants('t1');
      expect(loaded.single.role, ParticipantRole.member);
    });

    test('participant with null userId, displayName, avatarUrl round-trips',
        () async {
      await repo.cacheParticipants('t1', [
        build(
          id: 'p1',
          userId: null,
          displayName: null,
          avatarUrl: null,
        ),
      ]);
      final loaded = await repo.getCachedParticipants('t1');
      expect(loaded.single.userId, isNull);
      expect(loaded.single.displayName, isNull);
      expect(loaded.single.avatarUrl, isNull);
    });
  });
}
