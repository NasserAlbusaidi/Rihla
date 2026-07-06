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

/// #998 — roster chips show each member's OWN event net ("their standing"),
/// not the negation of it. The old `signedAmount = -theirNet` claimed a
/// pairwise "they owe you / you owe them" reading that is only true in
/// 2-person events; for 3+ members the negated value is the member's position
/// vs the GROUP, and the sign flip actively misleads (a rust chip suggested a
/// you→them debt no settlement plan would ever route).
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  GroupMember member(String uid, String name) => GroupMember(
        id: uid,
        groupId: groupId,
        userId: uid,
        displayName: name,
        role: 'MEMBER',
        joinedAt: DateTime(2026, 1, 10),
      );

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Three Way Trip',
    type: EventType.trip,
    createdBy: 'uid-amal',
    participantIds: const ['uid-amal', 'uid-badr', 'uid-cyra'],
    participantNames: const {
      'uid-amal': 'Amal',
      'uid-badr': 'Badr',
      'uid-cyra': 'Cyra',
    },
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  Expense globalEqual({
    required String id,
    required String payer,
    required String amount,
  }) =>
      Expense(
        id: id,
        tripId: eventId,
        payerParticipantId: payer,
        amount: Decimal.parse(amount),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 11),
        createdBy: payer,
        currency: 'OMR',
      );

  ProviderContainer makeContainer({required List<Expense> expenses}) {
    final container = ProviderContainer(
      overrides: [
        eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
        eventExpensesProvider(eventRef)
            .overrideWith((ref) => Stream.value(expenses)),
        eventSettlementsProvider(eventRef)
            .overrideWith((ref) => Stream.value(const <Settlement>[])),
        groupMembersProvider(groupId).overrideWith(
          (ref) => Stream.value([
            member('uid-amal', 'Amal'),
            member('uid-badr', 'Badr'),
            member('uid-cyra', 'Cyra'),
          ]),
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
    await container.read(eventDetailProvider(eventRef).future);
    await container.read(eventExpensesProvider(eventRef).future);
    await container.read(eventSettlementsProvider(eventRef).future);
    await container.read(groupMembersProvider(groupId).future);
    container.read(ledgerViewProvider(eventRef));
    return container.read(
      ledgerPerspectiveProvider((eventRef: eventRef, currentPid: currentPid)),
    );
  }

  test('3-member event: each roster chip is that member\'s OWN net (#998)',
      () async {
    // Amal pays 30 equal (each owes 10) → Amal +20, Badr −10, Cyra −10.
    // Cyra pays 24 equal (each owes 8)  → Cyra +16−... net effect below.
    // Final nets: Amal +12, Badr −18, Cyra +6 (sum 0).
    final container = makeContainer(
      expenses: [
        globalEqual(id: 'x1', payer: 'uid-amal', amount: '30.000'),
        globalEqual(id: 'x2', payer: 'uid-cyra', amount: '24.000'),
      ],
    );
    final p = await readPerspective(container, currentPid: 'uid-amal');

    expect(p.myLines, [(currency: 'OMR', net: Decimal.fromInt(12))]);

    final byPid = {for (final r in p.roster) r.participantId: r};
    // Badr owes the group 18 → his standing is NEGATIVE (rust chip).
    expect(byPid['uid-badr']!.signedAmount, Decimal.fromInt(-18));
    // Cyra is owed 6 by the group → her standing is POSITIVE (sage chip).
    // Under the old −net framing this chip showed −6 and read as a you→Cyra
    // debt that no settlement plan would ever produce.
    expect(byPid['uid-cyra']!.signedAmount, Decimal.fromInt(6));

    // Sort is by |signedAmount| descending, unchanged.
    expect(
      p.roster.map((r) => r.participantId).toList(),
      ['uid-badr', 'uid-cyra'],
    );
  });
}
