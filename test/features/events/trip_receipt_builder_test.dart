import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/services/money_serializer.dart';
import 'package:safar/features/activity/models/activity_log_model.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/trip_receipt.dart';
import 'package:safar/features/events/utils/trip_receipt_builder.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// #704 Slice A — the money/legal core. Table-driven across clean, corrections,
/// multi-currency, an adversarial settlements/identity case, and coverage. The
/// receipt copies oracle balances verbatim and re-uses the canonical allocator,
/// so ALLOCATIONS must sum-reconcile with the BALANCES it sits beside.
void main() {
  Decimal d(String s) => Decimal.parse(s);
  final gen = DateTime(2026, 6, 30, 12);

  Participant pt(String id) => Participant(
        id: id,
        tripId: 'e1',
        role: ParticipantRole.member,
        joinedAt: DateTime(2026),
        displayName: id,
      );

  Expense exp(
    String id, {
    required String amount,
    required String payer,
    String currency = 'OMR',
    SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    ExpenseScope scope = ExpenseScope.global,
    List<String>? customSplit,
    String? categoryId,
    String? description,
  }) =>
      Expense(
        id: id,
        tripId: 'e1',
        payerParticipantId: payer,
        amount: d(amount),
        scope: scope,
        splitMode: splitMode,
        splitDistribution: splitDistribution,
        customSplitParticipants: customSplit,
        categoryId: categoryId,
        description: description,
        createdAt: DateTime(2026, 6, 10),
        currency: currency,
      );

  Settlement settle(
    String id, {
    required String from,
    required String to,
    required String amount,
    String currency = 'OMR',
    String? groupSettleUpId,
    String? note,
  }) =>
      Settlement(
        id: id,
        tripId: 'e1',
        payerParticipantId: from,
        recipientParticipantId: to,
        amount: d(amount),
        settledAt: DateTime(2026, 6, 20),
        currency: currency,
        groupSettleUpId: groupSettleUpId,
        note: note,
      );

  Map<String, dynamic> snap(
    String amount,
    String currency, {
    String? payer,
    String? desc,
    bool isDeleted = false,
  }) =>
      {
        'amountFils': MoneySerializer.toSubunits(d(amount), currency),
        'currency': currency,
        'payerParticipantId': payer,
        'description': desc,
        'isDeleted': isDeleted,
      };

  ActivityLog audit({
    required String type,
    required String expenseId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? actorName,
    String? actorId,
    DateTime? at,
  }) =>
      ActivityLog(
        id: 'log-$expenseId-$type',
        tripId: 'e1',
        category: 'MONEY',
        eventType: type,
        logText: '',
        actorId: actorId,
        actorName: actorName,
        metadata: {
          'expenseId': expenseId,
          'before': before,
          'after': after,
        },
        createdAt: at ?? DateTime(2026, 6, 15),
      );

  Event event({
    bool isClosed = false,
    DateTime? closedAt,
    String? closedBy,
    List<String> participantIds = const ['p1', 'p2'],
    Map<String, String> participantNames = const {'p1': 'Ahmed', 'p2': 'Sara'},
  }) =>
      Event(
        id: 'e1',
        name: 'Desert Camp',
        type: EventType.camping,
        groupId: 'g1',
        createdBy: 'p1',
        participantIds: participantIds,
        participantNames: participantNames,
        modules: const EventModules(),
        startDate: DateTime(2026, 6, 10),
        endDate: DateTime(2026, 6, 12),
        createdAt: DateTime(2026, 6, 1),
        isClosed: isClosed,
        closedAt: closedAt,
        closedBy: closedBy,
      );

  // Build the receipt with oracle balances computed FROM the same inputs, so
  // any reconciliation assertion is genuine (not hand-fed).
  TripReceipt build({
    required Event ev,
    required List<Expense> expenses,
    required List<Participant> participants,
    List<Settlement> settlements = const [],
    List<ActivityLog> audits = const [],
    AuditCoverage coverage = AuditCoverage.complete,
    Map<String, String>? roster,
  }) {
    final balances = BalanceCalculator.calculateBalances(
      expenses: expenses,
      participants: participants,
      settlements: settlements,
    );
    return buildTripReceipt(
      event: ev,
      expenses: expenses,
      settlements: settlements,
      participants: participants,
      auditLogs: audits,
      correctionsCoverage: coverage,
      balancesByCurrency: balances,
      roster: roster ?? {for (final p in participants) p.id: p.id},
      generatedAt: gen,
    );
  }

  group('clean', () {
    test('equal split + settlement → expenses, allocations, settlement, nets', () {
      final ps = [pt('p1'), pt('p2')];
      final r = build(
        ev: event(),
        participants: ps,
        expenses: [exp('x1', amount: '10.000', payer: 'p1', categoryId: 'food')],
        settlements: [settle('s1', from: 'p2', to: 'p1', amount: '5.000')],
        roster: {'p1': 'Ahmed', 'p2': 'Sara'},
      );

      expect(r.expenses, hasLength(1));
      expect(r.expenses.first.payerName, 'Ahmed');
      // 10.000 split equally over {p1, p2} → 5.000 each.
      expect(r.allocations, hasLength(2));
      expect(
        r.allocations.firstWhere((a) => a.personName == 'Sara').owed,
        d('5.000'),
      );
      expect(r.settlements.single.fromName, 'Sara');
      expect(r.settlements.single.toName, 'Ahmed');
      expect(r.settlements.single.isGroupLinked, isFalse);
      expect(r.currencies, ['OMR']);
      expect(r.isEmpty, isFalse);
    });
  });

  group('corrections', () {
    test('amount edit, soft-delete keeps amount, split-only generic row', () {
      final ps = [pt('p1'), pt('p2')];
      final r = build(
        ev: event(),
        participants: ps,
        expenses: [exp('x1', amount: '6.000', payer: 'p1')],
        roster: {'p1': 'Ahmed', 'p2': 'Sara'},
        audits: [
          // amount edit 5.000 -> 6.000
          audit(
            type: 'UPDATE',
            expenseId: 'x1',
            before: snap('5.000', 'OMR', payer: 'p1', desc: 'Fuel'),
            after: snap('6.000', 'OMR', payer: 'p1', desc: 'Fuel'),
            actorName: 'Ahmed',
          ),
          // soft-delete: money fields UNCHANGED, only isDeleted flips
          audit(
            type: 'DELETE',
            expenseId: 'x2',
            before: snap('2.000', 'OMR', payer: 'p2', desc: 'Snacks'),
            after: snap('2.000', 'OMR', payer: 'p2', desc: 'Snacks', isDeleted: true),
            actorName: 'Sara',
          ),
          // split-only edit: before==after on money snap → hasFieldChange false
          audit(
            type: 'UPDATE',
            expenseId: 'x3',
            before: snap('4.000', 'OMR', payer: 'p1', desc: 'Gear'),
            after: snap('4.000', 'OMR', payer: 'p1', desc: 'Gear'),
            actorName: 'Ahmed',
          ),
        ],
      );

      final edit = r.corrections.firstWhere((c) => c.expenseId == 'x1');
      expect(edit.kind, 'EDIT');
      expect(edit.amountChange, isNotNull);
      expect(edit.amountChange!.before, d('5.000'));
      expect(edit.amountChange!.after, d('6.000'));

      final del = r.corrections.firstWhere((c) => c.expenseId == 'x2');
      expect(del.kind, 'DELETE');
      expect(del.detailsCaptured, isTrue);
      expect(del.amount, d('2.000')); // the removed magnitude survives
      expect(del.currency, 'OMR');

      final splitOnly = r.corrections.firstWhere((c) => c.expenseId == 'x3');
      expect(splitOnly.detailsCaptured, isFalse); // generic "edited" row
      expect(splitOnly.amount, d('4.000')); // still carries the amount
    });

    test('legacy empty metadata → unreadable entry (no crash, sentinel currency)', () {
      final ps = [pt('p1'), pt('p2')];
      final r = build(
        ev: event(),
        participants: ps,
        expenses: const [],
        audits: [audit(type: 'UPDATE', expenseId: 'old')], // no before/after
      );
      final c = r.corrections.single;
      expect(c.detailsCaptured, isFalse);
      expect(c.currency, ''); // sentinel, excluded from per-currency math
      expect(c.amount, Decimal.zero);
    });

    test('payer-change + null-actor corrections leak ZERO uids into the model', () {
      final ps = [pt('p1'), pt('p2')];
      final r = build(
        ev: event(),
        participants: ps,
        expenses: const [],
        roster: {'p1': 'Ahmed', 'p2': 'Sara'},
        audits: [
          // payer change p1 -> p2; actorName null + a departed actorId
          audit(
            type: 'UPDATE',
            expenseId: 'x1',
            before: snap('3.000', 'OMR', payer: 'p1'),
            after: snap('3.000', 'OMR', payer: 'p2'),
            actorId: 'departed-uid-xyz',
          ),
        ],
      );
      final c = r.corrections.single;
      expect(c.payerChange, isNotNull);
      // resolved to names, never the raw uids
      expect(c.payerChange!.before, 'Ahmed');
      expect(c.payerChange!.after, 'Sara');
      // unresolved actor → placeholder, never the raw uid
      expect(c.actorName, 'Unknown');
      expect(c.actorName, isNot(contains('departed')));
    });
  });

  group('multi-currency', () {
    test('OMR + USD + JPY bucket independently; no cross-sum', () {
      final ps = [pt('p1'), pt('p2')];
      final r = build(
        ev: event(),
        participants: ps,
        expenses: [
          exp('x1', amount: '10.000', payer: 'p1', currency: 'OMR'),
          exp('x2', amount: '20.00', payer: 'p2', currency: 'USD'),
          exp('x3', amount: '500', payer: 'p1', currency: 'JPY'),
        ],
      );
      expect(r.currencies.toSet(), {'OMR', 'USD', 'JPY'});
      expect(r.netsByCurrency.keys.toSet(), {'OMR', 'USD', 'JPY'});
      // Each currency bucket nets to zero across the two participants.
      for (final cur in r.currencies) {
        final sum = r.netsByCurrency[cur]!
            .fold(Decimal.zero, (acc, n) => acc + n.net);
        expect(sum, Decimal.zero, reason: '$cur should net to zero');
      }
    });
  });

  group('adversarial — settlements / money-flow / identity', () {
    test('#752 group-linked + #249 departed net + same-name; allocations reconcile', () {
      // Universe = current p1,p2 (both named "Sara") + departed p3 who still
      // holds a balance (#249). p3 is in `participants` (the oracle universe)
      // but NOT in event.participantIds.
      final ps = [pt('p1'), pt('p2'), pt('p3')];
      final ev = event(
        participantIds: const ['p1', 'p2'],
        participantNames: const {'p1': 'Sara', 'p2': 'Sara'},
      );
      final expenses = [
        // global equal expense over the full universe (3 heads)
        exp('x1', amount: '9.000', payer: 'p1'),
        // an exact split naming the departed p3 too
        exp(
          'x2',
          amount: '6.000',
          payer: 'p2',
          splitMode: SplitMode.exact,
          splitDistribution: {'p1': d('2.000'), 'p2': d('2.000'), 'p3': d('2.000')},
        ),
      ];
      final settlements = [
        settle('s1', from: 'p2', to: 'p1', amount: '1.000', groupSettleUpId: 'gs-1'),
        settle('s2', from: 'p1', to: 'p2', amount: '0.500'), // append-only offset
      ];
      // #196-style disambiguated roster: two live "Sara"s carry uid discriminators.
      final r = build(
        ev: ev,
        participants: ps,
        expenses: expenses,
        settlements: settlements,
        roster: {'p1': 'Sara (#0001)', 'p2': 'Sara (#0002)', 'p3': 'Bilal (former member)'},
      );

      // group-linked settlement flagged; the other not.
      expect(r.settlements.firstWhere((s) => s.note == null && s.amount == d('1.000')).isGroupLinked, isTrue);
      expect(r.settlements.firstWhere((s) => s.amount == d('0.500')).isGroupLinked, isFalse);

      // same-name members are distinct, NON-uid ordinal, zero uid bytes.
      expect(r.participantNames, containsAll(['Sara', 'Sara (2)']));
      for (final n in r.participantNames) {
        expect(n, isNot(contains('#')));
      }
      // departed p3 present in balances, shown by name not uid.
      final omr = r.netsByCurrency['OMR']!;
      expect(omr.any((n) => n.participantId == 'p3'), isTrue);

      // RECONCILIATION: per person, Σ allocations.owed == oracle totalOwed.
      final balances = BalanceCalculator.calculateBalances(
        expenses: expenses,
        participants: ps,
        settlements: settlements,
      )['OMR']!;
      for (final b in balances) {
        final allocSum = r.allocations
            .where((a) => a.personName == r.netsByCurrency['OMR']!
                .firstWhere((n) => n.participantId == b.participantId)
                .personName)
            .fold(Decimal.zero, (acc, a) => acc + a.owed);
        expect(allocSum, b.totalOwed,
            reason: 'allocations for ${b.participantId} must equal oracle owed');
      }
      // And the full allocation total equals total spent (no leakage).
      final allocTotal =
          r.allocations.fold(Decimal.zero, (acc, a) => acc + a.owed);
      expect(allocTotal, d('15.000')); // 9.000 + 6.000
    });
  });

  group('coverage + empty', () {
    test('coverage flows through verbatim', () {
      final ps = [pt('p1'), pt('p2')];
      for (final cov in AuditCoverage.values) {
        final r = build(
          ev: event(),
          participants: ps,
          expenses: [exp('x1', amount: '1.000', payer: 'p1')],
          coverage: cov,
        );
        expect(r.correctionsCoverage, cov);
      }
    });

    test('no expenses/settlements/corrections → isEmpty', () {
      final ps = [pt('p1'), pt('p2')];
      final r = build(ev: event(), participants: ps, expenses: const []);
      expect(r.isEmpty, isTrue);
    });
  });
}
