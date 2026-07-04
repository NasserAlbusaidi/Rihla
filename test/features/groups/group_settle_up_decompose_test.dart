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
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
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

/// Bob owes Alice 7.750 OMR, ALL of it earned in event-1 (single-event case).
GroupBalances _balancesSingleEvent({String debtorId = 'uid-bob'}) => (
      balances: <String, List<UserBalance>>{
        'OMR': [
          UserBalance(
            participantId: 'uid-alice',
            displayName: 'Alice',
            totalPaid: Decimal.parse('15.500'),
            totalOwed: Decimal.parse('7.750'),
            netBalance: Decimal.parse('7.750'),
          ),
          UserBalance(
            participantId: debtorId,
            displayName: 'Bob',
            totalPaid: Decimal.parse('0.000'),
            totalOwed: Decimal.parse('7.750'),
            netBalance: Decimal.parse('-7.750'),
          ),
        ],
      },
      totalSpent: <String, Decimal>{'OMR': Decimal.parse('15.500')},
      eventCount: 1,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
        'uid-alice': {
          'event-1': {'OMR': Decimal.parse('7.750')},
        },
        debtorId: {
          'event-1': {'OMR': Decimal.parse('-7.750')},
        },
      },
      memberNames: <String, String>{'uid-alice': 'Alice', debtorId: 'Bob'},
      memberRawNames: <String, String>{'uid-alice': 'Alice', debtorId: 'Bob'},
    );

class _RecordingEventSettlementService extends SettlementService {
  _RecordingEventSettlementService() : super.withFirestore(FakeFirebaseFirestore());

  final addCalls = <({
    String groupId,
    String eventId,
    String payerParticipantId,
    String recipientParticipantId,
    Decimal amount,
    String currency,
    String? note,
    String? groupSettleUpId,
  })>[];

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
    addCalls.add((
      groupId: groupId,
      eventId: eventId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      currency: currency,
      note: note,
      groupSettleUpId: groupSettleUpId,
    ));
    return Settlement(
      id: 'evt-set-${addCalls.length}',
      tripId: eventId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      currency: currency,
      createdBy: createdBy,
      settledAt: DateTime(2026, 4, 1),
      groupSettleUpId: groupSettleUpId,
    );
  }
}

class _RecordingGroupSettlementService extends GroupSettlementService {
  _RecordingGroupSettlementService() : super.withFirestore(FakeFirebaseFirestore());

  final addCalls = <({
    Decimal amount,
    String currency,
    String? groupSettleUpId,
  })>[];

  @override
  Future<Settlement> addGroupSettlement({
    required String groupId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required Decimal amount,
    required String createdBy,
    String currency = 'OMR',
    String? note,
    String? payerName,
    String? recipientName,
    String? groupSettleUpId,
  }) async {
    addCalls.add((
      amount: amount,
      currency: currency,
      groupSettleUpId: groupSettleUpId,
    ));
    return Settlement(
      id: 'grp-set-${addCalls.length}',
      tripId: groupId,
      payerParticipantId: payerParticipantId,
      recipientParticipantId: recipientParticipantId,
      amount: amount,
      currency: currency,
      createdBy: createdBy,
      settledAt: DateTime(2026, 4, 1),
      scope: 'group',
      groupId: groupId,
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

Widget _wrap({
  required GroupBalances balances,
  required List<Event> events,
  required Group group,
  required List<Override> overrides,
  List<Settlement> settlements = const <Settlement>[],
  String currentUid = 'uid-bob',
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(group)),
      groupBalancesProvider(_groupId).overrideWith((_) => AsyncValue.data(balances)),
      groupSettlementsProvider(_groupId)
          .overrideWith((_) => Stream.value(settlements)),
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
  group('#752 group settle-up decomposes into per-event writes', () {
    testWidgets(
      'a single-event group settle-up writes an EVENT settlement (reducing the '
      'event ledger), no residual group doc, and bumps ledgerRevision',
      (tester) async {
        final eventService = _RecordingEventSettlementService();
        final groupService = _RecordingGroupSettlementService();
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(_wrap(
          balances: _balancesSingleEvent(),
          events: [_event1],
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

        // The money truth landed in the EVENT subcollection — this is the bug
        // fix: a group settle-up now reduces the per-event ledger.
        expect(eventService.addCalls, hasLength(1));
        final call = eventService.addCalls.single;
        expect(call.eventId, 'event-1');
        expect(call.payerParticipantId, 'uid-bob');
        expect(call.recipientParticipantId, 'uid-alice');
        expect(call.amount, Decimal.parse('7.750'));
        expect(call.currency, 'OMR');
        expect(call.groupSettleUpId, isNotNull);

        // residual == 0 → NO group settlement doc.
        expect(groupService.addCalls, isEmpty);

        // Activity logged ONCE for the whole logical settle-up, amount = A.
        // #831: the decomposed event-settlement SLICES must emit no
        // event_settlement rows — they bypass settle_up_screen.dart's record
        // path structurally (written via addSettlement here), and the one
        // aggregate group_settlement row already represents the settle-up.
        expect(activityService.logCalls, hasLength(1));
        expect(activityService.logCalls.single.type, 'group_settlement');
        expect(
          activityService.logCalls.where((c) => c.type == 'event_settlement'),
          isEmpty,
        );
        expect(activityService.logCalls.single.metadata?['amount'], '7.75');

        // #818 Wave 3.1: direction keys stamped alongside the legacy shape —
        // cardinality stays exactly 1 (this spec only widens the metadata map).
        final metadata = activityService.logCalls.single.metadata!;
        expect(metadata['fromUserId'], 'uid-bob');
        expect(metadata['toUserId'], 'uid-alice');
        expect(metadata['fromName'], isA<String>());
        expect(metadata['fromName'], isNotEmpty);
        expect(metadata['toName'], isA<String>());
        expect(metadata['toName'], isNotEmpty);

        // Per-event write happened → home one-shot must be refreshed.
        expect(container.read(ledgerRevisionProvider), 1);

        expect(find.text('Settlement recorded.'), findsOneWidget);
      },
    );

    testWidgets(
      'a settle-up involving a NON-member (departed #249) falls back to a single '
      'group settlement — no partial-persist of event writes',
      (tester) async {
        // Charlie has a balance but is NOT in group.memberIds → the residual
        // group write would be permission-denied, so decompose must not run.
        final balances = (
          balances: <String, List<UserBalance>>{
            'OMR': [
              UserBalance(
                participantId: 'uid-alice',
                displayName: 'Alice',
                totalPaid: Decimal.parse('7.750'),
                totalOwed: Decimal.zero,
                netBalance: Decimal.parse('7.750'),
              ),
              UserBalance(
                participantId: 'uid-charlie',
                displayName: 'Charlie',
                totalPaid: Decimal.zero,
                totalOwed: Decimal.parse('7.750'),
                netBalance: Decimal.parse('-7.750'),
              ),
            ],
          },
          totalSpent: <String, Decimal>{'OMR': Decimal.parse('7.750')},
          eventCount: 1,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
            'uid-alice': {
              'event-1': {'OMR': Decimal.parse('7.750')},
            },
            'uid-charlie': {
              'event-1': {'OMR': Decimal.parse('-7.750')},
            },
          },
          memberNames: <String, String>{
            'uid-alice': 'Alice',
            'uid-charlie': 'Charlie',
          },
          memberRawNames: <String, String>{
            'uid-alice': 'Alice',
            'uid-charlie': 'Charlie',
          },
        );

        final eventService = _RecordingEventSettlementService();
        final groupService = _RecordingGroupSettlementService();
        final activityService = _RecordingGroupActivityService();

        await tester.pumpWidget(_wrap(
          balances: balances,
          events: [_event1],
          group: _group(memberIds: const ['uid-alice', 'uid-bob']), // charlie absent
          currentUid: 'uid-charlie',
          overrides: [
            settlementServiceProvider.overrideWithValue(eventService),
            groupSettlementServiceProvider.overrideWithValue(groupService),
            groupActivityServiceProvider.overrideWithValue(activityService),
          ],
        ));
        await tester.pumpAndSettle();

        await _recordFullAmount(tester);

        // No event writes (would orphan if the residual were denied).
        expect(eventService.addCalls, isEmpty);
        // Fell back to today's single atomic group settlement.
        expect(groupService.addCalls, hasLength(1));
        expect(groupService.addCalls.single.amount, Decimal.parse('7.750'));
      },
    );
  });

  group('#752 display breakdown == decomposed write (WYSIWYG)', () {
    testWidgets(
      'over-display fixed: offsetting cross-event nets show the CAPPED slice '
      '(6), never the raw per-event overlap (10)',
      (tester) async {
        // bob: -10 in E1, +4 in E2; alice: +10 in E1, -4 in E2 → net debt 6.
        final balances = (
          balances: <String, List<UserBalance>>{
            'OMR': [
              _bal('uid-alice', 'Alice', '6.000'),
              _bal('uid-bob', 'Bob', '-6.000'),
            ],
          },
          totalSpent: <String, Decimal>{'OMR': Decimal.parse('14.000')},
          eventCount: 2,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
            'uid-alice': {
              'event-1': {'OMR': Decimal.parse('10.000')},
              'event-2': {'OMR': Decimal.parse('-4.000')},
            },
            'uid-bob': {
              'event-1': {'OMR': Decimal.parse('-10.000')},
              'event-2': {'OMR': Decimal.parse('4.000')},
            },
          },
          memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
          memberRawNames: <String, String>{
            'uid-alice': 'Alice',
            'uid-bob': 'Bob',
          },
        );

        await tester.pumpWidget(_wrap(
          balances: balances,
          events: [_event1, _event2],
          group: _group(),
          overrides: const [],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(GroupSettlementTile));
        await tester.pumpAndSettle();

        // E1 carries the whole capped transfer (6), E2 nothing, no residual.
        expect(find.textContaining('Camping Weekend'), findsOneWidget);
        expect(find.textContaining('Road Trip'), findsNothing);
        expect(find.text('Across events'), findsNothing);
        // The raw E1 overlap (10) must NOT be displayed anywhere.
        expect(find.textContaining('10.000'), findsNothing);
      },
    );

    testWidgets(
      'pure cross-event debt (no shared event) shows ONLY the "Across events" '
      'residual row',
      (tester) async {
        // bob owes in E1, alice is owed in E2 — no shared event → all residual.
        final balances = (
          balances: <String, List<UserBalance>>{
            'OMR': [
              _bal('uid-alice', 'Alice', '5.000'),
              _bal('uid-bob', 'Bob', '-5.000'),
            ],
          },
          totalSpent: <String, Decimal>{'OMR': Decimal.parse('5.000')},
          eventCount: 2,
          perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
            'uid-alice': {
              'event-2': {'OMR': Decimal.parse('5.000')},
            },
            'uid-bob': {
              'event-1': {'OMR': Decimal.parse('-5.000')},
            },
          },
          memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
          memberRawNames: <String, String>{
            'uid-alice': 'Alice',
            'uid-bob': 'Bob',
          },
        );

        await tester.pumpWidget(_wrap(
          balances: balances,
          events: [_event1, _event2],
          group: _group(),
          overrides: const [],
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(GroupSettlementTile));
        await tester.pumpAndSettle();

        expect(find.text('Across events'), findsOneWidget);
        expect(find.textContaining('Camping Weekend'), findsNothing);
        expect(find.textContaining('Road Trip'), findsNothing);
      },
    );
  });

  group('#752 group history unions tagged event settlements', () {
    final settledBalances = (
      balances: <String, List<UserBalance>>{
        'OMR': [
          _bal('uid-alice', 'Alice', '0'),
          _bal('uid-bob', 'Bob', '0'),
        ],
      },
      totalSpent: <String, Decimal>{'OMR': Decimal.zero},
      eventCount: 1,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
      memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    );

    Settlement taggedSettlement() => Settlement(
          id: 'evt-set-1',
          tripId: 'event-1',
          payerParticipantId: 'uid-bob',
          recipientParticipantId: 'uid-alice',
          amount: Decimal.parse('7.750'),
          settledAt: DateTime(2026, 4, 1),
          payerName: 'Bob',
          recipientName: 'Alice',
          currency: 'OMR',
          groupSettleUpId: 'su-1',
        );

    testWidgets(
      'a single-event settle-up (0 group docs) still shows in group history via '
      'its tagged event settlement, with the all-settled headline',
      (tester) async {
        await tester.pumpWidget(_wrap(
          balances: settledBalances,
          events: [_event1],
          group: _group(),
          overrides: [
            groupTaggedEventSettlementsProvider(_groupId)
                .overrideWithValue([taggedSettlement()]),
          ],
        ));
        await tester.pumpAndSettle();

        // Fully settled → "Everyone's even." headline (transferCount == 0)…
        expect(find.textContaining("Everyone's even"), findsOneWidget);
        // …and the payment did NOT vanish — it shows in history.
        expect(find.textContaining('7.750'), findsWidgets);
      },
    );

    testWidgets(
      'a tagged (decomposed) settlement exposes the LOGICAL correct button '
      '(#753 — PR1 hid it; PR2 reverses the whole settle-up atomically)',
      (tester) async {
        await tester.pumpWidget(_wrap(
          balances: settledBalances,
          events: [_event1],
          group: _group(),
          overrides: [
            groupTaggedEventSettlementsProvider(_groupId)
                .overrideWithValue([taggedSettlement()]),
          ],
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
      },
    );

    testWidgets(
      'the one-tap correct button IS shown on a legacy/standalone group '
      'settlement (null groupSettleUpId) — today\'s correct path unchanged',
      (tester) async {
        final legacy = Settlement(
          id: 'grp-set-legacy',
          tripId: _groupId,
          payerParticipantId: 'uid-bob',
          recipientParticipantId: 'uid-alice',
          amount: Decimal.parse('3.000'),
          settledAt: DateTime(2026, 4, 2),
          payerName: 'Bob',
          recipientName: 'Alice',
          scope: 'group',
          groupId: _groupId,
          currency: 'OMR',
        );
        await tester.pumpWidget(_wrap(
          balances: settledBalances,
          events: [_event1],
          group: _group(),
          settlements: [legacy],
          overrides: const [],
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);
      },
    );
  });
}
