import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

void main() {
  // -------------------------------------------------------------------------
  // Factory total-parse: a present-but-wrong-type field is salvaged, never
  // thrown (#532). Was a hard `CastError` that blanked the whole list stream.
  // -------------------------------------------------------------------------
  group('GroupMember.fromDoc total-parse', () {
    Future<DocumentSnapshot> memberDoc(Map<String, dynamic> data) async {
      final db = FakeFirebaseFirestore();
      final ref =
          db.collection('groups').doc('g').collection('members').doc('m');
      await ref.set(data);
      return ref.get();
    }

    test('salvages joinedAt-as-String and junk role/isShadow; keeps userId',
        () async {
      final doc = await memberDoc({
        'userId': 'uid-x',
        'displayName': 'X',
        'role': 42, // wrong type → 'MEMBER'
        'isShadow': 'yes', // wrong type → false
        'isTombstone': true,
        'joinedAt': '2025-01-02T03:04:05.000', // ISO String → parsed
      });

      final m = GroupMember.fromDoc(doc, 'g');

      expect(m.userId, 'uid-x');
      expect(m.displayName, 'X');
      expect(m.role, 'MEMBER');
      expect(m.isShadow, isFalse);
      expect(m.isTombstone, isTrue);
      expect(m.joinedAt, DateTime.parse('2025-01-02T03:04:05.000'));
    });

    test('isTombstone mirrors the server: a non-true value (string) is LIVE',
        () async {
      // Server: `data.isTombstone !== true` → 'true' string is LIVE.
      final doc = await memberDoc({
        'userId': 'uid-y',
        'displayName': 'Y',
        'role': 'MEMBER',
        'isTombstone': 'true', // string, not bool → must read as NOT tombstoned
        'joinedAt': Timestamp.fromDate(DateTime(2025)),
      });

      expect(GroupMember.fromDoc(doc, 'g').isTombstone, isFalse);
    });

    test('still THROWS on a missing userId — the deliberate oracle gate '
        '(the skip-net then drops it, exactly as the server excludes it)',
        () async {
      final doc = await memberDoc({
        'displayName': 'NoId',
        'role': 'MEMBER',
        'joinedAt': Timestamp.fromDate(DateTime(2025)),
      });

      expect(() => GroupMember.fromDoc(doc, 'g'), throwsA(isA<TypeError>()));
    });
  });

  group('Group.fromDoc total-parse', () {
    Future<DocumentSnapshot> groupDoc(Map<String, dynamic> data) async {
      final db = FakeFirebaseFirestore();
      final ref = db.collection('groups').doc('g');
      await ref.set(data);
      return ref.get();
    }

    test('salvages createdAt-as-String, missing name, wrong-type memberIds',
        () async {
      final doc = await groupDoc({
        // no 'name'
        'inviteCode': 'ABC123',
        'createdBy': 'uid0',
        'memberIds': 'not-a-list', // wrong type → []
        'createdAt': '2025-01-01T00:00:00.000', // String → parsed
      });

      final g = Group.fromDoc(doc);

      expect(g.name, '');
      expect(g.memberIds, isEmpty);
      expect(g.createdAt, DateTime.parse('2025-01-01T00:00:00.000'));
      expect(g.currency, 'OMR');
      expect(g.isDeleted, isFalse);
    });

    test('a junk createdAt (un-parseable string) salvages to now, not a throw',
        () async {
      final doc = await groupDoc({
        'name': 'G',
        'inviteCode': 'ABC123',
        'createdBy': 'uid0',
        'memberIds': ['uid0'],
        'createdAt': 'not-a-date',
      });

      // Does not throw; createdAt falls back to a synthesized DateTime.
      expect(Group.fromDoc(doc).createdAt, isA<DateTime>());
    });
  });

  // -------------------------------------------------------------------------
  // PARITY (#249 + #532): a salvaged tombstoned split-recipient member stays
  // in allMemberIds, so the balance universe still folds their owed share —
  // dropping the member doc would silently delete it and diverge from the
  // server oracle (groupNetBalance.ts:529/618, gated only on userId-string).
  // -------------------------------------------------------------------------
  test('a salvaged tombstoned split-recipient stays in the balance universe',
      () async {
    final db = FakeFirebaseFirestore();
    final mRef = db.collection('groups').doc('g').collection('members').doc('m');
    await mRef.set({
      'userId': 'uid-m',
      'displayName': 'M',
      'role': 99, // junk
      'isShadow': 'nope', // junk
      'isTombstone': true, // departed
      'joinedAt': '2025-01-01T00:00:00.000', // String
    });
    final m = GroupMember.fromDoc(await mRef.get(), 'g');
    final a = GroupMember(
      id: 'a',
      groupId: 'g',
      userId: 'uid-a',
      displayName: 'A',
      role: 'MEMBER',
      joinedAt: DateTime(2025),
    );

    final members = [a, m];
    final allMemberIds = members.map((x) => x.userId).toSet();
    final liveMemberIds =
        members.where((x) => !x.isTombstone).map((x) => x.userId).toSet();

    expect(allMemberIds, containsAll(['uid-a', 'uid-m']),
        reason: 'the salvaged tombstoned member keeps its userId in the set '
            'the #249 split-recipient fold gates on');
    expect(liveMemberIds, equals({'uid-a'}),
        reason: 'isTombstone==true salvaged correctly → M is not live');

    // An exact-split expense paid by A, splitting onto A and the departed M,
    // who is NOT in the event participants.
    final event = Event(
      id: 'e',
      name: 'E',
      type: EventType.trip,
      groupId: 'g',
      createdBy: 'uid-a',
      participantIds: const ['uid-a'],
      participantNames: const {'uid-a': 'A'},
      modules: const EventModules(),
      createdAt: DateTime(2025),
    );
    final expense = Expense(
      id: 'x',
      tripId: 'e',
      payerParticipantId: 'uid-a',
      amount: Decimal.fromInt(10),
      scope: ExpenseScope.global,
      splitMode: SplitMode.exact,
      splitDistribution: {
        'uid-a': Decimal.fromInt(5),
        'uid-m': Decimal.fromInt(5),
      },
      createdAt: DateTime(2025),
    );

    final universe = eventBalanceUniverse(
      event: event,
      expenses: [expense],
      settlements: const [],
      allMemberIds: allMemberIds,
      liveMemberIds: liveMemberIds,
    );

    expect(universe, contains('uid-m'),
        reason: 'a salvaged tombstoned split-recipient must stay in the '
            'balance universe; dropping the member doc would silently delete '
            'their owed share, diverging from the server oracle');
  });

  // -------------------------------------------------------------------------
  // Stream-level: one malformed doc no longer blanks the whole list (#532).
  // -------------------------------------------------------------------------
  group('list streams survive one malformed doc', () {
    late FakeFirebaseFirestore db;
    late ProviderContainer container;
    late GroupService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = FakeFirebaseFirestore();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupServiceProvider.overrideWith(
          (ref) => GroupService.withFirestore(ref, db, currentUserId: 'owner'),
        ),
      ]);
      service = container.read(groupServiceProvider);
    });

    tearDown(() => container.dispose());

    test('watchMembers skips a no-userId member, emits the good ones', () async {
      final members = db.collection('groups').doc('g').collection('members');
      await members.doc('a').set({
        'userId': 'uid-a',
        'displayName': 'A',
        'role': 'MEMBER',
        'joinedAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
      });
      await members.doc('bad').set({
        // NO userId → undecodable → skipped (server excludes it too)
        'displayName': 'Bad',
        'role': 'MEMBER',
        'joinedAt': Timestamp.fromDate(DateTime(2025, 1, 2)),
      });
      await members.doc('b').set({
        'userId': 'uid-b',
        'displayName': 'B',
        'role': 'MEMBER',
        'joinedAt': Timestamp.fromDate(DateTime(2025, 1, 3)),
      });

      final roster = await service.watchMembers('g').first;

      expect(roster.map((m) => m.userId), ['uid-a', 'uid-b']);
    });

    test('watchUserGroups keeps a group with a malformed (salvaged) field',
        () async {
      final groups = db.collection('groups');
      await groups.doc('good').set({
        'name': 'Good',
        'inviteCode': 'AAA111',
        'createdBy': 'owner',
        'memberIds': ['owner'],
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 2)),
      });
      await groups.doc('salvage').set({
        'name': 12345, // wrong type → salvaged to ''
        'inviteCode': 'BBB222',
        'createdBy': 'owner',
        'memberIds': ['owner'],
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
      });

      final list = await service.watchUserGroups('owner').first;

      expect(list.length, 2, reason: 'a malformed field salvages, not blanks');
      expect(list.firstWhere((g) => g.inviteCode == 'BBB222').name, '');
    });
  });
}
