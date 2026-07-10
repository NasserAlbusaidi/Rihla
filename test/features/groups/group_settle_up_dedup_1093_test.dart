import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #1093: a group settle-up written twice from the SAME observed state (neither
// device has seen the other's write yet) must collapse — decomposed legs +
// residual to N+1 docs (not 2·(N+1)), and the fallback single group write to
// ONE doc (not two). Epoch is pinned at 0 for BOTH record actions by directly
// overriding groupSettlementsProvider (single-shot) and
// groupTaggedEventSettlementsProvider (a plain Provider.family, overridden to
// a fixed empty list) so no amount of pumping between the two actions can
// advance the basis — a stronger guarantee than merely "don't pump between
// the calls."

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

/// Bob owes Alice 10.000: 3 attributable in each of two events + a 4.000
/// cross-event residual → a decompose of 2 event legs + 1 residual (3 docs).
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

/// Bob owes Alice across TEN events (1.000 each) → over kMaxDecomposeLegsAtomic
/// → the screen routes to the single atomic group-write fallback.
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

class _RecordingGroupActivityService extends GroupActivityService {
  _RecordingGroupActivityService() : super.withFirestore(FakeFirebaseFirestore());

  @override
  void logGroupEvent({
    required String groupId,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata,
  }) {
    // Swallow — activity logging is not under test here.
  }
}

Widget _wrap({
  required GroupBalances balances,
  required List<Event> events,
  required Group group,
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(group)),
      groupBalancesProvider(_groupId)
          .overrideWith((_) => AsyncValue.data(balances)),
      // Single-shot: pinned at [] for the life of the test — epoch stays 0.
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      // Directly overridden (bypassing its normal live-event derivation) so
      // decompose legs landing in the fake between the two record actions
      // cannot advance this basis either.
      groupTaggedEventSettlementsProvider(
        _groupId,
      ).overrideWith((_) => const <Settlement>[]),
      groupEventsProvider(_groupId).overrideWith((_) => Stream.value(events)),
      currentUserIdProvider.overrideWithValue('uid-bob'),
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
  // #367: the debtor recording their own payment triggers a post-record
  // WhatsApp-notify nudge — dismiss it so the next record action's tap lands
  // on the real record-payment button, not the nudge.
  final notifySheet = find.byKey(GroupKeys.settleNotifySheet);
  if (notifySheet.evaluate().isNotEmpty) {
    await tester.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
    await tester.pumpAndSettle();
  }
}

Future<int> _totalSettlementDocs(FakeFirebaseFirestore fake) async {
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

void main() {
  testWidgets(
    '#1093 (a): a decomposed settle-up staged twice from the same epoch-0 '
    'snapshot collapses to N+1 docs, not 2*(N+1)',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      final groupService = GroupSettlementService.withFirestore(fake);
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();

      await _recordFullAmount(tester);
      await _recordFullAmount(tester);

      expect(
        await _totalSettlementDocs(fake),
        3,
        reason:
            '2 event legs + 1 residual = 3 unique docs; both decompose calls '
            'derive the same groupSettleUpId (and therefore the same leg/'
            'residual ids), so the second batch overwrites the first rather '
            'than doubling it. Production is denied by the already-live '
            '`allow update: if false`.',
      );
    },
  );

  testWidgets(
    '#1093 (b): the fallback single group settle recorded twice from the same '
    'epoch-0 snapshot collapses to ONE group doc',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      final groupService = GroupSettlementService.withFirestore(fake);
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(_wrap(
        balances: _balancesTenEvents(),
        events: [for (var i = 1; i <= 10; i++) _event('event-$i', 'E$i', EventType.trip)],
        group: _group(),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(groupService),
          groupActivityServiceProvider.overrideWithValue(activityService),
        ],
      ));
      await tester.pumpAndSettle();

      await _recordFullAmount(tester);
      await _recordFullAmount(tester);

      final groupDocs = await fake
          .collection('groups')
          .doc(_groupId)
          .collection('settlements')
          .get();
      expect(
        groupDocs.docs,
        hasLength(1),
        reason:
            'both fallback writes derive the same deterministic group-scope '
            'id from the identical epoch-0 snapshot.',
      );
    },
  );
}
