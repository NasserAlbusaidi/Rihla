import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/groups/widgets/group_danger_section.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// RED regression for cluster `server-deletegroup-callable` (#190), spec §8.3.
//
// POST-FIX contract (server-authoritative deletion):
//   1. `GroupService.deleteGroup` routes deletion through the `deleteGroup`
//      Cloud callable and performs NO direct Firestore writes (the client
//      delete path is locked at the rules layer, `allow delete: if false;`).
//   2. The danger-section handler maps `FirebaseFunctionsException`:
//        failed-precondition → `groupSettleBeforeDeleting` snackbar;
//        any other code       → `groupFailedDelete`.
//   3. HARD REQ #8 — when `groupBalancesProvider` is null/loading, the handler
//      MUST still invoke the callable (the SERVER is the sole authority; the
//      local balance pre-check is UX-only). This REVERSES the pre-#190
//      fail-closed-on-null guard.
//
// Original RED reasons before #190 was implemented:
//   - case 1: `GroupService.deleteGroup` (group_provider.dart:352-371) builds a
//     WriteBatch that deletes member docs + invite code + group doc directly →
//     the injected fake's group doc is GONE → ASSERTION fail.
//   - cases 2/3: the current client delete is a Firestore batch — it never
//     throws a `FirebaseFunctionsException`, so the error→snackbar mapping the
//     spec mandates is absent; with the post-fix callable wiring + a throwing
//     fake service the mapping must hold.
//   - case 4: the current `_executeDelete` (group_danger_section.dart:259-273)
//     short-circuits ONLY on a loaded outstanding balance and falls through to
//     invoke the service when balances are null. HARD REQ #8 pins that the
//     callable IS invoked on the null path. NOTE: this directly CONTRADICTS the
//     pre-#190 cluster-#104 guard in `group_destructive_guard_test.dart`
//     ("delete is BLOCKED when balances null"); #190 HARD REQ #8 supersedes it.

class _MockGroupService extends Mock implements GroupService {}

class _MockFunctionsService extends Mock implements FirebaseFunctionsService {}

class _MockExpenseService extends Mock implements ExpenseService {}

class _MockSettlementService extends Mock implements SettlementService {}

class _RecordingGroupActivityService extends GroupActivityService {
  _RecordingGroupActivityService()
    : super.withFirestore(FakeFirebaseFirestore());

  final calls =
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
    calls.add((
      groupId: groupId,
      type: type,
      actorId: actorId,
      actorName: actorName,
      description: description,
      metadata: metadata,
    ));
  }
}

final _testGroup = Group(
  id: 'g1',
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
    groupId: 'g1',
    userId: 'uid-creator',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'mem-2',
    groupId: 'g1',
    userId: 'uid-member',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 2),
  ),
];

final _outstandingBalances = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-creator',
        displayName: 'Alice',
        totalPaid: Decimal.fromInt(30),
        totalOwed: Decimal.fromInt(15),
        netBalance: Decimal.fromInt(15),
      ),
      UserBalance(
        participantId: 'uid-member',
        displayName: 'Bob',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.fromInt(15),
        netBalance: Decimal.fromInt(-15),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.fromInt(30)},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
  memberRawNames: <String, String>{},
);

Event _event({required List<String> participantIds}) => Event(
  id: 'e1',
  name: 'Event e1',
  type: EventType.trip,
  groupId: 'g1',
  createdBy: 'uid-creator',
  participantIds: participantIds,
  participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
  modules: const EventModules(),
  createdAt: DateTime(2026, 1, 1),
);

Expense _expense() => Expense(
  id: 'x1',
  tripId: 'e1',
  payerParticipantId: 'uid-creator',
  amount: Decimal.fromInt(30),
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 1, 2),
);

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
    registerFallbackValue('');
  });

  // -------------------------------------------------------------------------
  // §8.3 case 1 — service-level: deleteGroup performs NO client Firestore
  // delete (the cascade is server-authoritative, invisible to the fake db).
  // -------------------------------------------------------------------------
  test('case 1: deleteGroup performs NO direct client Firestore delete '
      '(server-authoritative)', () async {
    final fakeDb = FakeFirebaseFirestore();
    await fakeDb.doc('groups/g').set({
      'id': 'g',
      'name': 'Desert Crew',
      'inviteCode': 'ABC123',
      'createdBy': 'owner',
      'memberIds': ['owner', 'member'],
      'currency': 'OMR',
    });
    await fakeDb.doc('groups/g/members/owner').set({
      'id': 'owner',
      'userId': 'owner',
      'displayName': 'Owner',
      'role': 'CREATOR',
      'isShadow': false,
    });
    await fakeDb.doc('inviteCodes/ABC123').set({'groupId': 'g'});

    // The real GroupService.deleteGroup routes through the deleteGroup
    // callable (server-authoritative). Inject a fake FirebaseFunctionsService
    // so the call resolves without Firebase and we can assert it was invoked
    // (spec §8.3 case 1) — the client must perform NO direct Firestore writes.
    final functionsService = _MockFunctionsService();
    when(
      () => functionsService.deleteGroup(groupId: any(named: 'groupId')),
    ).thenAnswer((_) async {});

    final container = ProviderContainer(
      overrides: [
        firebaseFunctionsServiceProvider.overrideWithValue(functionsService),
        groupServiceProvider.overrideWith(
          (ref) =>
              GroupService.withFirestore(ref, fakeDb, currentUserId: 'owner'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(groupServiceProvider).deleteGroup(groupId: 'g');

    verify(() => functionsService.deleteGroup(groupId: 'g')).called(1);

    expect(
      (await fakeDb.doc('groups/g').get()).exists,
      isTrue,
      reason:
          'Client deleteGroup must not directly delete the group doc — '
          'deletion is server-authoritative via the deleteGroup callable '
          '(#190 §4.2).',
    );
    expect(
      (await fakeDb.doc('groups/g/members/owner').get()).exists,
      isTrue,
      reason: 'Client must not directly delete member docs (#190).',
    );
    expect(
      (await fakeDb.doc('inviteCodes/ABC123').get()).exists,
      isTrue,
      reason: 'Client must not directly delete the invite code (#190).',
    );
  });

  // -------------------------------------------------------------------------
  // Widget harness for the danger-section error-mapping + fall-through cases.
  // -------------------------------------------------------------------------
  List<Override> buildOverrides({
    required GroupService groupService,
    required Stream<List<Expense>> eventExpenses,
    required Stream<List<Settlement>> eventSettlements,
    GroupActivityService? groupActivityService,
    GroupBalances? groupBalances,
  }) {
    final expenseService = _MockExpenseService();
    final settlementService = _MockSettlementService();
    when(
      () => expenseService.watchExpenses('g1', 'e1'),
    ).thenAnswer((_) => eventExpenses);
    when(
      () => settlementService.watchSettlements('g1', 'e1'),
    ).thenAnswer((_) => eventSettlements);

    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider('g1').overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        'g1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider('g1').overrideWith(
        (ref) => Stream.value([
          _event(participantIds: const ['uid-creator', 'uid-member']),
        ]),
      ),
      groupSettlementsProvider(
        'g1',
      ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      if (groupBalances != null)
        groupBalancesProvider(
          'g1',
        ).overrideWith((ref) => AsyncValue.data(groupBalances)),
      expenseServiceProvider.overrideWithValue(expenseService),
      settlementServiceProvider.overrideWithValue(settlementService),
      groupServiceProvider.overrideWithValue(groupService),
      if (groupActivityService != null)
        groupActivityServiceProvider.overrideWithValue(groupActivityService),
    ];
  }

  Widget buildApp(List<Override> overrides) {
    final router = GoRouter(
      initialLocation: '/host',
      routes: [
        GoRoute(
          path: '/host',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(
              child: GroupDangerSection(
                groupId: 'g1',
                isCreator: true,
                groupName: 'Adventure Crew',
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/group/:gid/settle-up',
          builder: (context, state) => const Scaffold(body: Text('SettleUp')),
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(GroupKeys.deleteGroupTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.deleteGroupTile));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(GroupKeys.deleteGroupDialog),
        matching: find.byType(TextField),
      ),
      _testGroup.name,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.deleteGroupConfirmButton));
    await tester.pumpAndSettle();
  }

  Future<void> confirmLeave(WidgetTester tester) async {
    await tester.tap(find.byKey(GroupKeys.leaveGroupTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.leaveGroupConfirmButton));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'leave success calls the callable-backed service + goes home, and NO '
    'longer logs activity client-side (server writes member_left now, #290)',
    (tester) async {
    final groupService = _MockGroupService();
    final activityService = _RecordingGroupActivityService();
    when(
      () => groupService.leaveGroup(groupId: any(named: 'groupId')),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      buildApp(
        buildOverrides(
          groupService: groupService,
          groupActivityService: activityService,
          eventExpenses: Stream.value(const <Expense>[]),
          eventSettlements: Stream.value(const <Settlement>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await confirmLeave(tester);

    verify(() => groupService.leaveGroup(groupId: 'g1')).called(1);
    expect(find.text('Home'), findsOneWidget);
    // The member_left activity is written server-side by the leaveGroup
    // callable (the client can't — post-leave it is no longer a member, #290).
    expect(activityService.calls, isEmpty);
  });

  testWidgets('leave failure shows groupFailedLeave snackbar', (tester) async {
    final groupService = _MockGroupService();
    when(
      () => groupService.leaveGroup(groupId: any(named: 'groupId')),
    ).thenThrow(StateError('boom'));

    await tester.pumpWidget(
      buildApp(
        buildOverrides(
          groupService: groupService,
          eventExpenses: Stream.value(const <Expense>[]),
          eventSettlements: Stream.value(const <Settlement>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await confirmLeave(tester);

    verify(() => groupService.leaveGroup(groupId: 'g1')).called(1);
    // #356: a raw error is translated to a friendly cause, never shown verbatim.
    expect(
      find.text('Failed to leave group: Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state: boom'), findsNothing);
  });

  testWidgets(
    '#1149 leave aborted (departure-lock contention) shows retry copy, '
    'no settle action, no navigation',
    (tester) async {
      final groupService = _MockGroupService();
      when(() => groupService.leaveGroup(groupId: any(named: 'groupId'))).thenThrow(
        FirebaseFunctionsException(
          message: 'departure lock held by another operation.',
          code: 'aborted',
        ),
      );

      await tester.pumpWidget(
        buildApp(
          buildOverrides(
            groupService: groupService,
            eventExpenses: Stream.value(const <Expense>[]),
            eventSettlements: Stream.value(const <Settlement>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmLeave(tester);

      verify(() => groupService.leaveGroup(groupId: 'g1')).called(1);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.groupMembershipChangeInProgress), findsOneWidget);
      expect(find.textContaining('Failed to leave group'), findsNothing);
      expect(find.textContaining('departure lock'), findsNothing);
      expect(find.widgetWithText(SnackBarAction, 'Settle up'), findsNothing);
      expect(find.text('Home'), findsNothing);
    },
  );

  // The server `leaveGroup` callable is the sole balance authority (#290); the
  // client UX short-circuit is uid-gated (FirebaseConfig.currentUser, not set in
  // this harness) so the balance gate is exercised server-side in
  // functions/test/callables/leaveGroup.test.ts. These cases pin the client's
  // FirebaseFunctionsException → UX mapping.
  testWidgets(
    'leave failed-precondition shows the settle-before-leaving snackbar (#290)',
    (tester) async {
      final groupService = _MockGroupService();
      when(() => groupService.leaveGroup(groupId: any(named: 'groupId'))).thenThrow(
        FirebaseFunctionsException(
          message: 'unsettled',
          code: 'failed-precondition',
        ),
      );

      await tester.pumpWidget(
        buildApp(
          buildOverrides(
            groupService: groupService,
            eventExpenses: Stream.value(const <Expense>[]),
            eventSettlements: Stream.value(const <Settlement>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmLeave(tester);

      verify(() => groupService.leaveGroup(groupId: 'g1')).called(1);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.groupSettleBeforeLeaving), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    },
  );

  testWidgets(
    '#411: blocked-leave settle-up snackbar auto-dismisses',
    (tester) async {
      // On Flutter >=3.41 a SnackBar with an action defaults to persist: true
      // and never times out (snack_bar.dart: persist = persist ?? action != null).
      final groupService = _MockGroupService();
      when(() => groupService.leaveGroup(groupId: any(named: 'groupId'))).thenThrow(
        FirebaseFunctionsException(
          message: 'unsettled',
          code: 'failed-precondition',
        ),
      );

      await tester.pumpWidget(
        buildApp(
          buildOverrides(
            groupService: groupService,
            eventExpenses: Stream.value(const <Expense>[]),
            eventSettlements: Stream.value(const <Settlement>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmLeave(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.groupSettleBeforeLeaving), findsOneWidget);

      // Past the explicit 8s duration the timeout must dismiss it.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.text(l10n.groupSettleBeforeLeaving), findsNothing);
    },
  );

  testWidgets('not-found from leave callable is treated as success (goes home)', (
    tester,
  ) async {
    final groupService = _MockGroupService();
    when(
      () => groupService.leaveGroup(groupId: any(named: 'groupId')),
    ).thenThrow(FirebaseFunctionsException(message: 'gone', code: 'not-found'));

    await tester.pumpWidget(
      buildApp(
        buildOverrides(
          groupService: groupService,
          eventExpenses: Stream.value(const <Expense>[]),
          eventSettlements: Stream.value(const <Settlement>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await confirmLeave(tester);

    verify(() => groupService.leaveGroup(groupId: 'g1')).called(1);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'loaded outstanding balances block local delete before callable',
    (tester) async {
      final groupService = _MockGroupService();

      await tester.pumpWidget(
        buildApp(
          buildOverrides(
            groupService: groupService,
            groupBalances: _outstandingBalances,
            eventExpenses: Stream.value([_expense()]),
            eventSettlements: Stream.value(const <Settlement>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmDelete(tester);

      verifyNever(
        () => groupService.deleteGroup(groupId: any(named: 'groupId')),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.groupSettleBeforeDeleting), findsOneWidget);
    },
  );

  // #382 PR-1: "deletable" = every member zero in EVERY currency bucket.
  testWidgets(
    'two buckets BOTH settled allow delete (false-block regression, #382 PR-1)',
    (tester) async {
      // The dangerous failure direction: a wrong-restrictive gate has NO
      // server fallback (early return) — a group settled in both of two
      // currency buckets must reach the callable.
      UserBalance zero(String id, String name) => UserBalance(
        participantId: id,
        displayName: name,
        totalPaid: Decimal.fromInt(10),
        totalOwed: Decimal.fromInt(10),
        netBalance: Decimal.zero,
      );
      final settledTwoBuckets = (
        balances: <String, List<UserBalance>>{
          'OMR': [zero('uid-creator', 'Alice'), zero('uid-member', 'Bob')],
          'AED': [zero('uid-creator', 'Alice'), zero('uid-member', 'Bob')],
        },
        totalSpent: <String, Decimal>{
          'OMR': Decimal.fromInt(20),
          'AED': Decimal.fromInt(20),
        },
        eventCount: 1,
        perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
        memberNames: <String, String>{
          'uid-creator': 'Alice',
          'uid-member': 'Bob',
        },
        memberRawNames: <String, String>{},
      );

      final groupService = _MockGroupService();
      when(
        () => groupService.deleteGroup(groupId: any(named: 'groupId')),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        buildApp(
          buildOverrides(
            groupService: groupService,
            groupBalances: settledTwoBuckets,
            eventExpenses: Stream.value([_expense()]),
            eventSettlements: Stream.value(const <Settlement>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmDelete(tester);

      verify(() => groupService.deleteGroup(groupId: 'g1')).called(1);
    },
  );

  testWidgets(
    'a nonzero FOREIGN-currency bucket blocks delete even when the group-'
    'currency bucket is settled (#382 PR-1)',
    (tester) async {
      UserBalance bal(String id, String name, int net) => UserBalance(
        participantId: id,
        displayName: name,
        totalPaid: net > 0 ? Decimal.fromInt(net) : Decimal.zero,
        totalOwed: net < 0 ? Decimal.fromInt(-net) : Decimal.zero,
        netBalance: Decimal.fromInt(net),
      );
      final mixedOutstanding = (
        balances: <String, List<UserBalance>>{
          'OMR': [bal('uid-creator', 'Alice', 0), bal('uid-member', 'Bob', 0)],
          'AED': [bal('uid-creator', 'Alice', 5), bal('uid-member', 'Bob', -5)],
        },
        totalSpent: <String, Decimal>{'OMR': Decimal.zero, 'AED': Decimal.fromInt(5)},
        eventCount: 1,
        perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
        memberNames: <String, String>{
          'uid-creator': 'Alice',
          'uid-member': 'Bob',
        },
        memberRawNames: <String, String>{},
      );

      final groupService = _MockGroupService();

      await tester.pumpWidget(
        buildApp(
          buildOverrides(
            groupService: groupService,
            groupBalances: mixedOutstanding,
            eventExpenses: Stream.value([_expense()]),
            eventSettlements: Stream.value(const <Settlement>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmDelete(tester);

      verifyNever(
        () => groupService.deleteGroup(groupId: any(named: 'groupId')),
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.groupSettleBeforeDeleting), findsOneWidget);
    },
  );

  testWidgets('not-found from delete callable is treated as success', (
    tester,
  ) async {
    final groupService = _MockGroupService();
    when(
      () => groupService.deleteGroup(groupId: any(named: 'groupId')),
    ).thenThrow(FirebaseFunctionsException(message: 'gone', code: 'not-found'));

    await tester.pumpWidget(
      buildApp(
        buildOverrides(
          groupService: groupService,
          eventExpenses: Stream.value(const <Expense>[]),
          eventSettlements: Stream.value(const <Settlement>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await confirmDelete(tester);

    verify(() => groupService.deleteGroup(groupId: 'g1')).called(1);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('plain delete exception shows groupFailedDelete snackbar', (
    tester,
  ) async {
    final groupService = _MockGroupService();
    when(
      () => groupService.deleteGroup(groupId: any(named: 'groupId')),
    ).thenThrow(StateError('boom'));

    await tester.pumpWidget(
      buildApp(
        buildOverrides(
          groupService: groupService,
          eventExpenses: Stream.value(const <Expense>[]),
          eventSettlements: Stream.value(const <Settlement>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await confirmDelete(tester);

    verify(() => groupService.deleteGroup(groupId: 'g1')).called(1);
    // #356: a raw error is translated to a friendly cause, never shown verbatim.
    expect(
      find.text('Failed to delete group: Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state: boom'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // §8.3 case 2 — failed-precondition → groupSettleBeforeDeleting snackbar.
  // -------------------------------------------------------------------------
  testWidgets('case 2: failed-precondition from the callable shows '
      'groupSettleBeforeDeleting', (tester) async {
    final groupService = _MockGroupService();
    when(
      () => groupService.deleteGroup(groupId: any(named: 'groupId')),
    ).thenThrow(
      FirebaseFunctionsException(
        message: 'unsettled',
        code: 'failed-precondition',
      ),
    );

    // Balances all-zero so the UX pre-check does not short-circuit and the
    // callable is reached (and throws failed-precondition, server-side gate).
    await tester.pumpWidget(
      buildApp(
        buildOverrides(
          groupService: groupService,
          eventExpenses: Stream.value(const <Expense>[]),
          eventSettlements: Stream.value(const <Settlement>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await confirmDelete(tester);

    verify(() => groupService.deleteGroup(groupId: 'g1')).called(1);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.groupSettleBeforeDeleting), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // §8.3 case 3 — generic code (internal) → groupFailedDelete.
  // -------------------------------------------------------------------------
  testWidgets("case 3: generic 'internal' error shows groupFailedDelete", (
    tester,
  ) async {
    final groupService = _MockGroupService();
    when(
      () => groupService.deleteGroup(groupId: any(named: 'groupId')),
    ).thenThrow(FirebaseFunctionsException(message: 'boom', code: 'internal'));

    await tester.pumpWidget(
      buildApp(
        buildOverrides(
          groupService: groupService,
          eventExpenses: Stream.value(const <Expense>[]),
          eventSettlements: Stream.value(const <Settlement>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await confirmDelete(tester);

    verify(() => groupService.deleteGroup(groupId: 'g1')).called(1);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // groupFailedDelete is parameterized with the error string; match the
    // stable prefix so the exact error rendering does not over-constrain.
    expect(
      find.textContaining(l10n.groupFailedDelete('').split('{').first.trim()),
      findsWidgets,
    );
  });

  // -------------------------------------------------------------------------
  // §8.3 case 4 — HARD REQ #8: null/loading balances must NOT skip the call.
  // (Contradicts the pre-#190 cluster-#104 fail-closed-on-null guard; #190
  // supersedes — the server is the sole authority.)
  // -------------------------------------------------------------------------
  testWidgets(
    'case 4: null-balance fall-through still invokes the callable '
    '(HARD REQ #8) — FAILS on a client that skips the call when balances null',
    (tester) async {
      final groupService = _MockGroupService();
      when(
        () => groupService.deleteGroup(groupId: any(named: 'groupId')),
      ).thenAnswer((_) async {});

      // Leaf streams never emit => groupBalancesProvider stays AsyncLoading =>
      // valueOrNull == null (the cold/loading path).
      await tester.pumpWidget(
        buildApp(
          buildOverrides(
            groupService: groupService,
            eventExpenses: StreamController<List<Expense>>().stream,
            eventSettlements: StreamController<List<Settlement>>().stream,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await confirmDelete(tester);

      verify(() => groupService.deleteGroup(groupId: 'g1')).called(1);
    },
  );
}
