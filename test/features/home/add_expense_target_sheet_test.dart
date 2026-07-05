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
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/widgets/add_expense_target_sheet.dart';
import 'package:safar/features/home/widgets/bottom_nav_shell.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
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
}) {
  return Event(
    id: id,
    name: name ?? 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: _uid,
    participantIds: const [_uid],
    participantNames: const {_uid: 'Nasser'},
    modules: const EventModules(),
    startDate: startDate,
    endDate: endDate,
    isClosed: isClosed,
    createdAt: startDate ?? DateTime(2026),
  );
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  List<Override> overridesFor(Map<Group, List<Event>> data) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserIdProvider.overrideWithValue(_uid),
    userGroupsProvider.overrideWith(
      (ref) => Stream.value(data.keys.toList()),
    ),
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

  // Opens the sheet directly rather than via the FAB (#900): the FAB now
  // fast-paths through `AddExpenseTargets.preferred` whenever ANY open
  // target exists anywhere (in-window or not), so tapping it no longer
  // reliably reaches the sheet for these multi-target fixtures — that
  // routing decision has its own dedicated coverage in
  // add_expense_fab_navigation_test.dart. This file tests the sheet's own
  // rendering/filtering/navigation once shown, independent of how it opened.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    unawaited(
      AddExpenseTargetSheet.show(tester.element(find.text('Dashboard'))),
    );
    await tester.pumpAndSettle();
  }

  group('AddExpenseTargetSheet (#364)', () {
    testWidgets('closed events never appear as rows (#723)', (tester) async {
      final group = makeGroup(id: 'g1');
      await tester.pumpWidget(
        buildApp(
          overridesFor({
            group: [
              makeEvent(id: 'e1', groupId: 'g1', name: 'Open Event'),
              makeEvent(
                id: 'e2',
                groupId: 'g1',
                name: 'Closed Event',
                isClosed: true,
              ),
              makeEvent(id: 'e3', groupId: 'g1', name: 'Second Open'),
            ],
          }),
        ),
      );
      await openSheet(tester);

      expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
      expect(find.text('Open Event'), findsOneWidget);
      expect(find.text('Second Open'), findsOneWidget);
      expect(find.text('Closed Event'), findsNothing);
    });

    testWidgets(
      'browse-all: group list → single-open-event group pushes directly',
      (tester) async {
        final g1 = makeGroup(id: 'g1', name: 'Salalah Khareef');
        final g2 = makeGroup(id: 'g2', name: 'Dubai Trip');
        await tester.pumpWidget(
          buildApp(
            overridesFor({
              g1: [
                makeEvent(id: 'a', groupId: 'g1', name: 'Wadi Darbat'),
                makeEvent(id: 'b', groupId: 'g1', name: 'Day Two'),
              ],
              g2: [makeEvent(id: 'c', groupId: 'g2', name: 'Desert Safari')],
            }),
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(HomeKeys.addExpenseSheetBrowseAll));
        await tester.pumpAndSettle();

        expect(find.text('Salalah Khareef'), findsOneWidget);
        expect(find.text('Dubai Trip'), findsOneWidget);

        // g2 has exactly one open event → tapping it skips the event page.
        await tester.tap(find.text('Dubai Trip'));
        await tester.pumpAndSettle();

        expect(find.text('Add:g2/c'), findsOneWidget);
      },
    );

    testWidgets(
      'browse-all: multi-event group shows its event page, tap pushes',
      (tester) async {
        final g1 = makeGroup(id: 'g1', name: 'Salalah Khareef');
        await tester.pumpWidget(
          buildApp(
            overridesFor({
              g1: [
                makeEvent(id: 'a', groupId: 'g1', name: 'Wadi Darbat'),
                makeEvent(id: 'b', groupId: 'g1', name: 'Day Two'),
              ],
            }),
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(HomeKeys.addExpenseSheetBrowseAll));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Salalah Khareef'));
        await tester.pumpAndSettle();

        // Event page for the group, with a back affordance.
        expect(find.byKey(HomeKeys.addExpenseSheetBack), findsOneWidget);
        await tester.tap(find.text('Day Two'));
        await tester.pumpAndSettle();

        expect(find.text('Add:g1/b'), findsOneWidget);
      },
    );

    testWidgets('group with zero open events is a disabled row', (
      tester,
    ) async {
      final g1 = makeGroup(id: 'g1', name: 'Live Group');
      final g2 = makeGroup(id: 'g2', name: 'Frozen Group');
      await tester.pumpWidget(
        buildApp(
          overridesFor({
            g1: [
              makeEvent(id: 'a', groupId: 'g1'),
              makeEvent(id: 'b', groupId: 'g1'),
            ],
            g2: [makeEvent(id: 'c', groupId: 'g2', isClosed: true)],
          }),
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(HomeKeys.addExpenseSheetBrowseAll));
      await tester.pumpAndSettle();

      final frozenTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Frozen Group'),
          matching: find.byType(ListTile),
        ),
      );
      expect(frozenTile.enabled, isFalse);
    });

    testWidgets(
      'zero groups → empty body, Create-group CTA routes /create-group',
      (tester) async {
        await tester.pumpWidget(buildApp(overridesFor({})));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // #807 hides the FAB on the zero-groups empty state, so the sheet
        // can't be opened through it here. The empty body stays reachable
        // (a session's last group can vanish while the sheet is open), so
        // open the sheet directly to keep pinning it.
        expect(find.byKey(HomeKeys.addExpenseFab), findsNothing);
        unawaited(
          AddExpenseTargetSheet.show(tester.element(find.text('Dashboard'))),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
        await tester.tap(find.byKey(HomeKeys.addExpenseSheetCreateGroup));
        await tester.pumpAndSettle();

        expect(find.text('CreateGroupRoute'), findsOneWidget);
      },
    );

    testWidgets(
      'groups exist but zero window-active open events → opens on the '
      'browse-all group list',
      (tester) async {
        final now = DateTime.now();
        final g1 = makeGroup(id: 'g1', name: 'Old Group');
        await tester.pumpWidget(
          buildApp(
            overridesFor({
              g1: [
                // Open but ended 20 days ago — outside the active window.
                makeEvent(
                  id: 'a',
                  groupId: 'g1',
                  name: 'Long Ended',
                  startDate: now.subtract(const Duration(days: 30)),
                  endDate: now.subtract(const Duration(days: 20)),
                ),
                makeEvent(
                  id: 'b',
                  groupId: 'g1',
                  name: 'Also Ended',
                  startDate: now.subtract(const Duration(days: 40)),
                  endDate: now.subtract(const Duration(days: 35)),
                ),
              ],
            }),
          ),
        );
        await openSheet(tester);

        // Group list directly (no flattened rows to show).
        expect(find.text('Old Group'), findsOneWidget);
        await tester.tap(find.text('Old Group'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Long Ended'));
        await tester.pumpAndSettle();

        expect(find.text('Add:g1/a'), findsOneWidget);
      },
    );

    testWidgets('renders under RTL (Arabic) and rows still push', (
      tester,
    ) async {
      final group = makeGroup(id: 'g1');
      await tester.pumpWidget(
        buildApp(
          overridesFor({
            group: [
              makeEvent(id: 'e1', groupId: 'g1', name: 'Open One'),
              makeEvent(id: 'e2', groupId: 'g1', name: 'Open Two'),
            ],
          }),
          locale: const Locale('ar'),
        ),
      );
      await openSheet(tester);

      expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
      await tester.tap(find.text('Open Two'));
      await tester.pumpAndSettle();

      expect(find.text('Add:g1/e2'), findsOneWidget);
    });
  });
}
