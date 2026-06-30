import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/providers/event_recap_provider.dart';
import 'package:safar/features/events/screens/event_recap_screen.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/ledger_view_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #721 deferred item — the recap settle CTA navigates to the existing
/// event-level and group-level settle-up routes. Router-aware harness (the
/// `pumpRihlaApp` helper wraps a plain MaterialApp, so it can't resolve
/// `context.push`); mirrors `event_command_center_test._pumpEventHubRouter`.
void main() {
  const eventRef = (groupId: 'g1', eventId: 'e1');
  Decimal d(String s) => Decimal.parse(s);

  UserBalance ub(String id, String paid, String owed, String net) =>
      UserBalance(
        participantId: id,
        displayName: id,
        totalPaid: d(paid),
        totalOwed: d(owed),
        netBalance: d(net),
      );

  Event event() => Event(
        id: 'e1',
        name: 'Jabal Trip',
        type: EventType.trip,
        groupId: 'g1',
        createdBy: 'a',
        participantIds: const ['a', 'b'],
        participantNames: const {'a': 'Alice', 'b': 'Bob'},
        modules: const EventModules(),
        createdAt: DateTime(2026, 3, 1),
      );

  // a net +50, b net -50 → OUTSTANDING → CTA shows.
  EventRecap outstandingRecap() => EventRecap.from(
        eventId: 'e1',
        eventName: 'Jabal Trip',
        startDate: null,
        endDate: null,
        participantIds: const ['a', 'b'],
        expenseCount: 1,
        totalSpentByCurrency: {'OMR': d('100')},
        balances: {
          'OMR': [ub('a', '100', '50', '50'), ub('b', '0', '50', '-50')],
        },
        uid: 'a',
      );

  LedgerView fakeLedgerView() => (
        participants: const [],
        balances: const {},
        eventTotal: const {},
        rosterDisplayNames: const {'a': 'Alice', 'b': 'Bob'},
        expensePayerDisplayNames: const {},
        settlementDisplayNames: const {},
        owedByExpenseId: const {},
      );

  Future<void> pumpRecapRouter(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/group/g1/event/e1/recap',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (_, _) => const Scaffold(),
          routes: [
            GoRoute(
              path: 'settle-up',
              builder: (_, state) => Scaffold(
                body: Text('GroupSettleUp:${state.pathParameters['gid']}'),
              ),
            ),
            GoRoute(
              path: 'event/:eid',
              builder: (_, _) => const Scaffold(),
              routes: [
                GoRoute(
                  path: 'recap',
                  builder: (_, state) => EventRecapScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
                GoRoute(
                  path: 'ledger',
                  builder: (_, _) => const Scaffold(),
                  routes: [
                    GoRoute(
                      path: 'settle-up',
                      builder: (_, state) => Scaffold(
                        body:
                            Text('EventSettleUp:${state.pathParameters['eid']}'),
                      ),
                    ),
                  ],
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
          eventDetailProvider(eventRef)
              .overrideWith((_) => Stream.value(event())),
          eventRecapProvider(eventRef).overrideWithValue(outstandingRecap()),
          ledgerViewProvider(eventRef).overrideWithValue(fakeLedgerView()),
          currentUserIdProvider.overrideWithValue('a'),
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
  }

  testWidgets('Settle this event → event-level settle-up route', (tester) async {
    await pumpRecapRouter(tester);
    final button = find.byKey(EventKeys.recapSettleEventButton);
    expect(button, findsOneWidget);

    // CTA sits at the bottom of the scroll view — scroll it on-screen first.
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('EventSettleUp:e1'), findsOneWidget);
  });

  testWidgets('Settle at group level → group-level settle-up route',
      (tester) async {
    await pumpRecapRouter(tester);
    final button = find.byKey(EventKeys.recapSettleGroupButton);
    expect(button, findsOneWidget);

    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('GroupSettleUp:g1'), findsOneWidget);
  });
}
