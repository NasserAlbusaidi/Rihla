import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/review_prompt.dart';
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
import 'package:safar/l10n/generated/app_localizations.dart';

import '../../helpers/recording_functions_service.dart';

// #1263: a CLEAN recorded group settle-up (decomposed groupSettleUp mode) is
// the natural moment for the store review ask — exactly one fire-and-forget
// ReviewPrompt call per completed single-tile record. An #1129 idempotent
// replay (alreadyRecorded) must NOT prompt (same reasoning as the #367 nudge
// gate).

class _SpyReviewPrompt extends ReviewPrompt {
  _SpyReviewPrompt(super.ref);
  int calls = 0;
  @override
  Future<void> maybeRequest() async => calls++;
}

const _groupId = 'grp-1';

Group _group() => Group(
      id: _groupId,
      name: 'Test Crew',
      inviteCode: 'TST123',
      createdBy: 'uid-alice',
      memberIds: const ['uid-alice', 'uid-bob'],
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
GroupBalances _balances() => (
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

void main() {
  late RecordingFunctionsService recordingFunctions;
  _SpyReviewPrompt? spy;
  setUp(() {
    recordingFunctions = RecordingFunctionsService();
    spy = null;
  });

  Widget wrap() {
    final service = GroupSettlementService.withFirestore(
      FakeFirebaseFirestore(),
      functionsService: recordingFunctions,
    );
    return ProviderScope(
      overrides: [
        groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group())),
        groupBalancesProvider(_groupId)
            .overrideWith((_) => AsyncValue.data(_balances())),
        groupSettlementsProvider(
          _groupId,
        ).overrideWith((_) => Stream.value(const <Settlement>[])),
        groupTaggedEventSettlementsProvider(
          _groupId,
        ).overrideWith((_) => const <Settlement>[]),
        groupEventsProvider(
          _groupId,
        ).overrideWith((_) => Stream.value([_event1, _event2])),
        currentUserIdProvider.overrideWithValue('uid-bob'),
        groupSettlementServiceProvider.overrideWithValue(service),
        reviewPromptProvider.overrideWith((ref) => spy = _SpyReviewPrompt(ref)),
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

  Future<void> recordFullAmount(WidgetTester tester) async {
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();
    // #367: the debtor recording their own payment gets the WhatsApp-notify
    // nudge sheet first — dismiss it; the review ask fires after the nudge.
    final notifySheet = find.byKey(GroupKeys.settleNotifySheet);
    if (notifySheet.evaluate().isNotEmpty) {
      await tester.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('#1263: a clean group settle-up record asks for a review once', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await recordFullAmount(tester);

    expect(recordingFunctions.recordSettlementCalls, hasLength(1));
    expect(spy?.calls ?? 0, 1);
  });

  testWidgets('#1263: an alreadyRecorded (#1129) replay never prompts', (
    tester,
  ) async {
    recordingFunctions.result = const RecordSettlementResult(
      alreadyRecorded: true,
      eventScopeWrites: 0,
      groupScopeWrites: 0,
      shouldBumpLedgerRevision: false,
      settledAt: '2026-07-11T12:00:00.000Z',
    );
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await recordFullAmount(tester);

    expect(recordingFunctions.recordSettlementCalls, hasLength(1));
    expect(spy?.calls ?? 0, 0);
  });
}
