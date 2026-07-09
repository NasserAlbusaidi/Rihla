import 'dart:ui' show Tristate;

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/providers/ledger_view_provider.dart';
import 'package:safar/features/ledger/widgets/pre_settlement_review_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #758 — the tabbed event view: pinned balance header + Expenses · Settle up ·
/// Activity (· Recap when closed) tabs replacing the launchpad hub.
void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Event event({bool isClosed = false, String? closedBy}) => Event(
    id: eventId,
    name: 'Marrakech',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'uid-1',
    participantIds: const ['uid-1', 'uid-2'],
    participantNames: const {'uid-1': 'Mona', 'uid-2': 'Nasser'},
    modules: const EventModules(),
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 1, 3),
    createdAt: DateTime(2026, 1, 1),
    isClosed: isClosed,
    closedAt: isClosed ? DateTime(2026, 5, 1) : null,
    closedBy: closedBy,
  );

  Expense expense({
    String id = 'x1',
    String payer = 'uid-2',
    String amount = '20.000',
    String currency = 'OMR',
    String description = 'Dinner',
    SplitMode splitMode = SplitMode.equally,
  }) => Expense(
    id: id,
    tripId: eventId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    description: description,
    scope: ExpenseScope.global,
    splitMode: splitMode,
    createdAt: DateTime(2026, 1, 2),
    createdBy: payer,
    currency: currency,
  );

  final group = Group(
    id: groupId,
    name: 'Friends',
    inviteCode: 'ABC123',
    createdBy: 'uid-1',
    memberIds: const ['uid-1', 'uid-2'],
    createdAt: DateTime(2026, 1, 1),
  );

  GroupMember member(String uid, String name) => GroupMember(
    id: 'doc-$uid',
    groupId: groupId,
    userId: uid,
    displayName: name,
    role: 'member',
    joinedAt: DateTime(2026, 1, 1),
  );

  Future<GoRouter> pumpTabbedEvent(
    WidgetTester tester, {
    required Event ev,
    List<Expense> expenses = const [],
    List<Override> extraOverrides = const [],
  }) async {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (_, state) =>
              Scaffold(body: Text('GroupRoute:${state.pathParameters['gid']}')),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (_, state) => EventCommandCenter(
                groupId: state.pathParameters['gid']!,
                eventId: state.pathParameters['eid']!,
              ),
              routes: [
                GoRoute(
                  path: 'ledger',
                  builder: (_, state) => Scaffold(
                    body: Text('LedgerRoute:${state.pathParameters['eid']}'),
                  ),
                  routes: [
                    GoRoute(
                      path: 'add',
                      builder: (_, state) => Scaffold(
                        body: Text(
                          'AddExpenseRoute:${state.pathParameters['eid']}',
                        ),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'settings',
                  builder: (_, state) => Scaffold(
                    body: Text('SettingsRoute:${state.pathParameters['eid']}'),
                  ),
                ),
                GoRoute(
                  path: 'recap',
                  builder: (_, state) => Scaffold(
                    body: Text('RecapRoute:${state.pathParameters['eid']}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-1'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((_) => Stream<Event?>.value(ev)),
          groupDetailProvider(
            groupId,
          ).overrideWith((_) => Stream<Group?>.value(group)),
          eventExpensesProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(expenses)),
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(const [])),
          groupMembersProvider(groupId).overrideWith(
            (_) =>
                Stream.value([member('uid-1', 'Mona'), member('uid-2', 'Nasser')]),
          ),
          activityServiceProvider.overrideWithValue(
            ActivityService.withFirestore(FakeFirebaseFirestore()),
          ),
          ...extraOverrides,
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Expenses is the default tab — ledger rows, no settle body', (
    tester,
  ) async {
    await pumpTabbedEvent(tester, ev: event(), expenses: [expense()]);

    expect(find.byKey(EventKeys.tabBar), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.byType(SettleUpPageBody), findsNothing);
  });

  testWidgets('#1067 tabs expose button role and selected state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    addTearDown(handle.dispose);
    await pumpTabbedEvent(tester, ev: event(), expenses: [expense()]);

    final l10n = AppLocalizations.of(
      tester.element(find.byKey(EventKeys.tabBar)),
    );
    final expenses = tester.getSemantics(
      find.bySemanticsLabel(l10n.eventTabExpenses),
    );
    final settleUp = tester.getSemantics(
      find.bySemanticsLabel(l10n.eventTabSettleUp),
    );

    expect(expenses.flagsCollection.isButton, isTrue);
    expect(expenses.flagsCollection.isSelected, Tristate.isTrue);
    expect(settleUp.flagsCollection.isButton, isTrue);
    expect(settleUp.flagsCollection.isSelected, Tristate.isFalse);
  });

  testWidgets('#1067 tab hit region is >=44dp without inflating its pill', (
    tester,
  ) async {
    await pumpTabbedEvent(tester, ev: event(), expenses: [expense()]);

    final tab = find.byKey(EventKeys.tabExpenses);
    final hitRegion = find.descendant(
      of: tab,
      matching: find.byType(GestureDetector),
    );
    final paintedPill = find.descendant(
      of: tab,
      matching: find.byType(AnimatedContainer),
    );
    final paintedTrack = find.byKey(const Key('event_tab_bar_track'));

    expect(tester.getSize(hitRegion).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(paintedPill).height, lessThan(44));
    expect(tester.getSize(paintedTrack).height, lessThan(44));
  });

  testWidgets('tapping Settle up shows the who-pays-whom plan', (tester) async {
    await pumpTabbedEvent(tester, ev: event(), expenses: [expense()]);

    await tester.tap(find.byKey(EventKeys.tabSettleUp));
    await tester.pumpAndSettle();

    expect(find.byType(SettleUpPageBody), findsOneWidget);
    // Ledger panel stays alive (IndexedStack) but is hidden.
    expect(find.text('Dinner', skipOffstage: true), findsNothing);
  });

  testWidgets('tapping Activity shows the feed panel', (tester) async {
    await pumpTabbedEvent(tester, ev: event(), expenses: [expense()]);

    await tester.tap(find.byKey(EventKeys.tabActivity));
    await tester.pumpAndSettle();

    // Empty fake backend → the activity empty state renders inside the tab.
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(EventKeys.tabBar)),
    );
    expect(find.text(l10n.activityNoActivityTitle), findsOneWidget);
  });

  testWidgets('Recap tab is hidden while the event is open', (tester) async {
    await pumpTabbedEvent(tester, ev: event(), expenses: [expense()]);
    expect(find.byKey(EventKeys.tabRecap), findsNothing);
  });

  testWidgets('Recap tab appears on a closed event and renders the recap', (
    tester,
  ) async {
    await pumpTabbedEvent(
      tester,
      ev: event(isClosed: true, closedBy: 'uid-1'),
      expenses: [expense()],
    );

    final recapTab = find.byKey(EventKeys.tabRecap);
    expect(recapTab, findsOneWidget);
    await tester.tap(recapTab);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byKey(EventKeys.tabBar)),
    );
    expect(find.text(l10n.recapTotalSpent), findsOneWidget);
  });

  testWidgets('FAB routes to /ledger/add on an open event', (tester) async {
    await pumpTabbedEvent(tester, ev: event(), expenses: [expense()]);

    await tester.tap(find.byKey(EventKeys.addExpenseFab));
    await tester.pumpAndSettle();

    expect(find.text('AddExpenseRoute:$eventId'), findsOneWidget);
  });

  testWidgets('#723 closed event: FAB absent, banner present', (tester) async {
    await pumpTabbedEvent(
      tester,
      ev: event(isClosed: true, closedBy: 'uid-1'),
      expenses: [expense()],
    );

    expect(find.byKey(EventKeys.addExpenseFab), findsNothing);
    expect(find.byKey(EventKeys.closedBanner), findsOneWidget);
  });

  testWidgets(
    '#708 closed banner "View receipt" switches to the Recap tab (no push)',
    (tester) async {
      await pumpTabbedEvent(
        tester,
        ev: event(isClosed: true, closedBy: 'uid-1'),
        expenses: [expense()],
      );

      await tester.tap(find.byKey(EventKeys.closedBannerViewReceipt));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(EventKeys.tabBar)),
      );
      expect(find.text(l10n.recapTotalSpent), findsOneWidget);
      expect(find.text('RecapRoute:$eventId'), findsNothing);
    },
  );

  testWidgets(
    '#204 review sheet fires on first Settle tab activation, not event open',
    (tester) async {
      await pumpTabbedEvent(
        tester,
        ev: event(),
        // Exact split → review-worthy (detectReviewWorthyExpenses flags it).
        expenses: [expense(splitMode: SplitMode.exact)],
      );

      expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);

      await tester.tap(find.byKey(EventKeys.tabSettleUp));
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    },
  );

  testWidgets(
    'header renders one balance line per currency — never a summed amount',
    (tester) async {
      // OMR: uid-1 owed 10; USD: uid-1 owes 15 → two lines, mixed signs.
      UserBalance balance(String uid, String name, String net) => UserBalance(
        participantId: uid,
        displayName: name,
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.parse(net),
      );
      final exp = expense();
      await pumpTabbedEvent(
        tester,
        ev: event(),
        expenses: [exp],
        extraOverrides: [
          ledgerViewProvider(eventRef).overrideWithValue((
            participants: const [],
            balances: {
              'OMR': [
                balance('uid-1', 'Mona', '10.000'),
                balance('uid-2', 'Nasser', '-10.000'),
              ],
              'USD': [
                balance('uid-1', 'Mona', '-15.00'),
                balance('uid-2', 'Nasser', '15.00'),
              ],
            },
            eventTotal: BalanceCalculator.calculateTotalExpensesByCurrency([
              exp,
            ]),
            rosterDisplayNames: const {'uid-1': 'Mona', 'uid-2': 'Nasser'},
            expensePayerDisplayNames: const {},
            settlementDisplayNames: const {},
            owedByExpenseId: const {},
          )),
        ],
      );

      final header = find.byKey(EventKeys.balanceHeader);
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.textContaining('10.000')),
        findsWidgets,
      );
      expect(
        find.descendant(of: header, matching: find.textContaining('USD')),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'header collapses on scroll into a compact amount and re-expands',
    (tester) async {
      // Enough day cards to make the Expenses panel actually scroll.
      final many = [
        for (var i = 0; i < 20; i++)
          Expense(
            id: 'x$i',
            tripId: eventId,
            payerParticipantId: 'uid-2',
            amount: Decimal.parse('5.000'),
            description: 'Item $i',
            scope: ExpenseScope.global,
            createdAt: DateTime(2026, 1, 1).add(Duration(days: i)),
            createdBy: 'uid-2',
            currency: 'OMR',
          ),
      ];
      await pumpTabbedEvent(tester, ev: event(), expenses: many);

      expect(find.byKey(EventKeys.balanceHeader), findsOneWidget);
      expect(find.byKey(EventKeys.headerCompactAmount), findsNothing);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.balanceHeader), findsNothing);
      expect(find.byKey(EventKeys.headerCompactAmount), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.balanceHeader), findsOneWidget);
      expect(find.byKey(EventKeys.headerCompactAmount), findsNothing);
    },
  );

  testWidgets('back button returns to the group route', (tester) async {
    await pumpTabbedEvent(tester, ev: event());

    await tester.tap(find.byIcon(Iconsax.arrow_left));
    await tester.pumpAndSettle();

    expect(find.text('GroupRoute:$groupId'), findsOneWidget);
  });
}
