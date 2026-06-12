import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

// Regression suite — issue #195 (audit finding #10). Pins
// `BalanceCalculator._allocateExact`'s output contract: for an exact split
// whose sum is within `_splitTolerance` (0.001) of `amount`, the residual
// `amount - sum` is closed onto the alphabetically-last recipient that can
// absorb it without going negative, so sum(owed) == amount exactly — matching
// the last-sorted-recipient contract every other allocator honours — and the
// output is never negative for any input.
//
// Two negative-owed paths the fresh-context Gate caught are pinned here:
//   - over-allocation (residual < 0) onto a 0.000 alphabetically-last recipient
//     (reachable: the custom split sheet emits a 0.000 entry per blank member);
//   - a negative exact entry persisted via a forged/unvalidated write (rules
//     only check splitDistribution is a map) — rejected to an equal-split
//     fallback rather than echoed through as a negative owed.
void main() {
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
    String payerId = 'p1',
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

  Settlement settlement({
    required String payer,
    required String recipient,
    required String amount,
  }) {
    return Settlement(
      id: 'settlement-$payer-$recipient-$amount',
      tripId: 'event-1',
      payerParticipantId: payer,
      recipientParticipantId: recipient,
      amount: Decimal.parse(amount),
      settledAt: DateTime(2026),
    );
  }

  Decimal owedFor(List<UserBalance> balances, String participantId) {
    return balances
        .singleWhere((balance) => balance.participantId == participantId)
        .totalOwed;
  }

  Decimal sumOwed(List<UserBalance> balances) =>
      balances.fold(Decimal.zero, (s, b) => s + b.totalOwed);

  Decimal sumNet(List<UserBalance> balances) =>
      balances.fold(Decimal.zero, (s, b) => s + b.netBalance);

  group(
    'BalanceCalculator exact-split tolerance-boundary renormalization (#195)',
    () {
      final participants = [
        participant('p1'),
        participant('p2'),
        participant('p3'),
      ];

      test(
        'boundary +0.001 drift renormalizes onto alphabetically-last recipient',
        () {
          // sum = 10.001, drift = +0.001 over (== tolerance, guard does NOT fire).
          final balances = BalanceCalculator.calculateBalances(
            expenses: [
              expense(
                amount: '10.000',
                splitMode: SplitMode.exact,
                splitDistribution: {
                  'p1': Decimal.parse('5.000'),
                  'p2': Decimal.parse('5.001'),
                },
              ),
            ],
            participants: participants,
          )['OMR']!;

          // Residual (amount - sum) = -0.001 lands on alphabetically-last key p2.
          expect(owedFor(balances, 'p1'), Decimal.parse('5.000'));
          expect(owedFor(balances, 'p2'), Decimal.parse('5.000'));
          // Conservation: sum(owed) == amount. FAILS today (returns 10.001).
          expect(sumOwed(balances), Decimal.parse('10.000'));
        },
      );

      test(
        'boundary -0.001 drift (under-allocated) renormalizes onto last recipient',
        () {
          // sum = 9.999, drift = -0.001 under (abs == tolerance, guard NOT fired).
          final balances = BalanceCalculator.calculateBalances(
            expenses: [
              expense(
                amount: '10.000',
                splitMode: SplitMode.exact,
                splitDistribution: {
                  'p1': Decimal.parse('5.000'),
                  'p2': Decimal.parse('4.999'),
                },
              ),
            ],
            participants: participants,
          )['OMR']!;

          // Residual (+0.001) lands on alphabetically-last key p2.
          expect(owedFor(balances, 'p1'), Decimal.parse('5.000'));
          expect(owedFor(balances, 'p2'), Decimal.parse('5.000'));
          // Conservation: sum(owed) == amount. FAILS today (returns 9.999).
          expect(sumOwed(balances), Decimal.parse('10.000'));
        },
      );

      test(
        'residual lands on alphabetically-last key, not the largest-value participant',
        () {
          // sum = 10.001; alphabetically-last key p3 is the SMALLER allocation.
          final balances = BalanceCalculator.calculateBalances(
            expenses: [
              expense(
                amount: '10.000',
                splitMode: SplitMode.exact,
                splitDistribution: {
                  'p1': Decimal.parse('6.001'),
                  'p3': Decimal.parse('4.000'),
                },
              ),
            ],
            participants: participants,
          )['OMR']!;

          // Residual (-0.001) lands on p3 (sortedKeys.last), not on the larger p1.
          expect(owedFor(balances, 'p1'), Decimal.parse('6.001'));
          expect(owedFor(balances, 'p3'), Decimal.parse('3.999'));
          expect(sumOwed(balances), Decimal.parse('10.000'));
        },
      );

      test(
        '[gate #195 P2] over-allocation onto a 0.000 alphabetically-last '
        'recipient never produces a negative owed',
        () {
          // Reachable from the custom split sheet: exact _buildResult emits a
          // 0.000 entry for any blank participant (custom_split_sheet.dart:
          // 241-246) and _canApply lets a +0.001 over-allocation through
          // (|remainder| <= 0.001). Here the alphabetically-last key p3 is the
          // blank 0.000 participant.
          //   amount 10.000, {p1: 6.001, p2: 4.000, p3: 0.000} → total 10.001,
          //   residual -0.001. Closing it naively onto sortedKeys.last (p3)
          //   yields -0.001 owed — a non-payer turned phantom creditor.
          final balances = BalanceCalculator.calculateBalances(
            expenses: [
              expense(
                amount: '10.000',
                splitMode: SplitMode.exact,
                splitDistribution: {
                  'p1': Decimal.parse('6.001'),
                  'p2': Decimal.parse('4.000'),
                  'p3': Decimal.zero,
                },
              ),
            ],
            participants: participants,
          )['OMR']!;

          // Invariant: residual normalization never drives any owed below zero.
          expect(owedFor(balances, 'p1') >= Decimal.zero, isTrue);
          expect(owedFor(balances, 'p2') >= Decimal.zero, isTrue);
          expect(owedFor(balances, 'p3') >= Decimal.zero, isTrue);
          // p3 cannot absorb -0.001 without going negative, so the residual is
          // closed onto the alphabetically-last recipient that CAN: p2 → 3.999.
          // p3 stays at exactly 0.000.
          expect(owedFor(balances, 'p3'), Decimal.zero);
          expect(owedFor(balances, 'p2'), Decimal.parse('3.999'));
          expect(owedFor(balances, 'p1'), Decimal.parse('6.001'));
          // Conservation still holds.
          expect(sumOwed(balances), Decimal.parse('10.000'));
        },
      );

      test(
        '[gate #195 P1] a negative exact-split entry never yields a negative '
        'owed (residual==0 path)',
        () {
          // The custom split sheet strips minus signs, but firestore.rules
          // (security/firestore.rules:415-416) only checks splitDistribution
          // is a map — not its sign — and _encodeDistribution scales each value
          // verbatim (expense_service.dart). So a forged/unvalidated write can
          // persist a negative exact value. Here sum == amount exactly, so the
          // residual==0 early-return would have echoed {p1: -0.001} straight
          // through as a negative owed (phantom creditor). The calculator must
          // treat a negative entry as an invalid exact split (equal-split
          // fallback), never emit a negative owed.
          //   amount 10.000, {p1: -0.001, p2: 10.001} → total 10.000,
          //   residual 0.000.
          final balances = BalanceCalculator.calculateBalances(
            expenses: [
              expense(
                amount: '10.000',
                splitMode: SplitMode.exact,
                splitDistribution: {
                  'p1': Decimal.parse('-0.001'),
                  'p2': Decimal.parse('10.001'),
                },
              ),
            ],
            participants: participants,
          )['OMR']!;

          // Invariant: no owed is ever negative, for any input.
          expect(owedFor(balances, 'p1') >= Decimal.zero, isTrue);
          expect(owedFor(balances, 'p2') >= Decimal.zero, isTrue);
          // Invalid exact split → equal-split fallback over its keys {p1, p2}.
          expect(owedFor(balances, 'p1'), Decimal.parse('5.000'));
          expect(owedFor(balances, 'p2'), Decimal.parse('5.000'));
          expect(sumOwed(balances), Decimal.parse('10.000'));
        },
      );

      test('exactly-correct exact split is unchanged (no regression)', () {
        // residual == 0 → returns distribution byte-identical.
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '10.000',
              splitMode: SplitMode.exact,
              splitDistribution: {
                'p1': Decimal.parse('2.250'),
                'p2': Decimal.parse('3.750'),
                'p3': Decimal.parse('4.000'),
              },
            ),
          ],
          participants: participants,
        )['OMR']!;

        expect(owedFor(balances, 'p1'), Decimal.parse('2.250'));
        expect(owedFor(balances, 'p2'), Decimal.parse('3.750'));
        expect(owedFor(balances, 'p3'), Decimal.parse('4.000'));
        expect(sumOwed(balances), Decimal.parse('10.000'));
      });

      test(
        'out-of-tolerance still falls back to equal split (no regression)',
        () {
          // sum = 9.000, drift = 1.000 > tolerance → equal-split fallback.
          final balances = BalanceCalculator.calculateBalances(
            expenses: [
              expense(
                amount: '10.000',
                splitMode: SplitMode.exact,
                splitDistribution: {
                  'p1': Decimal.parse('3.000'),
                  'p2': Decimal.parse('3.000'),
                  'p3': Decimal.parse('3.000'),
                },
              ),
            ],
            participants: participants,
          )['OMR']!;

          expect(owedFor(balances, 'p1'), Decimal.parse('3.333'));
          expect(owedFor(balances, 'p2'), Decimal.parse('3.333'));
          expect(owedFor(balances, 'p3'), Decimal.parse('3.334'));
        },
      );

      test(
        '[adversarial] conservation holds under settlement + second equal expense',
        () {
          // Orthogonal axis: settlements + multi-expense aggregation. The exact
          // drift must still heal when it is not the only term.
          //   A: exact 10.000 {p1: 5.000, p2: 5.001} (p3 absent → only p1,p2 owe)
          //   B: equally 6.000 global (p1/p2/p3 → 2.000 each)
          //   S: settlement p1 -> p2 of 2.000 (conservation-neutral)
          final balances = BalanceCalculator.calculateBalances(
            expenses: [
              expense(
                amount: '10.000',
                splitMode: SplitMode.exact,
                payerId: 'p1',
                splitDistribution: {
                  'p1': Decimal.parse('5.000'),
                  'p2': Decimal.parse('5.001'),
                },
              ),
              expense(
                amount: '6.000',
                splitMode: SplitMode.equally,
                payerId: 'p2',
                scope: ExpenseScope.global,
              ),
            ],
            settlements: [
              settlement(payer: 'p1', recipient: 'p2', amount: '2.000'),
            ],
            participants: participants,
          )['OMR']!;

          // Settlements and equal split are conservation-neutral; the only term
          // that breaks sum(net)==0 today is the un-healed exact drift (-0.001).
          expect(sumNet(balances), Decimal.zero);
        },
      );

      test('JPY exact split with valid 0dp sum is unchanged (no false heal)', () {
        // residual == 0 on a clean 0dp split → returns 333/333/334 verbatim.
        final balances = BalanceCalculator.calculateBalances(
          expenses: [
            expense(
              amount: '1000',
              currency: 'JPY',
              splitMode: SplitMode.exact,
              splitDistribution: {
                'p1': Decimal.fromInt(333),
                'p2': Decimal.fromInt(333),
                'p3': Decimal.fromInt(334),
              },
            ),
          ],
          participants: participants,
        )['JPY']!;

        expect(owedFor(balances, 'p1'), Decimal.parse('333'));
        expect(owedFor(balances, 'p2'), Decimal.parse('333'));
        expect(owedFor(balances, 'p3'), Decimal.parse('334'));
        expect(sumOwed(balances), Decimal.parse('1000'));
      });
    },
  );
}
