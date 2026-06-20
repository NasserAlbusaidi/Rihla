import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// Reproduction of a real-world QA scenario (group "SH362P"): an 8-person day
/// trip whose ledger surfaced a Rihla↔Splid discrepancy AND the #596 settle-up
/// bug. This test pins that Rihla's balances + optimal settlement CONSERVE
/// exactly — every fils of the 53.100 pot is accounted for — that every share
/// is a WHOLE baisa (the #596 fix: the client now quantizes each per-head share
/// like the server oracle), and documents the two facts Splid got wrong:
///
///   1. Mohammed, excluded from the coffee round, owes ONLY the 8-way base
///      (5.112), not ~5.223 (Splid charged him ~0.110 too much, and credited
///      Anas the same ~0.110 too much).
///   2. Two splits are indivisible in 3-dp OMR — bread (2.900 ÷ 8 = 0.3625) and
///      coffee (9.600 ÷ 7) — so each is truncated to whole baisa and its
///      remainder lands on exactly one recipient (the alphabetically-last id),
///      never dropped or spread. Yousuf sorts last in BOTH sets, so he absorbs
///      bread's 0.004 and coffee's 0.003.
///
/// Pre-#596 the client kept bread's raw 0.3625 half-baisa for every head, so
/// netBalance carried a 4th decimal (e.g. 7.1335) that diverged from the server
/// aggregate and made the settle-up cap reject the full balance ("amount cannot
/// exceed the outstanding balance"). The fix quantizes at source.
///
/// Trip ledger (all OMR):
///   groceries 24.200  Nasser  → all 8
///   water      1.800  Murshid → all 8
///   bread      2.900  Murshid → all 8   (2.900 ÷ 8 = 0.3625 → 0.362, +0.004→Yousuf)
///   veggies    2.000  Murshid → all 8
///   burger    10.000  Anas    → all 8
///   coffee     9.600  Nasser  → 7 (Mohammed excluded; 9.600 ÷ 7 → 1.371, +0.003→Yousuf)
///   breakfast  2.600  Nasser  → Nasser, Hatim, Ali, Murshid
void main() {
  // Lowercase-name ids so the "remainder → alphabetically-last id" rule is
  // deterministic: 'yousuf' sorts last among both the 8 participants and the 7
  // coffee drinkers, so he absorbs both indivisible remainders. (In the real
  // group a different uid sorted last, which is why Fori — not Yousuf — held
  // them there. Either is correct; the id, not the display name, decides.)
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

  // Expected exact nets (paid − owed), in OMR Decimals — all WHOLE baisa after
  // #596 (the client quantizes each per-head share like the server oracle).
  //   8-way base (groceries+water+bread+veggies+burger = 40.900): 5.112/head;
  //     bread 2.900/8 = 0.3625 truncates to 0.362, and Yousuf (alphabetically-
  //     last of the 8) absorbs the 0.004 remainder → his base is 5.116.
  //   coffee 9.600 / 7 → 1.371; Yousuf absorbs the 0.003 remainder → 1.374.
  //   breakfast 2.600 / 4 = 0.650.
  final expectedNet = <String, Decimal>{
    nasser: Decimal.parse('29.267'), // 36.400 − 7.133
    anas: Decimal.parse('3.517'), // 10.000 − 6.483
    murshid: Decimal.parse('-0.433'), // 6.700 − 7.133
    mohammed: Decimal.parse('-5.112'), // 0 − 5.112
    fori: Decimal.parse('-6.483'),
    yousuf: Decimal.parse('-6.490'), // holds both bread + coffee remainders
    ali: Decimal.parse('-7.133'),
    hatim: Decimal.parse('-7.133'),
  };

  List<UserBalance> computeBalances() => BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: participants,
      )['OMR']!;

  UserBalance balanceOf(List<UserBalance> bals, String id) =>
      bals.firstWhere((b) => b.participantId == id);

  group('Jabal trip — 8-person settlement (SH362P QA scenario)', () {
    test('per-person net balances are exact, whole-baisa, and conserve to zero',
        () {
      final balances = computeBalances();

      for (final id in allIds) {
        final net = balanceOf(balances, id).netBalance;
        expect(net, expectedNet[id], reason: '${names[id]} net balance');
        // #596: no share carries a sub-baisa, so every net is whole-baisa.
        expect(
          (net * Decimal.fromInt(1000)).isInteger,
          isTrue,
          reason: '${names[id]} net $net must be whole-baisa',
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

      // 8-way base, quantized: (24.2 + 1.8 + 2.9 + 2.0 + 10.0) / 8 = 40.9 / 8.
      // bread's 0.0005/head rounds away (it routes to Yousuf), so Mohammed owes
      // the clean 5.112 — not ~5.223 as Splid computed.
      expect(m.totalOwed, Decimal.parse('5.112'),
          reason: 'Mohammed skipped coffee — owes only the 8-way base, '
              'not ~5.223 as Splid computed');
      expect(m.totalPaid, Decimal.zero);
      expect(m.netBalance, Decimal.parse('-5.112'));

      // Anas drank coffee → owes base + one coffee share (6.483), and is the
      // second creditor at +3.517 — NOT +3.623 as Splid credited him.
      final a = balanceOf(balances, anas);
      expect(a.totalOwed, Decimal.parse('6.483'));
      expect(a.netBalance, Decimal.parse('3.517'));
    });

    test('indivisible remainders land on the alphabetically-last id, not '
        'dropped or spread (bread 0.004 + coffee 0.003 → Yousuf)', () {
      final balances = computeBalances();

      // Fori and Yousuf both owe the 8-way base + one coffee share + no
      // breakfast. The ONLY differences are the two indivisible remainders,
      // both assigned to the alphabetically-last id (Yousuf): bread 2.900/8
      // leaves 0.004 and coffee 9.600/7 leaves 0.003.
      expect(balanceOf(balances, fori).totalOwed, Decimal.parse('6.483'));
      expect(balanceOf(balances, yousuf).totalOwed, Decimal.parse('6.490'));
      expect(
        balanceOf(balances, yousuf).totalOwed -
            balanceOf(balances, fori).totalOwed,
        Decimal.parse('0.007'),
        reason: 'Yousuf absorbs bread 0.004 + coffee 0.003; neither remainder '
            'is dropped nor spread',
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

      // Total moved == total debt == 32.784.
      final total = settlements.fold(
          Decimal.zero, (sum, s) => sum + (s['amount'] as Decimal));
      expect(total, Decimal.parse('32.784'));

      // Greedy minimal for this shape: 7 transfers (Mohammed's debt splits
      // across both creditors — the one unavoidable "extra" hop).
      expect(settlements, hasLength(7));
    });

    test('settlement amounts are whole-baisa — settle-up cap cannot misfire '
        '(#596 regression)', () {
      final balances = computeBalances();
      final settlements =
          BalanceCalculator.calculateOptimalSettlements(balances: balances);
      final amounts = [for (final s in settlements) s['amount'] as Decimal];

      // Pre-#596 a terminating division like bread 2.900 ÷ 8 = 0.3625 kept a 4th
      // decimal that flowed untouched into netBalance and the optimizer output,
      // producing sub-fils transfers (e.g. 7.1335). The fix quantizes at source,
      // so the largest transfer is the clean 7.133 — never 7.1335.
      expect(amounts, contains(Decimal.parse('7.133')));
      expect(amounts, isNot(contains(Decimal.parse('7.1335'))));

      // Every amount now survives the millis round-trip unchanged (whole-baisa),
      // so persisting the raw optimizer amount loses nothing.
      Decimal millisRoundTrip(Decimal d) => MoneySerializer.fromSubunits(
            MoneySerializer.toSubunits(d, 'OMR'),
            'OMR',
          );
      expect(
        amounts.every((a) => millisRoundTrip(a) == a),
        isTrue,
        reason: 'every transfer is exact at 3-dp OMR (no sub-fils residue)',
      );

      // The settle-up sheet prefills suggestedAmount.toStringAsFixed(3) and the
      // cap rejects editedAmount > suggestedAmount. With whole-baisa amounts the
      // prefill is EXACT (parse(toStringAsFixed(3)) == amount), so the prefilled
      // value never exceeds the raw balance — the #596 rejection cannot recur.
      for (final a in amounts) {
        expect(Decimal.parse(a.toStringAsFixed(3)), a,
            reason: 'prefill of $a is exact → cap (edited > suggested) passes');
      }
    });
  });
}
