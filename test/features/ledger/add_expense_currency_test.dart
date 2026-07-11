import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
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
                memberIds: const ['uid-yasmin', 'uid-layla'],
                currency: currency,
                createdAt: DateTime(2026),
              ),
            ),
          ),
          eventDetailProvider((
            groupId: groupId,
            eventId: eventId,
          )).overrideWith((ref) => Stream.value(event)),
          // #204: category is mandatory at creation, so the picker must offer
          // at least one option (production always serves the 10 defaults, #689).
          tripCategoriesProvider(eventId).overrideWith(
            (ref) => Stream.value([
              ExpenseCategory(
                id: 'food',
                tripId: eventId,
                name: 'Food',
                icon: 'food',
                color: '#C2693B',
                createdAt: DateTime(2026, 1, 1),
              ),
            ]),
          ),
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
    await tester.tap(find.text('Food')); // #204: category is mandatory
    await tester.pump();
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
    await tester.tap(find.text('Food')); // #204: category is mandatory
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final data = await readExpense(db);
    expect(data['currency'], 'OMR');
    // OMR scale = 1000 → 12.000 = 12000 fils.
    expect(data['amountFils'], 12000);
  });

  // #382 PR-6: opens the per-expense currency picker row and taps the option
  // whose display name is [label] (e.g. 'US dollar', 'Japanese yen').
  Future<void> pickCurrency(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(LedgerKeys.expenseCurrencyField));
    await tester.pumpAndSettle();
    // The sheet is GCC-first scrollable; JPY (last) sits below the fold.
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    '#382 PR-6: pick USD in an OMR group → hero flips to USD and the '
    'expense persists currency USD + amountFils 1234',
    (tester) async {
      final db = await pump(tester, currency: 'OMR');

      // Before picking, the hero shows the group default (OMR).
      expect(find.text('AMOUNT · OMR'), findsOneWidget);

      await pickCurrency(tester, 'US dollar');

      // The picked currency drives the amount-hero label.
      expect(find.text('AMOUNT · USD'), findsOneWidget);
      expect(find.text('AMOUNT · OMR'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '12.34');
      await tester.pump();
      await tester.tap(find.text('Food')); // #204: category is mandatory
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final data = await readExpense(db);
      // The CLIENT now creates a divergent-currency expense in an OMR group.
      expect(data['currency'], 'USD');
      // USD scale = 100 → 12.34 = 1234. The OMR-scale bug would store 12340.
      expect(data['amountFils'], 1234);
    },
  );

  testWidgets(
    '#382 PR-6: pick JPY → the 0dp scale clamps the input (100.5 → 100) and '
    'persists amountFils 100 (effectiveCurrency drives _sanitizeAmount)',
    (tester) async {
      final db = await pump(tester, currency: 'OMR');

      await pickCurrency(tester, 'Japanese yen');
      expect(find.text('AMOUNT · JPY'), findsOneWidget);

      // Drive the amount field's onChanged DIRECTLY with an unclamped '100.5',
      // bypassing the input formatter — this isolates _sanitizeAmount (:628).
      // If it read the stale OMR 3dp the .5 would survive, the hero would render
      // '100.5', and toBigInt() would truncate it at the JPY=1 boundary.
      final amountField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      amountField.onChanged!('100.5');
      await tester.pump();

      // JPY = 0 decimals → _sanitizeAmount clamps the fraction away.
      expect(find.text('100'), findsOneWidget);
      expect(find.textContaining('.5'), findsNothing);

      await tester.tap(find.text('Food')); // #204: category is mandatory
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final data = await readExpense(db);
      expect(data['currency'], 'JPY');
      // JPY scale = 1 → 100 = 100.
      expect(data['amountFils'], 100);
    },
  );

  testWidgets(
    '#382 PR-6: pick USD → the split preview renders per-person amounts under '
    'USD (exact-split entry/preview scales by the picked currency)',
    (tester) async {
      await pump(tester, currency: 'OMR');

      await pickCurrency(tester, 'US dollar');

      // Global scope across the 2 event participants → each owes 10/2 = 5.
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.pumpAndSettle();

      // The on-screen split preview (:582) must format per-person amounts in
      // the picked currency. USD = 2dp ('USD 5.00'); the stale OMR path would
      // render 'OMR 5.000'.
      expect(find.text('USD 5.00'), findsWidgets);
      expect(find.textContaining('OMR'), findsNothing);

      // #485: the weights sheet (opened from the card's "Shares" mode segment)
      // also inherits the picked currency in its header.
      final shares = find.text('Shares');
      await tester.ensureVisible(shares);
      await tester.tap(shares);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('USD', findRichText: true),
        findsWidgets,
      );
    },
  );

  // #382 PR-6 (Task 5 — parent wiring): the smart default is computed in the
  // parent from the event's expense history. Pumps the add screen with
  // [eventExpensesProvider] overridden so the body seeds the picker from
  // last-used-in-event instead of the group default.
  Expense seedExpense({
    required String id,
    required String currency,
    required DateTime createdAt,
    bool isDeleted = false,
  }) {
    return Expense(
      id: id,
      tripId: eventId,
      payerParticipantId: 'uid-yasmin',
      amount: Decimal.fromInt(10),
      scope: ExpenseScope.global,
      createdAt: createdAt,
      currency: currency,
      isDeleted: isDeleted,
    );
  }

  Future<void> pumpWithHistory(
    WidgetTester tester, {
    required String groupCurrency,
    required List<Expense> eventExpenses,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fakeDb = FakeFirebaseFirestore();
    const EventRef eventRef = (groupId: groupId, eventId: eventId);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-yasmin'),
          expenseServiceProvider.overrideWithValue(
            ExpenseService.withFirestore(fakeDb),
          ),
          eventExpensesProvider(eventRef).overrideWith(
            (ref) => Stream.value(eventExpenses),
          ),
          groupDetailProvider(groupId).overrideWith(
            (ref) => Stream.value(
              Group(
                id: groupId,
                name: 'Trip',
                inviteCode: 'ABC123',
                createdBy: 'uid-yasmin',
                memberIds: const ['uid-yasmin', 'uid-layla'],
                currency: groupCurrency,
                createdAt: DateTime(2026),
              ),
            ),
          ),
          eventDetailProvider((
            groupId: groupId,
            eventId: eventId,
          )).overrideWith((ref) => Stream.value(event)),
          // #204: category is mandatory at creation, so the picker must offer
          // at least one option (production always serves the 10 defaults, #689).
          tripCategoriesProvider(eventId).overrideWith(
            (ref) => Stream.value([
              ExpenseCategory(
                id: 'food',
                tripId: eventId,
                name: 'Food',
                icon: 'food',
                color: '#C2693B',
                createdAt: DateTime(2026, 1, 1),
              ),
            ]),
          ),
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
  }

  testWidgets(
    '#382 PR-6: OMR group whose event already has a USD expense → add-expense '
    'defaults the hero to USD (last-used-in-event)',
    (tester) async {
      await pumpWithHistory(
        tester,
        groupCurrency: 'OMR',
        eventExpenses: [
          seedExpense(
            id: 'e-usd',
            currency: 'USD',
            createdAt: DateTime(2026, 3, 22),
          ),
        ],
      );

      // The smart default = last-used (USD), NOT the group default (OMR).
      expect(find.text('AMOUNT · USD'), findsOneWidget);
      expect(find.text('AMOUNT · OMR'), findsNothing);
    },
  );

  testWidgets(
    '#382 PR-6: event [OMR@t1, OMR@t2, USD@t3] → default USD (most-recent), '
    'group default ignored',
    (tester) async {
      await pumpWithHistory(
        tester,
        groupCurrency: 'OMR',
        eventExpenses: [
          seedExpense(
            id: 'e1',
            currency: 'OMR',
            createdAt: DateTime(2026, 3, 20),
          ),
          seedExpense(
            id: 'e2',
            currency: 'OMR',
            createdAt: DateTime(2026, 3, 21),
          ),
          seedExpense(
            id: 'e3',
            currency: 'USD',
            createdAt: DateTime(2026, 3, 22),
          ),
        ],
      );

      // Recency wins for the default: the most-recent expense is USD.
      expect(find.text('AMOUNT · USD'), findsOneWidget);
    },
  );

  // #382 PR-6 (Task 6 — soft fat-finger warning): when the picked currency
  // diverges from the event's DOMINANT (most-frequent) currency, an inline
  // non-blocking warning card naming both currencies appears below the amount
  // hero. Reactive: picking the dominant currency makes it vanish. Never in
  // edit mode (covered in edit_expense_currency_test.dart).
  testWidgets(
    '#382 PR-6: event [OMR×2], pick USD → soft warning naming USD+OMR; '
    'pick OMR back → warning gone',
    (tester) async {
      // Two OMR expenses → dominant = OMR. The two share a createdAt so the
      // most-recent (smart default) is still OMR, isolating the warning to the
      // user's manual divergent pick rather than a USD default.
      await pumpWithHistory(
        tester,
        groupCurrency: 'OMR',
        eventExpenses: [
          seedExpense(
            id: 'e1',
            currency: 'OMR',
            createdAt: DateTime(2026, 3, 20),
          ),
          seedExpense(
            id: 'e2',
            currency: 'OMR',
            createdAt: DateTime(2026, 3, 21),
          ),
        ],
      );

      // Default = OMR (= dominant) → no warning yet.
      expect(find.text('AMOUNT · OMR'), findsOneWidget);
      expect(find.byKey(LedgerKeys.expenseCurrencyWarning), findsNothing);

      // Diverge: pick USD while the event mostly uses OMR.
      await pickCurrency(tester, 'US dollar');
      expect(find.text('AMOUNT · USD'), findsOneWidget);

      final warning = find.byKey(LedgerKeys.expenseCurrencyWarning);
      expect(warning, findsOneWidget);
      // The card names both the selected (USD) and the dominant (OMR) currency.
      expect(
        find.descendant(
          of: warning,
          matching: find.textContaining('USD'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: warning,
          matching: find.textContaining('OMR'),
        ),
        findsWidgets,
      );

      // Reactive: picking the dominant currency back hides the warning.
      await pickCurrency(tester, 'Omani rial');
      expect(find.byKey(LedgerKeys.expenseCurrencyWarning), findsNothing);
    },
  );
}
