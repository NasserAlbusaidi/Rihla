import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

// #366 parity mirror — the Dart half of the aggregate fixtures P1-P5 in
// functions/test/triggers/balanceAggregator.test.ts (hand-ported constants
// cross-referenced by case id, the delete_group_balance_parity_test.dart
// convention; Dart uses major-unit Decimals, TS asserts milli ints ×1000).
//
// The server doc's `netMilli` mirrors [computeGroupBalances].balances
// netBalance and `perEventNetMilli` mirrors .perEventBreakdown — these tests
// pin the exact client values the server is REQUIRED to reproduce. Like the
// deleteGroup parity file, this passes against lib/ today by design; its RED
// value is differential (a divergence on either side gets caught by one of
// the two suites going red).
//
// Axes (verification principle #7 — orthogonal to the read-perf axis #366
// ships on): P1 identity (former actor in net, NOT in drill-down) +
// settlements (event vs group scope), P2 settlement-only, P3 rounding
// remainder (alphabetically-last), P4 in-tolerance exact residual, P5
// negative-legacy equal-split fallback.

void main() {
  GroupMember member(String uid, {bool isTombstone = false}) => GroupMember(
    id: uid,
    groupId: 'g1',
    userId: uid,
    displayName: uid,
    role: 'MEMBER',
    isTombstone: isTombstone,
    joinedAt: DateTime(2026),
  );

  Event event(String id, List<String> participantIds) => Event(
    id: id,
    name: id,
    type: EventType.trip,
    groupId: 'g1',
    createdBy: participantIds.isEmpty ? 'alice' : participantIds.first,
    participantIds: participantIds,
    participantNames: {for (final uid in participantIds) uid: uid},
    modules: const EventModules(ledger: true),
    createdAt: DateTime(2026),
  );

  Expense expense({
    required String amount,
    required String payerId,
    SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    String eventId = 'e1',
  }) => Expense(
    id: 'x-$amount-$payerId',
    tripId: eventId,
    payerParticipantId: payerId,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    splitMode: splitMode,
    splitDistribution: splitDistribution,
    createdAt: DateTime(2026),
    currency: 'OMR',
  );

  Settlement settlement({
    required String payerId,
    required String recipientId,
    required String amount,
    String eventId = 'e1',
  }) => Settlement(
    id: 's-$payerId-$amount',
    tripId: eventId,
    payerParticipantId: payerId,
    recipientParticipantId: recipientId,
    amount: Decimal.parse(amount),
    settledAt: DateTime(2026),
  );

  // #382 PR-1 interim parity statement: the client fold now buckets per
  // currency while the v1 aggregate doc stays flat until PR-3. Every case
  // here is single-currency OMR, so the sole 'OMR' bucket must reproduce the
  // pinned netMilli values byte-for-byte. PR-3 introduces the bucketed v2 doc.
  Decimal netFor(GroupBalances balances, String uid) => balances
      .balances['OMR']!
      .singleWhere((b) => b.participantId == uid)
      .netBalance;

  group('aggregate doc parity (#366 — mirrors balanceAggregator.test.ts)', () {
    test('P1: former-actor payer + both settlement scopes — net vs drill-down', () {
      final result = computeGroupBalances(
        events: [event('e1', ['alice', 'bob'])],
        members: [
          member('alice'),
          member('bob'),
          member('carol', isTombstone: true),
        ],
        allExpenses: [
          // 9.000 paid by the tombstoned former member, equal split, global.
          expense(amount: '9.000', payerId: 'carol'),
        ],
        allEventSettlements: [
          settlement(payerId: 'alice', recipientId: 'bob', amount: '1.000'),
        ],
        groupSettlements: [
          settlement(payerId: 'bob', recipientId: 'alice', amount: '2.000'),
        ],
      );

      // netMilli mirror: {alice: -4000, bob: -2000, carol: 6000}.
      expect(netFor(result, 'alice'), Decimal.parse('-4.000'));
      expect(netFor(result, 'bob'), Decimal.parse('-2.000'));
      expect(netFor(result, 'carol'), Decimal.parse('6.000'));

      // perEventNetMilli mirror: {e1: {alice: -3500, bob: -5500}} — the
      // drill-down universe is participantIds-only: carol's payment DROPPED,
      // the group settlement NOT folded, carol has NO slice.
      expect(
        result.perEventBreakdown['alice']!['e1'],
        Decimal.parse('-3.500'),
      );
      expect(result.perEventBreakdown['bob']!['e1'], Decimal.parse('-5.500'));
      expect(result.perEventBreakdown.containsKey('carol'), isFalse);
    });

    test('P2: group-scope settlement moves net but NO per-event slice', () {
      final result = computeGroupBalances(
        events: [event('e1', ['alice', 'bob'])],
        members: [member('alice'), member('bob')],
        allExpenses: const [],
        allEventSettlements: const [],
        groupSettlements: [
          settlement(payerId: 'alice', recipientId: 'bob', amount: '2.500'),
        ],
      );

      expect(netFor(result, 'alice'), Decimal.parse('2.500'));
      expect(netFor(result, 'bob'), Decimal.parse('-2.500'));
      expect(result.perEventBreakdown['alice']!['e1'], Decimal.zero);
      expect(result.perEventBreakdown['bob']!['e1'], Decimal.zero);
    });

    test('P3: 3-way equal split of 0.100 — alphabetically-last absorbs', () {
      final result = computeGroupBalances(
        events: [event('e1', ['alice', 'bob', 'carol'])],
        members: [member('alice'), member('bob'), member('carol')],
        allExpenses: [expense(amount: '0.100', payerId: 'alice')],
        allEventSettlements: const [],
        groupSettlements: const [],
      );

      // milli mirror: {alice: 67, bob: -33, carol: -34}.
      expect(netFor(result, 'alice'), Decimal.parse('0.067'));
      expect(netFor(result, 'bob'), Decimal.parse('-0.033'));
      expect(netFor(result, 'carol'), Decimal.parse('-0.034'));
    });

    test('P4: in-tolerance exact residual closes onto the last absorber', () {
      final result = computeGroupBalances(
        events: [event('e1', ['alice', 'bob'])],
        members: [member('alice'), member('bob')],
        allExpenses: [
          expense(
            amount: '10.000',
            payerId: 'alice',
            splitMode: SplitMode.exact,
            splitDistribution: {
              'alice': Decimal.parse('4.000'),
              'bob': Decimal.parse('5.999'),
            },
          ),
        ],
        allEventSettlements: const [],
        groupSettlements: const [],
      );

      // milli mirror: {alice: 6000, bob: -6000} (residual +0.001 → bob).
      expect(netFor(result, 'alice'), Decimal.parse('6.000'));
      expect(netFor(result, 'bob'), Decimal.parse('-6.000'));
    });

    test('P5: negative legacy exact value falls back to equal split', () {
      final result = computeGroupBalances(
        events: [event('e1', ['alice', 'bob'])],
        members: [member('alice'), member('bob')],
        allExpenses: [
          expense(
            amount: '10.000',
            payerId: 'alice',
            splitMode: SplitMode.exact,
            splitDistribution: {
              'alice': Decimal.parse('-1.000'),
              'bob': Decimal.parse('11.000'),
            },
          ),
        ],
        allEventSettlements: const [],
        groupSettlements: const [],
      );

      // milli mirror: {alice: 5000, bob: -5000}.
      expect(netFor(result, 'alice'), Decimal.parse('5.000'));
      expect(netFor(result, 'bob'), Decimal.parse('-5.000'));
    });
  });
}
