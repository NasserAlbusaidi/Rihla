import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  balances: <String, List<UserBalance>>{
    'OMR': [
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
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.zero},
  eventCount: 0,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
  memberRawNames: <String, String>{},
);

final _nonZeroBalances = (
  balances: <String, List<UserBalance>>{
    'OMR': [
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
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('30.000')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-creator': {
      'evt-1': {'OMR': Decimal.parse('15.000')},
    },
    'uid-member': {
      'evt-1': {'OMR': Decimal.parse('-15.000')},
    },
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

Widget _wrapDirectEntrySettingsBackFallbackTest({
  required SharedPreferences prefs,
}) {
  final router = GoRouter(
    initialLocation: '/group/group-1/settings',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/group/:gid/settings',
        builder: (context, state) =>
            GroupSettingsScreen(groupId: state.pathParameters['gid']!),
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

/// Pumps [GroupInfoSection] under a recording service so the ✎-opened
/// [GroupEditSheet]'s `updateGroupIdentity` call can be asserted, and returns
/// that service. The container is read eagerly so the recording service exists
/// even before the first save (a lazy `overrideWith` would leave it
/// uninstantiated). [onIdentitySave] lets a test make the save throw.
Future<_IdentityRecordingService> _pumpGroupInfoSection(
  WidgetTester tester, {
  Group? group,
  bool isCreator = true,
  Future<void> Function()? onIdentitySave,
}) async {
  final container = ProviderContainer(
    overrides: [
      groupServiceProvider.overrideWith(
        (ref) => _IdentityRecordingService(ref, onSave: onIdentitySave),
      ),
    ],
  );
  addTearDown(container.dispose);
  final service =
      container.read(groupServiceProvider) as _IdentityRecordingService;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
    ),
  );
  await tester.pumpAndSettle();
  return service;
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

/// Records every [updateGroupIdentity] call (the only write the ✎-opened
/// [GroupEditSheet] performs) so a test can assert the exact args, or that it
/// was never called. [onSave], when set, runs before recording — pass a
/// throwing closure to exercise the sheet's failure path.
class _IdentityRecordingService extends GroupService {
  _IdentityRecordingService(Ref ref, {this.onSave})
    : super.withFirestore(ref, FakeFirebaseFirestore());

  final Future<void> Function()? onSave;
  final calls =
      <({String groupId, String name, String? glyph, int? inkIndex})>[];

  @override
  Future<void> updateGroupIdentity({
    required String groupId,
    required String name,
    String? glyph,
    int? inkIndex,
  }) async {
    await onSave?.call();
    calls.add((groupId: groupId, name: name, glyph: glyph, inkIndex: inkIndex));
  }
}

class _RemovingGroupService extends GroupService {
  _RemovingGroupService(Ref ref, {this.onRemove})
    : super.withFirestore(ref, FakeFirebaseFirestore());

  final Future<void> Function({
    required String groupId,
    required String userId,
  })?
  onRemove;

  final removeCalls = <({String groupId, String userId})>[];

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    removeCalls.add((groupId: groupId, userId: userId));
    await onRemove?.call(groupId: groupId, userId: userId);
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

    testWidgets('direct-entry back button falls back to home without a stack', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapDirectEntrySettingsBackFallbackTest(prefs: prefs),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.settingsBackButton));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
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

    testWidgets('creator ✎ opens the edit sheet, saves name + stamp', (
      tester,
    ) async {
      final service = await _pumpGroupInfoSection(tester);

      await tester.tap(find.byKey(GroupKeys.groupNameEditIcon));
      await tester.pumpAndSettle();
      expect(find.byKey(GroupKeys.editGroupSheet), findsOneWidget);

      await tester.enterText(
        find.byKey(GroupKeys.editGroupNameField),
        'New Crew',
      );
      await tester.tap(find.byKey(GroupKeys.editGroupSaveButton));
      await tester.pumpAndSettle();

      // The single recorded identity write carries the edited name; glyph +
      // inkIndex pass through unchanged from the (unset) test group.
      expect(service.calls, hasLength(1));
      final call = service.calls.single;
      expect(call.groupId, 'group-1');
      expect(call.name, 'New Crew');
      // Sheet dismissed on success.
      expect(find.byKey(GroupKeys.editGroupSheet), findsNothing);
    });

    testWidgets('empty name in the sheet blocks Save (validation, no write)', (
      tester,
    ) async {
      final service = await _pumpGroupInfoSection(tester);

      await tester.tap(find.byKey(GroupKeys.groupNameEditIcon));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(GroupKeys.editGroupNameField), '   ');
      await tester.tap(find.byKey(GroupKeys.editGroupSaveButton));
      await tester.pumpAndSettle();

      // The display-name validator surfaces an inline error; nothing is written
      // and the sheet stays open.
      expect(service.calls, isEmpty);
      expect(find.text("Name can't be empty."), findsOneWidget);
      expect(find.byKey(GroupKeys.editGroupSheet), findsOneWidget);
    });

    testWidgets('failed save in the sheet shows error, sheet stays open', (
      tester,
    ) async {
      final service = await _pumpGroupInfoSection(
        tester,
        onIdentitySave: () async => throw StateError('write failed'),
      );

      await tester.tap(find.byKey(GroupKeys.groupNameEditIcon));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(GroupKeys.editGroupNameField),
        'New Crew',
      );
      await tester.tap(find.byKey(GroupKeys.editGroupSaveButton));
      await tester.pumpAndSettle();

      // The sheet's catch path surfaces the failure SnackBar and does NOT pop.
      expect(service.calls, isEmpty);
      expect(find.textContaining('Failed to update name'), findsOneWidget);
      expect(find.byKey(GroupKeys.editGroupSheet), findsOneWidget);
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

      await _pumpGroupInfoSection(tester);

      await tester.tap(find.byKey(GroupKeys.inviteCodeCopyButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(clipboardText, 'ABC123');
      expect(find.text('Invite code copied'), findsOneWidget);
    });

    testWidgets('non-creator sees no ✎ edit affordance', (tester) async {
      await _pumpGroupInfoSection(tester, isCreator: false);

      // No creator pencil → no way to open the edit sheet.
      expect(find.byKey(GroupKeys.groupNameEditIcon), findsNothing);
      expect(find.byKey(GroupKeys.editGroupSheet), findsNothing);
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

    testWidgets('#411: blocked-remove settle-up snackbar auto-dismisses', (
      tester,
    ) async {
      // On Flutter >=3.41 a SnackBar with an action defaults to persist: true
      // and never times out (snack_bar.dart: persist = persist ?? action != null).
      await tester.pumpWidget(
        _wrapCreatorWithBalances(
          const GroupSettingsScreen(groupId: 'group-1'),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
      await tester.pumpAndSettle();
      expect(
        find.text('Settle up with Bob before removing them.'),
        findsOneWidget,
      );

      // Past the explicit 8s duration the timeout must dismiss it.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(
        find.text('Settle up with Bob before removing them.'),
        findsNothing,
      );
    });

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

    testWidgets(
      'successful member removal calls callable route and writes NO client activity log (#318)',
      (tester) async {
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

        // Routes through the callable with targetUserId (memberId dropped).
        expect(groupService.removeCalls, [
          (groupId: 'group-1', userId: 'uid-member'),
        ]);
        // #318: the server writes the member_left activity entry; the client
        // must NOT log it (double-log + the old log fired even on failure).
        expect(activityService.logCalls, isEmpty);
      },
    );

    testWidgets(
      'unexpected removal failure shows the friendly (translated) message, '
      'never the raw error string, no client activity log (#318/#1160)',
      (tester) async {
        // #1160: a non-FirebaseFunctionsException (here a StateError) hits the
        // outer generic catch. It must be routed through friendlyMessageFor —
        // NOT interpolated raw via e.toString() — so an Arabic user never sees
        // an untranslated English "Bad state: …". Mirrors the leave handler.
        late _RemovingGroupService groupService;
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrapMembersSection(
            prefs: prefs,
            groupServiceBuilder: (ref) => groupService = _RemovingGroupService(
              ref,
              onRemove: ({required groupId, required userId}) {
                throw StateError('write failed');
              },
            ),
            activityService: activityService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
        await tester.pumpAndSettle();

        // friendlyMessageFor classifies a StateError as `unexpected` →
        // l10n.errorUnexpected, slotted into the groupFailedRemoveMember
        // template.
        expect(
          find.text(
            'Failed to remove Bob: Something went wrong. Please try again.',
          ),
          findsOneWidget,
        );
        // The raw Dart error string must never reach the user.
        expect(find.textContaining('Bad state'), findsNothing);
        expect(groupService.removeCalls, [
          (groupId: 'group-1', userId: 'uid-member'),
        ]);
        expect(activityService.logCalls, isEmpty);
      },
    );

    testWidgets(
      '#1144/#1149 lock-contention (aborted) shows the retry-inviting copy, never the raw server string',
      (tester) async {
        // The departure fence throws `aborted` on lock contention with an
        // English-only server message. #1149: this transient race gets its
        // own retry-inviting copy (groupMembershipChangeInProgress) instead
        // of the generic "Something went wrong" — and `failed-precondition`
        // stays reserved for the settle-up snackbar, so this must NOT
        // surface that either.
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrapMembersSection(
            prefs: prefs,
            groupServiceBuilder: (ref) => _RemovingGroupService(
              ref,
              onRemove: ({required groupId, required userId}) {
                throw FirebaseFunctionsException(
                  code: 'aborted',
                  message: 'departure lock held by another operation.',
                );
              },
            ),
            activityService: activityService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Another membership change is happening right now. '
            'Please try again in a moment.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('departure lock'), findsNothing);
        expect(find.textContaining('Failed to remove'), findsNothing);
        expect(find.widgetWithText(SnackBarAction, 'Settle up'), findsNothing);
        expect(activityService.logCalls, isEmpty);
      },
    );

    testWidgets(
      'failed-precondition maps to settle-up snackbar with action routing to settle up (#318)',
      (tester) async {
        late _RemovingGroupService groupService;
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrapMembersSection(
            prefs: prefs,
            groupServiceBuilder: (ref) => groupService = _RemovingGroupService(
              ref,
              onRemove: ({required groupId, required userId}) {
                throw FirebaseFunctionsException(
                  message: 'unsettled',
                  code: 'failed-precondition',
                );
              },
            ),
            activityService: activityService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
        await tester.pumpAndSettle();

        expect(
          find.text('Settle up with Bob before removing them.'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(SnackBarAction, 'Settle up'));
        await tester.pumpAndSettle();

        expect(find.text('SettleUp:group-1'), findsOneWidget);
        expect(groupService.removeCalls, [
          (groupId: 'group-1', userId: 'uid-member'),
        ]);
        expect(activityService.logCalls, isEmpty);
      },
    );

    testWidgets('not-found maps to silent success — no error snackbar (#318)', (
      tester,
    ) async {
      late _RemovingGroupService groupService;
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrapMembersSection(
          prefs: prefs,
          groupServiceBuilder: (ref) => groupService = _RemovingGroupService(
            ref,
            onRemove: ({required groupId, required userId}) {
              throw FirebaseFunctionsException(
                message: 'already gone',
                code: 'not-found',
              );
            },
          ),
          activityService: activityService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to remove'), findsNothing);
      expect(groupService.removeCalls, [
        (groupId: 'group-1', userId: 'uid-member'),
      ]);
      expect(activityService.logCalls, isEmpty);
    });

    testWidgets(
      'generic FirebaseFunctionsException (e.g. internal) reports to Sentry '
      'and shows the friendly (translated) cause, never the raw server string '
      '(#1160)',
      (tester) async {
        // #1160: an FFE whose code is NOT one of the handled trio
        // (not-found / failed-precondition / aborted) falls through to the
        // generic branch — it is captured to Sentry and the user sees the
        // friendly translated cause via friendlyMessageFor, NOT the raw
        // English-only server message. This exercises the Sentry-capture line
        // that the StateError (outer-catch) case does not reach.
        late _RemovingGroupService groupService;
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(
          _wrapMembersSection(
            prefs: prefs,
            groupServiceBuilder: (ref) => groupService = _RemovingGroupService(
              ref,
              onRemove: ({required groupId, required userId}) {
                throw FirebaseFunctionsException(
                  code: 'internal',
                  message: 'INTERNAL: unexpected server fault.',
                );
              },
            ),
            activityService: activityService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-2')));
        await tester.pumpAndSettle();

        // classifyError maps an unknown FFE code to `unexpected` →
        // l10n.errorUnexpected, slotted into the groupFailedRemoveMember
        // template.
        expect(
          find.text(
            'Failed to remove Bob: Something went wrong. Please try again.',
          ),
          findsOneWidget,
        );
        // The raw English-only server string must never reach the user, and
        // this must NOT surface the aborted retry copy nor the settle-up copy.
        expect(find.textContaining('INTERNAL'), findsNothing);
        expect(
          find.textContaining('Another membership change'),
          findsNothing,
        );
        expect(
          find.textContaining('Settle up with Bob before removing them.'),
          findsNothing,
        );
        expect(find.widgetWithText(SnackBarAction, 'Settle up'), findsNothing);
        expect(groupService.removeCalls, [
          (groupId: 'group-1', userId: 'uid-member'),
        ]);
        expect(activityService.logCalls, isEmpty);
      },
    );
  });
}
