import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/features/groups/screens/group_settings_screen.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

// ---------------------------------------------------------------------------
// CreateGroupScreen tests
// ---------------------------------------------------------------------------

void main() {
  group('CreateGroupScreen', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    Future<Widget> buildCreateScreen({bool loading = false}) async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupLoadingProvider.overrideWith((ref) => loading),
          groupErrorProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CreateGroupScreen(),
        ),
      );
    }

    testWidgets('renders top bar with New group title', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('New group'), findsOneWidget);
    });

    testWidgets('renders Create Group wireframe content', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text("Who's coming along?"), findsOneWidget);
      expect(
        find.text(
          'A group is a circle of people you share expenses with — a household, a travel crew, a project team.',
        ),
        findsOneWidget,
      );
      expect(find.text('Group glyph'), findsOneWidget);
      expect(find.text('⛺'), findsOneWidget);
      expect(find.text('⌂'), findsOneWidget);
      expect(find.text('Default currency'), findsOneWidget);
      expect(find.text('OMR · ر.ع.'), findsOneWidget);
      expect(find.text("You're the creator."), findsOneWidget);
    });

    testWidgets('renders Group Name label and hint', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('Group Name'), findsOneWidget);
      expect(find.text('e.g. Family trip'), findsOneWidget);
    });

    testWidgets('renders Your name in this group label', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('Your name in this group'), findsOneWidget);
    });

    testWidgets('pre-fills display name from settings', (tester) async {
      // The device name is seeded in setUpAll via SharedPreferences mock.
      // The controller text is set lazily on first build when _didInitName=false.
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CreateGroupScreen(),
          ),
        ),
      );
      await tester.pump();
      // Device name from SharedPreferences ('Test User') should appear in the
      // display name controller.
      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('renders top-bar Create action', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator when loading is true', (
      tester,
    ) async {
      // LoadingButton shows CircularProgressIndicator when isLoading=true,
      // not the label text.
      await tester.pumpWidget(await buildCreateScreen(loading: true));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('validates group name is required on submit', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();

      // Tap Create without filling the group name field
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text("Group name can't be empty."), findsOneWidget);
    });

    testWidgets('validates display name is required on submit', (tester) async {
      SharedPreferences.setMockInitialValues({'device_name': ''});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CreateGroupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Type group name but leave display name blank
      final nameFields = find.byType(TextFormField);
      await tester.enterText(nameFields.first, 'My Group');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter your name so others know who you are.'),
        findsOneWidget,
      );

      // Reset for subsequent tests
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    testWidgets('renders close button in top bar', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.byType(CloseButton), findsOneWidget);
    });

    testWidgets('renders form with TextFormFields', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      // Expect at least 2 text form fields: group name and display name
      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });

    testWidgets('group name text field accepts input', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();

      final nameFields = find.byType(TextFormField);
      await tester.enterText(nameFields.first, 'My Travel Group');
      expect(find.text('My Travel Group'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // JoinGroupScreen tests
  // ---------------------------------------------------------------------------

  group('JoinGroupScreen', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    Future<Widget> buildJoinScreen({bool loading = false}) async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupLoadingProvider.overrideWith((ref) => loading),
          groupErrorProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const JoinGroupScreen(),
        ),
      );
    }

    testWidgets('renders AppBar with Join a Group title', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Join a Group'), findsOneWidget);
    });

    testWidgets('renders Your name label', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Your name'), findsOneWidget);
    });

    testWidgets('pre-fills display name from settings', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const JoinGroupScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('renders Invite code label', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Invite code'), findsOneWidget);
    });

    testWidgets('renders 6-character instruction text', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(
        find.text('Ask a group member for their 6-character code'),
        findsOneWidget,
      );
    });

    testWidgets('renders Join Group button', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Join Group'), findsOneWidget);
    });

    testWidgets('Join Group button is disabled when code field is empty', (
      tester,
    ) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Join Group'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows CircularProgressIndicator when loading is true', (
      tester,
    ) async {
      // LoadingButton shows CircularProgressIndicator when isLoading=true.
      await tester.pumpWidget(await buildJoinScreen(loading: true));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders ABC123 hint text in code input', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets('code input uppercases typed text', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();

      // The code field is the last TextFormField on the screen
      final codeField = find.byType(TextFormField).last;
      await tester.enterText(codeField, 'abc12');
      await tester.pump();

      expect(find.text('ABC12'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // GroupSettingsScreen tests
  // ---------------------------------------------------------------------------

  group('GroupSettingsScreen', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    final testGroup = Group(
      id: 'group-1',
      name: 'Adventure Crew',
      inviteCode: 'XYZ789',
      createdBy: 'uid-creator',
      memberIds: const ['uid-creator'],
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

    final testMembers = [
      GroupMember(
        id: 'mem-1',
        groupId: 'group-1',
        userId: 'uid-creator',
        displayName: 'Alice',
        role: 'CREATOR',
        joinedAt: DateTime(2026, 1, 1),
      ),
    ];

    Future<Widget> buildSettingsScreen() async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(
            'group-1',
          ).overrideWith((ref) => Stream.value(testGroup)),
          groupMembersProvider(
            'group-1',
          ).overrideWith((ref) => Stream.value(testMembers)),
          groupBalancesProvider('group-1').overrideWith(
            (ref) => AsyncValue.data((
              balances: <UserBalance>[],
              totalSpent: Decimal.zero,
              eventCount: 0,
              perEventBreakdown: <String, Map<String, Decimal>>{},
              memberNames: <String, String>{},
            )),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const GroupSettingsScreen(groupId: 'group-1'),
        ),
      );
    }

    testWidgets('renders back button (no AppBar)', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('group_settings_back_button')),
        findsOneWidget,
      );
    });

    testWidgets('renders Group Name label', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Group Name'), findsOneWidget);
    });

    testWidgets('renders group name value', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Adventure Crew'), findsOneWidget);
    });

    testWidgets('renders Invite Code label', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Invite Code'), findsOneWidget);
    });

    testWidgets('renders invite code value', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('XYZ789'), findsOneWidget);
    });

    testWidgets('shows skeleton loader when group stream not yet emitted', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final widget = ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(
            'group-loading',
          ).overrideWith((ref) => const Stream.empty()),
          groupMembersProvider(
            'group-loading',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const GroupSettingsScreen(groupId: 'group-loading'),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pump();
      expect(find.byType(SkeletonLoader), findsOneWidget);
    });

    testWidgets('shows error text when group stream errors', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final widget = ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider('group-error').overrideWith(
            (ref) => Stream<Group?>.error(Exception('test error')),
          ),
          groupMembersProvider(
            'group-error',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const GroupSettingsScreen(groupId: 'group-error'),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(find.text('Could not load settings'), findsOneWidget);
    });
  });
}
