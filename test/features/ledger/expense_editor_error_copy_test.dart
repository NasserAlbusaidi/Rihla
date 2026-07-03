import 'package:decimal/decimal.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'package:safar/l10n/generated/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Editor failure snacks must show the friendlyMessageFor translation, never
// the raw exception (which leaks '[cloud_firestore/permission-denied] ...'
// plugin noise to the user — the whole-app scorecard critical).
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
  startDate: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 20),
);

final _expense = Expense(
  id: 'expense-1',
  tripId: 'event-1',
  payerParticipantId: 'uid-yasmin',
  amount: Decimal.parse('12.000'),
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 5, 30),
  createdBy: 'uid-yasmin',
  splitMode: SplitMode.equally,
  splitDistribution: const {},
);

final _rejection = FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
  message: 'Missing or insufficient permissions.',
);

Future<void> pumpEditor(
  WidgetTester tester, {
  required Future<void> Function(ExpenseEditorPayload payload) onSubmit,
  Future<void> Function()? onDelete,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

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
            initial: _expense,
            onSubmit: onSubmit,
            onDelete: onDelete,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final en = AppLocalizationsEn();

  testWidgets('save failure shows the friendly cause, not the raw exception', (
    tester,
  ) async {
    await pumpEditor(tester, onSubmit: (_) async => throw _rejection);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text(en.editorFailedToUpdateExpense(en.errorPermissionDenied)),
      findsOneWidget,
    );
    expect(find.textContaining('cloud_firestore'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'delete failure shows the friendly cause, not the raw exception',
    (tester) async {
      await pumpEditor(
        tester,
        onSubmit: (_) async {},
        onDelete: () async => throw _rejection,
      );

      await tester.scrollUntilVisible(
        find.text(en.editorDeleteThisExpense),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // The card's trash FilledButton opens the confirm dialog; the dialog's
      // TextButton shares the same commonDelete label.
      await tester.tap(find.widgetWithText(FilledButton, en.commonDelete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, en.commonDelete));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(en.editorDeleteExpenseFailed(en.errorPermissionDenied)),
        findsOneWidget,
      );
      expect(find.textContaining('cloud_firestore'), findsNothing);
      await tester.pumpAndSettle();
    },
  );
}
