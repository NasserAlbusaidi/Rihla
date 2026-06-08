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

/// #289 — the split-preview tile and the "Paid by" card must distinguish two
/// members both named "Ahmed" (free-typed identical names are the cohort norm).
/// The preview collapses to first-name; the fix must keep the #196 ` (#…)`
/// discriminator alive through that collapse.
final _event = Event(
  id: 'event-1',
  name: 'Muscat weekend',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-omar-9999',
  participantIds: const ['uid-ahmed-aaaa', 'uid-ahmed-bbbb', 'uid-omar-9999'],
  participantNames: const {
    'uid-ahmed-aaaa': 'Ahmed',
    'uid-ahmed-bbbb': 'Ahmed',
    'uid-omar-9999': 'Omar Said',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 30),
);

void main() {
  Future<void> pumpEditor(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-omar-9999'),
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
                payerParticipantId: 'uid-ahmed-aaaa',
                amount: Decimal.parse('12.000'),
                scope: ExpenseScope.global,
                createdAt: DateTime(2026, 5, 30),
                createdBy: 'uid-omar-9999',
                splitMode: SplitMode.equally,
              ),
              onSubmit: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('split preview + paid-by distinguish two members named Ahmed',
      (tester) async {
    await pumpEditor(tester);

    // Both Ahmeds carry their discriminator (paid-by card shows aaaa; preview
    // tiles show both). Bare "Ahmed" — the silent mis-attribution — must be gone.
    expect(find.text('Ahmed (#aaaa)'), findsWidgets);
    expect(find.text('Ahmed (#bbbb)'), findsOneWidget);
    expect(find.text('Ahmed'), findsNothing);
    // Non-colliding member still collapses to a clean first name in the tile.
    expect(find.text('Omar'), findsOneWidget);
  });
}
