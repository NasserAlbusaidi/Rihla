import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

// #366 parity mirror — the Dart half of the aggregate fixtures P1-P6 in
// functions/test/triggers/balanceAggregator.test.ts (hand-ported constants
// cross-referenced by case id, the delete_group_balance_parity_test.dart
// convention; Dart uses major-unit Decimals, TS asserts milli ints ×1000
// per bucket).
//
// The v2 doc's `netMilliByCurrency` mirrors [computeGroupBalances].balances
// netBalance per bucket and `perEventNetMilliByCurrency` mirrors
// .perEventBreakdown (eventId → currency → uid, #382 PR-3) — these tests pin
// the exact client values the server is REQUIRED to reproduce. Like the
// deleteGroup parity file, this passes against lib/ today by design; its RED
// value is differential (a divergence on either side gets caught by one of
// the two suites going red).
//
// Axes (verification principle #7 — orthogonal to the read-perf axis #366
// ships on): P1 identity (former actor in net, NOT in drill-down) +
// settlements (event vs group scope), P2 settlement-only, P3 rounding
// remainder (alphabetically-last), P4 in-tolerance exact residual, P5
// negative-legacy equal-split fallback, P6 currency (independent buckets,
// no cross-currency netting — #382).

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
    String currency = 'OMR',
  }) => Expense(
    id: 'x-$amount-$payerId',
    tripId: eventId,
    payerParticipantId: payerId,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    splitMode: splitMode,
    splitDistribution: splitDistribution,
    createdAt: DateTime(2026),
    currency: currency,
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

  // #382 PR-3 parity statement: client fold AND the v2 aggregate doc are both
  // per-currency. Each bucket must reproduce the pinned
  // netMilliByCurrency[ccy] values byte-for-byte (per-bucket ×1000).
  Decimal netFor(
    GroupBalances balances,
    String uid, {
    String currency = 'OMR',
  }) => balances.balances[currency]!
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

      // netMilliByCurrency mirror: {OMR: {alice: -4000, bob: -2000,
      // carol: 6000}}.
      expect(netFor(result, 'alice'), Decimal.parse('-4.000'));
      expect(netFor(result, 'bob'), Decimal.parse('-2.000'));
      expect(netFor(result, 'carol'), Decimal.parse('6.000'));

      // perEventNetMilliByCurrency mirror: {e1: {OMR: {alice: -3500,
      // bob: -5500}}} — the drill-down universe is participantIds-only:
      // carol's payment DROPPED, the group settlement NOT folded, carol has
      // NO slice.
      expect(result.perEventBreakdown['alice']!['e1'], {
        'OMR': Decimal.parse('-3.500'),
      });
      expect(result.perEventBreakdown['bob']!['e1'], {
        'OMR': Decimal.parse('-5.500'),
      });
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
      // No-money event → explicit synthetic-OMR zero slice (D10).
      expect(result.perEventBreakdown['alice']!['e1'], {'OMR': Decimal.zero});
      expect(result.perEventBreakdown['bob']!['e1'], {'OMR': Decimal.zero});
    });

    test('P3: 3-way equal split of 0.100 — alphabetically-last absorbs', () {
      final result = computeGroupBalances(
        events: [event('e1', ['alice', 'bob', 'carol'])],
        members: [member('alice'), member('bob'), member('carol')],
        allExpenses: [expense(amount: '0.100', payerId: 'alice')],
        allEventSettlements: const [],
        groupSettlements: const [],
      );

      // netMilliByCurrency.OMR mirror: {alice: 67, bob: -33, carol: -34}.
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

      // netMilliByCurrency.OMR mirror: {alice: 6000, bob: -6000} (residual
      // +0.001 → bob).
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

      // netMilliByCurrency.OMR mirror: {alice: 5000, bob: -5000}.
      expect(netFor(result, 'alice'), Decimal.parse('5.000'));
      expect(netFor(result, 'bob'), Decimal.parse('-5.000'));
    });

    test('P6: two-currency event buckets independently — OMR settled, USD '
        'outstanding (mirrors deleteGroup parity case 5) (#382)', () {
      // alice pays 10.000 OMR global-equal {alice, bob} → alice +5.000,
      // bob −5.000; bob→alice 5.000 OMR event settlement zeroes the OMR
      // bucket. bob pays 6.00 USD global-equal → bob +3.00, alice −3.00 with
      // no USD settlement. The buckets NEVER net across currencies (no FX).
      final result = computeGroupBalances(
        events: [event('e1', ['alice', 'bob'])],
        members: [member('alice'), member('bob')],
        allExpenses: [
          expense(amount: '10.000', payerId: 'alice'),
          expense(amount: '6.00', payerId: 'bob', currency: 'USD'),
        ],
        allEventSettlements: [
          settlement(payerId: 'bob', recipientId: 'alice', amount: '5.000'),
        ],
        groupSettlements: const [],
      );

      // Exactly two independent buckets — no cross-currency bleed.
      expect(result.balances.keys.toSet(), {'OMR', 'USD'});

      // netMilliByCurrency mirror (per-bucket ×1000):
      //   {OMR: {alice: 0, bob: 0}, USD: {alice: -3000, bob: 3000}}.
      expect(netFor(result, 'alice'), Decimal.zero);
      expect(netFor(result, 'bob'), Decimal.zero);
      expect(
        netFor(result, 'alice', currency: 'USD'),
        Decimal.parse('-3.00'),
      );
      expect(
        netFor(result, 'bob', currency: 'USD'),
        Decimal.parse('3.00'),
      );

      // perEventNetMilliByCurrency mirror (eventId-major, D2):
      //   {e1: {OMR: {alice: 0, bob: 0}, USD: {alice: -3000, bob: 3000}}}.
      expect(result.perEventBreakdown['alice']!['e1'], {
        'OMR': Decimal.zero,
        'USD': Decimal.parse('-3.00'),
      });
      expect(result.perEventBreakdown['bob']!['e1'], {
        'OMR': Decimal.zero,
        'USD': Decimal.parse('3.00'),
      });
    });
  });
}
