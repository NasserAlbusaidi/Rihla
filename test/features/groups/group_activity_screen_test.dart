import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
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
  List<GroupActivityLog> activities = const [],
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

      expect(find.text('Group Activity'), findsOneWidget);
    });

    testWidgets('renders empty state when no activity entries exist', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _buildActivityScreen(groupId: 'grp-empty', prefs: prefs),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Empty state title from EmptyStateView
      expect(find.text('No group activity yet'), findsOneWidget);
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

      // Back button is an IconButton with Iconsax.arrow_left icon
      expect(find.byType(IconButton), findsOneWidget);
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
  });
}
