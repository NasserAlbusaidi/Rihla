import 'package:cloud_functions/cloud_functions.dart';
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
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

import '../../helpers/recording_functions_service.dart';

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

// #1129: the decompose write is ONE recordSettlement server transaction —
// the client's observable surface is the callable payload, captured by
// RecordingFunctionsService; the persisted docs, residual, and the ONE
// group_settlement activity row are pinned by the emulator tables in
// functions/test/callables/recordSettlement.group.test.ts.

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
      'a single-event group settle-up sends ONE groupSettleUp intent whose '
      'single leg carries the full amount, and bumps ledgerRevision',
      (tester) async {
        final recordingFunctions = RecordingFunctionsService();
        final groupService = GroupSettlementService.withFirestore(
          FakeFirebaseFirestore(),
          functionsService: recordingFunctions,
        );

        await tester.pumpWidget(_wrap(
          balances: _balancesSingleEvent(),
          events: [_event1],
          group: _group(),
          overrides: [
            groupSettlementServiceProvider.overrideWithValue(groupService),
          ],
        ));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(GroupSettleUpScreen)),
        );

        await _recordFullAmount(tester);

        // The whole debt is attributable to event-1 → ONE leg carrying the
        // full amount; the server writes it into the EVENT subcollection
        // (the #752 fix), derives residual 0 (no group doc), and authors the
        // ONE gstl_ activity row — all emulator-pinned.
        expect(recordingFunctions.recordSettlementCalls, hasLength(1));
        final call = recordingFunctions.lastCall;
        expect(call['mode'], 'groupSettleUp');
        expect(call['payerParticipantId'], 'uid-bob');
        expect(call['recipientParticipantId'], 'uid-alice');
        expect(call['currency'], 'OMR');
        expect(call['amountFils'], 7750);
        expect(call['legs'], [
          {'eventId': 'event-1', 'amountFils': 7750},
        ]);

        // Event-scope legs were written → home one-shot must be refreshed
        // (the recording fake's default result says shouldBumpLedgerRevision).
        expect(container.read(ledgerRevisionProvider), 1);

        expect(find.text('Settlement recorded.'), findsOneWidget);
      },
    );

    testWidgets(
      'a suggestion naming a NON-member (departed #249) is pruned from the '
      'tile list (#1149) — no Record affordance, so the #1129 server '
      'transaction fence never even receives an intent',
      (tester) async {
        // Charlie has a balance but is NOT in group.memberIds → #1149 hides
        // the suggestion tile (the counted note explains; R1 balance rows
        // stay visible). The #1129 server fence (party-not-member →
        // failed-precondition, rejected atomically) remains the enforcement
        // boundary for any non-tile path — armed below, never reached.
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

        final recordingFunctions = RecordingFunctionsService()
          // #1144 server-side: the transaction rejects a non-member party
          // atomically — nothing persists, no partial event legs.
          ..error = FirebaseFunctionsException(
            message: 'party not member',
            code: 'failed-precondition',
            details: const {'kind': 'party-not-member'},
          );
        final groupService = GroupSettlementService.withFirestore(
          FakeFirebaseFirestore(),
          functionsService: recordingFunctions,
        );

        await tester.pumpWidget(_wrap(
          balances: balances,
          events: [_event1],
          group: _group(memberIds: const ['uid-alice', 'uid-bob']), // charlie absent
          currentUid: 'uid-charlie',
          overrides: [
            groupSettlementServiceProvider.overrideWithValue(groupService),
          ],
        ));
        await tester.pumpAndSettle();

        // The departed pair's tile is pruned — no Record affordance at all.
        expect(
          find.byKey(GroupKeys.settleUpRecordPaymentButton),
          findsNothing,
        );
        expect(
          find.text(
            '1 suggestion involving a former member is hidden — '
            'that transfer can no longer be recorded.',
          ),
          findsOneWidget,
        );
        // The R1 balance row keeps the unpruned truth.
        expect(find.text('Charlie'), findsWidgets);

        // #1149: with the tile gone, the decomposed intent is NEVER sent —
        // no callable call, no denied snackbar, no success copy.
        expect(recordingFunctions.recordSettlementCalls, isEmpty);
        expect(
          find.text(
            "This settlement wasn't allowed. Please check the details and "
            'try again.',
          ),
          findsNothing,
        );
        expect(find.text('Settlement recorded.'), findsNothing);
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
      'its tagged event settlement',
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

        // The payment did NOT vanish — it shows in history.
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
