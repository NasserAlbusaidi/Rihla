import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

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

  final expenses = [
    Expense(
      id: 'expense-1',
      tripId: eventId,
      payerParticipantId: 'alice',
      amount: Decimal.parse('20.000'),
      description: 'Dinner',
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 5, 16),
      createdBy: 'alice',
    ),
  ];

  Widget buildScreen(FakeFirebaseFirestore fakeDb, {Locale? locale}) {
    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('bob'),
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(event)),
        eventExpensesProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(expenses)),
        eventSettlementsProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(const <Settlement>[])),
        settlementServiceProvider.overrideWithValue(
          SettlementService.withFirestore(fakeDb),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettleUpScreen(groupId: groupId, eventId: eventId),
      ),
    );
  }

  testWidgets('records settlement with resolved participant names', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpRecordSheetTitle), findsOneWidget);

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
    expect(snap.docs.first.data()['payerParticipantId'], equals('bob'));
    expect(snap.docs.first.data()['recipientParticipantId'], equals('alice'));
    expect(snap.docs.first.data()['payerName'], equals('Bob'));
    expect(snap.docs.first.data()['recipientName'], equals('Alice'));
  });

  testWidgets('back arrow is mirrored under Arabic RTL (#126)', (tester) async {
    final fakeDb = FakeFirebaseFirestore();

    await tester.pumpWidget(buildScreen(fakeDb, locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Iconsax.arrow_left_2), findsOneWidget);
    final mirrored = tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.byIcon(Iconsax.arrow_left_2),
            matching: find.byType(Transform),
          ),
        )
        .any((t) => t.transform.getRow(0).x == -1.0);
    expect(mirrored, isTrue);
  });
}
