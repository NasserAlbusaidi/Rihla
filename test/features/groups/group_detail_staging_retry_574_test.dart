import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #574 — a freshly-created group transiently denies its members/events
/// subcollection listens (~1s, server consistency lag after create). The
/// group-detail screen must RETRY the terminated listen a bounded number of
/// times — showing a skeleton meanwhile — instead of flashing a hard
/// "Couldn't load members" / "Couldn't load events" error. A genuine,
/// persistent denial still surfaces after the bound; non-permission errors are
/// never retried.
void main() {
  const groupId = 'group-1';

  final group = Group(
    id: groupId,
    name: 'Trip',
    inviteCode: 'AAAAAA',
    createdBy: 'uid-creator',
    memberIds: const ['uid-creator'],
    createdAt: DateTime(2025, 1, 1),
  );

  final denied = FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
    message: 'Missing or insufficient permissions.',
  );

  Future<void> pump(WidgetTester tester, List<Override> extra) async {
    SharedPreferences.setMockInitialValues({'device_name': 'Alice'});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/group/$groupId',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid',
          builder: (_, state) =>
              GroupDetailScreen(groupId: state.pathParameters['gid']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(groupId).overrideWith((ref) => Stream.value(group)),
          ...extra,
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump(); // group doc emits → _Content builds
    await tester.pump(); // subcollection streams settle
  }

  testWidgets(
    'transient permission-denied shows a skeleton during the window, then '
    'surfaces the error once the bounded retry budget is spent',
    (tester) async {
      await pump(tester, [
        groupBalancesProvider(groupId).overrideWith(
          (ref) => AsyncValue<GroupBalances>.error(denied, StackTrace.empty),
        ),
        groupEventsProvider(groupId)
            .overrideWith((ref) => Stream<List<Event>>.error(denied)),
        groupMembersProvider(groupId)
            .overrideWith((ref) => Stream<List<GroupMember>>.error(denied)),
      ]);

      // During the staging-retry window: skeleton, NOT the hard error. (Before
      // the fix, "Couldn't load members"/"events" rendered immediately.)
      expect(find.text("Couldn't load members"), findsNothing);
      expect(find.text("Couldn't load events"), findsNothing);
      expect(find.byType(SkeletonLoader), findsWidgets);

      // Drain the bounded retries (3 × 800ms) to the terminal state.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 800));
      }
      await tester.pumpAndSettle();

      // Bound preserved: a persistent denial still surfaces the real error.
      expect(find.text("Couldn't load members"), findsOneWidget);
      expect(find.byType(SkeletonLoader), findsNothing);
    },
  );

  testWidgets(
    'recovers when the retried listen succeeds (skeleton → members), no error',
    (tester) async {
      var balAttempts = 0;
      var evAttempts = 0;
      var memAttempts = 0;
      await pump(tester, [
        groupBalancesProvider(groupId).overrideWith((ref) {
          balAttempts++;
          if (balAttempts == 1) {
            return AsyncValue<GroupBalances>.error(denied, StackTrace.empty);
          }
          return const AsyncValue<GroupBalances>.data((
            balances: <String, List<UserBalance>>{},
            totalSpent: <String, Decimal>{},
            eventCount: 0,
            perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
            memberNames: {'uid-creator': 'Alice', 'uid-b': 'Bob'},
            memberRawNames: {'uid-creator': 'Alice', 'uid-b': 'Bob'},
          ));
        }),
        groupEventsProvider(groupId).overrideWith((ref) {
          evAttempts++;
          if (evAttempts == 1) return Stream<List<Event>>.error(denied);
          return Stream.value(const <Event>[]);
        }),
        groupMembersProvider(groupId).overrideWith((ref) {
          memAttempts++;
          if (memAttempts == 1) return Stream<List<GroupMember>>.error(denied);
          return Stream.value(const <GroupMember>[]);
        }),
      ]);

      // First window: denied → no members yet, no hard error.
      expect(find.text('Alice'), findsNothing);
      expect(find.text("Couldn't load members"), findsNothing);

      // Fire the retry → listens re-subscribe and succeed.
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Recovered: skeleton gone, no hard error.
      expect(find.text("Couldn't load members"), findsNothing);
      expect(find.byType(SkeletonLoader), findsNothing);

      // The members section now lists the real members (scroll it into view —
      // the members card sits below the events empty-state, off the viewport).
      await tester.scrollUntilVisible(
        find.text('Alice'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Alice'), findsOneWidget);
    },
  );

  testWidgets(
    'members stays denied while events/balances recover → error after the '
    'bound, NOT an endless "Loading members…" (independent listen recovery)',
    (tester) async {
      // The members and events subcollection listens recover at independent
      // times. Here events + balances resolve (empty) but members stays denied.
      // groupBalancesProvider swallows the members error into empty data, so the
      // screen must observe members directly: retry it within budget, then show
      // the real error — never hang on "Loading members…".
      await pump(tester, [
        groupBalancesProvider(groupId).overrideWith(
          (ref) => const AsyncValue<GroupBalances>.data((
            balances: <String, List<UserBalance>>{},
            totalSpent: <String, Decimal>{},
            eventCount: 0,
            perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
            memberNames: <String, String>{},
            memberRawNames: <String, String>{},
          )),
        ),
        groupEventsProvider(groupId)
            .overrideWith((ref) => Stream.value(const <Event>[])),
        groupMembersProvider(groupId)
            .overrideWith((ref) => Stream<List<GroupMember>>.error(denied)),
      ]);

      // During the window: retrying members → skeleton, not the error.
      expect(find.text("Couldn't load members"), findsNothing);
      expect(find.byType(SkeletonLoader), findsWidgets);

      // Drain the bounded retries.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 800));
      }
      await tester.pumpAndSettle();

      // Members error surfaces (scroll the members card past the events empty
      // state); it must NOT hang on "Loading members…".
      await tester.scrollUntilVisible(
        find.text("Couldn't load members"),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text("Couldn't load members"), findsOneWidget);
      expect(find.text('Loading members…'), findsNothing);
    },
  );

  testWidgets(
    'a non-permission error surfaces immediately (NOT retried)',
    (tester) async {
      await pump(tester, [
        groupBalancesProvider(groupId).overrideWith(
          (ref) => AsyncValue<GroupBalances>.error(
            Exception('network blip'),
            StackTrace.empty,
          ),
        ),
        groupEventsProvider(groupId)
            .overrideWith((ref) => Stream<List<Event>>.error(Exception('blip'))),
      ]);
      await tester.pumpAndSettle();

      // Generic (non-permission) errors keep the existing immediate-error
      // behavior — the staging retry must not swallow them behind a skeleton.
      expect(find.text("Couldn't load members"), findsOneWidget);
      expect(find.byType(SkeletonLoader), findsNothing);
    },
  );
}
