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
import 'package:safar/features/groups/services/group_settlement_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

import '../../helpers/recording_functions_service.dart';

// #1093 → #1129: a group settle-up recorded twice from the SAME observed
// state (neither device has seen the other's write yet) must collapse to ONE
// logical payment. Since #1129 the id derivation is SERVER-side: the client's
// contribution to determinism is sending the identical `observedPairEpoch` +
// money payload for the identical observed snapshot. Epoch is pinned at 0 for
// BOTH record actions by overriding groupSettlementsProvider (single-shot)
// and groupTaggedEventSettlementsProvider (fixed empty list) so no amount of
// pumping between the two actions can advance the basis. The one-payment
// guarantee itself (identical payload → same gsu/group sd1 id →
// alreadyRecorded) is pinned by the emulator idempotency tables in
// functions/test/callables/recordSettlement.group.test.ts.

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
/// cross-event residual → a decompose of 2 event legs + the server residual.
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

/// Bob owes Alice 10.000 with NO per-event attribution (pure cross-event
/// pair) → the screen routes to the mode-'group' single aggregate write.
GroupBalances _balancesCrossEventOnly() => (
      balances: <String, List<UserBalance>>{
        'OMR': [
          _bal('uid-alice', 'Alice', '10.000'),
          _bal('uid-bob', 'Bob', '-10.000'),
        ],
      },
      totalSpent: <String, Decimal>{'OMR': Decimal.parse('20.000')},
      eventCount: 2,
      perEventBreakdown: const <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
      memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
    );

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
      // nothing landing between the two record actions can advance this
      // basis either.
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

void main() {
  late RecordingFunctionsService recordingFunctions;
  setUp(() {
    recordingFunctions = RecordingFunctionsService();
  });

  GroupSettlementService service() => GroupSettlementService.withFirestore(
        FakeFirebaseFirestore(),
        functionsService: recordingFunctions,
      );

  testWidgets(
    '#1093/#1129 (a): a decomposed settle-up recorded twice from the same '
    'epoch-0 snapshot sends the IDENTICAL groupSettleUp intent twice',
    (tester) async {
      await tester.pumpWidget(_wrap(
        balances: _balancesTwoEventsWithResidual(),
        events: [_event1, _event2],
        group: _group(),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service()),
        ],
      ));
      await tester.pumpAndSettle();

      await _recordFullAmount(tester);
      await _recordFullAmount(tester);

      expect(recordingFunctions.recordSettlementCalls, hasLength(2));
      final first = recordingFunctions.recordSettlementCalls[0];
      final second = recordingFunctions.recordSettlementCalls[1];
      expect(first['mode'], 'groupSettleUp');
      expect(first['observedPairEpoch'], 0);
      expect(first['amountFils'], 10000);
      expect(first['legs'], [
        {'eventId': 'event-1', 'amountFils': 3000},
        {'eventId': 'event-2', 'amountFils': 3000},
      ]);
      expect(
        second,
        first,
        reason:
            'identical observed snapshot ⇒ byte-identical callable intent ⇒ '
            'the server derives ONE gsu id (and therefore one leg/residual '
            'set) for both — the second lands as alreadyRecorded',
      );
    },
  );

  testWidgets(
    '#1093/#1129 (b): the mode-group fallback recorded twice from the same '
    'epoch-0 snapshot sends the IDENTICAL group intent twice',
    (tester) async {
      await tester.pumpWidget(_wrap(
        balances: _balancesCrossEventOnly(),
        events: [_event1, _event2],
        group: _group(),
        overrides: [
          groupSettlementServiceProvider.overrideWithValue(service()),
        ],
      ));
      await tester.pumpAndSettle();

      await _recordFullAmount(tester);
      await _recordFullAmount(tester);

      expect(recordingFunctions.recordSettlementCalls, hasLength(2));
      final first = recordingFunctions.recordSettlementCalls[0];
      final second = recordingFunctions.recordSettlementCalls[1];
      expect(first['mode'], 'group');
      expect(first['observedPairEpoch'], 0);
      expect(first['amountFils'], 10000);
      expect(first['legs'], isNull);
      expect(
        second,
        first,
        reason:
            'identical observed snapshot ⇒ byte-identical callable intent ⇒ '
            'the server derives ONE group-scope id for both',
      );
    },
  );
}
