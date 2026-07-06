import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
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
}
