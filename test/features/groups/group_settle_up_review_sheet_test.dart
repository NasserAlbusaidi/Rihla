import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_presettle_review_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/pre_settlement_review.dart';
import 'package:safar/features/ledger/widgets/pre_settlement_review_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String currency = 'OMR',
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    splitMode: splitMode,
    currency: currency,
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

UserBalance _balance({
  required String participantId,
  required String displayName,
  required String net,
}) {
  return UserBalance(
    participantId: participantId,
    displayName: displayName,
    totalPaid: Decimal.zero,
    totalOwed: Decimal.zero,
    netBalance: Decimal.parse(net),
  );
}

GroupBalances _balances(Map<String, List<UserBalance>> balances) {
  return (
    balances: balances,
    totalSpent: <String, Decimal>{
      for (final currency in balances.keys) currency: Decimal.zero,
    },
    eventCount: 1,
    perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
    memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  );
}

/// All-zero OMR nets — review flags in OMR are suppressed at group scope.
final _settledBalances = _balances({
  'OMR': [
    _balance(participantId: 'uid-alice', displayName: 'Alice', net: '0'),
    _balance(participantId: 'uid-bob', displayName: 'Bob', net: '0'),
  ],
});

final _outstandingBalances = _balances({
  'OMR': [
    _balance(participantId: 'uid-alice', displayName: 'Alice', net: '5'),
    _balance(participantId: 'uid-bob', displayName: 'Bob', net: '-5'),
  ],
});

final _mixedBalances = _balances({
  'OMR': [
    _balance(participantId: 'uid-alice', displayName: 'Alice', net: '0'),
    _balance(participantId: 'uid-bob', displayName: 'Bob', net: '0'),
  ],
  'USD': [
    _balance(participantId: 'uid-alice', displayName: 'Alice', net: '60.50'),
    _balance(participantId: 'uid-bob', displayName: 'Bob', net: '-60.50'),
  ],
});

List<Override> _overrides({
  required List<Event> events,
  required Map<String, Stream<List<Expense>>> expensesByEvent,
  List<GroupMember>? members,
  AsyncValue<GroupBalances>? balances,
  Map<String, Stream<List<Settlement>>> settlementsByEvent = const {},
}) {
  return [
    groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_testGroup)),
    groupBalancesProvider(
      _groupId,
    ).overrideWith((_) => balances ?? AsyncValue.data(_outstandingBalances)),
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
      eventExpensesProvider((
        groupId: _groupId,
        eventId: entry.key,
      )).overrideWith((_) => entry.value),
      eventSettlementsProvider((
        groupId: _groupId,
        eventId: entry.key,
      )).overrideWith(
        (_) =>
            settlementsByEvent[entry.key] ?? Stream.value(const <Settlement>[]),
      ),
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

Future<void> _pumpReviewProvider(ProviderContainer container) async {
  container.listen(
    groupPreSettleReviewProvider(_groupId),
    (_, _) {},
    fireImmediately: true,
  );
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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
          events: [
            _makeEvent(id: 'event-a'),
            _makeEvent(id: 'event-b'),
          ],
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

  testWidgets('no sheet when every flagged currency is already settled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [_makeEvent(id: 'event-a')],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                description: 'Settled OMR villa',
                splitMode: SplitMode.exact,
              ),
            ]),
          },
          balances: AsyncValue.data(_settledBalances),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
    expect(find.text('Settled OMR villa'), findsNothing);
  });

  testWidgets('no sheet while balances are unresolved', (tester) async {
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
          balances: const AsyncValue.loading(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });

  testWidgets('no latch while any event settlement stream is loading', (
    tester,
  ) async {
    final eventBSettlements = StreamController<List<Settlement>>();
    addTearDown(eventBSettlements.close);

    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [
            _makeEvent(id: 'event-a'),
            _makeEvent(id: 'event-b'),
          ],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(id: 'x-plain', tripId: 'event-a'),
            ]),
            'event-b': Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-b',
                description: 'Event B exact',
                splitMode: SplitMode.exact,
              ),
            ]),
          },
          settlementsByEvent: {
            'event-a': Stream.value(const <Settlement>[]),
            'event-b': eventBSettlements.stream,
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);

    eventBSettlements.add(const <Settlement>[]);
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.text('Event B exact'), findsOneWidget);
  });

  test(
    'review provider stays unresolved while balances are unresolved',
    () async {
      final event = _makeEvent(id: 'event-a');
      final container = ProviderContainer(
        overrides: _overrides(
          events: [event],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                splitMode: SplitMode.exact,
              ),
            ]),
          },
          balances: const AsyncValue.loading(),
        ),
      );
      addTearDown(container.dispose);
      await _pumpReviewProvider(container);

      final review = container.read(groupPreSettleReviewProvider(_groupId));

      expect(review.resolved, isFalse);
      expect(review.flags, isEmpty);
    },
  );

  test(
    'review provider leaves flags unsuppressed when balances error',
    () async {
      final event = _makeEvent(id: 'event-a');
      final container = ProviderContainer(
        overrides: _overrides(
          events: [event],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(
                id: 'x-exact',
                tripId: 'event-a',
                splitMode: SplitMode.exact,
              ),
            ]),
          },
          balances: AsyncValue.error(
            StateError('balances failed'),
            StackTrace.current,
          ),
        ),
      );
      addTearDown(container.dispose);
      await _pumpReviewProvider(container);

      final review = container.read(groupPreSettleReviewProvider(_groupId));

      expect(review.resolved, isTrue);
      expect(review.flags.map((f) => (f.expense.id, f.reason)), [
        ('x-exact', ReviewReason.exactSplit),
      ]);
    },
  );

  testWidgets('mixed buckets suppress settled OMR and keep outstanding USD', (
    tester,
  ) async {
    // Two currency buckets mount CurrencyBucketsExplainer, which reads
    // sharedPreferencesProvider — the single-bucket tests never hit it.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      _wrap([
        sharedPreferencesProvider.overrideWithValue(prefs),
        ..._overrides(
          events: [_makeEvent(id: 'event-a')],
          expensesByEvent: {
            'event-a': Stream.value([
              _makeExpense(
                id: 'x-omr',
                tripId: 'event-a',
                description: 'Settled OMR villa',
                splitMode: SplitMode.exact,
              ),
              _makeExpense(
                id: 'x-usd-big',
                tripId: 'event-a',
                description: 'Outstanding USD villa',
                amount: '120.00',
                currency: 'USD',
              ),
              _makeExpense(
                id: 'x-usd-small',
                tripId: 'event-a',
                description: 'USD coffee',
                amount: '1.00',
                currency: 'USD',
              ),
            ]),
          },
          balances: AsyncValue.data(_mixedBalances),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.text('Settled OMR villa'), findsNothing);
    expect(find.text('Outstanding USD villa'), findsOneWidget);
  });

  testWidgets('no sheet while an expense stream never resolves', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [
            _makeEvent(id: 'event-a'),
            _makeEvent(id: 'event-b'),
          ],
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
          events: [
            _makeEvent(id: 'event-a'),
            _makeEvent(id: 'event-b'),
          ],
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
