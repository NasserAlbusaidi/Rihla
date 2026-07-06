import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:safar/features/ledger/services/settlement_service.dart';
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

final _event1 = Event(
  id: 'event-1',
  name: 'Camping Weekend',
  type: EventType.camping,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 15),
  createdAt: DateTime(2026, 3, 10),
);

final _event2 = Event(
  id: 'event-2',
  name: 'Road Trip',
  type: EventType.trip,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 5, 2),
  createdAt: DateTime(2026, 5, 1),
);

UserBalance _bal(String id, String name, String net) => UserBalance(
      participantId: id,
      displayName: name,
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.parse(net),
    );

/// Bob owes Alice 8.000 OMR, split 4.000 in event-1 + 4.000 in event-2 → a
/// TWO-leg decompose, no residual (both events have a positive attributable
/// slice). This is the smallest case that persists a partial settle-up when a
/// later leg is rejected.
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

/// Event settlement service that writes the FIRST leg for real to the shared
/// fake, then throws `permission-denied` on the SECOND — modelling a leg whose
/// membership/participation changed so its rule evaluation fails while the
/// earlier leg already committed. Exercises the CURRENT sequential walk.
class _SecondLegRejectingEventService extends SettlementService {
  _SecondLegRejectingEventService(FakeFirebaseFirestore fake)
      : super.withFirestore(fake);

  int _calls = 0;

  @override
  Future<Settlement> addSettlement({
    required String groupId,
    required String eventId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String createdBy,
    String currency = 'OMR',
    String? payerName,
    String? recipientName,
    String? note,
    String? groupSettleUpId,
  }) async {
    _calls++;
    if (_calls >= 2) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Simulated rules rejection on the second leg.',
      );
    }
    return super.addSettlement(
      groupId: groupId,
      eventId: eventId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      createdBy: createdBy,
      currency: currency,
      payerName: payerName,
      recipientName: recipientName,
      note: note,
      groupSettleUpId: groupSettleUpId,
    );
  }
}

class _RecordingGroupActivityService extends GroupActivityService {
  _RecordingGroupActivityService() : super.withFirestore(FakeFirebaseFirestore());

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

/// Total settlement docs that landed anywhere for the group: both event
/// subcollections + the group-level residual collection.
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
      final fake = FakeFirebaseFirestore();
      final eventService = _SecondLegRejectingEventService(fake);
      final groupService = GroupSettlementService.withFirestore(fake);
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEvents(),
        events: [_event1, _event2],
        group: _group(),
        overrides: [
          settlementServiceProvider.overrideWithValue(eventService),
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      // A single logical settle-up must be all-or-nothing: the second leg was
      // rejected, so NO settlement doc may survive anywhere. Today's sequential
      // walk leaves the first leg persisted → this is RED pre-fix.
      expect(await _settlementDocCount(fake), 0);

      // A failed write must not bump the home one-shot or log the settle-up.
      expect(container.read(ledgerRevisionProvider), 0);
      expect(activityService.logCalls, isEmpty);
    },
    // RED partial-persist repro (Refs #929). Captured pre-fix in
    // RED-evidence-929.txt (leg-1 survives a leg-2 rejection). Unskipped and
    // rebuilt onto the atomic WriteBatch injection point in Task 4 (the
    // sequential walk it exercises no longer exists after the fix).
    skip: true, // RED repro — GREEN after the #929 atomic fix (Task 4).
  );
}
