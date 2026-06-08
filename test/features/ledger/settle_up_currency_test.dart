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
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #261 PR-A: event settle-up must write the OWNING GROUP's currency, not a
/// hardcoded 'OMR'. RED before A4: settle_up_screen had `const currency = 'OMR'`
/// so a USD group's settlement persisted as OMR (amountFils scaled by 1000).
void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

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

  // Alice paid 20 split equally → bob owes alice 10 (currency-blind amount).
  final expenses = [
    Expense(
      id: 'expense-1',
      tripId: eventId,
      payerParticipantId: 'alice',
      amount: Decimal.parse('20'),
      description: 'Dinner',
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 5, 16),
      createdBy: 'alice',
    ),
  ];

  Widget buildScreen(FakeFirebaseFirestore fakeDb, {required String currency}) {
    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('bob'),
        eventDetailProvider(eventRef).overrideWith((_) => Stream.value(event)),
        eventExpensesProvider(
          eventRef,
        ).overrideWith((_) => Stream.value(expenses)),
        eventSettlementsProvider(
          eventRef,
        ).overrideWith((_) => Stream.value(const <Settlement>[])),
        groupMembersProvider(groupId).overrideWith((_) => Stream.value([])),
        groupDetailProvider(groupId).overrideWith(
          (_) => Stream.value(
            Group(
              id: groupId,
              name: 'Trip',
              inviteCode: 'ABC123',
              createdBy: 'alice',
              memberIds: const [],
              currency: currency,
              createdAt: DateTime(2026),
            ),
          ),
        ),
        settlementServiceProvider.overrideWithValue(
          SettlementService.withFirestore(fakeDb),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettleUpScreen(groupId: groupId, eventId: eventId),
      ),
    );
  }

  Future<Map<String, dynamic>> recordAndRead(
    WidgetTester tester,
    FakeFirebaseFirestore fakeDb, {
    required String currency,
  }) async {
    await tester.pumpWidget(buildScreen(fakeDb, currency: currency));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();

    final snap = await fakeDb
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('settlements')
        .get();
    expect(snap.docs, hasLength(1));
    return snap.docs.first.data();
  }

  testWidgets('USD group → settlement persists currency USD + amountFils 1000', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();
    final data = await recordAndRead(tester, fakeDb, currency: 'USD');
    expect(data['currency'], 'USD');
    // USD scale = 100 → 10 = 1000 fils. The OMR bug would store 10000.
    expect(data['amountFils'], 1000);
  });

  testWidgets('OMR group → settlement persists currency OMR + amountFils 10000', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();
    final data = await recordAndRead(tester, fakeDb, currency: 'OMR');
    expect(data['currency'], 'OMR');
    expect(data['amountFils'], 10000);
  });
}
