import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_activity_screen.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

// ---------------------------------------------------------------------------
// Test fixture data
// ---------------------------------------------------------------------------

/// Returns a DateTime at noon, `dayOffset` days from today's local date.
///
/// Fixtures used to subtract small hour offsets from `DateTime.now()` (e.g.
/// `now - 1h` for "today"), which rolled to the previous day whenever the
/// test happened to run in the first hour or two after midnight. Anchoring
/// at midday gives ~12 hours of slack on each side of the day boundary, so
/// the bucketing the production code does (calendar-day comparison in
/// `_groupByDay`) always lands on the intended day.
DateTime _atMidday(int dayOffset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + dayOffset, 12);
}

GroupActivityLog _todayActivity() => GroupActivityLog(
  id: 'act-1',
  type: 'group_settlement',
  actorId: 'uid-alice',
  actorName: 'Alice',
  description: 'paid Bob',
  timestamp: _atMidday(0),
);

GroupActivityLog _yesterdayActivity() => GroupActivityLog(
  id: 'act-2',
  type: 'event_created',
  actorId: 'uid-bob',
  actorName: 'Bob',
  description: 'created Camping Trip',
  metadata: const {'eventName': 'Camping Trip'},
  timestamp: _atMidday(-1),
);

GroupActivityLog _memberActivity() => GroupActivityLog(
  id: 'act-3',
  type: 'member_joined',
  actorId: 'uid-carol',
  actorName: 'Carol',
  description: 'joined the group',
  timestamp: _atMidday(-2),
);

// Minimal test Group used to satisfy groupDetailProvider override
final _testGroup = Group(
  id: 'grp-test',
  name: 'Test Crew',
  inviteCode: 'TC123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  createdAt: DateTime(2026, 1, 1),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Seeds a list of [GroupActivityLog] entries into [FakeFirebaseFirestore].
Future<void> _seedActivities(
  FakeFirebaseFirestore db,
  String groupId,
  List<GroupActivityLog> activities,
) async {
  for (final a in activities) {
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

/// A [GroupActivityService] whose page fetch always throws — models a
/// network failure on load so the screen must surface a real error state
/// rather than the misleading "No activity yet" empty state (#488).
class _ThrowingActivityService extends GroupActivityService {
  _ThrowingActivityService() : super.withFirestore(FakeFirebaseFirestore());

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) async {
    throw Exception('simulated network failure');
  }
}

/// Builds GroupActivityScreen with injected FakeFirebaseFirestore and
/// a [groupDetailProvider] override that returns [_testGroup].
Widget _buildActivityScreen({
  required String groupId,
  required FakeFirebaseFirestore fakeDb,
  SharedPreferences? prefs,
}) {
  final activityService = GroupActivityService.withFirestore(fakeDb);

  return ProviderScope(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      groupActivityServiceProvider.overrideWith((ref) => activityService),
      groupDetailProvider(
        groupId,
      ).overrideWith((ref) => Stream.value(_testGroup)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupActivityScreen(groupId: groupId),
    ),
  );
}

Widget _buildActivityRoute({
  required String groupId,
  required FakeFirebaseFirestore fakeDb,
  SharedPreferences? prefs,
}) {
  final activityService = GroupActivityService.withFirestore(fakeDb);
  final router = GoRouter(
    initialLocation: '/group/$groupId/activity',
    routes: [
      GoRoute(
        path: '/group/:gid',
        builder: (context, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['gid']}')),
        routes: [
          GoRoute(
            path: 'activity',
            builder: (context, state) =>
                GroupActivityScreen(groupId: state.pathParameters['gid']!),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      groupActivityServiceProvider.overrideWith((ref) => activityService),
      groupDetailProvider(
        groupId,
      ).overrideWith((ref) => Stream.value(_testGroup)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    return (widget.data?.contains(text) ?? false) ||
        (widget.textSpan?.toPlainText().contains(text) ?? false);
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GroupActivityScreen', () {
    testWidgets('renders group activity title in the current top bar', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Test Crew'), findsOneWidget);
    });

    testWidgets('renders empty state when no activity entries exist', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-empty',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // EmptyStateView is present
      expect(find.byKey(SharedKeys.emptyStateView), findsOneWidget);
    });

    testWidgets('renders empty state message', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-empty2',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Group events, payments, and member changes will appear here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'first-load failure shows an error+retry state, not "No activity yet" '
      '(#488)',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupActivityServiceProvider.overrideWith(
                (ref) => _ThrowingActivityService(),
              ),
              groupDetailProvider(
                'grp-load-error',
              ).overrideWith((ref) => Stream.value(_testGroup)),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const GroupActivityScreen(groupId: 'grp-load-error'),
            ),
          ),
        );
        await tester.pump(); // initState _loadPage runs and throws
        await tester.pumpAndSettle();

        // A real, distinct error state with a retry affordance.
        expect(find.text('Could not load activity'), findsOneWidget);
        expect(find.text('Reload'), findsOneWidget);
        // The misleading "empty" copy must NOT be shown on a failed load.
        expect(
          find.text(
            'Group events, payments, and member changes will appear here.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets('renders back button in the current top bar', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.activityBackButton), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('direct route back button returns to group detail', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityRoute(groupId: 'grp-test', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.activityBackButton));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:grp-test'), findsOneWidget);
    });

    testWidgets('renders SafeArea inside Scaffold body', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-safearea',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // ModuleHeader wraps content in SafeArea — verify it exists
      expect(find.byType(SafeArea), findsWidgets);
    });

    // --- Phase 30 Plan 03 — unskipped stubs ---

    testWidgets('renders date section headers (TODAY, YESTERDAY)', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();

      await _seedActivities(fakeDb, 'grp-dates', [
        _todayActivity(),
        _yesterdayActivity(),
      ]);

      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-dates',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
    });

    testWidgets('renders 4 filter chips', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.activityFilterAll), findsOneWidget);
      expect(find.byKey(GroupKeys.activityFilterSettlements), findsOneWidget);
      expect(find.byKey(GroupKeys.activityFilterEvents), findsOneWidget);
      expect(find.byKey(GroupKeys.activityFilterMembers), findsOneWidget);
    });

    testWidgets('Settlements filter shows only settlement activities', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();

      await _seedActivities(fakeDb, 'grp-filter', [
        _todayActivity(), // group_settlement — 'paid Bob'
        GroupActivityLog(
          id: 'act-event',
          type: 'event_created',
          actorId: 'uid-bob',
          actorName: 'Bob',
          description: 'Bob created a camping event',
          timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        ),
      ]);

      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-filter',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Tap Settlements filter chip
      await tester.tap(find.byKey(GroupKeys.activityFilterSettlements));
      await tester.pumpAndSettle();

      // Only settlement activity visible
      expect(_richTextContaining('recorded a settlement'), findsOneWidget);
      expect(_richTextContaining('created an event'), findsNothing);
    });

    testWidgets('renders activity tile with actor name and description', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();

      await _seedActivities(fakeDb, 'grp-tile', [
        GroupActivityLog(
          id: 'act-1',
          type: 'event_created',
          actorId: 'uid1',
          actorName: 'Alice',
          description: 'Alice created Weekend Trip',
          metadata: const {'eventName': 'Weekend Trip'},
          timestamp: DateTime.now(),
        ),
      ]);

      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-tile', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_richTextContaining('Alice'), findsOneWidget);
      expect(_richTextContaining('Weekend Trip'), findsOneWidget);
    });

    testWidgets(
      'settlement activity uses the money/wallet glyph, not a bare chevron '
      '(#160)',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final prefs = await SharedPreferences.getInstance();

        await _seedActivities(fakeDb, 'grp-icon', [
          _todayActivity(), // group_settlement
        ]);

        await tester.pumpWidget(
          _buildActivityScreen(groupId: 'grp-icon', fakeDb: fakeDb, prefs: prefs),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byIcon(Iconsax.wallet_3), findsOneWidget);
        expect(find.byIcon(Iconsax.arrow_right_3), findsNothing);
      },
    );

    testWidgets('no Load more button present (infinite scroll replaces it)', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();

      // Seed 3 activities — below page limit, _hasMore will be false
      for (var i = 0; i < 3; i++) {
        await fakeDb
            .collection('groups')
            .doc('grp-scroll')
            .collection('activity')
            .doc('act-$i')
            .set({
              'id': 'act-$i',
              'type': 'event_created',
              'actorId': 'uid1',
              'actorName': 'Alice',
              'description': 'Event $i',
              'metadata': <String, dynamic>{},
              'timestamp': DateTime.now()
                  .subtract(Duration(minutes: i))
                  .toUtc()
                  .toIso8601String(),
            });
      }

      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-scroll',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Infinite scroll replaces 'Load more' — must not exist
      expect(find.text('Load more'), findsNothing);
    });

    // --- Additional new tests ---

    testWidgets('All filter shows all activities by default', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();

      await _seedActivities(fakeDb, 'grp-all', [
        _todayActivity(), // group_settlement
        GroupActivityLog(
          id: 'act-event',
          type: 'event_created',
          actorId: 'uid-bob',
          actorName: 'Bob',
          description: 'created Weekend Hike',
          metadata: const {'eventName': 'Weekend Hike'},
          timestamp: _atMidday(0),
        ),
        _memberActivity(), // member_joined
      ]);

      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-all', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // All activities visible with default 'All' filter
      expect(_richTextContaining('recorded a settlement'), findsOneWidget);
      expect(_richTextContaining('created Weekend Hike'), findsOneWidget);
      expect(_richTextContaining('joined the group'), findsOneWidget);
    });

    testWidgets('empty filter state shows no-results message', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();

      // Seed only settlement activities
      await _seedActivities(fakeDb, 'grp-no-member', [
        _todayActivity(), // group_settlement
      ]);

      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-no-member',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      // Use pump with a generous duration to flush flutter_animate timers
      await tester.pump(const Duration(seconds: 1));

      // Tap Members filter — no member activities exist
      await tester.tap(find.byKey(GroupKeys.activityFilterMembers));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Filter-empty state shown
      expect(find.text('Nothing matches this filter'), findsOneWidget);
      expect(
        find.text('Try a different filter, or switch back to All.'),
        findsOneWidget,
      );
    });
  });

  group('per-log settlement currency (#382 PR-4)', () {
    testWidgets(
      'prefers metadata.currency for the amount and labels a foreign one',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final prefs = await SharedPreferences.getInstance();
        await _seedActivities(fakeDb, 'grp-1', [
          GroupActivityLog(
            id: 'act-usd',
            type: 'group_settlement',
            actorId: 'uid-alice',
            actorName: 'Alice',
            description: 'paid Bob',
            metadata: const {'amount': '12.50', 'currency': 'USD'},
            timestamp: _atMidday(0),
          ),
          GroupActivityLog(
            id: 'act-legacy',
            type: 'group_settlement',
            actorId: 'uid-bob',
            actorName: 'Bob',
            description: 'paid Alice',
            metadata: const {'amount': '7.750'},
            timestamp: _atMidday(-1),
          ),
        ]);

        await tester.pumpWidget(
          _buildActivityScreen(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
        );
        await tester.pumpAndSettle();

        final amounts = tester
            .widgetList<RAmount>(find.byType(RAmount))
            .toList();
        // Two settlement rows, each a 14px main + 11px sage amount.
        expect(amounts, hasLength(4));

        final usd = amounts.where((a) => a.currency == 'USD').toList();
        final omr = amounts.where((a) => a.currency == 'OMR').toList();
        expect(usd, hasLength(2)); // stamped row renders at its own currency
        expect(omr, hasLength(2)); // legacy row falls back to group currency

        // Foreign currency gets labeled on the main amount; the group
        // currency stays bare (pre-PR-4 appearance preserved).
        expect(usd.where((a) => a.showCurrency).length, 1);
        expect(omr.where((a) => a.showCurrency).length, 0);
      },
    );
  });
}
