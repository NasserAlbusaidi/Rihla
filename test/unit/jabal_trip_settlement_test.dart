import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// Reproduction of a real-world QA scenario (group "SH362P"): an 8-person day
/// trip whose ledger surfaced a Rihla↔Splid discrepancy. This test pins that
/// Rihla's balances + optimal settlement CONSERVE exactly — every fils of the
/// 53.100 pot is accounted for — and documents the two facts Splid got wrong:
///
///   1. Mohammed, excluded from the coffee round, owes ONLY the 8-way base
///      (5.1125), not ~5.223 (Splid charged him ~0.110 too much, and credited
///      Anas the same 0.110 too much).
///   2. Coffee (9.600 ÷ 7) is indivisible in 3-dp OMR, so exactly one drinker
///      absorbs the 0.003 remainder and the seven shares still sum to 9.600.
///
/// Trip ledger (all OMR):
///   groceries 24.200  Nasser  → all 8
///   water      1.800  Murshid → all 8
///   bread      2.900  Murshid → all 8
///   veggies    2.000  Murshid → all 8
///   burger    10.000  Anas    → all 8
///   coffee     9.600  Nasser  → 7 (Mohammed excluded)
///   breakfast  2.600  Nasser  → Nasser, Hatim, Ali, Murshid
void main() {
  // Lowercase-name ids so the "remainder → alphabetically-last id" rule is
  // deterministic: among the 7 coffee drinkers, 'yousuf' sorts last and so
  // absorbs the 0.003 remainder. (In the real group a different uid sorted
  // last, which is why Fori — not Yousuf — held it there. Either is correct;
  // the id, not the display name, decides.)
  const ali = 'ali';
  const anas = 'anas';
  const fori = 'fori';
  const hatim = 'hatim';
  const mohammed = 'mohammed';
  const murshid = 'murshid';
  const nasser = 'nasser';
  const yousuf = 'yousuf';

  final names = <String, String>{
    ali: 'Ali',
    anas: 'Anas',
    fori: 'Fori',
    hatim: 'Hatim',
    mohammed: 'Mohammed',
    murshid: 'Murshid',
    nasser: 'Nasser',
    yousuf: 'Yousuf',
  };
  final allIds = [ali, anas, fori, hatim, mohammed, murshid, nasser, yousuf];

  Participant participant(String id) => Participant(
        id: id,
        tripId: 'jabal',
        role: ParticipantRole.member,
        joinedAt: DateTime(2026, 6, 19),
        displayName: names[id],
      );

  Expense expense({
    required String id,
    required String payer,
    required String amount,
    ExpenseScope scope = ExpenseScope.global,
    List<String>? splitWith,
  }) =>
      Expense(
        id: id,
        tripId: 'jabal',
        payerParticipantId: payer,
        amount: Decimal.parse(amount),
        scope: scope,
        customSplitParticipants: splitWith,
        createdAt: DateTime(2026, 6, 19),
      );

  final participants = [for (final id in allIds) participant(id)];

  final expenses = [
    expense(id: 'groceries', payer: nasser, amount: '24.200'),
    expense(id: 'water', payer: murshid, amount: '1.800'),
    expense(id: 'bread', payer: murshid, amount: '2.900'),
    expense(id: 'veggies', payer: murshid, amount: '2.000'),
    expense(id: 'burger', payer: anas, amount: '10.000'),
    expense(
      id: 'coffee',
      payer: nasser,
      amount: '9.600',
      scope: ExpenseScope.custom,
      splitWith: [ali, anas, fori, hatim, murshid, nasser, yousuf], // no Mohammed
    ),
    expense(
      id: 'breakfast',
      payer: nasser,
      amount: '2.600',
      scope: ExpenseScope.custom,
      splitWith: [nasser, hatim, ali, murshid],
    ),
  ];

  // Expected exact nets (paid − owed), in OMR Decimals.
  //   8-way base each            = 40.900 / 8        = 5.1125
  //   coffee share (6 drinkers)  = 9.600 / 7 → 1.371 (Yousuf absorbs +0.003)
  //   breakfast share (4 people) = 2.600 / 4         = 0.650
  final expectedNet = <String, Decimal>{
    nasser: Decimal.parse('29.2665'), // 36.400 − 7.1335
    anas: Decimal.parse('3.5165'), // 10.000 − 6.4835
    murshid: Decimal.parse('-0.4335'), // 6.700 − 7.1335
    mohammed: Decimal.parse('-5.1125'), // 0 − 5.1125
    fori: Decimal.parse('-6.4835'),
    yousuf: Decimal.parse('-6.4865'), // holds the coffee remainder
    ali: Decimal.parse('-7.1335'),
    hatim: Decimal.parse('-7.1335'),
  };

  List<UserBalance> computeBalances() => BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      )['OMR']!;

  UserBalance balanceOf(List<UserBalance> bals, String id) =>
      bals.firstWhere((b) => b.participantId == id);

  group('Jabal trip — 8-person settlement (SH362P QA scenario)', () {
    test('per-person net balances are exact and conserve to zero', () {
      final balances = computeBalances();

      for (final id in allIds) {
        expect(
          balanceOf(balances, id).netBalance,
          expectedNet[id],
          reason: '${names[id]} net balance',
        );
      }

      final sumNet = balances.fold(Decimal.zero, (s, b) => s + b.netBalance);
      expect(sumNet, Decimal.zero, reason: 'balances must conserve to zero');

      final totalPaid = balances.fold(Decimal.zero, (s, b) => s + b.totalPaid);
      final totalOwed = balances.fold(Decimal.zero, (s, b) => s + b.totalOwed);
      expect(totalPaid, Decimal.parse('53.100'));
      expect(totalOwed, Decimal.parse('53.100'),
          reason: 'every fils of the 53.100 pot is allocated');
    });

    test('coffee-excluded member owes only the 8-way base '
        '(Splid overcharged Mohammed ~0.110)', () {
      final balances = computeBalances();
      final m = balanceOf(balances, mohammed);

      // 8-way base = (24.2 + 1.8 + 2.9 + 2.0 + 10.0) / 8 = 40.9 / 8 = 5.1125
      expect(m.totalOwed, Decimal.parse('5.1125'),
          reason: 'Mohammed skipped coffee — owes only the 8-way base, '
              'not ~5.223 as Splid computed');
      expect(m.totalPaid, Decimal.zero);
      expect(m.netBalance, Decimal.parse('-5.1125'));

      // Anas drank coffee → owes base + one coffee share (6.4835), and is the
      // second creditor at +3.5165 — NOT +3.623 as Splid credited him.
      final a = balanceOf(balances, anas);
      expect(a.totalOwed, Decimal.parse('6.4835'));
      expect(a.netBalance, Decimal.parse('3.5165'));
    });

    test('indivisible coffee 0.003 remainder lands on exactly one drinker', () {
      final balances = computeBalances();

      // Fori and Yousuf are economically identical (8-way base + one coffee
      // share, no breakfast). The only difference is the 0.003 remainder from
      // 9.600 ÷ 7, assigned to the alphabetically-last id (Yousuf here).
      expect(balanceOf(balances, fori).totalOwed, Decimal.parse('6.4835'));
      expect(balanceOf(balances, yousuf).totalOwed, Decimal.parse('6.4865'));
      expect(
        balanceOf(balances, yousuf).totalOwed -
            balanceOf(balances, fori).totalOwed,
        Decimal.parse('0.003'),
        reason: 'one drinker absorbs the indivisible 0.003; it is neither '
            'dropped nor spread',
      );
    });

    test('optimal settlement clears every balance exactly (conservation)', () {
      final balances = computeBalances();
      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);

      // Net settlement flow per participant = received − paid.
      final flow = {for (final id in allIds) id: Decimal.zero};
      for (final s in settlements) {
        final from = s['fromUserId'] as String;
        final to = s['toUserId'] as String;
        final amt = s['amount'] as Decimal;
        flow[from] = flow[from]! - amt;
        flow[to] = flow[to]! + amt;
      }

      // The settlement must carry each participant from their net to zero —
      // i.e. settlement flow == netBalance for everyone. This is the whole
      // conservation guarantee in one assertion.
      for (final id in allIds) {
        expect(flow[id], expectedNet[id],
            reason: 'settlement flow for ${names[id]} must equal their net');
      }

      // Every transfer flows from a debtor to one of the two creditors.
      const creditors = {nasser, anas};
      final debtors = allIds.toSet().difference(creditors);
      for (final s in settlements) {
        expect(debtors, contains(s['fromUserId']));
        expect(creditors, contains(s['toUserId']));
        expect(s['amount'] as Decimal, greaterThan(Decimal.zero));
      }

      // Total moved == total debt == 32.783.
      final total = settlements.fold(
          Decimal.zero, (sum, s) => sum + (s['amount'] as Decimal));
      expect(total, Decimal.parse('32.783'));

      // Greedy minimal for this shape: 7 transfers (Mohammed's debt splits
      // across both creditors — the one unavoidable "extra" hop).
      expect(settlements, hasLength(7));
    });

    test('settlement amounts carry sub-fils precision '
        '(settle-up write must quantize)', () {
      final balances = computeBalances();
      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);
      final amounts = [for (final s in settlements) s['amount'] as Decimal];

      // Terminating divisions like 2.900 ÷ 8 = 0.3625 keep a 4th decimal that
      // flows untouched into netBalance and thence into the optimizer output,
      // so some transfers are finer than OMR's 3 dp (e.g. 7.1335).
      expect(amounts, contains(Decimal.parse('7.1335')));

      // Such an amount does NOT survive the millis round-trip: toSubunits
      // truncates 7.1335 → 7133 (= 7.133), dropping 0.0005. A settle-up write
      // that persists the raw optimizer amount would lose that fraction, so
      // the write path must quantize to currency precision first.
      Decimal millisRoundTrip(Decimal d) => MoneySerializer.fromSubunits(
            MoneySerializer.toSubunits(d, 'OMR'),
            'OMR',
          );
      expect(
        amounts.any((a) => millisRoundTrip(a) != a),
        isTrue,
        reason: 'at least one transfer is finer than 3-dp OMR',
      );
    });
  });
}
