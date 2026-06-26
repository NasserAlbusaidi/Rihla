import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/providers/ledger_perspective_provider.dart';
import 'package:safar/features/ledger/providers/ledger_view_provider.dart';

/// #628 — the filter-INDEPENDENT roster/hero perspective is hoisted out of
/// `_Body.build()` into the memoized [ledgerPerspectiveProvider], so a
/// category-chip `setState` (which rebuilds the body but does NOT change this
/// provider's key or its watched [ledgerViewProvider] value) is served from
/// cache instead of re-running the per-person balance pivots + sort.
///
/// These tests pin BOTH halves of "done":
///   1. behavior preservation — the perspective reproduces the former inline
///      derivations byte-for-byte (signed amounts, GCC-first lines, people
///      counts, the deferred l10n name fallback);
///   2. the memoization itself — identical value across reads with unchanged
///      deps, and a distinct value per `currentPid` key.
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  GroupMember member(String uid, String name, {bool tombstone = false}) =>
      GroupMember(
        id: uid,
        groupId: groupId,
        userId: uid,
        displayName: name,
        role: 'MEMBER',
        isTombstone: tombstone,
        joinedAt: DateTime(2026, 1, 10),
      );

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-sara',
    participantIds: const ['uid-sara', 'uid-bob'],
    participantNames: const {'uid-sara': 'Sara', 'uid-bob': 'Bob'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  Expense globalEqual({
    required String id,
    required String payer,
    required String amount,
    String currency = 'OMR',
  }) =>
      Expense(
        id: id,
        tripId: eventId,
        payerParticipantId: payer,
        amount: Decimal.parse(amount),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 11),
        createdBy: payer,
        currency: currency,
      );

  ProviderContainer makeContainer({
    List<Expense> expenses = const [],
    List<Settlement> settlements = const [],
    List<GroupMember>? members,
  }) {
    final container = ProviderContainer(
      overrides: [
        eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
        eventExpensesProvider(eventRef)
            .overrideWith((ref) => Stream.value(expenses)),
        eventSettlementsProvider(eventRef)
            .overrideWith((ref) => Stream.value(settlements)),
        groupMembersProvider(groupId).overrideWith(
          (ref) => Stream.value(
            members ?? [member('uid-sara', 'Sara'), member('uid-bob', 'Bob')],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<LedgerPerspective> readPerspective(
    ProviderContainer container, {
    required String? currentPid,
  }) async {
    // Resolve the watched streams (and the upstream ledgerViewProvider) before
    // the synchronous read, so the perspective computes against full data.
    await container.read(eventDetailProvider(eventRef).future);
    await container.read(eventExpensesProvider(eventRef).future);
    await container.read(eventSettlementsProvider(eventRef).future);
    await container.read(groupMembersProvider(groupId).future);
    container.read(ledgerViewProvider(eventRef));
    return container.read(
      ledgerPerspectiveProvider((eventRef: eventRef, currentPid: currentPid)),
    );
  }

  test('single-currency creditor: myLines, roster sign, people count, name',
      () async {
    // Sara pays 30 OMR, equal split → Sara net +15 (creditor), Bob net -15.
    final container = makeContainer(
      expenses: [globalEqual(id: 'x1', payer: 'uid-sara', amount: '30.000')],
    );
    final p = await readPerspective(container, currentPid: 'uid-sara');

    expect(p.myDisplayName, 'Sara');
    expect(p.myLines, [(currency: 'OMR', net: Decimal.fromInt(15))]);

    // Bob owes you → POSITIVE chip (signedAmount = -bobNet = -(-15) = +15).
    expect(p.roster, hasLength(1));
    expect(p.roster.single.participantId, 'uid-bob');
    expect(p.roster.single.displayName, 'Bob'); // resolved, NOT a deferred null
    expect(p.roster.single.signedAmount, Decimal.fromInt(15));
    expect(p.roster.single.currency, 'OMR');

    expect(p.peopleCountByCurrency, {'OMR': 1});
  });

  test('settled event: empty myLines, single zero roster entry, zero count',
      () async {
    // Each pays 10 OMR equal split → both net 0.
    final container = makeContainer(
      expenses: [
        globalEqual(id: 'x-a', payer: 'uid-sara', amount: '10.000'),
        globalEqual(id: 'x-b', payer: 'uid-bob', amount: '10.000'),
      ],
    );
    final p = await readPerspective(container, currentPid: 'uid-sara');

    expect(p.myLines, isEmpty); // ⇒ widget computes isSettled = true
    // A settled-everywhere person keeps a single zero entry so their EVEN chip
    // stays on the strip (the `otherLines.isEmpty` branch).
    expect(p.roster, hasLength(1));
    expect(p.roster.single.participantId, 'uid-bob');
    expect(p.roster.single.signedAmount, Decimal.zero);
    expect(p.roster.single.currency, isNull);
    expect(p.peopleCountByCurrency, {'OMR': 0});
  });

  test('orthogonal axis — multi-currency roster: GCC-first lines, abs-desc sort',
      () async {
    // Bob pays 10 OMR + 30 USD, each equal split → Sara owes 5 OMR + 15 USD.
    final container = makeContainer(
      expenses: [
        globalEqual(id: 'x-omr', payer: 'uid-bob', amount: '10.000'),
        globalEqual(
          id: 'x-usd',
          payer: 'uid-bob',
          amount: '30.00',
          currency: 'USD',
        ),
      ],
    );
    final p = await readPerspective(container, currentPid: 'uid-sara');

    // Sara is a debtor in both buckets; GCC-first ⇒ OMR before USD.
    expect(p.myLines, [
      (currency: 'OMR', net: Decimal.fromInt(-5)),
      (currency: 'USD', net: Decimal.fromInt(-15)),
    ]);

    // One roster entry per (Bob, non-zero bucket); sorted by |signedAmount| desc
    // ⇒ USD (15) before OMR (5). Sara owes Bob ⇒ NEGATIVE chips.
    expect(p.roster.map((r) => (r.currency, r.signedAmount)).toList(), [
      ('USD', Decimal.fromInt(-15)),
      ('OMR', Decimal.fromInt(-5)),
    ]);
    expect(p.roster.every((r) => r.participantId == 'uid-bob'), isTrue);
    expect(p.peopleCountByCurrency, {'OMR': 1, 'USD': 1});
  });

  test('non-participant viewer (currentPid null): empty self, full roster',
      () async {
    final container = makeContainer(
      expenses: [globalEqual(id: 'x1', payer: 'uid-sara', amount: '30.000')],
    );
    final p = await readPerspective(container, currentPid: null);

    expect(p.myDisplayName, isNull); // ⇒ widget applies l10n.ledgerYou
    expect(p.myLines, isEmpty);
    // With no "self" to exclude, BOTH members appear in the roster.
    expect(
      p.roster.map((r) => r.participantId).toSet(),
      {'uid-sara', 'uid-bob'},
    );
  });

  group('memoization (the #628 fix)', () {
    test('two reads with unchanged deps return the IDENTICAL value', () async {
      final container = makeContainer(
        expenses: [globalEqual(id: 'x1', payer: 'uid-sara', amount: '30.000')],
      );
      await readPerspective(container, currentPid: 'uid-sara');
      final p1 = container.read(
        ledgerPerspectiveProvider(
          (eventRef: eventRef, currentPid: 'uid-sara'),
        ),
      );
      final p2 = container.read(
        ledgerPerspectiveProvider(
          (eventRef: eventRef, currentPid: 'uid-sara'),
        ),
      );
      expect(identical(p1, p2), isTrue,
          reason: 'a chip-tap setState must not recompute the perspective');
    });

    test('a different currentPid key yields a distinct perspective', () async {
      final container = makeContainer(
        expenses: [globalEqual(id: 'x1', payer: 'uid-sara', amount: '30.000')],
      );
      final sara = await readPerspective(container, currentPid: 'uid-sara');
      final bob = container.read(
        ledgerPerspectiveProvider((eventRef: eventRef, currentPid: 'uid-bob')),
      );
      expect(identical(sara, bob), isFalse);
      // Sara is owed 15; Bob owes 15 — opposite signs prove the key discriminates.
      expect(sara.myLines, [(currency: 'OMR', net: Decimal.fromInt(15))]);
      expect(bob.myLines, [(currency: 'OMR', net: Decimal.fromInt(-15))]);
    });
  });
}
