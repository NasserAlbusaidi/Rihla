import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/home/providers/cross_group_activity_pager.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// #928 — Malformed-doc fencing for the money read paths.
///
/// The money factories (`Expense.fromFirestore`, `Settlement.fromFirestore`)
/// are TOTAL-PARSE: a present-but-wrong-type field is salvaged to the value the
/// TS server oracle `recomputeNet` reads for the same doc — never thrown. One
/// bad Firestore doc must not blank the ledger, the settle-up stream, or the
/// home balance once-path. Skipping a money doc has NO server counterpart (the
/// oracle is total), so the factory MUST stay total; the layer-2 fence is a
/// doc-catastrophe backstop only.
void main() {
  final epochUtc = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  Participant participant(String id) => Participant(
        id: id,
        tripId: 'event-1',
        role: ParticipantRole.member,
        joinedAt: DateTime(2026),
        displayName: id,
      );

  Decimal netFor(List<UserBalance> balances, String id) =>
      balances.singleWhere((b) => b.participantId == id).netBalance;

  Map<String, dynamic> goodExpense(Map<String, dynamic> overrides) => {
        'id': 'x1',
        'eventId': 'e1',
        'payerParticipantId': 'p1',
        'amountFils': 10000,
        'currency': 'OMR',
        'scope': 'global',
        'createdAt': DateTime.utc(2026, 5, 13, 10).toIso8601String(),
        'isDeleted': false,
        'createdBy': 'u',
        ...overrides,
      };

  Map<String, dynamic> goodSettlement(Map<String, dynamic> overrides) => {
        'id': 's1',
        'eventId': 'e1',
        'payerParticipantId': 'p1',
        'recipientParticipantId': 'p2',
        'amountFils': 5000,
        'currency': 'OMR',
        'settledAt': DateTime.utc(2026, 5, 13, 10).toIso8601String(),
        'isDeleted': false, // the watch* queries filter isDeleted == false
        'createdBy': 'u',
        ...overrides,
      };

  // ---------------------------------------------------------------------------
  // Test 1 — timestamp salvage (direct unit). The issue's named repro.
  // ---------------------------------------------------------------------------
  group('test 1 — timestamp salvage keeps the money counting', () {
    test('Expense createdAt: 12345 (int) → epoch UTC, amount intact, no throw',
        () {
      final e = Expense.fromFirestore(goodExpense({'createdAt': 12345}));
      expect(e.createdAt, epochUtc);
      expect(e.amount, Decimal.parse('10.000'));
    });

    test('Settlement settledAt: {x:1} (map) → epoch UTC, amount intact', () {
      final s =
          Settlement.fromFirestore(goodSettlement({'settledAt': {'x': 1}}));
      expect(s.settledAt, epochUtc);
      expect(s.amount, Decimal.parse('5.000'));
    });

    test('an un-parseable createdAt STRING also salvages to epoch, not a throw',
        () {
      final e = Expense.fromFirestore(goodExpense({'createdAt': 'not-a-date'}));
      expect(e.createdAt, epochUtc);
      expect(e.amount, Decimal.parse('10.000'));
    });
  });

  // ---------------------------------------------------------------------------
  // Test 3 — expense split-garbage (direct unit). Mirrors TS persistedInt.
  // ---------------------------------------------------------------------------
  group('test 3 — non-numeric split value decodes to 0, not a throw', () {
    test('splitDistribution {uid-b: "abc"} (mode exact) → 0-value entry', () {
      final e = Expense.fromFirestore(goodExpense({
        'splitMode': SplitMode.exact.storageKey,
        'splitDistribution': {'uid-b': 'abc'},
      }));
      expect(e.splitDistribution?['uid-b'], Decimal.zero);
    });
  });

  // ---------------------------------------------------------------------------
  // Test 4 — client↔oracle parity pin (Dart side). Mirrored in
  // functions/test/callables/groupNetBalance.test.ts with identical inputs and
  // identical hand-computed nets. Pins BOTH layers of the fix: the payer salvage
  // (throws pre-salvage) AND the eventBalanceUniverse guard (a naive salvage-only
  // fix would seed a phantom '' row + inflate the equal-split divisor).
  // ---------------------------------------------------------------------------
  test('test 4 — non-string-payer expense: alice -5.000, bob -5.000, no phantom',
      () {
    final expense = Expense.fromFirestore(goodExpense({
      'payerParticipantId': 42, // non-string → salvaged to ''
    }));
    // Layer 1: salvage — no throw, payer is the empty sentinel.
    expect(expense.payerParticipantId, '');
    expect(expense.amount, Decimal.parse('10.000'));

    final event = Event(
      id: 'e1',
      name: 'E',
      type: EventType.trip,
      groupId: 'g',
      createdBy: 'alice',
      participantIds: const ['alice', 'bob'],
      participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
      modules: const EventModules(),
      createdAt: DateTime(2026),
    );

    // Layer 2: the universe guard drops the '' payer — no phantom row.
    final universe = eventBalanceUniverse(
      event: event,
      expenses: [expense],
      settlements: const [],
      allMemberIds: {'alice', 'bob'},
      liveMemberIds: {'alice', 'bob'},
    );
    expect(universe, {'alice', 'bob'});

    // Derive participants FROM the universe so a missing guard (phantom '')
    // would surface here as a 3-way split, not a -5.000/-5.000 pair.
    final balances = BalanceCalculator.calculateBalances(
      expenses: [expense],
      participants: universe.map(participant).toList(),
    )['OMR']!;
    expect(balances.length, 2, reason: 'no phantom "" balance row');
    expect(netFor(balances, 'alice'), Decimal.parse('-5.000'));
    expect(netFor(balances, 'bob'), Decimal.parse('-5.000'));
  });

  // ---------------------------------------------------------------------------
  // Test 7 — factory-totality guardrail (the standing pin keeping the money
  // fence a dead branch). EVERY field simultaneously wrong-typed — incl.
  // currency: 42 — must salvage, never throw. Keys enumerated from the model.
  // ---------------------------------------------------------------------------
  group('test 7 — factory totality: every field wrong-typed salvages', () {
    test('Expense.fromFirestore never throws with all fields wrong-typed', () {
      late Expense e;
      expect(
        () => e = Expense.fromFirestore({
          'id': 1,
          'eventId': 2,
          'payerParticipantId': 3,
          'amountFils': 'not-int',
          'currency': 42,
          'description': 5,
          'scope': 6,
          'subGroupId': 7,
          'customSplitParticipants': {'not': 'a list'},
          'splitMode': 8,
          'splitDistribution': [1, 2, 3],
          'splitExplanation': 'not-a-map',
          'receiptUrl': 9,
          'createdAt': 12345,
          'categoryId': 10,
          'note': 11,
          'isDeleted': 'yes',
          'deletedAt': {'x': 1},
          'createdBy': 12,
          'lastEditedBy': 13,
        }),
        returnsNormally,
      );
      expect(e.id, '');
      expect(e.payerParticipantId, '');
      expect(e.amount, Decimal.zero);
      expect(e.currency, 'OMR');
      expect(e.customSplitParticipants, isNull);
      expect(e.splitExplanation, isNull);
      expect(e.createdAt, epochUtc);
      expect(e.isDeleted, isFalse);
      expect(e.deletedAt, isNull);
    });

    test('Settlement.fromFirestore never throws with all fields wrong-typed',
        () {
      late Settlement s;
      expect(
        () => s = Settlement.fromFirestore({
          'id': 1,
          'eventId': 2,
          'groupId': 3,
          'payerParticipantId': 4,
          'recipientParticipantId': 5,
          'amountFils': 'x',
          'currency': 42,
          'note': 6,
          'settledAt': {'x': 1},
          'payerName': 7,
          'recipientName': 8,
          'isDeleted': 'no',
          'deletedAt': 9,
          'scope': 10,
          'createdBy': 11,
          'groupSettleUpId': 12,
          'correctionOfSettlementId': 13,
        }),
        returnsNormally,
      );
      expect(s.id, '');
      expect(s.tripId, '');
      expect(s.payerParticipantId, isNull);
      expect(s.recipientParticipantId, isNull);
      expect(s.amount, Decimal.zero);
      expect(s.currency, 'OMR');
      expect(s.settledAt, epochUtc);
      expect(s.isDeleted, isFalse);
      expect(s.scope, 'event');
    });
  });

  // ---------------------------------------------------------------------------
  // Test 2 — query-level salvage (service level). A malformed doc alongside good
  // docs no longer errors the stream; every doc surfaces (salvaged). The bad
  // field is NOT the orderBy sort key (payer / recipient, not createdAt /
  // settledAt) so FakeFirebaseFirestore's comparator never throws pre-decode.
  // ---------------------------------------------------------------------------
  group('test 2 — money list streams survive one malformed doc', () {
    late FakeFirebaseFirestore db;

    setUp(() => db = FakeFirebaseFirestore());

    CollectionReference<Map<String, dynamic>> eventExpenses() => db
        .collection('groups')
        .doc('g')
        .collection('events')
        .doc('e')
        .collection('expenses');

    CollectionReference<Map<String, dynamic>> eventSettlements() => db
        .collection('groups')
        .doc('g')
        .collection('events')
        .doc('e')
        .collection('settlements');

    CollectionReference<Map<String, dynamic>> groupSettlements() =>
        db.collection('groups').doc('g').collection('settlements');

    test('watchExpenses + getExpenses emit all 3 (2 good + 1 payer:42)',
        () async {
      for (final id in ['a', 'b']) {
        await eventExpenses().doc(id).set(goodExpense({'id': id}));
      }
      await eventExpenses().doc('bad').set(goodExpense({
        'id': 'bad',
        'payerParticipantId': 42, // NOT the sort key
      }));

      final service = ExpenseService.withFirestore(db);
      final streamed = await service.watchExpenses('g', 'e').first;
      final once = await service.getExpenses('g', 'e');

      expect(streamed.length, 3);
      expect(once.length, 3);
      expect(
        streamed.singleWhere((e) => e.id == 'bad').payerParticipantId,
        '',
      );
    });

    test('watchSettlements + getSettlements emit all 3 (recipient:42)',
        () async {
      for (final id in ['a', 'b']) {
        await eventSettlements().doc(id).set(goodSettlement({'id': id}));
      }
      await eventSettlements().doc('bad').set(goodSettlement({
        'id': 'bad',
        'recipientParticipantId': 42, // NOT the sort key
      }));

      final service = SettlementService.withFirestore(db);
      final streamed = await service.watchSettlements('g', 'e').first;
      final once = await service.getSettlements('g', 'e');

      expect(streamed.length, 3);
      expect(once.length, 3);
      expect(
        streamed.singleWhere((s) => s.id == 'bad').recipientParticipantId,
        isNull,
      );
    });

    test('watchGroupSettlements emits all 3 (recipient:42)', () async {
      for (final id in ['a', 'b']) {
        await groupSettlements().doc(id).set(goodSettlement({
              'id': id,
              'scope': 'group',
              'groupId': 'g',
            }));
      }
      await groupSettlements().doc('bad').set(goodSettlement({
            'id': 'bad',
            'scope': 'group',
            'groupId': 'g',
            'recipientParticipantId': 42,
          }));

      final service = GroupSettlementService.withFirestore(db);
      final streamed = await service.watchGroupSettlements('g').first;

      expect(streamed.length, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // Test 6 — reconcile-cache fence. The incremental `_reconcileExpenses`
  // docChanges path carries a salvaged expense that arrives on a LATER tick
  // (cache-miss → build-loop parse), not just the initial snapshot; the good
  // rows survive. (A doc whose decode STILL throws is unreachable through the
  // total factory — the inline catch is a documented doc-catastrophe backstop
  // covered by review + the totality test 7.)
  // ---------------------------------------------------------------------------
  group('test 6 — reconcile cache carries a salvaged doc on a later tick', () {
    test('a payer:42 expense added after the first tick is salvaged, not lost',
        () async {
      final db = FakeFirebaseFirestore();
      final expenses = db
          .collection('groups')
          .doc('g')
          .collection('events')
          .doc('e')
          .collection('expenses');
      await expenses.doc('good1').set(goodExpense({'id': 'good1'}));

      final service = ExpenseService.withFirestore(db);
      final emissions = <List<Expense>>[];
      final sub = service.watchExpenses('g', 'e').listen(emissions.add);

      // Let the first tick land, then add a malformed-but-salvageable doc.
      await Future<void>.delayed(Duration.zero);
      await expenses.doc('bad').set(goodExpense({
            'id': 'bad',
            'payerParticipantId': 42,
          }));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      final last = emissions.last;
      expect(last.map((e) => e.id), containsAll(['good1', 'bad']));
      expect(last.singleWhere((e) => e.id == 'bad').payerParticipantId, '');
    });
  });

  // ---------------------------------------------------------------------------
  // Test 5 — activity feeds skip a malformed row instead of failing the page.
  // The display-only activity factories are UNTOUCHED (skip-and-report is
  // correct — no oracle to stay in lockstep with); the fence lives at each list
  // map. `description`/`logText` throw sites are NOT the `timestamp`/`createdAt`
  // sort keys, so the FakeFirebaseFirestore comparator never trips pre-decode.
  // ---------------------------------------------------------------------------
  group('test 5 — group activity service skips a malformed row', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    Future<void> seedActivity(String gid, List<Map<String, dynamic>> rows) async {
      for (final r in rows) {
        await db
            .collection('groups')
            .doc(gid)
            .collection('activity')
            .doc(r['id'] as String)
            .set(r);
      }
    }

    Map<String, dynamic> gLog(String id, {Object? description = 'ok', DateTime? at}) => {
          'id': id,
          'type': 'event_created',
          'actorId': 'uid0',
          'actorName': 'A',
          'description': description, // NOT the sort key
          'metadata': const <String, dynamic>{},
          'timestamp': (at ?? DateTime.utc(2026, 3, 28)).toIso8601String(),
        };

    test('watchRecentActivity skips a description:null row, emits the good one',
        () async {
      await seedActivity('g', [
        gLog('good', at: DateTime.utc(2026, 3, 28, 10)),
        gLog('bad', description: null, at: DateTime.utc(2026, 3, 28, 9)),
      ]);
      final service = GroupActivityService.withFirestore(db);
      final logs = await service.watchRecentActivity('g').first;
      expect(logs.map((l) => l.id), ['good']);
    });

    test('fetchActivityPage skips a description:null row, keeps the good ones',
        () async {
      await seedActivity('g', [
        gLog('good1', at: DateTime.utc(2026, 3, 28, 10)),
        gLog('bad', description: null, at: DateTime.utc(2026, 3, 28, 9)),
        gLog('good2', at: DateTime.utc(2026, 3, 28, 8)),
      ]);
      final service = GroupActivityService.withFirestore(db);
      final page = await service.fetchActivityPage('g');
      expect(page.map((l) => l.id), ['good1', 'good2']);
    });
  });

  // ---------------------------------------------------------------------------
  // Test 5 (pager) + 5b (frontier). The cross-group pager must (a) keep a
  // group's good rows when one of its rows is malformed (today the per-group
  // catch drops the WHOLE group), and (b) NOT falsely exhaust a group when a
  // FULL raw page decodes short because a row was skipped — the frontier fix
  // derives `exhausted` from the RAW page count, not the deserialized count.
  // ---------------------------------------------------------------------------
  group('test 5/5b — cross-group activity pager fences + frontier', () {
    Group grp(String id) => Group(
          id: id,
          name: id,
          inviteCode: 'INV${id.toUpperCase()}',
          createdBy: 'uid0',
          memberIds: const ['uid0'],
          currency: 'OMR',
          createdAt: DateTime(2026, 1, 1),
        );

    Map<String, dynamic> gLog(String id, {Object? description = 'ok', required DateTime at}) => {
          'id': id,
          'type': 'event_created',
          'actorId': 'uid0',
          'actorName': 'A',
          'description': description,
          'metadata': const <String, dynamic>{},
          'timestamp': at.toIso8601String(),
        };

    Future<CrossGroupActivityPagerState> settled(
      ProviderContainer container,
    ) async {
      container.read(crossGroupActivityPagerProvider.notifier);
      for (var i = 0; i < 400; i++) {
        final s = container.read(crossGroupActivityPagerProvider);
        if (s.initialised && !s.isLoadingMore) return s;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      throw StateError('pager never settled');
    }

    test('a malformed row in group A does not drop group A from the feed',
        () async {
      final db = FakeFirebaseFirestore();
      Future<void> put(String gid, Map<String, dynamic> r) => db
          .collection('groups')
          .doc(gid)
          .collection('activity')
          .doc(r['id'] as String)
          .set(r);
      await put('a', gLog('a-good', at: DateTime.utc(2026, 3, 28, 10)));
      await put('a', gLog('a-bad', description: null, at: DateTime.utc(2026, 3, 28, 9)));
      await put('b', gLog('b-good', at: DateTime.utc(2026, 3, 28, 8)));

      final container = ProviderContainer(overrides: [
        userGroupsProvider.overrideWith((ref) => Stream.value([grp('a'), grp('b')])),
        groupActivityServiceProvider
            .overrideWith((ref) => GroupActivityService.withFirestore(db)),
      ]);
      addTearDown(container.dispose);

      final state = await settled(container);
      final ids = state.entries.map((e) => e.log.id).toSet();
      expect(ids, contains('a-good'),
          reason: 'group A survives its own malformed row');
      expect(ids, contains('b-good'));
      expect(state.firstLoadFailed, isFalse);
    });

    test('test 5b — a full page with 1 skipped row does not falsely exhaust',
        () async {
      final db = FakeFirebaseFirestore();
      // kCrossGroupActivityPageSize raw docs on page 1 (one mid-page malformed)
      // + 5 more OLDER docs beyond the page. Newest-first by timestamp.
      const total = kCrossGroupActivityPageSize + 5;
      for (var i = 1; i <= total; i++) {
        final id = 'd${i.toString().padLeft(2, '0')}';
        await db.collection('groups').doc('g').collection('activity').doc(id).set(
              gLog(
                id,
                description: i == 25 ? null : 'desc',
                at: DateTime.utc(2026, 1, 1).subtract(Duration(minutes: i)),
              ),
            );
      }

      final container = ProviderContainer(overrides: [
        userGroupsProvider.overrideWith((ref) => Stream.value([grp('g')])),
        groupActivityServiceProvider
            .overrideWith((ref) => GroupActivityService.withFirestore(db)),
      ]);
      addTearDown(container.dispose);

      final afterFirst = await settled(container);
      // A full raw page (50) decoded to 49 must NOT mark the group exhausted.
      expect(afterFirst.hasMore, isTrue,
          reason: 'raw page was full (50); the skipped row must not drain it');

      await container.read(crossGroupActivityPagerProvider.notifier).loadMore();
      final afterSecond = await settled(container);
      final ids = afterSecond.entries.map((e) => e.log.id).toSet();
      expect(ids, contains('d${total.toString().padLeft(2, '0')}'),
          reason: 'the older page-2 docs surface; the group was not falsely '
              'drained by the raw-vs-deserialized count mismatch');
    });
  });
}
