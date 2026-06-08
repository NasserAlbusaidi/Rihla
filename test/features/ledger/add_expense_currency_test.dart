import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/add_expense_screen.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #261 PR-A: AddExpenseScreen must write the OWNING GROUP's currency, not a
/// hardcoded 'OMR'. RED before the fix: the screen ignored group.currency and
/// the service defaulted to OMR (amountFils scaled by 1000, not 100).
void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';

  final event = Event(
    id: eventId,
    name: 'Marrakech',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'uid-yasmin',
    participantIds: const ['uid-yasmin', 'uid-layla'],
    participantNames: const {
      'uid-yasmin': 'Yasmin Khan',
      'uid-layla': 'Layla Hassan',
    },
    modules: const EventModules(),
    startDate: DateTime(2026, 3, 21),
    createdAt: DateTime(2026, 3, 20),
  );

  Future<FakeFirebaseFirestore> pump(
    WidgetTester tester, {
    required String currency,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-yasmin'),
          expenseServiceProvider.overrideWithValue(
            ExpenseService.withFirestore(fakeDb),
          ),
          groupDetailProvider(groupId).overrideWith(
            (ref) => Stream.value(
              Group(
                id: groupId,
                name: 'Trip',
                inviteCode: 'ABC123',
                createdBy: 'uid-yasmin',
                memberIds: const ['uid-yasmin'],
                currency: currency,
                createdAt: DateTime(2026),
              ),
            ),
          ),
          eventDetailProvider((
            groupId: groupId,
            eventId: eventId,
          )).overrideWith((ref) => Stream.value(event)),
          tripCategoriesProvider(
            eventId,
          ).overrideWith((ref) => Stream.value(const <ExpenseCategory>[])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AddExpenseScreen(groupId: groupId, eventId: eventId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fakeDb;
  }

  Future<Map<String, dynamic>> readExpense(FakeFirebaseFirestore db) async {
    final snap = await db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection('expenses')
        .get();
    expect(snap.docs.length, 1, reason: 'exactly one expense written');
    return snap.docs.first.data();
  }

  testWidgets('USD group → amount label shows USD and accepts 2 decimals', (
    tester,
  ) async {
    await pump(tester, currency: 'USD');

    expect(find.text('AMOUNT · USD'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '12.34');
    await tester.pump();
    // 2-decimal currency keeps both fraction digits (OMR would pad to 3dp).
    expect(find.text('12'), findsOneWidget);
    expect(find.text('.34'), findsOneWidget);
  });

  testWidgets('USD group → expense persists currency USD + amountFils 1234', (
    tester,
  ) async {
    final db = await pump(tester, currency: 'USD');

    await tester.enterText(find.byType(TextField).first, '12.34');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final data = await readExpense(db);
    expect(data['currency'], 'USD');
    // USD scale = 100 → 12.34 = 1234 fils. The OMR bug would store 12340.
    expect(data['amountFils'], 1234);
  });

  testWidgets('OMR group → expense persists currency OMR + amountFils 12000', (
    tester,
  ) async {
    final db = await pump(tester, currency: 'OMR');

    await tester.enterText(find.byType(TextField).first, '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final data = await readExpense(db);
    expect(data['currency'], 'OMR');
    // OMR scale = 1000 → 12.000 = 12000 fils.
    expect(data['amountFils'], 12000);
  });
}
