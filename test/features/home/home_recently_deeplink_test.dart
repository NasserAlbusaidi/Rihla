import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/activity_row.dart';
import 'package:safar/shared/widgets/r_avatar.dart';

// ---------------------------------------------------------------------------
// #852: home RECENTLY rows deep-link per activity type, mirroring the History
// tab's #840 target table (shared util `activityRowTarget`). Harness modeled
// on home_screen_dashboard_test.dart; stub routes mirror the #840 set in
// cross_group_activity_screen_test.dart.
// ---------------------------------------------------------------------------

CrossGroupBalance _settled() => (
  byCurrency: const <CurrencyBalance>[],
  groupCount: 1,
  isLoading: false,
);

Event _makeEvent(String id, String name) => Event(
  id: id,
  name: name,
  type: EventType.camping,
  groupId: 'g1',
  createdBy: 'uid0',
  participantIds: ['uid0'],
  participantNames: {'uid0': 'Alice'},
  modules: EventModules.forType(EventType.camping),
  createdAt: DateTime(2026, 3, 1),
);

Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'uid0',
  memberIds: const ['uid0', 'uid1'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

GroupActivityLog _makeActivity(
  String id,
  String actorName,
  String description, {
  String type = 'event_created',
  Map<String, dynamic> metadata = const {},
}) => GroupActivityLog(
  id: id,
  type: type,
  actorId: 'uid0',
  actorName: actorName,
  description: description,
  metadata: metadata,
  timestamp: DateTime(2026, 3, 28),
);

CrossGroupActivityEntry _toEntry(GroupActivityLog log) =>
    (log: log, groupName: 'Desert Crew', groupId: 'g1', currency: 'OMR');

GroupBalances _testGroupBalances() => (
  balances: {
    'OMR': [
      UserBalance(
        participantId: 'test-user-id',
        displayName: 'Test User',
        totalPaid: Decimal.parse('10.000'),
        totalOwed: Decimal.parse('20.000'),
        netBalance: Decimal.parse('-5.500'),
      ),
    ],
  },
  totalSpent: {'OMR': Decimal.parse('25.000')},
  eventCount: 1,
  perEventBreakdown: {},
  memberNames: {'test-user-id': 'Test User'},
  memberRawNames: <String, String>{},
);

Widget _buildTestApp({
  required GroupActivityLog activity,
  required SharedPreferences prefs,
}) {
  // Stub target routes mirror the #840 harness in
  // cross_group_activity_screen_test.dart:153-200 — pushes are literal path
  // strings, so each stub just echoes its identity.
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
      GoRoute(
        path: '/group/:id',
        builder: (ctx, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}')),
        routes: [
          GoRoute(
            path: 'settle-up',
            builder: (ctx, state) => Scaffold(
              body: Text(
                'GroupSettleUp:${state.pathParameters['id']}'
                '?${state.uri.query}',
              ),
            ),
          ),
          GoRoute(
            path: 'event/:eid',
            builder: (ctx, state) => Scaffold(
              body: Text(
                'EventHub:${state.pathParameters['id']}/'
                '${state.pathParameters['eid']}',
              ),
            ),
            routes: [
              GoRoute(
                path: 'ledger',
                builder: (ctx, state) => Scaffold(
                  body: Text(
                    'EventLedger:${state.pathParameters['id']}/'
                    '${state.pathParameters['eid']}',
                  ),
                ),
              ),
              GoRoute(
                path: 'activity',
                builder: (ctx, state) => Scaffold(
                  body: Text(
                    'EventActivity:${state.pathParameters['id']}/'
                    '${state.pathParameters['eid']}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // #285/#428: durable user so the account-backup nudge stays out of the
      // scroll path.
      linkedEmailProvider.overrideWithValue('secured@example.com'),
      isDurableUserProvider.overrideWithValue(true),
      userGroupsProvider.overrideWith(
        (ref) => Stream.value([_makeGroup('g1', 'Desert Crew')]),
      ),
      crossGroupHomeBalanceProvider.overrideWith(
        (ref) => AsyncValue.data((balance: _settled(), partial: false)),
      ),
      crossGroupActivityProvider.overrideWith(
        (ref) => AsyncValue.data([_toEntry(activity)]),
      ),
      groupBalancesProvider.overrideWith(
        (ref, groupId) => AsyncValue.data(_testGroupBalances()),
      ),
      groupEventsProvider.overrideWith(
        (ref, groupId) => Stream.value([_makeEvent('e1', 'Camping Trip')]),
      ),
      currentUserIdProvider.overrideWithValue('test-user-id'),
      groupBalancesOnceProvider.overrideWith(
        (ref, gid) => ref.watch(groupBalancesProvider(gid)).maybeWhen(
              data: (d) => (balances: d, failedEventIds: const <String>{}),
              orElse: () => Completer<GroupBalancesOnce>().future,
            ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// Scrolls the home CustomScrollView until the single RECENTLY row is
/// visible, then taps it.
Future<void> _scrollToAndTapRow(WidgetTester tester) async {
  final scrollable = find.byType(CustomScrollView);
  final row = find.byType(ActivityRow);
  for (var i = 0; i < 12 && row.evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -250));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  await tester.tap(row, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpWith(WidgetTester tester, GroupActivityLog activity) async {
    await tester.pumpWidget(_buildTestApp(activity: activity, prefs: prefs));
    await tester.pumpAndSettle();
  }

  group('RECENTLY row deep-links (#852, mirrors #840)', () {
    testWidgets('expense_added routes to the event ledger', (tester) async {
      await pumpWith(
        tester,
        _makeActivity(
          'e1',
          'Alice',
          'added an expense',
          type: 'expense_added',
          metadata: const {
            'eventId': 'ev1',
            'eventName': 'Beach Trip',
            'amountFils': 500,
            'currency': 'OMR',
          },
        ),
      );
      await _scrollToAndTapRow(tester);

      expect(find.text('EventLedger:g1/ev1'), findsOneWidget);
      expect(find.text('GroupDetail:g1'), findsNothing);
    });

    testWidgets('expense_deleted routes to the event activity feed', (
      tester,
    ) async {
      await pumpWith(
        tester,
        _makeActivity(
          'e1',
          'Alice',
          'deleted an expense',
          type: 'expense_deleted',
          metadata: const {'eventId': 'ev1', 'eventName': 'Beach Trip'},
        ),
      );
      await _scrollToAndTapRow(tester);

      expect(find.text('EventActivity:g1/ev1'), findsOneWidget);
    });

    testWidgets('event_created routes to the event hub', (tester) async {
      await pumpWith(
        tester,
        _makeActivity(
          'a1',
          'Alice',
          'created an event',
          type: 'event_created',
          metadata: const {'eventId': 'ev1', 'eventName': 'Beach Trip'},
        ),
      );
      await _scrollToAndTapRow(tester);

      expect(find.text('EventHub:g1/ev1'), findsOneWidget);
      expect(find.text('GroupDetail:g1'), findsNothing);
    });

    testWidgets('group_settlement routes to settle-up with no query params', (
      tester,
    ) async {
      await pumpWith(
        tester,
        _makeActivity(
          's1',
          'Alice',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {
            'amount': '12.5',
            'fromUserId': 'uid0',
            'toUserId': 'uid1',
            'fromName': 'Alice',
            'toName': 'Bob',
            'recipientId': 'uid1',
          },
        ),
      );
      await _scrollToAndTapRow(tester);

      expect(find.text('GroupSettleUp:g1?'), findsOneWidget);
    });

    testWidgets('member_joined routes to group detail (unchanged)', (
      tester,
    ) async {
      await pumpWith(
        tester,
        _makeActivity('m1', 'Bob', 'joined', type: 'member_joined'),
      );
      await _scrollToAndTapRow(tester);

      expect(find.text('GroupDetail:g1'), findsOneWidget);
    });

    group('forged/absent eventId degrades to group detail, never an '
        'ErrorWidget (mirrors #840)', () {
      final forgedValues = <String, Object>{
        'int': 42,
        'empty string': '',
      };

      for (final forged in forgedValues.entries) {
        testWidgets('expense_added with eventId as ${forged.key}', (
          tester,
        ) async {
          await pumpWith(
            tester,
            _makeActivity(
              'e1',
              'Alice',
              'added an expense',
              type: 'expense_added',
              metadata: {
                'eventId': forged.value,
                'eventName': 'Beach Trip',
                'amountFils': 500,
                'currency': 'OMR',
              },
            ),
          );
          await _scrollToAndTapRow(tester);

          expect(find.byType(ErrorWidget), findsNothing);
          expect(find.text('GroupDetail:g1'), findsOneWidget);
        });
      }

      testWidgets('expense_added with an absent eventId', (tester) async {
        await pumpWith(
          tester,
          _makeActivity(
            'e1',
            'Alice',
            'added an expense',
            type: 'expense_added',
            metadata: const {
              'eventName': 'Beach Trip',
              'amountFils': 500,
              'currency': 'OMR',
            },
          ),
        );
        await _scrollToAndTapRow(tester);

        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text('GroupDetail:g1'), findsOneWidget);
      });
    });
  });

  group('RECENTLY row visuals (PR4 #490, D-a)', () {
    testWidgets(
      'leads with the category-icon glyph, drops the avatar; group chip '
      'and the #852 deep-link both still work',
      (tester) async {
        await pumpWith(
          tester,
          _makeActivity(
            's1',
            'Alice',
            'recorded a settlement',
            type: 'group_settlement',
            metadata: const {
              'amount': '12.5',
              'fromUserId': 'uid0',
              'toUserId': 'uid1',
              'fromName': 'Alice',
              'toName': 'Bob',
              'recipientId': 'uid1',
            },
          ),
        );

        final scrollable = find.byType(CustomScrollView);
        for (
          var i = 0;
          i < 12 && find.byType(ActivityRow).evaluate().isEmpty;
          i++
        ) {
          await tester.drag(scrollable, const Offset(0, -250));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(HomeKeys.activitySection),
            matching: find.byType(RAvatar),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(HomeKeys.activitySection),
            matching: find.byIcon(Iconsax.wallet_3),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(HomeKeys.activitySection),
            matching: find.text('Desert Crew'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byType(ActivityRow), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('GroupSettleUp:g1?'), findsOneWidget);
      },
    );
  });
}
