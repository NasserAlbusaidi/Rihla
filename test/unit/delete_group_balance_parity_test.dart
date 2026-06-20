import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

// Cluster `server-deletegroup-callable` (#190), spec §8.4-B.
//
// Cross-implementation parity ORACLE: the Dart client `BalanceCalculator` is
// the reference the TS server `deleteGroup` balance gate (§2.4) must reproduce
// EXACTLY. These assertions pin the per-UID net the server is REQUIRED to
// produce for the same fixtures and guard R1 (gate divergence from the client)
// across the four axes the gate can get wrong:
//   case 1  — the §8.1 case 7/8 happy fixtures net to all-zero (settled parity).
//   case 2  — out-of-universe `splitDistribution` ghost is DROPPED, not
//             redistributed (identity axis; §8.1 case 12 mirror; HARD REQ #4).
//   case 3  — percent split decodes via /1000 (60.0/40.0), NOT the 0..100-raw
//             fallback to equal split (money axis; §8.1 case 9/10; HARD REQ #3).
//   case 4  — equal-split (no `splitDistribution`) over the FULL universe
//             including a re-injected former actor `gone` (identity axis,
//             orthogonal to case 2's distribution branch; Gate R1 finding #2;
//             HARD REQ #4 / §2.4 step 5).
//
// NB on TDD-RED: unlike the callable/rules/client-routing tests in this
// cluster (RED because the surface does not exist yet), this file asserts the
// CURRENT Dart calculator's contract — it is the oracle the server must copy,
// so it passes against `lib/` today by design. Its RED value is differential:
// it pins the exact nets so a server (or a future Dart regression) that takes
// the "single global map", the 0..100-raw percent read, or `participantIds`-
// only equal split DIVERGES and is caught. Verification principle #7: cases 2
// and 4 exercise the identity axis the clean/outstanding cases never touch.

void main() {
  // The per-event universe the server builds (group_balance_provider.dart
  // :243-258) becomes `participants` here. A former actor (tombstoned member
  // who is a payer/settlement actor) is re-injected into that universe by
  // :234 — modelled by listing it as a participant below.
  Participant participant(String id) => Participant(
    id: id,
    tripId: 'event-1',
    role: ParticipantRole.member,
    joinedAt: DateTime(2026),
    displayName: id,
  );

  Expense expense({
    required String amount,
    required SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    String payerId = 'owner',
    ExpenseScope scope = ExpenseScope.global,
    List<String>? customSplitParticipants,
    String currency = 'OMR',
  }) {
    return Expense(
      id: 'expense-$amount-${splitMode?.storageKey ?? 'legacy'}',
      tripId: 'event-1',
      payerParticipantId: payerId,
      amount: Decimal.parse(amount),
      scope: scope,
      customSplitParticipants: customSplitParticipants,
      splitMode: splitMode,
      splitDistribution: splitDistribution,
      createdAt: DateTime(2026),
      currency: currency,
    );
  }

  Decimal netFor(List<UserBalance> balances, String id) =>
      balances.singleWhere((b) => b.participantId == id).netBalance;

  // #382 PR-1 interim parity statement: the client calculator now returns
  // per-currency buckets while the TS oracle (recomputeNet) stays flat until
  // PR-2. Every case here is single-currency OMR, so the client's sole 'OMR'
  // bucket must reproduce the pinned flat server values byte-for-byte. PR-2
  // buckets the server and grows this suite with mixed-currency cases.
  group('deleteGroup gate parity (#190 §8.4-B)', () {
    test(
      'case 1: §8.1 case 7/8 fixtures net to all-zero (client and server agree '
      'on "settled")',
      () {
        // owner pays 12.000, exact split 6.000/6.000; member settles 6.000.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '12.000',
              splitMode: SplitMode.exact,
              scope: ExpenseScope.custom,
              customSplitParticipants: ['owner', 'member'],
              splitDistribution: {
                'owner': Decimal.parse('6.000'),
                'member': Decimal.parse('6.000'),
              },
            ),
          ],
          settlements: [
            Settlement(
              id: 's1',
              tripId: 'event-1',
              payerParticipantId: 'member',
              recipientParticipantId: 'owner',
              amount: Decimal.parse('6.000'),
              settledAt: DateTime(2026),
            ),
          ],
        )['OMR']!;

        expect(netFor(balances, 'owner'), Decimal.zero);
        expect(netFor(balances, 'member'), Decimal.zero);
      },
    );

    test(
      'case 1b: in-tolerance exact residual nets to all-zero — the value the '
      'server allocateExact MUST match after its residual close-out (#223)',
      () {
        // owner pays 10.000, exact {owner:5.000, member:5.001} (sum 10.001,
        // +0.001 IN-tolerance drift — not the out-of-tolerance equal fallback).
        // The client closes the -0.001 residual onto the alphabetically-last
        // absorbable recipient (owner: 5.000 → 4.999), so member owes exactly
        // 5.001; member settles 5.001 → all-zero. The TS deleteGroup gate
        // (allocateExact) returned the distribution verbatim in-tolerance, so it
        // kept owner owed 5.000 → owner net -0.001 → it refused to delete a
        // group the client shows as settled. This pins the net the server must
        // reach once it mirrors the close-out.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '10.000',
              splitMode: SplitMode.exact,
              scope: ExpenseScope.custom,
              customSplitParticipants: ['owner', 'member'],
              splitDistribution: {
                'owner': Decimal.parse('5.000'),
                'member': Decimal.parse('5.001'),
              },
            ),
          ],
          settlements: [
            Settlement(
              id: 's1',
              tripId: 'event-1',
              payerParticipantId: 'member',
              recipientParticipantId: 'owner',
              amount: Decimal.parse('5.001'),
              settledAt: DateTime(2026),
            ),
          ],
        )['OMR']!;

        expect(netFor(balances, 'owner'), Decimal.zero);
        expect(netFor(balances, 'member'), Decimal.zero);
      },
    );

    test(
      'case 1c: negative EXACT split value → equal-split fallback — the net the '
      'server allocateExact MUST match after its #270 negative guard',
      () {
        // owner pays 10.000, exact {owner:-1.000, member:11.000} (sum 10.000 ==
        // amount → IN-tolerance, so the tolerance guard would NOT fire). A
        // legacy/Admin doc could carry this; rules block new ones. The client
        // _allocateExact negative-value guard fires FIRST → equal split
        // (owner 5.000 / member 5.000). Expense-only (no settlement) so the
        // asserted net IS the differential oracle: owner +5.000, member -5.000.
        // A server that keeps the distribution verbatim in-tolerance instead
        // reads owner owed -1.000 / member 11.000 → owner +11.000 → divergent.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '10.000',
              splitMode: SplitMode.exact,
              scope: ExpenseScope.custom,
              customSplitParticipants: ['owner', 'member'],
              splitDistribution: {
                'owner': Decimal.parse('-1.000'),
                'member': Decimal.parse('11.000'),
              },
            ),
          ],
        )['OMR']!;

        expect(netFor(balances, 'owner'), Decimal.parse('5.000'));
        expect(netFor(balances, 'member'), Decimal.parse('-5.000'));
      },
    );

    test(
      'case 1d: negative SHARES split value → equal-split fallback (#270)',
      () {
        // owner pays 8.000, shares {owner:-1, member:5} (totalShares 4 > 0, so
        // the invalid-shares guard would NOT fire — it reaches _allocateWeighted
        // without the negative guard). The client negative guard equal-splits
        // 8.000 → owner 4.000 / member 4.000. Expense-only: owner +4.000,
        // member -4.000. A server without the guard weights over [member, owner]
        // → member 10.000, owner (last) -2.000 → owner +10.000 → divergent.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '8.000',
              payerId: 'owner',
              splitMode: SplitMode.shares,
              splitDistribution: {
                'owner': Decimal.fromInt(-1),
                'member': Decimal.fromInt(5),
              },
            ),
          ],
        )['OMR']!;

        expect(netFor(balances, 'owner'), Decimal.parse('4.000'));
        expect(netFor(balances, 'member'), Decimal.parse('-4.000'));
      },
    );

    test(
      'case 1e: negative PERCENT split value → equal-split fallback (#270)',
      () {
        // owner pays 10.000, percent {owner:-20.0, member:120.0} (sum 100 →
        // IN-tolerance, so the drift guard would NOT fire). The client negative
        // guard equal-splits 10.000 → 5.000 / 5.000. Expense-only: owner +5.000,
        // member -5.000. A server without the guard weights over [member, owner]
        // → member 12.000, owner (last) -2.000 → owner +12.000 → divergent.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '10.000',
              payerId: 'owner',
              splitMode: SplitMode.percent,
              splitDistribution: {
                'owner': Decimal.parse('-20.0'),
                'member': Decimal.parse('120.0'),
              },
            ),
          ],
        )['OMR']!;

        expect(netFor(balances, 'owner'), Decimal.parse('5.000'));
        expect(netFor(balances, 'member'), Decimal.parse('-5.000'));
      },
    );

    test(
      'case 2: out-of-universe ghost share is DROPPED, not redistributed '
      '(identity axis, distribution branch — §8.1 case 12)',
      () {
        // participants = the per-event universe the server builds; `ghost` is
        // excluded (not a participantId, not a payer/settlement actor).
        // splitDistribution carries an extra `ghost` key. #191 now rejects new
        // forged writes like this at the rules boundary; this parity test still
        // documents how legacy/Admin-written malformed docs are read. The
        // client drops the ghost key; the server gate MUST too.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '6.000',
              payerId: 'owner',
              splitMode: SplitMode.shares,
              splitDistribution: {
                'owner': Decimal.fromInt(1),
                'member': Decimal.fromInt(1),
                'ghost': Decimal.fromInt(1),
              },
            ),
          ],
        )['OMR']!;

        // shares over sorted keys [ghost, member, owner] = 2.000 each, but
        // owedMap is seeded only for the universe {owner, member} → ghost's
        // 2.000 share is dropped → owner +4.000, member -2.000, NO ghost entry.
        // A "single global map" server would instead credit ghost -2.000
        // (grand sum 0) and wrongly report SETTLED.
        expect(netFor(balances, 'owner'), Decimal.parse('4.000'));
        expect(netFor(balances, 'member'), Decimal.parse('-2.000'));
        expect(
          balances.any((b) => b.participantId == 'ghost'),
          isFalse,
          reason:
              'ghost is outside the per-event universe and must not appear in '
              'the net map (#190 Gate finding 2 / §8.1 case 12).',
        );
      },
    );

    test(
      'case 3: percent split decodes via /1000 (60.0/40.0), NOT the 0..100-raw '
      'fallback (money axis — §8.1 case 9/10, HARD REQ #3)',
      () {
        // 60/40 percent expense of 10.000 paid by owner. The persisted ints are
        // 60000/40000 (value x 1000); the client decodes them to 60.0/40.0
        // humanPercent. Weighted over sorted keys [member, owner], denominator
        // 100: member (non-last) = 10.000 * 40/100 = 4.000; owner (last) =
        // 10.000 - 4.000 = 6.000.
        //   owner net = paid 10.000 - owed 6.000 = +4.000
        //   member net = 0 - 4.000 = -4.000
        // A 0..100-raw server reading 60000/40000 directly hits |sum-100|>0.001
        // and falls back to EQUAL split (5.000/5.000) → owner +5.000, member
        // -5.000 → divergent.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '10.000',
              payerId: 'owner',
              splitMode: SplitMode.percent,
              splitDistribution: {
                'owner': Decimal.parse('60.0'),
                'member': Decimal.parse('40.0'),
              },
            ),
          ],
        )['OMR']!;

        expect(
          netFor(balances, 'owner'),
          Decimal.parse('4.000'),
          reason:
              'percent must decode to 60.0/40.0 (owed 6.000), not fall back to '
              'equal 5.000 — the 0..100-raw read bug (#190 HARD REQ #3).',
        );
        expect(netFor(balances, 'member'), Decimal.parse('-4.000'));
      },
    );

    test(
      'case 4: equal-split (no splitDistribution) over the FULL universe '
      'including a re-injected former actor (identity axis — Gate R1 finding 2, '
      'HARD REQ #4 / §2.4 step 5)',
      () {
        // The universe is {owner, gone}; `gone` is a former actor (a tombstoned
        // member who paid/received in the event) the server re-injects via
        // group_balance_provider.dart:234, so the caller passes it in the
        // participant set. A `scope:global`, `equally`/no-distribution expense
        // of 6.000 paid by owner splits equally over the WHOLE universe:
        //   perHead 3.000 → owner net = paid 6.000 - owed 3.000 = +3.000;
        //   gone net = 0 - 3.000 = -3.000.
        // A server that splits the equal/global branch over event.participantIds
        // = ['owner'] alone owes owner the full 6.000 → owner +6.000, no `gone`
        // entry → divergent. This is the precise path §2.4 step 5 gets wrong if
        // it uses event.participantIds instead of participantUniverse.
        final balances = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('gone')],
          expenses: [
            expense(
              amount: '6.000',
              payerId: 'owner',
              splitMode: null, // no distribution → equal split branch
              scope: ExpenseScope.global,
            ),
          ],
        )['OMR']!;

        expect(
          netFor(balances, 'owner'),
          Decimal.parse('3.000'),
          reason:
              'equal/global split must distribute over the full universe '
              '{owner, gone}, not participantIds alone (#190 Gate finding 2).',
        );
        expect(
          netFor(balances, 'gone'),
          Decimal.parse('-3.000'),
          reason:
              'the re-injected former actor `gone` must receive an equal share '
              '(#190 HARD REQ #4 equal-split universe).',
        );
      },
    );

    test(
      'case 4b: terminating sub-subunit equal split quantizes to whole subunits '
      '— EXACT per-head distribution, not just conservation (#596)',
      () {
        // 2.900 OMR global-equal over 8 → 2.900 / 8 = 0.3625, a FINITE rational.
        // The server allocateEqual (groupNetBalance.ts:152 `quantize`,
        // ROUND_DOWN) bills 7 heads 0.362 and the alphabetically-last 0.366
        // (absorbing the 0.004 remainder). The client MUST reproduce this
        // byte-for-byte. Pre-#596 the client kept the raw 0.3625 for every head:
        // conservation still held (0.3625 × 8 == 2.900) so the existing oracle
        // cases — which only assert nets that happen to be whole — never caught
        // it. This case pins the EXACT per-head share (the axis the bug slipped
        // through) and that every net is a whole number of baisa.
        const eight = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
        final balances = BalanceCalculator.calculateBalances(
          participants: [for (final id in eight) participant(id)],
          expenses: [
            expense(
              amount: '2.900',
              payerId: 'a',
              splitMode: null, // no distribution → equal-split branch
              scope: ExpenseScope.global,
            ),
          ],
        )['OMR']!;

        Decimal owedFor(String id) =>
            balances.singleWhere((b) => b.participantId == id).totalOwed;

        for (final id in const ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
          expect(
            owedFor(id),
            Decimal.parse('0.362'),
            reason: '$id must owe the server-quantized 0.362, not 0.3625',
          );
        }
        expect(
          owedFor('h'),
          Decimal.parse('0.366'),
          reason: 'alphabetically-last absorbs the 0.004 remainder',
        );
        // No half-baisa residue may survive on any net.
        for (final b in balances) {
          expect(
            (b.netBalance * Decimal.fromInt(1000)).isInteger,
            isTrue,
            reason: '${b.participantId} net ${b.netBalance} is not whole-baisa',
          );
        }
        // Conservation (the check that ALSO passed pre-fix — kept as a fence).
        expect(
          balances.fold(Decimal.zero, (s, b) => s + b.netBalance),
          Decimal.zero,
        );
      },
    );

    test(
      'case 5: a two-currency event buckets independently — OMR settled, USD '
      'outstanding (the #382 PR-2 per-bucket gate must refuse) (#382)',
      () {
        // owner pays 10.000 OMR global-equal {owner, member} → owner +5.000,
        // member −5.000; member→owner 5.000 OMR settles the OMR bucket to zero.
        // member pays 6.00 USD global-equal → member +3.00, owner −3.00; no USD
        // settlement, so the USD bucket stays non-zero. The buckets NEVER net
        // across currencies (no FX): the server recomputeNet must reproduce the
        // SAME two independent buckets, so its per-bucket gate refuses deletion
        // on the live USD debt even though OMR is settled (orthogonal axis:
        // currency + settlements, vs cases 2/4's identity axis).
        final buckets = BalanceCalculator.calculateBalances(
          participants: [participant('owner'), participant('member')],
          expenses: [
            expense(
              amount: '10.000',
              splitMode: null,
              scope: ExpenseScope.global,
              currency: 'OMR',
            ),
            expense(
              amount: '6.00',
              payerId: 'member',
              splitMode: null,
              scope: ExpenseScope.global,
              currency: 'USD',
            ),
          ],
          settlements: [
            Settlement(
              id: 's-omr',
              tripId: 'event-1',
              payerParticipantId: 'member',
              recipientParticipantId: 'owner',
              amount: Decimal.parse('5.000'),
              settledAt: DateTime(2026),
              currency: 'OMR',
            ),
          ],
        );

        // Exactly two independent buckets — no cross-currency bleed.
        expect(buckets.keys.toSet(), {'OMR', 'USD'});

        // OMR bucket settled.
        expect(netFor(buckets['OMR']!, 'owner'), Decimal.zero);
        expect(netFor(buckets['OMR']!, 'member'), Decimal.zero);

        // USD bucket outstanding (member +3.00, owner −3.00) — the per-bucket
        // gate REFUSES on this even though OMR is settled.
        expect(netFor(buckets['USD']!, 'member'), Decimal.parse('3.00'));
        expect(netFor(buckets['USD']!, 'owner'), Decimal.parse('-3.00'));
      },
    );
  });
}
