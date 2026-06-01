import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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
// RED reasons against current code:
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

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    prefs = await SharedPreferences.getInstance();
    registerFallbackValue('');
  });

  // -------------------------------------------------------------------------
  // §8.3 case 1 — service-level: deleteGroup performs NO client Firestore
  // delete (the cascade is server-authoritative, invisible to the fake db).
  // -------------------------------------------------------------------------
  test(
    'case 1: deleteGroup performs NO direct client Firestore delete '
    '(server-authoritative) — FAILS today (client batch-deletes the docs)',
    () async {
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
      when(() => functionsService.deleteGroup(groupId: any(named: 'groupId')))
          .thenAnswer((_) async {});

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
    },
  );

  // -------------------------------------------------------------------------
  // Widget harness for the danger-section error-mapping + fall-through cases.
  // -------------------------------------------------------------------------
  List<Override> buildOverrides({
    required GroupService groupService,
    required Stream<List<Expense>> eventExpenses,
    required Stream<List<Settlement>> eventSettlements,
  }) {
    final expenseService = _MockExpenseService();
    final settlementService = _MockSettlementService();
    when(() => expenseService.watchExpenses('g1', 'e1'))
        .thenAnswer((_) => eventExpenses);
    when(() => settlementService.watchSettlements('g1', 'e1'))
        .thenAnswer((_) => eventSettlements);

    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      groupDetailProvider('g1').overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider('g1')
          .overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider('g1').overrideWith(
        (ref) => Stream.value([
          _event(participantIds: const ['uid-creator', 'uid-member']),
        ]),
      ),
      groupSettlementsProvider('g1')
          .overrideWith((ref) => Stream.value(const <Settlement>[])),
      expenseServiceProvider.overrideWithValue(expenseService),
      settlementServiceProvider.overrideWithValue(settlementService),
      groupServiceProvider.overrideWithValue(groupService),
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

  // -------------------------------------------------------------------------
  // §8.3 case 2 — failed-precondition → groupSettleBeforeDeleting snackbar.
  // -------------------------------------------------------------------------
  testWidgets(
    'case 2: failed-precondition from the callable shows '
    'groupSettleBeforeDeleting',
    (tester) async {
      final groupService = _MockGroupService();
      when(() => groupService.deleteGroup(groupId: any(named: 'groupId')))
          .thenThrow(
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
    },
  );

  // -------------------------------------------------------------------------
  // §8.3 case 3 — generic code (internal) → groupFailedDelete.
  // -------------------------------------------------------------------------
  testWidgets(
    "case 3: generic 'internal' error shows groupFailedDelete",
    (tester) async {
      final groupService = _MockGroupService();
      when(() => groupService.deleteGroup(groupId: any(named: 'groupId')))
          .thenThrow(
        FirebaseFunctionsException(message: 'boom', code: 'internal'),
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

      await confirmDelete(tester);

      verify(() => groupService.deleteGroup(groupId: 'g1')).called(1);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // groupFailedDelete is parameterized with the error string; match the
      // stable prefix so the exact error rendering does not over-constrain.
      expect(
        find.textContaining(l10n.groupFailedDelete('').split('{').first.trim()),
        findsWidgets,
      );
    },
  );

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
      when(() => groupService.deleteGroup(groupId: any(named: 'groupId')))
          .thenAnswer((_) async {});

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
