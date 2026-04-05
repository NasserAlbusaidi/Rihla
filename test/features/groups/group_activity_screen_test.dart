import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/screens/group_activity_screen.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps GroupActivityScreen in ProviderScope + MaterialApp.
///
/// The screen uses [GroupActivityService.fetchActivityPageRaw] which
/// needs a live Firestore. We inject [FakeFirebaseFirestore] via
/// [groupActivityServiceProvider] override.
Widget _buildActivityScreen({
  required String groupId,
  SharedPreferences? prefs,
}) {
  final fakeDb = FakeFirebaseFirestore();
  final activityService = GroupActivityService.withFirestore(fakeDb);

  return ProviderScope(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      groupActivityServiceProvider.overrideWith((ref) => activityService),
    ],
    child: MaterialApp(
      home: GroupActivityScreen(groupId: groupId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GroupActivityScreen', () {
    testWidgets('renders Group Activity header', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-1', prefs: prefs),
      );
      // Pump once to start initState, then settle
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.activityScreenTitle), findsOneWidget);
    });

    testWidgets('renders empty state when no activity entries exist', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-empty', prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Empty state presence (title is passed as constructor arg to EmptyStateView)
      expect(find.byKey(SharedKeys.emptyStateView), findsOneWidget);
    });

    testWidgets('renders empty state message', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-empty2', prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Actions like creating events and settling up will appear here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders back button', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-1', prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Back button
      expect(find.byKey(GroupKeys.activityBackButton), findsOneWidget);
    });

    testWidgets('renders SafeArea as root layout', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-safearea', prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(SafeArea), findsOneWidget);
    });

    // --- Phase 30 Stubs (RED — will turn GREEN after Plan 03) ---

    testWidgets(
      'renders date section headers (TODAY, YESTERDAY)',
      (tester) async {
        // Seed activities with today and yesterday timestamps
        // Expect: find.text('TODAY'), find.text('YESTERDAY')
        final fakeDb = FakeFirebaseFirestore();
        final activityService = GroupActivityService.withFirestore(fakeDb);

        // Insert activity from today
        final today = DateTime.now().toUtc();
        await fakeDb
            .collection('groups')
            .doc('grp-dates')
            .collection('activity')
            .add({
          'id': 'act-today',
          'type': 'event_created',
          'actorId': 'uid1',
          'actorName': 'Alice',
          'description': 'Alice created event today',
          'metadata': <String, dynamic>{},
          'timestamp': today.toIso8601String(),
        });

        // Insert activity from yesterday
        final yesterday =
            today.subtract(const Duration(days: 1));
        await fakeDb
            .collection('groups')
            .doc('grp-dates')
            .collection('activity')
            .add({
          'id': 'act-yesterday',
          'type': 'member_joined',
          'actorId': 'uid2',
          'actorName': 'Bob',
          'description': 'Bob joined yesterday',
          'metadata': <String, dynamic>{},
          'timestamp': yesterday.toIso8601String(),
        });

        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
              groupActivityServiceProvider.overrideWith(
                (ref) => activityService,
              ),
            ],
            child: const MaterialApp(
              home: GroupActivityScreen(groupId: 'grp-dates'),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('TODAY'), findsOneWidget);
        expect(find.text('YESTERDAY'), findsOneWidget);
      },
      skip: true, // Phase 30: will pass after Plan 03 implementation
    );

    testWidgets(
      'renders 4 filter chips',
      (tester) async {
        // Pump screen
        // Expect: find.byKey(GroupKeys.activityFilterAll),
        //         find.byKey(GroupKeys.activityFilterSettlements),
        //         find.byKey(GroupKeys.activityFilterEvents),
        //         find.byKey(GroupKeys.activityFilterMembers)
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          _buildActivityScreen(groupId: 'grp-1', prefs: prefs),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.activityFilterAll), findsOneWidget);
        expect(
          find.byKey(GroupKeys.activityFilterSettlements),
          findsOneWidget,
        );
        expect(find.byKey(GroupKeys.activityFilterEvents), findsOneWidget);
        expect(find.byKey(GroupKeys.activityFilterMembers), findsOneWidget);
      },
      skip: true, // Phase 30: will pass after Plan 03 implementation
    );

    testWidgets(
      'Settlements filter shows only settlement activities',
      (tester) async {
        // Seed mixed activities (settlement + event + member)
        // Tap Settlements filter chip
        // Expect: only settlement description visible
        final fakeDb = FakeFirebaseFirestore();
        final activityService = GroupActivityService.withFirestore(fakeDb);

        final now = DateTime.now().toUtc();
        await fakeDb
            .collection('groups')
            .doc('grp-filter')
            .collection('activity')
            .doc('act-settlement')
            .set({
          'id': 'act-settlement',
          'type': 'group_settlement',
          'actorId': 'uid1',
          'actorName': 'Alice',
          'description': 'Alice settled with Bob',
          'metadata': <String, dynamic>{},
          'timestamp': now.toIso8601String(),
        });
        await fakeDb
            .collection('groups')
            .doc('grp-filter')
            .collection('activity')
            .doc('act-event')
            .set({
          'id': 'act-event',
          'type': 'event_created',
          'actorId': 'uid2',
          'actorName': 'Bob',
          'description': 'Bob created a camping event',
          'metadata': <String, dynamic>{},
          'timestamp': now
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        });

        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
              groupActivityServiceProvider.overrideWith(
                (ref) => activityService,
              ),
            ],
            child: const MaterialApp(
              home: GroupActivityScreen(groupId: 'grp-filter'),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        // Tap Settlements filter chip
        await tester.tap(find.byKey(GroupKeys.activityFilterSettlements));
        await tester.pumpAndSettle();

        // Only settlement description should be visible
        expect(find.text('Alice settled with Bob'), findsOneWidget);
        expect(find.text('Bob created a camping event'), findsNothing);
      },
      skip: true, // Phase 30: will pass after Plan 03 implementation
    );

    testWidgets(
      'renders activity tile with actor name and description',
      (tester) async {
        // Seed one activity
        // Expect: actor name and description text visible
        final fakeDb = FakeFirebaseFirestore();
        final activityService = GroupActivityService.withFirestore(fakeDb);

        final now = DateTime.now().toUtc();
        await fakeDb
            .collection('groups')
            .doc('grp-tile')
            .collection('activity')
            .doc('act-1')
            .set({
          'id': 'act-1',
          'type': 'event_created',
          'actorId': 'uid1',
          'actorName': 'Alice',
          'description': 'Alice created Weekend Trip',
          'metadata': <String, dynamic>{},
          'timestamp': now.toIso8601String(),
        });

        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
              groupActivityServiceProvider.overrideWith(
                (ref) => activityService,
              ),
            ],
            child: const MaterialApp(
              home: GroupActivityScreen(groupId: 'grp-tile'),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsWidgets);
        expect(find.textContaining('Weekend Trip'), findsOneWidget);
      },
      skip: true, // Phase 30: will pass after Plan 03 implementation
    );

    testWidgets(
      'no Load more button present (infinite scroll replaces it)',
      (tester) async {
        // Pump screen with activities
        // Expect: find.text('Load more') findsNothing
        final fakeDb = FakeFirebaseFirestore();
        final activityService = GroupActivityService.withFirestore(fakeDb);

        // Seed 3 activities (below page limit — _hasMore will be false)
        final now = DateTime.now().toUtc();
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
            'timestamp':
                now.subtract(Duration(minutes: i)).toIso8601String(),
          });
        }

        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
              groupActivityServiceProvider.overrideWith(
                (ref) => activityService,
              ),
            ],
            child: const MaterialApp(
              home: GroupActivityScreen(groupId: 'grp-scroll'),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        // Infinite scroll replaces 'Load more' button — must not be present
        expect(find.text('Load more'), findsNothing);
      },
      skip: true, // Phase 30: will pass after Plan 03 implementation
    );
  });
}
