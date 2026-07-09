import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_presettle_review_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/pre_settlement_review.dart';

Event _makeEvent({
  required String id,
  required String groupId,
  List<String> participantIds = const ['uid-alice', 'uid-bob'],
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'uid-alice',
    participantIds: participantIds,
    participantNames: {for (final uid in participantIds) uid: 'User $uid'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 1),
  );
}

Expense _makeExpense({
  required String id,
  required String tripId,
  required String amount,
  String payer = 'uid-alice',
  SplitMode? splitMode,
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    splitMode: splitMode,
    createdAt: DateTime(2026, 1, 1),
  );
}

GroupMember _makeMember({required String userId, bool isTombstone = false}) {
  return GroupMember(
    id: userId,
    groupId: 'group-1',
    userId: userId,
    displayName: 'User $userId',
    role: 'MEMBER',
    isTombstone: isTombstone,
    joinedAt: DateTime(2026, 1, 1),
  );
}

UserBalance _balance(String uid, String net) {
  return UserBalance(
    participantId: uid,
    displayName: 'User $uid',
    totalPaid: Decimal.zero,
    totalOwed: Decimal.zero,
    netBalance: Decimal.parse(net),
  );
}

final _outstandingBalances = (
  balances: <String, List<UserBalance>>{
    'OMR': [_balance('uid-alice', '5'), _balance('uid-bob', '-5')],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.zero},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{
    'uid-alice': 'User uid-alice',
    'uid-bob': 'User uid-bob',
  },
  memberRawNames: <String, String>{
    'uid-alice': 'User uid-alice',
    'uid-bob': 'User uid-bob',
  },
);

List<Override> _resolvedMoneyOverrides(String groupId, List<Event> events) {
  return [
    groupBalancesProvider(
      groupId,
    ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
    groupSettlementsProvider(
      groupId,
    ).overrideWith((_) => Stream.value(const <Settlement>[])),
    currentUserIdProvider.overrideWithValue(null),
    for (final event in events)
      eventSettlementsProvider((
        groupId: groupId,
        eventId: event.id,
      )).overrideWith((_) => Stream.value(const <Settlement>[])),
  ];
}

Settlement _viewerSettlement({
  required String id,
  String currency = 'OMR',
  DateTime? settledAt,
  String scope = 'event',
  String? groupSettleUpId,
}) => Settlement(
  id: id,
  tripId: scope == 'group' ? 'group-1' : 'event-a',
  payerParticipantId: 'uid-viewer',
  recipientParticipantId: 'uid-alice',
  amount: Decimal.parse('1.000'),
  settledAt: settledAt ?? DateTime(2026, 6, 10),
  currency: currency,
  scope: scope,
  groupSettleUpId: groupSettleUpId,
);

Future<void> _pump(ProviderContainer container, String groupId) async {
  container.listen(
    groupPreSettleReviewProvider(groupId),
    (_, _) {},
    fireImmediately: true,
  );
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const groupId = 'group-1';

  group('groupPreSettleReviewProvider', () {
    test('unions flags across events with per-event active sets', () async {
      // Gate rd-1 P2: event-b's roster MUST include a live member (alice) —
      // a roster of only the tombstoned payer intersects live to ∅ and the
      // detector SKIPS the payer check entirely.
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final eventB = _makeEvent(
        id: 'event-b',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-gone'],
      );
      final container = ProviderContainer(
        overrides: [
          ..._resolvedMoneyOverrides(groupId, [eventA, eventB]),
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-bob'),
              _makeMember(userId: 'uid-gone', isTombstone: true),
            ]),
          ),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                amount: '10',
                splitMode: SplitMode.exact,
              ),
            ]),
          ),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith(
            (_) => Stream.value([
              _makeExpense(
                id: 'x-gone',
                tripId: 'event-b',
                amount: '5',
                payer: 'uid-gone',
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));

      expect(review.resolved, isTrue);
      expect(review.flags, hasLength(2));
      expect(
        review.flags.map((f) => (f.expense.id, f.reason)),
        containsAll([
          ('x-exact', ReviewReason.exactSplit),
          ('x-gone', ReviewReason.payerNotInParticipants),
        ]),
      );
    });

    test('largeAmount denominator is event-local, not group-wide', () async {
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final eventB = _makeEvent(id: 'event-b', groupId: groupId);
      final container = ProviderContainer(
        overrides: [
          ..._resolvedMoneyOverrides(groupId, [eventA, eventB]),
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-bob'),
            ]),
          ),
          // event-a: 10 of 12 total → dominant within its event.
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream.value([
              _makeExpense(id: 'x-big', tripId: 'event-a', amount: '10'),
              _makeExpense(id: 'x-small', tripId: 'event-a', amount: '2'),
            ]),
          ),
          // event-b: 100 is the LONE expense in its event → never "large",
          // even though it dominates the group-wide total.
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith(
            (_) => Stream.value([
              _makeExpense(id: 'x-lone', tripId: 'event-b', amount: '100'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));

      expect(review.resolved, isTrue);
      final large = review.flags
          .where((f) => f.reason == ReviewReason.largeAmount)
          .toList();
      expect(large, hasLength(1));
      expect(large.single.expense.id, 'x-big');
    });

    test('unresolved while any expense stream is still loading', () async {
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final eventB = _makeEvent(id: 'event-b', groupId: groupId);
      final container = ProviderContainer(
        overrides: [
          ..._resolvedMoneyOverrides(groupId, [eventA, eventB]),
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([_makeMember(userId: 'uid-alice')]),
          ),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                amount: '10',
                splitMode: SplitMode.exact,
              ),
            ]),
          ),
          // Never emits: event-b's basis is still assembling.
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => const Stream<List<Expense>>.empty()),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));

      expect(review.resolved, isFalse);
      expect(review.flags, isEmpty);
    });

    test('errored expense stream is OR-dropped but basis resolves', () async {
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final eventB = _makeEvent(id: 'event-b', groupId: groupId);
      final container = ProviderContainer(
        overrides: [
          ..._resolvedMoneyOverrides(groupId, [eventA, eventB]),
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([_makeMember(userId: 'uid-alice')]),
          ),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                amount: '10',
                splitMode: SplitMode.exact,
              ),
            ]),
          ),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith(
            (_) => Stream<List<Expense>>.error(Exception('denied')),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));

      expect(review.resolved, isTrue);
      expect(review.flags.map((f) => (f.expense.id, f.reason)), [
        ('x-exact', ReviewReason.exactSplit),
      ]);
    });

    test(
      'members error -> payer check skipped, other reasons still fire',
      () async {
        final eventA = _makeEvent(id: 'event-a', groupId: groupId);
        final container = ProviderContainer(
          overrides: [
            ..._resolvedMoneyOverrides(groupId, [eventA]),
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([eventA])),
            groupMembersProvider(groupId).overrideWith(
              (_) => Stream<List<GroupMember>>.error(Exception('denied')),
            ),
            eventExpensesProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith(
              (_) => Stream.value([
                _makeExpense(
                  id: 'x-exact',
                  tripId: 'event-a',
                  amount: '10',
                  payer: 'uid-unknown',
                  splitMode: SplitMode.exact,
                ),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);
        await _pump(container, groupId);

        final review = container.read(groupPreSettleReviewProvider(groupId));

        expect(review.resolved, isTrue);
        expect(review.flags.map((f) => f.reason), [ReviewReason.exactSplit]);
      },
    );

    test('unresolved while members are still loading', () async {
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final container = ProviderContainer(
        overrides: [
          ..._resolvedMoneyOverrides(groupId, [eventA]),
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(
            groupId,
          ).overrideWith((_) => const Stream<List<GroupMember>>.empty()),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                amount: '10',
                splitMode: SplitMode.exact,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));

      expect(review.resolved, isFalse);
      expect(review.flags, isEmpty);
    });

    test('stage A: viewer-party newer EVENT settlement suppresses THAT '
        'event\'s flag (#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(
            groupId,
          ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value([flagged])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value([_viewerSettlement(id: 's1')])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, isEmpty);
    });

    test('stage A is event-local: an UNTAGGED settlement in event-a never '
        'suppresses event-b\'s flag (#1058 Gate R1)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final eventB = _makeEvent(
        id: 'event-b',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flaggedB = _makeExpense(
        id: 'b-exact',
        tripId: 'event-b',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(
            groupId,
          ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(const <Expense>[])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value([_viewerSettlement(id: 's1')])),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => Stream.value([flaggedB])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags.map((f) => f.expense.id), ['b-exact']);
    });

    test('stage B: a groupSettleUpId-TAGGED leg in event-a suppresses '
        'event-b\'s older flag group-wide (#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final eventB = _makeEvent(
        id: 'event-b',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flaggedB = _makeExpense(
        id: 'b-exact',
        tripId: 'event-b',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(
            groupId,
          ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(const <Expense>[])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream.value([
              _viewerSettlement(id: 'leg1', groupSettleUpId: 'gsu-1'),
            ]),
          ),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => Stream.value([flaggedB])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, isEmpty);
    });

    test('stage B: viewer-party newer GROUP-level settlement suppresses '
        'group-wide (#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(
            groupId,
          ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(groupId).overrideWith(
            (_) => Stream.value([_viewerSettlement(id: 'g1', scope: 'group')]),
          ),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value([flagged])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, isEmpty);
    });

    test('a viewer with NO settlements (fresh joiner) still sees flags '
        '(#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-joiner'],
      );
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-joiner'),
            ]),
          ),
          groupBalancesProvider(
            groupId,
          ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-joiner'),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value([flagged])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream.value([
              Settlement(
                id: 'others',
                tripId: 'event-a',
                payerParticipantId: 'uid-alice',
                recipientParticipantId: 'uid-bob',
                amount: Decimal.parse('1.000'),
                settledAt: DateTime(2026, 6, 10),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, hasLength(1));
    });

    test(
      'unresolved while the group settlement stream is loading (#1058)',
      () async {
        final eventA = _makeEvent(
          id: 'event-a',
          groupId: groupId,
          participantIds: const ['uid-alice', 'uid-viewer'],
        );
        final flagged = _makeExpense(
          id: 'x',
          tripId: 'event-a',
          amount: '5.000',
          splitMode: SplitMode.exact,
        );
        final container = ProviderContainer(
          overrides: [
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([eventA])),
            groupMembersProvider(groupId).overrideWith(
              (_) => Stream.value([_makeMember(userId: 'uid-alice')]),
            ),
            groupBalancesProvider(
              groupId,
            ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
            groupSettlementsProvider(
              groupId,
            ).overrideWith((_) => const Stream<List<Settlement>>.empty()),
            currentUserIdProvider.overrideWithValue('uid-viewer'),
            eventExpensesProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value([flagged])),
            eventSettlementsProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value(const <Settlement>[])),
          ],
        );
        addTearDown(container.dispose);
        await _pump(container, groupId);

        final review = container.read(groupPreSettleReviewProvider(groupId));
        expect(review.resolved, isFalse);
        expect(review.flags, isEmpty);
      },
    );
  });
}
