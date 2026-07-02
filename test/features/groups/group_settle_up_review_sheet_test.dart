import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/widgets/pre_settlement_review_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #204 (group trigger): the group settle-up screen fires the pre-settlement
/// review sheet ONCE when the resolved group basis holds review-worthy
/// expenses; each row deep-links to its OWN event's editor; the review-all
/// CTA is hidden (no group-wide ledger surface, #422 deferred).

const _groupId = 'grp-1';

final _testGroup = Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Event _makeEvent({
  required String id,
  List<String> participantIds = const ['uid-alice', 'uid-bob'],
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: _groupId,
    createdBy: 'uid-alice',
    participantIds: participantIds,
    participantNames: {for (final uid in participantIds) uid: 'User $uid'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 3, 1),
  );
}

Expense _makeExpense({
  required String id,
  required String tripId,
  String description = 'Expense',
  String amount = '5.000',
  String payer = 'uid-alice',
  SplitMode? splitMode = SplitMode.equally,
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    splitMode: splitMode,
    createdAt: DateTime(2026, 3, 5),
    description: description,
  );
}

GroupMember _makeMember({required String userId, bool isTombstone = false}) {
  return GroupMember(
    id: userId,
    groupId: _groupId,
    userId: userId,
    displayName: 'User $userId',
    role: 'MEMBER',
    isTombstone: isTombstone,
    joinedAt: DateTime(2026, 1, 1),
  );
}

/// All-settled balances — the sheet trigger is independent of net amounts.
final _settledBalances = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.zero},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

List<Override> _overrides({
  required List<Event> events,
  required Map<String, Stream<List<Expense>>> expensesByEvent,
  List<GroupMember>? members,
}) {
  return [
    groupDetailProvider(
      _groupId,
    ).overrideWith((_) => Stream.value(_testGroup)),
    groupBalancesProvider(
      _groupId,
    ).overrideWith((_) => AsyncValue.data(_settledBalances)),
    groupSettlementsProvider(
      _groupId,
    ).overrideWith((_) => Stream.value(const <Settlement>[])),
    groupEventsProvider(_groupId).overrideWith((_) => Stream.value(events)),
    groupMembersProvider(_groupId).overrideWith(
      (_) => Stream.value(
        members ??
            [_makeMember(userId: 'uid-alice'), _makeMember(userId: 'uid-bob')],
      ),
    ),
    currentUserIdProvider.overrideWithValue('uid-alice'),
    for (final entry in expensesByEvent.entries) ...[
      eventExpensesProvider(
        (groupId: _groupId, eventId: entry.key),
      ).overrideWith((_) => entry.value),
      eventSettlementsProvider(
        (groupId: _groupId, eventId: entry.key),
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
    ],
  ];
}

Widget _wrap(List<Override> overrides, {GoRouter? router}) {
  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: router != null
          ? MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            )
          : MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const GroupSettleUpScreen(groupId: _groupId),
            ),
    ),
  );
}

void main() {
  testWidgets('fires the review sheet once when any event has flags', (
    tester,
  ) async {
    final controller = StreamController<List<Expense>>.broadcast();
    addTearDown(controller.close);
    final flagged = [
      _makeExpense(
        id: 'x-exact',
        tripId: 'event-b',
        description: 'Villa',
        splitMode: SplitMode.exact,
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [_makeEvent(id: 'event-a'), _makeEvent(id: 'event-b')],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(id: 'x-plain', tripId: 'event-a'),
            ]),
            'event-b': controller.stream,
          },
        ),
      ),
    );
    // Settle fully BEFORE emitting: the review provider only subscribes to
    // event-b's expense stream once the events list has resolved, and a
    // broadcast stream drops events with no listener attached. This also
    // pins the partial-basis guard: with event-b still loading, no sheet.
    await tester.pumpAndSettle();
    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);

    controller.add(flagged);
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.text('Villa'), findsOneWidget);

    await tester.tap(find.byKey(PreSettleReviewKeys.continueButton));
    await tester.pumpAndSettle();
    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);

    // A later stream emission recomputes the provider — the one-shot latch
    // must keep the sheet dismissed.
    controller.add(flagged);
    await tester.pumpAndSettle();
    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });

  testWidgets('no sheet when the basis is clean', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [_makeEvent(id: 'event-a')],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(id: 'x-plain', tripId: 'event-a'),
            ]),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });

  testWidgets('no sheet while an expense stream never resolves', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [_makeEvent(id: 'event-a'), _makeEvent(id: 'event-b')],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                splitMode: SplitMode.exact,
              ),
            ]),
            // event-b's basis never assembles — partial-basis guard.
            'event-b': const Stream<List<Expense>>.empty(),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });

  testWidgets('discriminating: departed payer flags at group level', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [
            _makeEvent(
              id: 'event-a',
              participantIds: const ['uid-alice', 'uid-gone'],
            ),
          ],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(id: 'x-gone', tripId: 'event-a', payer: 'uid-gone'),
            ]),
          },
          members: [
            _makeMember(userId: 'uid-alice'),
            _makeMember(userId: 'uid-bob'),
            _makeMember(userId: 'uid-gone', isTombstone: true),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.text('1 paid by someone who left'), findsOneWidget);
  });

  testWidgets('review-all CTA is hidden at group scope', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [_makeEvent(id: 'event-a')],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                splitMode: SplitMode.exact,
              ),
            ]),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.byKey(PreSettleReviewKeys.reviewButton), findsNothing);
    expect(find.byKey(PreSettleReviewKeys.continueButton), findsOneWidget);
  });

  testWidgets('row tap deep-links to the expense\'s OWN event editor', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/settle',
      routes: [
        GoRoute(
          path: '/settle',
          builder: (_, _) => const GroupSettleUpScreen(groupId: _groupId),
        ),
        GoRoute(
          path: '/group/:gid/event/:eid/ledger/edit/:xid',
          builder: (_, state) => Scaffold(
            body: Text(
              'Edit:${state.pathParameters['eid']}'
              ':${state.pathParameters['xid']}',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [_makeEvent(id: 'event-a'), _makeEvent(id: 'event-b')],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(id: 'x-plain', tripId: 'event-a'),
            ]),
            'event-b': Stream.value([
              _makeExpense(
                id: 'x-villa',
                tripId: 'event-b',
                description: 'Villa',
                splitMode: SplitMode.exact,
              ),
            ]),
          },
        ),
        router: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    await tester.tap(find.text('Villa'));
    await tester.pumpAndSettle();

    // The flagged expense lives in event-b — the editor route must carry
    // event-b's id, never another event's.
    expect(find.text('Edit:event-b:x-villa'), findsOneWidget);
  });
}
