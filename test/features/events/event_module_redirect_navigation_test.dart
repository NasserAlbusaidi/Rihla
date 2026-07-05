import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/router/app_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/keys/activity_keys.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/activity/utils/activity_nav.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/events/screens/event_recap_screen.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/add_expense_screen.dart';
import 'package:safar/features/ledger/screens/edit_expense_screen.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// PR-5 §4 (Gate-cleared `docs/plans/2026-07-05-falaj-pr5-ia-spec.md`) —
/// module-route consolidation. `…/ledger` and `…/activity` are now
/// route-level redirects into the hub's `?tab=` query; `…/recap`,
/// `…/ledger/add`, `…/ledger/edit/:expId`, and `…/ledger/settle-up` stay real
/// screens (O1 closed). This file exercises the PRODUCTION redirect
/// functions (`eventLedgerModuleRedirect` / `eventActivityModuleRedirect` /
/// `EventTab.fromQuery`) through a router that mirrors `app_router.dart`'s
/// event subtree — the ancestor `/group/:gid` is a stub (out of scope here;
/// covered by `group_detail_navigation_test.dart`), every module screen is
/// the real production widget.
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);
  const currentUid = 'uid-1'; // Mona
  const otherUid = 'uid-2'; // Nasser

  Event buildEvent({bool isClosed = false}) => Event(
    id: eventId,
    name: 'Marrakech',
    type: EventType.trip,
    groupId: groupId,
    createdBy: currentUid,
    participantIds: const [currentUid, otherUid],
    participantNames: const {currentUid: 'Mona', otherUid: 'Nasser'},
    modules: const EventModules(),
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 1, 3),
    createdAt: DateTime(2026, 1, 1),
    isClosed: isClosed,
    closedAt: isClosed ? DateTime(2026, 5, 1) : null,
    closedBy: isClosed ? currentUid : null,
  );

  final fixtureGroup = Group(
    id: groupId,
    name: 'Friends',
    inviteCode: 'ABC123',
    createdBy: currentUid,
    memberIds: const [currentUid, otherUid],
    currency: 'OMR',
    createdAt: DateTime(2026, 1, 1),
  );

  // Nasser (otherUid) pays 20 OMR, equal split → Mona owes Nasser 10.000 —
  // exactly one settlement tile (for the settle-up preselect test), and
  // non-empty ledger content ('Dinner') that doubles as the
  // Expenses-tab-is-active marker throughout this file.
  final expense = Expense(
    id: 'exp-1',
    tripId: eventId,
    payerParticipantId: otherUid,
    amount: Decimal.parse('20.000'),
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 2),
    createdBy: otherUid,
    currency: 'OMR',
  );

  GroupMember member(String uid, String name) => GroupMember(
    id: 'doc-$uid',
    groupId: groupId,
    userId: uid,
    displayName: name,
    role: uid == currentUid ? 'CREATOR' : 'MEMBER',
    joinedAt: DateTime(2026, 1, 1),
  );

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  List<Override> baseOverrides({Event? event}) {
    final fakeDb = FakeFirebaseFirestore();
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(currentUid),
      eventDetailProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(event ?? buildEvent())),
      groupDetailProvider(
        groupId,
      ).overrideWith((ref) => Stream.value(fixtureGroup)),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value([expense])),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      groupMembersProvider(groupId).overrideWith(
        (ref) => Stream.value([
          member(currentUid, 'Mona'),
          member(otherUid, 'Nasser'),
        ]),
      ),
      activityServiceProvider.overrideWithValue(
        ActivityService.withFirestore(fakeDb),
      ),
      settlementServiceProvider.overrideWithValue(
        SettlementService.withFirestore(fakeDb),
      ),
      groupActivityServiceProvider.overrideWithValue(
        GroupActivityService.withFirestore(fakeDb),
      ),
    ];
  }

  // Mirrors app_router.dart's event subtree exactly, wiring the SAME
  // production redirect functions and EventTab.fromQuery — only the
  // out-of-scope `/group/:gid` ancestor and page transitions are stubbed.
  GoRouter buildRouter(String initialLocation) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid',
          builder: (_, state) => Scaffold(
            body: Text('GroupDetail:${state.pathParameters['gid']}'),
          ),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (_, state) => EventCommandCenter(
                groupId: state.pathParameters['gid']!,
                eventId: state.pathParameters['eid']!,
                initialTab: EventTab.fromQuery(
                  state.uri.queryParameters['tab'],
                ),
              ),
              routes: [
                GoRoute(
                  path: 'ledger',
                  redirect: (context, state) =>
                      eventLedgerModuleRedirect(state),
                  builder: (_, state) => LedgerScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'add',
                      builder: (_, state) => AddExpenseScreen(
                        groupId: state.pathParameters['gid']!,
                        eventId: state.pathParameters['eid']!,
                      ),
                    ),
                    GoRoute(
                      path: 'edit/:expId',
                      builder: (_, state) => EditExpenseScreen(
                        groupId: state.pathParameters['gid']!,
                        eventId: state.pathParameters['eid']!,
                        expenseId: state.pathParameters['expId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'settle-up',
                      builder: (_, state) => SettleUpScreen(
                        groupId: state.pathParameters['gid']!,
                        eventId: state.pathParameters['eid']!,
                        preSelectedMemberId:
                            state.uri.queryParameters['memberId'],
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'activity',
                  redirect: (context, state) =>
                      eventActivityModuleRedirect(state),
                  builder: (_, state) => ActivityFeedScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
                GoRoute(
                  path: 'recap',
                  builder: (_, state) => EventRecapScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<GoRouter> pump(
    WidgetTester tester, {
    required String initialLocation,
    Event? event,
  }) async {
    final router = buildRouter(initialLocation);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(event: event),
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

  group('EventTab.fromQuery — explicit mapping (pure)', () {
    test('expenses/activity/recap map to themselves', () {
      expect(EventTab.fromQuery('expenses'), EventTab.expenses);
      expect(EventTab.fromQuery('activity'), EventTab.activity);
      expect(EventTab.fromQuery('recap'), EventTab.recap);
    });

    test('settleUp, absent, and unknown all fall back to expenses', () {
      expect(EventTab.fromQuery('settleUp'), EventTab.expenses);
      expect(EventTab.fromQuery(null), EventTab.expenses);
      expect(EventTab.fromQuery('bogus'), EventTab.expenses);
    });
  });

  group('(a) cold …/ledger', () {
    testWidgets(
      'lands on exactly ONE hub, Expenses tab; one Back reaches GroupDetail',
      (tester) async {
        await pump(
          tester,
          initialLocation: '/group/$groupId/event/$eventId/ledger',
        );

        expect(find.byType(EventCommandCenter), findsOneWidget);
        expect(find.byKey(EventKeys.tabBar), findsOneWidget);
        // Not the dead full-chrome ledger route — its Scaffold key is absent.
        expect(find.byKey(LedgerKeys.screen), findsNothing);
        expect(find.text('Dinner'), findsOneWidget);

        await tester.tap(find.byIcon(Iconsax.arrow_left).first);
        await tester.pumpAndSettle();

        expect(find.text('GroupDetail:$groupId'), findsOneWidget);
        expect(find.byType(EventCommandCenter), findsNothing);
      },
    );
  });

  group('(b) cold …/activity', () {
    testWidgets('lands on the hub, Activity tab', (tester) async {
      await pump(
        tester,
        initialLocation: '/group/$groupId/event/$eventId/activity',
      );

      expect(find.byType(EventCommandCenter), findsOneWidget);
      expect(find.byKey(EventKeys.tabBar), findsOneWidget);
      // Not the dead full-chrome activity route.
      expect(find.byKey(ActivityKeys.screen), findsNothing);

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(EventKeys.tabBar)),
      );
      expect(find.text(l10n.activityNoActivityTitle), findsOneWidget);
    });
  });

  group('(c) the null-for-children guard is load-bearing', () {
    testWidgets('cold …/ledger/add renders the real editor, not the hub', (
      tester,
    ) async {
      await pump(
        tester,
        initialLocation: '/group/$groupId/event/$eventId/ledger/add',
      );

      expect(find.byKey(LedgerKeys.addExpenseScreen), findsOneWidget);
      expect(find.byKey(EventKeys.tabBar), findsNothing);
    });

    testWidgets(
      'cold …/ledger/edit/:expId renders the real editor, not the hub',
      (tester) async {
        await pump(
          tester,
          initialLocation: '/group/$groupId/event/$eventId/ledger/edit/exp-1',
        );

        expect(find.byKey(LedgerKeys.editExpenseSheet), findsOneWidget);
        expect(find.byKey(EventKeys.tabBar), findsNothing);
      },
    );
  });

  group('(d) …/ledger/settle-up?memberId= stays a real screen', () {
    testWidgets(
      'cold landing renders the real SettleUpScreen, preselecting the member',
      (tester) async {
        await pump(
          tester,
          initialLocation:
              '/group/$groupId/event/$eventId/ledger/settle-up'
              '?memberId=$otherUid',
        );

        expect(find.byKey(LedgerKeys.settleUpScreen), findsOneWidget);
        final tile = tester.widget<GroupSettlementTile>(
          find.byType(GroupSettlementTile),
        );
        expect(tile.isHighlighted, isTrue);
      },
    );
  });

  group('(e) …/recap stays a real screen on open AND closed events', () {
    testWidgets(
      'cold landing on an OPEN event renders EventRecapScreen with the '
      'share affordance reachable',
      (tester) async {
        await pump(
          tester,
          initialLocation: '/group/$groupId/event/$eventId/recap',
          event: buildEvent(),
        );

        expect(find.byKey(EventKeys.recapScreen), findsOneWidget);
        expect(find.byKey(EventKeys.recapShareButton), findsOneWidget);
      },
    );

    testWidgets(
      'cold landing on a CLOSED event renders EventRecapScreen with the '
      'share affordance reachable',
      (tester) async {
        await pump(
          tester,
          initialLocation: '/group/$groupId/event/$eventId/recap',
          event: buildEvent(isClosed: true),
        );

        expect(find.byKey(EventKeys.recapScreen), findsOneWidget);
        expect(find.byKey(EventKeys.recapShareButton), findsOneWidget);
      },
    );
  });

  group('(f) activity-row landings (activityRowTarget → redirect)', () {
    testWidgets('expense_added target renders hub@Expenses', (tester) async {
      final log = GroupActivityLog(
        id: 'log-1',
        type: 'expense_added',
        actorId: otherUid,
        actorName: 'Nasser',
        description: 'added an expense',
        metadata: const {'eventId': eventId},
        timestamp: DateTime(2026, 1, 2),
      );
      final target = activityRowTarget(groupId: groupId, log: log);
      expect(target, '/group/$groupId/event/$eventId/ledger');

      await pump(tester, initialLocation: target);

      expect(find.byType(EventCommandCenter), findsOneWidget);
      expect(find.byKey(EventKeys.tabBar), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
    });

    testWidgets('expense_deleted target renders hub@Activity', (
      tester,
    ) async {
      final log = GroupActivityLog(
        id: 'log-2',
        type: 'expense_deleted',
        actorId: otherUid,
        actorName: 'Nasser',
        description: 'deleted an expense',
        metadata: const {'eventId': eventId},
        timestamp: DateTime(2026, 1, 2),
      );
      final target = activityRowTarget(groupId: groupId, log: log);
      expect(target, '/group/$groupId/event/$eventId/activity');

      await pump(tester, initialLocation: target);

      expect(find.byType(EventCommandCenter), findsOneWidget);
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(EventKeys.tabBar)),
      );
      expect(find.text(l10n.activityNoActivityTitle), findsOneWidget);
    });
  });

  group('(g) hub ?tab=recap on an OPEN event falls back to Expenses', () {
    testWidgets('no crash, Expenses content renders, no Recap tab', (
      tester,
    ) async {
      await pump(
        tester,
        initialLocation: '/group/$groupId/event/$eventId?tab=recap',
        event: buildEvent(),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(EventKeys.tabRecap), findsNothing);
      expect(find.text('Dinner'), findsOneWidget);
    });
  });

  group('(h) hub ?tab= absent/garbage defaults to Expenses', () {
    testWidgets('absent tab query', (tester) async {
      await pump(tester, initialLocation: '/group/$groupId/event/$eventId');

      expect(find.text('Dinner'), findsOneWidget);
    });

    testWidgets('unknown tab query value', (tester) async {
      await pump(
        tester,
        initialLocation: '/group/$groupId/event/$eventId?tab=bogus',
      );

      expect(find.text('Dinner'), findsOneWidget);
    });
  });
}
