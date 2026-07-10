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

// #1093: a settlement written twice from the SAME observed state (neither
// device has seen the other's write yet) must collapse to ONE Firestore doc,
// not two. This models the concurrent/offline-replay double-record by wiring
// eventSettlementsProvider to a SINGLE-SHOT `Stream.value(const [])` — it
// emits exactly once and then never again, so BOTH record actions read the
// identical epoch-0 snapshot no matter how much the widget is pumped between
// them (a stronger guarantee than merely "don't pump between the calls").
//
// RED today (pre-fix): _recordSettlement has no id-derivation wired in yet —
// settlement_service.dart's `addSettlement` now REQUIRES an id (Task 2), so
// this file cannot even compile against a naive/no-op id until Task 3 lands.
// The genuine RED evidence for "two uuid docs" was captured against an
// interim `id: const Uuid().v4()` callsite before the deterministic
// derivation replaced it (see PR body for the pasted output).

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
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
        SettlementService.withFirestore(fakeDb),
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
    '#1093: two settle-up records from the same epoch-0 snapshot collapse '
    'to ONE settlement doc (deterministic id dedup)',
    (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(buildScreen(fakeDb));
      await tester.pumpAndSettle();

      // Two full record round-trips. Because eventSettlementsProvider is
      // single-shot ([] forever), the screen's balance/tile — and therefore
      // the id-derivation epoch inside _recordSettlement — NEVER learns about
      // the first write. Both derive from the identical epoch-0 snapshot,
      // exactly modeling two devices racing the same debt.
      await recordOnce(tester);
      await recordOnce(tester);

      final snap = await fakeDb
          .collection('groups')
          .doc(groupId)
          .collection('events')
          .doc(eventId)
          .collection('settlements')
          .get();

      expect(
        snap.docs,
        hasLength(1),
        reason:
            'both writes derive the same deterministic id — the fake '
            'overwrites the same doc; production is denied by the already-'
            'live `allow update: if false`',
      );
    },
  );
}
