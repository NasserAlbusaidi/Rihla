import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

const _groupId = 'grp-1';

Group _group({List<String> memberIds = const ['uid-alice', 'uid-bob']}) => Group(
      id: _groupId,
      name: 'Test Crew',
      inviteCode: 'TST123',
      createdBy: 'uid-alice',
      memberIds: memberIds,
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

Event _event(String id, String name, EventType type) => Event(
      id: id,
      name: name,
      type: type,
      groupId: _groupId,
      createdBy: 'uid-alice',
      participantIds: const ['uid-alice', 'uid-bob'],
      participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
      modules: const EventModules(),
      startDate: DateTime(2026, 3, 15),
      createdAt: DateTime(2026, 3, 10),
    );

final _event1 = _event('event-1', 'Camping Weekend', EventType.camping);
final _event2 = _event('event-2', 'Road Trip', EventType.trip);

UserBalance _bal(String id, String name, String net) => UserBalance(
      participantId: id,
      displayName: name,
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.parse(net),
    );

/// Bob owes Alice 8.000 OMR split 4+4 across two events → a TWO-leg decompose,
/// no residual.
GroupBalances _balancesTwoEvents() => (
      balances: <String, List<UserBalance>>{
        'OMR': [
          _bal('uid-alice', 'Alice', '8.000'),
          _bal('uid-bob', 'Bob', '-8.000'),
        ],
      },
      totalSpent: <String, Decimal>{'OMR': Decimal.parse('16.000')},
      eventCount: 2,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
        'uid-alice': {
          'event-1': {'OMR': Decimal.parse('4.000')},
          'event-2': {'OMR': Decimal.parse('4.000')},
        },
        'uid-bob': {
          'event-1': {'OMR': Decimal.parse('-4.000')},
          'event-2': {'OMR': Decimal.parse('-4.000')},
        },
      },
      memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
      memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    );

/// Bob owes Alice 10.000: 3 attributable in each of two events + a 4.000
/// cross-event residual → a THREE-doc batch (2 event legs + 1 residual).
GroupBalances _balancesTwoEventsWithResidual() => (
      balances: <String, List<UserBalance>>{
        'OMR': [
          _bal('uid-alice', 'Alice', '10.000'),
          _bal('uid-bob', 'Bob', '-10.000'),
        ],
      },
      totalSpent: <String, Decimal>{'OMR': Decimal.parse('20.000')},
      eventCount: 2,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
        'uid-alice': {
          'event-1': {'OMR': Decimal.parse('3.000')},
          'event-2': {'OMR': Decimal.parse('3.000')},
        },
        'uid-bob': {
          'event-1': {'OMR': Decimal.parse('-3.000')},
          'event-2': {'OMR': Decimal.parse('-3.000')},
        },
      },
      memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
      memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    );

/// Bob owes Alice across TEN events (1.000 each) → 10 legs, one over the
/// [kMaxDecomposeLegsAtomic] cap, so the screen routes to a single group write.
GroupBalances _balancesTenEvents() {
  final alice = <String, Map<String, Decimal>>{};
  final bob = <String, Map<String, Decimal>>{};
  for (var i = 1; i <= 10; i++) {
    alice['event-$i'] = {'OMR': Decimal.parse('1.000')};
    bob['event-$i'] = {'OMR': Decimal.parse('-1.000')};
  }
  return (
    balances: <String, List<UserBalance>>{
      'OMR': [
        _bal('uid-alice', 'Alice', '10.000'),
        _bal('uid-bob', 'Bob', '-10.000'),
      ],
    },
    totalSpent: <String, Decimal>{'OMR': Decimal.parse('20.000')},
    eventCount: 10,
    perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
      'uid-alice': alice,
      'uid-bob': bob,
    },
    memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  );
}

/// Bob owes Alice across [n] events (1.000 each) → [n] legs, no residual.
GroupBalances _balancesNEvents(int n) {
  final alice = <String, Map<String, Decimal>>{};
  final bob = <String, Map<String, Decimal>>{};
  for (var i = 1; i <= n; i++) {
    alice['event-$i'] = {'OMR': Decimal.parse('1.000')};
    bob['event-$i'] = {'OMR': Decimal.parse('-1.000')};
  }
  return (
    balances: <String, List<UserBalance>>{
      'OMR': [
        _bal('uid-alice', 'Alice', '$n.000'),
        _bal('uid-bob', 'Bob', '-$n.000'),
      ],
    },
    totalSpent: <String, Decimal>{'OMR': Decimal.parse('${2 * n}.000')},
    eventCount: n,
    perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
      'uid-alice': alice,
      'uid-bob': bob,
    },
    memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  );
}

/// Hand-rolled spy WriteBatch injected via `batchFactoryOverride`: counts
/// set()/commit() and returns a caller-supplied commit future so a test can
/// model a rejected (Future.error) or never-acking (offline) commit. `set` is a
/// no-op so nothing lands in the fake regardless of whether commit succeeds.
class _StubWriteBatch implements WriteBatch {
  // Build the commit future lazily so a rejected future isn't created (and
  // flagged unhandled) until commit() is called and the screen synchronously
  // attaches its handler via awaitServerAck.
  _StubWriteBatch(this._commitFactory);
  final Future<void> Function() _commitFactory;
  int setCount = 0;
  int commitCount = 0;
  // #1140: capture (docId, data) for each staged write so a test can assert the
  // co-batched activity leg's ref/data even though `set` is a no-op (nothing
  // lands in the fake).
  final staged = <({String id, Object? data})>[];

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    setCount++;
    staged.add((id: document.id, data: data));
  }

  @override
  Future<void> commit() {
    commitCount++;
    return _commitFactory();
  }

  @override
  void delete(DocumentReference<Object?> document) {}

  @override
  void update(DocumentReference<Object?> document, Map<Object, Object?> data) {}
}

class _RecordingGroupActivityService extends GroupActivityService {
  _RecordingGroupActivityService()
      : super.withFirestore(FakeFirebaseFirestore());

  final logCalls = <({String type, Map<String, dynamic>? metadata})>[];

  @override
  void logGroupEvent({
    required String groupId,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata,
  }) {
    logCalls.add((type: type, metadata: metadata));
  }
}

/// Total settlement docs anywhere for the group: both event subcollections
/// (used by the tests) + the group-level residual collection.
Future<int> _settlementDocCount(FakeFirebaseFirestore fake) async {
  var count = 0;
  for (final eventId in const ['event-1', 'event-2']) {
    final snap = await fake
        .collection('groups')
        .doc(_groupId)
        .collection('events')
        .doc(eventId)
        .collection('settlements')
        .get();
    count += snap.docs.length;
  }
  final groupSnap = await fake
      .collection('groups')
      .doc(_groupId)
      .collection('settlements')
      .get();
  count += groupSnap.docs.length;
  return count;
}

Widget _wrap({
  required GroupBalances balances,
  required List<Event> events,
  required Group group,
  required List<Override> overrides,
  ConnectivityNotifier? connectivity,
  String currentUid = 'uid-bob',
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(group)),
      groupBalancesProvider(_groupId)
          .overrideWith((_) => AsyncValue.data(balances)),
      groupSettlementsProvider(_groupId)
          .overrideWith((_) => Stream.value(const <Settlement>[])),
      groupEventsProvider(_groupId).overrideWith((_) => Stream.value(events)),
      currentUserIdProvider.overrideWithValue(currentUid),
      if (connectivity != null)
        connectivityProvider.overrideWith((_) => connectivity),
      ...overrides,
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupSettleUpScreen(groupId: _groupId),
      ),
    ),
  );
}

Future<void> _recordFullAmount(WidgetTester tester) async {
  await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a rejected leg of a decomposed settle-up persists NOTHING (atomic)',
    (tester) async {
      // Post-fix twin of the RED repro (RED-evidence-929.txt): the single
      // WriteBatch commit is rejected, so the whole logical settle-up fails —
      // no doc, no ledger bump, no activity log, a denied error snackbar.
      final fake = FakeFirebaseFirestore();
      final rejectingBatch = _StubWriteBatch(
        () => Future<void>.error(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Simulated rules rejection of the batch commit.',
          ),
        ),
      );
      final groupService = GroupSettlementService.withFirestore(fake)
        ..batchFactoryOverride = () => rejectingBatch;
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEvents(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false), // online
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      // All-or-nothing: the batch was rejected → NOTHING persisted, no bump,
      // no activity, and the denied error copy (not the success copy) shows.
      expect(await _settlementDocCount(fake), 0);
      expect(container.read(ledgerRevisionProvider), 0);
      // #1140: the activity is no longer a separate logGroupEvent call — it was
      // staged INTO the rejected batch (2 event legs + 1 gstl_ activity = 3),
      // so it shares the rejection and never persists. Non-vacuous proof:
      expect(activityService.logCalls, isEmpty);
      expect(rejectingBatch.setCount, 3);
      expect(
        rejectingBatch.staged.where((s) => s.id.startsWith('gstl_')),
        hasLength(1),
      );
      expect(
        find.text(
          "This settlement wasn't allowed. Please check the details and "
          'try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Settlement recorded.'), findsNothing);
    },
  );

  testWidgets(
    'offline: the decomposed batch queues as ONE unit — 3 sets + 1 commit, '
    'one ledger bump, syncing, queued snackbar, activity logged once',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      // Offline: the commit future never acks until reconnect (#412).
      final queuedBatch = _StubWriteBatch(() => Completer<void>().future);
      final groupService = GroupSettlementService.withFirestore(fake)
        ..batchFactoryOverride = () => queuedBatch;
      final activityService = _RecordingGroupActivityService();
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: connectivity,
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      // #1140: 2 event legs + 1 residual + 1 group_settlement activity staged
      // into ONE batch, committed once.
      expect(queuedBatch.setCount, 4);
      expect(queuedBatch.commitCount, 1);
      // Exactly ONE bump for the whole logical settle-up (not per leg).
      expect(container.read(ledgerRevisionProvider), 1);
      // Queued-offline: noteQueuedWrite moved connectivity to syncing.
      expect(container.read(connectivityProvider), ConnectivityStatus.syncing);
      // The activity is folded into the batch (a gstl_ doc), NOT a separate
      // logGroupEvent call.
      expect(activityService.logCalls, isEmpty);
      final act = queuedBatch.staged.where((s) => s.id.startsWith('gstl_'));
      expect(act, hasLength(1));
      expect(
        (act.single.data! as Map)['type'],
        'group_settlement',
      );
      expect(
        find.text('Settlement recorded — will sync when online.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a > kMaxDecomposeLegsAtomic decompose routes to the single group write '
    '(no event docs, no ledger bump)',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      // Real batch factory (unused on the fallback path — the single group
      // write goes through addGroupSettlement, not stageDecomposedSettleUp).
      final groupService = GroupSettlementService.withFirestore(fake);
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(_wrap(
        balances: _balancesTenEvents(),
        events: [for (var i = 1; i <= 10; i++) _event('event-$i', 'E$i', EventType.trip)],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      // Over the cap → ONE atomic group settlement, zero event docs.
      final eventDocs = await fake
          .collection('groups')
          .doc(_groupId)
          .collection('events')
          .doc('event-1')
          .collection('settlements')
          .get();
      expect(eventDocs.docs, isEmpty);
      final groupDocs = await fake
          .collection('groups')
          .doc(_groupId)
          .collection('settlements')
          .get();
      expect(groupDocs.docs, hasLength(1));
      expect(groupDocs.docs.single.data()['amountFils'], 10000);
      // A group-only write needs no home bump (group settlements are live-watched).
      expect(container.read(ledgerRevisionProvider), 0);
    },
  );

  // #1140: adding the activity op moved the budget from 2·N+1 to 2·N+2, so the
  // cap dropped 9→8. Pin the new boundary: 8 decomposes atomically, 9 falls back.
  testWidgets(
    'exactly kMaxDecomposeLegsAtomic (8) event legs stay on the decomposed '
    'batch path (2·8 legs + 1 activity = 17 sets)',
    (tester) async {
      expect(kMaxDecomposeLegsAtomic, 8);
      final fake = FakeFirebaseFirestore();
      final queuedBatch = _StubWriteBatch(() => Completer<void>().future);
      final groupService = GroupSettlementService.withFirestore(fake)
        ..batchFactoryOverride = () => queuedBatch;
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(_wrap(
        balances: _balancesNEvents(8),
        events: [for (var i = 1; i <= 8; i++) _event('event-$i', 'E$i', EventType.trip)],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false)..setOffline(),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();
      await _recordFullAmount(tester);

      // 8 event legs (no residual) + 1 group_settlement activity = 9 sets.
      expect(queuedBatch.commitCount, 1);
      expect(queuedBatch.setCount, 9);
      expect(
        queuedBatch.staged.where((s) => s.id.startsWith('gstl_')),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'nine event legs (> cap 8) route to the single atomic group write '
    '(no event docs, no decomposed batch)',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      final groupService = GroupSettlementService.withFirestore(fake);
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(_wrap(
        balances: _balancesNEvents(9),
        events: [for (var i = 1; i <= 9; i++) _event('event-$i', 'E$i', EventType.trip)],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();
      await _recordFullAmount(tester);

      // Over the cap → ONE atomic group settlement, zero event docs.
      final eventDocs = await fake
          .collection('groups')
          .doc(_groupId)
          .collection('events')
          .doc('event-1')
          .collection('settlements')
          .get();
      expect(eventDocs.docs, isEmpty);
      final groupDocs = await fake
          .collection('groups')
          .doc(_groupId)
          .collection('settlements')
          .get();
      expect(groupDocs.docs, hasLength(1));
      // The single group write folds its own group_settlement activity row.
      final activity = await fake
          .collection('groups')
          .doc(_groupId)
          .collection('activity')
          .get();
      expect(activity.docs, hasLength(1));
      expect(activity.docs.single.data()['type'], 'group_settlement');
    },
  );
}
