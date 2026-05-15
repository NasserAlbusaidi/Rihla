import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settings_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

final _testGroup = Group(
  id: 'group-1',
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'uid-member'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

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

final _zeroBalances = (
  balances: <UserBalance>[
    UserBalance(
      participantId: 'uid-creator',
      displayName: 'Alice',
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.zero,
    ),
    UserBalance(
      participantId: 'uid-member',
      displayName: 'Bob',
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.zero,
    ),
  ],
  totalSpent: Decimal.zero,
  eventCount: 0,
  perEventBreakdown: <String, Map<String, Decimal>>{},
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
);

final _nonZeroBalances = (
  balances: <UserBalance>[
    UserBalance(
      participantId: 'uid-creator',
      displayName: 'Alice',
      totalPaid: Decimal.parse('30.000'),
      totalOwed: Decimal.parse('15.000'),
      netBalance: Decimal.parse('15.000'),
    ),
    UserBalance(
      participantId: 'uid-member',
      displayName: 'Bob',
      totalPaid: Decimal.zero,
      totalOwed: Decimal.parse('15.000'),
      netBalance: Decimal.parse('-15.000'),
    ),
  ],
  totalSpent: Decimal.parse('30.000'),
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Decimal>>{
    'uid-creator': {'evt-1': Decimal.parse('15.000')},
    'uid-member': {'evt-1': Decimal.parse('-15.000')},
  },
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wrap with creator view — currentUserIdProvider = 'uid-creator'.
Widget _wrapCreatorView(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_zeroBalances)),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: child),
  );
}

/// Wrap with member view — currentUserIdProvider = 'uid-member'.
Widget _wrapMemberView(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-member'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_zeroBalances)),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: child),
  );
}

/// Wrap with creator view and non-zero balances (for balance gate tests).
Widget _wrapCreatorWithBalances(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_nonZeroBalances)),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: child),
  );
}

Widget _wrapDeleteNavigationTest({
  required SharedPreferences prefs,
  required StreamController<Group?> groupController,
  required Completer<void> deleteStarted,
  required Completer<void> allowDeleteToComplete,
}) {
  final router = GoRouter(
    initialLocation: '/group/group-1/settings',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (context, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['gid']}')),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, state) =>
                GroupSettingsScreen(groupId: state.pathParameters['gid']!),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => groupController.stream),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_zeroBalances)),
      groupServiceProvider.overrideWith(
        (ref) => _RouteInvalidatingDeleteService(
          ref,
          onDelete: () async {
            deleteStarted.complete();
            groupController.add(null);
            await allowDeleteToComplete.future;
          },
        ),
      ),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
}

Widget _wrapBackNavigationTest({required SharedPreferences prefs}) {
  final router = GoRouter(
    initialLocation: '/group/group-1/settings',
    routes: [
      GoRoute(
        path: '/group/:gid',
        builder: (context, state) =>
            Scaffold(body: Text('GroupDetail:${state.pathParameters['gid']}')),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, state) =>
                GroupSettingsScreen(groupId: state.pathParameters['gid']!),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_zeroBalances)),
    ],
    child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
}

class _RouteInvalidatingDeleteService extends GroupService {
  _RouteInvalidatingDeleteService(Ref ref, {required this.onDelete})
    : super.withFirestore(ref, FakeFirebaseFirestore());

  final Future<void> Function() onDelete;

  @override
  Future<void> deleteGroup({required String groupId}) => onDelete();
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

  group('GroupSettingsScreen Phase 29', () {
    // --- Layout ---

    testWidgets('renders back button instead of AppBar', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settingsBackButton), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('direct route back button returns to group detail', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapBackNavigationTest(prefs: prefs));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settingsBackButton));
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:group-1'), findsOneWidget);
    });

    testWidgets('renders GroupInfoSection', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.infoSection), findsOneWidget);
    });

    testWidgets('renders GroupMembersSection', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.membersSection), findsOneWidget);
    });

    testWidgets('renders GroupDangerSection', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.dangerSection), findsOneWidget);
    });

    // --- GroupInfoSection ---

    testWidgets('shows group name tile with current name', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settingsGroupNameTile), findsOneWidget);
      expect(find.text('Adventure Crew'), findsOneWidget);
    });

    testWidgets('shows invite code tile with code text', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settingsInviteCodeTile), findsOneWidget);
      expect(find.text('ABC123'), findsWidgets);
    });

    // --- GroupMembersSection ---

    testWidgets('shows member names in members section', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.memberTile('mem-1')), findsOneWidget);
      expect(find.byKey(GroupKeys.memberTile('mem-2')), findsOneWidget);
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows creator badge for creator member only', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.creatorBadge), findsOneWidget);
    });

    testWidgets('creator sees remove button for non-creator members', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      // Creator (Alice) should see remove button for Bob (mem-2) only
      expect(find.byKey(GroupKeys.removeMemberButton('mem-2')), findsOneWidget);
      // Creator should NOT see remove button for themselves
      expect(find.byKey(GroupKeys.removeMemberButton('mem-1')), findsNothing);
    });

    testWidgets('non-creator does not see remove buttons', (tester) async {
      await tester.pumpWidget(
        _wrapMemberView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.removeMemberButton('mem-1')), findsNothing);
      expect(find.byKey(GroupKeys.removeMemberButton('mem-2')), findsNothing);
    });

    // --- GroupDangerSection ---

    testWidgets('all members see leave group tile', (tester) async {
      await tester.pumpWidget(
        _wrapMemberView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.leaveGroupTile), findsOneWidget);
    });

    testWidgets('creator sees delete group tile', (tester) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.deleteGroupTile), findsOneWidget);
    });

    testWidgets('non-creator does not see delete group tile', (tester) async {
      await tester.pumpWidget(
        _wrapMemberView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.deleteGroupTile), findsNothing);
    });

    // --- Confirmation dialogs ---

    testWidgets('tapping leave tile shows confirmation dialog', (tester) async {
      await tester.pumpWidget(
        _wrapMemberView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.leaveGroupTile));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.leaveGroupDialog), findsOneWidget);
    });

    testWidgets('tapping delete tile shows confirmation dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCreatorView(const GroupSettingsScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(GroupKeys.deleteGroupTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.deleteGroupTile));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.deleteGroupDialog), findsOneWidget);
    });

    // --- Balance gate (D-07) ---

    testWidgets(
      'remove blocked when member has non-zero balance shows snackbar',
      (tester) async {
        await tester.pumpWidget(
          _wrapCreatorWithBalances(
            const GroupSettingsScreen(groupId: 'group-1'),
            prefs,
          ),
        );
        await tester.pumpAndSettle();

        // Bob has non-zero balance — tapping remove should show a snackbar
        await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
        await tester.pumpAndSettle();

        expect(
          find.text('Settle up with Bob before removing them.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'delete navigates home even when group stream invalidates settings route',
      (tester) async {
        final groupController = StreamController<Group?>();
        addTearDown(groupController.close);
        final deleteStarted = Completer<void>();
        final allowDeleteToComplete = Completer<void>();

        await tester.pumpWidget(
          _wrapDeleteNavigationTest(
            prefs: prefs,
            groupController: groupController,
            deleteStarted: deleteStarted,
            allowDeleteToComplete: allowDeleteToComplete,
          ),
        );
        groupController.add(_testGroup);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(GroupKeys.deleteGroupTile));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.deleteGroupTile));
        await tester.pumpAndSettle();
        // Type-to-confirm: enter the group name to enable the destructive button.
        await tester.enterText(
          find.descendant(
            of: find.byKey(GroupKeys.deleteGroupDialog),
            matching: find.byType(TextField),
          ),
          _testGroup.name,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.deleteGroupConfirmButton));
        await deleteStarted.future;
        await tester.pumpAndSettle();
        expect(find.text('Could not load settings'), findsOneWidget);

        allowDeleteToComplete.complete();
        await tester.pumpAndSettle();

        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Could not load settings'), findsNothing);
      },
    );
  });
}
