import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/widgets/expense_editor/amount_hero.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #1080 — invalid amount at submit must produce a PERSISTENT field-associated
// error (not just a transient snackbar), move focus to the amount field, and
// announce the error to assistive tech. The old tests asserted the message at
// t=0 (while the snackbar was still alive) and never advanced past its
// lifetime — the exact gap the audit named.
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

Future<void> _pumpAddEditor(WidgetTester tester) async {
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
            mode: ExpenseEditorMode.add,
            currency: 'OMR',
            onSubmit: (_) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inlineAmountError() => find.descendant(
  of: find.byType(AmountHero),
  matching: find.text('Amount must be greater than zero'),
);

Finder _amountField() => find.descendant(
  of: find.byType(AmountHero),
  matching: find.byType(TextField),
);

void main() {
  testWidgets(
    '#1080: zero-amount submit shows a field-associated error that outlives '
    'the snackbar lifetime',
    (tester) async {
      await _pumpAddEditor(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(_inlineAmountError(), findsOneWidget);

      // Advance PAST the default 4s snackbar lifetime + exit animation.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(_inlineAmountError(), findsOneWidget);
    },
  );

  testWidgets('#1080: invalid submit moves focus to the amount field', (
    tester,
  ) async {
    await _pumpAddEditor(tester);

    expect(
      tester.widget<TextField>(_amountField()).focusNode!.hasFocus,
      isFalse,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();

    expect(
      tester.widget<TextField>(_amountField()).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('#1080: invalid submit announces the error to assistive tech', (
    tester,
  ) async {
    final announcements = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        announcements.add(message);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );

    await _pumpAddEditor(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();

    final announce = announcements
        .whereType<Map<Object?, Object?>>()
        .where((m) => m['type'] == 'announce')
        .toList();
    expect(announce, isNotEmpty);
    final data = announce.first['data']! as Map<Object?, Object?>;
    expect(data['message'], 'Amount must be greater than zero');
  });

  testWidgets('#1080: editing the amount clears the inline error', (
    tester,
  ) async {
    await _pumpAddEditor(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    expect(_inlineAmountError(), findsOneWidget);

    await tester.enterText(_amountField(), '5');
    await tester.pump();

    expect(_inlineAmountError(), findsNothing);
  });
}
