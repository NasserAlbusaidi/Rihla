import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/groups/services/settlement_correction_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

// #753 — SettlementCorrectionService.reverseLogicalSettleUp atomically reverses
// EVERY doc of one logical group settle-up (the N event settlements + the
// residual group settlement sharing a groupSettleUpId) in a single WriteBatch.
// Each reverse swaps payer↔recipient, keeps the amount/currency/destination, and
// carries the SAME groupSettleUpId + the correction-note sentinel — so the
// logical history row reads "corrected" and balances re-open.

const String gid = 'group-1';
const String e1 = 'event-1';
const String e2 = 'event-2';
const String ahmed = 'uid-ahmed'; // expense payer → creditor
const String sara = 'uid-sara'; // debtor
const String note = 'Correction of a recorded payment'; // en sentinel

bool _isReverse(Settlement s) => s.note == note;

Settlement _eventOriginal(String eventId, String amount, String x) => Settlement(
      id: 'orig-$eventId',
      tripId: eventId,
      payerParticipantId: sara, // debtor pays creditor in a settle-up
      recipientParticipantId: ahmed,
      amount: Decimal.parse(amount),
      currency: 'OMR',
      settledAt: DateTime(2026, 6, 29),
      payerName: 'Sara',
      recipientName: 'Ahmed',
      scope: 'event',
      createdBy: sara,
      groupSettleUpId: x,
    );

Settlement _residualOriginal(String amount, String x) => Settlement(
      id: 'orig-residual',
      tripId: gid, // group sentinel
      payerParticipantId: sara,
      recipientParticipantId: ahmed,
      amount: Decimal.parse(amount),
      currency: 'OMR',
      settledAt: DateTime(2026, 6, 29),
      payerName: 'Sara',
      recipientName: 'Ahmed',
      scope: 'group',
      groupId: gid,
      createdBy: sara,
      groupSettleUpId: x,
    );

Event _event(String id) => Event(
      id: id,
      name: 'Beach House',
      type: EventType.trip,
      groupId: gid,
      createdBy: ahmed,
      participantIds: const [ahmed, sara],
      participantNames: const {ahmed: 'Ahmed', sara: 'Sara'},
      modules: const EventModules(),
      createdAt: DateTime(2026, 1, 1),
    );

List<GroupMember> _members() => [
      GroupMember(
        id: 'm-ahmed',
        groupId: gid,
        userId: ahmed,
        displayName: 'Ahmed',
        role: 'OWNER',
        joinedAt: DateTime(2026, 1, 1),
      ),
      GroupMember(
        id: 'm-sara',
        groupId: gid,
        userId: sara,
        displayName: 'Sara',
        role: 'MEMBER',
        joinedAt: DateTime(2026, 1, 1),
      ),
    ];

Decimal _net(GroupBalances b, String currency, String uid) {
  final bucket = b.balances[currency];
  if (bucket == null) return Decimal.zero;
  final ub = bucket.where((u) => u.participantId == uid).firstOrNull;
  return ub?.netBalance ?? Decimal.zero;
}

void main() {
  group('#753 reverseLogicalSettleUp', () {
    test('reverses each event doc + the residual in one batch (swap, tag, note)',
        () async {
      final fake = FakeFirebaseFirestore();
      final correction = SettlementCorrectionService.withFirestore(fake);
      final eventSvc = SettlementService.withFirestore(fake);
      final groupSvc = GroupSettlementService.withFirestore(fake);
      const x = 'gsu-1';

      await correction.reverseLogicalSettleUp(
        groupId: gid,
        groupSettleUpId: x,
        originals: [
          _eventOriginal(e1, '3.000', x),
          _eventOriginal(e2, '2.000', x),
          _residualOriginal('1.000', x),
        ],
        correctedBy: ahmed,
        correctionNote: note,
      );

      // E1 reverse: exactly one, swapped, same amount, tagged + noted.
      final e1Rev = (await eventSvc.getSettlements(gid, e1)).where(_isReverse);
      expect(e1Rev.length, 1);
      expect(e1Rev.first.payerParticipantId, ahmed, reason: 'swapped');
      expect(e1Rev.first.recipientParticipantId, sara, reason: 'swapped');
      expect(e1Rev.first.payerName, 'Ahmed');
      expect(e1Rev.first.recipientName, 'Sara');
      expect(e1Rev.first.amount, Decimal.parse('3.000'));
      expect(e1Rev.first.currency, 'OMR');
      expect(e1Rev.first.groupSettleUpId, x);
      expect(e1Rev.first.createdBy, ahmed);

      // E2 reverse: amount 2.000.
      final e2Rev = (await eventSvc.getSettlements(gid, e2)).where(_isReverse);
      expect(e2Rev.length, 1);
      expect(e2Rev.first.amount, Decimal.parse('2.000'));

      // Residual reverse: in the GROUP collection, scope group, amount 1.000.
      final groupRev =
          (await groupSvc.watchGroupSettlements(gid).first).where(_isReverse);
      expect(groupRev.length, 1);
      expect(groupRev.first.scope, 'group');
      expect(groupRev.first.amount, Decimal.parse('1.000'));
      expect(groupRev.first.payerParticipantId, ahmed, reason: 'swapped');
      expect(groupRev.first.recipientParticipantId, sara, reason: 'swapped');
      expect(groupRev.first.groupSettleUpId, x);
    });

    test('no-residual case writes only the event reverse, group untouched',
        () async {
      final fake = FakeFirebaseFirestore();
      final correction = SettlementCorrectionService.withFirestore(fake);
      final eventSvc = SettlementService.withFirestore(fake);
      final groupSvc = GroupSettlementService.withFirestore(fake);
      const x = 'gsu-2';

      await correction.reverseLogicalSettleUp(
        groupId: gid,
        groupSettleUpId: x,
        originals: [_eventOriginal(e1, '5.000', x)],
        correctedBy: ahmed,
        correctionNote: note,
      );

      expect((await eventSvc.getSettlements(gid, e1)).where(_isReverse).length, 1);
      expect((await groupSvc.watchGroupSettlements(gid).first).isEmpty, isTrue,
          reason: 'no residual original → no group write');
    });

    test('createdBy empty throws ArgumentError (rules require auth uid)',
        () async {
      final correction =
          SettlementCorrectionService.withFirestore(FakeFirebaseFirestore());
      expect(
        () => correction.reverseLogicalSettleUp(
          groupId: gid,
          groupSettleUpId: 'gsu-3',
          originals: [_eventOriginal(e1, '5.000', 'gsu-3')],
          correctedBy: '',
          correctionNote: note,
        ),
        throwsArgumentError,
      );
    });

    // The #567 parity, on the decomposed/batch path: original decomposed
    // settle-up nets P/R to zero; the atomic reverse RE-OPENS the debt.
    test('OMR: reverse re-opens the per-event debt the settle-up closed',
        () async {
      final fake = FakeFirebaseFirestore();
      final eventSvc = SettlementService.withFirestore(fake);
      final correction = SettlementCorrectionService.withFirestore(fake);
      const x = 'gsu-4';

      // Ahmed paid 10.000, split equally → Sara owes 5.000 (net +5 / -5).
      final expense = Expense(
        id: 'exp-1',
        tripId: e1,
        payerParticipantId: ahmed,
        amount: Decimal.parse('10.000'),
        scope: ExpenseScope.global,
        splitMode: SplitMode.equally,
        createdAt: DateTime(2026, 1, 2),
        currency: 'OMR',
      );

      // Original decomposed settle-up: Sara pays Ahmed 5.000 in event e1.
      await eventSvc.addSettlement(
        groupId: gid,
        eventId: e1,
        payerParticipantId: sara,
        recipientParticipantId: ahmed,
        amount: Decimal.parse('5.000'),
        currency: 'OMR',
        createdBy: sara,
        payerName: 'Sara',
        recipientName: 'Ahmed',
        groupSettleUpId: x,
      );

      final settled = computeGroupBalances(
        events: [_event(e1)],
        members: _members(),
        allExpenses: [expense],
        allEventSettlements: await eventSvc.getSettlements(gid, e1),
        groupSettlements: const [],
      );
      expect(_net(settled, 'OMR', ahmed), Decimal.zero);
      expect(_net(settled, 'OMR', sara), Decimal.zero);

      // Reverse the logical settle-up (the live originals tagged x).
      final originals = (await eventSvc.getSettlements(gid, e1))
          .where((s) => s.groupSettleUpId == x && !_isReverse(s))
          .toList();
      await correction.reverseLogicalSettleUp(
        groupId: gid,
        groupSettleUpId: x,
        originals: originals,
        correctedBy: ahmed,
        correctionNote: note,
      );

      final corrected = computeGroupBalances(
        events: [_event(e1)],
        members: _members(),
        allExpenses: [expense],
        allEventSettlements: await eventSvc.getSettlements(gid, e1),
        groupSettlements: const [],
      );
      expect(_net(corrected, 'OMR', ahmed), Decimal.parse('5.000'),
          reason: 'correction re-opens: Ahmed owed 5 again');
      expect(_net(corrected, 'OMR', sara), Decimal.parse('-5.000'),
          reason: 'correction re-opens: Sara owes 5 again');
    });
  });
}
