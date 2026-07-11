import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

import '../../helpers/recording_functions_service.dart';

// #1093 → #1129: a settlement recorded twice from the SAME observed state
// (neither device has seen the other's write yet) must collapse to ONE
// recorded payment. Since #1129 the id derivation is SERVER-side: the client's
// contribution to determinism is sending the same `observedPairEpoch` for the
// same observed snapshot — pinned here by wiring eventSettlementsProvider to a
// SINGLE-SHOT `Stream.value(const [])` (emits once, never again), so BOTH
// record actions must put the identical epoch-0 + money payload on the wire.
// The one-doc guarantee itself (identical payload → same sd1 id →
// alreadyRecorded) is pinned by the emulator idempotency tables in
// functions/test/callables/recordSettlement.event.test.ts.

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  late SharedPreferences prefs;
  late RecordingFunctionsService recordingFunctions;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    recordingFunctions = RecordingFunctionsService();
  });

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'alice',
    participantIds: const ['alice', 'bob'],
    participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 5, 16),
  );

  final expenses = [
    Expense(
      id: 'expense-1',
      tripId: eventId,
      payerParticipantId: 'alice',
      amount: Decimal.parse('20.000'),
      description: 'Dinner',
      scope: ExpenseScope.global,
      splitMode: SplitMode.equally,
      createdAt: DateTime(2026, 5, 16),
      createdBy: 'alice',
    ),
  ];

  Widget buildScreen(FakeFirebaseFirestore fakeDb) {
    final overrides = [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('bob'),
      eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(expenses)),
      // Single-shot: emits [] exactly once, then never again — both record
      // actions in this test observe the identical epoch-0 snapshot.
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      groupMembersProvider(groupId).overrideWith((ref) => Stream.value(const [])),
      groupDetailProvider(groupId).overrideWith(
        (ref) => Stream.value(
          Group(
            id: groupId,
            name: 'Trip',
            inviteCode: 'ABC123',
            createdBy: 'bob',
            memberIds: const [],
            currency: 'OMR',
            createdAt: DateTime(2026),
          ),
        ),
      ),
      settlementServiceProvider.overrideWithValue(
        SettlementService.withFirestore(
          fakeDb,
          functionsService: recordingFunctions,
        ),
      ),
      groupActivityServiceProvider.overrideWithValue(
        GroupActivityService.withFirestore(fakeDb),
      ),
    ];

    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettleUpScreen(groupId: groupId, eventId: eventId),
      ),
    );
  }

  Future<void> recordOnce(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();
    // #367: the debtor (bob, currentUid) recording their own payment triggers
    // a post-record WhatsApp-notify nudge sheet — dismiss it so the next
    // recordOnce's tap lands on the real record-payment button, not the nudge.
    final notifySheet = find.byKey(GroupKeys.settleNotifySheet);
    if (notifySheet.evaluate().isNotEmpty) {
      await tester.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    '#1093/#1129: two settle-up records from the same epoch-0 snapshot send '
    'the IDENTICAL callable intent (server-side deterministic-id dedup)',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(buildScreen(fakeDb));
      await tester.pumpAndSettle();

      // Two full record round-trips. Because eventSettlementsProvider is
      // single-shot ([] forever), the screen's epoch basis NEVER learns about
      // the first record. Both calls must carry the identical epoch-0 money
      // payload — the server derives the same sd1 id from it, so the second
      // lands as alreadyRecorded (one doc), never a double-record.
      await recordOnce(tester);
      await recordOnce(tester);

      expect(recordingFunctions.recordSettlementCalls, hasLength(2));
      final first = Map.of(recordingFunctions.recordSettlementCalls[0]);
      final second = Map.of(recordingFunctions.recordSettlementCalls[1]);
      expect(first['observedPairEpoch'], 0);
      expect(second, first,
          reason:
              'identical observed snapshot ⇒ byte-identical callable intent '
              '⇒ the server derives ONE deterministic id for both');
    },
  );
}
