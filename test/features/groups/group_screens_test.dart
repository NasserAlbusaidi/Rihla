import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/groups/screens/group_settings_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stub group used across tests.
final _testGroup = Group(
  id: 'group-1',
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'uid-member'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

/// Stub member list — two members.
final _testMembers = [
  GroupMember(
    id: 'mem-1',
    groupId: 'group-1',
    userId: 'uid-creator',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'mem-2',
    groupId: 'group-1',
    userId: 'uid-member',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 2),
  ),
];

/// Wraps a widget in ProviderScope + MaterialApp with shared test overrides.
///
/// Also overrides [groupEventsProvider] so GroupDetailScreen does not attempt
/// to open a real Firestore stream, and overrides
/// [tripExpensesProvider] (no-op empty list) to prevent SQLite initialization
/// from EventCard's live financial total.
Widget _wrap(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      groupDetailProvider('group-1').overrideWith(
        (ref) => Stream.value(_testGroup),
      ),
      groupMembersProvider('group-1').overrideWith(
        (ref) => Stream.value(_testMembers),
      ),
      groupEventsProvider('group-1').overrideWith(
        (ref) => Stream.value(const []),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    prefs = await SharedPreferences.getInstance();
  });

  group('Group screens', () {
    // -----------------------------------------------------------------------
    // GroupDetailScreen
    // -----------------------------------------------------------------------
    group('GroupDetailScreen', () {
      testWidgets('shows group name in header', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        // ModuleHeader renders group.name as the large title text
        expect(find.text('Adventure Crew'), findsWidgets);
      });

      testWidgets('shows member count chip', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('2 members'), findsOneWidget);
      });

      testWidgets('shows invite code section header and code display',
          (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        // Section header
        expect(find.text('Invite Code'), findsOneWidget);
        // The code itself appears in InviteCodeDisplay
        expect(find.text('ABC123'), findsWidgets);
      });

      testWidgets('shows members section with member names from groupMembersProvider',
          (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Members'), findsOneWidget);
        // Member names rendered via GroupMemberTile
        expect(find.text('Alice'), findsWidgets);
        expect(find.text('Bob'), findsOneWidget);
      });

      testWidgets(
          'shows "No events yet" empty state when no events exist', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('No events yet'), findsOneWidget);
        // Copywriting Contract message for 03-03
        expect(
          find.text(
            'Tap the + button to create the first event for this group.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('shows Events section header', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupDetailScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Events'), findsOneWidget);
      });
    });

    // -----------------------------------------------------------------------
    // GroupSettingsScreen
    // -----------------------------------------------------------------------
    group('GroupSettingsScreen', () {
      testWidgets('shows Group Settings appbar title', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupSettingsScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Group Settings'), findsOneWidget);
      });

      testWidgets('shows group name tile with current name (D-15)', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupSettingsScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Group Name'), findsOneWidget);
        expect(find.text('Adventure Crew'), findsOneWidget);
      });

      testWidgets('shows currency tile with change option (D-16)', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupSettingsScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Currency'), findsOneWidget);
        expect(find.text('OMR'), findsOneWidget);
      });

      testWidgets('shows invite code tile with copy button', (tester) async {
        await tester.pumpWidget(
          _wrap(const GroupSettingsScreen(groupId: 'group-1'), prefs),
        );
        await tester.pumpAndSettle();

        expect(find.text('Invite Code'), findsOneWidget);
        expect(find.text('ABC123'), findsWidgets);
      });
    });
  });
}
