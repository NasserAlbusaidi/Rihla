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

    testWidgets('hidden on the zero-groups empty state (#807)', (
      tester,
    ) async {
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

    testWidgets('two open events → opens the picker sheet with both rows', (
      tester,
    ) async {
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

      expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
      expect(find.text('Ongoing Trip'), findsOneWidget);
      expect(find.text('House Ledger'), findsOneWidget);

      await tester.tap(find.text('Ongoing Trip'));
      await tester.pumpAndSettle();

      expect(find.text('Add:g1/e1'), findsOneWidget);
      expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);
    });
  });
}
