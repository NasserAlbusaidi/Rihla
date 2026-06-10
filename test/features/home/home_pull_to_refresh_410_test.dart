import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// #410 — pull-to-refresh must re-run the per-group one-shot balance reads.
//
// A peer device's expense write in an EXISTING event triggers none of the
// one-shot family's re-run conditions (no event/member/group-settlement
// stream emission, no local ledgerRevision bump). The only in-app recovery is
// pull-to-refresh — so onRefresh must invalidate groupBalancesOnceProvider
// itself, not just the cross-group aggregate that reads its (pinned, cached)
// instances.
//
// This test uses the REAL provider chain (groupBalancesOnceProvider →
// homeGroupBalance facade fallback, #366) over seed-mutable fake services, and drives
// the real RefreshIndicator in HomeScreen — mutating the seed mid-test plays
// the part of the other device.
// ---------------------------------------------------------------------------

class _SeededExpenseService extends ExpenseService {
  _SeededExpenseService(this.seed) : super.withFirestore(FakeFirebaseFirestore());
  final Map<String, List<Expense>> seed;

  @override
  Future<List<Expense>> getExpenses(String groupId, String eventId) async =>
      List.unmodifiable(seed[eventId] ?? const <Expense>[]);

  @override
  Stream<List<Expense>> watchExpenses(String groupId, String eventId) =>
      Stream.value(seed[eventId] ?? const <Expense>[]);
}

class _SeededSettlementService extends SettlementService {
  _SeededSettlementService() : super.withFirestore(FakeFirebaseFirestore());

  @override
  Future<List<Settlement>> getSettlements(String groupId, String eventId) async =>
      const <Settlement>[];

  @override
  Stream<List<Settlement>> watchSettlements(String groupId, String eventId) =>
      Stream.value(const <Settlement>[]);
}

const _gid = 'g1';
const _eid = 'e1';

Group _makeGroup() => Group(
      id: _gid,
      name: 'Desert Crew',
      inviteCode: 'AAAAAA',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

Event _makeEvent() => Event(
      id: _eid,
      name: 'Muscat Trip',
      type: EventType.trip,
      groupId: _gid,
      createdBy: 'uid-a',
      participantIds: const ['uid-a', 'uid-b'],
      participantNames: const {'uid-a': 'A', 'uid-b': 'B'},
      modules: const EventModules(),
      createdAt: DateTime(2026, 1, 1),
    );

GroupMember _makeMember(String uid) => GroupMember(
      id: 'member-$uid',
      groupId: _gid,
      userId: uid,
      displayName: uid == 'uid-a' ? 'A' : 'B',
      role: 'MEMBER',
      joinedAt: DateTime(2026, 1, 1),
    );

Expense _makeExpense(String id, String payer, int amount) => Expense(
      id: id,
      tripId: _eid,
      payerParticipantId: payer,
      amount: Decimal.fromInt(amount),
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _buildApp({
  required SharedPreferences prefs,
  required _SeededExpenseService expFake,
  required _SeededSettlementService setFake,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      linkedEmailProvider.overrideWithValue('secured@example.com'),
      currentUserIdProvider.overrideWith((_) => 'uid-a'),
      expenseServiceProvider.overrideWithValue(expFake),
      settlementServiceProvider.overrideWithValue(setFake),
      userGroupsProvider.overrideWith((_) => Stream.value([_makeGroup()])),
      groupEventsProvider(_gid).overrideWith((_) => Stream.value([_makeEvent()])),
      groupMembersProvider(_gid).overrideWith(
        (_) => Stream.value([_makeMember('uid-a'), _makeMember('uid-b')]),
      ),
      groupSettlementsProvider(_gid)
          .overrideWith((_) => Stream.value(const <Settlement>[])),
      crossGroupActivityProvider
          .overrideWithValue(const AsyncValue.data([])),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  testWidgets(
    'pull-to-refresh re-runs the one-shot per-group reads, so a peer '
    'device\'s expense shows up without a cold restart (#410)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // uid-a paid 10, equal 2-way split → uid-a is owed 5.000.
      final expFake = _SeededExpenseService({
        _eid: [_makeExpense('x1', 'uid-a', 10)],
      });
      final setFake = _SeededSettlementService();

      await tester.pumpWidget(
        _buildApp(prefs: prefs, expFake: expFake, setFake: setFake),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('5.000', findRichText: true),
        findsWidgets,
        reason: 'sanity: the hero/group rows show the pre-change net',
      );

      // Peer device (uid-b) adds an offsetting expense in the EXISTING event:
      // no list-stream emission, no local ledgerRevision bump on this device.
      expFake.seed[_eid] = [
        _makeExpense('x1', 'uid-a', 10),
        _makeExpense('x2', 'uid-b', 10),
      ];

      // Pull-to-refresh on the home dashboard.
      await tester.fling(
        find.byType(CustomScrollView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('5.000', findRichText: true),
        findsNothing,
        reason: 'pull-to-refresh must re-fetch the per-event one-shot reads — '
            'a stale +5.000 here is exactly the #410 bug',
      );
    },
  );
}
