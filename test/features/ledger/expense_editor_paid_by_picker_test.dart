import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #280 — "Paid by" must be changeable directly from its own section, not only
/// via the buried Split-between → Customise sheet. The inline picker writes the
/// single payerParticipantId field (no persisted-shape change).
final _event = Event(
  id: 'event-1',
  name: 'Marrakech',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-layla'],
  participantNames: const {
    'uid-yasmin': 'Yasmin Khan',
    'uid-layla': 'Layla Hassan',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 3, 20),
);

void main() {
  Future<ExpenseEditorPayload?> pickPayerAndSave(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ExpenseEditorPayload? captured;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-yasmin'),
          eventDetailProvider((
            groupId: 'group-1',
            eventId: 'event-1',
          )).overrideWith((ref) => Stream.value(_event)),
          tripCategoriesProvider(
            'event-1',
          ).overrideWith((ref) => Stream.value(const <ExpenseCategory>[])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseEditorBody(
              groupId: 'group-1',
              eventId: 'event-1',
              mode: ExpenseEditorMode.edit,
              currency: 'OMR',
              initial: Expense(
                id: 'expense-1',
                tripId: 'event-1',
                payerParticipantId: 'uid-yasmin',
                amount: Decimal.parse('12.000'),
                scope: ExpenseScope.global,
                createdAt: DateTime(2026, 3, 21),
                createdBy: 'uid-yasmin',
                splitMode: SplitMode.equally,
              ),
              onSubmit: (payload) async => captured = payload,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the dedicated "Paid by" picker — NOT the Split-between sheet.
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    // Pick the other participant as payer.
    await tester.tap(find.text('Layla Hassan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    return captured;
  }

  testWidgets('inline Paid-by picker changes payerParticipantId on save',
      (tester) async {
    final payload = await pickPayerAndSave(tester);

    expect(payload, isNotNull);
    expect(payload!.payerParticipantId, 'uid-layla');
  });
}
