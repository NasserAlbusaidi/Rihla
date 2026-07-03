import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/keys/activity_keys.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/home/screens/cross_group_activity_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fixtures + helpers (mirror cross_group_activity_screen_test.dart)
// ---------------------------------------------------------------------------

Group _group(String id, String name, {String currency = 'OMR'}) => Group(
  id: id,
  name: name,
  inviteCode: 'INV${id.toUpperCase()}',
  createdBy: 'uid0',
  memberIds: const ['uid0'],
  currency: currency,
  createdAt: DateTime(2026, 1, 1),
);

GroupActivityLog _activity(
  String id,
  String actorName,
  String description, {
  String type = 'event_created',
  Map<String, dynamic> metadata = const {},
  DateTime? at,
}) => GroupActivityLog(
  id: id,
  type: type,
  actorId: 'uid0',
  actorName: actorName,
  description: description,
  metadata: metadata,
  timestamp: at ?? DateTime(2026, 3, 28),
);

Future<void> _seed(
  FakeFirebaseFirestore db,
  String groupId,
  List<GroupActivityLog> logs,
) async {
  for (final a in logs) {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('activity')
        .doc(a.id)
        .set({
          'id': a.id,
          'type': a.type,
          'actorId': a.actorId,
          'actorName': a.actorName,
          'description': a.description,
          'metadata': a.metadata,
          'timestamp': a.timestamp.toUtc().toIso8601String(),
        });
  }
}

Widget _app({
  required List<Group> groups,
  required GroupActivityService service,
  required SharedPreferences prefs,
}) {
  final router = GoRouter(
    initialLocation: '/activity',
    routes: [
      GoRoute(
        path: '/activity',
        builder: (ctx, state) => const CrossGroupActivityScreen(),
      ),
      GoRoute(
        path: '/group/:id',
        builder: (ctx, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
      groupActivityServiceProvider.overrideWith((ref) => service),
      currentUserIdProvider.overrideWithValue('uid0'),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Finder _rich(String text) =>
    find.textContaining(text, findRichText: true);

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(ActivityKeys.searchToggle));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(ActivityKeys.searchField), query);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  group('CrossGroupActivityScreen search (#808 PR3)', () {
    testWidgets('the search toggle is hidden until the feed has entries', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ActivityKeys.searchToggle), findsNothing);
    });

    testWidgets('typing narrows the visible rows', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('a1', 'Alice', 'created an event', at: DateTime(2026, 3, 28)),
        _activity(
          's1',
          'Bob',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '9'},
          at: DateTime(2026, 3, 27),
        ),
        _activity(
          'e1',
          'Carol',
          'added an expense',
          type: 'expense_added',
          metadata: const {'eventName': 'Beach Trip'},
          at: DateTime(2026, 3, 26),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      expect(_rich('Alice'), findsOneWidget);
      expect(_rich('Bob'), findsOneWidget);

      await _openSearch(tester);
      await _type(tester, 'carol');

      expect(_rich('Carol'), findsOneWidget);
      expect(_rich('Alice'), findsNothing);
      expect(_rich('Bob'), findsNothing);
    });

    testWidgets('the active chip and the query compose', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity(
          'e1',
          'Alice',
          'added an expense',
          type: 'expense_added',
          metadata: const {'eventName': 'Beach Trip'},
          at: DateTime(2026, 3, 28),
        ),
        _activity(
          'e2',
          'Bob',
          'added an expense',
          type: 'expense_added',
          metadata: const {'eventName': 'Mountain Hike'},
          at: DateTime(2026, 3, 27),
        ),
        _activity(
          's1',
          'Zed',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '9'},
          at: DateTime(2026, 3, 26),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      // Expenses chip: settlement drops out, both expenses stay.
      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();
      expect(_rich('Beach Trip'), findsOneWidget);
      expect(_rich('Mountain Hike'), findsOneWidget);
      expect(_rich('Zed'), findsNothing);

      // Query 'beach' AND the Expenses chip → only the Beach expense.
      await _openSearch(tester);
      await _type(tester, 'beach');
      expect(_rich('Beach Trip'), findsOneWidget);
      expect(_rich('Mountain Hike'), findsNothing);
      expect(_rich('Zed'), findsNothing);
    });

    testWidgets('closing the search restores the full feed', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('a1', 'Alice', 'created an event', at: DateTime(2026, 3, 28)),
        _activity(
          's1',
          'Bob',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '9'},
          at: DateTime(2026, 3, 27),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await _openSearch(tester);
      await _type(tester, 'alice');
      expect(_rich('Alice'), findsOneWidget);
      expect(_rich('Bob'), findsNothing);

      // Toggle the search off → field gone, feed restored.
      await tester.tap(find.byKey(ActivityKeys.searchToggle));
      await tester.pumpAndSettle();
      expect(find.byKey(ActivityKeys.searchField), findsNothing);
      expect(_rich('Alice'), findsOneWidget);
      expect(_rich('Bob'), findsOneWidget);
    });

    testWidgets('zero matches with more pages offers the load-older action, '
        'and it fetches an older matching row (virtualized: findable after '
        'the fetch)', (tester) async {
      final db = FakeFirebaseFirestore();
      final now = DateTime(2026, 3, 28, 12);
      await _seed(db, 'g1', [
        for (var i = 0; i < 60; i++)
          _activity(
            'a$i',
            i == 55 ? 'Zulu' : 'Actor-$i',
            'created an event',
            at: now.subtract(Duration(minutes: i)),
          ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      // 'Zulu' sits on page 2 (entries 50..59) — not loaded yet.
      await _openSearch(tester);
      await _type(tester, 'zulu');
      expect(_rich('Zulu'), findsNothing);
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Search older activity'), findsOneWidget);

      await tester.tap(find.text('Search older activity'));
      await tester.pumpAndSettle();

      expect(_rich('Zulu'), findsOneWidget);
    });

    testWidgets('zero matches with no more pages shows a plain no-match state '
        '(no load-older action)', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('a1', 'Alice', 'created an event', at: DateTime(2026, 3, 28)),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await _openSearch(tester);
      await _type(tester, 'nothingmatchesthis');
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Search older activity'), findsNothing);
    });

    testWidgets('with matches AND more pages, the footer offers a load-older '
        'button', (tester) async {
      final db = FakeFirebaseFirestore();
      final now = DateTime(2026, 3, 28, 12);
      await _seed(db, 'g1', [
        for (var i = 0; i < 60; i++)
          _activity(
            'a$i',
            i < 2 ? 'Match-Me' : 'Filler-$i',
            'created an event',
            at: now.subtract(Duration(minutes: i)),
          ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await _openSearch(tester);
      await _type(tester, 'match-me');

      // Two short match rows → the footer's load-older button is on-screen.
      expect(_rich('Match-Me'), findsWidgets);
      expect(find.byKey(ActivityKeys.searchOlderButton), findsOneWidget);
    });

    testWidgets('a forged legacy-NaN amount entry never ErrorWidgets the tab '
        'while searching (matcher runs activityAmount over ALL loaded entries '
        'in the parent build)', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('a1', 'Alice', 'created an event', at: DateTime(2026, 3, 28)),
        _activity(
          's-nan',
          'Mallory',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': double.nan},
          at: DateTime(2026, 3, 27),
        ),
        _activity(
          's1',
          'Bob',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '9'},
          at: DateTime(2026, 3, 26),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await _openSearch(tester);
      await _type(tester, 'bob');

      expect(find.byType(ErrorWidget), findsNothing);
      expect(_rich('Bob'), findsOneWidget);
      expect(_rich('Mallory'), findsNothing);
      expect(_rich('Alice'), findsNothing);
    });

    testWidgets('a forged non-String eventName entry never ErrorWidgets the '
        'tab while searching (same class: unvalidated metadata value-domain '
        'reaching the parent-build matcher)', (tester) async {
      final db = FakeFirebaseFirestore();
      await _seed(db, 'g1', [
        _activity('a1', 'Alice', 'created an event', at: DateTime(2026, 3, 28)),
        _activity(
          'e-forged',
          'Mallory',
          'added an expense',
          type: 'expense_added',
          metadata: const {'eventName': 42},
          at: DateTime(2026, 3, 27),
        ),
        _activity(
          's1',
          'Bob',
          'recorded a settlement',
          type: 'group_settlement',
          metadata: const {'amount': '9'},
          at: DateTime(2026, 3, 26),
        ),
      ]);
      await tester.pumpWidget(
        _app(
          groups: [_group('g1', 'Trip A')],
          service: GroupActivityService.withFirestore(db),
          prefs: await prefs(),
        ),
      );
      await tester.pumpAndSettle();

      await _openSearch(tester);
      await _type(tester, 'bob');

      expect(find.byType(ErrorWidget), findsNothing);
      expect(_rich('Bob'), findsOneWidget);
      expect(_rich('Mallory'), findsNothing);
      expect(_rich('Alice'), findsNothing);
    });
  });
}
