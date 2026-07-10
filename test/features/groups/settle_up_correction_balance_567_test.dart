import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

// #567 — the #283 settle-up correction must re-OPEN the debt the original
// (mistaken) settlement closed. Exercises the deterministic money path EXACTLY
// as the group settle-up screen does:
//   - real GroupSettlementService.withFirestore (FakeFirebaseFirestore) write+read-back
//   - real computeGroupBalances + BalanceCalculator fold
//   - correction recorded via the SAME swap the screen's onCorrect uses:
//       payer  = original.recipientParticipantId
//       recipient = original.payerParticipantId
//       amount = original.amount, currency = original.currency
// Money invariant (table-driven: OMR scale 1000, USD scale 100): original +
// offsetting correction net to zero in the SAME per-currency bucket, so the
// pre-settlement debt reappears.

const String gid = 'group-1';
const String eventId = 'event-1';
const String ahmed = 'uid-ahmed';
const String sara = 'uid-sara';

Event _event() => Event(
      id: eventId,
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

Expense _expense({required Decimal amount, String currency = 'OMR'}) => Expense(
      id: 'exp-1',
      tripId: eventId,
      payerParticipantId: ahmed,
      amount: amount,
      scope: ExpenseScope.global,
      splitMode: SplitMode.equally,
      createdAt: DateTime(2026, 1, 2),
      currency: currency,
    );

Decimal _net(GroupBalances b, String currency, String uid) {
  final bucket = b.balances[currency];
  if (bucket == null) return Decimal.zero;
  final ub = bucket.where((u) => u.participantId == uid).firstOrNull;
  return ub?.netBalance ?? Decimal.zero;
}

void main() {
  group('#567 group settle-up correction re-opens the balance (pure path)', () {
    test('OMR: original settles, correction re-opens to +5 / -5', () async {
      final firestore = FakeFirebaseFirestore();
      final service = GroupSettlementService.withFirestore(firestore);
      final event = _event();
      final members = _members();
      final expense = _expense(amount: Decimal.parse('10.000'));

      final preGroupSettlements =
          await service.watchGroupSettlements(gid).first;
      final pre = computeGroupBalances(
        events: [event],
        members: members,
        allExpenses: [expense],
        allEventSettlements: const [],
        groupSettlements: preGroupSettlements,
      );
      expect(_net(pre, 'OMR', ahmed), Decimal.parse('5.000'),
          reason: 'pre: Ahmed is owed 5');
      expect(_net(pre, 'OMR', sara), Decimal.parse('-5.000'),
          reason: 'pre: Sara owes 5');

      await service.addGroupSettlement(
        id: 'test-id-567-omr-original',
        groupId: gid,
        payerParticipantId: sara,
        recipientParticipantId: ahmed,
        amount: Decimal.parse('5.000'),
        currency: 'OMR',
        createdBy: sara,
        payerName: 'Sara',
        recipientName: 'Ahmed',
      );
      final afterOriginal = await service.watchGroupSettlements(gid).first;
      expect(afterOriginal.length, 1, reason: 'original written + read back');
      final original = afterOriginal.first;

      final settled = computeGroupBalances(
        events: [event],
        members: members,
        allExpenses: [expense],
        allEventSettlements: const [],
        groupSettlements: afterOriginal,
      );
      expect(_net(settled, 'OMR', ahmed), Decimal.zero,
          reason: 'after original: Ahmed settled (0)');
      expect(_net(settled, 'OMR', sara), Decimal.zero,
          reason: 'after original: Sara settled (0)');

      // The screen's exact onCorrect swap.
      await service.addGroupSettlement(
        id: 'test-id-567-omr-correction',
        groupId: gid,
        payerParticipantId: original.recipientParticipantId!,
        recipientParticipantId: original.payerParticipantId!,
        amount: original.amount,
        currency: original.currency,
        createdBy: ahmed,
        payerName: original.recipientName,
        recipientName: original.payerName,
      );
      final afterCorrection = await service.watchGroupSettlements(gid).first;
      expect(afterCorrection.length, 2,
          reason: 'correction is an append (original stays)');

      final corrected = computeGroupBalances(
        events: [event],
        members: members,
        allExpenses: [expense],
        allEventSettlements: const [],
        groupSettlements: afterCorrection,
      );
      expect(_net(corrected, 'OMR', ahmed), Decimal.parse('5.000'),
          reason: 'CORRECTION must re-open: Ahmed owed 5 again');
      expect(_net(corrected, 'OMR', sara), Decimal.parse('-5.000'),
          reason: 'CORRECTION must re-open: Sara owes 5 again');
    });

    test('USD: original settles, correction reads s.currency and offsets in USD',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = GroupSettlementService.withFirestore(firestore);
      final event = _event();
      final members = _members();
      final expense = _expense(amount: Decimal.parse('10.00'), currency: 'USD');

      await service.addGroupSettlement(
        id: 'test-id-567-usd-original',
        groupId: gid,
        payerParticipantId: sara,
        recipientParticipantId: ahmed,
        amount: Decimal.parse('5.00'),
        currency: 'USD',
        createdBy: sara,
        payerName: 'Sara',
        recipientName: 'Ahmed',
      );
      final afterOriginal = await service.watchGroupSettlements(gid).first;
      final original = afterOriginal.first;
      expect(original.currency, 'USD');
      expect(original.amount, Decimal.parse('5.00'));

      final settled = computeGroupBalances(
        events: [event],
        members: members,
        allExpenses: [expense],
        allEventSettlements: const [],
        groupSettlements: afterOriginal,
      );
      expect(_net(settled, 'USD', ahmed), Decimal.zero);
      expect(_net(settled, 'USD', sara), Decimal.zero);

      await service.addGroupSettlement(
        id: 'test-id-567-usd-correction',
        groupId: gid,
        payerParticipantId: original.recipientParticipantId!,
        recipientParticipantId: original.payerParticipantId!,
        amount: original.amount,
        currency: original.currency,
        createdBy: ahmed,
        payerName: original.recipientName,
        recipientName: original.payerName,
      );
      final afterCorrection = await service.watchGroupSettlements(gid).first;

      final corrected = computeGroupBalances(
        events: [event],
        members: members,
        allExpenses: [expense],
        allEventSettlements: const [],
        groupSettlements: afterCorrection,
      );
      expect(_net(corrected, 'USD', ahmed), Decimal.parse('5.00'),
          reason: 'USD correction must re-open Ahmed');
      expect(_net(corrected, 'USD', sara), Decimal.parse('-5.00'),
          reason: 'USD correction must re-open Sara');
    });
  });
}
