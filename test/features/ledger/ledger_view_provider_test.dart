import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/providers/ledger_view_provider.dart';

/// #106 — the hoisted [ledgerViewProvider] must reproduce the former inline
/// `_Body.build` logic exactly: memoize the balance pass, preserve the #249
/// former-member universe, and store settlement names with the l10n fallback
/// DEFERRED (null) rather than resolved.
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

  Future<LedgerView> readView(
    ProviderContainer container, {
    List<Expense> expenses = const [],
    List<Settlement> settlements = const [],
  }) async {
    // Resolve every watched stream before reading the synchronous provider, so
    // it computes against full data (not the transient empty-degrade path).
    await container.read(eventDetailProvider(eventRef).future);
    await container.read(eventExpensesProvider(eventRef).future);
    await container.read(eventSettlementsProvider(eventRef).future);
    await container.read(groupMembersProvider(groupId).future);
    return container.read(ledgerViewProvider(eventRef));
  }

  ProviderContainer makeContainer({
    List<Expense> expenses = const [],
    List<Settlement> settlements = const [],
    List<GroupMember>? members,
  }) {
    final container = ProviderContainer(
      overrides: [
        eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
        eventExpensesProvider(eventRef).overrideWith((ref) => Stream.value(expenses)),
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

  test('memoizes: two reads with unchanged deps return identical balances', () async {
    final container = makeContainer(
      expenses: [
        Expense(
          id: 'x1',
          tripId: eventId,
          payerParticipantId: 'uid-sara',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 1, 11),
          createdBy: 'uid-sara',
          currency: 'OMR',
        ),
      ],
    );
    await readView(container);
    final v1 = container.read(ledgerViewProvider(eventRef));
    final v2 = container.read(ledgerViewProvider(eventRef));
    expect(identical(v1.balances, v2.balances), isTrue);
  });

  test('former-member payer + departed split-recipient survive the hoist', () async {
    final container = makeContainer(
      members: [
        member('uid-sara', 'Sara'),
        member('uid-bob', 'Bob'),
        member('uid-omar', 'Omar', tombstone: true),
      ],
      expenses: [
        // (a) paid by a departed member → former-member label.
        Expense(
          id: 'x-omar',
          tripId: eventId,
          payerParticipantId: 'uid-omar',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 1, 11),
          createdBy: 'uid-omar',
          currency: 'OMR',
        ),
        // (b) shares split that owes a departed member a share (#249 universe).
        Expense(
          id: 'x-split',
          tripId: eventId,
          payerParticipantId: 'uid-sara',
          amount: Decimal.parse('30.000'),
          scope: ExpenseScope.global,
          splitMode: SplitMode.shares,
          splitDistribution: {
            'uid-sara': Decimal.one,
            'uid-bob': Decimal.one,
            'uid-omar': Decimal.one,
          },
          createdAt: DateTime(2026, 1, 12),
          createdBy: 'uid-sara',
          currency: 'OMR',
        ),
      ],
    );
    final view = await readView(container);

    expect(view.expensePayerDisplayNames['x-omar'], 'Omar (former member)');
    expect(
      view.balances.where((b) => b.participantId == 'uid-omar'),
      isNotEmpty,
      reason: 'departed split-recipient must be folded into the universe (#249)',
    );
  });

  test('settlementDisplayNames stores the four party combinations exactly', () async {
    Settlement settle(
      String id, {
      String? payerId,
      String? payerName,
    }) =>
        Settlement(
          id: id,
          tripId: eventId,
          payerParticipantId: payerId,
          recipientParticipantId: 'uid-bob',
          recipientName: 'Bob',
          payerName: payerName,
          amount: Decimal.parse('5.000'),
          settledAt: DateTime(2026, 1, 13),
        );

    final container = makeContainer(
      settlements: [
        settle('s-a'), // null participant, null name
        settle('s-b', payerName: 'Sam'), // null participant, persisted name
        settle('s-c', payerId: 'uid-sara', payerName: 'Ignored'), // resolvable
        settle('s-d', payerId: 'uid-ghost', payerName: 'Sam'), // unresolvable
      ],
    );
    final view = await readView(container);

    // (a) unknown party → null (widget substitutes l10n.ledgerSomeone later).
    expect(view.settlementDisplayNames['s-a']!.payerName, isNull);
    // (b) no participant id → persisted name stored verbatim.
    expect(view.settlementDisplayNames['s-b']!.payerName, 'Sam');
    // (c) resolvable participant → resolved name, NOT the raw payerName.
    expect(view.settlementDisplayNames['s-c']!.payerName, 'Sara');
    // (d) unresolvable participant + persisted name → former-member label.
    expect(view.settlementDisplayNames['s-d']!.payerName, 'Sam (former member)');
  });
}
