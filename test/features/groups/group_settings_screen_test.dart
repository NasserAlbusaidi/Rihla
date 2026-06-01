import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settings_screen.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/groups/widgets/group_info_section.dart';
import 'package:safar/features/groups/widgets/group_members_section.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

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
  memberRawNames: <String, String>{},
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
  memberRawNames: <String, String>{},
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wrap with creator view — currentUserIdProvider = 'uid-creator'.
Widget _wrapCreatorView(
  Widget child,
  SharedPreferences prefs, {
  List<GroupMember>? members,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(members ?? _testMembers)),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(_zeroBalances)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
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
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
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
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
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
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
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
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Widget _wrapGroupInfoSection({
  required Future<void> Function({
    required String groupId,
    String? name,
    String? currency,
  })
  onUpdateGroup,
  Group? group,
  bool isCreator = true,
}) {
  return ProviderScope(
    overrides: [
      groupServiceProvider.overrideWith(
        (ref) => _UpdatingGroupService(ref, onUpdateGroup: onUpdateGroup),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GroupInfoSection(
          group: group ?? _testGroup,
          isCreator: isCreator,
        ),
      ),
    ),
  );
}

Widget _wrapMembersSection({
  required SharedPreferences prefs,
  required GroupService Function(Ref ref) groupServiceBuilder,
  required GroupActivityService activityService,
  GroupBalances? balances,
  List<GroupMember> members = const [],
}) {
  final sectionMembers = members.isEmpty ? _testMembers : members;
  final sectionBalances = balances ?? _zeroBalances;
  final router = GoRouter(
    initialLocation: '/members',
    routes: [
      GoRoute(
        path: '/members',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: GroupMembersSection(
              groupId: 'group-1',
              members: sectionMembers,
              currentUserId: 'uid-creator',
              isCurrentUserCreator: true,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/group/:gid/settle-up',
        builder: (context, state) =>
            Scaffold(body: Text('SettleUp:${state.pathParameters['gid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(sectionBalances)),
      groupServiceProvider.overrideWith(groupServiceBuilder),
      groupActivityServiceProvider.overrideWith((ref) => activityService),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

class _RouteInvalidatingDeleteService extends GroupService {
  _RouteInvalidatingDeleteService(Ref ref, {required this.onDelete})
    : super.withFirestore(ref, FakeFirebaseFirestore());

  final Future<void> Function() onDelete;

  @override
  Future<void> deleteGroup({required String groupId}) => onDelete();
}

class _UpdatingGroupService extends GroupService {
  _UpdatingGroupService(Ref ref, {required this.onUpdateGroup})
    : super.withFirestore(ref, FakeFirebaseFirestore());

  final Future<void> Function({
    required String groupId,
    String? name,
    String? currency,
  })
  onUpdateGroup;

  @override
  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? currency,
  }) {
    return onUpdateGroup(groupId: groupId, name: name, currency: currency);
  }
}

class _RemovingGroupService extends GroupService {
  _RemovingGroupService(Ref ref, {this.onRemove})
    : super.withFirestore(ref, FakeFirebaseFirestore());

  final Future<void> Function({
    required String groupId,
    required String memberId,
    required String userId,
  })?
  onRemove;

  final removeCalls = <({String groupId, String memberId, String userId})>[];

  @override
  Future<void> removeMember({
    required String groupId,
    required String memberId,
    required String userId,
  }) async {
    removeCalls.add((groupId: groupId, memberId: memberId, userId: userId));
    await onRemove?.call(groupId: groupId, memberId: memberId, userId: userId);
  }
}

class _RecordingGroupActivityService extends GroupActivityService {
  _RecordingGroupActivityService()
    : super.withFirestore(FakeFirebaseFirestore());

  final logCalls =
      <
        ({
          String groupId,
          String type,
          String actorId,
          String actorName,
          String description,
          Map<String, dynamic>? metadata,
        })
      >[];

  @override
  void logGroupEvent({
    required String groupId,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata,
  }) {
    logCalls.add((
      groupId: groupId,
      type: type,
      actorId: actorId,
      actorName: actorName,
      description: description,
      metadata: metadata,
    ));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }

    SharedPreferences.setMockInitialValues({
      'device_name': 'Test User',
      'settings_device_name': 'Test User',
    });
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

    testWidgets('creator edits and saves the group name', (tester) async {
      final calls = <({String groupId, String? name, String? currency})>[];
      await tester.pumpWidget(
        _wrapGroupInfoSection(
          onUpdateGroup: ({required groupId, name, currency}) async {
            calls.add((groupId: groupId, name: name, currency: currency));
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.groupNameEditIcon));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New Crew');
      await tester.tap(find.byIcon(Iconsax.tick_circle));
      await tester.pumpAndSettle();

      expect(calls, [(groupId: 'group-1', name: 'New Crew', currency: null)]);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('empty group name shows validation snack bar', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _wrapGroupInfoSection(
          onUpdateGroup: ({required groupId, name, currency}) async {
            called = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.groupNameEditIcon));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byIcon(Iconsax.tick_circle));
      await tester.pump();

      expect(called, isFalse);
      expect(find.text("Group name can't be empty."), findsOneWidget);
    });

    testWidgets('failed group-name save leaves editor open with error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapGroupInfoSection(
          onUpdateGroup: ({required groupId, name, currency}) async {
            throw StateError('write failed');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.groupNameEditIcon));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New Crew');
      await tester.tap(find.byIcon(Iconsax.tick_circle));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('Failed to update name'), findsOneWidget);
    });

    testWidgets('copy invite code writes the code to clipboard', (
      tester,
    ) async {
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = call.arguments as Map<dynamic, dynamic>;
              clipboardText = args['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        _wrapGroupInfoSection(
          onUpdateGroup: ({required groupId, name, currency}) async {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.inviteCodeCopyButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(clipboardText, 'ABC123');
      expect(find.text('Invite code copied'), findsOneWidget);
    });

    testWidgets('non-creator cannot open the group-name editor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapGroupInfoSection(
          isCreator: false,
          onUpdateGroup: ({required groupId, name, currency}) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.groupNameEditIcon), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Adventure Crew'), findsOneWidget);
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

    testWidgets('creator cannot remove tombstone members', (tester) async {
      final members = [
        ..._testMembers,
        GroupMember(
          id: 'deleted-a1b2c3d4',
          groupId: 'group-1',
          userId: 'deleted-a1b2c3d4',
          displayName: 'Deleted member',
          role: 'MEMBER',
          isTombstone: true,
          joinedAt: DateTime(2026, 1, 3),
        ),
      ];

      await tester.pumpWidget(
        _wrapCreatorView(
          const GroupSettingsScreen(groupId: 'group-1'),
          prefs,
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.memberTile('deleted-a1b2c3d4')),
        findsOneWidget,
      );
      expect(find.text('Deleted member'), findsOneWidget);
      expect(
        find.byKey(GroupKeys.removeMemberButton('deleted-a1b2c3d4')),
        findsNothing,
      );
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

    testWidgets('blocked removal snackbar action routes to settle up', (
      tester,
    ) async {
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrapMembersSection(
          prefs: prefs,
          groupServiceBuilder: _RemovingGroupService.new,
          activityService: activityService,
          balances: _nonZeroBalances,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SnackBarAction, 'Settle up'));
      await tester.pumpAndSettle();

      expect(find.text('SettleUp:group-1'), findsOneWidget);
      expect(activityService.logCalls, isEmpty);
    });

    testWidgets('successful member removal logs activity and calls service', (
      tester,
    ) async {
      late _RemovingGroupService groupService;
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrapMembersSection(
          prefs: prefs,
          groupServiceBuilder: (ref) =>
              groupService = _RemovingGroupService(ref),
          activityService: activityService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
      await tester.pumpAndSettle();

      expect(groupService.removeCalls, [
        (groupId: 'group-1', memberId: 'mem-2', userId: 'uid-member'),
      ]);
      expect(activityService.logCalls, hasLength(1));
      expect(activityService.logCalls.single.groupId, 'group-1');
      expect(activityService.logCalls.single.type, 'member_left');
      expect(activityService.logCalls.single.actorId, '');
      expect(activityService.logCalls.single.actorName, 'Test User');
      expect(
        activityService.logCalls.single.description,
        'Bob was removed from the group',
      );
      expect(activityService.logCalls.single.metadata, {
        'memberAction': 'removed',
        'memberName': 'Bob',
      });
    });

    testWidgets('member removal failure shows snackbar', (tester) async {
      late _RemovingGroupService groupService;
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrapMembersSection(
          prefs: prefs,
          groupServiceBuilder: (ref) => groupService = _RemovingGroupService(
            ref,
            onRemove: ({required groupId, required memberId, required userId}) {
              throw StateError('write failed');
            },
          ),
          activityService: activityService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to remove Bob: Bad state: write failed'),
        findsOneWidget,
      );
      expect(groupService.removeCalls, [
        (groupId: 'group-1', memberId: 'mem-2', userId: 'uid-member'),
      ]);
      expect(activityService.logCalls, hasLength(1));
    });
  });
}
