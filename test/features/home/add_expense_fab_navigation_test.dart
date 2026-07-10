import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/active_journeys_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/widgets/bottom_nav_shell.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/screens/add_expense_screen.dart';
import 'package:safar/features/ledger/widgets/expense_editor/where_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

const _uid = 'uid-user';

Group makeGroup({required String id, String? name}) {
  return Group(
    id: id,
    name: name ?? 'Group $id',
    inviteCode: 'ABC123',
    createdBy: _uid,
    memberIds: const [_uid],
    createdAt: DateTime(2026),
  );
}

Event makeEvent({
  required String id,
  required String groupId,
  String? name,
  DateTime? startDate,
  DateTime? endDate,
  bool isClosed = false,
  List<String> participantIds = const [_uid],
}) {
  return Event(
    id: id,
    name: name ?? 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: _uid,
    participantIds: participantIds,
    participantNames: {for (final p in participantIds) p: 'Name $p'},
    modules: const EventModules(),
    startDate: startDate,
    endDate: endDate,
    isClosed: isClosed,
    createdAt: startDate ?? DateTime(2026),
  );
}

Finder _whereCardDestination(String eventName) => find.descendant(
  of: find.byType(WhereCard),
  matching: find.text('Adding to $eventName'),
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  List<Override> overridesFor(Map<Group, List<Event>> data) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserIdProvider.overrideWithValue(_uid),
    userGroupsProvider.overrideWith((ref) => Stream.value(data.keys.toList())),
    crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
    groupEventsProvider.overrideWith((ref, groupId) {
      final entry = data.entries.where((e) => e.key.id == groupId);
      return Stream.value(entry.isEmpty ? const <Event>[] : entry.first.value);
    }),
    groupBalancesProvider.overrideWith(
      (ref, groupId) => const AsyncValue.data((
        balances: <String, List<UserBalance>>{},
        totalSpent: <String, Decimal>{},
        eventCount: 0,
        perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
        memberNames: <String, String>{},
        memberRawNames: <String, String>{},
      )),
    ),
  ];

  Widget buildApp(List<Override> overrides, {Locale? locale}) {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const BottomNavShell(child: Text('Dashboard')),
        ),
        GoRoute(
          path: '/create-group',
          builder: (_, _) => const Scaffold(body: Text('CreateGroupRoute')),
        ),
        GoRoute(
          path: '/group/:gid/event/:eid/ledger/add',
          builder: (_, state) => Scaffold(
            body: Text(
              'Add:${state.pathParameters['gid']}/${state.pathParameters['eid']}',
            ),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        locale: locale,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  group('AddExpenseFab on the tab shell (#364)', () {
    testWidgets('visible on Groups and Activity tabs, hidden on Profile', (
      tester,
    ) async {
      final group = makeGroup(id: 'g1');
      await tester.pumpWidget(
        buildApp(
          overridesFor({
            group: [makeEvent(id: 'e1', groupId: 'g1')],
          }),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.addExpenseFab), findsOneWidget);

      await tester.tap(find.byKey(HomeKeys.bottomNavActivity));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(HomeKeys.addExpenseFab), findsOneWidget);

      await tester.tap(find.byKey(HomeKeys.bottomNavProfile));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(HomeKeys.addExpenseFab), findsNothing);
    });

    testWidgets('hidden on the zero-groups empty state (#807)', (tester) async {
      // No groups: the empty state already carries its own "create group"
      // CTA — the FAB would be a redundant second entry point to the same
      // dead end (the target sheet's own empty body).
      await tester.pumpWidget(buildApp(overridesFor({})));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.addExpenseFab), findsNothing);
    });

    testWidgets(
      'fast path: exactly one open event → pushes its add route, no sheet',
      (tester) async {
        final group = makeGroup(id: 'g1');
        await tester.pumpWidget(
          buildApp(
            overridesFor({
              group: [makeEvent(id: 'e1', groupId: 'g1')],
            }),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(HomeKeys.addExpenseFab));
        await tester.pumpAndSettle();

        expect(find.text('Add:g1/e1'), findsOneWidget);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);
      },
    );

    testWidgets(
      'no fast path when the sole open event is not mine to write into '
      '(non-participant, Gate rd-1 P2)',
      (tester) async {
        final group = makeGroup(id: 'g1');
        await tester.pumpWidget(
          buildApp(
            overridesFor({
              group: [
                makeEvent(
                  id: 'e1',
                  groupId: 'g1',
                  participantIds: const ['uid-other'],
                ),
              ],
            }),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(HomeKeys.addExpenseFab));
        await tester.pumpAndSettle();

        // Not a valid target → the sheet opens instead of a dead-end push.
        expect(find.text('Add:g1/e1'), findsNothing);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
      },
    );

    testWidgets(
      'two open events in one group → pushes the _priority-first event '
      '(was: opened the picker sheet — #900)',
      (tester) async {
        final now = DateTime.now();
        final group = makeGroup(id: 'g1');
        await tester.pumpWidget(
          buildApp(
            overridesFor({
              group: [
                makeEvent(
                  id: 'e1',
                  groupId: 'g1',
                  name: 'Ongoing Trip',
                  startDate: now.subtract(const Duration(days: 1)),
                  endDate: now.add(const Duration(days: 1)),
                ),
                makeEvent(id: 'e2', groupId: 'g1', name: 'House Ledger'),
              ],
            }),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(HomeKeys.addExpenseFab));
        await tester.pumpAndSettle();

        // Ongoing (priority 0) beats the undated House Ledger — the ranked
        // `preferred` getter fires the fast path even within one group; the
        // "browse all" sheet path is covered by the group/no-match tests
        // below, and the editor's own "change" affordance is the recovery
        // path if the guess is wrong (see the "change destination" group).
        expect(find.text('Add:g1/e1'), findsOneWidget);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);
      },
    );

    testWidgets(
      'two groups, each with one open event → pushes the _priority-first '
      'event across groups, not the sheet (#900, spec §1 test (a))',
      (tester) async {
        final now = DateTime.now();
        final g1 = makeGroup(id: 'g1');
        final g2 = makeGroup(id: 'g2');
        await tester.pumpWidget(
          buildApp(
            overridesFor({
              g1: [
                makeEvent(
                  id: 'e1',
                  groupId: 'g1',
                  name: 'Ongoing Trip',
                  startDate: now.subtract(const Duration(days: 1)),
                  endDate: now.add(const Duration(days: 1)),
                ),
              ],
              g2: [
                makeEvent(
                  id: 'e2',
                  groupId: 'g2',
                  name: 'Upcoming Trip',
                  startDate: now.add(const Duration(days: 10)),
                  endDate: now.add(const Duration(days: 12)),
                ),
              ],
            }),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(HomeKeys.addExpenseFab));
        await tester.pumpAndSettle();

        // Ongoing (priority 0, group g1) outranks an upcoming event 10 days
        // out (group g2) — the FAB pushes the LOCATION directly, no sheet.
        expect(find.text('Add:g1/e1'), findsOneWidget);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);
      },
    );

    testWidgets(
      '!allResolved (a second group still loading) → sheet, never a false '
      'fast path (#900, spec §1 test (b))',
      (tester) async {
        final g1 = makeGroup(id: 'g1');
        final g2 = makeGroup(id: 'g2');
        final neverController = StreamController<List<Event>>();
        addTearDown(neverController.close);

        await tester.pumpWidget(
          buildApp([
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentUserIdProvider.overrideWithValue(_uid),
            userGroupsProvider.overrideWith((ref) => Stream.value([g1, g2])),
            crossGroupActivityProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
            // g1 resolves with an active (undated ⇒ always-active) open
            // event — without the `!allResolved` guard, `active.first` would
            // fire the fast path on this partial data alone.
            groupEventsProvider.overrideWith((ref, groupId) {
              if (groupId == 'g1') {
                return Stream.value([makeEvent(id: 'e1', groupId: 'g1')]);
              }
              return neverController.stream; // g2: never resolves.
            }),
            groupBalancesProvider.overrideWith(
              (ref, groupId) => const AsyncValue.data((
                balances: <String, List<UserBalance>>{},
                totalSpent: <String, Decimal>{},
                eventCount: 0,
                perEventBreakdown:
                    <String, Map<String, Map<String, Decimal>>>{},
                memberNames: <String, String>{},
                memberRawNames: <String, String>{},
              )),
            ),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(HomeKeys.addExpenseFab));
        await tester.pumpAndSettle();

        expect(find.text('Add:g1/e1'), findsNothing);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
      },
    );

    testWidgets('zero open targets across existing groups → sheet '
        '(#900, spec §1 test (c))', (tester) async {
      final group = makeGroup(id: 'g1');
      await tester.pumpWidget(
        buildApp(
          overridesFor({
            // Only a closed event — not an open target at all.
            group: [makeEvent(id: 'e1', groupId: 'g1', isClosed: true)],
          }),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.addExpenseFab));
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
    });
  });

  group('Editor "change destination" affordance (#900, spec §1 test (d))', () {
    final categories = [
      ExpenseCategory(
        id: 'food',
        tripId: 'e1',
        name: 'Food',
        icon: 'food',
        color: '#C2693B',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    Widget buildEditorApp({
      required Group startGroup,
      required Event startEvent,
      required Group otherGroup,
      required Event otherEvent,
    }) {
      final router = GoRouter(
        initialLocation:
            '/group/${startGroup.id}/event/${startEvent.id}/ledger/add',
        routes: [
          GoRoute(
            path: '/group/:gid/event/:eid/ledger/add',
            builder: (_, state) => AddExpenseScreen(
              groupId: state.pathParameters['gid']!,
              eventId: state.pathParameters['eid']!,
            ),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(_uid),
          userGroupsProvider.overrideWith(
            (ref) => Stream.value([startGroup, otherGroup]),
          ),
          groupDetailProvider(
            startGroup.id,
          ).overrideWith((ref) => Stream.value(startGroup)),
          groupDetailProvider(
            otherGroup.id,
          ).overrideWith((ref) => Stream.value(otherGroup)),
          groupEventsProvider(
            startGroup.id,
          ).overrideWith((ref) => Stream.value([startEvent])),
          groupEventsProvider(
            otherGroup.id,
          ).overrideWith((ref) => Stream.value([otherEvent])),
          eventDetailProvider((
            groupId: startGroup.id,
            eventId: startEvent.id,
          )).overrideWith((ref) => Stream.value(startEvent)),
          eventDetailProvider((
            groupId: otherGroup.id,
            eventId: otherEvent.id,
          )).overrideWith((ref) => Stream.value(otherEvent)),
          tripCategoriesProvider(
            startEvent.id,
          ).overrideWith((ref) => Stream.value(categories)),
          tripCategoriesProvider(
            otherEvent.id,
          ).overrideWith((ref) => Stream.value(categories)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Stack(
            children: [
              ?child,
              // Pre-warms addExpenseTargetsProvider (both groups' event
              // streams) before "change" ever opens the sheet — mirrors
              // production, where AddExpenseFab already keeps it warm
              // continuously from app start. Without this, the sheet's own
              // first read races the group-events streams and its `_view`
              // (resolved once) pins to the browse-all fallback.
              Consumer(
                builder: (context, ref, _) {
                  ref.watch(addExpenseTargetsProvider);
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );
    }

    testWidgets(
      'tap opens the target sheet; picking a second event pushes a fresh '
      'add route for that eid',
      (tester) async {
        final g1 = makeGroup(id: 'g1');
        final g2 = makeGroup(id: 'g2');
        final e1 = makeEvent(id: 'e1', groupId: 'g1', name: 'Trip One');
        final e2 = makeEvent(id: 'e2', groupId: 'g2', name: 'Trip Two');

        // The "change" affordance sits low in the editor's scroll view —
        // widen the surface so it's on-screen without scrolling.
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildEditorApp(
            startGroup: g1,
            startEvent: e1,
            otherGroup: g2,
            otherEvent: e2,
          ),
        );
        await tester.pumpAndSettle();

        // Add mode, pristine — the affordance names the current target.
        expect(_whereCardDestination('Trip One'), findsOneWidget);
        final changeButton = find.byKey(
          LedgerKeys.editorChangeDestinationButton,
        );
        expect(changeButton, findsOneWidget);

        await tester.tap(changeButton);
        await tester.pumpAndSettle();

        expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
        expect(find.text('Trip Two'), findsOneWidget);

        await tester.tap(find.text('Trip Two'));
        await tester.pumpAndSettle();

        // Replaced, not stacked — the fresh editor names the new target.
        expect(_whereCardDestination('Trip Two'), findsOneWidget);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);
        // The discriminator that actually proves `pushReplacement` (not a
        // plain `push`): with a replace, the stack holds exactly ONE add
        // page, so there is nothing left to pop back into — a `push` would
        // leave the abandoned "Trip One" draft one pop away (findsNothing on
        // its text is not a valid proxy: an offstage/obscured page under an
        // opaque route wouldn't render its text either way).
        final editorContext = tester.element(_whereCardDestination('Trip Two'));
        expect(Navigator.of(editorContext).canPop(), isFalse);
      },
    );

    testWidgets(
      'dirty form → discard confirm first; "keep editing" cancels, no sheet; '
      '"discard" then opens the sheet',
      (tester) async {
        final g1 = makeGroup(id: 'g1');
        final g2 = makeGroup(id: 'g2');
        final e1 = makeEvent(id: 'e1', groupId: 'g1', name: 'Trip One');
        final e2 = makeEvent(id: 'e2', groupId: 'g2', name: 'Trip Two');

        // The "change" affordance sits low in the editor's scroll view —
        // widen the surface so it's on-screen without scrolling (a
        // scroll-to-visible round trip across a dialog open/close cycle is
        // flaky: the on-screen keyboard's viewInsets shift the scroll extent
        // between frames).
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildEditorApp(
            startGroup: g1,
            startEvent: e1,
            otherGroup: g2,
            otherEvent: e2,
          ),
        );
        await tester.pumpAndSettle();

        // Dirty the form (same amount field the discard-guard suite uses).
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.pump();

        final changeButton = find.byKey(
          LedgerKeys.editorChangeDestinationButton,
        );
        await tester.tap(changeButton);
        await tester.pump();

        // Same add-discard confirm as X/system-back — not the sheet yet.
        expect(find.text('Discard this expense?'), findsOneWidget);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);

        await tester.tap(find.text('Keep editing'));
        await tester.pump();

        // Cancelled: dialog gone, sheet never opened, draft still there.
        expect(find.text('Discard this expense?'), findsNothing);
        expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);
        expect(_whereCardDestination('Trip One'), findsOneWidget);

        await tester.tap(changeButton);
        await tester.pump();
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        // Confirmed: the sheet opens (no premature push before the confirm).
        expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
        expect(find.text('Trip Two'), findsOneWidget);
      },
    );
  });
}
