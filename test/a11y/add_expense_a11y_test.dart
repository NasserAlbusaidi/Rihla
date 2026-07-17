// #1283 — accessibility guideline matchers for AddExpenseScreen.
//
// Arrange section copied from test/features/ledger/add_expense_screen_test.dart
// (`_pumpAddExpenseScreen`/`_event`/`_categories`) — reuse, don't invent new
// fixtures.

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
import 'package:safar/features/ledger/screens/add_expense_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _event = Event(
  id: 'event-1',
  name: 'Marrakech, four ways',
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

final _categories = [
  ExpenseCategory(
    id: 'food',
    tripId: 'event-1',
    name: 'Food',
    icon: 'food',
    color: '#C2693B',
    createdAt: DateTime(2026, 1, 1),
  ),
  ExpenseCategory(
    id: 'transit',
    tripId: 'event-1',
    name: 'Transit',
    icon: 'transport',
    color: '#8C6A2F',
    createdAt: DateTime(2026, 1, 1),
  ),
];

Future<void> _pumpAddExpenseScreen(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue('uid-yasmin'),
        groupDetailProvider('group-1').overrideWith(
          (ref) => Stream.value(
            Group(
              id: 'group-1',
              name: 'Trip',
              inviteCode: 'ABC123',
              createdBy: 'uid-yasmin',
              memberIds: const ['uid-yasmin', 'uid-layla'],
              currency: 'OMR',
              createdAt: DateTime(2026),
            ),
          ),
        ),
        eventDetailProvider((
          groupId: 'group-1',
          eventId: 'event-1',
        )).overrideWith((ref) => Stream.value(_event)),
        tripCategoriesProvider(
          'event-1',
        ).overrideWith((ref) => Stream.value(_categories)),
      ],
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AddExpenseScreen(groupId: 'group-1', eventId: 'event-1'),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  group('AddExpenseScreen accessibility (#1283)', () {
    testWidgets('EN meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAddExpenseScreen(tester);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('AR meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAddExpenseScreen(tester, locale: const Locale('ar'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    // Unlike Home/GroupDetail, AddExpenseScreen's tap targets (amount field,
    // category chips, Split card rows, the full-width "Add" FilledButton) all
    // measure at least 48x48 today — androidTapTargetGuideline passes for
    // real, not vacuously (verified stable across repeated runs).
    testWidgets('EN meets androidTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAddExpenseScreen(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('AR meets androidTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAddExpenseScreen(tester, locale: const Locale('ar'));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('EN meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAddExpenseScreen(tester);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('AR meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAddExpenseScreen(tester, locale: const Locale('ar'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
