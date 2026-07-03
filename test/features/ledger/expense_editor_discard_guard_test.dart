import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #818 Wave 3.2: discard guard on the shared add/edit expense editor
// (expense_editor_body.dart). Spec: docs/plans/2026-07-03-add-expense-discard-guard.md

const String _groupId = 'group-1';
const String _eventId = 'event-1';
const String _uid = 'uid-yasmin';

Future<void> _noopSubmit(ExpenseEditorPayload payload) async {}

final Event _event = Event(
  id: _eventId,
  name: 'Marrakech, four ways',
  type: EventType.trip,
  groupId: _groupId,
  createdBy: _uid,
  participantIds: const [_uid, 'uid-layla'],
  participantNames: const {_uid: 'Yasmin Khan', 'uid-layla': 'Layla Hassan'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 20),
);

final Expense _initialExpense = Expense(
  id: 'expense-1',
  tripId: _eventId,
  payerParticipantId: _uid,
  amount: Decimal.parse('10'),
  description: 'Original note',
  scope: ExpenseScope.global,
  categoryId: 'food',
  splitMode: SplitMode.equally,
  createdAt: DateTime(2026, 5, 1),
  createdBy: _uid,
);

List<Override> _baseOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  currentUserIdProvider.overrideWithValue(_uid),
  eventDetailProvider((
    groupId: _groupId,
    eventId: _eventId,
  )).overrideWith((ref) => Stream.value(_event)),
  tripCategoriesProvider(
    _eventId,
  ).overrideWith((ref) => Stream.value(const [])),
];

/// Two-entry stack (`/home` + the pushed editor route) so a real
/// `context.pop()`/system-back can be exercised, following
/// `group_detail_navigation_test.dart`'s pattern. Bounded pumps only — no
/// `pumpAndSettle` (the editor's `OfflineBanner` watches `connectivityProvider`;
/// the repo's documented trap is a live `ConnectivityNotifier` subscription
/// that never settles).
Future<GoRouter> _pumpEditorRoute(
  WidgetTester tester, {
  required Widget editor,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(path: '/editor', builder: (_, _) => editor),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _baseOverrides(prefs),
      child: MaterialApp.router(
        locale: const Locale('en'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();

  unawaited(router.push('/editor'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  return router;
}

/// Widget-level harness (no router) for test 5 — rebuilds the SAME element
/// with a new `currency` prop to trigger `didUpdateWidget`, simulating the
/// async smart-default re-seed (#382 PR-6).
Widget _wrapDirect(SharedPreferences prefs, Widget child) => ProviderScope(
  overrides: _baseOverrides(prefs),
  child: MaterialApp(
    locale: const Locale('en'),
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  group('Expense editor discard guard (#818 Wave 3.2)', () {
    testWidgets('pristine add: canPop true; X pops without dialog', (
      tester,
    ) async {
      await _pumpEditorRoute(
        tester,
        editor: const ExpenseEditorBody(
          groupId: _groupId,
          eventId: _eventId,
          mode: ExpenseEditorMode.add,
          currency: 'OMR',
          onSubmit: _noopSubmit,
        ),
      );

      final popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );
      expect(popScope.canPop, isTrue);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Discard this expense?'), findsNothing);
    });

    testWidgets(
      'dirty add: X shows discard dialog; Keep editing stays; Discard pops',
      (tester) async {
        await _pumpEditorRoute(
          tester,
          editor: const ExpenseEditorBody(
            groupId: _groupId,
            eventId: _eventId,
            mode: ExpenseEditorMode.add,
            currency: 'OMR',
            onSubmit: _noopSubmit,
          ),
        );

        await tester.enterText(find.byType(TextField).first, '5');
        await tester.pump();

        final dirtyPopScope = tester.widget<PopScope>(
          find.byWidgetPredicate((widget) => widget is PopScope),
        );
        expect(dirtyPopScope.canPop, isFalse);

        await tester.tap(find.byTooltip('Close'));
        await tester.pump();

        expect(find.text('Discard this expense?'), findsOneWidget);

        await tester.tap(find.text('Keep editing'));
        await tester.pump();

        expect(find.text('Discard this expense?'), findsNothing);
        expect(find.byType(TextField), findsWidgets);

        await tester.tap(find.byTooltip('Close'));
        await tester.pump();
        await tester.tap(find.text('Discard'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Home'), findsOneWidget);
      },
    );

    testWidgets(
      'note-only dirty: canPop false; simulated system back shows dialog '
      '(the listener regression)',
      (tester) async {
        await _pumpEditorRoute(
          tester,
          editor: const ExpenseEditorBody(
            groupId: _groupId,
            eventId: _eventId,
            mode: ExpenseEditorMode.add,
            currency: 'OMR',
            onSubmit: _noopSubmit,
          ),
        );

        await tester.enterText(find.byType(TextField).last, 'Coffee run');
        await tester.pump();

        final popScope = tester.widget<PopScope>(
          find.byWidgetPredicate((widget) => widget is PopScope),
        );
        expect(popScope.canPop, isFalse);

        popScope.onPopInvokedWithResult!(false, null);
        await tester.pump();

        expect(find.text('Discard this expense?'), findsOneWidget);
      },
    );

    testWidgets('pristine edit: canPop true; X pops without dialog', (
      tester,
    ) async {
      await _pumpEditorRoute(
        tester,
        editor: ExpenseEditorBody(
          groupId: _groupId,
          eventId: _eventId,
          mode: ExpenseEditorMode.edit,
          currency: 'OMR',
          initial: _initialExpense,
          onSubmit: _noopSubmit,
        ),
      );

      final popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );
      expect(popScope.canPop, isTrue);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('late add-mode currency re-seed does not dirty the form', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      Widget build(String currency) => _wrapDirect(
        prefs,
        ExpenseEditorBody(
          groupId: _groupId,
          eventId: _eventId,
          mode: ExpenseEditorMode.add,
          currency: currency,
          onSubmit: _noopSubmit,
        ),
      );

      await tester.pumpWidget(build('OMR'));
      await tester.pump();

      // Simulates the #382 PR-6 async smart-default arriving after first
      // frame — didUpdateWidget must adopt it without dirtying a pristine form.
      await tester.pumpWidget(build('USD'));
      await tester.pump();

      final popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );
      expect(popScope.canPop, isTrue);
    });

    testWidgets('edit-dirty: system back shows dialog; Discard pops', (
      tester,
    ) async {
      await _pumpEditorRoute(
        tester,
        editor: ExpenseEditorBody(
          groupId: _groupId,
          eventId: _eventId,
          mode: ExpenseEditorMode.edit,
          currency: 'OMR',
          initial: _initialExpense,
          onSubmit: _noopSubmit,
        ),
      );

      await tester.enterText(find.byType(TextField).last, 'Updated note');
      await tester.pump();

      final popScope = tester.widget<PopScope>(
        find.byWidgetPredicate((widget) => widget is PopScope),
      );
      expect(popScope.canPop, isFalse);

      popScope.onPopInvokedWithResult!(false, null);
      await tester.pump();

      expect(find.text('Discard your changes?'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Home'), findsOneWidget);
    });
  });
}
