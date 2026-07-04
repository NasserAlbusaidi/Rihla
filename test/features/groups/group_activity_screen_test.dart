import 'dart:async';

import 'package:decimal/decimal.dart';
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
import 'package:safar/core/utils/localized_dates.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_activity_screen.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/animations/tap_bounce.dart';
import 'package:safar/shared/widgets/caption_title_bar.dart';
import 'package:safar/shared/widgets/paper_backdrop.dart';
import 'package:safar/shared/widgets/r_amount.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

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
/// `groupByDay`) always lands on the intended day.
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

/// A [GroupActivityService] that serves the first page normally but hangs
/// forever on the second — models an in-flight `_hasMore` pagination fetch so
/// the loading footer can be observed in a settled widget tree without the
/// #634-style race of an immediate zero-doc second page flipping `_hasMore`
/// back to false before the test can assert on it.
class _SlowSecondPageActivityService extends GroupActivityService {
  _SlowSecondPageActivityService(super.db)
    : _delegate = GroupActivityService.withFirestore(db),
      super.withFirestore();

  final GroupActivityService _delegate;
  int _calls = 0;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> fetchActivityPageRaw(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) {
    _calls++;
    if (_calls == 1) {
      return _delegate.fetchActivityPageRaw(
        groupId,
        startAfter: startAfter,
        limit: limit,
      );
    }
    return Completer<QuerySnapshot<Map<String, dynamic>>>().future;
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
          // #852: stub target routes for per-type row deep-links, mirroring
          // the #840 harness in cross_group_activity_screen_test.dart.
          GoRoute(
            path: 'settle-up',
            builder: (context, state) => Scaffold(
              body: Text('GroupSettleUp:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'event/:eid',
            builder: (context, state) => Scaffold(
              body: Text(
                'EventHub:${state.pathParameters['gid']}/'
                '${state.pathParameters['eid']}',
              ),
            ),
            routes: [
              GoRoute(
                path: 'ledger',
                builder: (context, state) => Scaffold(
                  body: Text(
                    'EventLedger:${state.pathParameters['gid']}/'
                    '${state.pathParameters['eid']}',
                  ),
                ),
              ),
              GoRoute(
                path: 'activity',
                builder: (context, state) => Scaffold(
                  body: Text(
                    'EventActivity:${state.pathParameters['gid']}/'
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

    testWidgets(
      'top bar is the journal CaptionTitleBar — group name as serif title, '
      'ACTIVITY caption',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          _buildActivityScreen(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byType(CaptionTitleBar), findsOneWidget);
        final bar = tester.widget<CaptionTitleBar>(
          find.byType(CaptionTitleBar),
        );
        expect(bar.title, 'Test Crew');
        expect(bar.caption, 'ACTIVITY');
        expect(find.byKey(GroupKeys.activityScreenTitle), findsOneWidget);
        expect(find.byKey(GroupKeys.activityBackButton), findsOneWidget);
      },
    );

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

      // CaptionTitleBar now wraps the back InkResponse in a localized
      // Tooltip (a11y fix) — restored after the initial adoption pass
      // dropped it.
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

      // The screen's Scaffold body wraps its content in SafeArea.
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets(
      'wraps body content in the shared PaperBackdrop (#490 D-c)',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          _buildActivityScreen(
            groupId: 'grp-backdrop',
            fakeDb: fakeDb,
            prefs: prefs,
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byType(PaperBackdrop), findsOneWidget);
      },
    );

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

    testWidgets(
      'filter chips are the shared ActivityFilterStrip — wrapped in '
      'TapBounce, not a bare GestureDetector',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          _buildActivityScreen(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          tester.widget(find.byKey(GroupKeys.activityFilterAll)),
          isA<TapBounce>(),
        );
      },
    );

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

    testWidgets(
      'pagination footer uses the shared skeleton loader, not a bare '
      'spinner (#488)',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final prefs = await SharedPreferences.getInstance();

        // Exactly the page size (50) so _hasMore flips true and the
        // ListView grows a trailing footer item.
        for (var i = 0; i < 50; i++) {
          await fakeDb
              .collection('groups')
              .doc('grp-footer')
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
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupActivityServiceProvider.overrideWith(
                (ref) => _SlowSecondPageActivityService(fakeDb),
              ),
              groupDetailProvider(
                'grp-footer',
              ).overrideWith((ref) => Stream.value(_testGroup)),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const GroupActivityScreen(groupId: 'grp-footer'),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        // The first (full) page settled with `_hasMore == true`. Scrolling
        // near the bottom triggers the second page fetch, which hangs
        // forever (per the fake service above) — the loading footer stays
        // observable instead of racing to a resolved/empty state.
        //
        // The filter strip's own horizontal ListView is Scrollable #0 in the
        // tree; the vertical activity list is #1 — target it explicitly by
        // index (NOT `.last`: once the footer skeleton itself mounts, its
        // internal never-scrollable SingleChildScrollView becomes the new
        // last match). Positive delta scrolls forward (down).
        await tester.scrollUntilVisible(
          find.byType(SkeletonLoader),
          300,
          scrollable: find.byType(Scrollable).at(1),
        );

        expect(find.byType(SkeletonLoader), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'first-load error state uses the warning glyph, not the activity '
      'glyph (P1)',
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
                'grp-error-icon',
              ).overrideWith((ref) => Stream.value(_testGroup)),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const GroupActivityScreen(groupId: 'grp-error-icon'),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.activityErrorView), findsOneWidget);
        expect(find.byIcon(Iconsax.warning_2), findsOneWidget);
        expect(find.byIcon(Iconsax.activity), findsNothing);
      },
    );

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
        // #818 Wave 3.1: the signed sage RAmount is gone — each settlement
        // row renders only its single 14px main amount.
        expect(amounts, hasLength(2));

        final usd = amounts.where((a) => a.currency == 'USD').toList();
        final omr = amounts.where((a) => a.currency == 'OMR').toList();
        expect(usd, hasLength(1)); // stamped row renders at its own currency
        expect(omr, hasLength(1)); // legacy row falls back to group currency

        // Foreign currency gets labeled on the main amount; the group
        // currency stays bare (pre-PR-4 appearance preserved).
        expect(usd.where((a) => a.showCurrency).length, 1);
        expect(omr.where((a) => a.showCurrency).length, 0);
      },
    );

    // #818 Wave 3.1: the unconditional green `+` (a second signed sage
    // RAmount rendered IN PLACE of the timestamp) is gone — settlement rows
    // now fall into the same relative-timestamp `else` branch as every other
    // row. A NEW directional fixture (not `_todayActivity()`, which the
    // legacy-fallback assertions at :424/:546/:710 depend on staying
    // direction-key-free) exercises this.
    testWidgets(
      'settlement row shows no signed sage amount and renders the relative '
      'timestamp instead',
      (tester) async {
        final fakeDb = FakeFirebaseFirestore();
        final prefs = await SharedPreferences.getInstance();
        final timestamp = _atMidday(0).subtract(const Duration(hours: 2));
        await _seedActivities(fakeDb, 'grp-1', [
          GroupActivityLog(
            id: 'act-directional',
            type: 'group_settlement',
            actorId: 'uid-alice',
            actorName: 'Alice',
            description: 'settled OMR 10.500 with Bob',
            metadata: const {
              'amount': '10.5',
              'currency': 'OMR',
              'recipientId': 'uid-bob',
              'fromUserId': 'uid-alice',
              'toUserId': 'uid-bob',
              'fromName': 'Alice',
              'toName': 'Bob',
            },
            timestamp: timestamp,
          ),
        ]);

        await tester.pumpWidget(
          _buildActivityScreen(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
        );
        await tester.pumpAndSettle();

        // Only the single unsigned main amount — no second signed sage
        // RAmount rendered for the settlement row.
        final amounts = tester
            .widgetList<RAmount>(find.byType(RAmount))
            .toList();
        expect(amounts, hasLength(1));
        expect(amounts.single.sign, isFalse);
        expect(amounts.single.tone, isNot(AmountTone.sage));

        // The relative timestamp renders where the signed amount used to be.
        final context = tester.element(find.byType(GroupActivityScreen));
        final expectedTime = formatRelativeShort(context, timestamp);
        expect(find.text(expectedTime), findsOneWidget);
      },
    );
  });

  group('expense fan-in rendering (#808 PR2)', () {
    GroupActivityLog expenseLog({
      String id = 'exp-1',
      String type = 'expense_added',
      String eventName = 'Beach Trip',
      int amountFils = 10500,
      String currency = 'OMR',
    }) => GroupActivityLog(
      id: id,
      type: type,
      actorId: 'uid-alice',
      actorName: 'Alice',
      // The server fan-in writes an English verb phrase WITH the label; the
      // client localizes GENERICALLY (no label) from type + eventName.
      description: 'added Dinner (10.500 OMR)',
      metadata: {
        'expenseId': 'e1',
        'eventId': 'ev1',
        'eventName': eventName,
        'amountFils': amountFils,
        'currency': currency,
      },
      timestamp: _atMidday(0),
    );

    testWidgets('localizes an expense row with a receipt icon and the amount '
        'from amountFils', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await _seedActivities(fakeDb, 'grp-exp', [expenseLog()]);

      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-exp', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_richTextContaining('added an expense in Beach Trip'), findsOneWidget);
      // The embedded English label from the fan-in description is NOT surfaced.
      expect(_richTextContaining('Dinner'), findsNothing);
      expect(find.byIcon(Iconsax.receipt_add), findsOneWidget);

      final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
      expect(amounts, hasLength(1));
      // 10500 fils = OMR 10.500 — never 10,500.
      expect(amounts.single.value, Decimal.parse('10.5'));
      expect(amounts.single.currency, 'OMR');
    });

    testWidgets('the Expenses filter chip shows only expense rows', (
      tester,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      final prefs = await SharedPreferences.getInstance();
      await _seedActivities(fakeDb, 'grp-exp-filter', [
        expenseLog(),
        _todayActivity(), // group_settlement
      ]);

      await tester.pumpWidget(
        _buildActivityScreen(
          groupId: 'grp-exp-filter',
          fakeDb: fakeDb,
          prefs: prefs,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.activityFilterExpenses), findsOneWidget);
      await tester.tap(find.byKey(GroupKeys.activityFilterExpenses));
      await tester.pumpAndSettle();

      expect(_richTextContaining('added an expense in Beach Trip'), findsOneWidget);
      expect(_richTextContaining('recorded a settlement'), findsNothing);
    });
  });

  // #852: rows in the raised day card deep-link per type via the shared
  // activityRowTarget table; targets resolving to this screen's own group
  // root stay inert (pushing a duplicate of the parent is the same false
  // affordance this issue removes).
  group('row deep-links (#852)', () {
    GroupActivityLog makeLog(
      String id,
      String type, {
      Map<String, dynamic> metadata = const {},
    }) => GroupActivityLog(
      id: id,
      type: type,
      actorId: 'uid-alice',
      actorName: 'Alice',
      description: 'does something',
      metadata: metadata,
      timestamp: _atMidday(0),
    );

    Future<void> pumpSeeded(
      WidgetTester tester,
      GroupActivityLog log,
    ) async {
      final fakeDb = FakeFirebaseFirestore();
      await _seedActivities(fakeDb, 'grp-1', [log]);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityRoute(groupId: 'grp-1', fakeDb: fakeDb, prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('expense_added routes to the event ledger', (tester) async {
      await pumpSeeded(
        tester,
        makeLog(
          'e1',
          'expense_added',
          metadata: const {
            'eventId': 'ev1',
            'eventName': 'Beach Trip',
            'amountFils': 500,
            'currency': 'OMR',
          },
        ),
      );

      await tester.tap(_richTextContaining('added an expense in Beach Trip'));
      await tester.pumpAndSettle();

      expect(find.text('EventLedger:grp-1/ev1'), findsOneWidget);
    });

    testWidgets('group_settlement routes to group settle-up', (tester) async {
      await pumpSeeded(
        tester,
        makeLog(
          's1',
          'group_settlement',
          metadata: const {'amount': '12.5'},
        ),
      );

      await tester.tap(find.byIcon(Iconsax.wallet_3));
      await tester.pumpAndSettle();

      expect(find.text('GroupSettleUp:grp-1'), findsOneWidget);
    });

    testWidgets('event_created routes to the event hub', (tester) async {
      await pumpSeeded(
        tester,
        makeLog(
          'ev-log',
          'event_created',
          metadata: const {'eventId': 'ev1', 'eventName': 'Beach Trip'},
        ),
      );

      await tester.tap(_richTextContaining('created Beach Trip'));
      await tester.pumpAndSettle();

      expect(find.text('EventHub:grp-1/ev1'), findsOneWidget);
      expect(find.text('GroupDetail:grp-1'), findsNothing);
    });

    testWidgets(
      'member_joined row is inert — self-target never pushes a duplicate '
      'group detail',
      (tester) async {
        await pumpSeeded(tester, makeLog('m1', 'member_joined'));

        await tester.tap(
          _richTextContaining('joined the group'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.activityScreen), findsOneWidget);
        expect(find.text('GroupDetail:grp-1'), findsNothing);
      },
    );

    testWidgets(
      'expense_added with a forged eventId is inert and never an ErrorWidget',
      (tester) async {
        await pumpSeeded(
          tester,
          makeLog(
            'e-forged',
            'expense_added',
            metadata: const {
              'eventId': 42,
              'eventName': 'Beach Trip',
              'amountFils': 500,
              'currency': 'OMR',
            },
          ),
        );

        await tester.tap(
          _richTextContaining('added an expense in Beach Trip'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.byKey(GroupKeys.activityScreen), findsOneWidget);
        expect(find.text('GroupDetail:grp-1'), findsNothing);
        expect(find.text('EventLedger:grp-1/42'), findsNothing);
      },
    );
  });
}
