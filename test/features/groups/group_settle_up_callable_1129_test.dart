import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/record_settlement_result.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #1129 successor of the retired group_settle_up_atomic_929_test.dart: the
// client WriteBatch (and its kMaxDecomposeLegsAtomic routing) died with the
// direct-write path — atomicity is now the recordSettlement SERVER transaction
// (pinned by functions/test/callables/recordSettlement.group.test.ts). What
// remains client-side to pin: the wire payload (WYSIWYG legs, total, epoch),
// the offline pre-flight, the empty-decompose mode-'group' routing, the
// server-gated ledger bump, and the alreadyRecorded / error copy.

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
/// cross-event residual → a two-leg decompose with a residual.
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

/// Bob owes Alice 8.000 with NO per-event attribution (pure cross-event pair)
/// → decompose.perEvent is empty → the screen routes to mode 'group'.
GroupBalances _balancesCrossEventOnly() => (
      balances: <String, List<UserBalance>>{
        'OMR': [
          _bal('uid-alice', 'Alice', '8.000'),
          _bal('uid-bob', 'Bob', '-8.000'),
        ],
      },
      totalSpent: <String, Decimal>{'OMR': Decimal.parse('16.000')},
      eventCount: 2,
      perEventBreakdown: const <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
      memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    );

typedef _DecomposedCall = ({
  List<({String eventId, Decimal amount})> eventLegs,
  Decimal amount,
  String payer,
  String recipient,
  String currency,
  int observedPairEpoch,
});

typedef _GroupCall = ({
  Decimal amount,
  String payer,
  String recipient,
  String currency,
  int observedPairEpoch,
});

/// Records what the screen sends to the callable seam; the Firestore half is
/// a throwaway fake (only the untouched watch streams would use it).
class _RecordingGroupSettlementService extends GroupSettlementService {
  _RecordingGroupSettlementService()
      : super.withFirestore(FakeFirebaseFirestore());

  final decomposedCalls = <_DecomposedCall>[];
  final groupCalls = <_GroupCall>[];

  RecordSettlementResult result = const RecordSettlementResult(
    alreadyRecorded: false,
    eventScopeWrites: 2,
    groupScopeWrites: 1,
    shouldBumpLedgerRevision: true,
    settledAt: '2026-07-11T12:00:00.000Z',
  );
  Object? error;

  @override
  Future<RecordSettlementResult> addGroupSettlement({
    required String groupId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String currency,
    required int observedPairEpoch,
    String? note,
    String? payerName,
    String? recipientName,
  }) async {
    groupCalls.add((
      amount: amount,
      payer: payerParticipantId,
      recipient: recipientParticipantId,
      currency: currency,
      observedPairEpoch: observedPairEpoch,
    ));
    final e = error;
    if (e != null) throw e;
    return result;
  }

  @override
  Future<RecordSettlementResult> recordDecomposedSettleUp({
    required String groupId,
    required List<({String eventId, Decimal amount})> eventLegs,
    required Decimal amount,
    required String payerParticipantId,
    required String recipientParticipantId,
    required String currency,
    required int observedPairEpoch,
    String? payerName,
    String? recipientName,
    String? note,
  }) async {
    decomposedCalls.add((
      eventLegs: eventLegs,
      amount: amount,
      payer: payerParticipantId,
      recipient: recipientParticipantId,
      currency: currency,
      observedPairEpoch: observedPairEpoch,
    ));
    final e = error;
    if (e != null) throw e;
    return result;
  }
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
    'decomposed settle-up sends ONE callable payload: WYSIWYG legs in event '
    'order, the TOTAL, epoch 0 — and bumps the ledger revision once',
    (tester) async {
      final service = _RecordingGroupSettlementService();

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      expect(service.decomposedCalls, hasLength(1));
      expect(service.groupCalls, isEmpty);
      final call = service.decomposedCalls.single;
      expect(call.amount, Decimal.parse('10.000'));
      expect(call.payer, 'uid-bob');
      expect(call.recipient, 'uid-alice');
      expect(call.currency, 'OMR');
      // Epoch over the (empty) overridden settlement streams.
      expect(call.observedPairEpoch, 0);
      // WYSIWYG (#752): legs in the displayed eventOrder; the 4.000 residual
      // is NOT a leg — the server derives it from total − Σ legs.
      expect(call.eventLegs, [
        (eventId: 'event-1', amount: Decimal.parse('3.000')),
        (eventId: 'event-2', amount: Decimal.parse('3.000')),
      ]);
      // ONE server-gated bump for the whole logical settle-up.
      expect(container.read(ledgerRevisionProvider), 1);
      expect(find.text('Settlement recorded.'), findsOneWidget);
    },
  );

  testWidgets(
    'offline pre-flight: no callable invocation, honest failure copy, no bump',
    (tester) async {
      final service = _RecordingGroupSettlementService();
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: connectivity,
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      // The callable was never invoked — settlement creates have no offline
      // queue (#1129 trade-off 1), so the screen refuses before the call.
      expect(service.decomposedCalls, isEmpty);
      expect(service.groupCalls, isEmpty);
      expect(container.read(ledgerRevisionProvider), 0);
      expect(
        find.text(
          "Couldn't record settlement. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('Settlement recorded.'), findsNothing);
    },
  );

  testWidgets(
    'syncing PROCEEDS: the pre-flight blocks only provably-offline devices',
    (tester) async {
      final service = _RecordingGroupSettlementService();
      // offline → noteQueuedWrite = the #412 queued transition to `syncing`.
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline()
        ..noteQueuedWrite(groupId: _groupId);

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: connectivity,
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();
      expect(connectivity.state, ConnectivityStatus.syncing);

      await _recordFullAmount(tester);

      expect(service.decomposedCalls, hasLength(1));
      expect(find.text('Settlement recorded.'), findsOneWidget);
    },
  );

  testWidgets(
    'empty per-event attribution routes to mode group (addGroupSettlement) '
    'and honors shouldBumpLedgerRevision=false',
    (tester) async {
      final service = _RecordingGroupSettlementService()
        ..result = const RecordSettlementResult(
          alreadyRecorded: false,
          eventScopeWrites: 0,
          groupScopeWrites: 1,
          shouldBumpLedgerRevision: false,
          settledAt: '2026-07-11T12:00:00.000Z',
        );

      await tester.pumpWidget(_wrap(
        balances: _balancesCrossEventOnly(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      expect(service.groupCalls, hasLength(1));
      expect(service.decomposedCalls, isEmpty);
      expect(service.groupCalls.single.amount, Decimal.parse('8.000'));
      // A pure group write is live-watched — the server says no bump.
      expect(container.read(ledgerRevisionProvider), 0);
      expect(find.text('Settlement recorded.'), findsOneWidget);
    },
  );

  testWidgets(
    'alreadyRecorded replay shows the already-recorded success copy',
    (tester) async {
      final service = _RecordingGroupSettlementService()
        ..result = const RecordSettlementResult(
          alreadyRecorded: true,
          eventScopeWrites: 2,
          groupScopeWrites: 1,
          shouldBumpLedgerRevision: true,
          settledAt: '2026-07-11T12:00:00.000Z',
        );

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      await _recordFullAmount(tester);

      expect(find.text('This payment was already recorded.'), findsOneWidget);
      expect(find.text('Settlement recorded.'), findsNothing);
    },
  );

  testWidgets(
    'a denied callable shows the denied copy and persists no bump',
    (tester) async {
      final service = _RecordingGroupSettlementService()
        ..error = FirebaseFunctionsException(
          message: 'denied',
          code: 'permission-denied',
        );

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await _recordFullAmount(tester);

      expect(service.decomposedCalls, hasLength(1));
      expect(container.read(ledgerRevisionProvider), 0);
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
    'an over-outstanding rejection surfaces the LIVE server cap via the '
    'balance-changed copy (#773 reuse)',
    (tester) async {
      final service = _RecordingGroupSettlementService()
        ..error = FirebaseFunctionsException(
          message: 'cap',
          code: 'failed-precondition',
          details: const {
            'kind': 'over-outstanding',
            'outstandingFils': 4000,
            'currency': 'OMR',
          },
        );

      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        connectivity: ConnectivityNotifier(startPeriodicChecks: false),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service),
        ],
      ));
      await tester.pumpAndSettle();

      await _recordFullAmount(tester);

      expect(
        find.text(
          "Balance changed while you were recording — it's now OMR 4.000. "
          'Review and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Settlement recorded.'), findsNothing);
    },
  );
}
