import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/review_prompt.dart';
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
import 'package:safar/features/ledger/models/record_settlement_result.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

import '../../helpers/recording_functions_service.dart';

// #1263: a CLEAN recorded settle-up is the natural moment for the store
// review ask — exactly one fire-and-forget ReviewPrompt call per completed
// single-tile record. An #1129 idempotent replay (alreadyRecorded) must NOT
// prompt: the user already had their moment for this exact payment (same
// reasoning as the #367 nudge gate).

class _SpyReviewPrompt extends ReviewPrompt {
  _SpyReviewPrompt(super.ref);
  int calls = 0;
  @override
  Future<void> maybeRequest() async => calls++;
}

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  late SharedPreferences prefs;
  late RecordingFunctionsService recordingFunctions;
  _SpyReviewPrompt? spy;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    recordingFunctions = RecordingFunctionsService();
    spy = null;
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
      reviewPromptProvider.overrideWith((ref) => spy = _SpyReviewPrompt(ref)),
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
    // #367: the debtor recording their own payment gets the WhatsApp-notify
    // nudge sheet first — dismiss it; the review ask fires after the nudge.
    final notifySheet = find.byKey(GroupKeys.settleNotifySheet);
    if (notifySheet.evaluate().isNotEmpty) {
      await tester.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('#1263: a clean single-tile record asks for a review once', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    await recordOnce(tester);

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
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    await recordOnce(tester);

    expect(spy?.calls ?? 0, 0);
  });
}
