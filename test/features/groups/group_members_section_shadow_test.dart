// #278 PR3: in-group add-a-shadow + "Not joined yet" pill + remove a shadow.
//
// The whole GroupService is mocked via a GroupService subclass (the
// _RemovingGroupService precedent in group_settings_screen_test.dart) so the
// addShadowMember + removeMember wrappers are stubbed — no Firebase, no network.
// Connectivity is varied with a timer-free ConnectivityNotifier
// (startPeriodicChecks: false) so pumpAndSettle never hangs.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_members_section.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Stub data
// ---------------------------------------------------------------------------

GroupMember _creator() => GroupMember(
  id: 'mem-creator',
  groupId: 'group-1',
  userId: 'uid-creator',
  displayName: 'Alice',
  role: 'CREATOR',
  joinedAt: DateTime(2026, 1, 1),
);

GroupMember _shadow() => GroupMember(
  id: 'mem-shadow',
  groupId: 'group-1',
  userId: 'shadow-sara',
  displayName: 'Sara',
  role: 'MEMBER',
  isShadow: true,
  joinedAt: DateTime(2026, 1, 2),
);

GroupBalances _zeroBalances() => (
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
        participantId: 'shadow-sara',
        displayName: 'Sara',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.zero,
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.zero},
  eventCount: 0,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-creator': 'Alice', 'shadow-sara': 'Sara'},
  memberRawNames: <String, String>{},
);

GroupBalances _nonZeroShadow() => (
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
        participantId: 'shadow-sara',
        displayName: 'Sara',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.parse('15.000'),
        netBalance: Decimal.parse('-15.000'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('30.000')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-creator': 'Alice', 'shadow-sara': 'Sara'},
  memberRawNames: <String, String>{},
);

// ---------------------------------------------------------------------------
// Mock service — records addShadowMember + removeMember calls. Mirrors
// _RemovingGroupService in group_settings_screen_test.dart.
// ---------------------------------------------------------------------------

/// Per-test recorder, owned by the test (NOT the service). The service is
/// built lazily by `groupServiceProvider` only when first read; paths that
/// never read it (offline gate, local non-zero short-circuit) leave the service
/// unconstructed, so call records live here where the assertions can always
/// reach them.
class _Calls {
  final add = <({String groupId, String displayName})>[];
  final remove = <({String groupId, String userId})>[];
}

class _MockGroupService extends GroupService {
  _MockGroupService(
    Ref ref, {
    required this.calls,
    this.onRemove,
  }) : super.withFirestore(ref, FakeFirebaseFirestore());

  final _Calls calls;

  final Future<void> Function({
    required String groupId,
    required String userId,
  })?
  onRemove;

  @override
  Future<String> addShadowMember({
    required String groupId,
    required String displayName,
  }) async {
    calls.add.add((groupId: groupId, displayName: displayName));
    return 'm-generated';
  }

  @override
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    calls.remove.add((groupId: groupId, userId: userId));
    await onRemove?.call(groupId: groupId, userId: userId);
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _wrap({
  required SharedPreferences prefs,
  required GroupService Function(Ref ref) serviceBuilder,
  required ConnectivityNotifier connectivity,
  required bool isCreator,
  required List<GroupMember> members,
  GroupBalances? balances,
}) {
  final currentUserId = isCreator ? 'uid-creator' : 'shadow-sara';
  final router = GoRouter(
    initialLocation: '/members',
    routes: [
      GoRoute(
        path: '/members',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: GroupMembersSection(
              groupId: 'group-1',
              members: members,
              currentUserId: currentUserId,
              isCurrentUserCreator: isCreator,
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
      currentUserIdProvider.overrideWithValue(currentUserId),
      connectivityProvider.overrideWith((ref) => connectivity),
      groupBalancesProvider(
        'group-1',
      ).overrideWith((ref) => AsyncValue.data(balances ?? _zeroBalances())),
      groupServiceProvider.overrideWith(serviceBuilder),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

ConnectivityNotifier _online() =>
    ConnectivityNotifier(startPeriodicChecks: false);

ConnectivityNotifier _offline() {
  final c = ConnectivityNotifier(startPeriodicChecks: false);
  c.setOffline();
  return c;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Alice',
    });
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('creator sees the Add-person affordance; non-creator does not', (
    tester,
  ) async {
    final calls = _Calls();
    // Creator view.
    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        serviceBuilder: (ref) => _MockGroupService(ref, calls: calls),
        connectivity: _online(),
        isCreator: true,
        members: [_creator(), _shadow()],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(GroupKeys.addPersonAction), findsOneWidget);

    // Non-creator view — affordance absent.
    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        serviceBuilder: (ref) => _MockGroupService(ref, calls: calls),
        connectivity: _online(),
        isCreator: false,
        members: [_creator(), _shadow()],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(GroupKeys.addPersonAction), findsNothing);
  });

  testWidgets('a shadow member tile renders the "Not joined yet" pill', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        serviceBuilder: (ref) => _MockGroupService(ref, calls: calls),
        connectivity: _online(),
        isCreator: true,
        members: [_creator(), _shadow()],
      ),
    );
    await tester.pumpAndSettle();

    // The shadow (Sara) tile has the pill; the creator (Alice) tile does not.
    expect(find.byKey(GroupKeys.shadowBadge('mem-shadow')), findsOneWidget);
    expect(find.byKey(GroupKeys.shadowBadge('mem-creator')), findsNothing);
    expect(find.text('Not joined yet'), findsOneWidget);
  });

  testWidgets(
    'tap Add → enter a name → calls addShadowMember with (groupId, name)',
    (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          serviceBuilder: (ref) => _MockGroupService(ref, calls: calls),
          connectivity: _online(),
          isCreator: true,
          members: [_creator()],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.addPersonAction));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(GroupKeys.addPersonInput), 'Khalid');
      await tester.tap(find.byKey(GroupKeys.addPersonSubmit));
      await tester.pumpAndSettle();

      expect(calls.add, [
        (groupId: 'group-1', displayName: 'Khalid'),
      ]);
    },
  );

  testWidgets(
    'offline: Add affordance disabled / offline hint shown, no callable',
    (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          serviceBuilder: (ref) => _MockGroupService(ref, calls: calls),
          connectivity: _offline(),
          isCreator: true,
          members: [_creator()],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.addPersonAction));
      await tester.pumpAndSettle();

      // Offline hint shown; the submit button is disabled so no call possible.
      expect(find.text('Connect to add names'), findsOneWidget);
      final submit = tester.widget<ElevatedButton>(
        find.byKey(GroupKeys.addPersonSubmit),
      );
      expect(submit.onPressed, isNull);
      expect(calls.add, isEmpty);
    },
  );

  testWidgets(
    'remove on a zero-balance shadow → calls removeMember with shadow userId',
    (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          serviceBuilder: (ref) => _MockGroupService(ref, calls: calls),
          connectivity: _online(),
          isCreator: true,
          members: [_creator(), _shadow()],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-shadow')));
      await tester.pumpAndSettle();

      expect(calls.remove, [
        (groupId: 'group-1', userId: 'shadow-sara'),
      ]);
    },
  );

  testWidgets(
    'remove on a non-zero shadow → settle-up snackbar, no removeMember',
    (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          serviceBuilder: (ref) => _MockGroupService(
            ref,
            calls: calls,
            onRemove: ({required groupId, required userId}) {
              throw FirebaseFunctionsException(
                message: 'unsettled',
                code: 'failed-precondition',
              );
            },
          ),
          connectivity: _online(),
          isCreator: true,
          members: [_creator(), _shadow()],
          balances: _nonZeroShadow(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupKeys.removeMemberButton('mem-shadow')));
      await tester.pumpAndSettle();

      // Local non-zero gate short-circuits before the callable.
      expect(
        find.text('Settle up with Sara before removing them.'),
        findsOneWidget,
      );
      expect(calls.remove, isEmpty);
    },
  );
}
